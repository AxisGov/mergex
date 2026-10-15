#!/usr/bin/env bash
# Controle e dez mutacoes dirigidas do P0.2-C7-B / M3.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER='scripts/ci/lib/fixture-git.sh'
HOOK='.claude/hooks/mergex/arquivo-fora-do-plano.sh'
TRAVA='.claude/skills/mergex/scripts/trava-do-e1.sh'
RUNBOOK='.claude/skills/mergex/references/01-commits.md'
TESTE='scripts/ci/test-m3-fixture-lock-lf.sh'
TMP_RAIZ="$(mktemp -d)"
RESULTADOS="$TMP_RAIZ/resultados"
trap 'rm -rf "$TMP_RAIZ"' EXIT
mkdir -p "$RESULTADOS"

copia() { # <id>
  local id d
  id="$1"
  d="$TMP_RAIZ/$id"
  mkdir -p "$d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - ) || return 1
  (
    cd "$d" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config core.autocrlf false
    git add -A && git commit -qm fixture || exit 1
  ) || return 1
  printf '%s\n' "$d"
}

troca() { # <arquivo> <linha exata> <linha nova>
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || return 1
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

M1() { troca "$HELPER" '  git switch -q "$@" || return 1' '  git switch -q "$@" || true # mutante: ignora retorno'; }
M2() { troca "$HELPER" '  [ "$atual" = "$esperado" ] || return 1' '  : # mutante: nao confere a branch'; }
M3() { troca "$HELPER" '  [ "$#" -eq 0 ] || git restore --worktree -- "$@"' '  : # mutante: tracked sujo atravessa cenarios'; }
M4() { troca "$HOOK" '  eh_historico_global_sprintx "$arquivo" && continue' '  false && continue # mutante: HISTORICO vira desvio'; }
M5() { rm -f .gitattributes; }
M6() { troca .gitattributes '*.sh text eol=lf' '*.sh text'; }
M7() { troca "$TRAVA" '  if ! mkdir "$trava" 2>/dev/null; then' '  if ! mkdir "$trava" 2>/dev/null; then
    rm -f "$trava/dono"; rmdir "$trava"; mkdir "$trava" # mutante: remove lock velho'; }
M8() { troca "$TRAVA" '  if ! mkdir "$trava" 2>/dev/null; then' '  if ! mkdir "$trava" 2>/dev/null; then
    if ! git diff --cached --quiet; then rm -f "$trava/dono"; rmdir "$trava"; mkdir "$trava"; fi # mutante: remove com stage'; }
M9() { troca "$RUNBOOK" "   rm -f -- '<caminho-exato-da-trava>/dono'" "   rm -f -- '<caminho-exato-da-trava>'/* # mutante: glob"; }
M10() { troca "$TESTE" "    if LC_ALL=C grep -q \$'\\r' \"\$dir/\$f\"; then" '    if false; then # mutante: nao inspeciona bytes CR'; }

LISTA='M1|fixture|ignora retorno nao zero do switch
M2|fixture|nao confere a branch resultante
M3|fixture|nao restaura tracked entre cenarios
M4|historico|converte HISTORICO em desvio
M5|lf|remove .gitattributes
M6|lf|remove eol=lf da politica
M7|lock|auto-remove lock velho
M8|lock|auto-remove lock com stage
M9|contract|usa glob no runbook
M10|contract|remove scan byte a byte de CRLF'

rodar_grupo() { # <grupo>
  case "$1" in
    contract) bash scripts/ci/validate-mergex-contract.sh >/dev/null 2>&1 ;;
    *) bash scripts/ci/test-m3-fixture-lock-lf.sh "$1" >/dev/null 2>&1 ;;
  esac
}

printf 'Controle - copia sem mutacao\n'
controle="$(copia controle)" || { printf 'FALHA ao copiar controle\n' >&2; exit 1; }
if ( cd "$controle" && bash scripts/ci/test-m3-fixture-lock-lf.sh todos > controle.log 2>&1 \
  && bash scripts/ci/validate-mergex-contract.sh >> controle.log 2>&1 ); then
  printf 'ok    controle verde\n\n'
else
  printf 'FALHA controle sem mutacao\n' >&2
  cat "$controle/controle.log" >&2
  exit 1
fi

executar() { # <id> <grupo> <descricao>
  local id="$1" grupo="$2" desc="$3" d
  d="$(copia "$id")" || { printf 'ERRO|%s|%s\n' "$id" "$desc" > "$RESULTADOS/$id"; return; }
  if ! ( cd "$d" && "$id" ); then
    printf 'ERRO|%s|%s\n' "$id" "$desc" > "$RESULTADOS/$id"
    return
  fi
  if ( cd "$d" && rodar_grupo "$grupo" ); then
    printf 'VIVA|%s|%s\n' "$id" "$desc" > "$RESULTADOS/$id"
  else
    printf 'MORTA|%s|%s\n' "$id" "$desc" > "$RESULTADOS/$id"
  fi
}

ativos=0
while IFS='|' read -r id grupo desc; do
  ( executar "$id" "$grupo" "$desc" ) &
  ativos=$((ativos + 1))
  if [ "$ativos" -eq 4 ]; then wait; ativos=0; fi
done <<EOF
$LISTA
EOF
wait

mortas=0; vivas=0; erros=0
while IFS='|' read -r estado id desc; do
  case "$estado" in
    MORTA) mortas=$((mortas + 1)); printf 'morta %-4s %s\n' "$id" "$desc" ;;
    VIVA) vivas=$((vivas + 1)); printf 'VIVA  %-4s %s\n' "$id" "$desc" ;;
    *) erros=$((erros + 1)); printf 'ERRO  %-4s %s\n' "$id" "$desc" ;;
  esac
done < <(cat "$RESULTADOS"/M* | LC_ALL=C sort -t'|' -k2,2V)

printf '\n%d morta(s), %d viva(s), %d erro(s)\n' "$mortas" "$vivas" "$erros"
[ "$mortas" -eq 10 ] && [ "$vivas" -eq 0 ] && [ "$erros" -eq 0 ]
