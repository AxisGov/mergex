#!/usr/bin/env bash
#
# A copia do nucleo do expx que os testes montam num projeto temporario
# (scripts/ci/fixtures/candidatos/expx-nucleo/). E artefato gerado, regerado so por
# `bash scripts/ci/atualizar-nucleo-expx.sh <expxdev_raiz> <rev>`; o ORIGEM diz de
# qual revisao do expxdev ela veio e o sha256 de cada arquivo.
#
# Uso: bash scripts/ci/test-nucleo-expx.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
copia_rel='scripts/ci/fixtures/candidatos/expx-nucleo'
copia="$raiz/$copia_rel"
script="$raiz/.claude/skills/mergex/scripts/fatiamento-da-pr.sh"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }
# sem CR: num checkout com core.autocrlf=true a copia chega com CRLF; o ORIGEM e do commitado (LF)
sha() { tr -d '\r' < "$1" | if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }

# 1. ORIGEM: `expxdev <rev>` e uma linha `sha256  arquivo` por copia, que confere
if [ ! -f "$copia/ORIGEM" ]; then
  quebra "ORIGEM ausente em $copia_rel"
else
  # sem CR, como a copia: num checkout com core.autocrlf=true o ORIGEM tambem chega com CRLF
  origem="$(tr -d '\r' < "$copia/ORIGEM")"
  erros=''; n=0
  printf '%s\n' "$origem" | head -1 | grep -Eq '^expxdev [0-9a-f]{7,40}$' || erros="$erros cabecalho"
  while read -r h f; do
    n=$((n + 1))
    [ -f "$copia/$f" ] && [ "$(sha "$copia/$f")" = "$h" ] || erros="$erros $f"
  done < <(printf '%s\n' "$origem" | tail -n +2)
  for f in expx-fatiamento.mjs expx-revisao.mjs; do
    printf '%s\n' "$origem" | grep -Eq "^[0-9a-f]{64}  $f\$" || erros="$erros sem:$f"
  done
  [ -z "$erros" ] && [ "$n" -ge 2 ] && passa 'ORIGEM confere com o sha256 de cada copia' \
    || quebra "ORIGEM nao confere:$erros"
fi

# 2. a copia, num commit so dela, fica fora do F2 do proprio repositorio (padrao do script)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
g() { git -C "$tmp" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base
g switch -q -c copia
mkdir -p "$tmp/$copia_rel"
cp "$copia"/* "$tmp/$copia_rel/" 2>/dev/null
if g add -A && g commit -q -m copia >/dev/null 2>&1; then
  saida="$(cd "$tmp" && unset FATIA_IGNORAR FATIA_IGNORAR_PROJETO && bash "$script" main copia 2>&1)"
  case "$saida" in
    *'PR com 0 linhas em 0 arquivo'*) passa 'a copia fica fora do F2 do proprio repositorio' ;;
    *) quebra "a copia entrou na medida do F2: $saida" ;;
  esac
else
  quebra 'a copia fica fora do F2: nao ha copia para commitar'
fi

# 3. node roda a copia: num projeto sem .expx/fatiamento.json, os padroes
if ! command -v node >/dev/null 2>&1; then
  passa 'node consegue rodar a copia (sem node)'
else
  mkdir -p "$tmp/vazio"
  saida="$(node "$copia/expx-fatiamento.mjs" --raiz "$tmp/vazio" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && case "$saida" in *'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
    && passa 'node consegue rodar a copia' \
    || quebra "node nao rodou a copia (rc $rc): $saida"
fi

# 4. o atualizar nao diz que copiou quando nao conseguiu gravar a copia (destino e um arquivo)
mkdir -p "$tmp/expx/nucleo/scripts" "$tmp/rep/scripts/ci/fixtures/candidatos"
for f in expx-fatiamento.mjs expx-revisao.mjs; do printf 'x\n' > "$tmp/expx/nucleo/scripts/$f"; done
e() { git -C "$tmp/expx" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
e init -q; e add -A; e commit -q -m nucleo
cp "$raiz/scripts/ci/atualizar-nucleo-expx.sh" "$tmp/rep/scripts/ci/"
printf 'nao e pasta\n' > "$tmp/rep/scripts/ci/fixtures/candidatos/expx-nucleo"
bash "$tmp/rep/scripts/ci/atualizar-nucleo-expx.sh" "$tmp/expx" HEAD >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && passa 'atualizar-nucleo-expx sai 1 quando nao grava a copia' \
  || quebra "atualizar-nucleo-expx saiu $rc sem conseguir gravar a copia"

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
