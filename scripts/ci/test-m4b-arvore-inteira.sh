#!/usr/bin/env bash
#
# Bancada P0.2-C7-B / M4-B — o E1 inspeciona a árvore inteira antes do staging.
#
# A lista de caminhos que o agente passa ao E1 nunca limita a barreira: todo
# produto dirty é classificado contra o ownership da task atual, e o artefato
# de método do trabalho corrente é reconhecido pelo catálogo do M2. Ela também
# nunca é ampliada: produto da task atual que não foi listado barra (código 11)
# em vez de ser absorvido no commit (DM-173). Nenhum
# caso aqui roda o hook de escopo da SprintX: a árvore é suja por escrita
# direta, que é exatamente o que sobra quando aquele hook estoura o timeout ou
# é contornado.
#
# Uso: bash scripts/ci/test-m4b-arvore-inteira.sh
#

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
FECHA="${FECHA:-$SCRIPTS/fechamento-do-e1.sh}"
OWN="${OWN:-$SCRIPTS/ownership-da-task.sh}"
PROVA="${PROVA:-$SCRIPTS/prova-de-commit.sh}"
V9_HOOK="$REPO/.claude/hooks/mergex/arquivo-fora-do-plano.sh"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 — obteve '$3', esperava '$2'"; fi; }
contem() { case "$2" in *"$3"*) ok "$1" ;; *) falha "$1 — '$3' ausente em: $2" ;; esac; }

TASKS_REL='docs/sprintx/features/ft-m4/sprint-01/tasks.md'
ENTREGA_REL='docs/entregas/ft-m4/ENTREGA.md'

plano() { # <arquivo> <altera da T-01.01> <cria da T-01.01> <altera da T-01.02> <cria da T-01.02>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-m4
tasks:
  - id: T-01.01
    titulo: Task atual
    status: concluida
    suite: parcial
    arquivos:
      cria: [$3]
      altera: [$2]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-01.02
    titulo: Task irmã
    status: pendente
    suite: nao_executada
    arquivos:
      cria: [$5]
      altera: [$4]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
---
YAML
}

PLANO_PADRAO_ATUAL='src/a.js, src/b.js, src/comum.js'
PLANO_PADRAO_ATUAL_CRIA='src/novo.js'
PLANO_PADRAO_IRMA='src/x.js, src/comum.js, src/x-old.js'
PLANO_PADRAO_IRMA_CRIA='src/x-novo.js, test/x.test.js'

repo() { # <dir>
  local dir="$1"
  git init -q -b feature/ft-m4 "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src docs/sprintx/features/ft-m4 docs/entregas/ft-m4
    for f in a b comum x x-old y; do printf 'base %s\n' "$f" > "src/$f.js"; done
    plano "$TASKS_REL" "$PLANO_PADRAO_ATUAL" "$PLANO_PADRAO_ATUAL_CRIA" \
      "$PLANO_PADRAO_IRMA" "$PLANO_PADRAO_IRMA_CRIA"
    cat > docs/sprintx/features/ft-m4/ORQUESTRADOR.md <<'YAML'
---
kind: orquestrador
trabalho_id: ft-m4
---
YAML
    cat > "$ENTREGA_REL" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: ft-m4
entregue_por: mergex
estado: aberto
versionado: true
branch: feature/ft-m4
branch_base: main
commits: []
desvios: []
criado_em: 2026-09-25
atualizado_em: 2026-09-25
---
YAML
    git add -A && git commit -qm 'chore: base'
  )
}

MSG="$D/e1.msg"
printf 'fix(src): fecha T-01.01\n\nObjetivo da task.\n\nTask: T-01.01\nTrabalho: ft-m4\n' > "$MSG"

fechar() { # <dir> <caminhos...>
  local dir="$1"; shift
  SAIDA="$(cd "$dir" && bash "$FECHA" --fechar --entrega "$ENTREGA_REL" --task T-01.01 \
    --mensagem "$MSG" -- "$@" 2>&1)"
  RC=$?
}

