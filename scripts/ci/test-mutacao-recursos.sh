#!/usr/bin/env bash
#
# As bancadas de mutação têm de caber na máquina de quem as roda: cada mutante copia
# o repositório e roda uma bancada, e 85 de uma vez, sem teto, travavam o WSL (DM-292).
#
#   - nenhuma cópia fica no diretório temporário: `copia` roda em `$(...)`, e a variável
#     que ela anotasse se perdia com o subshell, então o trap não limpava nada;
#   - no máximo quatro mutantes rodam ao mesmo tempo.
#
# Uso: bash scripts/ci/test-mutacao-recursos.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OK=0; FALHOU=0
ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

RAIZ="$(mktemp -d)" || exit 1
trap 'rm -rf "$RAIZ"' EXIT

# mede <bancada> <id>... — roda os mutantes num temporário próprio, contando os que
# estão em voo: a cópia com mutacao.log e ainda sem o rc.
mede() {
  local bancada="$1" t pid maximo=0 n d; shift
  t="$RAIZ/${bancada%.sh}"; mkdir -p "$t"
  ( cd "$REPO" && TMPDIR="$t" bash "scripts/ci/$bancada" "$@" ) > "$t.saida" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    n=0
    while IFS= read -r d; do
      [ -e "${d%/mutacao.log}/rc" ] || n=$((n+1))
    done < <(find "$t" -name mutacao.log 2>/dev/null)
    [ "$n" -le "$maximo" ] || maximo="$n"
    sleep 0.1
  done
  wait "$pid"; RC=$?
  MAXIMO="$maximo"; SOBROU="$(ls -A "$t" | wc -l | tr -d ' ')"
}

confere() { # <bancada> <id>...
  local bancada="$1"; shift
  echo "$bancada: $# mutantes do validador"
  mede "$bancada" "$@"
  [ "$RC" = 0 ] && ok "os mutantes morreram" || { falha "rc=$RC"; sed 's/^/        /' "$RAIZ/${bancada%.sh}.saida" | tail -8; }
  [ "$MAXIMO" -ge 2 ] && ok "rodam em paralelo (no máximo $MAXIMO)" || falha "não vi paralelo: máximo $MAXIMO"
  [ "$MAXIMO" -le 4 ] && ok "no máximo quatro ao mesmo tempo" || falha "$MAXIMO mutantes ao mesmo tempo"
  [ "$SOBROU" = 0 ] && ok "nada sobra no temporário" || falha "sobraram $SOBROU entradas no temporário"
}

confere mutacao-atencao-metodo.sh M1b M2b M3b M7 M8 M16 M17 M18
confere mutacao-trava-e1.sh M13 M14 M15 M16 M17

echo "Todas as bancadas: a cópia não é anotada em variável, e o que roda em paralelo tem teto"
for f in "$REPO"/scripts/ci/mutacao-*.sh; do
  n="$(basename "$f")"
  if grep -q 'TMPS="\$TMPS' "$f"; then falha "$n anota a cópia em variável"; else ok "$n não anota a cópia em variável"; fi
  if grep -Eq '^[[:space:]]*(roda |\().*&[[:space:]]*$' "$f" && ! grep -Eq 'ativos' "$f"; then
    falha "$n dispara em paralelo sem teto"
  else ok "$n sem paralelo fora do teto"; fi
done

echo
printf '%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
