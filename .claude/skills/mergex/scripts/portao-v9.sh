#!/usr/bin/env bash
# portao-v9 — a V9 do portão de prontidão (E2), executável: arquivo alterado
# fora da lista declarada no plano, sobre a base validada por SHA.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seção 10; references/02-prontidao.md, V9.
#
# Uso:
#   portao-v9.sh --verificar --entrega docs/entregas/<id>/ENTREGA.md \
#     --origem <sprintx|runx> --trabalho <id>
#
# Só leitura: não grava no repositório, não adquire a trava C5, não exige
# stage vazio; os temporários (fora do repositório) saem em toda saída.
#
# 1. Base B, sempre um SHA (nunca o nome de uma ref, salvo no legado):
#    - com reconciliação (a cadeia RECONCILIACAO-BASE-NNN.md que
#      `reconciliacao-base.sh --verificar` aprova): o b1_sha da última, lido do
#      artefato que a verificação validou (o mesmo conteúdo antes e depois
#      dela) — origem_base=reconciliacao;
#    - sem reconciliação: o base_validada_sha do ENTREGA.md de HEAD (a versão
#      commitada; o do disco nunca alimenta a base: divergência vira uma linha
#      `aviso`) — origem_base = a origem_base de HEAD (registrada_e0 sem ela);
#    - entrega legada (HEAD:ENTREGA.md sem a chave): `git merge-base --all HEAD
#      <branch_base>` com exatamente um resultado — origem_base=
#      inferida_leitura, nunca gravada. Mais de um, nenhum ou branch_base
#      inexistente: v9_sem_prova.
# 2. Diff: `git diff --name-only --no-renames B...HEAD`, caminho exato (sem
#    quoting).
# 3. Aceito, nesta ordem: a união de arquivos.cria + arquivos.altera de todas
#    as tasks do plano da árvore de HEAD (o plano do disco não conta); as
#    isenções de método (a pasta do trabalho resolvida em HEAD,
#    docs/entregas/<id>/ e, só na SprintX, docs/sprintx/estimativas/HISTORICO.md);
#    os caminhos `coberto` de `reconciliacao-base.sh --verificar`, só com
#    `ok=true` (ok=false é v9_sem_prova).
#
# Saída (stdout):
#   base=<sha40>
#   origem_base=<registrada_e0|inferida_legado|reconciliacao|inferida_leitura>
#   aviso<TAB><texto>                  (zero ou mais)
#   resultado=<ok|v9>
#   fora_do_plano<TAB><caminho>        (um por desvio, em ordem de byte)
# ou, sem prova:
#   resultado=v9_sem_prova
#   motivo<TAB><texto>                 (um ou mais; com ok=false, seguido das
#                                       linhas `motivo` da verificação)
# Códigos: 0 ok; 1 v9; 3 v9_sem_prova; 64 uso. Nenhuma opção de força.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOGO_SH="$AQUI/catalogo-de-metodo.sh"
OWNERSHIP_SH="$AQUI/ownership-da-task.sh"
ARTEFATO_SH="$AQUI/reconciliacao-artefato.sh"
RB_SH="$AQUI/reconciliacao-base.sh"

# Caminho exatamente como no Git e objetos só do Git (como em reconciliacao-base.sh).
unset GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS GIT_NOGLOB_PATHSPECS
export GIT_LITERAL_PATHSPECS=1
export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=advice.graftFileDeprecated GIT_CONFIG_VALUE_1=false \
  GIT_CONFIG_KEY_2=core.commitGraph GIT_CONFIG_VALUE_2=false
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null
# nem o refresh oportunista do índice
export GIT_OPTIONAL_LOCKS=0
g() { git -c core.quotepath=false "$@"; }

NL='
'
TAB='	'

uso() {
  [ -z "${1:-}" ] || printf 'portao-v9: %s\n' "$1" >&2
  printf '%s\n' 'uso: portao-v9.sh --verificar --entrega docs/entregas/<id>/ENTREGA.md --origem <sprintx|runx> --trabalho <id>' >&2
  exit 64
}

