#!/usr/bin/env bash
# O custo da dispensa do sem-segredo nao cresce com o numero de arquivos (DM-289), e o hook
# fecha dentro do timeout de 10 s do harness, inclusive quando a dispensa desiste. A DM-286
# foi revertida por isso: dez processos por arquivo, 11 s com 266 arquivos e, no Windows, pior.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$RAIZ/.claude/hooks/comum/sem-segredo.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok=0; falhou=0
afirma() { if [ "$2" = 0 ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; fi; }

sha_de() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# monta <pasta> <n> — repositorio com n arquivos do framework preparados e o lock conferindo.
monta() {
  local r="$1" n="$2" i
  git init -q "$r"; mkdir -p "$r/.claude/skills/mergex/scripts" "$r/.expx" "$r/.claude/hooks/comum"
  cp -R "$RAIZ/.claude/hooks/comum/." "$r/.claude/hooks/comum/"
  cp "$RAIZ"/.claude/skills/mergex/scripts/segredo-*.sh "$r/.claude/skills/mergex/scripts/"
  git -C "$r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m raiz
  { printf '{"lock_version":2,"cli_version":"0","harness":[],"skills":{},"instalacao":{"arquivos":{'
    for i in $(seq 1 "$n"); do
      printf 'conteudo %s\n' "$i" > "$r/.claude/skills/f$i.md"
      [ "$i" = 1 ] || printf ','
      printf '".claude/skills/f%s.md":"%s"' "$i" "$(sha_de "$r/.claude/skills/f$i.md")"
    done
    printf '}}}\n'; } > "$r/.expx/expx-lock.json"
  git -C "$r" add .expx .claude/skills
}

# conta <pasta> — invocacoes de git e perl durante a dispensa, sem a varredura
conta() {
  local r="$1" reg="$T/reg-$$"; : > "$reg"
  mkdir -p "$T/shim"
  for b in git perl; do
    real="$(command -v "$b")"
    printf '#!/bin/sh\nprintf "%s\\n" >> "%s"\nexec "%s" "$@"\n' "$b" "$reg" "$real" > "$T/shim/$b"; chmod +x "$T/shim/$b"
  done
  (cd "$r" && PATH="$T/shim:$PATH" bash -c '. "$1"; segredo_dispensaveis_indice >"$2"' _ "$RAIZ/.claude/skills/mergex/scripts/segredo-dispensa.sh" "$T/lista") 
  wc -l < "$reg" | tr -d ' '
}

monta "$T/um" 1;    c1="$(conta "$T/um")";    n1="$(wc -l < "$T/lista" | tr -d ' ')"
monta "$T/cem" 300; c300="$(conta "$T/cem")"; n300="$(wc -l < "$T/lista" | tr -d ' ')"
echo "  processos: N=1 -> $c1; N=300 -> $c300 (dispensados: $n1 e $n300)"
[ "$n1" = 1 ] && [ "$n300" = 300 ]; afirma "dispensa os arquivos que o lock confere" $?
[ "$c300" -le "$c1" ]; afirma "o numero de processos nao cresce com N" $?

# Caminho com TAB ou quebra de linha nao se passa por outro: o blob do decoy bate com o lock,
# mas o arquivo real tem outro conteudo. Windows nao aceita esses nomes.
case "${OSTYPE:-}" in
  msys*|cygwin*) ;;
  *)
    monta "$T/decoy" 1
    F="$T/decoy/.claude/skills/f1.md"
    printf 'segredo real\n' > "$F"
    printf 'conteudo 1\n' > "$F	decoy"
    mkdir -p "$(printf '%s\n.claude/skills' "$F")"
    printf 'conteudo 1\n' > "$(printf '%s\n.claude/skills/f1.md' "$F")"
    git -C "$T/decoy" add .claude/skills
    (cd "$T/decoy" && bash -c '. "$1"; segredo_dispensaveis_indice >"$2"' _ "$RAIZ/.claude/skills/mergex/scripts/segredo-dispensa.sh" "$T/lista-decoy")
    [ ! -s "$T/lista-decoy" ]; afirma "caminho com TAB ou quebra de linha nao dispensa o arquivo real" $?
    ;;
esac

evento() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git commit -m x"}}' "$1"; }
ms() { perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }

ini="$(ms)"; evento "$T/cem" | bash "$HOOK" >/dev/null 2>&1; rc=$?; fim="$(ms)"; d=$((fim - ini))
echo "  hook com dispensa: rc $rc, $d ms"
[ "$rc" = 0 ] && [ "$d" -lt 9000 ]; afirma "hook com 300 arquivos dispensados fecha em menos de 9 s" $?

ini="$(ms)"; evento "$T/cem" | SEG_DISP_TESTE_PRAZO=1 bash "$HOOK" >/dev/null 2>&1; rc=$?; fim="$(ms)"; d=$((fim - ini))
echo "  hook com a dispensa vencida: rc $rc, $d ms"
[ "$d" -lt 9000 ]; afirma "dispensa vencida e varredura completa fecham em menos de 9 s" $?

printf '\n  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
