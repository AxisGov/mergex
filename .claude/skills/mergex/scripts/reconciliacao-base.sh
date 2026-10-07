#!/usr/bin/env bash
# reconciliacao-base — registra a reconciliação de base pós-E8.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seções 5 (modelo Git), 6 (as quatro provas), 7 (artefato) e 8 (--registrar).
#
# Uso:
#   reconciliacao-base.sh --registrar --entrega docs/entregas/<id>/ENTREGA.md \
#     --origem <sprintx|runx> --trabalho <id> -- <caminho>...
#
#   M é HEAD; P1 = M^1; B1 = M^2; B0 = base_validada_sha do ENTREGA.md.
#   Calcula as condições estruturais, as quatro provas de cada caminho dado e o
#   inventário completo do merge (`git diff --name-only B1 M` contido em união
#   das tasks ∪ catálogo de método ∪ lista). Tudo aprovado: grava
#   docs/entregas/<id>/RECONCILIACAO-BASE-001.md e imprime `registrado=`,
#   `b0=`, `p1=`, `b1=`, `m=`. Qualquer reprovação: nada é gravado, e cada
#   motivo sai no stderr como `reconciliacao-base: <motivo>`.
#
#   Toda prova é recalculada do Git; nenhum caminho é aceito por estar listado.
#   Não há opção de força, nem variável de ambiente que relaxe prova.
#
# Códigos: 0 registrado; 1 ambiente (fora de repositório, temporário, trava
#   não criada); 2 trava C5 ocupada; 3 stage não vazio ou merge em andamento;
#   4 prova reprovada (estrutura, uma das quatro provas, inventário);
#   5 contrato do ENTREGA.md inválido ou reconciliação já registrada;
#   6 base validada indeterminável; 64 uso.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAVA_SH="$AQUI/trava-do-e1.sh"
CONTRATO_SH="$AQUI/contrato-de-commit.sh"
CATALOGO_SH="$AQUI/catalogo-de-metodo.sh"
OWNERSHIP_SH="$AQUI/ownership-da-task.sh"
ARTEFATO_SH="$AQUI/reconciliacao-artefato.sh"

for dependencia in "$TRAVA_SH" "$CONTRATO_SH" "$CATALOGO_SH" "$OWNERSHIP_SH" "$ARTEFATO_SH"; do
  [ -r "$dependencia" ] || { printf 'reconciliacao-base: dependência indisponível: %s\n' "$dependencia" >&2; exit 1; }
done
# shellcheck source=trava-do-e1.sh
. "$TRAVA_SH"
# shellcheck source=catalogo-de-metodo.sh
. "$CATALOGO_SH"
# shellcheck source=reconciliacao-artefato.sh
. "$ARTEFATO_SH"
set +e

# Caminho exatamente como no Git, qualquer que seja a configuração do
# repositório: sem escape de nome (quotepath) e pathspec sempre literal. Vale
# também para o rb_diff_sha da biblioteca, que roda neste processo.
unset GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS GIT_NOGLOB_PATHSPECS
export GIT_LITERAL_PATHSPECS=1
# (advice.graftFileDeprecated: o GIT_GRAFT_FILE abaixo não polui o stderr)
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=advice.graftFileDeprecated GIT_CONFIG_VALUE_1=false
# Ancestralidade e objetos só do Git, nunca de enxertos locais: refs/replace e
# .git/info/grafts falsificariam os pais de M. Exportado, para que os filhos
# (contrato-de-commit.sh, ownership-da-task.sh) herdem.
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null # guarda:EST
g() { git -c core.quotepath=false "$@"; }

NL='
'
TAB='	'

MODO=""
ENTREGA=""
ORIGEM=""
TRABALHO=""
SEPARADOR=0

uso() {
  [ -z "${1:-}" ] || printf 'reconciliacao-base: %s\n' "$1" >&2
  printf '%s\n' \
    'uso: reconciliacao-base.sh --registrar --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id> -- <caminho>...' >&2
  exit 64
}

TMP_DIR=""
TOKEN=""
LIBERAR_NA_SAIDA=0

encerrar() {
  local rc="$1"
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  if [ "$LIBERAR_NA_SAIDA" = 1 ] && [ -n "$TOKEN" ]; then
    liberar "$TOKEN" >/dev/null 2>&1
  fi
  exit "$rc"
}
trap 'encerrar $?' EXIT