commits() { git -C "$1" rev-list --count HEAD; }
stage() { git -C "$1" diff --cached --name-only; }
no_commit() { git -C "$1" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' ' '; }
seqs() { grep -Ec '^[[:space:]]*-[[:space:]]+seq:' "$1/$ENTREGA_REL"; }
trava_livre() {
  ( cd "$1" && bash "$SCRIPTS/trava-do-e1.sh" --status 2>/dev/null ) | grep -q '^estado=livre'
}
v11() { bash "$PROVA" --verificar "$1/$ENTREGA_REL" "$1/$TASKS_REL" >/dev/null 2>&1; }

barrado_sem_efeito() { # <descricao> <dir> <rc esperado> <commits antes> <seqs antes>
  igual "$1: código" "$3" "$RC"
  igual "$1: stage vazio" '' "$(stage "$2")"
  igual "$1: nenhum commit" "$4" "$(commits "$2")"
  igual "$1: nenhum seq" "$5" "$(seqs "$2")"
  trava_livre "$2" && ok "$1: trava liberada" || falha "$1: trava ficou presa"
}

echo '1. Bypass do hook de escopo: irmã editada direto, E1 real barra'
R="$D/bypass"; repo "$R"
# Nenhum hook SprintX roda aqui: é a escrita que sobra quando o PreToolUse
# estoura o timeout. A MergeX tem de barrar sozinha.
printf 'muda\n' >> "$R/src/a.js"
printf 'escrito sem hook\n' >> "$R/src/x.js"
fechar "$R" src/a.js
barrado_sem_efeito 'bypass' "$R" 8 1 0
grep -q 'escrito sem hook' "$R/src/x.js" && ok 'bypass: a alteração da irmã fica na árvore' \
  || falha 'bypass: a alteração da irmã foi descartada'

echo
echo '2. Irmã omitida nos argumentos continua barrando (--fechar e --preparar)'
R="$D/omitida"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; printf 'muda\n' >> "$R/src/x.js"
fechar "$R" src/a.js
barrado_sem_efeito 'irmã omitida' "$R" 8 1 0
contem 'irmã omitida: a mensagem nomeia o arquivo' "$SAIDA" 'src/x.js'
SAIDA="$(cd "$R" && bash "$FECHA" --preparar --entrega "$ENTREGA_REL" --task T-01.01 \
  --mensagem "$MSG" -- src/a.js 2>&1)"; RC=$?
barrado_sem_efeito 'irmã omitida no --preparar' "$R" 8 1 0

echo
echo '2b. Irmã que suja a árvore entre --preparar e --concluir barra o --concluir'
R="$D/entre-tempos"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
SAIDA="$(cd "$R" && bash "$FECHA" --preparar --entrega "$ENTREGA_REL" --task T-01.01 \
  --mensagem "$MSG" -- src/a.js 2>&1)"; RC=$?
TOKEN="$(printf '%s\n' "$SAIDA" | sed -n 's/^token=//p')"
igual 'entre tempos: preparar conclui' 0 "$RC"
printf 'muda\n' >> "$R/src/x.js"
SAIDA="$(cd "$R" && bash "$FECHA" --concluir --entrega "$ENTREGA_REL" --task T-01.01 \
  --mensagem "$MSG" --token "$TOKEN" 2>&1)"; RC=$?
igual 'entre tempos: concluir barra com a condição da irmã' 8 "$RC"
igual 'entre tempos: nenhum commit' 1 "$(commits "$R")"
igual 'entre tempos: nenhum seq' 0 "$(seqs "$R")"
igual 'entre tempos: stage preparado preservado' src/a.js "$(stage "$R")"

echo
echo '3. Desvio omitido é descoberto e preservado'
R="$D/desvio"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
printf 'fora do plano\n' >> "$R/src/y.js"
fechar "$R" src/a.js
barrado_sem_efeito 'desvio rastreado omitido' "$R" 10 1 0
contem 'desvio: a mensagem nomeia o arquivo' "$SAIDA" 'src/y.js'
grep -q 'fora do plano' "$R/src/y.js" && ok 'desvio: alteração preservada' || falha 'desvio: alteração perdida'
R="$D/desvio-novo"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
printf 'rascunho\n' > "$R/src/rascunho.js"
fechar "$R" src/a.js
barrado_sem_efeito 'desvio não rastreado omitido' "$R" 10 1 0
[ -f "$R/src/rascunho.js" ] && ok 'desvio novo: arquivo preservado' || falha 'desvio novo: arquivo apagado'

echo
echo '4. Produto da task atual omitido é classificado e barra: nunca é absorvido'
R="$D/atual-omitido"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; printf 'muda\n' >> "$R/src/b.js"
fechar "$R" src/a.js
barrado_sem_efeito 'atual omitido' "$R" 11 1 0
contem 'atual omitido: a mensagem nomeia o omitido' "$SAIDA" 'src/b.js'
git -C "$R" status --porcelain -- src/b.js | grep -q . \
  && ok 'atual omitido: a alteração fica na árvore' || falha 'atual omitido: a alteração sumiu'
fechar "$R" src/a.js src/b.js
igual 'atual listado: E1 conclui' 0 "$RC"
igual 'atual listado: o commit tem exatamente A e B' 'src/a.js src/b.js ' "$(no_commit "$R")"

echo
echo '5. Atual + irmã (declarado nas duas): listado, a atual vence; omitido, barra'
R="$D/comum"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; printf 'muda\n' >> "$R/src/comum.js"
fechar "$R" src/a.js
barrado_sem_efeito 'comum omitido' "$R" 11 1 0
fechar "$R" src/a.js src/comum.js
igual 'comum listado: E1 conclui' 0 "$RC"
igual 'comum listado: entra no commit da atual' 'src/a.js src/comum.js ' "$(no_commit "$R")"

echo
echo '6. Método dirty + produto atual: método fica fora do E1'
R="$D/metodo-atual"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
printf '\nnota de execução\n' >> "$R/$TASKS_REL"
printf '\nnota da entrega\n' >> "$R/$ENTREGA_REL"
printf 'fechamento\n' > "$R/docs/sprintx/features/ft-m4/FECHAMENTO.md"
fechar "$R" src/a.js
igual 'método + atual: E1 conclui' 0 "$RC"
igual 'método + atual: o commit tem só o produto' 'src/a.js ' "$(no_commit "$R")"
git -C "$R" status --porcelain -- "$TASKS_REL" | grep -q . \
  && ok 'método + atual: tasks.md continua dirty para o checkpoint' \
  || falha 'método + atual: tasks.md foi consumido pelo E1'
git -C "$R" status --porcelain -- docs/sprintx/features/ft-m4/FECHAMENTO.md | grep -q . \
  && ok 'método + atual: FECHAMENTO.md continua dirty' || falha 'método + atual: FECHAMENTO.md entrou no E1'
igual 'método + atual: um seq registrado' 1 "$(seqs "$R")"
# Segundo E1 com a ENTREGA já suja pelo primeiro append: método, não desvio.
printf 'muda de novo\n' >> "$R/src/b.js"
fechar "$R" src/b.js
igual 'método + atual: segundo E1 com ENTREGA dirty conclui' 0 "$RC"
igual 'método + atual: dois seqs' 2 "$(seqs "$R")"

echo
echo '7. Método dirty + irmã: o método não esconde a irmã'
R="$D/metodo-irma"; repo "$R"
printf '\nnota\n' >> "$R/$TASKS_REL"; printf '\nnota\n' >> "$R/$ENTREGA_REL"
printf 'muda\n' >> "$R/src/a.js"; printf 'muda\n' >> "$R/src/x.js"
fechar "$R" src/a.js
barrado_sem_efeito 'método + irmã' "$R" 8 1 0

echo
echo '8. Produto com nome parecido com método continua produto'
for alvo in docs/sprintx/features/ft-m4/notas.js docs/entregas/ft-m4/extra.md \
            src/docs/entregas/ft-m4/ENTREGA.md docs/sprintx/features/outra/sprint-01/tasks.md \
            docs/sprintx/features/ft-m4/sprint-1/tasks.md docs/sprintx/estimativas/OUTRO.md; do
  R="$D/parecido-$(printf '%s' "$alvo" | tr '/.' '__')"; repo "$R"
  mkdir -p "$R/$(dirname "$alvo")"; printf 'produto\n' > "$R/$alvo"
  printf 'muda\n' >> "$R/src/a.js"
  fechar "$R" src/a.js
  igual "parecido $alvo: é desvio" 10 "$RC"
  igual "parecido $alvo: nenhum commit" 1 "$(commits "$R")"
done

echo
echo '9. Rename de arquivo só da irmã barra por origem e por destino'
R="$D/rename-origem"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
mv "$R/src/x-old.js" "$R/src/novo.js"; git -C "$R" add -N src/novo.js
case "$(git -C "$R" status --porcelain=v1 --untracked-files=all)" in
  *' R src/novo.js'*|*' R src/x-old.js -> src/novo.js'*) ok 'rename: o Git reporta rename na árvore' ;;
  *) falha "rename: fixture não produziu rename: $(git -C "$R" status --porcelain=v1)" ;;
