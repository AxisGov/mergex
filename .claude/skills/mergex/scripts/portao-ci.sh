#!/usr/bin/env bash
# portao-ci — a verificação do portão no CI, sobre o SHA da cabeça do PR.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seção 13, item 8 (DM-184). Repete, no CI, a decisão do `pre-push`: não tem
# regra própria. Decide como se a ref refs/heads/<branch> fosse empurrada com o
# SHA local <sha> e o SHA remoto nulo, chamando pr_decide_ref (portao-regras.sh):
# a mesma validade (validade-do-portao.sh --rev) e o mesmo modo de `portao: null`
# (pr-so-com-portao em .expx/hooks.json). É a barreira contra contorno
# deliberado (`--no-verify`) quando o produto a ativa com proteção de merge;
# esta branch entrega o executável e o template, nunca ativa CI.
#
# Uso (a partir da raiz do checkout, com a história completa):
#   portao-ci.sh --verificar --sha <sha40|sha64> --branch <nome> --base <sha40|sha64>
#
# Aplicabilidade. No clone de um CI (actions/checkout com ref: <sha>) não existe
# refs/heads/* local nem SHA remoto anterior. O análogo da "árvore do SHA remoto
# anterior" é a história do PR: se o SHA enviado não declara a branch, o CI
# consulta os ENTREGA.md do merge-base(--base, --sha) e dos commits do PR que
# tocam docs/entregas, e usa o mais recente que declara `branch: <nome>` como
# SHA remoto anterior de pr_decide_ref. Assim um commit que apaga o ENTREGA.md é
# barrado, como no pre-push. Custo: um número constante de processos Git mais os
# poucos por commit do PR que toca docs/entregas; nunca proporcional às
# entregas do repositório. --base que não é objeto no clone, ou sem
# merge-base com --sha, é historia_incompleta (falha fechada).
#
# Saída: decisao=<passa|avisa|barra>, motivo= e entrega= em stdout. O
# diagnóstico (avisa e barra) vai a stderr; historia_incompleta (completar a
# história, clone raso) e erro_ambiente (falha do ambiente, inclusive o
# validador ausente) têm textos distintos.
#
# Códigos: 0 passa ou avisa; 1 barra; 64 uso. Nenhuma opção de força.
#
# RISCOS RESIDUAIS (documentados, não resolvidos aqui):
# - Aplicabilidade pelo `branch:` do ENTREGA.md, como nos três consumidores da
#   barreira (spec 13.7). Um PR de branch com outro nome (o ENTREGA declara
#   feature/ft-rec e o PR vem de feature/ft-rec-2) não é aplicável: um SHA
#   vencido passa no CI e no pre-push. Mudar a regra é decisão de desenho
#   pendente.
# - Com `on: pull_request`, o autor do PR controla a cabeça do PR: o próprio
#   portao-ci.sh e o workflow, e o .expx/hooks.json (o modo de `portao: null`).
#   O check confia neles. Proteja .expx/**, .claude/** e .github/** com
#   CODEOWNERS e revisão obrigatória no produto.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uso() {
  [ -z "${1:-}" ] || printf 'portao-ci: %s\n' "$1" >&2
  printf '%s\n' 'uso: portao-ci.sh --verificar --sha <sha completo> --branch <nome> --base <sha completo>' >&2
  exit 64
}

[ "$#" -eq 7 ] || uso 'esperava --verificar --sha <sha> --branch <nome> --base <sha>'
[ "$1" = --verificar ] || uso "opção desconhecida: $1"
shift
SHA=""; BRANCH=""; BASE=""; TEM_B=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sha) [ -z "$SHA" ] || uso '--sha repetido'; SHA="$2" ;;
    --branch) [ "$TEM_B" = 0 ] || uso '--branch repetido'; TEM_B=1; BRANCH="$2" ;;
    --base) [ -z "$BASE" ] || uso '--base repetido'; BASE="$2" ;;
    *) uso "opção desconhecida: $1" ;;
  esac
  shift 2
done
for v in "$SHA" "$BASE"; do
  printf '%s\n' "$v" | grep -Eqx '[0-9a-f]{40}|[0-9a-f]{64}' || uso '--sha e --base precisam ser SHAs completos em minúsculas (40 hex, ou 64)'
