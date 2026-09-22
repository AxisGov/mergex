#!/usr/bin/env bash
# Bancada do P0.2-C7-B / MergeX M2.
# Uso: bash scripts/ci/test-m2-lifecycle-recuperacao.sh [grammar|catalog|lifecycle|integration|recovery|v11]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
CONTRATO="${CONTRATO:-$SCRIPTS/contrato-de-commit.sh}"
FECHA="${FECHA:-$SCRIPTS/fechamento-do-e1.sh}"
PERSISTE="${PERSISTE:-$SCRIPTS/persistir-metodo.sh}"
PROVA="${PROVA:-$SCRIPTS/prova-de-commit.sh}"

OK=0
FALHOU=0

ok() { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
falha() {
  FALHOU=$((FALHOU + 1)); printf '  FALHA %s\n' "$1"
  [ "${M2_FAIL_FAST:-0}" = 1 ] && exit 1
  return 0
}
igual() { # <descricao> <obtido> <esperado>
  if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperava '$3', obteve '$2')"; fi
}

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

mensagem() { # <arquivo> [trailers...]
  local arquivo="$1"; shift
  {
    printf 'test(mergex): mensagem de prova\n\n'
    while [ "$#" -gt 0 ]; do printf '%s\n' "$1"; shift; done
  } > "$arquivo"
}

valida() { # <descricao> <rc esperado> <args do contrato...>
  local descricao="$1" esperado="$2"; shift 2
  local rc
  bash "$CONTRATO" "$@" >/dev/null 2>&1
  rc=$?
  if [ "$esperado" = 0 ] && [ "$rc" = 0 ]; then
    ok "$descricao"
  elif [ "$esperado" != 0 ] && [ "$rc" != 0 ]; then
    ok "$descricao"
  else
    falha "$descricao (rc=$rc, esperado=$esperado)"
  fi
}

entrega() { # <arquivo> <trabalho> <branch> [origem]
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: ${4:-sprintx}
kind: entrega
trabalho_id: $2
entregue_por: mergex
estado: aberto
versionado: true
branch: $3
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
  git init -q -b feature/ft-m2 "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src docs/sprintx/features/ft-m2/sprint-01
    printf 'base\n' > src/a.js
    cat > docs/sprintx/features/ft-m2/sprint-01/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-m2
tasks:
  - id: T-01.01
    titulo: Alterar A
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: [src/a.js]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
    criterio_aceite: A alterado
---
YAML
    entrega docs/entregas/ft-m2/ENTREGA.md ft-m2 feature/ft-m2
    git add -A
    git commit -qm 'chore: base'
  )
}

artefato() { # <arquivo> <kind> <trabalho>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: teste
kind: $2
trabalho_id: $3
---
conteudo inicial
YAML
}

repo_catalogo() { # <dir> <origem> <layout: canonico|legado>
  local dir="$1" origem="$2" layout="$3" pasta
  git init -q -b feature/ft-m2 "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false

    if [ "$origem" = sprintx ]; then
      if [ "$layout" = legado ]; then pasta="docs/ft-m2"; else pasta="docs/sprintx/features/ft-m2"; fi
      mkdir -p "$pasta/base"
      artefato "$pasta/ORQUESTRADOR.md" orquestrador ft-m2
      artefato "$pasta/00-PLANEJAMENTO.md" planejamento ft-m2
      artefato "$pasta/FECHAMENTO.md" fechamento ft-m2
      artefato "$pasta/sprint-01/tasks.md" tasks ft-m2
      artefato "$pasta/sprint-01/sprint.md" sprint ft-m2
      cat > "$pasta/base/00-INDICE.md" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: base_indice
trabalho_id: ft-m2
areas:
  - arquivo: area com espaco.md
---
YAML
      artefato "$pasta/base/area com espaco.md" base_area ft-m2
      artefato "$pasta/base/nao-listada.md" base_area ft-m2
      artefato docs/sprintx/estimativas/HISTORICO.md estimativa_historico null
    else
      pasta="docs/manutencao/ft-m2"
      mkdir -p "$pasta/base"
      artefato "$pasta/ORQUESTRADOR.md" orquestrador ft-m2
      artefato "$pasta/00-OCORRENCIA.md" ocorrencia ft-m2
      artefato "$pasta/BLOQUEIOS.md" bloqueios ft-m2
      artefato "$pasta/sprint-01/tasks.md" tasks ft-m2
      cat > "$pasta/base/00-INDICE.md" <<'YAML'
---
expx_schema: 1
expx_tool: runx
kind: base_indice
trabalho_id: ft-m2
areas:
  - arquivo: causa detalhada.md
---
YAML
      artefato "$pasta/base/causa detalhada.md" base_area ft-m2
    fi

    mkdir -p docs/entregas/ft-m2 docs/entregas/outro src docs/outro/base
    entrega docs/entregas/ft-m2/ENTREGA.md ft-m2 feature/ft-m2 "$origem"
    artefato docs/entregas/ft-m2/ATENCAO.md atencao ft-m2
    artefato docs/entregas/ft-m2/PR.md pr ft-m2
    artefato docs/entregas/ft-m2/QA-PACOTE.md qa_pacote ft-m2
    entrega docs/entregas/outro/ENTREGA.md outro feature/ft-m2
    artefato docs/outro/ORQUESTRADOR.md orquestrador outro
    artefato docs/outro/base/parecido.md base_area outro
    printf 'produto\n' > src/ORQUESTRADOR.md
    git add -A
    git commit -qm 'chore: base'
    printf '%s\n' "$pasta"
  )
}