esac
igual 'rename: stage de entrada continua vazio' '' "$(stage "$R")"
fechar "$R" src/a.js
barrado_sem_efeito 'rename irmã → atual (origem da irmã)' "$R" 8 1 0
contem 'rename: a origem é nomeada' "$SAIDA" 'src/x-old.js'
R="$D/rename-destino"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
mv "$R/src/b.js" "$R/src/x-novo.js"; git -C "$R" add -N src/x-novo.js
fechar "$R" src/a.js
barrado_sem_efeito 'rename atual → irmã (destino da irmã)' "$R" 8 1 0
contem 'rename: o destino é nomeado' "$SAIDA" 'src/x-novo.js'

echo
echo '10. Não rastreado só da irmã barra'
R="$D/untracked"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; printf 'novo\n' > "$R/src/x-novo.js"
fechar "$R" src/a.js
barrado_sem_efeito 'untracked irmã' "$R" 8 1 0
[ -f "$R/src/x-novo.js" ] && ok 'untracked irmã: arquivo preservado' || falha 'untracked irmã: arquivo apagado'

echo
echo '11. Removido só da irmã barra'
R="$D/deleted"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; rm "$R/src/x.js"
fechar "$R" src/a.js
barrado_sem_efeito 'deleted irmã' "$R" 8 1 0
[ ! -e "$R/src/x.js" ] && ok 'deleted irmã: a remoção não foi desfeita' || falha 'deleted irmã: arquivo restaurado'

