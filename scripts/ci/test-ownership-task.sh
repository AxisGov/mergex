#!/usr/bin/env bash
#
# Bancada do ownership da task no fechamento (E1) — a quarta situação:
# arquivo que mudou, que a task atual não declara e que outra task da mesma
# feature declara.
#
# Confere as quatro situações da tabela do E1, a precedência da task atual
# sobre a irmã, a estabilidade da classificação (nome, descrição e ordem das
# tasks não entram), a recusa de responder sem dono determinado, e reproduz o
# caso do piloto num repositório git temporário: T-03.01 já fechada, T-04.03
# em andamento, o arquivo da irmã mudando para cumprir a T-04.03.
#
# Sem rede, sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-ownership-task.sh
#      OWNERSHIP=<outro script> bash scripts/ci/test-ownership-task.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OWNERSHIP="${OWNERSHIP:-$REPO/.claude/skills/mergex/scripts/ownership-da-task.sh}"

OK=0; FALHOU=0
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

novo_tmp() { local d; d="$(mktemp -d)"; TMPS="$TMPS $d"; printf '%s\n' "$d"; }

# ---------------------------------------------------------------------------
# O plano do piloto: T-03.01 (fechada) e T-04.03 (fechando agora).
# ---------------------------------------------------------------------------
# `titulo`, `objetivo`, `status` e `suite` existem de propósito: a
# classificação não pode olhar para nenhum deles.
planta() { # <raiz> [titulo-0301] [titulo-0403] [ordem: 34|43]
  local raiz="$1" t1="${2:-Cabecalho do topo}" t2="${3:-Menu lateral}" ordem="${4:-34}"
  local f="$raiz/docs/sprintx/features/ft-piloto"
  mkdir -p "$f/sprint-03" "$f/sprint-04"
  cat > "$f/sprint-03/tasks.md" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-piloto
tasks:
  - id: T-03.01
    titulo: $t1
    objetivo: $t1
    status: concluida
    arquivos:
      cria: [tests/ui/cabecalho-topo.test.tsx]
      altera: [src/ui/cabecalho.tsx]
    suite: verde
---
YAML
  cat > "$f/sprint-04/tasks.md" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-piloto
tasks:
  - id: T-04.03
    titulo: $t2
    objetivo: $t2
    status: concluida
    arquivos:
      cria: [src/ui/menu.tsx]
      altera: [src/ui/layout.tsx]
    suite: parcial
---
YAML
  # A ordem em que as tasks aparecem no plano não pode mudar nada: `43` põe as
  # duas no mesmo arquivo, com a T-04.03 antes da T-03.01.
  if [ "$ordem" = 43 ]; then
    cat > "$f/sprint-03/tasks.md" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-piloto
tasks:
  - id: T-04.03
    titulo: $t2
    status: concluida
    arquivos:
      cria: [src/ui/menu.tsx]
      altera: [src/ui/layout.tsx]
    suite: parcial
  - id: T-03.01
    titulo: $t1
    status: concluida
    arquivos:
      cria: [tests/ui/cabecalho-topo.test.tsx]
      altera: [src/ui/cabecalho.tsx]
    suite: verde
---
YAML
    rm -f "$f/sprint-04/tasks.md"
  fi
}

# classifica <raiz> <task> <arquivos...> — guarda a saída em SAIDA e o código
# de saída em RC. Não imprime: `$(classifica ...)` rodaria num subshell, e o
# código — que é metade do contrato deste script — se perderia em silêncio.
RC=0
SAIDA=""
classifica() {
  local raiz="$1" task="$2"; shift 2
  SAIDA="$(bash "$OWNERSHIP" --classificar "$raiz" sprintx ft-piloto "$task" "$@" 2>&1)"; RC=$?
}

# situacao_de <saida> <arquivo> — a situação classificada para aquele caminho.
situacao_de() {
  printf '%s\n' "$1" | awk -F'\t' -v a="$2" '$2 == a { print $1; exit }'
}

# espera <descrição> <esperado> <obtido>
espera() {
  if [ "$2" = "$3" ]; then ok "$1 → $3"; else falha "$1 — obteve '$3', esperava '$2'"; fi
}

D="$(novo_tmp)"; planta "$D"

# ---------------------------------------------------------------------------
echo "1. Arquivo declarado SÓ na task atual e que mudou → entra"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 src/ui/menu.tsx; S="$SAIDA"
espera "src/ui/menu.tsx" na_task_atual "$(situacao_de "$S" src/ui/menu.tsx)"
espera "código de saída: o fechamento segue" 0 "$RC"