lista_catalogo() { # <repo> <origem> <checkpoint>
  local repo="$1" origem="$2" checkpoint="$3"
  (
    cd "$repo" || exit 1
    bash "$PERSISTE" --listar \
      --entrega docs/entregas/ft-m2/ENTREGA.md \
      --origem "$origem" --trabalho ft-m2 --checkpoint "$checkpoint"
  )
}

metodo() { # <repo> <acao> <origem> <checkpoint>
  local repo="$1" acao="$2" origem="$3" checkpoint="$4"
  (
    cd "$repo" || exit 1
    bash "$PERSISTE" "$acao" \
      --entrega docs/entregas/ft-m2/ENTREGA.md \
      --origem "$origem" --trabalho ft-m2 --checkpoint "$checkpoint"
  )
}

repo_recovery() { # <dir>
  local dir="$1"
  git init -q -b feature/ft-m2 "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src docs/sprintx/features/ft-m2/sprint-01 docs/entregas/ft-m2
    printf 'base a\n' > src/a.js
    printf 'base b\n' > src/b.js
    cat > docs/sprintx/features/ft-m2/ORQUESTRADOR.md <<'YAML'
---
kind: orquestrador
trabalho_id: ft-m2
---
YAML
    cat > docs/sprintx/features/ft-m2/sprint-01/tasks.md <<'YAML'
---
kind: tasks
trabalho_id: ft-m2
tasks:
  - id: T-01.01
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: [src/a.js]
    teste_integracao: cobre A
    teste_funcional: cobre A funcional
  - id: T-01.02
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: [src/b.js]
    teste_integracao: cobre B
    teste_funcional: cobre B funcional
---
YAML
    entrega docs/entregas/ft-m2/ENTREGA.md ft-m2 feature/ft-m2 sprintx
    git add -A
    git commit -qm 'chore: base recovery'
  )
}

repo_recovery_raiz() { # <dir> — o E1 recuperável é o commit raiz
  local dir="$1" msg="$D/root-e1.msg"
  git init -q -b feature/ft-m2 "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src
    printf 'raiz e1\n' > src/a.js
    mensagem "$msg" 'Task: T-01.01' 'Trabalho: ft-m2'
    git add -- src/a.js
    git commit -qF "$msg"
    git rev-parse HEAD > "$D/root-e1.sha"
    mkdir -p docs/sprintx/features/ft-m2/sprint-01 docs/entregas/ft-m2
    artefato docs/sprintx/features/ft-m2/ORQUESTRADOR.md orquestrador ft-m2
    cat > docs/sprintx/features/ft-m2/sprint-01/tasks.md <<'YAML'
---
kind: tasks
trabalho_id: ft-m2
tasks:
  - id: T-01.01
    status: concluida
    suite: verde
    arquivos:
      cria: [src/a.js]
      altera: []
    teste_integracao: cobre raiz
    teste_funcional: cobre raiz funcional
---
YAML
    entrega docs/entregas/ft-m2/ENTREGA.md ft-m2 feature/ft-m2 sprintx
    git add -- docs
    git commit -qm 'chore: contexto posterior'
  )
}

commit_e1_teste() { # <repo> <arquivo> <task> <trabalho> [metodo|sem-task|sem-trabalho]
  local repo="$1" arquivo="$2" task="$3" trabalho="$4" variante="${5:-}" msg
  printf '\nmuda %s\n' "$(git -C "$repo" rev-list --count HEAD)" >> "$repo/$arquivo"
  git -C "$repo" add -- "$arquivo"
  msg="$D/commit-$RANDOM-$RANDOM.msg"
  case "$variante" in
    sem-task) mensagem "$msg" "Trabalho: $trabalho" ;;
    sem-trabalho) mensagem "$msg" "Task: $task" ;;
    metodo) mensagem "$msg" "Task: $task" "Trabalho: $trabalho" 'Metodo: pre-e2' ;;
    *) mensagem "$msg" "Task: $task" "Trabalho: $trabalho" ;;
  esac
  git -C "$repo" commit -qF "$msg"
  git -C "$repo" rev-parse HEAD
}

recupera() { # <repo> <task> <sha>
  local repo="$1" task="$2" sha="$3"
  (
    cd "$repo" || exit 1
    bash "$FECHA" --registrar-existente \
      --entrega docs/entregas/ft-m2/ENTREGA.md \
      --origem sprintx --trabalho ft-m2 --task "$task" --sha "$sha"
  )
}