# para <rc> <motivo> — encerra sem gravar nada.
para() {
  printf 'reconciliacao-base: %s\n' "$2" >&2
  exit "$1"
}

# Condição estrutural reprovada: as provas não são calculáveis sobre ela.
estrutura() { para 4 "estrutura[$1]: $2"; }

FALHAS=0
reprova() {
  printf 'reconciliacao-base: %s\n' "$1" >&2
  FALHAS=$((FALHAS + 1))
}

# ---------------------------------------------------------------------------
# Argumentos. Os caminhos vêm depois de `--`, um por argumento, sem word
# splitting; vão para um arquivo, um por linha, depois de recusar os que não
# cabem numa linha.
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-reconciliacao.XXXXXX")" \
  || { printf 'reconciliacao-base: não foi possível criar diretório temporário\n' >&2; exit 1; }
LISTA="$TMP_DIR/lista"
: > "$LISTA"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --registrar) [ -z "$MODO" ] || uso; MODO=registrar; shift ;;
    --entrega) [ "$#" -ge 2 ] || uso; ENTREGA="$2"; shift 2 ;;
    --origem) [ "$#" -ge 2 ] || uso; ORIGEM="$2"; shift 2 ;;
    --trabalho) [ "$#" -ge 2 ] || uso; TRABALHO="$2"; shift 2 ;;
    --) SEPARADOR=1; shift; break ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done

[ "$MODO" = registrar ] || uso 'falta --registrar'
[ "$SEPARADOR" = 1 ] || uso 'falta -- antes da lista de caminhos'
case "$ORIGEM" in sprintx|runx) ;; *) uso "origem inválida: ${ORIGEM:-ausente}" ;; esac
case "$TRABALHO" in
  ''|*[!A-Za-z0-9._-]*|.*|sprintx|manutencao|entregas|eventos|relatorios|legado|stack|projeto)
    uso "trabalho inválido: ${TRABALHO:-ausente}" ;;
esac
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
[ "$ENTREGA" = "docs/entregas/$TRABALHO/ENTREGA.md" ] || uso "--entrega deve ser docs/entregas/$TRABALHO/ENTREGA.md"

for caminho in "$@"; do
  case "$caminho" in
    ''|*"$NL"*|*"$TAB"*) uso "caminho vazio ou com quebra de linha/tabulação" ;;
    /*|./*|..|../*|*/../*|*/..|*/./*|*/.|*//*) uso "caminho fora da forma do Git (relativo à raiz, sem . ou ..): $caminho" ;;
  esac
  grep -Fxq -e "$caminho" "$LISTA" && uso "caminho repetido na lista: $caminho"
  printf '%s\n' "$caminho" >> "$LISTA"
done

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { printf 'reconciliacao-base: fora de um repositório Git\n' >&2; exit 1; }
cd "$RAIZ" || { printf 'reconciliacao-base: raiz inacessível: %s\n' "$RAIZ" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pré-condições: trava C5, stage vazio, nenhum merge em andamento.
# ---------------------------------------------------------------------------
SAIDA_TRAVA="$(adquirir reconciliacao-base)"; RC_TRAVA=$?
[ "$RC_TRAVA" != 2 ] || para 2 'índice ocupado pela trava C5'
[ "$RC_TRAVA" = 0 ] || para 1 'não foi possível adquirir a trava C5 do índice'
TOKEN="$(printf '%s\n' "$SAIDA_TRAVA" | awk -F= '$1 == "token" { print $2 }')"
[ -n "$TOKEN" ] || para 1 'a trava C5 foi criada sem token'
LIBERAR_NA_SAIDA=1

if g rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  para 3 'merge em andamento (MERGE_HEAD presente): conclua o commit de integração antes de registrar'
fi
g diff --cached --quiet 2>/dev/null || para 3 'o stage não está vazio; nada foi limpo ou adotado'

# ---------------------------------------------------------------------------
# M e o que alimenta as provas. Nada que esteja só no disco entra numa prova:
# o ENTREGA.md, a pasta do trabalho (plano e catálogo) são lidos do commit M.
# ---------------------------------------------------------------------------
M="$(g rev-parse --verify -q HEAD)" || estrutura m 'HEAD ilegível'

# modo_em_m <caminho> — o modo do caminho na árvore de M (vazio se ausente)
modo_em_m() { g ls-tree -z "$M" -- "$1" 2>/dev/null | tr '\0' '\n' | sed -n '1s/ .*//p'; }

# ---------------------------------------------------------------------------
# ENTREGA.md (versão de M): contexto explícito igual ao registrado.
# ---------------------------------------------------------------------------
ENTREGA_M="$TMP_DIR/entrega-m.md"
MODO_ENTREGA="$(modo_em_m "$ENTREGA")"
[ -n "$MODO_ENTREGA" ] || para 5 "$ENTREGA ausente no commit M $M"
case "$MODO_ENTREGA" in 100644|100755) ;; *) para 5 "$ENTREGA não é arquivo regular em M (modo $MODO_ENTREGA)" ;; esac
g cat-file blob "$M:$ENTREGA" > "$ENTREGA_M" 2>/dev/null || para 5 "$ENTREGA ilegível em M"
fm() { catalogo_fm "$ENTREGA_M" "$1"; }

