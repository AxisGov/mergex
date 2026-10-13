#!/usr/bin/env bash
# Bancada R3: predecessores SprintX verificáveis e retomada estreita da V9.
#
# Uso: bash scripts/ci/test-r3-predecessores-sprintx.sh <grupo>... | todos

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${S:-$REPO/.claude/skills/mergex/scripts}"
PREDS="${PREDS:-$S/predecessores-sprintx.sh}"

OK=0; FALHOU=0
TMPS=()
trap 'cd "$REPO" 2>/dev/null; rm -rf ${TMPS[@]+"${TMPS[@]}"}' EXIT

ok()    { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU + 1)); printf '  FALHA %s\n' "$1"; }

rc_igual() {
  local desc="$1" esperado="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$esperado" ]; then ok "$desc"; else falha "$desc — rc=$rc, esperava $esperado"; fi
}

fixture() {
  FIXTURE_DIR="$(mktemp -d)" || return 1
  TMPS+=("$FIXTURE_DIR")
  # shellcheck source=lib/fixture-predecessores.sh
  . "$REPO/scripts/ci/lib/fixture-predecessores.sh" || return 1
  fx_predecessores_cenario "$FIXTURE_DIR" || return 1
}

grupo_verificador() {
  local d
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"
  cd "$d" || return
  [ "$(git rev-parse HEAD)" = "$FX_PRE_E8" ] && ok 'fixture termina no E8 bloqueado' || falha 'fixture não termina no E8'
  [ "$(git show "$FX_PRE_E8:$FX_PRE_ENTREGA" | sed -n 's/^estado:[[:space:]]*//p')" = bloqueado ] \
    && ok 'ENTREGA final está bloqueada' || falha 'ENTREGA final não está bloqueada'
  rc_igual 'verificador ainda ausente' 127 \
    bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return
}

grupo_protocolo() {
  local d out rc
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"
  cd "$d" || return
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = 'resultado=ausente' ] \
    && ok 'ausência usa resultado=ausente e rc 0' \
    || falha "protocolo de ausência ainda indisponível — rc=$rc, saída='${out:-vazia}'"
  cd "$REPO" || return
}

grupo_v9()        { falha 'grupo v9 ainda não implementado'; }
grupo_checkpoint(){ falha 'grupo checkpoint ainda não implementado'; }
grupo_retomada()  { falha 'grupo retomada ainda não implementado'; }
grupo_mp27b()     { falha 'grupo mp27b ainda não implementado'; }

roda_grupo() {
  case "$1" in
    verificador) grupo_verificador ;;
    protocolo) grupo_protocolo ;;
    v9) grupo_v9 ;;
    checkpoint) grupo_checkpoint ;;
    retomada) grupo_retomada ;;
    mp27b) grupo_mp27b ;;
    *) printf 'grupo desconhecido: %s\n' "$1" >&2; exit 64 ;;
  esac
}

if [ "$#" -eq 0 ]; then set -- todos; fi
if [ "$1" = todos ]; then set -- verificador protocolo v9 checkpoint retomada mp27b; fi
for grupo in "$@"; do
  printf '\n%s\n' "== $grupo =="
  roda_grupo "$grupo"
done

printf '\n---------------------------------------------\n%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" -eq 0 ]
