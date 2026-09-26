#!/usr/bin/env bash
# Controle sem mutação do P0.2 / reparo D-02.
# Cada mutante altera uma cópia temporária e precisa fazer a bancada D-02 falhar.
#
# Uso: bash scripts/ci/mutacao-d02-historico-inicial.sh [M1 M2 ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERSISTE='.claude/skills/mergex/scripts/persistir-metodo.sh'
FECHA='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
BANCADA='scripts/ci/test-d02-historico-inicial.sh'
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

CHAMADA='    confere_historico_inicial'
RECUSA="    para 'HISTORICO global untracked não tem base para provar ownership'"

M1() { # mantém a rejeição absoluta de untracked
  troca "$PERSISTE" "$CHAMADA" "$RECUSA"
}
M2() { # aceita qualquer HISTORICO untracked
  troca "$PERSISTE" "$CHAMADA" '    : # mutante: sem prova integral'
}
M3() { # não verifica a ausência em HEAD
  troca "$PERSISTE" '  [ -z "$presenca" ] \' '  true \'
}
M4() { # aceita entrada de outro trabalho
  troca "$PERSISTE" '      if (secao == "entradas" && chave == "trabalho_id" && v != trabalho)' \
    '      if (0)'
}
M5() { # aceita mistura: só a primeira entrada é conferida
  troca "$PERSISTE" '      if (secao == "entradas" && chave == "trabalho_id" && v != trabalho)' \
    '      if (secao == "entradas" && chave == "trabalho_id" && (n_trab++ ? 0 : v != trabalho))'
}
M6() { # aceita task estranha: basta ter formato de task
  troca "$PERSISTE" '        if (!(v in concluida)) erro("entrada de task que não é concluída do trabalho corrente: " v)' \
    '        if (v !~ /^T-/) erro("mutante")'
}
M7() { # aceita kind errado
  troca "$PERSISTE" '      if (valor_topo["kind"] != "estimativa_historico") { print "kind não é estimativa_historico"; exit 1 }' \
    '      if (0) { }'
}
M8() { # aceita header trabalho_id não-null
  troca "$PERSISTE" '      if (valor_topo["trabalho_id"] != "null") { print "trabalho_id do cabeçalho não é null"; exit 1 }' \
    '      if (0) { }'
}
M9() { # aceita symlink
  troca "$PERSISTE" "    [ ! -L \"\$parcial\" ] || para 'HISTORICO global inicial passa por link simbólico'" \
    '    : # mutante'
}
M10() { # E1 absorve o HISTORICO como produto
  troca "$FECHA" '    if grep -Fxq -- "$caminho" "$CATALOGO_TMP" && [ ! -L "$caminho" ]; then' \
    '    if grep -Fxq -- "$caminho" "$CATALOGO_TMP" && [ ! -L "$caminho" ] && [ "$caminho" != docs/sprintx/estimativas/HISTORICO.md ]; then'
}
M11() { # primeira criação pula o gate de segredo
  troca "$PERSISTE" "printf '%s' \"\$ENTRADA_SEGREDO\" | bash \"\$SEGREDO_SH\" \\" \
    "[ -z \"\$(git ls-tree --name-only HEAD -- docs/sprintx/estimativas/HISTORICO.md)\" ] || printf '%s' \"\$ENTRADA_SEGREDO\" | bash \"\$SEGREDO_SH\" \\"
}
M12() { # primeira criação aceita stage prévio
  troca "$PERSISTE" '  if [ -n "$(git diff --cached --name-only 2>/dev/null)" ]; then' \
    '  if [ -n "$(git diff --cached --name-only 2>/dev/null)" ] && git ls-files --error-unmatch -- docs/sprintx/estimativas/HISTORICO.md >/dev/null 2>&1; then'
}
M13() { # caminho tracked deixa remover evidência antiga
  troca "$PERSISTE" "      -*) para 'HISTORICO global remove ou reescreve evidência existente' ;;" \
    '      -*) continue ;;'
}
M14() { # e8 continua rejeitando a primeira criação válida
  troca "$PERSISTE" "$CHAMADA" "    [ \"\$CHECKPOINT\" != e8 ] || para 'mutante'; confere_historico_inicial"
}
M15() { # entrada duplicada aceita
  troca "$PERSISTE" '        if (v in registrada) erro("entrada duplicada para a task: " v)' '        # mutante'
}
M16() { # linha de tabela de outro trabalho aceita
  troca "$PERSISTE" '        if (c1 != trabalho) erro("linha da tabela de entradas de outro trabalho: " c1)' '        # mutante'
}
M17() { # calibração vira buraco: qualquer chave passa
  troca "$PERSISTE" '        if (!(chave in campo_calibracao)) erro("calibração com chave fora do contrato: " chave)' \
    '        # mutante'
}

LISTA='M1|mantém rejeição absoluta de untracked
M2|aceita qualquer HISTORICO untracked
M3|não verifica ausência em HEAD
M4|aceita entrada de outro trabalho
M5|aceita mistura de trabalhos
M6|aceita task estranha
M7|aceita kind errado
M8|aceita header trabalho_id não-null
M9|aceita symlink
M10|E1 absorve HISTORICO como produto
M11|primeira criação pula gate de segredo
M12|primeira criação aceita stage prévio
M13|caminho tracked deixa remover evidência antiga
M14|e8 continua rejeitando primeira criação válida
M15|aceita entrada duplicada
M16|aceita linha de tabela de outro trabalho
M17|calibração aceita chave fora do contrato'

FILTRAR=" $* "
FALHAS="$(mktemp)"
TMPS="$TMPS $FALHAS"
TOTAL=0

printf 'Controle — cópia SEM mutação: a bancada D-02 tem que passar\n'
controle="$(copia)"
if ( cd "$controle" && bash "$BANCADA" > controle.log 2>&1 ); then
  printf 'ok    controle verde\n\n'
else
  printf 'FALHA controle sem mutação\n' >&2
  cat "$controle/controle.log" >&2
  exit 1
fi

while IFS='|' read -r id desc; do
  if [ "$FILTRAR" != '  ' ]; then case "$FILTRAR" in *" $id "*) ;; *) continue ;; esac; fi
  TOTAL=$((TOTAL + 1))
  d="$(copia)"
  if ! ( cd "$d" && "$id" ); then
    printf 'FALHA %-4s mutação não aplicada — %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
    continue
  fi
  if ( cd "$d" && bash "$BANCADA" >/dev/null 2>&1 ); then
    printf 'VIVO  %-4s %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
  else
    printf 'morto %-4s %s\n' "$id" "$desc"
  fi
  rm -rf "$d"
done <<EOF
$LISTA
EOF

if [ -s "$FALHAS" ]; then
  printf '%s mutante(s) sobreviveram ou não foram aplicados\n' "$(wc -l < "$FALHAS" | tr -d ' ')" >&2
  exit 1
fi
printf '%s mutantes mortos\n' "$TOTAL"