grupo_grammar() {
  local m repo rc antes
  printf '\nGRAMMAR — classes E1 e metodo mutuamente exclusivas\n'

  m="$D/e1-ok.msg"; mensagem "$m" 'Task: T-01.01' 'Trabalho: ft-m2'
  valida 'E1 aceita exatamente Task + Trabalho' 0 --validar-e1 --trabalho ft-m2 --task T-01.01 --arquivo "$m"

  for checkpoint in pre-e2 pre-e6 e8; do
    m="$D/metodo-$checkpoint.msg"; mensagem "$m" 'Trabalho: ft-m2' "Metodo: $checkpoint"
    valida "metodo aceita $checkpoint" 0 --validar-metodo --trabalho ft-m2 --checkpoint "$checkpoint" --arquivo "$m"
  done

  m="$D/hibrido.msg"; mensagem "$m" 'Task: T-01.01' 'Trabalho: ft-m2' 'Metodo: pre-e2'
  valida 'Task + Metodo nunca e aceito como E1' 1 --validar-e1 --trabalho ft-m2 --task T-01.01 --arquivo "$m"
  valida 'Task + Metodo nunca e aceito como metodo' 1 --validar-metodo --trabalho ft-m2 --checkpoint pre-e2 --arquivo "$m"

  m="$D/task-duplicada.msg"; mensagem "$m" 'Task: T-01.01' 'Task: T-01.01' 'Trabalho: ft-m2'
  valida 'Task duplicado para' 1 --validar-e1 --trabalho ft-m2 --task T-01.01 --arquivo "$m"

  m="$D/trabalho-duplicado.msg"; mensagem "$m" 'Task: T-01.01' 'Trabalho: ft-m2' 'Trabalho: ft-m2'
  valida 'Trabalho duplicado para' 1 --validar-e1 --trabalho ft-m2 --task T-01.01 --arquivo "$m"

  m="$D/metodo-duplicado.msg"; mensagem "$m" 'Trabalho: ft-m2' 'Metodo: pre-e2' 'Metodo: pre-e2'
  valida 'Metodo duplicado para' 1 --validar-metodo --trabalho ft-m2 --checkpoint pre-e2 --arquivo "$m"

  m="$D/metodo-fora.msg"; mensagem "$m" 'Trabalho: ft-m2' 'Metodo: outro'
  valida 'Metodo fora do enum para' 1 --validar-metodo --trabalho ft-m2 --checkpoint outro --arquivo "$m"

  m="$D/e1-sem-trabalho.msg"; mensagem "$m" 'Task: T-01.01'
  valida 'E1 sem Trabalho para' 1 --validar-e1 --trabalho ft-m2 --task T-01.01 --arquivo "$m"

  m="$D/metodo-com-task.msg"; mensagem "$m" 'Task: T-01.01' 'Trabalho: ft-m2' 'Metodo: pre-e2'
  valida 'metodo com Task para' 1 --validar-metodo --trabalho ft-m2 --checkpoint pre-e2 --arquivo "$m"

  repo="$D/e1-hibrido"; repo_e1 "$repo"
  mensagem "$D/e1-hibrido-real.msg" 'Task: T-01.01' 'Trabalho: ft-m2' 'Metodo: pre-e2'
  printf 'muda\n' >> "$repo/src/a.js"
  antes="$(git -C "$repo" rev-list --count HEAD)"
  (
    cd "$repo" || exit 1
    bash "$FECHA" --fechar --entrega docs/entregas/ft-m2/ENTREGA.md \
      --task T-01.01 --mensagem "$D/e1-hibrido-real.msg" -- src/a.js >/dev/null 2>&1
  )
  rc=$?
  [ "$rc" != 0 ] && ok 'fechamento E1 recusa Metodo antes do commit' \
    || falha 'fechamento E1 aceitou trailer Metodo'
  igual 'E1 hibrido nao cria commit' "$(git -C "$repo" rev-list --count HEAD)" "$antes"
}