done
[ -n "$BRANCH" ] || uso '--branch vazio'
case "$BRANCH" in refs/*) uso '--branch é o nome da branch, sem o prefixo refs/' ;; esac
{ git check-ref-format --branch "$BRANCH" && git check-ref-format "refs/heads/$BRANCH"; } >/dev/null 2>&1 \
  || uso "--branch não é um nome de branch válido: $BRANCH" # guarda:CIBRANCH

diag() { printf 'mergex ci: %s\n' "$1" >&2; }
AMBIENTE='erro de ambiente (erro_ambiente): a validade do portão não pôde ser avaliada'
NULO=0000000000000000000000000000000000000000

# shellcheck source=portao-regras.sh
if [ ! -r "$AQUI/portao-regras.sh" ] || ! . "$AQUI/portao-regras.sh"; then
  diag "$AMBIENTE: regras indisponíveis em $AQUI (${PR_ERRO:-portao-regras.sh ausente}); PR reprovado"
  exit 1
fi
set +e

arvore_ambiente_git
export GIT_OPTIONAL_LOCKS=0

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { diag "$AMBIENTE: fora de um repositório Git com árvore de trabalho; PR reprovado"; exit 1; }

REF="refs/heads/$BRANCH"
TMP="$(mktemp "${TMPDIR:-/tmp}/mergex-portao-ci.XXXXXX")" \
  || { diag "$AMBIENTE: não foi possível criar arquivo temporário; PR reprovado"; exit 1; }
trap 'rm -f "$TMP" "$TMP.revs" "$TMP.um"' EXIT
trap 'exit 1' HUP INT TERM

# final — imprime a decisão de $TMP, o diagnóstico e sai com o código
final() {
  local decisao
  cat "$TMP"
  decisao="$(sed -n 's/^decisao=//p' "$TMP")"
  case "$decisao" in
    passa) exit 0 ;;
    avisa) diag "$REF: $PR_DIAG"; exit 0 ;;
    *) diag "$REF: ${PR_DIAG:-$AMBIENTE: decisão indeterminada}"; exit 1 ;; # guarda:CIBARRA
  esac
}

# a base precisa existir no clone: sem ela a história do PR não se lê
if ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  _pr_sai barra historia_incompleta - "$(_pr_diag_invalido historia_incompleta) [a base $BASE do PR não é objeto neste clone]" > "$TMP"
  final
fi

: > "$TMP"
pr_decide_ref "$RAIZ" "$REF" "$SHA" "$REF" "$NULO" > "$TMP" # guarda:CISHA

# SHA sem ENTREGA.md que declare a branch: a história do PR decide a aplicabilidade
if [ "$(sed -n 's/^motivo=//p' "$TMP")" = ref_nao_aplicavel ]; then
  MB="$(git merge-base "$BASE" "$SHA" 2>/dev/null)"
  # --full-history: sem simplificação, um merge cuja árvore descarta o docs/entregas
  # do PR continua listando os commits que o tocaram
  if [ -n "$MB" ]; then
    { git rev-list --full-history "$MB..$SHA" -- docs/entregas 2>/dev/null; printf '%s\n' "$MB"; } > "$TMP.revs" # guarda:CIFULL
  elif [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
    # branch órfã (sem ancestral comum com a base) num clone completo: a história
    # do PR é a do SHA inteiro
    git rev-list --full-history "$SHA" -- docs/entregas > "$TMP.revs" 2>/dev/null
  else
    _pr_sai barra historia_incompleta - "$(_pr_diag_invalido historia_incompleta) [sem merge-base entre a base $BASE e $SHA num clone raso ou ilegível]" > "$TMP"
    final
  fi
  ANTERIOR=""
  PR_FALTA=0; PR_CTRL=0
  while read -r rev; do
    [ -n "$rev" ] || continue
    : > "$TMP.um"
    if ! _pr_entregas_em "$RAIZ" "$rev" "$BRANCH" "$TMP.um"; then
      if [ "$PR_FALTA" = 1 ]; then
        _pr_sai barra historia_incompleta - "$(_pr_diag_invalido historia_incompleta) [$PR_ERRO]" > "$TMP"
      else
        _pr_sai barra entrega_indeterminada - "$(_pr_diag_invalido entrega_indeterminada): $PR_ERRO" > "$TMP"
      fi
      final
    fi
    if [ -s "$TMP.um" ]; then ANTERIOR="$rev"; break; fi
  done < "$TMP.revs"
  if [ -n "$ANTERIOR" ]; then
    : > "$TMP"
    pr_decide_ref "$RAIZ" "$REF" "$SHA" "$REF" "$ANTERIOR" > "$TMP" # guarda:CIHIST
  fi
fi
final
