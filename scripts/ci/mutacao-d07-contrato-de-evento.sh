#!/usr/bin/env bash
# Controle sem mutação do P0.2 / reparo D-07 (DM-177).
#
# Cada mutante desfaz uma parte da correção numa cópia temporária e precisa
# fazer a bancada D-07 ou o validador de contrato falhar. Mutante VIVO é buraco
# na bancada: significa que o defeito poderia voltar sem ninguém notar.
#
# Uso: bash scripts/ci/mutacao-d07-contrato-de-evento.sh [M1 M2 ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
R='.claude/skills/mergex/references'
COMMITS="$R/01-commits.md"
PR="$R/07-abertura-pr.md"
ESTADO="$R/10-estado.md"
ABERTURA="$R/00-abertura.md"
DECISOES='.claude/skills/mergex/DECISOES-DA-SKILL.md'
BASE_SH='.claude/hooks/comum/base.sh'
BANCADA='scripts/ci/test-d07-contrato-de-evento.sh'
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

troca_trecho() { # <arquivo> <trecho literal> <novo> — dentro de uma linha
  local arq="$1"
  grep -Fq -- "$2" "$arq" || return 1
  A="$2" B="$3" awk '{ p = index($0, ENVIRON["A"]); if (p) $0 = substr($0, 1, p - 1) ENVIRON["B"] substr($0, p + length(ENVIRON["A"])); print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

remove_linha() { # <arquivo> <trecho literal>
  local arq="$1"
  grep -Fq -- "$2" "$arq" || return 1
  A="$2" awk '!index($0, ENVIRON["A"])' "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

# --- Os mutantes: cada um é o defeito D-07 voltando por um caminho -----------

M1() { # o exemplo do E1 volta a agente:null
  troca_trecho "$COMMITS" '"task":"T-01.02","agente":"principal"' '"task":"T-01.02","agente":null'
}
M2() { # o exemplo do E7 volta a agente:null
  troca_trecho "$PR" '"task":null,"agente":"principal"' '"task":null,"agente":null'
}
M3() { # um agente fora do enum passa a valer
  troca_trecho "$COMMITS" '"agente":"principal"' '"agente":"implementador"'
}
M4() { # o evento inventado volta, dentro de um exemplo normativo
  troca_trecho "$ESTADO" 'o `ENTREGA.md` já tem' \
    'o rastro leva {"ts":"<ISO>","expx_eventos":1,"trabalho_id":"<id>","ferramenta":"mergex","origem":"skill","evento":"artefato_gravado","fase":"e0","task":null,"agente":"principal","resultado":"falha","detalhe":"x","arquivos":[]} e o `ENTREGA.md` já tem'
}
M5() { # a ocorrência passa a usar um evento existente com semântica falsa
  troca_trecho "$ESTADO" 'o `ENTREGA.md` já tem' \
    'o rastro leva {"ts":"<ISO>","expx_eventos":1,"trabalho_id":"<id>","ferramenta":"mergex","origem":"skill","evento":"commit_criado","fase":"e0","task":null,"agente":"principal","resultado":"falha","detalhe":"x","arquivos":[]} e o `ENTREGA.md` já tem'
}
M6() { # a bancada afrouxa o vocabulário, acrescentando o evento à própria cópia
  troca_trecho "$BANCADA" 'bloqueio_resolvido suite_executada' 'artefato_gravado bloqueio_resolvido suite_executada'
}
M7() { # a bancada afrouxa o enum de agente, aceitando null pela porta de trás
  troca_trecho "$BANCADA" "AGENTES='principal" "AGENTES='null principal"
}
M8() { # a lacuna deixa de ser registrada para o dono do contrato
  troca_trecho "$ESTADO" 'LACUNA REGISTRADA para o dono do contrato' 'Nota interna'
}
M9() { # a regra de que a falha não interrompe o fluxo é perdida
  troca_trecho "$ESTADO" '**A barra nunca é motivo de interrupção de trabalho.**' 'A barra interrompe o trabalho.'
}
M10() { # uma etapa volta a mandar a falha para o rastro
  troca_trecho "$ABERTURA" 'Falha de\ngravação é **silenciosa**' 'Registra no rastro e segue' \
    || troca_trecho "$ABERTURA" 'gravação é **silenciosa**' 'gravação vai para o rastro'
}
M11() { # a decisão sai do registro
  remove_linha "$DECISOES" '| DM-177 |'
}
M12() { # o escritor em disco dos hooks volta a agente null
  troca_trecho "$BASE_SH" 'agente:"principal"' 'agente:null'
}
M13() { # a bancada deixa de enxergar os exemplos (varredura vazia passa calada)
  troca_trecho "$BANCADA" "grep -n '\"expx_eventos\":1'" "grep -n 'ZZZ_NAO_EXISTE'"
}

LISTA='M1|exemplo do E1 volta a agente:null
M2|exemplo do E7 volta a agente:null
M3|agente fora do enum Agente
M4|evento inventado volta num exemplo normativo
M5|evento existente com semântica falsa
M6|bancada amplia o vocabulário de evento
M7|bancada amplia o enum de agente para aceitar null
M8|lacuna deixa de ser registrada para o dono do contrato
M9|regra de que a falha não interrompe é perdida
M10|uma etapa volta a mandar a falha para o rastro
M11|DM-177 sai do registro de decisões
M12|escritor dos hooks volta a agente null
M13|a varredura da bancada deixa de ver os exemplos'

verifica() { # <dir> — 0 só se a bancada D-07 e o contrato passam
  ( cd "$1" && bash "$BANCADA" && bash "$CONTRATO" )
}

FILTRAR=" $* "
FALHAS="$(mktemp)"
TMPS="$TMPS $FALHAS"
TOTAL=0

printf 'Controle — cópia SEM mutação: a bancada D-07 e o contrato têm que passar\n'
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