grupo_catalog() {
  local repo pasta obtido esperado rc
  printf '\nCATALOG — contexto explicito e conjunto elegivel\n'

  repo="$D/catalogo-canonico"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  printf '\nmudanca\n' >> "$repo/$pasta/ORQUESTRADOR.md"
  printf '\nmudanca\n' >> "$repo/$pasta/00-PLANEJAMENTO.md"
  printf '\nmudanca\n' >> "$repo/$pasta/sprint-01/tasks.md"
  printf '\nmudanca\n' >> "$repo/$pasta/base/area com espaco.md"
  printf '\n  - trabalho_id: ft-m2\n' >> "$repo/docs/sprintx/estimativas/HISTORICO.md"
  printf '\nmudanca\n' >> "$repo/docs/entregas/ft-m2/ENTREGA.md"
  printf '\nmudanca\n' >> "$repo/docs/entregas/ft-m2/PR.md"
  printf '\nnao entra\n' >> "$repo/$pasta/base/nao-listada.md"
  printf '\nnao entra\n' >> "$repo/src/ORQUESTRADOR.md"
  printf '\nnao entra\n' >> "$repo/docs/outro/ORQUESTRADOR.md"
  esperado="$(printf '%s\n' \
    "$pasta/00-PLANEJAMENTO.md" \
    "$pasta/ORQUESTRADOR.md" \
    "$pasta/base/area com espaco.md" \
    "$pasta/sprint-01/tasks.md" \
    'docs/entregas/ft-m2/ENTREGA.md' \
    'docs/sprintx/estimativas/HISTORICO.md' | LC_ALL=C sort)"
  obtido="$(lista_catalogo "$repo" sprintx pre-e2 2>/dev/null)"
  igual 'pre-e2 SprintX canonica inclui somente metodo dirty do trabalho' "$obtido" "$esperado"

  esperado="$(printf '%s\n' "$esperado" 'docs/entregas/ft-m2/PR.md' | LC_ALL=C sort)"
  obtido="$(lista_catalogo "$repo" sprintx pre-e6 2>/dev/null)"
  igual 'pre-e6 e cumulativo e inclui documentos E3-E5' "$obtido" "$esperado"
  obtido="$(lista_catalogo "$repo" sprintx e8 2>/dev/null)"
  igual 'e8 conserva o catalogo cumulativo terminal' "$obtido" "$esperado"

  repo="$D/catalogo-legado"
  pasta="$(repo_catalogo "$repo" sprintx legado)"
  printf '\nmudanca\n' >> "$repo/$pasta/FECHAMENTO.md"
  obtido="$(lista_catalogo "$repo" sprintx pre-e2 2>/dev/null)"
  igual 'SprintX legada resolve somente pela origem explicita e ENTREGA' "$obtido" "$pasta/FECHAMENTO.md"

  repo="$D/catalogo-runx"
  pasta="$(repo_catalogo "$repo" runx canonico)"
  printf '\nmudanca\n' >> "$repo/$pasta/00-OCORRENCIA.md"
  printf '\nmudanca\n' >> "$repo/$pasta/base/causa detalhada.md"
  printf '\nmudanca\n' >> "$repo/docs/entregas/ft-m2/ENTREGA.md"
  esperado="$(printf '%s\n' "$pasta/00-OCORRENCIA.md" "$pasta/base/causa detalhada.md" \
    'docs/entregas/ft-m2/ENTREGA.md' | LC_ALL=C sort)"
  obtido="$(lista_catalogo "$repo" runx pre-e2 2>/dev/null)"
  igual 'RunX usa seu catalogo exato sem artefatos globais SprintX' "$obtido" "$esperado"

  git -C "$repo" branch -m branch-divergente
  lista_catalogo "$repo" runx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'branch divergente barra apenas como prova de consistencia' \
    || falha 'branch divergente foi aceita'
  git -C "$repo" branch -m feature/ft-m2

  sed -i 's/trabalho_id: ft-m2/trabalho_id: outro/' "$repo/docs/entregas/ft-m2/ENTREGA.md"
  lista_catalogo "$repo" runx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'ENTREGA divergente do trabalho explicito para' \
    || falha 'ENTREGA divergente foi aceita'
  sed -i 's/trabalho_id: outro/trabalho_id: ft-m2/' "$repo/docs/entregas/ft-m2/ENTREGA.md"

  lista_catalogo "$repo" sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'origem explicita divergente da ENTREGA para' \
    || falha 'origem divergente foi aceita'

  obtido="$(lista_catalogo "$repo" runx pre-e2 2>/dev/null)"
  igual 'ENTREGA de outro trabalho na mesma branch nao seleciona contexto' "$obtido" "$esperado"

  repo="$D/catalogo-historico-alheio"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  printf '\n  - trabalho_id: outro\n' >> "$repo/docs/sprintx/estimativas/HISTORICO.md"
  lista_catalogo "$repo" sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'HISTORICO global com diff de outro trabalho para' \
    || falha 'HISTORICO global de outro trabalho entrou no catalogo corrente'
}

