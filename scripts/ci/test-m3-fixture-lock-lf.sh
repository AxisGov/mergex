#!/usr/bin/env bash
# Provas focadas do M3: fixture historica, lock orfao e portabilidade LF.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GRUPO="${1:-todos}"
OK=0
FALHOU=0

ok() { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU + 1)); printf '  FALHA %s\n' "$1" >&2; }

grupo_fixture() {
  printf '\nfixture fail-closed\n'
  # A ausencia do helper e o RED inicial deliberado desta suite.
  # shellcheck source=scripts/ci/lib/fixture-git.sh
  if ! . "$REPO/scripts/ci/lib/fixture-git.sh"; then
    falha "helper fixture-git.sh existe e pode ser carregado"
    return
  fi

  if (
    git() {
      [ "$1" = "switch" ] && return 7
      [ "$1 $2" = "branch --show-current" ] && { printf 'feature/esperada\n'; return 0; }
      return 1
    }
    fixture_switch_exato feature/esperada feature/esperada
  ); then
    falha "retorno nao zero do switch foi ignorado"
  else
    ok "retorno nao zero do switch encerra a troca"
  fi

  if (
    git() {
      [ "$1" = "switch" ] && return 0
      [ "$1 $2" = "branch --show-current" ] && { printf 'feature/errada\n'; return 0; }
      return 1
    }
    fixture_switch_exato feature/esperada feature/esperada
  ); then
    falha "branch resultante errada foi aceita"
  else
    ok "branch resultante e conferida literalmente"
  fi

  local tmp
  tmp="$(mktemp -d)" || return 1
  (
    trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    printf 'base\n' > tracked.txt
    git add tracked.txt && git commit -qm inicial || exit 1
    git branch feature/limpa || exit 1
    printf 'sujeira\n' >> tracked.txt
    git add tracked.txt || exit 1
    fixture_restaurar_tracked tracked.txt || exit 1
    fixture_switch_exato feature/limpa feature/limpa || exit 1
    [ "$(git branch --show-current)" = "feature/limpa" ] || exit 1
    [ "$(cat tracked.txt)" = "base" ] || exit 1
  ) && ok "tracked e restaurado antes do switch real" || falha "tracked atravessou a troca real"

  if grep -Eq '^[[:space:]]*git[[:space:]]+switch([[:space:]]|$)' "$REPO/.claude/hooks/teste.sh"; then
    falha "bancada de hooks ainda tem git switch sem helper"
  else
    ok "todo git switch executavel da bancada passa pelo helper"
  fi
}

verificar_checkout_lf() { # <checkout> <rotulo>
  local dir="$1" rotulo="$2" eols f first ruim=0
  eols="$(git -C "$dir" ls-files --eol -- '*.sh')" || {
    falha "$rotulo: git ls-files --eol responde"
    return
  }
  if [ -n "$eols" ] && ! printf '%s\n' "$eols" | grep -Evq \
    '^i/lf[[:space:]]+w/lf[[:space:]]+attr/text eol=lf[[:space:]]+'; then
    ok "$rotulo: indice, worktree e atributo declaram LF"
  else
    falha "$rotulo: algum script nao declarou i/lf w/lf attr/text eol=lf"
    ruim=1
  fi

  while IFS= read -r -d '' f; do
    if LC_ALL=C grep -q $'\r' "$dir/$f"; then
      falha "$rotulo: $f contem byte CR"
      ruim=1
      break
    fi
    IFS= read -r first < "$dir/$f" || first=""
    if [ "$first" != '#!/usr/bin/env bash' ]; then
      falha "$rotulo: $f perdeu o shebang literal"
      ruim=1
      break
    fi
  done < <(git -C "$dir" ls-files -z -- '*.sh')
  [ "$ruim" -ne 0 ] || ok "$rotulo: bytes sem CR e shebangs literais"
}

