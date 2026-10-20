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
# C2 (DM-240): `fechamento-do-e1.sh` commita `docs/entregas/<trabalho>/revisao/<task>.json`
# da task atual junto com a task, sem ela estar na lista; a de outra task fica na árvore;
# outro nome sob `revisao/` é desvio. O valor de `revisao:` vem do `conferir` do núcleo no
# commit da task. As evidências são gravadas pelo `revisar` do núcleo (no Linux, com a CLI
# falsa de codeant-falsa.sh): nenhum caso escreve evidência à mão.
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

echo
echo '== C2: o E1 commita a evidencia da task atual =='

# O núcleo do expx montado no projeto (a cópia dos testes, sem o ORIGEM e sem CR) e, no
# Linux, a CLI falsa de codeant-falsa.sh; as evidências são gravadas pelo `revisar` dele.
# shellcheck source=codeant-falsa.sh
. "$REPO/scripts/ci/codeant-falsa.sh"
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done
FECHA="$SCRIPTS/fechamento-do-e1.sh"
HOOK="$REPO/.claude/hooks/mergex/commit-por-task.sh"
COPIA="$REPO/scripts/ci/fixtures/candidatos/expx-nucleo"
NUCLEO_REL='.expx/marketplace/plugins/expx/nucleo/scripts'
TASKS_REL='docs/sprintx/features/ft-r/sprint-01/tasks.md'
ENTREGA_REL='docs/entregas/ft-r/ENTREGA.md'
REVISAO_REL='docs/entregas/ft-r/revisao'
command -v node >/dev/null 2>&1 || { echo 'test-e1-evidencia-revisao: node ausente' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'test-e1-evidencia-revisao: jq ausente' >&2; exit 1; }
FALSA=0; codeant_falsa_suportada && FALSA=1
nativo() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

resposta() { # <arquivo> [<issues JSON>]
  printf '{"issues":%s,"meta":{"reviewed_files":"__include__","total_changed":0,"skipped":[],"capped":false,"max_files":40},"error":null,"noFiles":false}\n' \
    "${2:-[]}" > "$1"
}
resposta "$D/resp-ok.json"
resposta "$D/resp-achado.json" '[{"issue_content":"variavel nunca usada","relevant_file":"src/a.js","start_line":1,"label":"bug"}]'
mkdir -p "$D/nucleo"
while IFS= read -r f; do
  mkdir -p "$D/nucleo/$(dirname "$f")" && tr -d '\r' < "$COPIA/$f" > "$D/nucleo/$f"
done < <(cd "$COPIA" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
if [ "$FALSA" = 1 ]; then
  instala_codeant_falsa "$D/falsa" "$D/resp-ok.json" && nucleo_com_falsa "$D/nucleo" "$D/falsa" \
    || { echo 'test-e1-evidencia-revisao: nao montou a CLI falsa' >&2; exit 1; }
fi
# node quebrado: registra cada chamada em $D/node.log e sai 127, como o node que não roda
mkdir -p "$D/sem-node"
printf '#!%s\nprintf "%%s\\n" "$*" >> "%s"\nexit 127\n' "$BASH" "$D/node.log" > "$D/sem-node/node"
chmod +x "$D/sem-node/node"

# repo <dir> [<cria da T-01.01>] — o projeto com o plano, a entrega e o núcleo na base
repo() {
  local dir="$1" cria="${2:-img/logo.png}"
  git init -q -b feature/ft-r "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local; git config user.name Teste
    git config commit.gpgsign false; git config core.autocrlf false
    mkdir -p src img "$(dirname "$TASKS_REL")" "$(dirname "$ENTREGA_REL")" "$NUCLEO_REL"
    cp -R "$D/nucleo/." "$NUCLEO_REL/"
    printf 'base a\n' > src/a.js; printf 'base x\n' > src/x.js
    cat > "$TASKS_REL" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-r
tasks:
  - id: T-01.01
    titulo: Task atual
    status: concluida
    suite: parcial
    arquivos:
      cria: [$cria]
      altera: [src/a.js]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-01.02
    titulo: Task irma
    status: pendente
    suite: nao_executada
    arquivos:
      cria: []
      altera: [src/x.js]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
---
YAML
    printf -- '---\nkind: orquestrador\ntrabalho_id: ft-r\n---\n' > "$(dirname "$(dirname "$TASKS_REL")")/ORQUESTRADOR.md"
    entrega_seq "$ENTREGA_REL"
    git add -A && git commit -qm 'chore: base'
  )
}
MSG="$D/e1.msg"
printf 'feat(src): fecha T-01.01\n\nObjetivo da task.\n\nTask: T-01.01\nTrabalho: ft-r\n' > "$MSG"
# revisa <dir> <task> <a,b,...> [<resposta>] — o `revisar` do núcleo do projeto
revisa() {
  [ -z "${4:-}" ] || instala_codeant_falsa "$D/falsa" "$4"
  (cd "$1" && PATH="$D/falsa/bin:$PATH" node "$(nativo "$1/$NUCLEO_REL/expx-revisao.mjs")" revisar \
     --trabalho ft-r --task "$2" --arquivos "$3" > "$D/revisar.out" 2>&1)
  local rc=$?
  [ -z "${4:-}" ] || instala_codeant_falsa "$D/falsa" "$D/resp-ok.json"
  return "$rc"
}
fechar() { # <dir> [VAR=valor...] -- <caminhos...>
  local dir="$1"; shift
  local -a amb=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do amb+=("$1"); shift; done
  shift
  SAIDA="$(cd "$dir" && env ${amb[@]+"${amb[@]}"} bash "$FECHA" --fechar --entrega "$ENTREGA_REL" \
    --task T-01.01 --mensagem "$MSG" -- "$@" 2>&1)"
  RC=$?
}
no_commit() { git -C "$1" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' '; }
ultimo() { # <dir> — o último item de commits, em uma linha
  awk '/^  - seq: /{ i = "" } /^  - seq: |^    [a-z]+: /{ i = i $0 "|" } /^[^ ]/{ if (i != "") u = i; i = "" } END { print u }' \
    "$1/$ENTREGA_REL"
}
revisao_de() { ultimo "$1" | tr '|' '\n' | sed -n 's/^    revisao: //p'; }