grupo_lifecycle() {
  local repo pasta antes depois saida rc nomes corpo token trava staged segredo
  printf '\nLIFECYCLE — checkpoints idempotentes e fail-closed\n'

  repo="$D/lifecycle-principal"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  printf '\nappend da ultima task\n' >> "$repo/docs/entregas/ft-m2/ENTREGA.md"
  printf '\nestado final F6\n' >> "$repo/$pasta/00-PLANEJAMENTO.md"
  printf '\n  - trabalho_id: ft-m2\n' >> "$repo/docs/sprintx/estimativas/HISTORICO.md"
  printf '\nproduto continua dirty\n' >> "$repo/src/ORQUESTRADOR.md"

  metodo "$repo" --verificar sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'E2 e barrado enquanto pre-e2 esta pendente' \
    || falha 'barreira pre-e2 aceitou metodo dirty'

  antes="$(git -C "$repo" rev-list --count HEAD)"
  saida="$(metodo "$repo" --persistir sprintx pre-e2 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Eq '^commit=[0-9a-f]{40}$' \
    && ok 'ultima task da sprint: pre-e2 cria commit de metodo' \
    || falha "pre-e2 nao criou commit auditavel (rc=$rc; $saida)"
  depois="$(git -C "$repo" rev-list --count HEAD)"
  igual 'ultima task da feature produz exatamente um commit adicional' "$depois" "$((antes + 1))"
  metodo "$repo" --verificar sprintx pre-e2 >/dev/null 2>&1
  igual 'apos pre-e2 a barreira encontra metodo limpo' "$?" 0

  corpo="$(git -C "$repo" show -s --format=%B HEAD)"
  printf '%s\n' "$corpo" | grep -Fxq 'Trabalho: ft-m2' \
    && printf '%s\n' "$corpo" | grep -Fxq 'Metodo: pre-e2' \
    && ok 'commit de metodo tem exatamente Trabalho e Metodo canonicos' \
    || falha 'trailers canonicos de metodo ausentes'
  ! printf '%s\n' "$corpo" | grep -Eq '^Task:' \
    && ok 'commit de metodo nao possui Task' || falha 'commit de metodo recebeu Task'
  nomes="$(git -C "$repo" show --format= --name-only HEAD | sed '/^$/d' | LC_ALL=C sort)"
  esperado="$(printf '%s\n' \
    "$pasta/00-PLANEJAMENTO.md" \
    'docs/entregas/ft-m2/ENTREGA.md' \
    'docs/sprintx/estimativas/HISTORICO.md' | LC_ALL=C sort)"
  igual 'pre-e2 inclui somente o conjunto elegivel, sem produto' "$nomes" "$esperado"
  grep -q '^commits: \[\]$' "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    && ok 'commit de metodo nao entra em ENTREGA.commits nem consome seq' \
    || falha 'commit de metodo alterou a sequencia E1'
  [ -n "$(git -C "$repo" status --porcelain -- src/ORQUESTRADOR.md)" ] \
    && ok 'produto dirty fica fora do commit de metodo' || falha 'produto dirty foi absorvido'

  antes="$(git -C "$repo" rev-list --count HEAD)"
  saida="$(metodo "$repo" --persistir sprintx pre-e2 2>/dev/null)"; rc=$?
  depois="$(git -C "$repo" rev-list --count HEAD)"
  [ "$rc" = 0 ] && [ "$saida" = 'noop=true' ] && [ "$antes" = "$depois" ] \
    && ok 'retomada de pre-e2 persistido e no-op sem commit vazio' \
    || falha "pre-e2 idempotente falhou (rc=$rc; $saida)"

  printf '\natencao\n' >> "$repo/docs/entregas/ft-m2/ATENCAO.md"
  printf '\npr\n' >> "$repo/docs/entregas/ft-m2/PR.md"
  printf '\noutro trabalho\n' >> "$repo/docs/outro/ORQUESTRADOR.md"
  saida="$(metodo "$repo" --persistir sprintx pre-e6 2>/dev/null)"; rc=$?
  nomes="$(git -C "$repo" show --format= --name-only HEAD | sed '/^$/d' | LC_ALL=C sort)"
  esperado="$(printf '%s\n' 'docs/entregas/ft-m2/ATENCAO.md' 'docs/entregas/ft-m2/PR.md' | LC_ALL=C sort)"
  [ "$rc" = 0 ] && [ "$nomes" = "$esperado" ] \
    && ok 'pre-e6 persiste somente metodo previsto de E3-E5' \
    || falha "pre-e6 contaminado (rc=$rc; caminhos=$nomes)"
  [ -n "$(git -C "$repo" status --porcelain -- docs/outro/ORQUESTRADOR.md)" ] \
    && ok 'metodo de outro trabalho permanece fora do checkpoint' \
    || falha 'checkpoint absorveu metodo de outro trabalho'

  printf '\nestado: entregue\n' >> "$repo/docs/entregas/ft-m2/ENTREGA.md"
  metodo "$repo" --persistir sprintx e8 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && git -C "$repo" show HEAD:docs/entregas/ft-m2/ENTREGA.md | grep -q 'estado: entregue' \
    && ok 'E8 entregue persiste o terminal' || falha 'E8 entregue nao ficou duravel'
  printf '\nestado: bloqueado\n' >> "$repo/docs/entregas/ft-m2/ENTREGA.md"
  metodo "$repo" --persistir sprintx e8 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && git -C "$repo" show HEAD:docs/entregas/ft-m2/ENTREGA.md | grep -q 'estado: bloqueado' \
    && ok 'E8 bloqueado persiste o terminal' || falha 'E8 bloqueado nao ficou duravel'

  repo="$D/lifecycle-stage"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  printf '\nproduto staged\n' >> "$repo/src/ORQUESTRADOR.md"
  git -C "$repo" add -- src/ORQUESTRADOR.md
  staged="$(git -C "$repo" diff --cached --name-only)"
  metodo "$repo" --verificar sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(git -C "$repo" diff --cached --name-only)" = "$staged" ] \
    && ok 'barreira recusa stage preexistente sem limpar ou adotar' \
    || falha 'barreira aceitou ou alterou stage preexistente'
  metodo "$repo" --persistir sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(git -C "$repo" diff --cached --name-only)" = "$staged" ] \
    && ok 'stage preexistente para sem limpar ou adotar' \
    || falha 'stage preexistente foi aceito ou alterado'

  repo="$D/lifecycle-segredo"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  segredo="$(printf 'sk-%s' 'abcdef1234567890QRS')"
  printf '\ntoken: %s\n' "$segredo" >> "$repo/$pasta/00-PLANEJAMENTO.md"
  antes="$(git -C "$repo" rev-list --count HEAD)"
  metodo "$repo" --persistir sprintx pre-e2 >/dev/null 2>&1; rc=$?
  depois="$(git -C "$repo" rev-list --count HEAD)"
  staged="$(git -C "$repo" diff --cached --name-only)"
  [ "$rc" != 0 ] && [ "$antes" = "$depois" ] && [ "$staged" = "$pasta/00-PLANEJAMENTO.md" ] \
    && ok 'segredo barra antes do commit, preserva stage e libera propria trava' \
    || falha 'gate de segredo nao preservou o estado diagnostico'
  trava="$(git -C "$repo" rev-parse --git-path index).mergex-e1.lock"
  [ ! -d "$repo/$trava" ] && ok 'falha interna libera somente a trava da execucao' \
    || falha 'trava propria ficou presa apos falha'

  repo="$D/lifecycle-lock"
  pasta="$(repo_catalogo "$repo" sprintx canonico)"
  printf '\nmetodo\n' >> "$repo/$pasta/ORQUESTRADOR.md"
  saida="$(cd "$repo" && bash "$SCRIPTS/trava-do-e1.sh" --adquirir T-LOCK)"
  token="$(printf '%s\n' "$saida" | awk -F= '$1 == "token" {print $2}')"
  metodo "$repo" --persistir sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok 'checkpoint usa a mesma trava C5 e para quando ocupada' \
    || falha "checkpoint ignorou trava C5 (rc=$rc)"
  (cd "$repo" && bash "$SCRIPTS/trava-do-e1.sh" --liberar "$token") >/dev/null 2>&1
}

