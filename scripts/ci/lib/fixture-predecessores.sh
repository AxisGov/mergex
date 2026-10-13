#!/usr/bin/env bash
# Fixture Git real para o contrato de predecessores SprintX consumido pela MergeX.
#
# fx_predecessores_cenario <diretorio>
#
# Exporta, entre outros:
#   FX_PRE_BASE FX_PRE_SPEC FX_PRE_PLANO FX_PRE_NASCIMENTO FX_PRE_PRE_E2
#   FX_PRE_E8 FX_PRE_ENTREGA FX_PRE_MANIFESTO FX_PRE_SPEC_PATH FX_PRE_PLAN_PATH

_FX_PRE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fixture-git.sh
. "$_FX_PRE_LIB/fixture-git.sh"

_fx_pre_msg() { # <arquivo> <assunto> [trailer...]
  local arq="$1" assunto="$2"; shift 2
  {
    printf '%s\n' "$assunto"
    if [ "$#" -gt 0 ]; then printf '\n'; printf '%s\n' "$@"; fi
  } > "$arq"
}

_fx_pre_commit() { # <mensagem> [caminho...]
  local msg="$1"; shift
  git add -- "$@" || return 1
  git commit -q -F "$msg"
}

_fx_pre_tasks() {
  local destino="$1" i
  mkdir -p "$destino/sprint-01" || return 1
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' \
      'trabalho_id: ft-pre' 'sprint:' '  titulo: Predecessores' '  status: concluido' \
      'fases:' '  - id: F-01.1' '    titulo: Execucao' \
      '    tasks: [T-01.01, T-01.02, T-01.03, T-01.04, T-01.05, T-01.06]' \
      'tasks:'
    i=1
    while [ "$i" -le 6 ]; do
      printf '  - id: T-01.%02d\n' "$i"
      printf '    titulo: Task %d\n    fase: F-01.1\n    status: concluida\n' "$i"
      printf '    objetivo: Entrega %d\n    suite: verde\n' "$i"
      printf '    arquivos:\n      cria: [src/task-%d.txt]\n      altera: []\n' "$i"
      printf '    teste_integracao: integra %d\n    teste_funcional: funciona %d\n' "$i" "$i"
      i=$((i + 1))
    done
    printf '%s\n' '---' '' '# Tasks' '' 'Seis entregas da fixture.'
  } > "$destino/sprint-01/tasks.md"
}

_fx_pre_entrega() { # <base_sha> <e8:0|1> <sha1> ... <sha6>
  local base="$1" fechada="$2"; shift 2
  local estado=aberto portao=bloqueado causa=arquivo_fora_do_plano i=1 c
  [ "$fechada" = 1 ] && estado=bloqueado
  mkdir -p docs/entregas/ft-pre || return 1
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: entrega' \
      'trabalho_id: ft-pre' 'entregue_por: mergex'
    printf 'estado: %s\nversionado: true\nbranch: feature/ft-pre\nbranch_base: main\n' "$estado"
    printf 'base_validada_sha: %s\norigem_base: registrada_e0\nreconciliacoes: []\nportao_sha: null\n' "$base"
    printf 'commits:\n'
    for c in "$@"; do
      printf '  - seq: %d\n    task: T-01.%02d\n    commit: %s\n' "$i" "$i" "$c"
      i=$((i + 1))
    done
    printf '%s\n' 'modulo_afetado: []' 'arquivos_alterados: []' 'faixa_atencao: []' 'raio: null' \
      'atencao:' '  olho_obrigatorio: 0' '  leitura_rapida: 0' '  dispensavel: 0'
    printf 'portao: %s\nfalhas_portao: [v9]\ncausa: %s\n' "$portao" "$causa"
    printf '%s\n' 'desvios:' \
      '  - docs/superpowers/specs/exemplo-design.md' \
      '  - docs/superpowers/plans/exemplo.md' \
      'push_feito: false' 'pr_url: null' 'pr_estado: null' \
      'criado_em: 2026-10-13' 'atualizado_em: 2026-10-13' 'entregue_em: null' '---' '' \
      '# Entrega' '' 'E8 bloqueado exclusivamente pela V9.'
  } > docs/entregas/ft-pre/ENTREGA.md
}