R="$D/atual"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png; rc=$?
fechar "$R" -- img/logo.png
[ "$rc" = 0 ] && [ "$RC" = 0 ] \
  && [ "$(no_commit "$R")" = "$REVISAO_REL/T-01.01.json img/logo.png " ] \
  && [ -z "$(git -C "$R" status --porcelain -uall -- "$REVISAO_REL")" ] \
  && ok 'evidencia da task atual suja entra no commit sem ser listada' \
  || falha "evidencia da task atual suja entra no commit sem ser listada — revisar=$rc rc=$RC commit=$(no_commit "$R") saida=$SAIDA"
[ "$(revisao_de "$R")" = ok ] \
  && ok 'item novo tem revisao: ok lido do conferir no commit da task' \
  || falha "item novo tem revisao: ok — item=$(ultimo "$R")"

R="$D/listada"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
fechar "$R" -- img/logo.png "$REVISAO_REL/T-01.01.json"
[ "$RC" = 0 ] && [ "$(no_commit "$R")" = "$REVISAO_REL/T-01.01.json img/logo.png " ] && [ "$(revisao_de "$R")" = ok ] \
  && ok 'evidencia da task atual listada pelo chamador entra igual' \
  || falha "evidencia listada — rc=$RC commit=$(no_commit "$R") saida=$SAIDA"

R="$D/outra"; repo "$R"
printf 'png\n' > "$R/img/logo.png"; printf 'png\n' > "$R/img/outro.png"
revisa "$R" T-01.02 img/outro.png
rm -f "$R/img/outro.png"
fechar "$R" -- img/logo.png
[ "$RC" = 0 ] && [ "$(no_commit "$R")" = 'img/logo.png ' ] \
  && [ "$(git -C "$R" status --porcelain -uall -- "$REVISAO_REL")" = "?? $REVISAO_REL/T-01.02.json" ] \
  && [ "$(revisao_de "$R")" = null ] \
  && ok 'evidencia de outra task fica na arvore e nao para o E1' \
  || falha "evidencia de outra task — rc=$RC commit=$(no_commit "$R") status=$(git -C "$R" status --porcelain -uall -- "$REVISAO_REL" | tr '\n' '|') saida=$SAIDA"

R="$D/sem"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
rm -f "$D/node.log"; fechar "$R" PATH="$D/sem-node:$PATH" -- src/a.js
[ "$RC" = 0 ] && [ "$(no_commit "$R")" = 'src/a.js ' ] && [ "$(revisao_de "$R")" = null ] && [ ! -s "$D/node.log" ] \
  && ok 'sem evidencia: revisao: null, sem node' \
  || falha "sem evidencia — rc=$RC item=$(ultimo "$R") saida=$SAIDA"

