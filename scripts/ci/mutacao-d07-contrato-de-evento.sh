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
MUTACAO='scripts/ci/mutacao-d07-contrato-de-evento.sh'
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d obrigatorio
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  # `pipefail` torna o status do pipeline o da primeira etapa que falhou, mas
  # quem o lê tem que ser o `if`: um `printf` depois do pipeline devolveria
  # sucesso e a cópia parcial seguiria para a medição do mutante.
  if ! ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
       | ( cd "$d" && tar -xf - ); then
    printf 'FALHA cópia da árvore falhou: git ls-files | tar (%s)\n' "$d" >&2
    return 1
  fi
  # Nem toda cópia parcial vem com status de falha: `xargs` pode partir a lista
  # em várias chamadas de `tar`, e o `tar -xf` para no primeiro fim de arquivo
  # do fluxo concatenado — árvore incompleta, status zero. Conferir os arquivos
  # de que o mutante e a medição dependem fecha esse caminho também. Não é
  # contagem exata de propósito: `tar` de macOS acrescenta membros `._*` ao
  # arquivar, e um total comparado quebraria a bancada lá sem haver defeito.
  for obrigatorio in "$COMMITS" "$PR" "$ESTADO" "$ABERTURA" "$DECISOES" \
                     "$BASE_SH" "$BANCADA" "$CONTRATO" "$MUTACAO"; do
    if [ ! -s "$d/$obrigatorio" ]; then
      printf 'FALHA cópia da árvore falhou: %s ausente ou vazio em %s\n' \
        "$obrigatorio" "$d" >&2
      return 1
    fi
  done
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
M14() { # a justificativa volta a afirmar o commit que o E0 e o E7 não fizeram
  troca_trecho "$ESTADO" 'histórico pelo fechamento final do E8' \
    'histórico, e foi gravado e commitado de todo modo'
}
M15() { # a âncora do aborto da cópia sai do arranjo, e o aborto fica sem diagnóstico
  # Este mutante apaga as duas linhas de diagnóstico de `copia()` — e só elas.
  # `copia()` continua abortando pelos dois `return 1`: o que cai é a âncora
  # estática que o validador de contrato exige, e é por ela que o M15 morre.
  # Quem mede o aborto em si é o arranjo executável da bancada D-07 (a seção
  # "a bancada de mutação aborta quando a cópia da árvore falha"), não aqui.
  # O literal vem partido (`falh''ou`) para o `remove_linha` não apagar também
  # esta linha, o que deixaria a cópia do arranjo sem sintaxe e mataria o
  # mutante por um motivo que não é o medido.
  remove_linha "$MUTACAO" 'cópia da árvore falh''ou'
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
M13|a varredura da bancada deixa de ver os exemplos
M14|a justificativa volta a afirmar commit do ENTREGA.md
M15|a âncora do aborto da cópia sai do arranjo da mutação'

verifica() { # <dir> — 0 só se a bancada D-07 e o contrato passam
  # MERGEX_D07_EM_COPIA avisa a bancada de que ela está rodando dentro de uma
  # cópia: a seção que invoca esta bancada de mutação se cala ali, e a recursão
  # fica com fundo.
  ( cd "$1" && MERGEX_D07_EM_COPIA=1 bash "$BANCADA" && MERGEX_D07_EM_COPIA=1 bash "$CONTRATO" )
}

FILTRAR=" $* "
FALHAS="$(mktemp)"
TMPS="$TMPS $FALHAS"
TOTAL=0

printf 'Controle — cópia SEM mutação: a bancada D-07 e o contrato têm que passar\n'
controle="$(copia)" || exit 1
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
  if ! d="$(copia)"; then
    printf 'FALHA %-4s cópia da árvore não pôde ser montada — %s\n' "$id" "$desc" >&2
    exit 1
  fi
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
