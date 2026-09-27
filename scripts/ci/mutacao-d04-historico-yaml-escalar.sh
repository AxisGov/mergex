#!/usr/bin/env bash
# Controle sem mutação do P0.2 / reparo D-04 (DM-176).
# Cada mutante altera uma cópia temporária e precisa fazer a bancada D-04 ou
# o validador de contrato falhar. A bancada e as mutações D-02 continuam
# valendo à parte (mutacao-d02-historico-inicial.sh).
#
# Uso: bash scripts/ci/mutacao-d04-historico-yaml-escalar.sh [M1 M2 ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERSISTE='.claude/skills/mergex/scripts/persistir-metodo.sh'
DECISOES='.claude/skills/mergex/DECISOES-DA-SKILL.md'
BANCADA='scripts/ci/test-d04-historico-yaml-escalar.sh'
CONTRATO='scripts/ci/validate-mergex-contract.sh'
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

troca() { # <arquivo> <linha exata> <linha nova> — todas as ocorrências
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || return 1
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}
troca_n() { # <arquivo> <linha exata> <linha nova> <ocorrencia>
  local arq="$1" antes="$2" depois="$3" n="$4"
  [ "$(grep -Fxc -- "$antes" "$arq")" -ge "$n" ] || return 1
  A="$antes" B="$depois" N="$n" awk '$0 == ENVIRON["A"] && ++k == ENVIRON["N"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}
troca_trecho() { # <arquivo> <trecho literal> <novo> — dentro de uma linha
  local arq="$1"
  grep -Fq -- "$2" "$arq" || return 1
  A="$2" B="$3" awk '{ p = index($0, ENVIRON["A"]); if (p) $0 = substr($0, 1, p - 1) ENVIRON["B"] substr($0, p + length(ENVIRON["A"])); print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

DUPLA='        gsub("\047\047", "\047", s)'
ASPA='        else if (c == "\"") r = r "\""'
BARRA='        else if (c == "\\") r = r "\\"'
SOLIDUS='        else if (c == "/") r = r "/"'
ESPACO='        else if (c == " ") r = r " "'
HEXA='        else if (c == "x") { r = r ascii_hexa(substr(s, i + 1, 2), v); i += 2 }'
QUEBRA='        else if (c == "\t" || index("0abtnvfreNLP", c)) erro("escape que produz controle ou quebra de linha (campos são de uma linha): " v)'
FORA='        else if (c == "u" || c == "U" || c == "_") erro("escape YAML fora do subconjunto suportado pelo leitor: " v)'
INVALIDO='        else erro("escape inválido em texto entre aspas duplas: " v)'
MIOLO='      q = substr(v, 1, 1); s = substr(v, 2, length(v) - 2); r = ""'
MIOLO_CRU='      q = substr(v, 1, 1); s = substr(v, 2, length(v) - 2); r = ""; if (ENVIRON["MUTANTE_CRU"]) return s'
FINAL='  ler_historico "$RAIZ/$caminho" > "$TMP_HIST/final" \'
BASE='  ler_historico "$TMP_HIST/head.md" > "$TMP_HIST/base" \'

M1() { # volta a não decodificar ''
  troca "$PERSISTE" "$DUPLA" '        s = s'
}
M2() { # volta a não decodificar \"
  troca "$PERSISTE" "$ASPA" '        else if (c == "\"") r = r "\\\""'
}
M3() { # volta a não decodificar \x20 (conserva \x como texto)
  troca "$PERSISTE" "$HEXA" '        else if (c == "x") r = r "\\x"'
}
M4() { # \n entre aspas duplas volta a canonicalizar como barra + n
  troca "$PERSISTE" "$QUEBRA" '        else if (c == "\t" || index("0abtnvfreNLP", c)) r = r "\\" c'
}
M5() { # \n entre aspas simples passa a ser quebra de linha
  troca "$PERSISTE" "$DUPLA" '        gsub("\047\047", "\047", s); gsub(/\\n/, "\n", s)'
}
M6() { # base decodifica, final não
  troca "$PERSISTE" "$MIOLO" "$MIOLO_CRU" \
    && troca "$PERSISTE" "$FINAL" '  export MUTANTE_CRU=1; ler_historico "$RAIZ/$caminho" > "$TMP_HIST/final" \'
}
M7() { # final decodifica, base não
  troca "$PERSISTE" "$MIOLO" "$MIOLO_CRU" \
    && troca "$PERSISTE" "$BASE" '  export MUTANTE_CRU=1; ler_historico "$TMP_HIST/head.md" > "$TMP_HIST/base" \' \
    && troca "$PERSISTE" "$FINAL" '  unset MUTANTE_CRU; ler_historico "$RAIZ/$caminho" > "$TMP_HIST/final" \'
}
M8() { # itens de sinais não passam pelo normalizador
  troca "$PERSISTE" '      if (aspas) return "s:" decodifica(v)' '      if (aspas) return "s:" substr(v, 2, length(v) - 2)'
}
M9() { # identidade usa o valor lexical, não o efetivo
  troca "$PERSISTE" '      bruto[chave] = v' '      bruto[chave] = aspas ? sem_comentario(valor) : v'
}
M10() { # escape YAML fora do subconjunto (\u, \U, \_) aceito literalmente
  troca "$PERSISTE" "$FORA" '        else if (c == "u" || c == "U" || c == "_") r = r "\\" c'
}
M11() { # DM-174 volta a ser contraditória com a DM-175
  troca_trecho "$DECISOES" 'nenhum marcador `{{...}}` do template pendente no frontmatter (inclusive em comentário dele) nem nas linhas de dados das tabelas oficiais — `{{...}}` na prosa humana explicativa é texto, não dado pendente (*parcialmente esclarecida pela DM-175*: a redação original desta célula dizia "nenhum marcador `{{...}}` do template em lugar nenhum do arquivo", o que contradizia o esclarecimento abaixo e a DM-175; corrigida no D-04 sem mudar comportamento)' \
    'nenhum marcador `{{...}}` do template em lugar nenhum do arquivo'
}
M12() { # FIRST regride: a primeira criação lê sem decodificar
  troca "$PERSISTE" "$MIOLO" "$MIOLO_CRU" \
    && troca_n "$PERSISTE" "$FINAL" '  export MUTANTE_CRU=1; ler_historico "$RAIZ/$caminho" > "$TMP_HIST/final" \' 1
}
M13() { # e8 regride: o checkpoint e8 pula a prova do HISTORICO
  troca "$PERSISTE" '[ "$ORIGEM" = sprintx ] && confere_historico_corrente' \
    '[ "$ORIGEM" = sprintx ] && [ "$CHECKPOINT" != e8 ] && confere_historico_corrente'
}
M14() { # escape inválido aceito literalmente
  troca "$PERSISTE" "$INVALIDO" '        else r = r "\\" c'
}
M15() { # \xHH aceita qualquer código (controle, DEL, fora de ASCII)
  troca "$PERSISTE" '      if (a < 32 || a > 126) erro("escape \\x fora de ASCII imprimível (campos são de uma linha): " v)' \
    '      a = a'
}
M16() { # caractere de controle cru passa no valor
  troca "$PERSISTE" '      if (controle(v)) erro("caractere de controle no valor (campos são de uma linha): " v)' \
    '      aspas = 0'
}
M17() { # célula de identidade da tabela oficial aceita controle cru
  troca "$PERSISTE" '      if (controle(c1) || controle(c2)) erro("caractere de controle em linha oficial de dados: " apara($0))' \
    '      c1 = c1'
}
M18() { # volta a não decodificar \\
  troca "$PERSISTE" "$BARRA" '        else if (c == "\\") r = r "\\\\"'
}
M19() { # volta a não decodificar \/
  troca "$PERSISTE" "$SOLIDUS" '        else if (c == "/") r = r "\\/"'
}
M20() { # volta a não decodificar \<espaço>
  troca "$PERSISTE" "$ESPACO" '        else if (c == " ") r = r "\\ "'
}

LISTA='M1|volta a não decodificar '"''"'
M2|volta a não decodificar \"
M3|volta a não decodificar \x20
M4|\n entre aspas duplas volta a ser barra + n
M5|\n entre aspas simples vira quebra de linha
M6|base decodifica, final não
M7|final decodifica, base não
M8|sinais não passam pelo normalizador
M9|identidade usa valor lexical em vez de efetivo
M10|escape fora do subconjunto aceito literalmente
M11|DM-174 continua contraditória
M12|FIRST regride (primeira criação sem decodificar)
M13|e8 regride (pula a prova do HISTORICO)
M14|escape inválido aceito literalmente
M15|\xHH aceita controle, DEL e fora de ASCII
M16|controle cru passa no valor
M17|célula de identidade da tabela aceita controle cru
M18|volta a não decodificar \\
M19|volta a não decodificar \/
M20|volta a não decodificar \<espaço>'

verifica() { # <dir> — 0 só se a bancada D-04 e o contrato passam
  ( cd "$1" && bash "$BANCADA" && bash "$CONTRATO" )
}

FILTRAR=" $* "
FALHAS="$(mktemp)"
TMPS="$TMPS $FALHAS"
TOTAL=0

printf 'Controle — cópia SEM mutação: a bancada D-04 e o contrato têm que passar\n'
controle="$(copia)"
if verifica "$controle" > "$controle/controle.log" 2>&1; then
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
  if verifica "$d" >/dev/null 2>&1; then
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
