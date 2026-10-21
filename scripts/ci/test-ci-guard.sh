#!/usr/bin/env bash
#
# Prova que a guarda `check-ci-runs-validators.sh` morde: cada forma de omitir
# um validador do CI tem que fazê-la falhar, e o workflow real tem que passar.
#
# Casos (cada um é um workflow mutado, em diretório temporário):
#   1. o passo do validate-mergex-contract.sh some;
#   2. o passo do validate-review-evidence-contract.sh some;
#   3. o passo existe, mas comentado;
#   4. o passo roda duas vezes (duplicado);
#   5. um validate-*.sh novo aparece em scripts/ci/ sem ser registrado;
#   6. o workflow de mutacao perde uma bancada (scripts/ci/mutacao-*.sh);
#   6b. a bancada sai da matriz e o nome fica so noutra lista do workflow;
#   7. uma bancada de mutacao nova aparece sem entrar no workflow de mutacao.
#
# Uso: bash scripts/ci/test-ci-guard.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$raiz" || exit 1
guarda='scripts/ci/check-ci-runs-validators.sh'
ci='.github/workflows/ci.yml'
A='scripts/ci/validate-mergex-contract.sh'
B='scripts/ci/validate-review-evidence-contract.sh'

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }

tmp="$(mktemp -d)"
# As sondas dos casos 5 e 7 moram em scripts/ci/: saem tambem na interrupcao.
novo='scripts/ci/validate-novo-contrato-teste.sh'
nova='scripts/ci/mutacao-nova-bancada-teste.sh'
trap 'rm -rf "$tmp"; rm -f "$novo" "$nova"' EXIT

# 0. o workflow real passa
if bash "$guarda" "$ci" >/dev/null 2>&1; then
  passa 'o workflow real roda os dois validadores'
else
  quebra 'o workflow real reprova na guarda'
fi

deve_reprovar() { # <nome> <arquivo-workflow>
  if bash "$guarda" "$2" >/dev/null 2>&1; then
    quebra "$1: a guarda aceitou um workflow que omite um validador"
  else
    passa "$1: a guarda reprova"
  fi
}

# 1 e 2. o passo some
grep -vF "run: bash $A" "$ci" > "$tmp/sem-a.yml"
deve_reprovar 'passo do validate-mergex-contract ausente' "$tmp/sem-a.yml"
grep -vF "run: bash $B" "$ci" > "$tmp/sem-b.yml"
deve_reprovar 'passo do validate-review-evidence-contract ausente' "$tmp/sem-b.yml"

# 3. o passo fica comentado
sed "s|^\([[:space:]]*\)run: bash $B|\1# run: bash $B|" "$ci" > "$tmp/comentado.yml"
deve_reprovar 'passo comentado' "$tmp/comentado.yml"

# 4. o passo duplicado
{ cat "$ci"; printf '      - name: de novo\n        shell: bash\n        run: bash %s\n' "$A"; } > "$tmp/duplicado.yml"
deve_reprovar 'passo duplicado' "$tmp/duplicado.yml"

# 5. um validador novo, não registrado
printf '#!/usr/bin/env bash\nexit 0\n' > "$novo"
if bash "$guarda" "$ci" >/dev/null 2>&1; then
  quebra 'validador novo sem registro: a guarda aceitou'
else
  passa 'validador novo sem registro: a guarda reprova'
fi
rm -f "$novo"

# 6. o workflow de mutacao perde uma bancada
mut='.github/workflows/mutacao.yml'
grep -vE '^[[:space:]]*- mutacao-trava-e1[[:space:]]*$' "$mut" > "$tmp/mutacao-sem-uma.yml"
if bash "$guarda" "$ci" "$tmp/mutacao-sem-uma.yml" >/dev/null 2>&1; then
  quebra 'bancada de mutacao fora do workflow agendado: a guarda aceitou'
else
  passa 'bancada de mutacao fora do workflow agendado: a guarda reprova'
fi

# 6b. a bancada sai da matriz, mas o nome continua noutra lista do workflow
awk '/^[[:space:]]*- mutacao-trava-e1[[:space:]]*$/ { next }
     /^[[:space:]]*paths:[[:space:]]*$/ { print; print "      - mutacao-trava-e1"; next } { print }' \
  "$mut" >"$tmp/mutacao-fora-da-matriz.yml"
if bash "$guarda" "$ci" "$tmp/mutacao-fora-da-matriz.yml" >/dev/null 2>&1; then
  quebra 'bancada so fora da matriz (noutra lista): a guarda aceitou'
else
  passa 'bancada so fora da matriz (noutra lista): a guarda reprova'
fi

# 7. uma bancada de mutacao nova, nao registrada
printf '#!/usr/bin/env bash\nexit 0\n' > "$nova"
if bash "$guarda" "$ci" >/dev/null 2>&1; then
  quebra 'bancada de mutacao nova sem registro: a guarda aceitou'
else
  passa 'bancada de mutacao nova sem registro: a guarda reprova'
fi
rm -f "$nova"

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