TMP_DIR=""
encerrar() {
  local rc="$1"
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  exit "$rc"
}
trap 'encerrar $?' EXIT
trap 'exit 3' HUP INT TERM

# sem_prova <motivo> [arquivo com linhas extras] — v9_sem_prova, rc 3
sem_prova() {
  printf 'resultado=v9_sem_prova\n'
  printf 'motivo\t%s\n' "$(printf '%s' "$1" | tr '\t\n\r' '   ')"
  [ -z "${2:-}" ] || [ ! -f "$2" ] || cat "$2"
  exit 3
}

MODO=""; ENTREGA=""; ORIGEM=""; TRABALHO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --verificar) [ -z "$MODO" ] || uso; MODO=verificar; shift ;;
    --entrega) [ "$#" -ge 2 ] && [ -z "$ENTREGA" ] || uso; ENTREGA="$2"; shift 2 ;;
    --origem) [ "$#" -ge 2 ] && [ -z "$ORIGEM" ] || uso; ORIGEM="$2"; shift 2 ;;
    --trabalho) [ "$#" -ge 2 ] && [ -z "$TRABALHO" ] || uso; TRABALHO="$2"; shift 2 ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done
[ "$MODO" = verificar ] || uso 'falta --verificar'
case "$ORIGEM" in sprintx|runx) ;; *) uso "origem inválida: ${ORIGEM:-ausente}" ;; esac
case "$TRABALHO" in
  ''|*[!A-Za-z0-9._-]*|.*|sprintx|manutencao|entregas|eventos|relatorios|legado|stack|projeto)
    uso "trabalho inválido: ${TRABALHO:-ausente}" ;;
esac
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
[ "$ENTREGA" = "docs/entregas/$TRABALHO/ENTREGA.md" ] || uso "--entrega deve ser docs/entregas/$TRABALHO/ENTREGA.md"

for dependencia in "$CATALOGO_SH" "$OWNERSHIP_SH" "$ARTEFATO_SH" "$RB_SH"; do
  [ -r "$dependencia" ] || sem_prova "dependência indisponível: $dependencia"
done
# shellcheck source=catalogo-de-metodo.sh
. "$CATALOGO_SH"
# shellcheck source=reconciliacao-artefato.sh
. "$ARTEFATO_SH"
set +e

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-portao-v9.XXXXXX")" || { TMP_DIR=""; sem_prova 'não foi possível criar diretório temporário'; }
RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" || sem_prova 'fora de um repositório Git'
cd "$RAIZ" || sem_prova "raiz inacessível: $RAIZ"
HEAD_SHA="$(g rev-parse --verify -q 'HEAD^{commit}')" || sem_prova 'HEAD não é um commit'

# ---------------------------------------------------------------------------
# O ENTREGA.md de HEAD (a versão commitada): contexto e base.
# ---------------------------------------------------------------------------
modo_em() { g ls-tree -z "$1" -- "$2" 2>/dev/null | tr '\0' '\n' | sed -n '1s/ .*//p'; }

ENTREGA_H="$TMP_DIR/entrega-head.md"
case "$(modo_em "$HEAD_SHA" "$ENTREGA")" in
  100644|100755) g cat-file blob "$HEAD_SHA:$ENTREGA" > "$ENTREGA_H" 2>/dev/null || sem_prova "$ENTREGA ilegível em HEAD" ;;
  '') sem_prova "$ENTREGA ausente em HEAD (o E2 avalia o ENTREGA.md commitado)" ;;
  *) sem_prova "$ENTREGA não é arquivo regular em HEAD" ;;
esac
[ "$(catalogo_fm "$ENTREGA_H" kind)" = entrega ] || sem_prova "$ENTREGA de HEAD não declara kind: entrega"
[ "$(catalogo_fm "$ENTREGA_H" trabalho_id)" = "$TRABALHO" ] || sem_prova 'trabalho explícito diverge de ENTREGA.trabalho_id em HEAD'
[ "$(catalogo_fm "$ENTREGA_H" expx_tool)" = "$ORIGEM" ] || sem_prova 'origem explícita diverge de ENTREGA.expx_tool em HEAD'