grupo_integration() {
  local skill commits prontidao push registro sprintx runx cmd cmd_check cmd_pr contrato
  printf '\nINTEGRATION — checkpoints explicitos no fluxo E2-E8\n'
  skill="$REPO/.claude/skills/mergex/SKILL.md"
  commits="$REPO/.claude/skills/mergex/references/01-commits.md"
  prontidao="$REPO/.claude/skills/mergex/references/02-prontidao.md"
  push="$REPO/.claude/skills/mergex/references/06-push.md"
  registro="$REPO/.claude/skills/mergex/references/08-registro.md"
  sprintx="$REPO/.claude/skills/mergex/references/integracao/sprintx.md"
  runx="$REPO/.claude/skills/mergex/references/integracao/runx.md"
  cmd="$REPO/.claude/commands/mergex.md"
  cmd_check="$REPO/.claude/commands/mergex-check.md"
  cmd_pr="$REPO/.claude/commands/mergex-pr.md"
  contrato="$REPO/scripts/ci/validate-mergex-contract.sh"

  grep -Fq 'persistir-metodo.sh' "$skill" \
    && ok 'SKILL torna o lifecycle executavel' || falha 'SKILL nao aponta ao executor de metodo'
  grep -Fq 'Metodo: pre-e2 | pre-e6 | e8' "$commits" \
    && ok 'E1 documenta commit de metodo como classe propria' || falha 'E1 ainda nao define a classe metodo'
  ! grep -Fq 'Isto **não é uma etapa nova**: é o E1' "$commits" \
    && ok 'commit de metodo nao e descrito como E1 tardio' || falha 'reference ainda mistura metodo com E1'

  grep -Fq -- '--verificar' "$prontidao" && grep -Fq -- '--checkpoint pre-e2' "$prontidao" \
    && ! grep -Fq -- '--persistir' "$prontidao" \
    && ok 'E2 apenas verifica a barreira pre-e2' || falha 'E2 nao e barreira pura pre-e2'
  grep -Fq -- '--verificar' "$push" && grep -Fq -- '--checkpoint pre-e6' "$push" \
    && ! grep -Fq -- '--persistir' "$push" \
    && ok 'E6 apenas verifica a barreira pre-e6' || falha 'E6 nao e barreira pura pre-e6'
  grep -Fq -- '--persistir' "$registro" && grep -Fq -- '--checkpoint e8' "$registro" \
    && ok 'E8 persiste o terminal pelo checkpoint e8' || falha 'E8 ainda persiste terminal manualmente'

  grep -Fq -- '--checkpoint pre-e2' "$cmd" && grep -Fq -- '--checkpoint pre-e6' "$cmd" \
    && grep -Fq -- '--checkpoint e8' "$cmd" \
    && ok 'fluxo completo encadeia os tres checkpoints' || falha 'comando mergex omite checkpoint'
  grep -Fq -- '--verificar' "$cmd_check" && grep -Fq -- '--checkpoint pre-e2' "$cmd_check" \
    && ! grep -Fq -- '--persistir' "$cmd_check" \
    && ok 'mergex-check recusa metodo pendente sem consertar' || falha 'mergex-check nao e somente barreira'
  grep -Fq -- '--persistir' "$cmd_pr" && grep -Fq -- '--checkpoint pre-e6' "$cmd_pr" \
    && ok 'mergex-pr executa a acao explicita pre-e6 antes do push' || falha 'mergex-pr omite pre-e6'

  grep -Fq 'persistir-metodo pre-e2' "$sprintx" && grep -Fq 'persistir-metodo pre-e2' "$runx" \
    && ok 'integracoes de origem entregam controle somente apos pre-e2' || falha 'origem nao aciona pre-e2'
  ! grep -Fq 'quem preenche é o **E1 tardio**' "$prontidao" \
    && ok 'V11 nao manda criar segundo commit quando SHA ja existe' || falha 'V11 ainda mistura os dois tipos de E1 tardio'
  grep -Fq 'persistir-metodo.sh' "$contrato" \
    && ok 'validador estrutural cobre o executor M2' || falha 'contrato CI ainda ignora o executor M2'
}