[ "$(fm kind)" = entrega ] || para 5 "$ENTREGA não declara kind: entrega"
[ "$(fm trabalho_id)" = "$TRABALHO" ] || para 5 'trabalho explícito diverge de ENTREGA.trabalho_id'
[ "$(fm expx_tool)" = "$ORIGEM" ] || para 5 'origem explícita diverge de ENTREGA.expx_tool'
BRANCH="$(g branch --show-current 2>/dev/null)" || BRANCH=""
[ -n "$BRANCH" ] || para 5 'HEAD destacado: a branch não prova o trabalho'
[ "$(fm branch)" = "$BRANCH" ] || para 5 "branch ativa ($BRANCH) diverge de ENTREGA.branch"
BRANCH_BASE="$(fm branch_base)"
[ -n "$BRANCH_BASE" ] || para 5 'ENTREGA.branch_base ausente'

# Árvore de M materializada só no necessário para resolver a pasta do trabalho
# e ler o plano: as três pastas candidatas, blob por blob. Link simbólico ou
# submódulo dentro delas: o plano não é lido, o registro para (rc 5).
RAIZ_M="$TMP_DIR/arvore-m"
mkdir -p "$RAIZ_M" || para 1 'não foi possível criar a árvore temporária de M'
g ls-tree -r -z --full-tree "$M" -- "docs/sprintx/features/$TRABALHO" "docs/$TRABALHO" "docs/manutencao/$TRABALHO" \
  > "$TMP_DIR/arvore-m.lista" 2>/dev/null || para 4 "prova 3: árvore de M ilegível"
while IFS= read -r -d '' item <&3; do
  modo="${item%% *}"; caminho="${item#*	}"
  # a união separa os tasks.md por linha: um nome com quebra de linha (ou
  # outro caractere de controle) desviaria a leitura para o disco
  case "$caminho" in *"$NL"*|*"$TAB"*|*[[:cntrl:]]*) para 5 "pasta do trabalho em M com caminho inválido: $(printf '%s' "$caminho" | tr '[:cntrl:]' '?')" ;; esac # guarda:P3
  case "$modo" in
    100644|100755) ;;
    *) para 5 "pasta do trabalho em M tem link simbólico ou submódulo (modo $modo): $caminho" ;;
  esac
  mkdir -p "$RAIZ_M/$(dirname "$caminho")" && g cat-file blob "$M:$caminho" > "$RAIZ_M/$caminho" 2>/dev/null \
    || para 4 "prova 3: não foi possível ler $caminho de M"
done 3< "$TMP_DIR/arvore-m.lista"

# A pasta do trabalho resolvida em M; no disco ela tem de estar igual a M, sem
# alteração nem arquivo não rastreado (defesa em profundidade).
# Sem subshell: o CATALOGO_ERRO da função chega ao motivo.
catalogo_pasta_do_trabalho "$RAIZ_M" "$ORIGEM" "$TRABALHO" > "$TMP_DIR/pasta" \
  || para 4 "prova 3: pasta do trabalho não determinável em M: $CATALOGO_ERRO"