# chave_qualquer <arquivo> <chave> — a chave de topo aparece no frontmatter em
# qualquer forma (entre aspas, espaço antes dos dois-pontos): presença que não
# se lê com segurança nunca vira ausência (legado).
chave_qualquer() {
  awk -v c="$2" '
    NR == 1 { next }
    /^---[ \t]*\r?$/ { exit }
    {
      l = $0; sub(/\r$/, "", l); q = ""
      if (l ~ /^["\047]/) { q = substr(l, 1, 1); l = substr(l, 2) }
      if (index(l, c) != 1) next
      r = substr(l, length(c) + 1)
      if (q != "" && substr(r, 1, 1) == q) r = substr(r, 2)
      if (r ~ /^[ \t]*:/) { achou = 1; exit }
    }
    END { exit !achou }
  ' "$1"
}

# ---------------------------------------------------------------------------
# A cadeia de reconciliação: `reconciliacao-base.sh --verificar`, com os
# artefatos do disco fotografados antes e conferidos depois (a base sai do
# artefato que a verificação validou).
# ---------------------------------------------------------------------------
DIR_E="docs/entregas/$TRABALHO"
mkdir -p "$TMP_DIR/antes" || sem_prova 'temporário inacessível'
foto() { # <destino> — `nome<TAB>sha256` de cada RECONCILIACAO-BASE-* do disco
  local arq
  : > "$1"
  for arq in "$DIR_E"/RECONCILIACAO-BASE-*; do
    [ -e "$arq" ] || [ -L "$arq" ] || continue
    printf '%s\t%s\n' "${arq##*/}" "$(rb_sha256 < "$arq" 2>/dev/null)" >> "$1"
  done
}
foto "$TMP_DIR/foto-antes"
for arq in "$DIR_E"/RECONCILIACAO-BASE-[0-9][0-9][0-9].md; do
  [ -f "$arq" ] || continue
  cp "$arq" "$TMP_DIR/antes/${arq##*/}" 2>/dev/null || sem_prova "artefato ilegível: ${arq##*/}"
done

bash "$RB_SH" --verificar --entrega "$ENTREGA" --origem "$ORIGEM" --trabalho "$TRABALHO" > "$TMP_DIR/verificar" 2> "$TMP_DIR/verificar.err"
RC_VER=$?
foto "$TMP_DIR/foto-depois"
cmp -s "$TMP_DIR/foto-antes" "$TMP_DIR/foto-depois" || sem_prova 'os artefatos de reconciliação mudaram durante a verificação'
[ "$(g rev-parse --verify -q 'HEAD^{commit}')" = "$HEAD_SHA" ] || sem_prova 'HEAD mudou durante a verificação'
if [ "$RC_VER" != 0 ] || [ "$(sed -n 1p "$TMP_DIR/verificar")" != ok=true ]; then # guarda:V9OK
  awk 'index($0, "motivo\t") == 1 { print "motivo\treconciliacao-base: " substr($0, 8) }' "$TMP_DIR/verificar" > "$TMP_DIR/motivos-ver"
  sem_prova "reconciliacao-base.sh --verificar ok=false (rc $RC_VER)$( [ -s "$TMP_DIR/verificar.err" ] && printf ': %s' "$(tr '\n' ' ' < "$TMP_DIR/verificar.err")")" "$TMP_DIR/motivos-ver"
fi
awk -F'\t' '$1 == "coberto" { print $2 }' "$TMP_DIR/verificar" > "$TMP_DIR/cobertos"

ULTIMO="$(ls "$TMP_DIR/antes" | LC_ALL=C sort | sed -n '$p')"
AVISOS="$TMP_DIR/avisos"; : > "$AVISOS"
if [ -n "$ULTIMO" ]; then
  # com reconciliação: o b1_sha da última, do artefato validado
  num="$(printf '%s' "$ULTIMO" | sed 's/^RECONCILIACAO-BASE-0*\([0-9][0-9]*\)\.md$/\1/')"
  RB_ERRO=""
  rb_validar "$TMP_DIR/antes/$ULTIMO" "$TRABALHO" "$num" || sem_prova "$ULTIMO inválido: $RB_ERRO"
  rb_ler "$TMP_DIR/antes/$ULTIMO" > "$TMP_DIR/ultimo.lido" || sem_prova "$ULTIMO ilegível: $RB_ERRO"
  B_CADEIA="$(awk -F'\t' '$1 == "escalar" && $2 == "b1_sha" { print $3; exit }' "$TMP_DIR/ultimo.lido")"
  BASE="$B_CADEIA"; ORIGEM_BASE=reconciliacao # guarda:V9SHA
elif chave_qualquer "$ENTREGA_H" base_validada_sha; then
  # sem reconciliação: a base validada de HEAD, nunca a do disco
  B_HEAD="$(catalogo_fm "$ENTREGA_H" base_validada_sha)" # guarda:V9DISCO
  printf '%s' "$B_HEAD" | grep -Eq '^[0-9a-f]{40}$' || sem_prova "base_validada_sha de HEAD não é SHA de 40 hex: ${B_HEAD:-vazia ou ilegível}"
  case "$(catalogo_fm "$ENTREGA_H" origem_base)" in
    inferida_legado) OB_HEAD=inferida_legado ;;
    registrada_e0|'') OB_HEAD=registrada_e0 ;;
    *) sem_prova "origem_base de HEAD fora de registrada_e0|inferida_legado: $(catalogo_fm "$ENTREGA_H" origem_base)" ;;
  esac
  BASE="$B_HEAD"; ORIGEM_BASE="$OB_HEAD" # guarda:V9SHA
