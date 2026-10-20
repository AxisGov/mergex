#!/usr/bin/env bash
# entrega-de-planejamento — diz se a entrega atual é a do PR de planejamento.
#
# Contrato: references/00-schema.md, "A entrega de planejamento"; DM-259.
# É o ÚNICO leitor de `sprint_atual` e `prs` na mergex: E2, E7, E8 e E9
# perguntam a ele, ninguém relê o YAML por conta própria.
#
# Uso:
#   entrega-de-planejamento.sh --entrega <ENTREGA.md> [--rev <commit>]
#
# Com --rev, lê o frontmatter da versão commitada (`git show <rev>:./<caminho>`,
# caminho relativo ao diretório atual), nunca o do disco.
#
# A marca (as duas, coerentes):
#   sprint_atual: planejamento
#   prs:                       (YAML de bloco; a forma em fluxo `[{...}]` é ilegível)
#     - sprint: planejamento   (sempre o PRIMEIRO item)
#       url: <url | null>
#       estado: <aberto | rascunho | aguardando_merge | merged | fechado | null>
#       merge_sha: <sha | null>  (sha só com estado merged)
#       merge: <humano | null>   (`automatico` nunca: o planejamento é do desenvolvedor)
#
# Saída (stdout):
#   planejamento=nao
# ou
#   planejamento=sim
#   estado=<prs[0].estado>      (nulo sai como o texto `null`)
#   merge_sha=<prs[0].merge_sha>
#
# Entrega sem `sprint_atual` nem `prs` (anterior às chaves) é `nao`. Depois da
# retomada do E0 (`sprint_atual: null` com o planejamento `merged`) também.
#
# Códigos: 0 leu; 2 ilegível ou incoerente (motivo em stderr); 64 uso.
#
# Bash 3.2 (macOS): nada de mapfile, arrays associativos ou ${v,,}.

set -uo pipefail

uso() {
  [ -z "${1:-}" ] || printf 'entrega-de-planejamento: %s\n' "$1" >&2
  printf '%s\n' 'uso: entrega-de-planejamento.sh --entrega <ENTREGA.md> [--rev <commit>]' >&2
  exit 64
}
ilegivel() { printf 'entrega-de-planejamento: %s\n' "$1" >&2; exit 2; }

ENTREGA=""; REV=""; TEM_REV=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --entrega) [ "$#" -ge 2 ] && [ -z "$ENTREGA" ] || uso; ENTREGA="$2"; shift 2 ;;
    --rev) [ "$#" -ge 2 ] && [ "$TEM_REV" = 0 ] || uso; REV="$2"; TEM_REV=1; shift 2 ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done
[ -n "$ENTREGA" ] || uso 'falta --entrega'
[ "$TEM_REV" = 0 ] || [ -n "$REV" ] || uso '--rev vazio'

if [ "$TEM_REV" = 1 ]; then
  case "$ENTREGA" in /*|?:*) ilegivel "--rev exige caminho relativo: $ENTREGA" ;; esac
  conteudo="$(git show "${REV}:./${ENTREGA#./}" 2>/dev/null)" \
    || ilegivel "não há $ENTREGA em $REV"
else
  [ -f "$ENTREGA" ] && [ -r "$ENTREGA" ] || ilegivel "arquivo ilegível: $ENTREGA"
  conteudo="$(cat "$ENTREGA")"
fi

# Uma linha por fato, com o motivo da ilegibilidade quando houver:
#   S<TAB><sprint_atual>          (ausente: sem a linha)
#   P<TAB><inline de prs:>        (ausente: sem a linha)
#   I<TAB>pos<TAB>sprint<TAB>url<TAB>estado<TAB>merge_sha<TAB>merge
#   E<TAB><motivo>
fatos="$(printf '%s\n' "$conteudo" | awk -v q="'" '
  function limpa(v,   a, z) {
    sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
    a = substr(v, 1, 1); z = substr(v, length(v))
    if (length(v) >= 2 && a == z && (a == "\"" || a == q)) v = substr(v, 2, length(v) - 2)
    return v
  }
  function emite() {
    if (!aberto) return
    aberto = 0
    if (!("sprint" in c) || !("url" in c) || !("estado" in c) || !("merge_sha" in c) || !("merge" in c)) {
      if (erro == "") erro = "item " n " de prs sem as cinco chaves (sprint, url, estado, merge_sha, merge)"
      return
    }
    printf "I\t%d\t%s\t%s\t%s\t%s\t%s\n", n, c["sprint"], c["url"], c["estado"], c["merge_sha"], c["merge"]
  }
  function campo(l,   k, v) {
    if (l !~ /^[a-z_]+:/) { erro = "linha de prs fora da forma chave: valor: " l; return }
    k = l; sub(/:.*/, "", k)
    v = l; sub(/^[^:]*:/, "", v); v = limpa(v)
    if (k != "sprint" && k != "url" && k != "estado" && k != "merge_sha" && k != "merge") {
      erro = "chave desconhecida num item de prs: " k; return
    }
    if (k in c) { erro = "chave repetida num item de prs: " k; return }
    if (v == "" || v == "~") v = "null"
    c[k] = v
  }
  { sub(/\r$/, "") }
  NR == 1 { if ($0 !~ /^---[[:space:]]*$/) { erro = "o arquivo não começa com frontmatter"; exit }; fm = 1; next }
  /^---[[:space:]]*$/ { fechado = 1; exit }
  /^[A-Za-z_][A-Za-z0-9_]*:/ {
    if (dentro) { emite(); if (erro != "") exit }
    dentro = 0
    nome = $0; sub(/:.*/, "", nome)
    v = $0; sub(/^[^:]*:/, "", v); v = limpa(v)
    if (nome == "sprint_atual") { if (vs) { erro = "sprint_atual repetida"; exit }; vs = 1; printf "S\t%s\n", (v == "" || v == "~") ? "null" : v }
    if (nome == "prs") { if (vp) { erro = "prs repetida"; exit }; vp = 1; dentro = 1; printf "P\t%s\n", v }
    next
  }
  !dentro { next }
  /^[[:space:]]*$/ { next }
  /^[[:space:]]+-[[:space:]]/ || /^[[:space:]]+-$/ {
    emite(); if (erro != "") exit
    n++; aberto = 1; split("", c)
    l = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", l)
    if (l != "") campo(l)
    if (erro != "") exit
    next
  }
  /^[[:space:]]+[a-z_]+:/ {
    if (!aberto) { erro = "campo de prs fora de um item"; exit }
    l = $0; sub(/^[[:space:]]+/, "", l); campo(l)
    if (erro != "") exit
    next
  }
  { erro = "linha de prs fora da forma de bloco: " $0; exit }
  END {
    if (erro == "" && fm && !fechado) erro = "o frontmatter não foi fechado"
    if (erro == "" && dentro) emite()
    if (erro != "") printf "E\t%s\n", erro
  }