grupo_recovery() {
  local repo sha1 sha2 sha alvo antes depois saida rc itens curto msg tree pai2 merge staged token lockout
  printf '\nRECOVERY — registro de commit E1 ja existente\n'
  repo="$D/recovery-principal"; repo_recovery "$repo"

  sha1="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  antes="$(git -C "$repo" rev-list --count HEAD)"
  saida="$(recupera "$repo" T-01.01 "$sha1" 2>/dev/null)"; rc=$?
  depois="$(git -C "$repo" rev-list --count HEAD)"
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Fxq 'seq=1' && [ "$antes" = "$depois" ] \
    && ok '19 commit existente e registrado sem criar segundo commit' \
    || falha "19 recovery valido falhou (rc=$rc; $saida)"
  grep -Fq "commit: $sha1" "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    && ok '33 recovery acrescenta o proximo seq global com SHA informado' \
    || falha '33 SHA informado nao foi registrado'

  saida="$(recupera "$repo" T-01.01 "$sha1" 2>/dev/null)"; rc=$?
  itens="$(grep -Fc "commit: $sha1" "$repo/docs/entregas/ft-m2/ENTREGA.md")"
  [ "$rc" = 0 ] && [ "$saida" = 'noop=true' ] && [ "$itens" = 1 ] \
    && ok '29 mesmo SHA e mesma task e no-op idempotente' || falha '29 SHA duplicado foi registrado novamente'

  curto="${sha1:0:12}"
  sed -i "s/$sha1/$curto/" "$repo/docs/entregas/ft-m2/ENTREGA.md"
  saida="$(recupera "$repo" T-01.01 "$sha1" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$saida" = 'noop=true' ] \
    && ok '29 SHA completo reconhece registro abreviado equivalente' || falha '29 abreviacao equivalente duplicou objeto'
  sed -i "s/$curto/$sha1/" "$repo/docs/entregas/ft-m2/ENTREGA.md"

  sha2="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  saida="$(recupera "$repo" T-01.01 "$sha2" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Fxq 'seq=2' \
    && ok '30 mesma task com outro SHA e permitida' || falha '30 historico multiplo da task foi recusado'

  sed -i 's/task: T-01.01/task: T-01.02/g' "$repo/docs/entregas/ft-m2/ENTREGA.md"
  recupera "$repo" T-01.01 "$sha1" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'mesmo SHA registrado para outra task e conflito' || falha 'SHA de outra task foi aceito'
  sed -i 's/task: T-01.02/task: T-01.01/g' "$repo/docs/entregas/ft-m2/ENTREGA.md"

  recupera "$repo" T-01.01 0000000000000000000000000000000000000000 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '20 SHA inexistente para' || falha '20 SHA inexistente foi aceito'
  recupera "$repo" T-01.01 "$curto" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '22 SHA curto para antes de consultar o commit' || falha '22 SHA curto foi aceito'

  msg="$D/unreachable.msg"; mensagem "$msg" 'Task: T-01.01' 'Trabalho: ft-m2'
  printf '\nobjeto solto\n' >> "$repo/src/a.js"
  git -C "$repo" add -- src/a.js
  tree="$(git -C "$repo" write-tree)"
  git -C "$repo" reset -q HEAD -- src/a.js
  git -C "$repo" restore --worktree -- src/a.js
  sha="$(git -C "$repo" commit-tree "$tree" -p HEAD -F "$msg")"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '21 SHA nao alcancavel do HEAD para' || falha '21 commit solto foi aceito'

  repo="$D/recovery-sha-informado"; repo_recovery "$repo"
  alvo="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  printf '\ntopo sem trailers\n' >> "$repo/src/a.js"
  git -C "$repo" add -- src/a.js
  git -C "$repo" commit -qm 'test: topo sem trailers'
  recupera "$repo" T-01.01 "$alvo" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && grep -Fq "commit: $alvo" "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    && ok 'recovery valida o SHA informado, nao substitui por HEAD' \
    || falha 'recovery ignorou o SHA informado'

  repo="$D/recovery-principal"

  sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2 sem-task)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '23 Task trailer ausente para' || falha '23 commit sem Task foi aceito'
  sha="$(commit_e1_teste "$repo" src/a.js T-01.02 ft-m2)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '24 Task divergente para' || falha '24 Task divergente foi aceita'
  sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2 sem-trabalho)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '25 Trabalho ausente para' || falha '25 commit sem Trabalho foi aceito'
  sha="$(commit_e1_teste "$repo" src/a.js T-01.01 outro)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '26 Trabalho divergente para' || falha '26 Trabalho divergente foi aceito'
  sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2 metodo)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'commit com Metodo nunca e recuperado como E1' || falha 'commit hibrido foi aceito'

  sha="$(commit_e1_teste "$repo" src/b.js T-01.01 ft-m2)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '27 sibling-only dentro do commit para' || falha '27 sibling-only foi aceito'
  printf 'fora\n' > "$repo/src/fora.js"; git -C "$repo" add -- src/fora.js
  git -C "$repo" commit -qm 'test: desvio' -m 'Task: T-01.01' -m 'Trabalho: ft-m2'
  sha="$(git -C "$repo" rev-parse HEAD)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok '28 desvio dentro do commit para' || falha '28 desvio foi aceito'

  git -C "$repo" branch -m branch-divergente
  recupera "$repo" T-01.01 "$sha1" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'branch divergente barra como consistencia, sem selecionar trabalho' || falha 'branch divergente foi aceita no recovery'
  git -C "$repo" branch -m feature/ft-m2

  printf '\nstage\n' >> "$repo/src/a.js"; git -C "$repo" add -- src/a.js
  staged="$(git -C "$repo" diff --cached --name-only)"
  recupera "$repo" T-01.01 "$sha1" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(git -C "$repo" diff --cached --name-only)" = "$staged" ] \
    && ok '31 stage preexistente para e fica intacto' || falha '31 stage foi adotado ou limpo'

  repo="$D/recovery-lock"; repo_recovery "$repo"; sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  lockout="$(cd "$repo" && bash "$SCRIPTS/trava-do-e1.sh" --adquirir T-LOCK)"
  token="$(printf '%s\n' "$lockout" | awk -F= '$1 == "token" {print $2}')"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok '32 lock C5 ocupado para' || falha "32 lock foi ignorado (rc=$rc)"
  (cd "$repo" && bash "$SCRIPTS/trava-do-e1.sh" --liberar "$token") >/dev/null 2>&1

  repo="$D/recovery-merge"; repo_recovery "$repo"; tree="$(git -C "$repo" rev-parse HEAD^{tree})"
  pai2="$(git -C "$repo" commit-tree "$tree" -m 'pai solto')"
  msg="$D/merge.msg"; mensagem "$msg" 'Task: T-01.01' 'Trabalho: ft-m2'
  merge="$(git -C "$repo" commit-tree "$tree" -p HEAD -p "$pai2" -F "$msg")"
  git -C "$repo" update-ref refs/heads/feature/ft-m2 "$merge"
  recupera "$repo" T-01.01 "$merge" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'merge commit e recusado como E1 indeterminavel' || falha 'merge commit foi recuperado'

  repo="$D/recovery-rename"; repo_recovery "$repo"
  git -C "$repo" mv src/a.js src/a-renomeado.js
  git -C "$repo" commit -qm 'test: rename' -m 'Task: T-01.01' -m 'Trabalho: ft-m2'
  sha="$(git -C "$repo" rev-parse HEAD)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'rename submete origem e destino ao ownership' || falha 'rename com destino nao provado foi aceito'

  repo="$D/recovery-root"; repo_recovery_raiz "$repo"; sha="$(cat "$D/root-e1.sha")"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && grep -Fq "commit: $sha" "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    && ok 'commit raiz e lido com --root e pode ser recuperado' || falha 'commit raiz valido nao foi recuperado'

  repo="$D/recovery-append-fail"; repo_recovery "$repo"; sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  sed -i 's/commits: \[\]/commits:\n  - seq: 2\n    task: T-01.02\n    commit: abcdef1/' "$repo/docs/entregas/ft-m2/ENTREGA.md"
  antes="$(git -C "$repo" rev-list --count HEAD)"
  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  depois="$(git -C "$repo" rev-list --count HEAD)"
  [ "$rc" != 0 ] && [ "$antes" = "$depois" ] \
    && ok '34 falha no append nunca cria novo commit de produto' || falha '34 append falho alterou historico Git'
}