# ---------------------------------------------------------------------------
echo
echo "2. Arquivo declarado na ATUAL e numa IRMÃ → é da atual, entra"
# ---------------------------------------------------------------------------
# `src/ui/comum.tsx` em T-03.01 e em T-04.03 ao mesmo tempo.
D2="$(novo_tmp)"; planta "$D2"
sed -i.bak 's#altera: \[src/ui/cabecalho.tsx\]#altera: [src/ui/cabecalho.tsx, src/ui/comum.tsx]#' \
  "$D2/docs/sprintx/features/ft-piloto/sprint-03/tasks.md"
sed -i.bak 's#altera: \[src/ui/layout.tsx\]#altera: [src/ui/layout.tsx, src/ui/comum.tsx]#' \
  "$D2/docs/sprintx/features/ft-piloto/sprint-04/tasks.md"
classifica "$D2" T-04.03 src/ui/comum.tsx; S="$SAIDA"
espera "src/ui/comum.tsx (atual + irmã)" na_task_atual "$(situacao_de "$S" src/ui/comum.tsx)"
espera "a interseção vence: o fechamento segue" 0 "$RC"
# E a evidência guarda as duas tasks, sem que isso mude a situação.
espera "as duas tasks ficam registradas" "T-03.01,T-04.03" \
  "$(printf '%s\n' "$S" | awk -F'\t' '$2 == "src/ui/comum.tsx" { print $3 }')"
# Fechando a IRMÃ, o mesmo arquivo é dela — ownership é sempre da que fecha.
classifica "$D2" T-03.01 src/ui/comum.tsx; S="$SAIDA"
espera "fechando T-03.01, o mesmo arquivo é da T-03.01" na_task_atual "$(situacao_de "$S" src/ui/comum.tsx)"

# ---------------------------------------------------------------------------
echo
echo "3. Arquivo declarado SÓ na irmã e que mudou → condição estruturada"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 tests/ui/cabecalho-topo.test.tsx; S="$SAIDA"
espera "tests/ui/cabecalho-topo.test.tsx" arquivo_de_task_irma \
  "$(situacao_de "$S" tests/ui/cabecalho-topo.test.tsx)"
espera "código de saída: condição estruturada" 2 "$RC"
case "$(situacao_de "$S" tests/ui/cabecalho-topo.test.tsx)" in
  desvio) falha "o arquivo da irmã virou desvio" ;;
  *) ok "não é desvio: o arquivo foi planejado, só que noutra task" ;;
esac
espera "a irmã que o declara fica registrada" "T-03.01" \
  "$(printf '%s\n' "$S" | awk -F'\t' '$2 == "tests/ui/cabecalho-topo.test.tsx" { print $3 }')"
espera "o nome da condição é o que a mergex observa" arquivo_de_task_irma \
  "$(bash "$OWNERSHIP" --condicao)"
# A mergex não fala a língua da sprintx: quem traduz para classe é a sprintx.
case "$(bash "$OWNERSHIP" --situacoes)" in
  *defeito_de_plano*) falha "a mergex nomeia a classe da sprintx" ;;
  *) ok "a mergex não grava defeito_de_plano: ela só nomeia o que observa" ;;
esac

# ---------------------------------------------------------------------------
echo
echo "4. Arquivo em NENHUMA task e que mudou → desvio, como sempre"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 src/ui/orfao.tsx; S="$SAIDA"
espera "src/ui/orfao.tsx" desvio "$(situacao_de "$S" src/ui/orfao.tsx)"
espera "desvio não é a condição nova: o fechamento segue" 0 "$RC"
espera "desvio não tem task" "-" \
  "$(printf '%s\n' "$S" | awk -F'\t' '$2 == "src/ui/orfao.tsx" { print $3 }')"

# ---------------------------------------------------------------------------
echo
echo "5. Declarado na atual e que NÃO mudou → não entra, e não é erro"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 src/ui/menu.tsx; S="$SAIDA"
espera "src/ui/layout.tsx (declarado, intacto)" declarado_nao_mudou \
  "$(situacao_de "$S" src/ui/layout.tsx)"
espera "declarado e intacto não barra" 0 "$RC"

