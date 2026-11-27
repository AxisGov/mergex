#!/usr/bin/env bash
#
# Bancada da V2 — registro de suíte por task e lista de falhas de ambiente (DM-357).
#
# `parcial` e `verde` passam. `vermelha` é AVISO só quando `suite_falhas` não é
# vazia, todo caminho está em `.expx/falhas-de-ambiente.tsv` para a plataforma,
# com motivo, e nenhum aparece em `<base>...HEAD` (nem no índice, com
# --staged). Todo o resto é FALHA; o que não dá para verificar é SEM_PROVA.
#
# Cobre o portao-v2.sh e o hook commit-por-task, que o chama. Os casos do hook
# precisam de jq (o hook lê o evento com ele); sem jq são contados como pulados.
#
# Sem rede. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-portao-v2.sh
#      V2=<outro script> HOOK=<outro hook> bash scripts/ci/test-portao-v2.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
V2="${V2:-$REPO/.claude/skills/mergex/scripts/portao-v2.sh}"
HOOK="${HOOK:-$REPO/.claude/hooks/mergex/commit-por-task.sh}"
export EXPX_PLATAFORMA=linux

OK=0; FALHOU=0; PULADO=0
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT
D="$(mktemp -d)"; TMPS="$TMPS $D"

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
pula()  { PULADO=$((PULADO+1)); printf '  pulo  %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Repositório: a base tem os testes; a feature toca um deles (e um com espaço).
# ---------------------------------------------------------------------------
R="$(mktemp -d)"; TMPS="$TMPS $R"
git -C "$R" init -q . && git -C "$R" checkout -q -b main 2>/dev/null
git -C "$R" config user.email teste@expx.local
git -C "$R" config user.name Teste
git -C "$R" config core.autocrlf false
git -C "$R" config commit.gpgsign false
mkdir -p "$R/tests" "$R/src" "$R/.expx"
for t in ambiente outro tocado indice 'com espaco' 'tocado espaco'; do
  printf 'base\n' > "$R/tests/$t.test.ts"
done
git -C "$R" add tests; git -C "$R" commit -qm base
git -C "$R" checkout -q -b feature/ft-v2
printf 'mudou\n' > "$R/tests/tocado.test.ts"
printf 'mudou\n' > "$R/tests/tocado espaco.test.ts"
git -C "$R" add tests; git -C "$R" commit -qm 'toca dois testes'

TSV="$R/.expx/falhas-de-ambiente.tsv"
# lista_padrao — todos os testes, menos tests/outro.test.ts
lista_padrao() {
  {
    printf '# caminho\tplataforma\tmotivo\tdesde\n\n'
    local t
    for t in ambiente tocado indice 'com espaco' 'tocado espaco'; do
      printf 'tests/%s.test.ts\tlinux\tfalha so de ambiente\t2026-11-27\n' "$t"
    done
  } > "$TSV"
}
lista_padrao

T="$D/tasks.md"
# plano <suite> [linhas de suite_falhas, já indentadas] [status]
plano() {
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: plano\ntrabalho_id: ft-v2\n'
    printf 'tasks:\n  - id: T-01.01\n    titulo: Task\n    status: %s\n' "${3:-concluida}"
    printf '    suite: %s\n' "$1"
    [ -z "${2:-}" ] || printf '%s\n' "$2"
    printf '    teste_integracao: integra\n    teste_funcional: funciona\n'
    printf -- '---\n\n# Plano\n'
  } > "$T"
}
fluxo() { printf '    suite_falhas: [%s]' "$1"; }

# confere <descrição> <resultado> <código> <argumentos do portao-v2...>
confere() {
  local desc="$1" esperado="$2" codigo="$3" saida rc=0; shift 3
  saida="$(bash "$V2" "$@" 2>/dev/null)" || rc=$?
  if [ "${saida%%$'\n'*}" = "V2=$esperado" ] && [ "$rc" = "$codigo" ]; then ok "$desc → $esperado"
  else falha "$desc — obteve rc=$rc '$(tr '\n\t' '| ' <<<"$saida")', esperava V2=$esperado rc=$codigo"; fi
}
verifica() { # <descrição> <resultado> <código> [opções extras...]
  local desc="$1" res="$2" cod="$3"; shift 3
  confere "$desc" "$res" "$cod" --verificar --raiz "$R" --base main "$@" "$T"
}

