#!/usr/bin/env bash
#
# Prova por mutação da classificação de artefatos de método (E3, L4/D4).
#
# Cada mutação quebra a regra de um jeito dirigido, numa CÓPIA temporária da
# árvore, e roda a verificação que tem que pegá-la. Mutação que sobrevive
# (verificação continua verde) é teste decorativo — e reprova esta suíte.
# O repositório nunca é tocado: não há nada a restaurar.
#
# Uso: bash scripts/ci/mutacao-atencao-metodo.sh [M1a M3a ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASS='.claude/skills/mergex/scripts/classificar-atencao.sh'
REF='.claude/skills/mergex/references/03-atencao-humana.md'
AGENTE='.claude/agents/revisor-diff.md'
AGENTE_OC='.opencode/agent/revisor-diff.md'

TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  # Rastreados e novos ainda não commitados; nada ignorado, nada de .git.
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

# troca <arquivo> <linha exata atual> <linha nova> — falha se a linha não existir
troca() {
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || { printf 'mutação não aplicada: linha ausente em %s\n' "$arq" >&2; return 1; }
  # ENVIRON, não -v: -v interpreta \t e a comparação deixaria de casar em silêncio.
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$arq" > "$arq.m"
  cmp -s "$arq" "$arq.m" && { rm -f "$arq.m"; printf 'mutação não aplicada: %s ficou igual\n' "$arq" >&2; return 1; }
  mv "$arq.m" "$arq"
}

# apaga <arquivo> <prefixo da linha>
apaga() {
  local arq="$1" prefixo="$2"
  grep -Fq -- "$prefixo" "$arq" || { printf 'mutação não aplicada: prefixo ausente em %s\n' "$arq" >&2; return 1; }
  awk -v p="$prefixo" 'index($0, p) == 1 { next } { print }' "$arq" > "$arq.m" && mv "$arq.m" "$arq"
}

teste()     { bash scripts/ci/test-atencao-metodo.sh > saida.log 2>&1; }
validador() { bash scripts/ci/validate-mergex-contract.sh > saida.log 2>&1; }

# ---------------------------------------------------------------------------
# As mutações: id | descrição | verificação que TEM que falhar | função que muta
# ---------------------------------------------------------------------------
M1a() { troca "$CLASS" '  if [ "$REC_CRITERIO" = L4 ]; then' '  if false; then'; }
M1b() { apaga "$REF" '| L4 |'; }
M2a() { troca "$CLASS" '  if [ "$REC_CRITERIO" = D4 ]; then' '  if false; then'; }
M2b() { apaga "$REF" '| D4 |'; }
M3a() {
  troca "$CLASS" '  # 1. OLHO OBRIGATÓRIO: critério O vence, inclusive em artefato de método.' \
    '  reconhece "$caminho"; if [ "$REC_CRITERIO" = L4 ]; then printf "%s\t%s\tL4: %s\n" "$caminho" "$FAIXA_LEITURA" "$REC_MOTIVO"; return; fi; if [ "$REC_CRITERIO" = D4 ]; then printf "%s\t%s\tD4: %s\n" "$caminho" "$FAIXA_DISPENSAVEL" "$REC_MOTIVO"; return; fi'
}
M3b() { # nos dois harnesses, para que só a guarda de ORDEM possa pegar
  local l4 a
  for a in "$AGENTE" "$AGENTE_OC"; do
    l4="$(grep -F '| L4 |' "$a" | head -1 | tr -d '\r')"
    apaga "$a" '| L4 |' || return 1
    tr -d '\r' < "$a" > "$a.lf" && mv "$a.lf" "$a"
    troca "$a" '| O1 | Arquivo em zona de risco declarada no `PERFIL.md` |' \
      "$l4"'
| O1 | Arquivo em zona de risco declarada no `PERFIL.md` |' || return 1
  done
}
M4a() {
  troca "$CLASS" '  [ "$CONTEXTO_OK" = 1 ] || { nao_reconhecido "$CONTEXTO_MOTIVO"; return; }' \
    '  case "$caminho" in docs/sprintx/*) REC_CRITERIO=L4; REC_MOTIVO="pasta docs/sprintx"; return ;; esac; [ "$CONTEXTO_OK" = 1 ] || { nao_reconhecido "$CONTEXTO_MOTIVO"; return; }'
}
M5a() {
  troca "$CLASS" '  [ "$CONTEXTO_OK" = 1 ] || { nao_reconhecido "$CONTEXTO_MOTIVO"; return; }' \
    '  if [ "$(fm "$RAIZ/$caminho" expx_tool)" = sprintx ]; then REC_CRITERIO=L4; REC_MOTIVO="expx_tool sprintx"; return; fi; [ "$CONTEXTO_OK" = 1 ] || { nao_reconhecido "$CONTEXTO_MOTIVO"; return; }'
}
M6() { # o padrão conservador deixa de ser OLHO OBRIGATÓRIO
  troca "$CLASS" '  printf '"'"'%s\t%s\tpadrão: nenhum critério bateu (%s)%s\n'"'"' "$caminho" "$FAIXA_OLHO" "$REC_MOTIVO" "$nota"' \
    '  printf '"'"'%s\t%s\tpadrão: nenhum critério bateu (%s)%s\n'"'"' "$caminho" "$FAIXA_LEITURA" "$REC_MOTIVO" "$nota"'
}
M7() { # o agente OpenCode diverge do Claude Code na regra
  troca "$AGENTE_OC" '- **O6** fala de código sem cobertura e não se aplica a artefato de método.' \
    '- **O6** também se aplica a artefato de método.'
}
M8() { # o catálogo do script ganha uma linha que o reference não tem
  troca "$CLASS" 'runx|QA.md|qa|L4|veredito e roteiro do QA' \
    'runx|QA.md|qa|L4|veredito e roteiro do QA
runx|FECHAMENTO.md|fechamento|L4|fechamento'
}
M9() { # a prova do HISTORICO passa a aceitar reescrita de linha existente
  troca "$CLASS" '      -*) PROVA_MOTIVO="remove ou reescreve linha existente: ${linha#-}"; return 1 ;;' \
    '      -*) continue ;;'
}

