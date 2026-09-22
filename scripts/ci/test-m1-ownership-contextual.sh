#!/usr/bin/env bash
#
# Bancada P0.2-C7-B / M1 — ownership resolvido pelo trabalho corrente.
#
# Exercita o contrato público dos dois executáveis reais. Os fixtures mantêm
# uma feature histórica com o mesmo id de task para provar que pasta/ordem não
# escolhem ownership; os casos E1 provam que contexto, footers e classificação
# falham antes do primeiro staging.
#
# Uso: bash scripts/ci/test-m1-ownership-contextual.sh
#

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
OWNERSHIP="${OWNERSHIP:-$SCRIPTS/ownership-da-task.sh}"
FECHA="${FECHA:-$SCRIPTS/fechamento-do-e1.sh}"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 — obteve '$3', esperava '$2'"; fi; }

classifica() { # <raiz> <origem> <trabalho> <task> <arquivos...>
  local raiz="$1" origem="$2" trabalho="$3" task="$4"; shift 4
  SAIDA="$(bash "$OWNERSHIP" --classificar "$raiz" "$origem" "$trabalho" "$task" "$@" 2>&1)"
  RC=$?
}

situacao_de() { printf '%s\n' "$1" | awk -F'\t' -v a="$2" '$2 == a { print $1; exit }'; }

plano() { # <raiz> <trabalho> <arquivo-atual> <arquivo-irma>
  local raiz="$1" trabalho="$2" atual="$3" irma="$4"
  local p="$raiz/docs/sprintx/features/$trabalho/sprint-01/tasks.md"
  mkdir -p "$(dirname "$p")"
  cat > "$p" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: $trabalho
tasks:
  - id: T-01.01
    status: concluida
    arquivos:
      cria: [$atual]
      altera: [src/comum.js]
    suite: verde
  - id: T-01.02
    status: concluida
    arquivos:
      cria: [$irma]
      altera: [src/comum.js, src/irma-2.js]
    suite: verde
---
YAML
}

echo '1–8. O plano vem somente do trabalho corrente, nunca do id global'
R1="$D/contexto-a"; mkdir -p "$R1"
plano "$R1" aaa-historica src/x.js src/historica-irma.js
plano "$R1" zzz-corrente src/y.js src/corrente-irma.js
classifica "$R1" sprintx zzz-corrente T-01.01 src/x.js src/y.js src/comum.js src/corrente-irma.js src/orfao.js
igual 'plano histórico alfabeticamente primeiro não governa' desvio "$(situacao_de "$SAIDA" src/x.js)"
igual 'arquivo da task corrente entra' na_task_atual "$(situacao_de "$SAIDA" src/y.js)"
igual 'current+sibling: a atual vence' na_task_atual "$(situacao_de "$SAIDA" src/comum.js)"
igual 'sibling-only continua irmã' arquivo_de_task_irma "$(situacao_de "$SAIDA" src/corrente-irma.js)"
igual 'no-task continua desvio' desvio "$(situacao_de "$SAIDA" src/orfao.js)"
igual 'uma irmã bloqueia o conjunto' 2 "$RC"

R2="$D/contexto-b"; mkdir -p "$R2"
plano "$R2" zzz-historica src/y.js src/historica-irma.js
plano "$R2" aaa-corrente src/x.js src/irma-1.js
classifica "$R2" sprintx aaa-corrente T-01.01 src/x.js src/y.js src/irma-1.js src/irma-2.js
igual 'ordem das features invertida mantém o plano corrente' na_task_atual "$(situacao_de "$SAIDA" src/x.js)"
igual 'o inverso: arquivo só histórico não pertence à atual' desvio "$(situacao_de "$SAIDA" src/y.js)"
igual 'duas irmãs são classificadas pela feature corrente' 2 "$RC"
igual 'primeira irmã preservada' arquivo_de_task_irma "$(situacao_de "$SAIDA" src/irma-1.js)"
igual 'segunda irmã preservada' arquivo_de_task_irma "$(situacao_de "$SAIDA" src/irma-2.js)"

echo
echo '9–12. Aplicabilidade explícita e falha fechada do plano corrente'
classifica "$D" n/a sem-task-model n/a qualquer.js
igual 'origem realmente sem task model retorna n/a' 0 "$RC"
igual 'n/a é explícito, não ausência acidental de plano' 'ownership=n/a' "$SAIDA"

