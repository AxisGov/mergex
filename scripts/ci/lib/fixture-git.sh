#!/usr/bin/env bash
# Helpers fail-closed exclusivos das fixtures de teste.

fixture_switch_exato() {
  local esperado atual
  esperado="$1"
  shift
  git switch -q "$@" || return 1
  atual="$(git branch --show-current)" || return 1
  [ "$atual" = "$esperado" ] || return 1
}

fixture_restaurar_tracked() {
  git reset -q || return 1
  [ "$#" -eq 0 ] || git restore --worktree -- "$@"
}
