#!/usr/bin/env bash
# Casos do lint-consumidor-precoce: recusa o consumidor que sai cedo e aceita as formas certas.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$RAIZ/scripts/ci/lint-consumidor-precoce.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok=0; falhou=0

caso() { # caso <nome> <0 aceita | 1 recusa> <linha de shell>
  rm -rf "$T/c"; mkdir -p "$T/c/skills/x" "$T/c/hooks/testes"
  printf '#!/usr/bin/env bash\n%s\n' "$3" > "$T/c/skills/x/a.sh"
  bash "$LINT" "$T/c" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$2" ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"
  else falhou=$((falhou+1)); printf '  FALHA %s (rc %s, esperado %s)\n' "$1" "$rc" "$2"; fi
}

caso "grep -q depois de pipe"        1 'printf "%s" "$x" | grep -q a'
caso "grep -Fxq depois de pipe"      1 'cut -f1 "$f" | grep -Fxq -- "$id"'
caso "head depois de pipe"           1 'x="$(git status | head -20)"'
caso "pipeline em duas linhas"       1 $'printf "%s" "$x" \\\n  | grep -q a'
caso "here-string"                   0 'grep -q a <<<"$x"'
caso "grep lendo o arquivo"          0 'grep -q a "$f"'
caso "grep sem -q le tudo"           0 'cut -f1 "$f" | grep -Fx -- "$id" >/dev/null'
caso "awk NR no lugar de head"       0 "git status | awk 'NR <= 20'"
caso "texto entre aspas simples"     0 "echo 'use x | grep -q y'"
caso "ou logico nao e pipe"          0 'a || grep -q b "$f"'

printf '\n  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
