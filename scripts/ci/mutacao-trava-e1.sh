#!/usr/bin/env bash
#
# Prova por mutação da seção crítica do E1 (P0.2-C5): o índice é do E1, e o E1
# não é reentrante.
#
# Cada mutação quebra a exclusão mútua de um jeito dirigido, numa CÓPIA
# temporária da árvore, e roda o grupo da bancada que tem que pegá-la. Mutação
# que sobrevive (a verificação continua verde) é teste decorativo — e reprova
# esta suíte. O repositório nunca é tocado: não há nada a restaurar.
#
# A bancada aceita grupos (`test-trava-e1.sh B`), e cada mutante roda só o
# grupo que a prova. Sem isso, dezesseis execuções da bancada inteira, cada uma
# com repositórios Git e concorrência real, levariam mais tempo do que qualquer
# pessoa espera por uma suíte.
#
# Uso: bash scripts/ci/mutacao-trava-e1.sh [M1 M4 ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRAVA='.claude/skills/mergex/scripts/trava-do-e1.sh'
FECHA='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
COMMITS='.claude/skills/mergex/references/01-commits.md'
SCHEMA='.claude/skills/mergex/references/00-schema.md'

TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

# troca <arquivo> <linha exata atual> <linha nova> — falha se a linha não existir
troca() {
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || { printf 'mutação não aplicada: linha ausente em %s\n' "$arq" >&2; return 1; }
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$arq" > "$arq.m"
  cmp -s "$arq" "$arq.m" && { rm -f "$arq.m"; printf 'mutação não aplicada: %s ficou igual\n' "$arq" >&2; return 1; }
  mv "$arq.m" "$arq"
}

# apaga <arquivo> <prefixo da linha>
apaga() {
  local arq="$1" prefixo="$2"
  grep -Fq -- "$prefixo" "$arq" || { printf 'mutação não aplicada: prefixo ausente em %s\n' "$arq" >&2; return 1; }
  awk -v p="$prefixo" 'index($0, p) == 1 { next } { print }' "$arq" > "$arq.m" || return 1
  cmp -s "$arq" "$arq.m" && { rm -f "$arq.m"; printf 'mutação não aplicada: nenhuma linha começa com o prefixo em %s\n' "$arq" >&2; return 1; }
  mv "$arq.m" "$arq"
}

bancada()   { bash scripts/ci/test-trava-e1.sh $GRUPO > saida.log 2>&1; }
validador() { bash scripts/ci/validate-mergex-contract.sh > saida.log 2>&1; }

# ---------------------------------------------------------------------------
# As doze mutações do contrato da C5, mais as que atacam o texto dele.
# ---------------------------------------------------------------------------

# 1. A trava é adquirida só DEPOIS do primeiro `git add`.
M1() {
  troca "$FECHA" '    abre_secao "$TASK"                 # 1 e 2' '    :' || return 1
  troca "$FECHA" '    prepara "$@"                       # A e B' \
    '    prepara "$@"; abre_secao "$TASK"'
}

# 2. A trava passa a ser do índice do diretório Git COMUM: uma por repositório.
M2() {
  troca "$TRAVA" '  p="$(cd "$raiz" && git rev-parse --git-path index 2>/dev/null)"' \
    '  p="$(cd "$raiz" && git rev-parse --git-common-dir 2>/dev/null)/index"'
}

# 3. O E1 ignora a trava existente e segue em frente.
M3() {
  troca "$TRAVA" '  if ! mkdir "$trava" 2>/dev/null; then' \
    '  if ! mkdir -p "$trava" 2>/dev/null; then'
}

# 4. Stage preexistente é aceito.
M4() {
  troca "$FECHA" '  [ -n "$staged" ] || return 0' '  return 0'
}

# 5. Stage preexistente é limpo antes de seguir.
M5() {
  troca "$FECHA" '  [ -n "$staged" ] || return 0' \
    '  git reset -q >/dev/null 2>&1; return 0'
}