# ---------------------------------------------------------------------------
echo "1. Registros válidos e inválidos"
# ---------------------------------------------------------------------------
plano verde;         verifica "caso verde" OK 0
plano parcial;       verifica "caso parcial" OK 0
plano nao_executada; verifica "caso nao_executada" FALHA 1
plano nao_executada '' pendente; verifica "caso task nao concluida nao e alvo" OK 0

# ---------------------------------------------------------------------------
echo
echo "2. Vermelha e a lista de ambiente"
# ---------------------------------------------------------------------------
plano vermelha "$(fluxo tests/ambiente.test.ts)"
verifica "caso vermelha toda listada e fora do diff" AVISO 0
plano vermelha "$(fluxo 'tests/ambiente.test.ts, tests/outro.test.ts')"
verifica "caso fora da lista" FALHA 1
plano vermelha "$(fluxo tests/tocado.test.ts)"
verifica "caso listada mas tocada por base...HEAD" FALHA 1
plano vermelha "$(fluxo '"tests/tocado espaco.test.ts"')"
verifica "caso caminho com espaco tocado pelo diff" FALHA 1

plano vermelha "$(fluxo tests/indice.test.ts)"
printf 'no indice\n' > "$R/tests/indice.test.ts"; git -C "$R" add tests/indice.test.ts
verifica "caso listada mas no indice com --staged" FALHA 1 --staged
verifica "caso o indice nao conta sem --staged" AVISO 0
git -C "$R" reset -q HEAD -- tests/indice.test.ts; git -C "$R" checkout -q -- tests/indice.test.ts

plano vermelha "$(fluxo tests/ambiente.test.ts)"
EXPX_PLATAFORMA=win32 verifica "caso plataforma diferente" FALHA 1
mv "$TSV" "$D/tsv"
verifica "caso sem a lista no projeto" FALHA 1
mv "$D/tsv" "$TSV"

plano vermelha;                    verifica "caso suite_falhas ausente" FALHA 1
plano vermelha "$(fluxo '')";      verifica "caso suite_falhas vazia []" FALHA 1

printf 'tests/ambiente.test.ts\tlinux\t\t2026-11-27\n' > "$TSV"
plano vermelha "$(fluxo tests/ambiente.test.ts)"
verifica "caso TSV com motivo vazio ignora a linha" FALHA 1

printf 'tests/com espaco.test.ts\tlinux\tfalha so de ambiente\t2026-11-27\r\n' > "$TSV"
plano vermelha "$(fluxo '"tests/com espaco.test.ts"')"
verifica "caso TSV com CRLF e caminho com espaco" AVISO 0
lista_padrao

plano vermelha "$(printf '    suite_falhas:\n      - tests/ambiente.test.ts\n      - "tests/com espaco.test.ts"')"
verifica "caso lista em bloco" AVISO 0

plano vermelha "$(fluxo tests/ambiente.test.ts)"
confere "caso base que nao resolve" SEM_PROVA 2 --verificar --raiz "$R" --base nao-existe "$T"

# ---------------------------------------------------------------------------
echo
echo "3. --conferir-falhas (fechamento da sprint)"
# ---------------------------------------------------------------------------
confere "caso conferir-falhas so de ambiente" AVISO 0 \
  --conferir-falhas --raiz "$R" --base main -- tests/ambiente.test.ts 'tests/com espaco.test.ts'
confere "caso conferir-falhas fora da lista" FALHA 1 \
  --conferir-falhas --raiz "$R" --base main -- tests/ambiente.test.ts tests/outro.test.ts
confere "caso conferir-falhas tocada pelo diff" FALHA 1 \
  --conferir-falhas --raiz "$R" --base main -- tests/tocado.test.ts
confere "caso conferir-falhas sem caminho" FALHA 1 --conferir-falhas --raiz "$R" --base main

# ---------------------------------------------------------------------------
echo
echo "4. Sem prova não é prova"
# ---------------------------------------------------------------------------
confere "caso tasks.md ilegivel" SEM_PROVA 2 --verificar --raiz "$R" --base main "$D/nao-existe.md"
printf 'sem frontmatter\n' > "$D/solto.md"
confere "caso tasks.md sem frontmatter" SEM_PROVA 2 --verificar --raiz "$R" --base main "$D/solto.md"