PASTA="$(cat "$TMP_DIR/pasta")"
g status --porcelain=v1 -z --untracked-files=all -- "$PASTA" > "$TMP_DIR/sujo" 2>/dev/null \
  || para 3 'não foi possível verificar se a pasta do trabalho está limpa'
[ ! -s "$TMP_DIR/sujo" ] || para 3 "pasta do trabalho com alteração não commitada: $(tr '\0' ' ' < "$TMP_DIR/sujo" | cut -c1-200)" # guarda:LIMPA

# Na pasta da entrega, só o que o próprio registro grava pode estar pendente
# (antes do checkpoint reconciliacao-base): ENTREGA.md alterado na árvore e
# RECONCILIACAO-BASE-NNN.md não rastreado ou alterado. Caminho casado exato.
ENTREGA_DIR="docs/entregas/$TRABALHO"
g status --porcelain=v1 -z --untracked-files=all -- "$ENTREGA_DIR" > "$TMP_DIR/sujo-entrega" 2>/dev/null \
  || para 3 'não foi possível verificar se a pasta da entrega está limpa'
while IFS= read -r -d '' registro <&3; do
  xy="${registro:0:2}"; p="${registro:3}"; tolerado=0
  if [ "$xy" = ' M' ] && [ "$p" = "$ENTREGA_DIR/ENTREGA.md" ]; then tolerado=1; fi # guarda:LIMPA
  case "$xy:$p" in "??:$ENTREGA_DIR/"RECONCILIACAO-BASE-[0-9][0-9][0-9].md|" M:$ENTREGA_DIR/"RECONCILIACAO-BASE-[0-9][0-9][0-9].md) tolerado=1 ;; esac # guarda:LIMPA
  [ "$tolerado" = 1 ] || para 3 "pasta do trabalho com alteração não commitada (entrega, fora do que o registro grava): $xy $p" # guarda:LIMPA
done 3< "$TMP_DIR/sujo-entrega"

for existente in "docs/entregas/$TRABALHO"/RECONCILIACAO-BASE-*.md; do
  [ -e "$existente" ] || [ -L "$existente" ] || continue
  para 5 "já existe reconciliação registrada ($existente); encadear reconciliações ainda não é suportado"
done

B0="$(fm base_validada_sha)"
[ -n "$B0" ] || para 6 'ENTREGA.base_validada_sha ausente: base validada indeterminável'
printf '%s' "$B0" | grep -Eq '^[0-9a-f]{40}$' || para 5 "ENTREGA.base_validada_sha não é SHA de 40 hex: $B0"
g cat-file -e "$B0^{commit}" 2>/dev/null || estrutura b0 "B0 $B0 não é commit deste repositório"

# ---------------------------------------------------------------------------
# Condições estruturais (seção 5). M = HEAD.
# ---------------------------------------------------------------------------
PAIS="$(g rev-list --parents -n1 "$M" 2>/dev/null)" || estrutura m "pais de M ilegíveis"
NPAIS=$(( $(printf '%s\n' "$PAIS" | wc -w) - 1 ))
[ "$NPAIS" = 2 ] || estrutura pais "M $M tem $NPAIS pai(s); o commit de integração tem exatamente dois" # guarda:EST
P1="$(g rev-parse --verify -q "$M^1")" || estrutura m 'M^1 ilegível'
B1="$(g rev-parse --verify -q "$M^2")" || estrutura m 'M^2 ilegível'
g rev-list --first-parent "$BRANCH" > "$TMP_DIR/primeiro-pai" 2>/dev/null || estrutura primeiro_pai "linha de primeiro pai de $BRANCH ilegível"
grep -Fxq -e "$M" "$TMP_DIR/primeiro-pai" || estrutura primeiro_pai "M $M fora da linha de primeiro pai de $BRANCH" # guarda:EST
CONTRATO_ERR="$TMP_DIR/contrato.err"
bash "$CONTRATO_SH" --validar-integracao --trabalho "$TRABALHO" --commit "$M" >/dev/null 2>"$CONTRATO_ERR" || estrutura contrato "mensagem de M fora do contrato de integração: $(tr '\n' ' ' < "$CONTRATO_ERR")" # guarda:EST
g merge-base --is-ancestor "$B0" "$B1" 2>/dev/null || estrutura b0_b1 "B0 $B0 não é ancestral de B1 $B1" # guarda:EST
g merge-base --is-ancestor "$B0" "$P1" 2>/dev/null || estrutura b0_p1 "B0 $B0 não é ancestral de P1 $P1" # guarda:EST
PONTA_BASE="$(g rev-parse --verify -q "$BRANCH_BASE^{commit}")" || estrutura base "ref de base $BRANCH_BASE ilegível"
g merge-base --is-ancestor "$B1" "$PONTA_BASE" 2>/dev/null || estrutura base "B1 $B1 não é ancestral da ponta de $BRANCH_BASE ($PONTA_BASE)" # guarda:EST

