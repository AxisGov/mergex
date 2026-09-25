#!/usr/bin/env bash
#
# Bancada de integração P0.2-C7-A — compõe o ownership da task (C1) com a
# seção crítica do E1 (C5) em scripts/fechamento-do-e1.sh.
#
# Não repete os testes isolados de cada contrato: scripts/ci/test-ownership-task.sh
# prova o ownership sozinho, scripts/ci/test-trava-e1.sh prova a trava sozinha,
# .claude/hooks/teste.sh prova o hook. Esta bancada prova a COMPOSIÇÃO dos
# dois dentro do fechamento real — a ordem lock → stage → ownership → add, e o
# que acontece com seq, V11 e V9 quando o ownership barra.
#
# Sem rede, sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-integracao-c7a.sh
#      bash scripts/ci/test-integracao-c7a.sh B F           # só esses grupos

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
FECHA="$SCRIPTS/fechamento-do-e1.sh"
TRAVA="$SCRIPTS/trava-do-e1.sh"
SEQ="$SCRIPTS/sequencia-de-commits.sh"
PROVA="$SCRIPTS/prova-de-commit.sh"
OWN="$SCRIPTS/ownership-da-task.sh"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
igual() { # <descrição> <obtido> <esperado>
  if [ "$2" = "$3" ]; then ok "$1"
  else falha "$1 — obteve '$2', esperava '$3'"; fi
}

GRUPOS=" $* "
grupo() { [ "$GRUPOS" = "  " ] && return 0; case "$GRUPOS" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ---------------------------------------------------------------------------
# Fixture: repositório real com plano (T-01.01 fechando, T-01.02 irmã, já
# fechada) e ENTREGA aberta. T-01.01 declara src/a.js e src/comum.js;
# T-01.02 declara src/irma.js e src/comum.js — comum.js prova a precedência
# atual-e-irmã (DM-150) sem precisar de um segundo plano.
# ---------------------------------------------------------------------------
ENTREGA=docs/entregas/ft-integ/ENTREGA.md
PLANO=docs/sprintx/features/ft-integ/sprint-01/tasks.md

entrega_vazia() { # <arquivo>
  cat > "$1" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: ft-integ
entregue_por: mergex
estado: aberto
versionado: true
branch: feature/ft-integ
branch_base: main
commits: []
desvios: []
criado_em: 2026-09-20
atualizado_em: 2026-09-20
---

# Entrega

Prosa da entrega.
EOF
}

plano() { # <arquivo>
  cat > "$1" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-integ
tasks:
  - id: T-01.01
    titulo: Task atual
    status: concluida
    arquivos:
      cria: []
      altera: [src/a.js, src/comum.js]
    suite: verde
    teste_integracao: integra
    teste_funcional: funciona
  - id: T-01.02
    titulo: Task irma
    status: concluida
    arquivos:
      cria: [src/irma.js]
      altera: [src/comum.js]
    suite: verde
    teste_integracao: integra
    teste_funcional: funciona
---
YAML
}

tasks_concluidas() { # <arquivo> <id>...
  local arq="$1" id; shift
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: plano\ntrabalho_id: ft-integ\n'
    printf 'tasks:\n'
    for id in "$@"; do
      printf -- '  - id: %s\n    status: concluida\n    suite: verde\n' "$id"
      printf '    teste_integracao: integra\n    teste_funcional: funciona\n'
    done
    printf -- '---\n\n# Plano\n'
  } > "$arq"
}

repo() { # <dir>
  git init -q -b main "$1" 2>/dev/null
  (
    cd "$1" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src docs/entregas/ft-integ "$(dirname "$PLANO")"
    printf 'base\n' > src/a.js
    printf 'base\n' > src/irma.js
    printf 'base\n' > src/comum.js
    entrega_vazia "$ENTREGA"
    plano "$PLANO"
    git add -A >/dev/null 2>&1
    git commit -qm 'chore: base' >/dev/null 2>&1
  )
}

mensagem() { # <arquivo> <task>
  printf 'feat(src): fecha %s\n\nObjetivo da task.\n\nTask: %s\nTrabalho: ft-integ\nTestes: integracao e funcional.\n' \
    "$2" "$2" > "$1"
}

fechar() { # <dir> <task> <arquivo> [--verificacao <cmd>]
  local dir="$1" task="$2" alvo="$3"; shift 3
  mensagem "$D/msg-$task-$$.txt" "$task"
  ( cd "$dir" && bash "$FECHA" --fechar --entrega "$ENTREGA" --task "$task" \
      --mensagem "$D/msg-$task-$$.txt" "$@" -- "$alvo" )
}