R="$D/sem-node-com-evidencia"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
rm -f "$D/node.log"; fechar "$R" PATH="$D/sem-node:$PATH" -- img/logo.png
[ "$RC" = 0 ] && [ "$(no_commit "$R")" = "$REVISAO_REL/T-01.01.json img/logo.png " ] && [ "$(revisao_de "$R")" = invalida ] \
  && [ -s "$D/node.log" ] \
  && ok 'evidencia no commit e node que nao roda: revisao: invalida (nao conferida), o registro segue' \
  || falha "node ausente com evidencia — rc=$RC item=$(ultimo "$R") saida=$SAIDA"

R="$D/fatia"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
fechar "$R" FATIA_X=1 -- img/logo.png
[ "$RC" = 0 ] && [ "$(revisao_de "$R")" = invalida ] \
  && ok 'FATIA_X no ambiente: o conferir sai 64 e a revisao e invalida' \
  || falha "FATIA_X — rc=$RC item=$(ultimo "$R") saida=$SAIDA"

R="$D/nao-bate"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
printf 'mudou depois da revisao\n' >> "$R/img/logo.png"
fechar "$R" -- img/logo.png
[ "$RC" = 0 ] && [ "$(revisao_de "$R")" = invalida ] \
  && ok 'arquivo mudou depois da revisao (evidencia-nao-bate): revisao: invalida' \
  || falha "evidencia-nao-bate — rc=$RC item=$(ultimo "$R") saida=$SAIDA"

lista=""; i=1
while [ "$i" -le 41 ]; do lista="$lista${lista:+, }src/f$i.js"; i=$((i + 1)); done
R="$D/incompleta"; repo "$R" "$lista"
i=1; arqs=""
while [ "$i" -le 41 ]; do printf 'const f%s = 1;\n' "$i" > "$R/src/f$i.js"; arqs="$arqs${arqs:+,}src/f$i.js"; i=$((i + 1)); done
revisa "$R" T-01.01 "$arqs"
fechar "$R" -- $(printf '%s' "$arqs" | tr ',' ' ')
[ "$(cat "$D/revisar.out")" = 'T-01.01 incompleta:L1:41' ] && [ "$RC" = 0 ] && [ "$(revisao_de "$R")" = incompleta:L1 ] \
  && ok 'evidencia incompleta no commit: revisao: incompleta:L1' \
  || falha "evidencia incompleta — revisar=$(cat "$D/revisar.out") rc=$RC item=$(ultimo "$R") saida=$SAIDA"

if command -v codeant >/dev/null 2>&1; then
  ok 'cli ausente: revisao: indisponivel:cli-ausente (pulado: ha um codeant no PATH)'
else
  R="$D/indisponivel"; repo "$R"
  printf 'muda\n' >> "$R/src/a.js"
  (cd "$R" && node "$(nativo "$R/$NUCLEO_REL/expx-revisao.mjs")" revisar --trabalho ft-r --task T-01.01 \
     --arquivos src/a.js > "$D/revisar.out" 2>&1)
  fechar "$R" -- src/a.js
  [ "$RC" = 0 ] && [ "$(revisao_de "$R")" = indisponivel:cli-ausente ] \
    && ok 'cli ausente: revisao: indisponivel:cli-ausente' \
    || falha "cli ausente — revisar=$(cat "$D/revisar.out") rc=$RC item=$(ultimo "$R") saida=$SAIDA"
fi

if [ "$FALSA" = 1 ]; then
  R="$D/achados"; repo "$R"
  printf 'const a = 1;\n' > "$R/src/a.js"
  revisa "$R" T-01.01 src/a.js "$D/resp-achado.json"
  fechar "$R" -- src/a.js
  [ "$RC" = 0 ] && [ "$(revisao_de "$R")" = achados ] \
    && ok 'achado aberto: revisao: achados' \
    || falha "achado aberto — revisar=$(cat "$D/revisar.out") rc=$RC item=$(ultimo "$R") saida=$SAIDA"
else
  ok 'achado aberto: revisao: achados (o CI em Linux cobre)'
fi

R="$D/temporario"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
mkdir -p "$R/$REVISAO_REL"; printf '{}\n' > "$R/$REVISAO_REL/T-01.01.json.123.tmp"
fechar "$R" -- img/logo.png
[ "$RC" = 10 ] && [ "$(git -C "$R" rev-list --count HEAD)" = 1 ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] \
  && case "$SAIDA" in *"$REVISAO_REL/T-01.01.json.123.tmp"*) true ;; *) false ;; esac \
  && ok 'T-01.01.json.123.tmp sob revisao/ e desvio' \
  || falha "temporario sob revisao/ — rc=$RC saida=$SAIDA"

