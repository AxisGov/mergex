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
# A prova de ownership mora no comparador compartilhado (DM-175): a mesma
# linha decide a primeira criação (base vazia) e o acréscimo tracked.
DONO='      if ($2 != trabalho) erro("entrada de outro trabalho: " $2 " " $3)'
M4() { # aceita entrada de outro trabalho
  troca "$PERSISTE" "$DONO" '      # mutante'
}
M5() { # aceita mistura: só a primeira entrada nova é conferida
  troca "$PERSISTE" "$DONO" \
    '      if ((n_trab++ ? 0 : $2 != trabalho)) erro("entrada de outro trabalho: " $2 " " $3)'
}
M6() { # aceita task estranha: basta ter formato de task
  troca "$PERSISTE" '      if (!($3 in concluida)) erro("entrada de task que não é concluída do trabalho corrente: " $3)' \
    '      if ($3 !~ /^T-/) erro("mutante")'
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
  troca "$PERSISTE" '    [ ! -L "$parcial" ] || para "$1 passa por link simbólico"' \
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
M13() { # caminho tracked deixa remover evidência antiga (linha da tabela oficial)
  troca "$PERSISTE" '        if (!(k in linha_final)) erro("remove ou reescreve evidência existente: linha " linha_antiga[k] " da tabela de Entradas removida")' \
    '        continue'
}
M14() { # e8 continua rejeitando a primeira criação válida
  troca "$PERSISTE" "$CHAMADA" "    [ \"\$CHECKPOINT\" != e8 ] || para 'mutante'; confere_historico_inicial"
}
M15() { # entrada duplicada aceita
  troca "$PERSISTE" '        if (k in registrada) erro("entrada duplicada: " bruto["trabalho_id"] " " bruto["task_id"])' \
    '        # mutante'
}
M16() { # linha de tabela de outro trabalho aceita: linha oficial sem entrada correspondente
  troca "$PERSISTE" '        if (!(k in final)) erro("linha da tabela de Entradas sem entrada no frontmatter: " linha_final[k])' \
    '        continue'
}
M17() { # calibração vira buraco: qualquer chave passa
  troca "$PERSISTE" '        if (!(chave in campo_calibracao)) erro("calibração com chave fora do contrato: " chave)' \
    '        # mutante'
}

# Alinhamento ao contrato publicado da sprintx: o relaxamento sintático não
# pode voltar a ser restrição de formato, nem virar buraco de ownership.
M18() { # volta a exigir sinais inline
  troca "$PERSISTE" '      if (!aspas && v == "") {' \
    '      if (!aspas && v == "") { erro("sinais fora do formato de lista: " v)'
}
M19() { # volta a varrer task id em toda a prosa
  troca "$PERSISTE" '    estado == "corpo" {' \
    '    estado == "corpo" { if ($0 !~ /^[[:space:]]*\|/ && $0 ~ /T-[0-9]+\.[0-9]+/) erro("cita task: " $0)'
}
M20() { # volta a proibir qualquer tabela humana extra
  troca "$PERSISTE" '        else tabela = "humana"' \
    '        else erro("tabela fora do contrato no corpo: " c1)'
}
M21() { # deixa marcador {{...}} passar no frontmatter
  troca "$PERSISTE" '    estado == "fm" && marcador() { erro("marcador do template não substituído no frontmatter: " apara($0)) }' \
    '    estado == "fm" && 0 { }'
}
M22() { # tabela oficial aceita outro trabalho: a seção Entradas deixa de ser reconhecida
  troca "$PERSISTE" '      if (texto == "Entradas") { secao_corpo = "entradas"; oficial_vista = 0 }' \
    '      if (0) { }'
}
M23() { # tabela oficial aceita outro trabalho: sub-heading tira a tabela da seção
  troca "$PERSISTE" '      if (nivel > 2) return' '      # mutante'
}
M24() { # tabela oficial aceita outro trabalho: cabeçalho renomeado vira tabela humana
  troca "$PERSISTE" '        else if (secao_corpo == "entradas" && !oficial_vista)' '        else if (0)'
}
M25() { # frontmatter aceita outro trabalho: "#" colado ao valor vira comentário
  troca "$PERSISTE" '      if (match(v, /[[:space:]]#/)) v = substr(v, 1, RSTART - 1)' \
    '      if (match(v, /#/)) v = substr(v, 1, RSTART - 1)'
}
M27() { # tabela oficial aceita outro trabalho: sem a barra inicial escapa da prova
  troca "$PERSISTE" '        erro("tabela de ## Entradas sem a barra inicial do formato publicado")' '        p = p'
}
M26() { # frontmatter aceita outro trabalho: item de sinais esconde par chave:valor
  troca "$PERSISTE" '      if (!sinal_valido(v)) erro("sinais com item inválido ou ambíguo: " apara(v))' \
    '      v = v'
}

# DM-175 — HISTORICO tracked: append-only quanto às entradas, não aos bytes.
M28() { # tracked volta a rejeitar recalibração
  troca "$PERSISTE" '    FILENAME == ARGV[1] { next }' \
    '    FILENAME == ARGV[1] { if ($1 == "C") derivada[$0] = 1; next }
    $1 == "C" && !($0 in derivada) { erro("remove ou reescreve evidência existente: calibração") }'
}
M29() { # entrada histórica pode desaparecer
  troca "$PERSISTE" '        if (!(k in final)) erro("remove ou reescreve evidência existente: entrada " nome[k] " removida")' \
    '        if (!(k in final)) continue'
}
M30() { # entrada histórica pode mudar real (e qualquer outro campo)
  troca "$PERSISTE" '        if (final[k] != antiga[k]) erro("remove ou reescreve evidência existente: entrada " nome[k] " reescrita")' \
    '        if (0) { }'
}
M31() { # entrada histórica pode mudar trabalho: identidade ignora trabalho_id
  troca "$PERSISTE" '    function chave(t, k) { return t SUBSEP k }' \
    '    function chave(t, k) { return k }'
}
M32() { # nova entrada de outro trabalho passa quando já existe base tracked
  troca "$PERSISTE" '      if (!(k in antiga)) nova[++n_nova] = $0' \
    '      if (!(k in antiga) && !n_antiga) nova[++n_nova] = $0'
}
M33() { # placeholder em linha oficial de dados passa
  troca "$PERSISTE" '      if (marcador()) erro("marcador do template não substituído em linha oficial de dados: " apara($0))' \
    '      # mutante'
}
M34() { # literal {{...}} em prosa volta a barrar
  troca "$PERSISTE" '    { sub(/\r$/, "") }' \
    '    { sub(/\r$/, ""); if (marcador()) erro("marcador do template não substituído: " apara($0)) }'
}
M35() { # calibração final inválida passa
  troca "$PERSISTE" '      confere_calibracao()' '      # mutante'
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
M13|caminho tracked deixa remover evidência antiga (linha oficial)
M14|e8 continua rejeitando primeira criação válida
M15|aceita entrada duplicada
M16|aceita linha de tabela de outro trabalho
M17|calibração aceita chave fora do contrato
M18|volta a exigir sinais inline
M19|volta a varrer task id em toda a prosa
M20|volta a proibir qualquer tabela humana extra
M21|deixa marcador {{...}} passar no frontmatter
M22|tabela oficial aceita outro trabalho (seção não reconhecida)
M23|tabela oficial aceita outro trabalho (sub-heading)
M24|tabela oficial aceita outro trabalho (cabeçalho renomeado)
M25|frontmatter aceita outro trabalho (# colado vira comentário)
M26|frontmatter aceita outro trabalho (sinais esconde chave:valor)
M27|tabela oficial aceita outro trabalho (sem barra inicial)
M28|tracked volta a rejeitar recalibração
M29|entrada histórica pode desaparecer
M30|entrada histórica pode mudar real
M31|entrada histórica pode mudar trabalho
M32|nova entrada de outro trabalho passa no tracked
M33|placeholder em linha oficial de dados passa
M34|literal {{...}} em prosa volta a barrar
M35|calibração final inválida passa'

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