else
  # entrega legada: merge-base único com branch_base, só para esta leitura
  BB="$(catalogo_fm "$ENTREGA_H" branch_base)"
  { [ -n "$BB" ] && g check-ref-format --branch "$BB" >/dev/null 2>&1; } || sem_prova "legado: branch_base inválida em HEAD: ${BB:-ausente}"
  BB_SHA="$(g rev-parse --verify -q "$BB^{commit}" 2>/dev/null)" || sem_prova "legado: branch_base $BB inexistente"
  g merge-base --all "$HEAD_SHA" "$BB_SHA" > "$TMP_DIR/mb" 2>/dev/null || sem_prova "legado: nenhum merge-base entre HEAD e $BB"
  n="$(grep -c . "$TMP_DIR/mb")"
  [ "$n" = 1 ] || sem_prova "legado: $n merge-bases entre HEAD e $BB (a leitura exige exatamente um)"
  BASE="$(sed -n 1p "$TMP_DIR/mb")"; ORIGEM_BASE=inferida_leitura # guarda:V9SHA
fi
printf '%s' "$BASE" | grep -Eq '^[0-9a-f]{40}$' || sem_prova "base fora de 40 hex: ${BASE:-vazia}"
g cat-file -e "$BASE^{commit}" 2>/dev/null || sem_prova "base $BASE não é commit deste repositório"

# sem reconciliação: o disco que diverge de HEAD é relatado, nunca usado
if [ -z "$ULTIMO" ]; then
  if [ -f "$ENTREGA" ] && [ ! -L "$ENTREGA" ]; then b_disco="$(catalogo_fm "$ENTREGA" base_validada_sha)"; else b_disco=""; fi
  b_head="$(catalogo_fm "$ENTREGA_H" base_validada_sha)"
  [ "$b_disco" = "$b_head" ] || printf 'aviso\tbase_validada_sha do disco (%s) diverge da de HEAD:%s (%s); vale a de HEAD\n' \
    "${b_disco:-ausente}" "$ENTREGA" "${b_head:-ausente}" >> "$AVISOS"
fi

# ---------------------------------------------------------------------------
# O plano de HEAD: a pasta do trabalho materializada blob por blob (as três
# candidatas), para a união das tasks e a pasta isenta.
# ---------------------------------------------------------------------------
RAIZ_H="$TMP_DIR/arvore-head"
mkdir -p "$RAIZ_H" && RAIZ_H="$(cd "$RAIZ_H" && pwd -P)" || sem_prova 'árvore temporária de HEAD inacessível'
g ls-tree -r -z --full-tree "$HEAD_SHA" -- "docs/sprintx/features/$TRABALHO" "docs/$TRABALHO" "docs/manutencao/$TRABALHO" \
  > "$TMP_DIR/lista-head" 2>/dev/null || sem_prova 'árvore de HEAD ilegível'
