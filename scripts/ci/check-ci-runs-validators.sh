#!/usr/bin/env bash
#
# Prova que o CI roda cada validador de contrato, uma vez e em passo próprio.
#
# Os dois validadores guardam coisas diferentes e não substituem um ao outro:
#   - validate-mergex-contract.sh           compatibilidade com os worktrees da sprintx;
#   - validate-review-evidence-contract.sh  o gate de evidência de review (E9).
#
# Sem esta guarda, apagar ou comentar o passo de um deles deixaria o CI verde
# sem que a verificação exista. Também recusa validador novo em scripts/ci/ que
# ninguém registrou aqui: ele existiria e nunca rodaria.
#
# Pelo mesmo motivo, cada bancada scripts/ci/mutacao-*.sh tem de estar, uma vez,
# na matriz do workflow agendado de mutação (que não é check exigido).
#
# Uso: bash scripts/ci/check-ci-runs-validators.sh [workflow [workflow-de-mutacao]]

set -euo pipefail

fail() {
  printf 'ci guard failed: %s\n' "$*" >&2
  exit 1
}

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$raiz"

ci="${1:-.github/workflows/ci.yml}"
[ -f "$ci" ] || fail "workflow ausente: $ci"

validadores=(
  scripts/ci/validate-mergex-contract.sh
  scripts/ci/validate-review-evidence-contract.sh
)

for v in "${validadores[@]}"; do
  [ -f "$v" ] || fail "validador ausente: $v"
  n="$(grep -cE "^[[:space:]]*run:[[:space:]]+bash[[:space:]]+${v//./\\.}[[:space:]]*$" "$ci" || true)"
  [ "$n" = '1' ] || fail "$v roda $n vez(es) em $ci; esperado exatamente 1"
done

for f in scripts/ci/validate-*.sh; do
  achado=0
  for v in "${validadores[@]}"; do
    [ "$f" = "$v" ] && achado=1
  done
  [ "$achado" = '1' ] || fail "$f existe mas nao esta registrado em check-ci-runs-validators.sh"
done

mut="${2:-.github/workflows/mutacao.yml}"
[ -f "$mut" ] || fail "workflow de mutacao ausente: $mut"
# Só os itens da lista `bancada:` da matriz contam: o mesmo nome em outra lista
# (os `paths` do gatilho, por exemplo) não põe a bancada para rodar.
matriz="$(tr -d '\r' < "$mut" | awk '
  dentro && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print; next }
  dentro && /^[[:space:]]*(#.*)?$/ { next }
  { dentro = 0 }
  /^[[:space:]]*bancada:[[:space:]]*$/ { dentro = 1 }
')"
for f in scripts/ci/mutacao-*.sh; do
  b="$(basename "$f" .sh)"
  n="$(printf '%s\n' "$matriz" | grep -cFx -- "$b" || true)"
  [ "$n" = '1' ] || fail "$f aparece $n vez(es) na matriz de $mut; esperado exatamente 1"
done

printf 'ci runs both validators\n'