# ---------------------------------------------------------------------------
echo
echo "6. Dois arquivos — um da atual, um só da irmã"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; S="$SAIDA"
espera "o da atual continua sendo da atual" na_task_atual "$(situacao_de "$S" src/ui/menu.tsx)"
espera "o da irmã é a condição" arquivo_de_task_irma \
  "$(situacao_de "$S" tests/ui/cabecalho-topo.test.tsx)"
espera "o conjunto inteiro para: um arquivo válido não salva o commit" 2 "$RC"

# ---------------------------------------------------------------------------
echo
echo "7. Nome, descrição e ordem das tasks não mudam a classificação"
# ---------------------------------------------------------------------------
classifica "$D" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; BASE="$SAIDA"; RC_BASE=$RC
D3="$(novo_tmp)"; planta "$D3" "Outro titulo completamente diferente" "Nada a ver com menu"
classifica "$D3" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; S="$SAIDA"
espera "título e objetivo trocados: mesma saída" "$BASE" "$S"
espera "título e objetivo trocados: mesmo código" "$RC_BASE" "$RC"
D4="$(novo_tmp)"; planta "$D4" "Cabecalho do topo" "Menu lateral" 43
classifica "$D4" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; S="$SAIDA"
espera "ordem das tasks invertida: mesma saída" "$BASE" "$S"
espera "ordem das tasks invertida: mesmo código" "$RC_BASE" "$RC"
classifica "$D" T-04.03 tests/ui/cabecalho-topo.test.tsx src/ui/menu.tsx; S="$SAIDA"
espera "ordem dos arquivos na entrada invertida: mesma saída" "$BASE" "$S"
classifica "$D" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; a="$SAIDA"
classifica "$D" T-04.03 src/ui/menu.tsx tests/ui/cabecalho-topo.test.tsx; b="$SAIDA"
espera "duas execuções, mesma evidência" "$a" "$b"

# ---------------------------------------------------------------------------
echo
echo "8. Sem dono determinado, o script recusa responder (falha fechado)"
# ---------------------------------------------------------------------------
# Nunca infere pela prosa, nunca escolhe a primeira task do plano.
bash "$OWNERSHIP" --classificar "$D" sprintx ft-piloto T-09.99 src/ui/menu.tsx >/dev/null 2>&1
espera "task que o plano não conhece" 1 "$?"
bash "$OWNERSHIP" --classificar "$D" sprintx ft-piloto '' src/ui/menu.tsx >/dev/null 2>&1
espera "task vazia" 1 "$?"
bash "$OWNERSHIP" --classificar "$D" sprintx ft-piloto nao-e-task src/ui/menu.tsx >/dev/null 2>&1
espera "task fora do formato T-NN.MM" 1 "$?"
bash "$OWNERSHIP" --classificar "$(novo_tmp)" sprintx ft-piloto T-04.03 src/ui/menu.tsx >/dev/null 2>&1
espera "sem plano nenhum" 1 "$?"
bash "$OWNERSHIP" --classificar "$D" >/dev/null 2>&1
espera "uso inválido" 64 "$?"
S="$(bash "$OWNERSHIP" --classificar "$D" sprintx ft-piloto T-09.99 src/ui/menu.tsx 2>&1)"
case "$S" in
  *na_task_atual*) falha "classificou sem dono determinado" ;;
  *) ok "não classifica nada sem dono determinado" ;;
esac

# ---------------------------------------------------------------------------
echo
echo "9. O enum é fechado, e as quatro situações existem"
# ---------------------------------------------------------------------------
LISTA="$(bash "$OWNERSHIP" --situacoes | cut -d'|' -f1)"
for s in na_task_atual declarado_nao_mudou desvio arquivo_de_task_irma; do
  printf '%s\n' "$LISTA" | grep -Fxq "$s" && ok "situação declarada: $s" || falha "situação ausente: $s"
done
espera "nenhuma situação a mais" 4 "$(printf '%s\n' "$LISTA" | grep -c .)"

# ---------------------------------------------------------------------------
echo
echo "10. Piloto: T-03.01 fechada, T-04.03 precisa mudar o arquivo dela"
# ---------------------------------------------------------------------------
R="$(novo_tmp)"
git -C "$R" init -q -b main . 2>/dev/null || { git -C "$R" init -q . && git -C "$R" checkout -q -b main; }
git -C "$R" config user.email teste@expx.local; git -C "$R" config user.name Teste
git -C "$R" config core.autocrlf false
planta "$R"
mkdir -p "$R/src/ui" "$R/tests/ui"
printf 'export const cabecalho = 1\n' > "$R/src/ui/cabecalho.tsx"
printf 'test("topo", () => {})\n'     > "$R/tests/ui/cabecalho-topo.test.tsx"
printf 'export const layout = 1\n'    > "$R/src/ui/layout.tsx"
git -C "$R" add -A && git -C "$R" commit -qm "T-03.01 fechada"
git -C "$R" checkout -q -b feature/ft-piloto 2>/dev/null || true