while IFS= read -r -d '' item <&3; do
  modo="${item%% *}"; caminho="${item#*	}"
  case "$caminho" in *"$NL"*|*"$TAB"*|*[[:cntrl:]]*) sem_prova "pasta do trabalho em HEAD com caminho inválido: $(printf '%s' "$caminho" | tr '[:cntrl:]' '?')" ;; esac
  case "/$caminho/" in */./*|*/../*|*//*) sem_prova "pasta do trabalho em HEAD com caminho inválido (componente vazio, . ou ..): $caminho" ;; esac
  case "$modo" in 100644|100755) ;; *) sem_prova "pasta do trabalho em HEAD tem link simbólico ou submódulo (modo $modo): $caminho" ;; esac
  mkdir -p "$RAIZ_H/$(dirname "$caminho")" 2>/dev/null || sem_prova "não foi possível materializar $caminho de HEAD"
  destino="$(cd "$RAIZ_H/$(dirname "$caminho")" && pwd -P)" || sem_prova "não foi possível materializar $caminho de HEAD"
  case "$destino/" in "$RAIZ_H"/*) ;; *) sem_prova "pasta do trabalho em HEAD: destino fora da árvore temporária: $caminho" ;; esac
  g cat-file blob "$HEAD_SHA:$caminho" > "$destino/${caminho##*/}" 2>/dev/null || sem_prova "não foi possível ler $caminho de HEAD"
done 3< "$TMP_DIR/lista-head"
catalogo_pasta_do_trabalho "$RAIZ_H" "$ORIGEM" "$TRABALHO" > /dev/null || sem_prova "pasta do trabalho não determinável em HEAD: $CATALOGO_ERRO"
PASTA="$CATALOGO_PASTA"
bash "$OWNERSHIP_SH" --uniao "$RAIZ_H" "$ORIGEM" "$TRABALHO" > "$TMP_DIR/uniao" 2> "$TMP_DIR/uniao.err" \
  || sem_prova "união das tasks de HEAD não calculável: $(tr '\n' ' ' < "$TMP_DIR/uniao.err")" # guarda:V9UNIAO

# ---------------------------------------------------------------------------
# O diff e o conjunto aceito.
# ---------------------------------------------------------------------------
g diff --name-only -z --no-renames "$BASE...$HEAD_SHA" > "$TMP_DIR/diff" 2>/dev/null || sem_prova "diff $BASE...HEAD não calculável"
contem() { grep -Fxq -e "$2" "$1"; }
: > "$TMP_DIR/fora"
while IFS= read -r -d '' p <&3; do
  case "$p" in
    *"$NL"*|*"$TAB"*) printf 'fora_do_plano\t%s\n' "$(printf '%s' "$p" | tr '\t\n' '??')" >> "$TMP_DIR/fora"; continue ;;
  esac
  contem "$TMP_DIR/uniao" "$p" && continue
  case "$p" in "$PASTA"/*|"$DIR_E"/*) continue ;; esac
  [ "$ORIGEM" = sprintx ] && [ "$p" = docs/sprintx/estimativas/HISTORICO.md ] && continue # guarda:V9HIST
  contem "$TMP_DIR/cobertos" "$p" && continue
  printf 'fora_do_plano\t%s\n' "$p" >> "$TMP_DIR/fora"
done 3< "$TMP_DIR/diff"

printf 'base=%s\norigem_base=%s\n' "$BASE" "$ORIGEM_BASE"
cat "$AVISOS"
if [ -s "$TMP_DIR/fora" ]; then
  printf 'resultado=v9\n'
  LC_ALL=C sort "$TMP_DIR/fora"
  exit 1
fi
printf 'resultado=ok\n'
exit 0