SEM="$D/sem-plano"; mkdir -p "$SEM/docs/sprintx/features/corrente"
classifica "$SEM" sprintx corrente T-01.01 src/a.js
igual 'plano corrente ausente é erro de contrato' 1 "$RC"
case "$SAIDA" in *'plano corrente ausente'*) ok 'erro nomeia plano corrente ausente' ;; *) falha "erro ausente não foi explicado: $SAIDA" ;; esac

ILEG="$D/ilegivel"; mkdir -p "$ILEG/docs/sprintx/features/corrente/sprint-01/tasks.md"
classifica "$ILEG" sprintx corrente T-01.01 src/a.js
igual 'plano corrente ilegível é erro de contrato' 1 "$RC"
case "$SAIDA" in *'plano corrente ileg'*) ok 'erro nomeia plano corrente ilegível' ;; *) falha "erro ilegível não foi explicado: $SAIDA" ;; esac

classifica "$SEM" origem-desconhecida corrente T-01.01 src/a.js
igual 'origem ambígua não inventa heurística global' 1 "$RC"

entrega() { # <arquivo> <trabalho>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: $2
entregue_por: mergex
estado: aberto
versionado: true
branch: feature/$2
branch_base: main
commits: []
desvios: []
criado_em: 2026-09-21
atualizado_em: 2026-09-21
---
YAML
}

repo_e1() { # <dir>
  local dir="$1"
  git init -q -b main "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src
    printf 'base\n' > src/atual.js
    printf 'base\n' > src/irma.js
    entrega docs/entregas/ft-m1/ENTREGA.md ft-m1
    plano . ft-m1 src/atual.js src/irma.js
    git add -A && git commit -qm 'chore: base'
  )
}

mensagem() { # <arquivo> <task-footer> <trabalho-footer> [duplicar-task] [duplicar-trabalho]
  local arq="$1" task="$2" trabalho="$3" dup_task="${4:-}" dup_trabalho="${5:-}"
  {
    printf 'fix(src): fecha T-01.01\n\nObjetivo.\n\n'
    [ "$task" != ausente ] && printf 'Task: %s\n' "$task"
    [ "$dup_task" = duplicar ] && printf 'Task: %s\n' "$task"
    [ "$trabalho" != ausente ] && printf 'Trabalho: %s\n' "$trabalho"
    [ "$dup_trabalho" = duplicar ] && printf 'Trabalho: %s\n' "$trabalho"
    printf 'Testes: integracao e funcional.\n'
  } > "$arq"
}

executa_e1() { # <dir> <mensagem> <paths...>
  local dir="$1" msg="$2"; shift 2
  SAIDA="$(cd "$dir" && bash "$FECHA" --fechar \
    --entrega docs/entregas/ft-m1/ENTREGA.md --task T-01.01 \
    --mensagem "$msg" -- "$@" 2>&1)"
  RC=$?
}

assert_sem_stage_commit() { # <descricao> <dir> <commits-antes>
  igual "$1: stage vazio" "$(git -C "$2" diff --cached --name-only)" ''
  igual "$1: nenhum commit" "$(git -C "$2" rev-list --count HEAD)" "$3"
}

echo
echo '13–18. Task/Trabalho são provas exatas antes do staging'
for caso in task-ausente task-duplicada task-divergente trabalho-ausente trabalho-duplicado trabalho-divergente; do
  R="$D/$caso"; repo_e1 "$R"
  msg="$D/$caso.msg"
  case "$caso" in
    task-ausente)       mensagem "$msg" ausente ft-m1 ;;
    task-duplicada)     mensagem "$msg" T-01.01 ft-m1 duplicar ;;
    task-divergente)    mensagem "$msg" T-99.99 ft-m1 ;;
    trabalho-ausente)  mensagem "$msg" T-01.01 ausente ;;
    trabalho-duplicado) mensagem "$msg" T-01.01 ft-m1 '' duplicar ;;
    trabalho-divergente) mensagem "$msg" T-01.01 outro ;;
  esac
  printf 'muda\n' >> "$R/src/atual.js"
  executa_e1 "$R" "$msg" src/atual.js
  [ "$RC" != 0 ] && ok "$caso: E1 para" || falha "$caso: E1 deixou passar"
  case "$SAIDA" in *'rodapé'*) ok "$caso: erro aponta o rodapé" ;; *) falha "$caso: erro não aponta rodapé: $SAIDA" ;; esac
  assert_sem_stage_commit "$caso" "$R" 1