echo
echo '12. Stage preexistente vence antes do inventário'
R="$D/stage"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"; git -C "$R" add src/a.js
printf 'muda\n' >> "$R/src/x.js"
antes="$(git -C "$R" diff --cached)"
fechar "$R" src/a.js
igual 'stage: código C5 vence a irmã' 3 "$RC"
igual 'stage: índice byte a byte igual' "$antes" "$(git -C "$R" diff --cached)"
igual 'stage: nenhum commit' 1 "$(commits "$R")"

echo
echo '13–15. Seq e V11: barrado não prova nada; válido prova'
R="$D/v11"; repo "$R"
v11 "$R" && falha 'V11 passou antes de qualquer E1' || ok 'V11 falha antes do E1'
printf 'muda\n' >> "$R/src/a.js"; printf 'muda\n' >> "$R/src/x.js"
fechar "$R" src/a.js
igual 'barrado: código' 8 "$RC"
igual 'barrado não consome seq' 0 "$(seqs "$R")"
igual 'barrado não grava item em ENTREGA.commits' '' \
  "$(bash "$PROVA" --commits "$R/$ENTREGA_REL" 2>/dev/null)"
v11 "$R" && falha 'barrado satisfez a V11' || ok 'barrado não satisfaz a V11'
# Replanejado pela sprintx: a atual passa a declarar x.js.
plano "$R/$TASKS_REL" "src/a.js, src/b.js, src/comum.js, src/x.js" "$PLANO_PADRAO_ATUAL_CRIA" \
  "$PLANO_PADRAO_IRMA" "$PLANO_PADRAO_IRMA_CRIA"
