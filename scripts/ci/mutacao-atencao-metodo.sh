#!/usr/bin/env bash
#
# Prova por mutação da classificação de artefatos de método (E3, L4/D4) e,
# desde a P0.2-A4, da causa do bloqueio (M10 em diante: causa-do-portao.sh).
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
CAUSA_SH='.claude/skills/mergex/scripts/causa-do-portao.sh'
SCHEMA='.claude/skills/mergex/references/00-schema.md'
ABERTURA='.claude/skills/mergex/references/00-abertura.md'
TEMPLATE_ENTREGA='.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md'
PROVA_SH='.claude/skills/mergex/scripts/prova-de-commit.sh'
PRONTIDAO='.claude/skills/mergex/references/02-prontidao.md'
COMMITS='.claude/skills/mergex/references/01-commits.md'
TEMPLATE_PRONTIDAO='.claude/skills/mergex/assets/TEMPLATE-prontidao.md'
CHECK_CMD='.claude/commands/mergex-check.md'
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
teste_causa() { bash scripts/ci/test-causa-portao.sh > saida.log 2>&1; }
teste_v11()   { bash scripts/ci/test-portao-v11.sh > saida.log 2>&1; }

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

# --- P0.2-A4: a causa do bloqueio (scripts/causa-do-portao.sh) ---
M10() { troca "$CAUSA_SH" '      [ "$t" = "$v" ] && { causa_de "$v"; return 0; }' \
  '      [ "$t" = "$v" ] && { printf '"'"'falha_tecnica\n'"'"'; return 0; }'; }
M11() { troca "$CAUSA_SH" '      [ "$causa" != null ]      || { ERRO="estado bloqueado exige causa não nula"; return 1; }' \
  '      [ "$causa" = null ] && { printf '"'"'causa=null\n'"'"'; return 0; }'; }
M12() { troca "$CAUSA_SH" '    if [ "$historico" = 1 ]; then' '    if true; then'; }
M13() { troca "$CAUSA_SH" "ORDEM='v10 v6 v7 v8 v9 v1 v2 v3 v4 v5 v11'" "ORDEM='v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11'"; }
M14() { troca "$CAUSA_SH" '      [ "$t" = "${v}_sem_prova" ] && { printf '"'"'%s\n'"'"' "$INDETERMINADA"; return 0; }' \
  '      [ "$t" = "${v}_sem_prova" ] && { causa_de "$v"; return 0; }'; }
M15() { troca "$CAUSA_SH" "      printf 'causa=ausente\n'; return 0" '      ERRO="legado"; return 1'; }
M16() { troca "$SCHEMA" '| 3 | `v7` | `bloqueio_aberto` |' '| 3 | `v7` | `falha_tecnica` |'; }
M17() { apaga "$ABERTURA" '| `falhas_portao`, `causa` |'; }
M18() { apaga "$TEMPLATE_ENTREGA" 'causa: '; }

