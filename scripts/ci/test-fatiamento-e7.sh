#!/usr/bin/env bash
#
# O E7 mede o PR contra o `expx-fatiamento` antes de abrir (07-abertura-pr.md,
# Passo 1.5). Confere que o passo existe, vem antes da abertura, e que o script
# da skill reprova PR grande e deixa passar PR pequeno.
#
# Uso: bash scripts/ci/test-fatiamento-e7.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$raiz/.claude/skills/mergex/scripts/fatiamento-da-pr.sh"
e7="$raiz/.claude/skills/mergex/references/07-abertura-pr.md"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }

[ -f "$script" ] && passa 'o script de fatiamento existe na skill' || quebra 'fatiamento-da-pr.sh ausente'
grep -Fq 'COPIA, nao dependencia' "$script" \
  && passa 'o script declara que e copia do verificador do ExpxDev' \
  || quebra 'o script nao declara de onde vem'

l15="$(grep -n '^## Passo 1.5' "$e7" | head -1 | cut -d: -f1)"
l2="$(grep -n '^## Passo 2 ' "$e7" | head -1 | cut -d: -f1)"
if [ -n "$l15" ] && [ -n "$l2" ] && [ "$l15" -lt "$l2" ]; then
  passa 'o Passo 1.5 (fatiamento) vem antes do Passo 2 (abrir o PR)'
else
  quebra 'o Passo 1.5 nao existe ou nao vem antes da abertura'
fi
grep -Fq 'fatiamento-da-pr.sh "$base" "$publicado"' "$e7" \
  && passa 'o E7 mede o SHA publicado contra a base' \
  || quebra 'o E7 nao chama o script sobre o SHA publicado'
grep -Fq 'o E7 **não abre o PR**' "$e7" \
  && passa 'violacao impede a abertura' \
  || quebra 'o E7 nao diz que a violacao impede a abertura'

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
g() { git -C "$tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base
g switch -q -c pequeno
printf 'linha\n%.0s' $(seq 1 30) > "$tmp/a.md"; g add -A; g commit -q -m pequeno
if (cd "$tmp" && bash "$script" main pequeno >/dev/null 2>&1); then passa 'PR pequeno passa'; else quebra 'PR pequeno reprovou'; fi
g switch -q -c grande main
for i in 1 2 3; do printf 'linha\n%.0s' $(seq 1 200) > "$tmp/g$i.md"; g add -A; g commit -q -m "parte $i"; done
if (cd "$tmp" && bash "$script" main grande >/dev/null 2>&1); then quebra 'PR de 600 linhas passou'; else passa 'PR de 600 linhas reprova (F2)'; fi

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