trava_de()   { ( cd "$1" && bash "$TRAVA" --caminho ); }
commits_de() { ( cd "$1" && git rev-list --count HEAD ); }
itens_de()   { ( cd "$1" && bash "$SEQ" --ler "$ENTREGA" ); }
stage_de()   { ( cd "$1" && git diff --cached --name-only ); }

espera_trava() { # <dir>
  local t i=0
  t="$(trava_de "$1")"
  while [ ! -d "$t" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i+1)); done
  [ -d "$t" ]
}

v11_de() { # <dir> <tasks concluídas...>
  local dir="$1"; shift
  tasks_concluidas "$D/tasks-v11-$$.md" "$@"
  bash "$PROVA" --verificar "$dir/$ENTREGA" "$D/tasks-v11-$$.md" 2>&1 | head -1
}

if grupo A; then
  # ---------------------------------------------------------------------------
  echo 'A. Stage vazio + arquivo de task irmã: lock adquirido, ownership'
  echo '   detecta, nada é adicionado/commitado/registrado, lock liberado'
  # ---------------------------------------------------------------------------
  A="$D/a"; repo "$A"
  printf 'muda\n' >> "$A/src/irma.js"
  saida="$(fechar "$A" T-01.01 src/irma.js 2>&1)"; rc=$?
  igual 'A — código de saída arquivo_de_task_irma' "$rc" 8
  case "$saida" in *arquivo_de_task_irma*) ok 'A — o relatório nomeia a condição' ;;
    *) falha "A — sem menção à condição: $saida" ;; esac
  igual 'A — nada foi adicionado ao índice' "$(stage_de "$A")" ''
  igual 'A — nenhum commit novo' "$(commits_de "$A")" 1
  igual 'A — nenhum item novo em ENTREGA.commits' "$(itens_de "$A" | wc -l | tr -d '[:space:]')" 0
  [ -d "$(trava_de "$A")" ] && falha 'A — a trava ficou presa' || ok 'A — a trava foi liberada'
  igual 'A — V11 não ganha prova falsa (nenhum commit real existe)' \
    "$(v11_de "$A" T-01.01)" 'V11=FALHA'

fi
if grupo B; then
  # ---------------------------------------------------------------------------
  echo
  echo 'B. Stage pré-existente + arquivo de task irmã: a regra do stage (C5)'
  echo '   vence — o ownership não "explica" nem autoriza o stage alheio'
  # ---------------------------------------------------------------------------
  Bd="$D/b"; repo "$Bd"
  printf 'de outro\n' >> "$Bd/src/a.js"
  ( cd "$Bd" && git add src/a.js )
  antes_nomes="$(stage_de "$Bd")"
  antes_diff="$( cd "$Bd" && git diff --cached )"
  printf 'muda\n' >> "$Bd/src/irma.js"
  saida="$(fechar "$Bd" T-01.01 src/irma.js 2>&1)"; rc=$?
  igual 'B — PARA no código de stage preexistente (C5), não no de ownership' "$rc" 3
  igual 'B — o stage ficou com exatamente os mesmos caminhos' "$(stage_de "$Bd")" "$antes_nomes"
  igual 'B — o conteúdo em stage ficou byte a byte igual' "$( cd "$Bd" && git diff --cached )" "$antes_diff"
  igual 'B — nenhum commit foi criado' "$(commits_de "$Bd")" 1
  [ -d "$(trava_de "$Bd")" ] && falha 'B — a trava ficou presa' || ok 'B — a trava foi liberada'

fi
if grupo C; then
  # ---------------------------------------------------------------------------
  echo
  echo 'C. Arquivo na task atual E numa irmã: é da atual (DM-150) — E1 normal'
  # ---------------------------------------------------------------------------
  Cd="$D/c"; repo "$Cd"
  printf 'muda\n' >> "$Cd/src/comum.js"
  saida="$(fechar "$Cd" T-01.01 src/comum.js 2>&1)"; rc=$?
  igual 'C — código de saída 0 (o fechamento segue)' "$rc" 0
  case "$saida" in *seq=1*) ok 'C — recebeu seq 1' ;; *) falha "C — sem seq=1: $saida" ;; esac
  igual 'C — o commit foi criado' "$(commits_de "$Cd")" 2
  igual 'C — exatamente um item novo em ENTREGA.commits' "$(itens_de "$Cd" | wc -l | tr -d '[:space:]')" 1