done

R="$D/task-so-na-prosa"; repo_e1 "$R"
cat > "$D/task-so-na-prosa.msg" <<'MSG'
fix(src): fecha T-01.01

Task: T-01.01
Esta linha ainda pertence à prosa da mensagem.

Trabalho: ft-m1
Testes: integração e funcional.
MSG
printf 'muda\n' >> "$R/src/atual.js"
executa_e1 "$R" "$D/task-so-na-prosa.msg" src/atual.js
[ "$RC" != 0 ] && ok 'Task em prosa não é aceita como footer' \
  || falha 'Task em prosa foi inferida como footer'
assert_sem_stage_commit 'Task em prosa' "$R" 1

echo
echo '19. Stage preexistente vence antes do ownership e dos footers'
R="$D/stage"; repo_e1 "$R"; mensagem "$D/stage.msg" T-99.99 outro
printf 'alheio\n' >> "$R/src/irma.js"; git -C "$R" add src/irma.js
antes="$(git -C "$R" diff --cached)"
printf 'muda\n' >> "$R/src/atual.js"
executa_e1 "$R" "$D/stage.msg" src/atual.js
igual 'stage preexistente mantém código soberano' 3 "$RC"
igual 'stage preexistente fica byte a byte igual' "$antes" "$(git -C "$R" diff --cached)"

echo
echo '20–22. Desvio/irmã não entram; E1 válido continua commitando'
R="$D/desvio"; repo_e1 "$R"; mensagem "$D/desvio.msg" T-01.01 ft-m1
printf 'muda\n' >> "$R/src/atual.js"; printf 'orfao\n' > "$R/src/orfao.js"
executa_e1 "$R" "$D/desvio.msg" src/atual.js src/orfao.js
[ "$RC" != 0 ] && ok 'desvio para o E1 normativo' || falha 'desvio entrou no commit'
assert_sem_stage_commit 'desvio' "$R" 1
[ -f "$R/src/orfao.js" ] && ok 'desvio permanece na árvore' || falha 'desvio foi apagado/restaurado'

R="$D/irma"; repo_e1 "$R"; mensagem "$D/irma.msg" T-01.01 ft-m1
printf 'muda\n' >> "$R/src/atual.js"; printf 'muda\n' >> "$R/src/irma.js"
executa_e1 "$R" "$D/irma.msg" src/atual.js src/irma.js
igual 'arquivo_de_task_irma para com o código contratual' 8 "$RC"
assert_sem_stage_commit 'arquivo_de_task_irma' "$R" 1
grep -q muda "$R/src/irma.js" && ok 'arquivo_de_task_irma permanece na árvore' || falha 'arquivo_de_task_irma foi descartado'

R="$D/valido"; repo_e1 "$R"; mensagem "$D/valido.msg" T-01.01 ft-m1
printf 'muda\n' >> "$R/src/atual.js"
executa_e1 "$R" "$D/valido.msg" src/atual.js
igual 'E1 válido continua commitando' 0 "$RC"
igual 'E1 válido criou um commit' 2 "$(git -C "$R" rev-list --count HEAD)"
igual 'commit produzido mantém Task exata' 1 "$(git -C "$R" log -1 --format=%B | grep -Ec '^Task: T-01.01$')"
igual 'commit produzido mantém Trabalho exato' 1 "$(git -C "$R" log -1 --format=%B | grep -Ec '^Trabalho: ft-m1$')"

echo
echo '23. V9 continua sendo a união do plano corrente'
classifica "$R1" sprintx zzz-corrente T-01.01 src/corrente-irma.js
igual 'irmã-only continua na união da feature corrente' arquivo_de_task_irma "$(situacao_de "$SAIDA" src/corrente-irma.js)"

echo
echo '24. Instalação task-based sem ownership falha fechada'
R="$D/sem-ownership"; repo_e1 "$R"; mensagem "$D/sem-ownership.msg" T-01.01 ft-m1
SCRIPTS_INCOMPLETOS="$D/scripts-incompletos"; mkdir -p "$SCRIPTS_INCOMPLETOS"
cp "$SCRIPTS/fechamento-do-e1.sh" "$SCRIPTS/trava-do-e1.sh" \
  "$SCRIPTS/sequencia-de-commits.sh" "$SCRIPTS/contrato-de-commit.sh" \
  "$SCRIPTS_INCOMPLETOS/"
