#!/usr/bin/env bash
# Controle sem mutação de P0.2-C7-B / M1.
# Cada mutante altera uma cópia temporária e precisa fazer a bancada M1 falhar.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OWN='.claude/skills/mergex/scripts/ownership-da-task.sh'
FECHA='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

troca() { # <arquivo> <linha exata> <linha nova>
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || return 1
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

M1() {
  troca "$OWN" '  arqs="$(find "$pasta" -name tasks.md -not -path '\''*/node_modules/*'\'' 2>/dev/null)"' \
    '  pasta="$(cd "$pasta/../../.." 2>/dev/null && pwd)"; arqs="$(find "$pasta" -name tasks.md -not -path '\''*/node_modules/*'\'' 2>/dev/null)"'
}
M2() {
  troca "$OWN" '      canonico="$raiz/docs/sprintx/features/$trabalho"' \
    '      canonico="$(find "$raiz/docs/sprintx/features" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)"'
}
M3() {
  troca "$FECHA" '  [ -f "$OWNERSHIP_SH" ] || para 9 '\''PARADO — instalação MergeX incompleta'\'' \' \
    '  [ -f "$OWNERSHIP_SH" ] || return 0; : || para 9 '\''PARADO — instalação MergeX incompleta'\'' \'
}
M4() {
  troca "$OWN" '  if [ "$plano_rc" != 0 ]; then' \
    '  if [ "$plano_rc" != 0 ]; then printf '\''ownership=n/a\n'\''; return 0 # mutante: plano ausente vira n/a'
}
M5() {
  troca "$FECHA" '  [ "$task_msg" = "$TASK" ] || para "$codigo" "PARADO — rodapé $fonte divergente" \' \
    '  [ -n "$task_msg" ] || para "$codigo" "PARADO — rodapé $fonte divergente" \'
}
M6() {
  troca "$FECHA" '  [ "$trabalho_msg" = "$TRABALHO" ] || para "$codigo" "PARADO — rodapé $fonte divergente" \' \
    '  [ -n "$trabalho_msg" ] || para "$codigo" "PARADO — rodapé $fonte divergente" \'
}
M7() {
  troca "$FECHA" '  [ "$qtd_task" = 1 ] || para "$codigo" "PARADO — rodapé $fonte inválido" \' \
    '  [ "$qtd_task" -ge 1 ] || para "$codigo" "PARADO — rodapé $fonte inválido" \' &&
  troca "$FECHA" '  task_msg="$(printf '\''%s\n'\'' "$rodapes" | sed -n '\''s/^Task:[[:space:]]*//p'\'')"' \
    '  task_msg="$(printf '\''%s\n'\'' "$rodapes" | sed -n '\''s/^Task:[[:space:]]*//p'\'' | head -1)"'
}
M8() {
  troca "$FECHA" '      desvios="$(printf '\''%s\n'\'' "$saida" | awk -F'\''\t'\'' '\''$1 == "desvio" { print "  - " $2 }'\'')"' \
    '      desvios="" # mutante: desvio entra no commit'
}
M9() {
  troca "$FECHA" '  case "$rc" in' \
    '  [ "$rc" = 2 ] && rc=0 # mutante: irmã entra no commit
  case "$rc" in'
}
M10() {
  troca "$FECHA" '    confere_stage_de_entrada           # 3' \
    '    carrega_contexto "$ENTREGA" # mutante: contexto antes do stage
    confere_stage_de_entrada           # 3' &&
  troca "$FECHA" '    carrega_contexto "$ENTREGA"' \
    '    : # contexto já carregado pelo mutante' &&
  troca "$FECHA" '  [ -n "$staged" ] || return 0' \
    '  [ -n "$staged" ] || return 0
  verifica_ownership "$TASK" $staged # mutante: ownership tenta explicar o stage'
}

LISTA='M1|volta ao find global
M2|escolhe o primeiro plano com task id repetido
M3|ownership ausente vira n/a
M4|plano corrente ausente vira n/a
M5|Task divergente passa
M6|Trabalho divergente passa
M7|footer duplicado passa
M8|desvio entra no commit
M9|arquivo de irmã entra no commit
M10|stage preexistente é explicado pelo ownership'

FILTRAR=" $* "
OK=0; FALHOU=0

printf 'Controle — cópia SEM mutação: a bancada M1 tem que passar\n'
controle="$(copia)"
if ( cd "$controle" && bash scripts/ci/test-m1-ownership-contextual.sh > controle.log 2>&1 ); then
  printf 'ok    controle verde\n\n'
else
  printf 'FALHA controle sem mutação\n' >&2
  cat "$controle/controle.log" >&2
  exit 1
fi

printf '%s\n' "$LISTA" | while IFS='|' read -r id desc; do
  if [ "$FILTRAR" != '  ' ]; then case "$FILTRAR" in *" $id "*) ;; *) continue ;; esac; fi
  d="$(copia)"
  if ! ( cd "$d" && "$id" ); then
    printf 'FALHA %-4s mutação não aplicada — %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$REPO/.mutacao-m1-falhas-$$"
    continue
  fi
  if ( cd "$d" && bash scripts/ci/test-m1-ownership-contextual.sh >/dev/null 2>&1 ); then
    printf 'VIVO  %-4s %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$REPO/.mutacao-m1-falhas-$$"
  else
    printf 'morto %-4s %s\n' "$id" "$desc"
  fi
  rm -rf "$d"
done

if [ -f "$REPO/.mutacao-m1-falhas-$$" ]; then
  n="$(wc -l < "$REPO/.mutacao-m1-falhas-$$" | tr -d ' ')"
  rm -f "$REPO/.mutacao-m1-falhas-$$"
  printf '%s mutante(s) sobreviveram ou não foram aplicados\n' "$n" >&2
  exit 1
fi
printf '10 mutantes mortos\n'
