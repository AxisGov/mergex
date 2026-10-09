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
#   portao-ci.sh --verificar --sha <sha40|sha64> --branch <nome>
#
# Imprime, em stdout, decisao=<passa|avisa|barra>, motivo= e entrega=. O
# diagnóstico (avisa e barra) vai a stderr; historia_incompleta (completar a
# história, clone raso) e erro_ambiente (falha do ambiente, inclusive o
# validador ausente) têm textos distintos.
#
# Códigos: 0 passa ou avisa; 1 barra; 64 uso. Nenhuma opção de força.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uso() {
  [ -z "${1:-}" ] || printf 'portao-ci: %s\n' "$1" >&2
  printf '%s\n' 'uso: portao-ci.sh --verificar --sha <sha40> --branch <nome>' >&2
  exit 64
}

[ "$#" -eq 5 ] || uso 'esperava --verificar --sha <sha40> --branch <nome>'
[ "$1" = --verificar ] || uso "opção desconhecida: $1"
[ "$2" = --sha ] || uso "esperava --sha, recebi: $2"
SHA="$3"
[ "$4" = --branch ] || uso "esperava --branch, recebi: $4"
BRANCH="$5"
printf '%s\n' "$SHA" | grep -Eqx '[0-9a-f]{40}|[0-9a-f]{64}' || uso '--sha precisa ser um SHA completo (40 hex)'
[ -n "$BRANCH" ] || uso '--branch vazio'

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
trap 'rm -f "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

: > "$TMP"
pr_decide_ref "$RAIZ" "$REF" "$SHA" "$REF" "$NULO" > "$TMP" # guarda:CISHA
cat "$TMP"
decisao="$(sed -n 's/^decisao=//p' "$TMP")"
case "$decisao" in
  passa) exit 0 ;;
  avisa) diag "$REF: $PR_DIAG"; exit 0 ;;
  *) diag "$REF: ${PR_DIAG:-$AMBIENTE: decisão indeterminada}"; exit 1 ;; # guarda:CIBARRA
esac