printf 'muda\n' >> "$R/src/atual.js"
FECHA_REAL="$FECHA"; FECHA="$SCRIPTS_INCOMPLETOS/fechamento-do-e1.sh"
executa_e1 "$R" "$D/sem-ownership.msg" src/atual.js
FECHA="$FECHA_REAL"
[ "$RC" != 0 ] && ok 'script ownership ausente para o E1' || falha 'instalação incompleta degradou para n/a'
case "$SAIDA" in *'instalação MergeX incompleta'*) ok 'erro nomeia instalação MergeX incompleta' ;; *) falha "erro de instalação incompleta ausente: $SAIDA" ;; esac
assert_sem_stage_commit 'ownership ausente' "$R" 1

echo
echo '25. --preparar/--concluir preservam o mesmo contexto de ownership'
R="$D/contexto-dividido"; repo_e1 "$R"
entrega "$R/docs/entregas/ft-outra/ENTREGA.md" ft-outra
plano "$R" ft-outra src/outra.js src/outra-irma.js
(
  cd "$R" || exit 1
  git add docs/entregas/ft-outra docs/sprintx/features/ft-outra
  git commit -qm 'chore: segundo trabalho com task id repetido'
)
mensagem "$D/contexto-a.msg" T-01.01 ft-m1
mensagem "$D/contexto-b.msg" T-01.01 ft-outra
printf 'muda\n' >> "$R/src/atual.js"
SAIDA_PREP="$(cd "$R" && bash "$FECHA" --preparar \
  --entrega docs/entregas/ft-m1/ENTREGA.md --task T-01.01 \
  --mensagem "$D/contexto-a.msg" -- src/atual.js 2>&1)"
RC_PREP=$?
TOKEN_PREP="$(printf '%s\n' "$SAIDA_PREP" | sed -n 's/^token=//p')"
igual 'contexto dividido: preparar A conclui' 0 "$RC_PREP"
[ -n "$TOKEN_PREP" ] && ok 'contexto dividido: preparar A devolve token' \
  || falha 'contexto dividido: preparar A não devolveu token'
SAIDA="$(cd "$R" && bash "$FECHA" --concluir \
  --entrega docs/entregas/ft-outra/ENTREGA.md --task T-01.01 \
  --mensagem "$D/contexto-b.msg" --token "$TOKEN_PREP" 2>&1)"
RC=$?
[ "$RC" != 0 ] && ok 'contexto dividido: concluir B para' \
  || falha 'contexto dividido: stage de A foi commitado como trabalho B'
igual 'contexto dividido: nenhum commit cruzado' 2 "$(git -C "$R" rev-list --count HEAD)"
igual 'contexto dividido: stage de A fica preservado' src/atual.js "$(git -C "$R" diff --cached --name-only)"

echo
echo '26. O commit produzido é revalidado depois do hook commit-msg'
R="$D/footer-pos-commit"; repo_e1 "$R"; mensagem "$D/footer-pos-commit.msg" T-01.01 ft-m1
cat > "$R/.git/hooks/commit-msg" <<'HOOK'
#!/usr/bin/env bash
awk '!/^Trabalho:/' "$1" > "$1.mergex" && mv "$1.mergex" "$1"
HOOK
chmod +x "$R/.git/hooks/commit-msg"
printf 'muda\n' >> "$R/src/atual.js"
executa_e1 "$R" "$D/footer-pos-commit.msg" src/atual.js
igual 'footer alterado pelo hook: commit existe sem registro E1' 6 "$RC"
igual 'footer alterado pelo hook: exatamente um commit foi produzido' 2 "$(git -C "$R" rev-list --count HEAD)"
igual 'footer alterado pelo hook: Trabalho não ficou no commit' 0 \
  "$(git -C "$R" log -1 --format=%B | grep -Ec '^Trabalho:')"
igual 'footer alterado pelo hook: ENTREGA não ganhou prova falsa' 0 \
  "$(grep -Ec '^[[:space:]]+- seq:' "$R/docs/entregas/ft-m1/ENTREGA.md")"

echo
echo '---------------------------------------------'
printf '%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
