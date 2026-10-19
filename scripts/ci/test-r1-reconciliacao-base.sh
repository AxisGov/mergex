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

# Biblioteca do artefato (rb_*): as tasks seguintes usam rb_sha256 nos testes.
# Ausente, o grupo `artefato` falha com "biblioteca ausente".
[ -r "$S/reconciliacao-artefato.sh" ] && . "$S/reconciliacao-artefato.sh"

OK=0; FALHOU=0
# Os temporários num array: a lista em string partia os caminhos no espaço, e
# com TMPDIR="…/com espaco" o `rm -rf` apagava o diretório irmão `…/com`
# (CodeAnt 4235534540). `${TMPS[@]+…}` evita o erro de `set -u` com o array
# vazio em bash < 4.4.
TMPS=()
trap 'cd "$REPO" 2>/dev/null; rm -rf ${TMPS[@]+"${TMPS[@]}"}' EXIT

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

# Os grupos ficam em partes, carregadas aqui na ordem de definição (a do
# `todos`): inteira, a bancada passava do limite da CLI do CodeAnt, que pula
# arquivo acima de 5.000 linhas ou 200 KB (emenda de 2026-10-19 do expxdev).
# Parte que não carrega para a bancada: um grupo a menos não pode virar verde.
R1_PARTES=(
  "$REPO/scripts/ci/test-r1-reconciliacao-base-registro.sh"
  "$REPO/scripts/ci/test-r1-reconciliacao-base-verificacao.sh"
  "$REPO/scripts/ci/test-r1-reconciliacao-base-portao.sh"
  "$REPO/scripts/ci/test-r1-reconciliacao-base-fluxo.sh"
)
for _r1_parte in "${R1_PARTES[@]}"; do
  # shellcheck source=/dev/null
  . "$_r1_parte" || { echo "parte da bancada não carregou: $_r1_parte" >&2; exit 1; }
done
unset _r1_parte

# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------

# Ordem de definição: lida das partes, na ordem de R1_PARTES (declare -F ordenaria por nome).
GRUPOS="$(sed -n 's/^grupo_\([a-z0-9_]*\)() {.*/\1/p' "${R1_PARTES[@]}" | tr '\n' ' ')"

[ "$#" -ge 1 ] || set -- todos

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
