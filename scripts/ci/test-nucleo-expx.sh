#!/usr/bin/env bash
#
# A copia do nucleo do expx que os testes montam num projeto temporario
# (scripts/ci/fixtures/candidatos/expx-nucleo/): a pasta nucleo/scripts/ inteira de uma
# revisao do expxdev. E artefato gerado, regerado so por
# `bash scripts/ci/atualizar-nucleo-expx.sh <expxdev_raiz> <rev>`; o ORIGEM diz de
# qual revisao do expxdev ela veio e o sha256 de cada arquivo, com o caminho relativo.
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

# confere_origem <pasta>: imprime o que nao confere (nada = confere). O ORIGEM tem
# `expxdev <rev>` e uma linha `sha256  caminho` por arquivo da pasta, e so por eles.
confere_origem() {
  local d="$1" origem erros='' h f n=0
  [ -f "$d/ORIGEM" ] || { printf ' ORIGEM-ausente'; return; }
  # sem CR, como a copia: num checkout com core.autocrlf=true o ORIGEM tambem chega com CRLF
  origem="$(tr -d '\r' < "$d/ORIGEM")"
  printf '%s\n' "$origem" | head -1 | grep -Eq '^expxdev [0-9a-f]{7,40}$' || erros="$erros cabecalho"
  while read -r h f; do
    n=$((n + 1))
    printf '%s\n' "$origem" | tail -n +2 | cut -c67- | grep -cxF -- "$f" | grep -qx 1 || erros="$erros repetida:$f"
    printf '%s\n' "$h" | grep -Eq '^[0-9a-f]{64}$' && [ -f "$d/$f" ] && [ "$(sha "$d/$f")" = "$h" ] \
      || erros="$erros $f"
  done < <(printf '%s\n' "$origem" | tail -n +2)
  while IFS= read -r f; do
    printf '%s\n' "$origem" | tail -n +2 | grep -qxF "$(sha "$d/$f")  $f" || erros="$erros sem-linha:$f"
  done < <(cd "$d" && find . -type f ! -path ./ORIGEM | sed 's|^\./||' | LC_ALL=C sort)
  [ "$n" -ge 1 ] || erros="$erros vazio"
  printf '%s' "$erros"
}

# 1. ORIGEM: `expxdev <rev>` e uma linha `sha256  caminho` por arquivo da copia, que confere
erros="$(confere_origem "$copia")"
origem="$(tr -d '\r' < "$copia/ORIGEM" 2>/dev/null)"
for f in expx-fatiamento.mjs expx-revisao.mjs; do
  printf '%s\n' "$origem" | grep -Eq "^[0-9a-f]{64}  $f\$" || erros="$erros sem:$f"
done
[ -z "$erros" ] && passa 'ORIGEM confere com o sha256 de cada copia' \
  || quebra "ORIGEM nao confere:$erros"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# 1b. ORIGEM lista todo arquivo da copia, e so eles: arquivo sem linha, ou linha sem arquivo, reprova
mkdir -p "$tmp/sobra" "$tmp/falta" "$tmp/repete"
cp -R "$copia"/. "$tmp/sobra/"; cp -R "$copia"/. "$tmp/falta/"; cp -R "$copia"/. "$tmp/repete/"
tr -d '\r' < "$copia/ORIGEM" | tail -1 >> "$tmp/repete/ORIGEM"
mkdir -p "$tmp/sobra/perfis"; printf '{}\n' > "$tmp/sobra/perfis/a-mais.json"
rm -f "$tmp/falta/expx-revisao.mjs"
s="$(confere_origem "$tmp/sobra")"; fa="$(confere_origem "$tmp/falta")"; r="$(confere_origem "$tmp/repete")"
case "$s" in *'sem-linha:perfis/a-mais.json'*) true ;; *) false ;; esac \
  && case "$fa" in *' expx-revisao.mjs'*) true ;; *) false ;; esac \
  && case "$r" in *'repetida:'*) true ;; *) false ;; esac \
  && passa 'ORIGEM lista todo arquivo da copia, uma vez, e so eles' \
  || quebra "ORIGEM com arquivo a mais, a menos ou repetido passou: sobra[$s] falta[$fa] repete[$r]"