# 6. A trava é liberada ANTES de acrescentar o item em ENTREGA.commits.
M6() {
  troca "$FECHA" '  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \' \
    '  liberar "$TOKEN" >/dev/null 2>&1; LIBERAR_NA_SAIDA=0
  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \'
}

# 7. O `seq` é calculado fora da seção: D a G inteiros saem de baixo da trava.
M7() {
  troca "$FECHA" '    conclui "$ENTREGA" "$TASK" "$MENSAGEM"   # D a G' \
    '    liberar "$TOKEN" >/dev/null 2>&1; LIBERAR_NA_SAIDA=0; conclui "$ENTREGA" "$TASK" "$MENSAGEM"'
}

# 8. O segundo E1 entra na seção e consegue commitar.
M8() {
  troca "$FECHA" '  saida="$(adquirir "$1")"; rc=$?' \
    '  saida="$(adquirir "$1")"; rc=0; saida="token=forcado"' || return 1
  troca "$FECHA" '  [ -n "$staged" ] || return 0' '  return 0'
}

# 9. Falha no append dispara um segundo commit.
M9() {
  troca "$FECHA" '  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \' \
    '  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" || git commit --allow-empty -q -m "segundo commit do E1"
  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \'
}

# 10. A trava órfã é removida automaticamente.
M10() {
  troca "$TRAVA" '  if ! mkdir "$trava" 2>/dev/null; then' \
    '  if [ -d "$trava" ]; then rm -rf "$trava"; fi
  if ! mkdir "$trava" 2>/dev/null; then'
}

# 11. Uma trava só para o repositório: worktrees diferentes bloqueiam uma à outra.
M11() {
  troca "$TRAVA" "  printf '%s%s\\n' \"\$i\" \"\$SUFIXO_DA_TRAVA\"" \
    '  printf "%s/mergex-e1%s\n" "$(cd "$(raiz_da_worktree)" && cd "$(git rev-parse --git-common-dir)" && pwd)" "$SUFIXO_DA_TRAVA"'
}

# 12. A saída normal deixa a trava presa.
M12() {
  troca "$FECHA" '  if [ "$LIBERAR_NA_SAIDA" = 1 ] && [ -n "$TOKEN" ]; then' '  if false; then'
}

# 13. O contrato perde a seção crítica.
M13() { apaga "$COMMITS" '## A seção crítica do E1'; }

# 14. O contrato volta a permitir decidir o gitdir por teste de diretório.
M14() {
  troca "$COMMITS" '`.git` **pode ser um ARQUIVO** — é o que a sprintx produz ao abrir a feature em `git worktree` próprio. **Nunca use `[ -d .git ]`.** Quem responde onde está o índice é o versionador:' \
    'Descubra o gitdir como preferir.'
}

# 15. O contrato perde o desfecho "commit existe, registro não".
M15() { apaga "$COMMITS" '**NÃO crie um segundo commit.**'; }

# 16. Um segundo escritor real de ENTREGA.commits escapa da regra.
M16() {
  printf '#!/usr/bin/env bash\nbash sequencia-de-commits.sh --acrescentar "$1" "$2" "$3"\n' \
    > escritor-solto.sh
}

# 17. O schema deixa de dizer que o seq é atribuído sob a seção crítica.
M17() { apaga "$SCHEMA" '**Quem impede a corrida é o E1**'; }

LISTA='M1|trava adquirida so depois do git add|bancada|B
M2|trava no indice do diretorio Git comum|bancada|C
M3|E1 ignora trava existente|bancada|E
M4|stage preexistente e aceito|bancada|D
M5|stage preexistente e limpo|bancada|D
M6|trava liberada antes de acrescentar a ENTREGA|bancada|ESPIAO
M7|seq calculado fora da secao critica|bancada|ESPIAO
M8|segundo E1 consegue commitar|bancada|B
M9|falha no append dispara segundo commit|bancada|I
M10|trava orfa e removida automaticamente|bancada|E
M11|worktrees diferentes bloqueiam uma a outra|bancada|C
M12|saida normal deixa trava residual|bancada|A
M13|o contrato perde a secao critica do E1|validador|
M14|o contrato volta a permitir [ -d .git ]|validador|
M15|o contrato perde o desfecho commit sem registro|validador|
M16|um segundo escritor real de commits escapa da regra|validador|
M17|o schema nao situa o seq sob a secao critica|validador|'

