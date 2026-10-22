#!/usr/bin/env bash
# Regressão: com `set -o pipefail`, `codigo | grep -q` pode devolver 141
# quando o produtor ainda escreve depois de o grep encontrar a ocorrência.
# Aumenta apenas com linhas vazias uma cópia da trava, sem mudar seu contrato,
# e exige que o validador continue verde.

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo" || exit 1

(
  cd "$raiz" || exit 1
  git ls-files -z | tar -cf - --null -T -
) | (
  cd "$tmp/repo" || exit 1
  tar -xf -
) || { echo 'não foi possível preparar a cópia do contrato' >&2; exit 1; }

(
  cd "$tmp/repo" || exit 1
  git init -q -b main . || exit 1
  git config user.email teste@expx.local
  git config user.name Teste
  git add -A && git commit -qm fixture
) || { echo 'não foi possível versionar a cópia do contrato' >&2; exit 1; }

# Mais que a capacidade usual do pipe: força o produtor a observar o leitor
# encerrado cedo quando houver `grep -q` na cadeia.
awk 'BEGIN { for (i = 0; i < 200000; i++) print "" }' \
  >> "$tmp/repo/.claude/skills/mergex/scripts/trava-do-e1.sh"

if ! (cd "$tmp/repo" && bash scripts/ci/validate-mergex-contract.sh) \
  > "$tmp/saida" 2>&1; then
  cat "$tmp/saida" >&2
  echo 'validador do contrato falhou com código equivalente e arquivo maior' >&2
  exit 1
fi

echo 'validador do contrato não depende de grep -q em pipeline'