LISTA='M1a|remove a regra L4 do classificador|teste
M1b|remove a linha L4 do reference|validador
M2a|remove a regra D4 do classificador|teste
M2b|remove a linha D4 do reference|validador
M3a|aplica o rebaixamento antes de O1–O9 no classificador|teste
M3b|põe L4 antes de O1 na tabela do agente|validador
M4a|reconhece por curinga docs/sprintx/*|teste
M5a|aceita qualquer expx_tool: sprintx|teste
M6|padrão deixa de ser OLHO OBRIGATÓRIO|teste
M7|agente OpenCode diverge da regra|validador
M8|catálogo do script diverge do reference|validador
M9|prova do HISTORICO aceita reescrita|teste'

SELECAO=" $* "
MORTAS=0; VIVAS=0; ERROS=0
PIDS=""; IDS=""

roda() { # id desc verificacao
  local id="$1" desc="$2" verif="$3" d
  d="$(copia)"
  (
    cd "$d" || exit 3
    "$id" || exit 3
    if "$verif"; then exit 1; else exit 0; fi
  ) > "$d/mutacao.log" 2>&1
  printf '%s\n' "$?" > "$d/rc"
  printf '%s\n' "$d" > "$REPO_TMP/$id.dir"
}

REPO_TMP="$(mktemp -d)"; TMPS="$TMPS $REPO_TMP"

while IFS='|' read -r id desc verif; do
  [ -n "$id" ] || continue
  [ "$#" -eq 0 ] || case "$SELECAO" in *" $id "*) ;; *) continue ;; esac
  roda "$id" "$desc" "$verif" &
  PIDS="$PIDS $!"; IDS="$IDS $id"
done <<EOF
$LISTA
EOF
for p in $PIDS; do wait "$p"; done

echo "Mutações dirigidas — a verificação TEM que falhar"
while IFS='|' read -r id desc verif; do
  [ -n "$id" ] || continue
  case " $IDS " in *" $id "*) ;; *) continue ;; esac
  d="$(cat "$REPO_TMP/$id.dir")"
  rc="$(cat "$d/rc")"
  case "$rc" in
    0) MORTAS=$((MORTAS+1))
       printf '  morta  %-4s %s (%s) — pega por:\n' "$id" "$desc" "$verif"
       grep -E 'FALHA|contract check failed' "$d/saida.log" 2>/dev/null | head -4 \
         | sed 's/^[[:space:]]*//' | cut -c1-140 | sed 's/^/           /' ;;
    1) VIVAS=$((VIVAS+1)); printf '  VIVA   %-4s %s — %s continuou verde\n' "$id" "$desc" "$verif" ;;
    *) ERROS=$((ERROS+1)); printf '  ERRO   %-4s %s — mutação não aplicada\n' "$id" "$desc"; sed 's/^/         /' "$d/mutacao.log" ;;
  esac
done <<EOF
$LISTA
EOF

echo "---------------------------------------------"
printf '%d morta(s), %d viva(s), %d erro(s)\n' "$MORTAS" "$VIVAS" "$ERROS"
[ "$VIVAS" = 0 ] && [ "$ERROS" = 0 ]