fi
if grupo D; then
  # ---------------------------------------------------------------------------
  echo
  echo 'D. Arquivo de NENHUMA task: continua desvio — nunca arquivo_de_task_irma'
  # ---------------------------------------------------------------------------
  Dd="$D/d"; repo "$Dd"
  printf 'orfao\n' > "$Dd/src/orfao.js"
  saida="$(fechar "$Dd" T-01.01 src/orfao.js 2>&1)"; rc=$?
  igual 'D — o E1 para desvio antes do staging' "$rc" 10
  classe="$( cd "$Dd" && printf 'src/orfao.js\n' | bash "$OWN" --classificar . sprintx ft-integ T-01.01 2>&1 )"
  case "$classe" in
    *arquivo_de_task_irma*) falha 'D — arquivo de nenhuma task virou arquivo_de_task_irma' ;;
    *desvio*) ok 'D — classificado como desvio, como sempre' ;;
    *) falha "D — classificação inesperada: $classe" ;;
  esac
  igual 'D — nenhum commit parcial foi criado' "$(commits_de "$Dd")" 1
  igual 'D — nada entrou em stage' "$(stage_de "$Dd")" ''
  [ -f "$Dd/src/orfao.js" ] && ok 'D — o desvio foi preservado na árvore' \
    || falha 'D — o desvio foi apagado ou restaurado'

fi
if grupo E; then
  # ---------------------------------------------------------------------------
  echo
  echo 'E. Task irmã replanejada para declarar o arquivo na atual: o próximo'
  echo '   E1 passa'
  # ---------------------------------------------------------------------------
  Ed="$D/e"; repo "$Ed"
  printf 'muda\n' >> "$Ed/src/irma.js"
  saida="$(fechar "$Ed" T-01.01 src/irma.js 2>&1)"; rc=$?
  igual 'E — antes do replanejamento: arquivo_de_task_irma' "$rc" 8
  sed -i.bak 's#altera: \[src/a.js, src/comum.js\]#altera: [src/a.js, src/comum.js, src/irma.js]#' \
    "$Ed/$PLANO"
  rm -f "$Ed/$PLANO.bak"
  saida2="$(fechar "$Ed" T-01.01 src/irma.js 2>&1)"; rc2=$?
  igual 'E — depois do replanejamento: o E1 passa' "$rc2" 0
  igual 'E — exatamente um commit (o do E1 válido)' "$(commits_de "$Ed")" 2

fi
if grupo F; then
  # ---------------------------------------------------------------------------
  echo
  echo 'F. Ownership barra uma tentativa: o seq NÃO avança; o próximo E1'
  echo '   válido recebe o seq que receberia sem a tentativa bloqueada'
  # ---------------------------------------------------------------------------
  Fd="$D/f"; repo "$Fd"
  printf 'muda1\n' >> "$Fd/src/a.js"
  saida="$(fechar "$Fd" T-01.01 src/a.js 2>&1)"; rc=$?
  igual 'F — primeiro E1 válido conclui com 0' "$rc" 0
  case "$saida" in *seq=1*) ok 'F — primeiro recebeu seq=1' ;; *) falha "F: $saida" ;; esac
  printf 'muda2\n' >> "$Fd/src/irma.js"
  saida2="$(fechar "$Fd" T-01.01 src/irma.js 2>&1)"; rc2=$?
  igual 'F — tentativa barrada pelo ownership' "$rc2" 8
  grep -q muda2 "$Fd/src/irma.js" && ok 'F — a alteração barrada ficou na árvore' \
    || falha 'F — a alteração barrada foi descartada'
  # M4: a alteração preservada continua visível para todo E1 desta worktree.
  # Quem a resolve é o fechamento da task dona dela — que recebe o seq que
  # receberia sem a tentativa barrada.
  saida3="$(fechar "$Fd" T-01.02 src/irma.js 2>&1)"; rc3=$?
  igual 'F — próximo E1 válido (a task dona da irmã) conclui com 0' "$rc3" 0
  case "$saida3" in
    *seq=2*) ok 'F — recebeu seq=2: a tentativa barrada não consumiu seq' ;;
    *) falha "F — esperava seq=2 (a barrada não pode ter avançado o contador): $saida3" ;;
  esac
  printf 'muda3\n' >> "$Fd/src/a.js"
  saida4="$(fechar "$Fd" T-01.01 src/a.js 2>&1)"; rc4=$?
  igual 'F — árvore resolvida: a task atual volta a fechar' "$rc4" 0
  case "$saida4" in *seq=3*) ok 'F — seq=3 em sequência' ;; *) falha "F — esperava seq=3: $saida4" ;; esac
  ( cd "$Fd" && bash "$SEQ" --validar "$ENTREGA" >/dev/null 2>&1 ) \
    && ok 'F — a lista continua válida' || falha 'F — a lista ficou inválida'

fi
if grupo G; then
  # ---------------------------------------------------------------------------
  echo
  echo 'G. Task marcada concluída sem E1 (bug simulado): a V11 falha'
  # ---------------------------------------------------------------------------
  Gd="$D/g"; repo "$Gd"
  igual 'G — V11 falha: task concluída sem nenhum commit registrado' \
    "$(v11_de "$Gd" T-01.01)" 'V11=FALHA'

