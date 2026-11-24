#!/usr/bin/env bash
# registrar-atencao — persiste a classificação E3 no registro da entrega.
#
# Uso: registrar-atencao.sh --entrega docs/entregas/<id>/ENTREGA.md
#        [--atencao <ATENCAO.md>]

set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RB_SH="$AQUI/reconciliacao-base.sh"
NL='
'

uso() {
  [ -z "${1:-}" ] || printf 'registrar-atencao: %s\n' "$1" >&2
  printf '%s\n' 'uso: registrar-atencao.sh --entrega <docs/entregas/<id>/ENTREGA.md> [--atencao <ATENCAO.md>]' >&2
  exit 64
}
recusa() { printf 'registrar-atencao: %s\n' "$1" >&2; exit 5; }
ambiente() { printf 'registrar-atencao: %s\n' "$1" >&2; exit 1; }

ENTREGA=""; ATENCAO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --entrega) [ "$#" -ge 2 ] || uso; ENTREGA="$2"; shift 2 ;;
    --atencao) [ "$#" -ge 2 ] || uso; ATENCAO="$2"; shift 2 ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done
[ -n "$ENTREGA" ] || uso 'falta --entrega'
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
case "$ENTREGA" in docs/entregas/*/ENTREGA.md) ;; *) uso '--entrega deve ser docs/entregas/<id>/ENTREGA.md' ;; esac
TRABALHO="${ENTREGA#docs/entregas/}"; TRABALHO="${TRABALHO%/ENTREGA.md}"
case "$TRABALHO" in ''|*/*|*[!A-Za-z0-9._-]*|.*) uso 'trabalho inválido' ;; esac

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" || ambiente 'o Git não resolveu a raiz do repositório'
ARQ="$RAIZ/$ENTREGA"
[ -f "$ARQ" ] && [ ! -L "$ARQ" ] || recusa "$ENTREGA não é arquivo regular"
ID_REGISTRO="$(awk '/^trabalho_id:[[:space:]]*/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit }' "$ARQ")"
[ "$ID_REGISTRO" = "$TRABALHO" ] || recusa 'ENTREGA.md tem trabalho_id diferente do caminho'
[ -n "$ATENCAO" ] || ATENCAO="${ENTREGA%/ENTREGA.md}/ATENCAO.md"
case "$ATENCAO" in /*) ATENCAO_ARQ="$ATENCAO" ;; *) ATENCAO_ARQ="$RAIZ/${ATENCAO#./}" ;; esac
[ -f "$ATENCAO_ARQ" ] && [ ! -L "$ATENCAO_ARQ" ] || recusa "ATENCAO.md ausente: $ATENCAO"
grep -Fq '{{' "$ATENCAO_ARQ" && recusa 'ATENCAO.md ainda tem marcador {{...}}'

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-registrar-atencao.XXXXXX")" || ambiente 'não foi possível criar temporário'
TMP_ARQ=""
limpar() { local rc="$1"; [ -z "$TMP_ARQ" ] || rm -f "$TMP_ARQ"; rm -rf "$TMP_DIR"; exit "$rc"; }
trap 'limpar $?' EXIT
trap 'exit 1' HUP INT TERM

# O formato da classificação é deliberadamente estreito: somente linhas de tabela
# cujo primeiro campo é um caminho entre crases, dentro das três seções do template.
CLASSIFICACAO="$TMP_DIR/classificacao.tsv"
awk '
  { sub(/\r$/, "") }
  /^##[[:space:]]+OLHO OBRIGAT/ { faixa="alta"; next }
  /^##[[:space:]]+LEITURA R/ { faixa="media"; next }
  /^##[[:space:]]+DISPENS/ { faixa="baixa"; next }
  /^##[[:space:]]/ { faixa=""; next }
  faixa != "" && $0 ~ /^\|[[:space:]]*`[^`]+`[[:space:]]*\|/ {
    linha=$0; sub(/^\|[[:space:]]*`/, "", linha); sub(/`[[:space:]]*\|.*/, "", linha)
    print linha "\t" faixa
  }
' "$ATENCAO_ARQ" > "$CLASSIFICACAO"

[ -s "$CLASSIFICACAO" ] || recusa 'ATENCAO.md não tem arquivos classificados nas três tabelas'
if awk -F '\t' 'seen[$1]++ { exit 1 }' "$CLASSIFICACAO"; then :; else recusa 'arquivo aparece em duas faixas no ATENCAO.md'; fi

