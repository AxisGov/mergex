#!/usr/bin/env bash
#
# Bancada do E1 com a revisão por task — a evidência entra no commit da task e o
# item de `ENTREGA.commits` registra o veredito.
#
# C1 (DM-241): `sequencia-de-commits.sh --acrescentar <ENTREGA.md> <task> <commit>
# [<revisao>]` grava `revisao:` como quarta chave do item. O valor é o que o `conferir`
# do núcleo disse da task (`ok`, `achados`, `indisponivel:<classe>`,
# `incompleta:<classe>`, `invalida`) ou `null`; a classe é o texto do motivo antes do
# segundo `:`, e nada depois dele (um caminho) entra no YAML. A leitura ignora a chave.
#
# Plano 2026-10-18-mergex-revisao-por-task-e-merge-automatico.md (Bloco C), com as
# emendas de 2026-10-20-mergex-limites-do-codeant-parte-2.md.
#
# Uso: bash scripts/ci/test-e1-evidencia-revisao.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
SEQ="$SCRIPTS/sequencia-de-commits.sh"
PROVA="$SCRIPTS/prova-de-commit.sh"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# entrega_seq <arquivo> [<item YAML>...] — a ENTREGA com os itens dados, já formatados
entrega_seq() {
  local arq="$1"; shift
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-r\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: true\nbranch: feature/ft-r\nbranch_base: main\n'
    if [ "$#" -eq 0 ]; then printf 'commits: []\n'; else printf 'commits:\n'; printf '%s\n' "$@"; fi
    printf 'desvios: []\natualizado_em: 2026-10-20\n'
    printf -- '---\n\n# Entrega\n'
  } > "$arq"
}
# item_de <arquivo> <seq> — o bloco YAML do item com aquele seq, em uma linha
item_de() {
  awk -v s="$2" '
    /^  - seq: / { dentro = ($0 == "  - seq: " s) }
    /^[^ ]/ { dentro = 0 }
    dentro { printf "%s|", $0 }
  ' "$1"
}

echo '== C1: o item de ENTREGA.commits registra a revisao da task =='

E="$D/ENTREGA.md"

entrega_seq "$E"
saida="$(bash "$SEQ" --acrescentar "$E" T-01.01 abc1234 ok 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$saida" = 'seq=1' ] \
  && [ "$(item_de "$E" 1)" = '  - seq: 1|    task: T-01.01|    commit: abc1234|    revisao: ok|' ] \
  && ok 'acrescentar com revisao ok grava a quarta chave' \
  || falha "acrescentar com revisao ok grava a quarta chave — rc=$rc saida=$saida item=$(item_de "$E" 1)"

saida="$(bash "$SEQ" --acrescentar "$E" T-01.02 def5678 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(item_de "$E" 2)" = '  - seq: 2|    task: T-01.02|    commit: def5678|    revisao: null|' ] \
  && ok 'sem o quarto argumento grava revisao: null' \
  || falha "sem o quarto argumento grava revisao: null — rc=$rc saida=$saida item=$(item_de "$E" 2)"

saida="$(bash "$SEQ" --acrescentar "$E" T-01.03 0123abc 'indisponivel:arquivo-inexistente:src/a: b.js' 2>&1)"; rc=$?
lidos="$(bash "$PROVA" --commits "$E" 2>&1 | tr '\t\n' ':|')"
[ "$rc" = 0 ] && [ "$(item_de "$E" 3)" = '  - seq: 3|    task: T-01.03|    commit: 0123abc|    revisao: indisponivel:arquivo-inexistente|' ] \
  && ! grep -q 'src/a' "$E" \
  && [ "$(bash "$SEQ" --validar "$E" 2>&1)" = 'commits=3' ] \
  && [ "$lidos" = 'T-01.01:abc1234|T-01.02:def5678|T-01.03:0123abc|' ] \
  && ok 'motivo com caminho nao entra no YAML (e --validar e prova-de-commit --commits leem a lista)' \
  || falha "motivo com caminho nao entra no YAML — rc=$rc saida=$saida item=$(item_de "$E" 3) lidos=$lidos"

saida="$(bash "$SEQ" --acrescentar "$E" T-01.04 4567def 'incompleta:L1:41' 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$(item_de "$E" 4)" = '  - seq: 4|    task: T-01.04|    commit: 4567def|    revisao: incompleta:L1|' ] \
  && ok 'incompleta:L1:41 grava revisao: incompleta:L1' \
  || falha "incompleta:L1:41 grava revisao: incompleta:L1 — rc=$rc saida=$saida item=$(item_de "$E" 4)"

n=4; todos=1
for v in achados invalida null 'incompleta:lote-falhou' 'indisponivel:cli-ausente'; do
  n=$((n + 1))
  bash "$SEQ" --acrescentar "$E" T-01.05 "abcdef$n" "$v" >/dev/null 2>&1 \
    && [ "$(item_de "$E" "$n")" = "  - seq: $n|    task: T-01.05|    commit: abcdef$n|    revisao: $v|" ] \
    || { todos=0; falha "valor da gramatica gravado como veio: $v — item=$(item_de "$E" "$n")"; }
done
[ "$todos" = 0 ] || ok 'achados, invalida, null, incompleta:<classe> e indisponivel:<classe> gravam como vieram'

antes="$(cat "$E")"; todos=1
for v in '' talvez OK incompleta 'incompleta:' 'indisponivel:a b' 'ok:x' 'achados:1' 'invalida:x' \
         'null:x' 'incompleta:-x' 'indisponivel:é' 'incompleta:L1
x'; do
  bash "$SEQ" --acrescentar "$E" T-01.06 fedcba9 "$v" >/dev/null 2>&1; rc=$?
  { [ "$rc" = 1 ] && [ "$(cat "$E")" = "$antes" ]; } \
    || { todos=0; falha "valor fora da gramatica nao grava: '$v' (rc=$rc)"; }
done
[ "$todos" = 0 ] || ok 'valor fora da gramatica nao grava (codigo 1, arquivo intocado)'

[ "$(bash "$SEQ" --revisao 'incompleta:L2:src/a.ts' 2>&1)" = 'incompleta:L2' ] \
  && ! bash "$SEQ" --revisao 'ok:x' >/dev/null 2>&1 \
  && ok '--revisao diz o valor como o --acrescentar o gravaria' \
  || falha '--revisao diz o valor como o --acrescentar o gravaria'

bash "$SEQ" --acrescentar "$E" T-01.06 fedcba9 ok extra >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && ok 'acrescentar com cinco argumentos: 64' || falha "acrescentar com cinco argumentos: rc=$rc"

entrega_seq "$E" '  - task: T-01.01' '    commit: aaa1111' '  - seq: 2' '    task: T-01.02' '    commit: bbb2222'
saida="$(bash "$SEQ" --acrescentar "$E" T-01.03 ccc3333 ok 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$saida" = 'seq=3' ] && [ "$(bash "$SEQ" --validar "$E" 2>&1)" = 'commits=3' ] \
  && [ "$(bash "$PROVA" --commits "$E" 2>&1 | wc -l | tr -d ' ')" = 3 ] \
  && [ "$(bash "$SEQ" --ler "$E" | tail -n 1 | tr '\t' ':')" = '3:3:T-01.03:ccc3333' ] \
  && ok 'lista legada sem revisao continua valida, e o item novo com revisao tambem' \
  || falha "lista legada sem revisao continua valida — rc=$rc saida=$saida validar=$(bash "$SEQ" --validar "$E" 2>&1)"

printf '\n%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
