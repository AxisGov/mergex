#!/usr/bin/env bash
#
# Regera a copia do nucleo do expx que os testes usam
# (scripts/ci/fixtures/candidatos/expx-nucleo/) a partir de um clone do expxdev,
# numa revisao, e regrava o ORIGEM (`expxdev <sha>` e `sha256  arquivo`).
#
#   bash scripts/ci/atualizar-nucleo-expx.sh <expxdev_raiz> <rev>
#
# Ex.: bash scripts/ci/atualizar-nucleo-expx.sh ../expxdev origin/main
# Le os arquivos da revisao (`git show <rev>:nucleo/scripts/<arquivo>`), nunca da
# arvore de trabalho do clone: o que entra e exatamente o commitado no expxdev.
# A copia e artefato gerado: commit proprio, com este comando no corpo.
# Saida: 0 copiou; 64 uso; 1 revisao ou arquivo ausente.

set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: ${0##*/} <expxdev_raiz> <rev>" >&2
  exit 64
fi
expx="$1"; rev="$2"
destino="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/candidatos/expx-nucleo"
arquivos='expx-fatiamento.mjs expx-revisao.mjs'

sha_rev="$(git -C "$expx" rev-parse --verify --quiet "$rev^{commit}")" \
  || { echo "revisao inexistente em $expx: $rev" >&2; exit 1; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'expxdev %s\n' "$sha_rev" > "$tmp/ORIGEM"
for f in $arquivos; do
  git -C "$expx" show "$sha_rev:nucleo/scripts/$f" > "$tmp/$f" 2>/dev/null \
    || { echo "arquivo ausente em $sha_rev: nucleo/scripts/$f" >&2; exit 1; }
  printf '%s  %s\n' "$(sha "$tmp/$f")" "$f" >> "$tmp/ORIGEM"
done

mkdir -p "$destino" || { echo "nao foi possivel criar $destino" >&2; exit 1; }
for f in $arquivos ORIGEM; do
  cp "$tmp/$f" "$destino/$f" || { echo "nao foi possivel gravar $destino/$f" >&2; exit 1; }
done
printf 'copia do nucleo: expxdev %s\n' "$sha_rev"