grupo_lf() {
  printf '\nportabilidade LF\n'
  local tmp fonte clone ligada lista
  tmp="$(mktemp -d)" || return 1
  fonte="$tmp/fonte"
  clone="$tmp/clone"
  ligada="$tmp/ligada"
  lista="$tmp/lista"
  mkdir -p "$fonte"
  (
    cd "$REPO" || exit 1
    git ls-files -z -- '*.sh' > "$lista" || exit 1
    [ ! -f scripts/ci/lib/fixture-git.sh ] || printf '%s\0' scripts/ci/lib/fixture-git.sh >> "$lista"
    [ ! -f scripts/ci/test-m3-fixture-lock-lf.sh ] || printf '%s\0' scripts/ci/test-m3-fixture-lock-lf.sh >> "$lista"
    tar --null -T "$lista" -cf - | (cd "$fonte" && tar -xf -) || exit 1
    [ ! -f .gitattributes ] || cp .gitattributes "$fonte/.gitattributes"
  ) || { rm -rf "$tmp"; falha "repo-fonte LF pode ser montado"; return; }

  (
    cd "$fonte" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config core.autocrlf false
    git add -A && git commit -qm fixture || exit 1
  ) || { rm -rf "$tmp"; falha "repo-fonte LF pode ser commitado"; return; }

  if git clone -q -c core.autocrlf=true "$fonte" "$clone"; then
    [ -d "$clone/.git" ] && ok "clone principal tem .git diretorio" \
      || falha "clone principal nao tem .git diretorio"
    [ "$(git -C "$clone" config --local --get --bool core.autocrlf 2>/dev/null)" = true ] \
      && ok "clone persiste core.autocrlf=true para worktrees vinculadas" \
      || falha "clone nao persistiu core.autocrlf=true localmente"
    verificar_checkout_lf "$clone" "clone autocrlf=true"
  else
    falha "clone autocrlf=true pode ser criado"
  fi

  if git -C "$clone" worktree add -q -b m3-linked "$ligada"; then
    [ -f "$ligada/.git" ] && ok "worktree vinculada tem .git arquivo" \
      || falha "worktree vinculada nao tem .git arquivo"
    verificar_checkout_lf "$ligada" "worktree vinculada"
  else
    falha "worktree vinculada pode ser criada"
  fi
  git -C "$clone" worktree remove -f "$ligada" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

grupo_lock() {
  printf '\nlock orfao conservador\n'
  local tmp trava_cli adquirida trava token dono_antes dono_depois stage_antes stage_depois rc
  tmp="$(mktemp -d)" || return 1
  trava_cli="$REPO/.claude/skills/mergex/scripts/trava-do-e1.sh"
  (
    cd "$tmp" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config core.autocrlf false
    printf 'base\n' > produto.txt
    git add produto.txt && git commit -qm base || exit 1

    adquirida="$(bash "$trava_cli" --adquirir T-03.01)" || exit 1
    trava="$(printf '%s\n' "$adquirida" | sed -n 's/^trava=//p')"
    token="$(printf '%s\n' "$adquirida" | sed -n 's/^token=//p')"
    [ -d "$trava" ] && [ -f "$trava/dono" ] || exit 1
    dono_antes="$(git hash-object "$trava/dono")" || exit 1

    bash "$trava_cli" --status >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] || exit 1
    dono_depois="$(git hash-object "$trava/dono")" || exit 1
    [ "$dono_antes" = "$dono_depois" ] || exit 1

    bash "$trava_cli" --liberar token-incorreto >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] || exit 1
    [ "$(git hash-object "$trava/dono")" = "$dono_antes" ] || exit 1

    printf 'preparado\n' >> produto.txt
    git add produto.txt || exit 1
    stage_antes="$(git diff --cached --binary | git hash-object --stdin)" || exit 1
    bash "$trava_cli" --adquirir T-03.02 >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] || exit 1
    stage_depois="$(git diff --cached --binary | git hash-object --stdin)" || exit 1
    [ "$stage_antes" = "$stage_depois" ] || exit 1
    [ "$(git hash-object "$trava/dono")" = "$dono_antes" ] || exit 1

    bash "$trava_cli" --liberar "$token" >/dev/null 2>&1 || exit 1
    [ ! -e "$trava" ] || exit 1
  ) && ok "status, token errado e novo E1 preservam lock e stage" \
    || falha "lock ou stage foi alterado sem prova humana"
  rm -rf "$tmp"
}