# Lê a lista YAML tanto na forma curta quanto na forma com um caminho por linha.
ALTERADOS="$TMP_DIR/alterados"
awk '
  { sub(/\r$/, "") }
  /^arquivos_alterados:[[:space:]]*\[/ {
    s=$0; sub(/^[^\[]*\[/, "", s); sub(/\].*$/, "", s); n=split(s, a, ",")
    for (i=1; i<=n; i++) { gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", a[i]); if (a[i] != "") print a[i] }
    next
  }
  /^arquivos_alterados:[[:space:]]*$/ { dentro=1; next }
  dentro && /^[A-Za-z_][A-Za-z0-9_]*:/ { dentro=0 }
  dentro && /^[[:space:]]*-[[:space:]]*/ { s=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", s); gsub(/^["\047]|["\047]$/, "", s); print s }
' "$ARQ" > "$ALTERADOS"
[ -s "$ALTERADOS" ] || recusa 'ENTREGA.md não declara arquivos_alterados'
while IFS=$'\t' read -r arquivo faixa; do
  grep -Fqx -- "$arquivo" "$ALTERADOS" || recusa "arquivo fora de arquivos_alterados: $arquivo"
done < "$CLASSIFICACAO"

MODO="$(awk '/^entrega:[[:space:]]*/ { sub(/^[^:]*:[[:space:]]*/, ""); sub(/\r$/, ""); print; exit }' "$ARQ")"
case "$MODO" in ''|por_trabalho) MODO=por_trabalho ;; por_sprint) ;; *) recusa 'ENTREGA.md tem entrega diferente de por_trabalho ou por_sprint' ;; esac

NOVAS="$TMP_DIR/novas.tsv"
cp "$CLASSIFICACAO" "$NOVAS"
LISTA="$TMP_DIR/lista.tsv"
if [ "$MODO" = por_sprint ]; then
  ANTIGAS="$TMP_DIR/antigas.tsv"
  awk '
    /^faixa_atencao:[[:space:]]*$/ { dentro=1; next }
    dentro && /^[A-Za-z_][A-Za-z0-9_]*:/ { dentro=0 }
    dentro && /^[[:space:]]*-[[:space:]]+arquivo:[[:space:]]*/ {
      s=$0; sub(/^[[:space:]]*-[[:space:]]+arquivo:[[:space:]]*/, "", s); sub(/\r$/, "", s); arq=s; next
    }
    dentro && arq != "" && /^[[:space:]]+faixa:[[:space:]]*/ {
      s=$0; sub(/^[[:space:]]+faixa:[[:space:]]*/, "", s); sub(/\r$/, "", s); print arq "\t" s; arq=""
    }
  ' "$ARQ" > "$ANTIGAS"
  # o caminho é comparado inteiro: `a.sh` antigo fica mesmo que `src/a.sh` seja novo
  awk -F '\t' 'NR == FNR { novo[$1] = 1; next } !($1 in novo) { print }' "$NOVAS" "$ANTIGAS" >> "$LISTA"
fi
cat "$NOVAS" >> "$LISTA"

OLHO="$(awk -F '\t' '$2 == "alta" { n++ } END { print n+0 }' "$CLASSIFICACAO")"
LEITURA="$(awk -F '\t' '$2 == "media" { n++ } END { print n+0 }' "$CLASSIFICACAO")"
DISPENSAVEL="$(awk -F '\t' '$2 == "baixa" { n++ } END { print n+0 }' "$CLASSIFICACAO")"

FAIXAS='faixa_atencao:'
while IFS=$'\t' read -r arquivo faixa; do
  FAIXAS="$FAIXAS$NL  - arquivo: $arquivo$NL    faixa: $faixa"
done < "$LISTA"
ATENCAO_YAML="atencao:$NL  olho_obrigatorio: $OLHO$NL  leitura_rapida: $LEITURA$NL  dispensavel: $DISPENSAVEL"

[ -r "$RB_SH" ] || ambiente "editor de frontmatter indisponível: $RB_SH"
eval "$(awk '/^(_entrega_fecha|_entrega_troca|entrega_define)\(\) \{/,/^}$/' "$RB_SH")" \
  && declare -F _entrega_troca >/dev/null && declare -F entrega_define >/dev/null \
  || ambiente "editor de frontmatter indisponível: $RB_SH"

HOJE="$(date +%Y-%m-%d)" || ambiente 'data do sistema indisponível'
NOVO="$TMP_DIR/ENTREGA.md"
cp "$ARQ" "$NOVO" || ambiente "não foi possível copiar $ENTREGA"
_entrega_troca "$NOVO" atencao "$ATENCAO_YAML" \
  && _entrega_troca "$NOVO" faixa_atencao "$FAIXAS" \
  && entrega_define "$NOVO" atualizado_em "$HOJE" \
  || recusa "$ENTREGA: $ENTREGA_ERRO; nada foi gravado"

EVENTOS="$RAIZ/docs/eventos"
mkdir -p "$EVENTOS" || ambiente 'não foi possível criar docs/eventos'
EVENTO="$TMP_DIR/evento.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || ambiente 'hora do sistema indisponível'
printf '{"ts":"%s","expx_eventos":1,"trabalho_id":"%s","ferramenta":"mergex","origem":"skill","evento":"veredito_emitido","fase":"e3","task":null,"agente":"revisor-diff","resultado":"ok","detalhe":"%s olho obrigatorio, %s leitura rapida, %s dispensavel","arquivos":[]}\n' \
  "$TS" "$TRABALHO" "$OLHO" "$LEITURA" "$DISPENSAVEL" > "$EVENTO" || ambiente 'não foi possível montar o evento'

TMP_ARQ="$ARQ.atencao.$$"
{ cp -p "$ARQ" "$TMP_ARQ" && cat "$NOVO" > "$TMP_ARQ" && mv "$TMP_ARQ" "$ARQ"; } \
  || { rm -f "$TMP_ARQ"; TMP_ARQ=""; ambiente "não foi possível gravar $ENTREGA; o arquivo não foi alterado"; }
TMP_ARQ=""
cat "$EVENTO" >> "$EVENTOS/$TRABALHO.jsonl" || ambiente 'não foi possível gravar o evento'

printf '%s\n' 'registrado=atencao' "olho_obrigatorio=$OLHO" "leitura_rapida=$LEITURA" "dispensavel=$DISPENSAVEL"
