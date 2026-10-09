#!/usr/bin/env bash
# portao-push — o validador de push da MergeX, chamado pelo `pre-push` do Git.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seção 13, item 7 (DM-184). É a barreira local autoritativa contra erro
# normal: decide só com o que o Git entrega na entrada padrão, nunca com texto
# de comando de shell (um push por `cd`, `bash -c` ou link simbólico chega aqui
# igual).
#
# Uso (pelo pre-push, que repassa a entrada padrão e propaga o código):
#   portao-push.sh --pre-push <remoto> <url>
#
# Entrada padrão: o protocolo do pre-push, uma linha por ref:
#   <ref local> SP <SHA local> SP <ref remota> SP <SHA remoto>
# Cada ref é decidida por pr_decide_ref (portao-regras.sh) sobre o SHA local
# DAQUELA linha, nunca sobre o HEAD do checkout. Qualquer ref que barra barra
# o push inteiro, mesmo depois de uma válida. Linha fora do protocolo barra.
#
# Diagnóstico em stderr, uma linha por ref que avisa ou barra; os de
# historia_incompleta (completar a história) e de erro_ambiente (falha do
# ambiente, inclusive o validador ausente) são textos distintos.
#
# MERGEX_PRE_PUSH_SINAL=<arquivo> no ambiente: só acrescenta a linha
# `mergex-pre-push invocado <pid>` ao arquivo (o sinal da prova funcional do
# E0/E2), sem mudar a decisão.
#
# Códigos: 0 libera; 1 barra; 64 uso. Custo: uma validade por ref aplicável,
# nenhuma varredura de branches. Nenhuma opção de força.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uso() {
  [ -z "${1:-}" ] || printf 'portao-push: %s\n' "$1" >&2
  printf '%s\n' 'uso: portao-push.sh --pre-push <remoto> <url>' >&2
  exit 64
}

[ "$#" -eq 3 ] || uso 'esperava --pre-push <remoto> <url>'
[ "$1" = --pre-push ] || uso "opção desconhecida: $1"
REMOTO="$2"

if [ -n "${MERGEX_PRE_PUSH_SINAL:-}" ]; then
  printf 'mergex-pre-push invocado %s\n' "$$" >> "$MERGEX_PRE_PUSH_SINAL" 2>/dev/null || true
fi

diag() { printf 'mergex pre-push: %s\n' "$1" >&2; }
AMBIENTE='erro de ambiente (erro_ambiente): a validade do portão não pôde ser avaliada'

TMP_DIR=""
encerrar() {
  local rc="$1"
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  exit "$rc"
}
trap 'encerrar $?' EXIT
trap 'exit 1' HUP INT TERM

# shellcheck source=portao-regras.sh
if [ ! -r "$AQUI/portao-regras.sh" ] || ! . "$AQUI/portao-regras.sh"; then
  cat >/dev/null 2>&1
  diag "$AMBIENTE: regras indisponíveis em $AQUI (${PR_ERRO:-portao-regras.sh ausente}); push barrado"
  exit 1
fi
set +e

arvore_ambiente_git
export GIT_OPTIONAL_LOCKS=0

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-portao-push.XXXXXX")" \
  || { TMP_DIR=""; cat >/dev/null 2>&1; diag "$AMBIENTE: não foi possível criar diretório temporário; push barrado"; exit 1; }
# a entrada inteira antes de decidir: o Git não fica preso escrevendo
cat > "$TMP_DIR/entrada" || { diag "$AMBIENTE: entrada padrão ilegível; push barrado"; exit 1; }

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { diag "$AMBIENTE: fora de um repositório Git com árvore de trabalho; push barrado"; exit 1; }

BARRA=0
while IFS=' ' read -r ref_local sha_local ref_remota sha_remoto resto <&3; do
  [ -n "$ref_local$sha_local$ref_remota$sha_remoto$resto" ] || continue
  if [ -n "$resto" ] || [ -z "$sha_remoto" ] \
    || printf '%s\n%s\n' "$sha_local" "$sha_remoto" | grep -Evqx '[0-9a-f]{40}|[0-9a-f]{64}'; then
    diag "linha fora do protocolo pre-push para $REMOTO: '$ref_local $sha_local $ref_remota $sha_remoto${resto:+ $resto}'; push barrado"
    BARRA=1; continue
  fi
  : > "$TMP_DIR/decisao"
  pr_decide_ref "$RAIZ" "$ref_local" "$sha_local" "$ref_remota" "$sha_remoto" > "$TMP_DIR/decisao" # guarda:PPSHA
  decisao="$(sed -n 's/^decisao=//p' "$TMP_DIR/decisao")"
  case "$decisao" in
    passa) ;;
    avisa) diag "$ref_remota: $PR_DIAG" ;;
    *) diag "$ref_remota: ${PR_DIAG:-$AMBIENTE: decisão indeterminada}" ;;
  esac
  [ "$decisao" = passa ] || [ "$decisao" = avisa ] || BARRA=1 # guarda:PPMULTI
done 3< "$TMP_DIR/entrada"

[ "$BARRA" = 0 ] || diag "push barrado: uma ref inválida barra o push inteiro"
exit "$BARRA"