# Para cumprir a T-04.03, o arquivo da T-03.01 muda.
printf 'export const menu = 1\n' > "$R/src/ui/menu.tsx"
printf 'test("topo", () => {})\ntest("menu no topo", () => {})\n' > "$R/tests/ui/cabecalho-topo.test.tsx"

MUDADOS="$(git -C "$R" status --porcelain | sed 's/^...//')"
S="$(printf '%s\n' "$MUDADOS" | bash "$OWNERSHIP" --classificar "$R" sprintx ft-piloto T-04.03 2>&1)"; RC=$?
espera "lendo o que mudou da entrada padrão" 2 "$RC"
espera "src/ui/menu.tsx é da T-04.03" na_task_atual "$(situacao_de "$S" src/ui/menu.tsx)"
espera "o arquivo da T-03.01 é de task irmã" arquivo_de_task_irma \
  "$(situacao_de "$S" tests/ui/cabecalho-topo.test.tsx)"

# O E1 prepara SÓ o que é da task atual. O arquivo da irmã não é adicionado,
# não é apagado, não é restaurado e não some da árvore.
printf '%s\n' "$S" | awk -F'\t' '$1 == "na_task_atual" { print $2 }' \
  | while IFS= read -r a; do [ -n "$a" ] && git -C "$R" add "$a"; done
PREP="$(git -C "$R" diff --cached --name-only)"
espera "só o arquivo da task atual foi preparado" "src/ui/menu.tsx" "$PREP"
case "$PREP" in
  *cabecalho-topo*) falha "o arquivo da irmã entrou no índice" ;;
  *) ok "o arquivo da irmã não entrou no índice" ;;
esac
[ -f "$R/tests/ui/cabecalho-topo.test.tsx" ] && ok "o arquivo da irmã continua na árvore" \
  || falha "o arquivo da irmã sumiu da árvore"
grep -q 'menu no topo' "$R/tests/ui/cabecalho-topo.test.tsx" \
  && ok "a alteração da irmã foi preservada, não revertida" \
  || falha "a alteração da irmã foi descartada"
espera "nenhum commit da T-04.03 foi criado" 0 \
  "$(git -C "$R" log --oneline | grep -c 'T-04.03' || true)"

# V9 continua respondendo pela UNIÃO: o arquivo FOI planejado nesta feature.
UNIAO="$(printf '%s\n' "$S" | awk -F'\t' '$3 != "-" { print $2 }' | sort -u)"
printf '%s\n' "$UNIAO" | grep -Fxq tests/ui/cabecalho-topo.test.tsx \
  && ok "V9 (união): o arquivo pertence ao plano da feature, e não reprova" \
  || falha "o arquivo da irmã ficaria fora da união que a V9 usa"

# ---------------------------------------------------------------------------
echo
echo "11. Replanejado: a task atual passa a declarar o arquivo → o E1 aceita"
# ---------------------------------------------------------------------------
sed -i.bak 's#cria: \[src/ui/menu.tsx\]#cria: [src/ui/menu.tsx, tests/ui/cabecalho-topo.test.tsx]#' \
  "$R/docs/sprintx/features/ft-piloto/sprint-04/tasks.md"
rm -f "$R/docs/sprintx/features/ft-piloto/sprint-04/tasks.md.bak"
S="$(printf '%s\n' "$MUDADOS" | bash "$OWNERSHIP" --classificar "$R" sprintx ft-piloto T-04.03 2>&1)"; RC=$?
espera "depois do replanejamento, o fechamento segue" 0 "$RC"
espera "o mesmo arquivo agora é da task atual" na_task_atual \
  "$(situacao_de "$S" tests/ui/cabecalho-topo.test.tsx)"
# E a T-03.01 antiga continua congelada: ela segue declarando o arquivo.
grep -q 'cabecalho-topo.test.tsx' "$R/docs/sprintx/features/ft-piloto/sprint-03/tasks.md" \
  && ok "a T-03.01 permanece congelada, com o arquivo ainda declarado nela" \
  || falha "a task antiga foi alterada"

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