# ---------------------------------------------------------------------------
# União das tasks e catálogo de método (prova 3 e inventário), sobre a árvore
# de M, nunca sobre o disco.
# ---------------------------------------------------------------------------
UNIAO="$TMP_DIR/uniao"
CATALOGO="$TMP_DIR/catalogo"
bash "$OWNERSHIP_SH" --uniao "$RAIZ_M" "$ORIGEM" "$TRABALHO" > "$UNIAO" 2>"$TMP_DIR/uniao.err" || para 4 "prova 3: união das tasks não calculável: $(tr '\n' ' ' < "$TMP_DIR/uniao.err")" # guarda:P3
catalogo_metodo "$RAIZ_M" "$ORIGEM" "$TRABALHO" "$PASTA" e8 > "$CATALOGO" || para 4 "prova 3: catálogo de método não calculável: $CATALOGO_ERRO" # guarda:P3

contem() { grep -Fxq -e "$2" "$1"; }

# ---------------------------------------------------------------------------
# As quatro provas, para cada caminho (seção 6). Todas são calculadas e todas
# as reprovações são relatadas; nenhuma falha de cálculo vira aprovação.
# ---------------------------------------------------------------------------
INICIO="$B0"
SAIDA="$TMP_DIR/saida"
while IFS= read -r f <&3; do
  # o caminho é de arquivo (blob), nunca de diretório nem submódulo
  case "$f" in */) reprova "arquivo: $f: caminho com barra final não é arquivo"; continue ;; esac # guarda:BLOB
  tb="$(g cat-file -t "$B1:$f" 2>/dev/null)"; tm="$(g cat-file -t "$M:$f" 2>/dev/null)"
  { [ -z "$tb" ] || [ "$tb" = blob ]; } && { [ -z "$tm" ] || [ "$tm" = blob ]; } || reprova "arquivo: $f: não é arquivo (blob) em B1 (${tb:--}) ou em M (${tm:--})" # guarda:BLOB

  # prova 1: f nasceu ou mudou na base entre B0 e B1
  if g diff --no-renames --name-status -z "$B0" "$B1" -- "$f" > "$SAIDA" 2>/dev/null; then
    st="$(tr '\0' '\n' < "$SAIDA" | sed -n 1p)"
    [ -n "$st" ] || reprova "prova 1: $f: a base não criou nem alterou o caminho entre B0 e B1" # guarda:P1
    [ "$st" != D ] || reprova "prova 1: $f: a base removeu o caminho (status D); ressurreição não é ajuste" # guarda:P1D
    case "$st" in A|M|D|'') ;; *) reprova "prova 1: $f: status $st na base fora de A|M (mudança de tipo também reprova)" ;; esac # guarda:P1T
  else
    reprova "prova 1: $f: diff B0..B1 não calculável"
  fi

  # prova 2: a feature não tocou f antes do merge
  if g rev-list --first-parent "$P1" "^$INICIO" -- "$f" > "$SAIDA" 2>/dev/null; then
    [ ! -s "$SAIDA" ] || reprova "prova 2: $f: a feature tocou o caminho antes do merge ($(sed -n 1p "$SAIDA"))" # guarda:P2FP
  else
    reprova "prova 2: $f: histórico da feature não calculável"
  fi

  # prova 3: f não consta das tasks nem é artefato de método
  if contem "$UNIAO" "$f" || contem "$CATALOGO" "$f"; then reprova "prova 3: $f: declarado em task ou artefato de método"; fi # guarda:P3

  # prova 4: diferença real entre B1 e M, com f presente em M
  g cat-file -e "$M:$f" 2>/dev/null || reprova "prova 4: $f: ausente em M (a integração removeu o caminho)" # guarda:P4
  g diff --quiet --no-renames "$B1" "$M" -- "$f" >/dev/null 2>&1; rc_p4=$?
  [ "$rc_p4" = 1 ] || reprova "prova 4: $f: sem diferença entre B1 e M (ou diff não calculável, rc=$rc_p4)" # guarda:P4