')"

erro="$(printf '%s\n' "$fatos" | awk -F'\t' '$1 == "E" { print $2; exit }')"
[ -z "$erro" ] || ilegivel "$erro"

tem_s=0; sprint=""; tem_p=0; inline=""
linha_s="$(printf '%s\n' "$fatos" | grep '^S	' || true)"
linha_p="$(printf '%s\n' "$fatos" | grep '^P	' || true)"
[ -z "$linha_s" ] || { tem_s=1; sprint="${linha_s#S	}"; }
[ -z "$linha_p" ] || { tem_p=1; inline="${linha_p#P	}"; }
itens="$(printf '%s\n' "$fatos" | grep '^I	' || true)"

case "$inline" in
  '') ;;
  '[]') [ -z "$itens" ] || ilegivel 'prs: [] com itens abaixo' ;;
  *) ilegivel "prs fora da forma de bloco (a forma em fluxo é ilegível): $inline" ;;
esac
[ "$tem_p" = 0 ] || [ -n "$inline" ] || [ -n "$itens" ] || ilegivel 'prs sem itens: use prs: []'

case "$sprint" in ''|null|planejamento) ;; *) ilegivel "sprint_atual fora do enum: $sprint" ;; esac

sha_ok() {
  case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -ge 7 ] && [ "${#1}" -le 40 ]
}

# Todo item: enums; o de planejamento só na primeira posição.
p_sprint=""; p_estado=""; p_sha=""; p_merge=""
TAB='	'
while IFS="$TAB" read -r _ pos s_item _url estado sha merge; do
  [ -n "$pos" ] || continue
  case "$estado" in aberto|rascunho|aguardando_merge|merged|fechado|null) ;;
    *) ilegivel "estado fora do enum no item $pos de prs: $estado" ;; esac
  case "$merge" in humano|automatico|null) ;;
    *) ilegivel "merge fora do enum no item $pos de prs: $merge" ;; esac
  case "$s_item" in
    planejamento) [ "$pos" = 1 ] || ilegivel "o item de planejamento está na posição $pos de prs (só a primeira)" ;;
    [0-9][0-9]) ;;
    *) ilegivel "sprint fora da forma no item $pos de prs: $s_item" ;;
  esac
  if [ "$estado" = merged ]; then
    sha_ok "$sha" || ilegivel "item $pos de prs merged sem merge_sha válido: $sha"
  else
    [ "$sha" = null ] || ilegivel "item $pos de prs com merge_sha sem estar merged"
  fi
  if [ "$pos" = 1 ]; then p_sprint="$s_item"; p_estado="$estado"; p_sha="$sha"; p_merge="$merge"; fi
done <<EOF
$itens
EOF

if [ "$p_sprint" = planejamento ]; then
  [ "$p_merge" != automatico ] || ilegivel 'o PR de planejamento nunca tem merge automático (merge: automatico)'
  case "$sprint" in
    planejamento) printf 'planejamento=sim\nestado=%s\nmerge_sha=%s\n' "$p_estado" "$p_sha"; exit 0 ;;
    null) [ "$p_estado" = merged ] \
            || ilegivel 'sprint_atual: null com o planejamento ainda não merged em prs'
          printf 'planejamento=nao\n'; exit 0 ;;
    *) ilegivel 'prs começa pelo planejamento sem sprint_atual' ;;
  esac
fi
[ "$sprint" != planejamento ] || ilegivel 'sprint_atual: planejamento sem o item de planejamento no início de prs'
printf 'planejamento=nao\n'