# --- P0.2-C3: a V11 cobra o commit da task concluída ---
# Cada mutação quebra UMA das afirmações da V11. Todas têm que morrer.
M19() { # a V11 nunca falha
  troca "$PROVA_SH" '  if [ -z "$faltam" ]; then printf '"'"'V11=OK\n'"'"'; return 0; fi' \
    '  if true; then printf '"'"'V11=OK\n'"'"'; return 0; fi'
}
M20() { # basta existir qualquer commit: o id da task deixa de ser cruzado
  troca "$PROVA_SH" '    printf '"'"'%s\n'"'"' "$provadas" | cut -f1 | grep -Fxq -- "$id" && continue' \
    '    [ -n "$provadas" ] && continue'
}
M21() { # task não concluída também passa a ser cobrada
  troca "$PROVA_SH" '        st = $0; sub(/^[[:space:]]*status:[[:space:]]*/, "", st); sub(/[[:space:]]+$/, "", st)' \
    '        st = "concluida"'
}
M22() { # só o primeiro item de commits decide
  troca "$PROVA_SH" '  if ! provadas="$(commits_validos "$ent")"; then' \
    '  if ! provadas="$(commits_validos "$ent" | head -1)"; then'
}
M23() { # commit vazio ou malformado passa a satisfazer
  troca "$PROVA_SH" '    sha_valido "$c" || continue' '    sha_valido "$c" || true'
}
M24a() { # o item que o E1 tardio acrescentou no fim é ignorado
  troca "$PROVA_SH" '  if ! provadas="$(commits_validos "$ent")"; then' \
    '  if ! provadas="$(commits_validos "$ent" | sed '"'"'$d'"'"')"; then'
}
M24b() { apaga "$COMMITS" '### O E1 tardio'; }
M25a() { apaga "$PRONTIDAO" '### V11 — Task concluída'; }
M25b() { apaga "$TEMPLATE_PRONTIDAO" '| V11 |'; }
M25c() { apaga "$CHECK_CMD" '| V11 |'; }
M26a() { # a falha V11 deixa de ter causa própria: vira a causa da V1
  # A linha fecha a string CAUSAS; a aspa faz parte dela.
  troca "$CAUSA_SH" "v11|commit_nao_registrado'" "v11|tarefa_nao_concluida'"
}
M26b() { # a V11 passa a vencer até a V10, e o estado terminal deixa de refletir a falha
  troca "$CAUSA_SH" "ORDEM='v10 v6 v7 v8 v9 v1 v2 v3 v4 v5 v11'" \
    "ORDEM='v11 v10 v6 v7 v8 v9 v1 v2 v3 v4 v5'"
}
M26c() { troca "$SCHEMA" '| 11 | `v11` | `commit_nao_registrado` |' '| 11 | `v11` | `falha_tecnica` |'; }

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
M9|prova do HISTORICO aceita reescrita|teste
M10|grava falha_tecnica para qualquer bloqueio|teste_causa
M11|aceita causa null em estado bloqueado|teste_causa
M12|gravação nova aceita ENTREGA sem a chave causa|teste_causa
M13|precedência na numeração crua (V1 antes de V7)|teste_causa
M14|verificação sem prova vira causa provada|teste_causa
M15|leitura histórica recusa ENTREGA anterior às chaves|teste_causa
M16|tabela de causas do schema diverge do script|validador
M17|retomada do E0 preserva a causa anterior|validador
M18|template da ENTREGA omite a chave causa|validador
M19|V11 sempre OK|teste_v11
M20|basta existir qualquer commit, sem cruzar o id da task|teste_v11
M21|task não concluída também é cobrada pela V11|teste_v11
M22|só o primeiro item de commits decide|teste_v11
M23|commit vazio ou malformado satisfaz a V11|teste_v11
M24a|o item acrescentado pelo E1 tardio é ignorado|teste_v11
M24b|o contrato do E1 perde o procedimento do E1 tardio|validador
M25a|a V11 sai do portão E2|validador
M25b|a V11 sai do template de prontidão|validador
M25c|a V11 sai do comando do portão|validador
M26a|a falha V11 deixa de ter causa própria|teste_v11
M26b|a V11 passa a vencer a V10 na precedência|teste_v11
M26c|tabela de causas do schema diverge no v11|validador'

SELECAO=" $* "
MORTAS=0; VIVAS=0; ERROS=0; CONTROLE_OK=1
PIDS=""; IDS=""

# Controle sem mutação: numa cópia intocada, as verificações TÊM que passar.
# Sem ele, uma bancada quebrada mataria toda mutação por motivo errado e a
# suíte ficaria verde sem provar nada.
controle() {
  local d rc
  d="$(copia)"
  echo "Controle — cópia SEM mutação: as verificações têm que passar"
  for v in teste teste_causa teste_v11 validador; do
    rc=0; ( cd "$d" && "$v" ) || rc=$?
    if [ "$rc" = 0 ]; then printf '  ok     %s\n' "$v"
    else CONTROLE_OK=0; printf '  FALHA  %s — verde era esperado (rc=%s)\n' "$v" "$rc"
         sed 's/^/           /' "$d/saida.log" 2>/dev/null | tail -5; fi
  done
  echo
}
[ "$#" -eq 0 ] && controle

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
[ "$CONTROLE_OK" = 1 ] || printf 'controle sem mutação REPROVOU: as mutações não provam nada\n'
[ "$VIVAS" = 0 ] && [ "$ERROS" = 0 ] && [ "$CONTROLE_OK" = 1 ]