# 2. a copia, num commit so dela, fica fora do F2 do proprio repositorio (padrao do script)
g() { git -C "$tmp/f2" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir -p "$tmp/f2"; g init -q -b main
printf 'base\n' > "$tmp/f2/base.txt"; g add -A; g commit -q -m base
g switch -q -c copia
mkdir -p "$tmp/f2/$copia_rel"
cp -R "$copia"/. "$tmp/f2/$copia_rel/" 2>/dev/null
if g add -A && g commit -q -m copia >/dev/null 2>&1; then
  saida="$(cd "$tmp/f2" && unset FATIA_IGNORAR FATIA_IGNORAR_PROJETO && bash "$script" main copia 2>&1)"
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

# o atualizar contra um expxdev falso: `nucleo` tem a pasta com subpasta; `sem-nucleo` nao tem
# a pasta. autocrlf=true no clone falso: a copia sai do commitado (LF), nunca convertida.
e() { git -C "$tmp/expx" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir -p "$tmp/expx/nucleo/scripts/perfis" "$tmp/expx/outro"
printf 'a\n' > "$tmp/expx/nucleo/scripts/a.mjs"
printf '{ "p": 1 }\n' > "$tmp/expx/nucleo/scripts/perfis/p.json"
printf 'fora\n' > "$tmp/expx/outro/fora.txt"
e init -q; e config core.autocrlf true; e add -A 2>/dev/null; e commit -q -m nucleo; e tag nucleo
e rm -rq nucleo; e commit -q -m sem; e tag sem-nucleo
# `ligacao`: nucleo/scripts com um link simbolico (modo 120000, pelo indice: vale sem symlink no disco)
e checkout -q nucleo 2>/dev/null
printf 'alvo\n' > "$tmp/alvo.txt"
e update-index --add --cacheinfo "120000,$(printf '%s' "$tmp/alvo.txt" | e hash-object -w --stdin),nucleo/scripts/ORIGEM"
e commit -q -m ligacao; e tag ligacao; e checkout -q sem-nucleo 2>/dev/null
sha_nucleo="$(e rev-parse nucleo)"
rep="$tmp/rep/scripts/ci"; dest="$rep/fixtures/candidatos/expx-nucleo"
mkdir -p "$rep/fixtures/candidatos"
cp "$raiz/scripts/ci/atualizar-nucleo-expx.sh" "$rep/"
atualizar() { bash "$rep/atualizar-nucleo-expx.sh" "$tmp/expx" "$1" >/dev/null 2>&1; }
inventario() { (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(sha "$f")" "$f"; done); }
vizinhos() { ls -A "$rep/fixtures/candidatos" | grep -vxF expx-nucleo; }

# 4. o atualizar copia as subpastas do nucleo, e o ORIGEM tem o caminho relativo
mkdir -p "$dest"; printf 'velho\n' > "$dest/velho.mjs"; printf 'expxdev 0000000\n' > "$dest/ORIGEM"
atualizar nucleo; rc=$?
o="$(cat "$dest/ORIGEM" 2>/dev/null)"
[ "$rc" = 0 ] && [ -f "$dest/perfis/p.json" ] && [ -f "$dest/a.mjs" ] \
  && printf '%s\n' "$o" | head -1 | grep -qxF "expxdev $sha_nucleo" \
  && printf '%s\n' "$o" | grep -qxF "$(sha "$dest/perfis/p.json")  perfis/p.json" \
  && [ -z "$(confere_origem "$dest")" ] \
  && passa 'atualizar copia subpastas do nucleo' \
  || quebra "atualizar nao copiou a pasta inteira (rc $rc): $o"
[ -f "$dest/a.mjs" ] && [ "$(tr -cd '\r' < "$dest/a.mjs" | wc -c | tr -d ' ')" = 0 ] && [ ! -e "$dest/outro" ] \
  && passa 'atualizar copia o commitado (LF), so de nucleo/scripts' \
  || quebra 'atualizar converteu fim de linha, nao copiou ou copiou fora de nucleo/scripts'

# 5. o que saiu do nucleo sai da copia; nada sobra ao lado do destino
[ ! -e "$dest/velho.mjs" ] && [ -z "$(vizinhos)" ] \
  && passa 'atualizar apaga o que saiu do nucleo' \
  || quebra "atualizar deixou o que saiu do nucleo: $(ls -A "$dest") | $(vizinhos)"

# 6. revisao sem nucleo/scripts: sai 1 e a copia fica como estava
antes="$(inventario "$dest")"
atualizar sem-nucleo; rc=$?
[ "$rc" = 1 ] && [ "$(inventario "$dest")" = "$antes" ] && [ -z "$(vizinhos)" ] \
  && passa 'atualizar sem nucleo/scripts na revisao sai 1 e nao toca a copia' \
  || quebra "atualizar sem nucleo/scripts saiu $rc ou mexeu na copia"

# 6b. outra atualizacao em curso (a trava ao lado do destino): sai 1, nao toca a copia nem a trava
mkdir "$dest.trava"
atualizar nucleo; rc=$?
[ "$rc" = 1 ] && [ "$(inventario "$dest")" = "$antes" ] && [ -d "$dest.trava" ] \
  && passa 'atualizar com outra atualizacao em curso sai 1 e nao toca a copia' \
  || quebra "atualizar com a trava de outra atualizacao saiu $rc ou mexeu na copia"
rmdir "$dest.trava"

# 6c. revisao com link simbolico em nucleo/scripts (aqui, um ORIGEM que aponta para um arquivo fora): sai 1,
# nao toca a copia nem o alvo do link
atualizar ligacao; rc=$?
[ "$rc" = 1 ] && [ "$(inventario "$dest")" = "$antes" ] && [ -z "$(vizinhos)" ] \
  && [ "$(cat "$tmp/alvo.txt")" = alvo ] \
  && passa 'atualizar com link simbolico no nucleo sai 1 e nao toca a copia' \
  || quebra "atualizar com link simbolico no nucleo saiu $rc ou mexeu na copia"

# 7. o atualizar nao diz que copiou quando nao conseguiu gravar a copia (destino e um arquivo)
rm -rf "$dest"; printf 'nao e pasta\n' > "$dest"
atualizar nucleo; rc=$?
[ "$rc" = 1 ] && [ "$(cat "$dest")" = 'nao e pasta' ] \
  && passa 'atualizar-nucleo-expx sai 1 quando nao grava a copia' \
  || quebra "atualizar-nucleo-expx saiu $rc sem conseguir gravar a copia"

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