fechar "$R" src/a.js src/x.js
igual 'válido: E1 conclui' 0 "$RC"
igual 'válido: seq 1' 1 "$(seqs "$R")"
v11 "$R" && ok 'E1 válido satisfaz a V11' || falha 'E1 válido não satisfez a V11'

echo
echo '16. TDD-first: teste parcial preservado + implementação, depois do replanejamento'
R="$D/tdd"; repo "$R"
mkdir -p "$R/test"; printf 'teste parcial preservado\n' > "$R/test/x.test.js"
printf 'implementação\n' >> "$R/src/x.js"
fechar "$R" src/a.js
igual 'TDD antes do replanejamento: irmã barra' 8 "$RC"
plano "$R/$TASKS_REL" "src/a.js, src/b.js, src/comum.js, src/x.js" "src/novo.js, test/x.test.js" \
  "src/comum.js, src/x-old.js" "src/x-novo.js"
fechar "$R" src/x.js
igual 'TDD replanejado, teste preservado não listado: barra' 11 "$RC"
igual 'TDD replanejado sem lista completa: nenhum commit' 1 "$(commits "$R")"
fechar "$R" src/x.js test/x.test.js
igual 'TDD depois do replanejamento, lista completa: E1 conclui' 0 "$RC"
igual 'TDD: teste preservado e implementação entram juntos' 'src/x.js test/x.test.js ' "$(no_commit "$R")"
git -C "$R" status --porcelain -- "$TASKS_REL" | grep -q . \
  && ok 'TDD: o plano replanejado fica para o checkpoint de método' \
  || falha 'TDD: o plano replanejado entrou no E1'

echo
echo '17. Duas worktrees continuam independentes'
R="$D/wt-a"; repo "$R"
if git -C "$R" worktree add -q -b feature/ft-m4-b "$D/wt-b" >/dev/null 2>&1; then
  printf 'muda\n' >> "$D/wt-b/src/x.js"
  printf 'muda\n' >> "$R/src/a.js"
  fechar "$R" src/a.js
  igual 'worktree A: a irmã suja na B não barra a A' 0 "$RC"
  igual 'worktree A: commit só com A' 'src/a.js ' "$(no_commit "$R")"
  printf 'muda\n' >> "$D/wt-b/src/a.js"
  fechar "$D/wt-b" src/a.js
  igual 'worktree B: a própria irmã barra a B' 8 "$RC"
  igual 'worktree B: stage da B vazio' '' "$(stage "$D/wt-b")"
else
  falha 'worktree vinculada não pôde ser criada'
fi

echo
echo '18. V9 continua sendo a união da feature'
R="$D/v9"; repo "$R"
printf 'muda\n' >> "$R/src/x.js"; git -C "$R" add src/x.js
CARGA="$(jq -cn --arg c "git commit -m 'fix: x

Task: T-01.01
Trabalho: ft-m4'" --arg w "$R" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}')"
V9_SAIDA="$(printf '%s' "$CARGA" | (cd "$R" && bash "$V9_HOOK") 2>&1)"; V9_RC=$?
igual 'V9: o hook de escopo aceita o arquivo da irmã' 0 "$V9_RC"
igual 'V9: nenhum aviso de arquivo fora do plano' '' "$V9_SAIDA"
CLASSE="$(cd "$R" && printf 'src/x.js\n' | bash "$OWN" --classificar . sprintx ft-m4 T-01.01 2>/dev/null)"
igual 'V9: o arquivo da irmã está na união (não é desvio)' 'arquivo_de_task_irma' \
  "$(printf '%s\n' "$CLASSE" | awk -F'\t' '$2 == "src/x.js" { print $1 }')"

echo
echo '---------------------------------------------'
printf '%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
