#!/usr/bin/env bash
#
# Regera a copia do nucleo do expx que os testes usam
# (scripts/ci/fixtures/candidatos/expx-nucleo/) a partir de um clone do expxdev,
# numa revisao, e regrava o ORIGEM (`expxdev <sha>` e `sha256  caminho` por arquivo).
#
#   bash scripts/ci/atualizar-nucleo-expx.sh <expxdev_raiz> <rev>
#
# Ex.: bash scripts/ci/atualizar-nucleo-expx.sh ../expxdev origin/main
# Copia a pasta nucleo/scripts/ inteira da revisao (`git archive <sha> nucleo/scripts`),
# com as subpastas, nunca da arvore de trabalho do clone: o que entra e exatamente o
# commitado no expxdev, e o que saiu do nucleo sai da copia. A troca nunca deixa o
# destino vazio: grava em <destino>.novo, poe a copia atual em <destino>.velho, poe
# a nova no lugar e so entao apaga a velha; se a nova nao entra, a velha volta.
# Uma atualizacao por vez: a trava <destino>.trava (mkdir) recusa a segunda, com saida 1.
# A copia e artefato gerado: commit proprio, com este comando no corpo.
# Saida: 0 copiou; 64 uso; 1 revisao ausente, revisao sem nucleo/scripts ou copia nao gravada.

set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "uso: ${0##*/} <expxdev_raiz> <rev>" >&2
  exit 64
fi
expx="$1"; rev="$2"
destino="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/candidatos/expx-nucleo"
novo="$destino.novo"; velho="$destino.velho"; trava="$destino.trava"

sha_rev="$(git -C "$expx" rev-parse --verify --quiet "$rev^{commit}")" \
  || { echo "revisao inexistente em $expx: $rev" >&2; exit 1; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

if [ -e "$destino" ] && [ ! -d "$destino" ]; then
  echo "o destino existe e nao e pasta: $destino" >&2; exit 1
fi
mkdir -p "$(dirname "$destino")" || { echo "nao foi possivel criar $(dirname "$destino")" >&2; exit 1; }
mkdir "$trava" 2>/dev/null \
  || { echo "outra atualizacao em curso ($trava); se nenhuma roda, apague a pasta" >&2; exit 1; }
tmp=''; trap 'rm -rf "${tmp:-}" "$novo"; rmdir "$trava"' EXIT
if [ -e "$velho" ]; then
  # resto de uma troca interrompida: com o destino no lugar, a velha sobrou; sem ele, e a unica copia
  [ -d "$destino" ] || { echo "copia anterior so em $velho: confira e devolva-a a $destino" >&2; exit 1; }
  rm -rf "$velho" || { echo "nao foi possivel apagar $velho" >&2; exit 1; }
fi

tmp="$(mktemp -d)" || { echo "nao foi possivel criar a pasta temporaria" >&2; exit 1; }
# sem conversao de fim de linha: a copia e o blob commitado (LF), em qualquer clone
git -C "$expx" -c core.autocrlf=false archive --format=tar "$sha_rev" nucleo/scripts > "$tmp/nucleo.tar" 2>/dev/null \
  && mkdir -p "$tmp/x" && tar -xf "$tmp/nucleo.tar" -C "$tmp/x" 2>/dev/null \
  && [ -d "$tmp/x/nucleo/scripts" ] \
  || { echo "revisao $sha_rev sem nucleo/scripts" >&2; exit 1; }
# so arquivos e pastas: um link simbolico (ORIGEM ou outro) escreveria ou copiaria fora da copia
outros="$(cd "$tmp/x/nucleo/scripts" && find . ! -type f ! -type d)"
[ -z "$outros" ] || { echo "nucleo/scripts de $sha_rev tem o que nao e arquivo nem pasta: $outros" >&2; exit 1; }
arquivos="$(cd "$tmp/x/nucleo/scripts" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)"
[ -n "$arquivos" ] || { echo "revisao $sha_rev sem arquivo em nucleo/scripts" >&2; exit 1; }
if printf '%s\n' "$arquivos" | grep -qxF ORIGEM; then
  echo "nucleo/scripts de $sha_rev tem um arquivo ORIGEM, que a copia reserva" >&2; exit 1
fi

rm -rf "$novo" && cp -R "$tmp/x/nucleo/scripts" "$novo" \
  || { echo "nao foi possivel gravar $novo" >&2; exit 1; }
{
  printf 'expxdev %s\n' "$sha_rev"
  printf '%s\n' "$arquivos" | while IFS= read -r f; do printf '%s  %s\n' "$(sha "$novo/$f")" "$f"; done
} > "$novo/ORIGEM" || { echo "nao foi possivel gravar $novo/ORIGEM" >&2; exit 1; }

if [ -d "$destino" ]; then
  mv "$destino" "$velho" || { echo "nao foi possivel tirar a copia atual de $destino" >&2; exit 1; }
fi
if ! mv "$novo" "$destino"; then
  [ -d "$velho" ] && mv "$velho" "$destino"
  echo "nao foi possivel por a copia nova em $destino; a anterior ficou" >&2; exit 1
fi
rm -rf "$velho" || echo "aviso: $velho ficou; apague-o" >&2
printf 'copia do nucleo: expxdev %s\n' "$sha_rev"