R="$D/link"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
mkdir -p "$R/$REVISAO_REL"
if ln -s ../ENTREGA.md "$R/$REVISAO_REL/T-01.01.json" 2>/dev/null && [ -L "$R/$REVISAO_REL/T-01.01.json" ]; then
  fechar "$R" -- img/logo.png
  [ "$RC" = 10 ] && ok 'link simbolico com o nome da evidencia e desvio' || falha "link simbolico — rc=$RC saida=$SAIDA"
else
  ok 'link simbolico com o nome da evidencia e desvio (sem link simbolico aqui; o CI em Linux cobre)'
fi

R="$D/preparar"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
SAIDA="$(cd "$R" && bash "$FECHA" --preparar --entrega "$ENTREGA_REL" --task T-01.01 --mensagem "$MSG" -- img/logo.png 2>&1)"; RC=$?
TOKEN="$(printf '%s\n' "$SAIDA" | sed -n 's/^token=//p')"
estagio="$(git -C "$R" diff --cached --name-only | LC_ALL=C sort | tr '\n' ' ')"
SAIDA2="$(cd "$R" && bash "$FECHA" --concluir --entrega "$ENTREGA_REL" --task T-01.01 --mensagem "$MSG" --token "$TOKEN" 2>&1)"; RC2=$?
[ "$RC" = 0 ] && [ "$estagio" = "$REVISAO_REL/T-01.01.json img/logo.png " ] && [ "$RC2" = 0 ] \
  && [ "$(no_commit "$R")" = "$REVISAO_REL/T-01.01.json img/logo.png " ] && [ "$(revisao_de "$R")" = ok ] \
  && ok '--preparar põe a evidencia no stage e o --concluir a commita' \
  || falha "--preparar/--concluir — rc=$RC stage=$estagio rc2=$RC2 saida=$SAIDA $SAIDA2"

R="$D/existente"; repo "$R"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
git -C "$R" add img/logo.png "$REVISAO_REL/T-01.01.json" && git -C "$R" commit -q -F "$MSG"
sha="$(git -C "$R" rev-parse HEAD)"
SAIDA="$(cd "$R" && bash "$FECHA" --registrar-existente --entrega "$ENTREGA_REL" --origem sprintx \
  --trabalho ft-r --task T-01.01 --sha "$sha" 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ "$(revisao_de "$R")" = ok ] \
  && ok '--registrar-existente tambem registra a revisao do commit' \
  || falha "--registrar-existente — rc=$RC item=$(ultimo "$R") saida=$SAIDA"

# o hook, em bloqueio: a evidência da task atual no stage não é mistura nem desvio
R="$D/hook"; repo "$R"
printf '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"bloqueio"}}}\n' > "$R/.expx/hooks.json"
printf 'png\n' > "$R/img/logo.png"
revisa "$R" T-01.01 img/logo.png
git -C "$R" add img/logo.png "$REVISAO_REL/T-01.01.json"
entrada="$(jq -cn --arg c "git commit -F $MSG" --arg d "$R" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
saida_hook="$(printf '%s' "$entrada" | bash "$HOOK" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -z "$saida_hook" ] \
  && ok 'hook commit-por-task aceita a evidencia da task atual no stage' \
  || falha "hook commit-por-task — rc=$rc saida=$saida_hook"

# contrato: 01-commits nomeia a exceção exata, e a frase antiga sem exceção sumiu
COMMITS_MD="$REPO/.claude/skills/mergex/references/01-commits.md"
grep -Fq 'docs/entregas/<trabalho_id>/revisao/<T-NN.MM>.json' "$COMMITS_MD" \
  && grep -Fq '**A evidência de revisão da task atual é a exceção**' "$COMMITS_MD" \
  && ok '01-commits nomeia a excecao da evidencia de revisao' \
  || falha '01-commits nomeia a excecao da evidencia de revisao'
grep -Fq 'Eles **nunca contam como desvio** e **não entram no commit de uma task**: o inventário' "$COMMITS_MD" \
  && falha '01-commits ainda tem a frase antiga sem a excecao' \
  || ok '01-commits nao tem mais a frase antiga sem a excecao'

printf '\n%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