done 3< "$LISTA"

# ---------------------------------------------------------------------------
# Inventário completo: todo caminho que o merge alterou em relação a B1 está
# na união, no catálogo ou na lista. Não existe registro parcial.
# ---------------------------------------------------------------------------
INVENTARIO="$TMP_DIR/inventario"
g diff --name-only -z --no-renames "$B1" "$M" > "$INVENTARIO" 2>/dev/null \
  || para 4 'inventário: diff B1..M não calculável'
while IFS= read -r -d '' p <&3; do
  case "$p" in *"$NL"*) reprova "inventário: caminho com quebra de linha alterado pelo merge"; continue ;; esac
  contem "$UNIAO" "$p" || contem "$CATALOGO" "$p" || contem "$LISTA" "$p" || reprova "inventário: $p: alterado pelo merge e não declarado" # guarda:INV
done 3< "$INVENTARIO"

[ "$FALHAS" = 0 ] || para 4 "$FALHAS reprovação(ões); nada foi gravado"

# ---------------------------------------------------------------------------
# Artefato (seção 7). Só depois de tudo aprovado.
# ---------------------------------------------------------------------------
NOME="RECONCILIACAO-BASE-001.md"
DESTINO="docs/entregas/$TRABALHO/$NOME"
ESC="$TMP_DIR/escalares.tsv"
ARQ="$TMP_DIR/arquivos.tsv"
{
  printf 'expx_tool\t%s\n' "$ORIGEM"
  printf 'trabalho_id\t%s\n' "$TRABALHO"
  printf 'numero\t1\n'
  printf 'anterior\tnull\n'
  printf 'branch\t%s\n' "$BRANCH"
  printf 'branch_base\t%s\n' "$BRANCH_BASE"
  printf 'origem_base\tregistrada_e0\n'
  printf 'b0_sha\t%s\n' "$B0"
  printf 'p1_sha\t%s\n' "$P1"
  printf 'b1_sha\t%s\n' "$B1"
  printf 'm_sha\t%s\n' "$M"
  printf 'estado\tativa\n'
  printf 'registrado_em\t%s\n' "$(date +%Y-%m-%d)"
} > "$ESC" || para 1 'não foi possível montar os escalares do artefato'
: > "$ARQ"
LC_ALL=C sort "$LISTA" > "$TMP_DIR/lista.ord" || para 1 'não foi possível ordenar a lista'
while IFS= read -r f <&3; do
  st="$(g diff --no-renames --name-status -z "$B0" "$B1" -- "$f" 2>/dev/null | tr '\0' '\n' | sed -n 1p)"
  case "$st" in A|M) ;; *) para 4 "artefato: status de $f mudou durante o registro" ;; esac
  bb="$(g rev-parse --verify -q "$B1:$f")" || para 4 "artefato: blob de $f em B1 ilegível"
  bm="$(g rev-parse --verify -q "$M:$f")" || para 4 "artefato: blob de $f em M ilegível"
  RB_ERRO=""
  rb_diff_sha "$B1" "$M" "$f" > "$SAIDA" || para 4 "artefato: $RB_ERRO"
  ds="$(cat "$SAIDA")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$bb" "$bm" "$ds" \
    "ajuste exigido pela integração da base: ver o diff B1..M deste caminho" >> "$ARQ"
done 3< "$TMP_DIR/lista.ord"

[ -d "docs/entregas/$TRABALHO" ] || para 5 "pasta da entrega ausente: docs/entregas/$TRABALHO"
RB_ERRO=""
rb_emitir "$DESTINO" "$ESC" "$ARQ" || para 5 "artefato não emitido: $RB_ERRO"

printf 'registrado=%s\n' "$NOME"
printf 'b0=%s\n' "$B0"
printf 'p1=%s\n' "$P1"
printf 'b1=%s\n' "$B1"
printf 'm=%s\n' "$M"
exit 0