_fx_pre_corpo() { # <diretorio> <arquivo-de-shas>
  local dir="$1" shas="$2" msg i c
  local commits="" FX_PRE_BASE FX_PRE_SPEC FX_PRE_PLANO FX_PRE_NASCIMENTO FX_PRE_PRE_E2 FX_PRE_E8
  msg="$dir/.msg"
  cd "$dir" || exit 1
  git init -q -b main
  git config user.email teste@expx.local
  git config user.name 'Teste Expx'
  git config core.autocrlf false
  git config core.quotepath false
  git config commit.gpgsign false

  printf '# Fixture predecessores\n' > README.md
  _fx_pre_msg "$msg" 'chore: base inicial'
  _fx_pre_commit "$msg" README.md
  FX_PRE_BASE="$(git rev-parse HEAD)"

  mkdir -p docs/superpowers/specs docs/superpowers/plans
  printf '# Especificacao predecessora\n' > docs/superpowers/specs/exemplo-design.md
  _fx_pre_msg "$msg" 'docs: cria especificacao predecessora'
  _fx_pre_commit "$msg" docs/superpowers/specs/exemplo-design.md
  FX_PRE_SPEC="$(git rev-parse HEAD)"

  printf '# Plano predecessor\n' > docs/superpowers/plans/exemplo.md
  _fx_pre_msg "$msg" 'docs: cria plano predecessor'
  _fx_pre_commit "$msg" docs/superpowers/plans/exemplo.md
  FX_PRE_PLANO="$(git rev-parse HEAD)"

  fixture_switch_exato feature/ft-pre -c feature/ft-pre
  mkdir -p docs/sprintx/features/ft-pre
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: planejamento' \
    'trabalho_id: ft-pre' 'estado: aprovado' '---' '' '# Planejamento' \
    > docs/sprintx/features/ft-pre/00-PLANEJAMENTO.md
  _fx_pre_tasks docs/sprintx/features/ft-pre
  _fx_pre_msg "$msg" 'chore(sprintx): nasce planejamento ft-pre'
  _fx_pre_commit "$msg" docs/sprintx/features/ft-pre/00-PLANEJAMENTO.md \
    docs/sprintx/features/ft-pre/sprint-01/tasks.md
  FX_PRE_NASCIMENTO="$(git rev-parse HEAD)"

  mkdir -p src
  i=1
  while [ "$i" -le 6 ]; do
    printf 'task %d\n' "$i" > "src/task-$i.txt"
    _fx_pre_msg "$msg" "feat(ft-pre): entrega task $i" \
      "Task: T-01.$(printf '%02d' "$i")" 'Trabalho: ft-pre'
    _fx_pre_commit "$msg" "src/task-$i.txt"
    c="$(git rev-parse --short HEAD)"
    commits="$commits $c"
    i=$((i + 1))
  done

  # shellcheck disable=SC2086 # a lista contém apenas SHAs curtos gerados pelo Git
  _fx_pre_entrega "$FX_PRE_BASE" 0 $commits
  _fx_pre_msg "$msg" 'chore(mergex): persiste metodo pre-e2' 'Trabalho: ft-pre' 'Metodo: pre-e2'
  _fx_pre_commit "$msg" docs/entregas/ft-pre/ENTREGA.md
  FX_PRE_PRE_E2="$(git rev-parse HEAD)"

  # O E2 não cria commit: a V9 bloqueia. O E8 persiste o estado terminal.
  # shellcheck disable=SC2086
  _fx_pre_entrega "$FX_PRE_BASE" 1 $commits
  _fx_pre_msg "$msg" 'chore(mergex): persiste metodo e8 bloqueado' 'Trabalho: ft-pre' 'Metodo: e8'
  _fx_pre_commit "$msg" docs/entregas/ft-pre/ENTREGA.md
  FX_PRE_E8="$(git rev-parse HEAD)"

  {
    printf 'FX_PRE_BASE=%s\nFX_PRE_SPEC=%s\nFX_PRE_PLANO=%s\n' "$FX_PRE_BASE" "$FX_PRE_SPEC" "$FX_PRE_PLANO"
    printf 'FX_PRE_NASCIMENTO=%s\nFX_PRE_PRE_E2=%s\nFX_PRE_E8=%s\n' "$FX_PRE_NASCIMENTO" "$FX_PRE_PRE_E2" "$FX_PRE_E8"
  } > "$shas"
}

fx_predecessores_cenario() { # <diretorio>
  local dir="$1" shas="$1/.fx-pre-shas"
  [ -n "$dir" ] || return 1
  mkdir -p "$dir" || return 1
  bash -e -c '. "$1"; _fx_pre_corpo "$2" "$3"' bash "$BASH_SOURCE" "$dir" "$shas" || return 1
  # shellcheck disable=SC1090
  . "$shas"
  rm -f "$shas"
  FX_PRE_ENTREGA=docs/entregas/ft-pre/ENTREGA.md
  FX_PRE_MANIFESTO=docs/sprintx/features/ft-pre/00-PREDECESSORES.md
  FX_PRE_SPEC_PATH=docs/superpowers/specs/exemplo-design.md
  FX_PRE_PLAN_PATH=docs/superpowers/plans/exemplo.md
  export FX_PRE_BASE FX_PRE_SPEC FX_PRE_PLANO FX_PRE_NASCIMENTO FX_PRE_PRE_E2 FX_PRE_E8
  export FX_PRE_ENTREGA FX_PRE_MANIFESTO FX_PRE_SPEC_PATH FX_PRE_PLAN_PATH
}