# ---------------------------------------------------------------------------
echo
echo "5. O hook commit-por-task em modo bloqueio"
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  W="$R/docs/sprintx/features/ft-v2/sprint-01"
  mkdir -p "$W" "$R/docs/entregas/ft-v2"
  printf '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"bloqueio"}}}\n' > "$R/.expx/hooks.json"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-v2\nbranch: feature/ft-v2\nbranch_base: main\n---\n' \
    > "$R/docs/entregas/ft-v2/ENTREGA.md"
  printf 'codigo\n' > "$R/src/hook.js"; git -C "$R" add src/hook.js

  # roda_hook <descrição> <código> <trecho do stderr> <teste de suite_falhas>
  roda_hook() {
    local desc="$1" codigo="$2" trecho="$3" rc=0 erro
    plano vermelha "$(fluxo "$4"; printf '\n    arquivos:\n      cria: [src/hook.js]\n      altera: []')"
    cp "$T" "$W/tasks.md"
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m ajuste"},"cwd":"%s"}' "$R" \
      | bash "$HOOK" >/dev/null 2>"$D/hook.err" || rc=$?
    erro="$(cat "$D/hook.err")"
    case "$erro" in
      *"$trecho"*) [ "$rc" = "$codigo" ] && { ok "$desc → rc $rc"; return 0; } ;;
    esac
    falha "$desc — rc=$rc (esperava $codigo com '$trecho'): $(tr '\n' '|' <<<"$erro")"
  }
  roda_hook "caso hook AVISO deixa commitar" 0 'só por falha de ambiente' tests/ambiente.test.ts
  roda_hook "caso hook fora da lista barra" 2 'a task fechou sem teste passando' tests/outro.test.ts
else
  pula "caso hook AVISO deixa commitar (sem jq)"
  pula "caso hook fora da lista barra (sem jq)"
fi

# ---------------------------------------------------------------------------
echo
echo "6. Fluxo com aspas (DM-358)"
# ---------------------------------------------------------------------------
lista_padrao
printf 'tests/%s.test.ts\tlinux\tfalha so de ambiente\t2026-11-27\n' 'a,b' "d'agua" >> "$TSV"

plano vermelha "$(fluxo '"tests/a,b.test.ts", tests/ambiente.test.ts')"
verifica "caso virgula entre aspas duplas" AVISO 0
plano vermelha "$(fluxo "tests/ambiente.test.ts, 'tests/a,b.test.ts'")"
verifica "caso virgula entre aspas simples" AVISO 0
plano vermelha "$(fluxo "tests/d'agua.test.ts")"
verifica "caso aspa no meio de item sem aspas e literal" AVISO 0
plano vermelha "$(fluxo 'tests/a,b.test.ts')"
verifica "caso virgula sem aspas separa os itens" FALHA 1

# invalida <descrição> <miolo do fluxo> — FALHA pelo motivo certo
invalida() {
  local saida rc=0
  plano vermelha "$(fluxo "$2")"
  saida="$(bash "$V2" --verificar --raiz "$R" --base main "$T" 2>/dev/null)" || rc=$?
  case "$saida" in
    V2=FALHA*suite_falhas-invalida*) [ "$rc" = 1 ] && { ok "$1 → suite_falhas-invalida"; return 0; } ;;
  esac
  falha "$1 — obteve rc=$rc '$(tr '\n\t' '| ' <<<"$saida")', esperava suite_falhas-invalida"
}
invalida "caso aspa aberta sem fecho" '"tests/ambiente.test.ts'
invalida "caso aspa solta no fim" 'tests/ambiente.test.ts"'
invalida "caso aspas trocadas" "'tests/ambiente.test.ts\""
invalida "caso texto depois do fecho" '"tests/ambiente.test.ts" x'
invalida "caso segundo item sem fecho" "tests/ambiente.test.ts, 'tests/a,b.test.ts"

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), %d pulado(s)\n' "$OK" "$FALHOU" "$PULADO"
[ "$FALHOU" = "0" ]