grupo_v11() {
  local repo sha rc entrega_head tasks_head
  printf '\nV11 — antes, recovery local e evidencia commitada\n'
  repo="$D/v11-cycle"; repo_recovery "$repo"
  sha="$(commit_e1_teste "$repo" src/a.js T-01.01 ft-m2)"
  # A segunda task não é alvo deste ciclo.
  sed -i '/id: T-01.02/,/suite: verde/ s/status: concluida/status: pendente/' \
    "$repo/docs/sprintx/features/ft-m2/sprint-01/tasks.md"

  bash "$PROVA" --verificar "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    "$repo/docs/sprintx/features/ft-m2/sprint-01/tasks.md" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'V11 falha antes de registrar o SHA existente' \
    || falha 'V11 passou sem prova em ENTREGA.commits'

  recupera "$repo" T-01.01 "$sha" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] || falha 'recovery do ciclo V11 falhou'
  bash "$PROVA" --verificar "$repo/docs/entregas/ft-m2/ENTREGA.md" \
    "$repo/docs/sprintx/features/ft-m2/sprint-01/tasks.md" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && ok 'V11 passa na leitura local depois do recovery' \
    || falha 'V11 local continua sem reconhecer o SHA recuperado'

  metodo "$repo" --persistir sprintx pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] || falha 'pre-e2 do ciclo V11 falhou'
  entrega_head="$D/ENTREGA-head.md"; tasks_head="$D/tasks-head.md"
  git -C "$repo" show HEAD:docs/entregas/ft-m2/ENTREGA.md > "$entrega_head"
  git -C "$repo" show HEAD:docs/sprintx/features/ft-m2/sprint-01/tasks.md > "$tasks_head"
  bash "$PROVA" --verificar "$entrega_head" "$tasks_head" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && ok 'V11 passa sobre a evidencia commitada pelo pre-e2' \
    || falha 'V11 falhou sobre ENTREGA extraida do HEAD'
  [ -z "$(lista_catalogo "$repo" sprintx pre-e2 2>/dev/null)" ] \
    && ok 'crash depois do recovery e retomado sem segundo commit de produto' \
    || falha '35 pre-e2 deixou metodo pendente depois da retomada'
}

grupo="${1:-all}"
case "$grupo" in
  all) grupo_grammar; grupo_catalog; grupo_lifecycle; grupo_integration; grupo_recovery; grupo_v11 ;;
  grammar) grupo_grammar ;;
  catalog) grupo_catalog ;;
  lifecycle) grupo_lifecycle ;;
  integration) grupo_integration ;;
  recovery) grupo_recovery ;;
  v11) grupo_v11 ;;
  *) printf 'grupo desconhecido: %s\n' "$grupo" >&2; exit 64 ;;
esac

printf '\n---------------------------------------------\n'
printf '%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
