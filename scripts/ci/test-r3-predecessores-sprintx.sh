#!/usr/bin/env bash
# Bancada R3: predecessores SprintX verificáveis e retomada estreita da V9.
#
# Uso: bash scripts/ci/test-r3-predecessores-sprintx.sh <grupo>... | todos

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${S:-$REPO/.claude/skills/mergex/scripts}"
PREDS="${PREDS:-$S/predecessores-sprintx.sh}"
V9="${V9:-$S/portao-v9.sh}"

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

grava_manifesto() { # usa a fixture corrente e cria o checkpoint de manifesto
  local bs bp
  bs="$(git rev-parse "$FX_PRE_SPEC:$FX_PRE_SPEC_PATH")" || return 1
  bp="$(git rev-parse "$FX_PRE_PLANO:$FX_PRE_PLAN_PATH")" || return 1
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: predecessores' \
      'trabalho_id: ft-pre' 'predecessores:'
    printf '  - caminho: %s\n    origem: superpowers\n    papel: especificacao\n    commit_sha: %s\n    blob_oid: %s\n' \
      "$FX_PRE_SPEC_PATH" "$FX_PRE_SPEC" "$bs"
    printf '  - caminho: %s\n    origem: superpowers\n    papel: plano\n    commit_sha: %s\n    blob_oid: %s\n' \
      "$FX_PRE_PLAN_PATH" "$FX_PRE_PLANO" "$bp"
    printf '%s\n' 'criado_em: 2026-10-13' 'atualizado_em: 2026-10-13' '---' '' \
      '# Predecessores' '' '- especificacao e plano consumidos antes da SprintX.'
  } > "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" || return 1
  git commit -q -m 'chore(mergex): registra predecessores da fixture' \
    -m 'Trabalho: ft-pre' -m 'Metodo: predecessores'
}

grupo_verificador() {
  local d out rc
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"
  cd "$d" || return
  [ "$(git rev-parse HEAD)" = "$FX_PRE_E8" ] && ok 'fixture termina no E8 bloqueado' || falha 'fixture não termina no E8'
  [ "$(git show "$FX_PRE_E8:$FX_PRE_ENTREGA" | sed -n 's/^estado:[[:space:]]*//p')" = bloqueado ] \
    && ok 'ENTREGA final está bloqueada' || falha 'ENTREGA final não está bloqueada'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = 'resultado=ausente' ] \
    && ok 'manifesto ausente preserva o comportamento histórico' || falha "ausência divergente — rc=$rc, saída=$out"
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=ok ] \
    && [ "$(printf '%s\n' "$out" | grep -c $'^predecessor\t')" = 2 ] \
    && ok 'dois predecessores imutáveis e anteriores são aprovados' \
    || falha "predecessores válidos reprovados — rc=$rc, saída=$out"

  printf '\nMudanca posterior.\n' >> "$FX_PRE_SPEC_PATH"
  git add -- "$FX_PRE_SPEC_PATH" && git commit -q -m 'docs: altera predecessor depois do manifesto'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=v9 ] \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md\tblob_divergente' \
    && ok 'blob atual divergente é v9 conhecido' || falha "divergência não virou v9 — rc=$rc, saída=$out"
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
  rc_igual 'uso inválido retorna 64' 64 bash "$PREDS" --verificar --trabalho ft-pre
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  # Frontmatter estruturalmente inválido: nenhuma linha parcial é autorizada.
  sed 's/^kind: predecessores$/kind: outro/' "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: quebra schema do manifesto'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 3 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=v9_sem_prova ] \
    && [ "$(printf '%s\n' "$out" | grep -c $'^motivo\t')" -ge 1 ] \
    && ! printf '%s\n' "$out" | grep -q $'^predecessor\t' \
    && ok 'schema inconclusivo falha fechado sem aceitação parcial' \
    || falha "v9_sem_prova fora do protocolo — rc=$rc, saída=$out"
  cd "$REPO" || return
}

grupo_v9() {
  local d out rc
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"; cd "$d" || return
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md' \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/plans/exemplo.md' \
    && ok 'V9 histórica barra spec e plano sem manifesto' || falha "V9 ausente divergente — rc=$rc, saída=$out"
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
    && ok 'V9 aceita somente os predecessores comprovados' || falha "V9 não integrou predecessores — rc=$rc, saída=$out"
  cd "$REPO" || return
}
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