rodar_hook_escopo() { # <repo> <script>
  local raiz="$1" hook="$2" entrada
  entrada="$(jq -cn --arg w "$raiz" '{tool_name:"Bash",cwd:$w,tool_input:{command:"git commit -m x"}}')" || return 1
  printf '%s' "$entrada" | bash "$hook" >/dev/null 2>&1
}

grupo_historico() {
  printf '\nHISTORICO exato e persistivel\n'
  local tmp hook rc
  if ! . "$REPO/scripts/ci/lib/fixture-git.sh"; then
    falha "helper fixture-git.sh existe para isolar HISTORICO"
    return
  fi
  tmp="$(mktemp -d)" || return 1
  hook="$REPO/.claude/hooks/mergex/arquivo-fora-do-plano.sh"
  if ! command -v jq >/dev/null 2>&1; then
    falha "jq esta disponivel para provar o hook de HISTORICO"
    rm -rf "$tmp"
    return
  fi
  (
    cd "$tmp" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config core.autocrlf false
    mkdir -p .expx docs/entregas/ft-historico docs/entregas/OC-M3 \
      docs/sprintx/features/ft-historico/sprint-01 docs/sprintx/estimativas \
      docs/manutencao/OC-M3 src
    printf '%s\n' '{"expx_hooks":1,"hooks":{"arquivo-fora-do-plano":{"modo":"bloqueio"}}}' > .expx/hooks.json
    cat > docs/entregas/ft-historico/ENTREGA.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: ft-historico
entregue_por: mergex
branch: feature/ft-historico
branch_base: main
---
YAML
    cat > docs/entregas/OC-M3/ENTREGA.md <<'YAML'
---
expx_schema: 1
expx_tool: runx
kind: entrega
trabalho_id: OC-M3
entregue_por: mergex
branch: fix/OC-M3
branch_base: main
---
YAML
    cat > docs/sprintx/features/ft-historico/sprint-01/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-historico
tasks:
  - id: T-01.01
    status: concluida
    arquivos:
      altera: [src/base.ts]
    suite: verde
---
YAML
    printf 'base\n' > src/base.ts
    printf 'historico base\n' > docs/sprintx/estimativas/HISTORICO.md
    git add -A && git commit -qm base || exit 1
    git branch feature/ft-historico
    git branch fix/OC-M3

    fixture_switch_exato feature/ft-historico feature/ft-historico || exit 1
    printf 'sprintx\n' >> docs/sprintx/estimativas/HISTORICO.md
    git add docs/sprintx/estimativas/HISTORICO.md || exit 1
    rodar_hook_escopo "$tmp" "$hook"; rc=$?
    [ "$rc" -eq 0 ] || exit 1

    fixture_restaurar_tracked docs/sprintx/estimativas/HISTORICO.md || exit 1
    fixture_switch_exato fix/OC-M3 fix/OC-M3 || exit 1
    printf 'runx\n' >> docs/sprintx/estimativas/HISTORICO.md
    git add docs/sprintx/estimativas/HISTORICO.md || exit 1
    rodar_hook_escopo "$tmp" "$hook"; rc=$?
    [ "$rc" -eq 2 ] || exit 1
  ) && ok "HISTORICO e isento so na SprintX, nunca na RunX" \
    || falha "semantica exata do HISTORICO regrediu"
  rm -rf "$tmp"

  if bash "$REPO/scripts/ci/test-m2-lifecycle-recuperacao.sh" catalog lifecycle >/dev/null 2>&1; then
    ok "M2 cataloga e persiste HISTORICO no lifecycle"
  else
    falha "M2 deixou de catalogar ou persistir HISTORICO"
  fi
}

case "$GRUPO" in
  fixture) grupo_fixture ;;
  historico) grupo_historico ;;
  lf) grupo_lf ;;
  lock) grupo_lock ;;
  todos) grupo_fixture; grupo_historico; grupo_lf; grupo_lock ;;
  *) printf 'grupo desconhecido: %s\n' "$GRUPO" >&2; exit 2 ;;
esac

printf '\n%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" -eq 0 ]