SELECAO=" $* "
MORTAS=0; VIVAS=0; ERROS=0; CONTROLE_OK=1
PIDS=""; IDS=""

# Controle sem mutação: numa cópia intocada, as verificações TÊM que passar.
controle() {
  local d rc
  d="$(copia)"
  echo "Controle — cópia SEM mutação: as verificações têm que passar"
  for v in bancada validador; do
    rc=0; ( cd "$d" && GRUPO="" "$v" ) || rc=$?
    if [ "$rc" = 0 ]; then printf '  ok     %s\n' "$v"
    else CONTROLE_OK=0; printf '  FALHA  %s — verde era esperado (rc=%s)\n' "$v" "$rc"
         sed 's/^/           /' "$d/saida.log" 2>/dev/null | tail -8; fi
  done
  echo
}
[ "$#" -eq 0 ] && controle

REPO_TMP="$(mktemp -d)"; TMPS="$TMPS $REPO_TMP"

roda() { # id desc verificacao grupo
  local id="$1" verif="$3" grupo="$4" d
  d="$(copia)"
  (
    cd "$d" || exit 3
    "$id" || exit 3
    if GRUPO="$grupo" "$verif"; then exit 1; else exit 0; fi
  ) > "$d/mutacao.log" 2>&1
  printf '%s\n' "$?" > "$d/rc"
  printf '%s\n' "$d" > "$REPO_TMP/$id.dir"
}

while IFS='|' read -r id desc verif grupo; do
  [ -n "$id" ] || continue
  [ "$#" -eq 0 ] || case "$SELECAO" in *" $id "*) ;; *) continue ;; esac
  roda "$id" "$desc" "$verif" "$grupo" &
  PIDS="$PIDS $!"; IDS="$IDS $id"
done <<EOF
$LISTA
EOF
for p in $PIDS; do wait "$p"; done

echo "Mutações dirigidas — a verificação TEM que falhar"
while IFS='|' read -r id desc verif grupo; do
  [ -n "$id" ] || continue
  case " $IDS " in *" $id "*) ;; *) continue ;; esac
  d="$(cat "$REPO_TMP/$id.dir" 2>/dev/null)"
  rc="$(cat "$d/rc" 2>/dev/null)"
  case "$rc" in
    0) MORTAS=$((MORTAS+1))
       printf '  morta  %-4s %s (%s%s) — pega por:\n' "$id" "$desc" "$verif" "${grupo:+ $grupo}"
       grep -E 'FALHA|contract check failed' "$d/saida.log" 2>/dev/null | head -3 \
         | sed 's/^[[:space:]]*//' | cut -c1-150 | sed 's/^/           /' ;;
    1) VIVAS=$((VIVAS+1)); printf '  VIVA   %-4s %s — %s continuou verde\n' "$id" "$desc" "$verif" ;;
    *) ERROS=$((ERROS+1)); printf '  ERRO   %-4s %s — mutação não aplicada\n' "$id" "$desc"
       sed 's/^/         /' "$d/mutacao.log" 2>/dev/null | head -5 ;;
  esac
done <<EOF
$LISTA
EOF

echo "---------------------------------------------"
printf '%d morta(s), %d viva(s), %d erro(s)\n' "$MORTAS" "$VIVAS" "$ERROS"
[ "$CONTROLE_OK" = 1 ] || printf 'controle sem mutação REPROVOU: as mutações não provam nada\n'
[ "$VIVAS" = 0 ] && [ "$ERROS" = 0 ] && [ "$CONTROLE_OK" = 1 ]
