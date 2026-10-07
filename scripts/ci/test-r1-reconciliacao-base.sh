#!/usr/bin/env bash
#
# Bancada da reconciliação de base pós-E8 (R1).
#
# Cada grupo monta um repositório Git real (fixture-reconciliacao.sh) e prova
# um aspecto do contrato. Os grupos são funções `grupo_<nome>`; os de tasks
# posteriores são acrescentados abaixo, na ordem de definição.
#
# Uso: bash scripts/ci/test-r1-reconciliacao-base.sh <grupo>... | todos
#      RB=<outro script> bash scripts/ci/test-r1-reconciliacao-base.sh <grupo>

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${S:-$REPO/.claude/skills/mergex/scripts}"
RB="${RB:-$S/reconciliacao-base.sh}"
V9="${V9:-$S/portao-v9.sh}"
VALIDADE="${VALIDADE:-$S/validade-do-portao.sh}"
CONTRATO="${CONTRATO:-$S/contrato-de-commit.sh}"
SEQ="${SEQ:-$S/sequencia-de-commits.sh}"
CAUSA="${CAUSA:-$S/causa-do-portao.sh}"
PROVA="${PROVA:-$S/prova-de-commit.sh}"
TRAVA="${TRAVA:-$S/trava-do-e1.sh}"

OK=0; FALHOU=0
TMPS=""
trap 'cd "$REPO" 2>/dev/null; for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# afirma <desc> <cmd...> — exige rc 0
afirma() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else falha "$desc"; fi
}

# rc_igual <desc> <rc> <cmd...> — exige o rc informado
rc_igual() {
  local desc="$1" esperado="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$esperado" ]; then ok "$desc"; else falha "$desc — rc=$rc, esperava $esperado"; fi
}

# ---------------------------------------------------------------------------
# Grupos
# ---------------------------------------------------------------------------

grupo_reproducao() {
  local d f; d="$(mktemp -d)"; TMPS="$TMPS $d"
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  [ "$(git rev-parse "$FX_M^1")" = "$FX_P1" ] && ok "M^1 é P1" || falha "M^1 diferente de P1"
  [ "$(git rev-parse "$FX_M^2")" = "$FX_B1" ] && ok "M^2 é B1" || falha "M^2 diferente de B1"
  for f in "$FX_NOVO1" "$FX_NOVO2"; do
    [ "$(git diff --no-renames --name-status "$FX_B0" "$FX_B1" -- "$f" | cut -f1)" = A ] \
      && ok "$f nasceu na base" || falha "$f não nasceu na base"
    git diff --quiet "$FX_B1" "$FX_M" -- "$f" && falha "$f sem ajuste no merge" || ok "$f ajustado no merge"
    git diff --name-only "$FX_B1...HEAD" | grep -Fxq "$f" \
      && ok "$f aparece no diff da V9 (defeito)" || falha "$f não aparece no diff da V9"
  done
  cd "$REPO" || return
}

# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------

# Ordem de definição: lida do próprio arquivo (declare -F ordenaria por nome).
GRUPOS="$(sed -n 's/^grupo_\([a-z0-9_]*\)() {.*/\1/p' "${BASH_SOURCE[0]}" | tr '\n' ' ')"

[ "$#" -ge 1 ] || { echo "uso: $0 <grupo>... | todos" >&2; exit 64; }

SEL=""
for g in "$@"; do
  if [ "$g" = todos ]; then SEL="$SEL $GRUPOS"
  else
    case " $GRUPOS " in
      *" $g "*) SEL="$SEL $g" ;;
      *) echo "grupo desconhecido: $g (grupos: $GRUPOS)" >&2; exit 64 ;;
    esac
  fi
done

for g in $SEL; do
  echo "== $g"
  "grupo_$g"
  cd "$REPO" || exit 1
done

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ]