fi
if grupo H; then
  # ---------------------------------------------------------------------------
  echo
  echo 'H. Depois do E1 válido, a V11 passa'
  # ---------------------------------------------------------------------------
  Hd="$D/h"; repo "$Hd"
  printf 'muda\n' >> "$Hd/src/a.js"
  fechar "$Hd" T-01.01 src/a.js >/dev/null 2>&1
  igual 'H — V11 passa depois do E1 válido' "$(v11_de "$Hd" T-01.01)" 'V11=OK'

fi
if grupo I; then
  # ---------------------------------------------------------------------------
  echo
  echo 'I. Dois E1 concorrentes na MESMA worktree: a C5 continua funcionando'
  echo '   com o ownership (C1) presente'
  # ---------------------------------------------------------------------------
  # Um escritor por worktree: a segunda chamada chega com a seção ocupada e
  # para pela trava antes de qualquer classificação. Só a primeira task tem
  # produto dirty — tasks simultaneamente em voo exigem worktrees distintas
  # (grupo J), e na mesma worktree o E1 barra (I2).
  Id="$D/i"; repo "$Id"
  printf 'primeira\n' >> "$Id/src/a.js"
  ( fechar "$Id" T-01.01 src/a.js --verificacao 'sleep 3' >"$D/i1.out" 2>&1; printf '%s\n' "$?" >"$D/i1.rc" ) &
  espera_trava "$Id"
  fechar "$Id" T-01.02 src/irma.js >"$D/i2.out" 2>&1; printf '%s\n' "$?" >"$D/i2.rc"
  wait
  igual 'I — a primeira concluiu' "$(cat "$D/i1.rc")" 0
  igual 'I — a segunda PARA no código de E1 ocupado (o lock, não o ownership)' "$(cat "$D/i2.rc")" 2
  [ -d "$(trava_de "$Id")" ] && falha 'I — sobrou trava' || ok 'I — nenhuma trava sobrou'

  I2="$D/i2"; repo "$I2"
  printf 'primeira\n' >> "$I2/src/a.js"
  printf 'segunda em voo\n' >> "$I2/src/irma.js"
  fechar "$I2" T-01.01 src/a.js >"$D/i2b.out" 2>&1; rc=$?
  igual 'I2 — irmã em voo na mesma worktree barra o E1 (arquivo_de_task_irma)' "$rc" 8
  igual 'I2 — nenhum commit' "$(commits_de "$I2")" 1
  igual 'I2 — nenhum seq' "$(itens_de "$I2" | wc -l | tr -d '[:space:]')" 0
  igual 'I2 — nada no índice' "$(stage_de "$I2")" ''
  grep -q 'segunda em voo' "$I2/src/irma.js" && ok 'I2 — o trabalho em voo ficou na árvore' \
    || falha 'I2 — o trabalho em voo foi descartado'

fi
if grupo J; then
  # ---------------------------------------------------------------------------
  echo
  echo 'J. Duas worktrees: continuam independentes com o ownership presente'
  # ---------------------------------------------------------------------------
  J1="$D/j1"; J2="$D/j2"; repo "$J1"
  git -C "$J1" worktree add -q "$J2" -b outra-integ >/dev/null 2>&1
  if [ -d "$J2" ]; then
    printf 'na principal\n' >> "$J1/src/a.js"
    printf 'na vinculada\n' >> "$J2/src/irma.js"
    ( fechar "$J1" T-01.01 src/a.js --verificacao 'sleep 2' >"$D/j1.out" 2>&1; printf '%s\n' "$?" >"$D/j1.rc" ) &
    espera_trava "$J1"
    fechar "$J2" T-01.02 src/irma.js >"$D/j2.out" 2>&1; printf '%s\n' "$?" >"$D/j2.rc"
    wait
    igual 'J — worktree principal fechou' "$(cat "$D/j1.rc")" 0
    igual 'J — worktree vinculada fechou ao mesmo tempo' "$(cat "$D/j2.rc")" 0
  else
    falha 'J — a worktree vinculada não pôde ser criada'
  fi

fi
if grupo K; then
  # ---------------------------------------------------------------------------
  echo
  echo 'K. V9 (união) continua aceitando o arquivo da irmã como planejado'
  # ---------------------------------------------------------------------------
  Kd="$D/k"; repo "$Kd"
  classe="$( cd "$Kd" && printf 'src/irma.js\n' | bash "$OWN" --classificar . sprintx ft-integ T-01.01 2>&1 )"
  uniao="$(printf '%s\n' "$classe" | awk -F'\t' '$3 != "-" { print $2 }')"
  printf '%s\n' "$uniao" | grep -Fxq src/irma.js \
    && ok 'K — a união (V9) inclui o arquivo da irmã: ele foi planejado na feature' \
    || falha 'K — o arquivo da irmã ficou fora da união que a V9 usa'

fi

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
