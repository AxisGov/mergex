#!/usr/bin/env bash
# Bancada do registro mecânico do veredito E3 (DM-350).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRAR="$REPO/.claude/skills/mergex/scripts/registrar-atencao.sh"
OK=0; FALHOU=0
passa() { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d "${TMPDIR:-/tmp}/test-registrar-atencao.XXXXXX")"; trap 'rm -rf "$aux"' EXIT
P=""
g() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# projeto <nome>: main com src/a.sh e src/b.sh; a branch muda os dois e cria tests/a.sh.
# docs/ fica fora dos commits: o diff do E3 é só src/ e tests/.
projeto() {
  P="$aux/$1"
  mkdir -p "$P/src" "$P/tests" "$P/docs/entregas/w"
  git -C "$P" init -q -b main; git -C "$P" config core.autocrlf false
  printf 'a\n' > "$P/src/a.sh"; seq 1 20 > "$P/src/b.sh"
  g -C "$P" add src; g -C "$P" commit -q -m base
  g -C "$P" switch -q -c feature/w
  printf 'a2\n' > "$P/src/a.sh"; seq 1 21 > "$P/src/b.sh"; printf 't\n' > "$P/tests/a.sh"
  g -C "$P" add src tests; g -C "$P" commit -q -m trabalho
}

entrega() {
  cat > "$P/docs/entregas/w/ENTREGA.md" <<EOF
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: w
entrega: $1
branch: feature/w
branch_base: main
arquivos_alterados: ${3:-[]}
faixa_atencao: $2
atencao:
  olho_obrigatorio: 0
  leitura_rapida: 0
  dispensavel: 0
atualizado_em: 2000-01-01
---

# Entrega
EOF
}

atencao() {
  cat > "$P/docs/entregas/w/ATENCAO.md" <<EOF
# Onde gastar atenção

## OLHO OBRIGATÓRIO
| Arquivo | Mudança |
|---|---|
| \`src/a.sh\` | M |

## LEITURA RÁPIDA
| Arquivo | Mudança |
|---|---|
| \`src/b.sh\` | M |

## DISPENSÁVEL
| Arquivo | Mudança |
|---|---|
| \`tests/a.sh\` | A |
EOF
}

E() { printf '%s' "$P/docs/entregas/w/ENTREGA.md"; }
roda() { (cd "$P" && bash "$REGISTRAR" --entrega docs/entregas/w/ENTREGA.md > "$aux/out" 2> "$aux/err"); rc=$?; }
mostra() { printf '(rc %s) %s | err: %s' "$rc" "$(tr '\n' '|' < "$aux/out")" "$(tr '\n' '|' < "$aux/err")"; }
recusa_igual() { cp "$(E)" "$aux/antes"; roda; [ "$rc" != 0 ] && cmp -s "$aux/antes" "$(E)" && grep -q -- "$1" "$aux/err"; }

echo '== registrar atencao: gravacao e recusas =='

projeto trabalho; entrega por_trabalho '[]'; atencao; roda
grep -q 'olho_obrigatorio: 1' "$(E)" \
  && grep -q 'arquivo: src/a.sh' "$(E)" \
  && grep -q 'faixa: alta' "$(E)" \
  && grep -qx 'arquivos_alterados: \[src/a.sh, src/b.sh, tests/a.sh\]' "$(E)" \
  && grep -qx 'registrado=atencao' "$aux/out" \
  && [ "$rc" = 0 ] \
  && passa 'por_trabalho grava contagens, lista inteira e arquivos_alterados do diff' || quebra "por_trabalho: $(mostra)"

projeto sprint
entrega por_sprint $'\n  - arquivo: legado.txt\n    faixa: baixa\n  - arquivo: a.sh\n    faixa: media\n  - arquivo: src/a.sh\n    faixa: baixa' '[a.sh, legado.txt]'
atencao; roda
grep -q 'arquivo: legado.txt' "$(E)" \
  && grep -qx '  - arquivo: a.sh' "$(E)" \
  && [ "$(grep -c 'arquivo: src/a.sh' "$(E)")" = 1 ] \
  && awk '/arquivo: src\/a.sh/{f=1; next} f && /faixa: alta/{ok=1} END {exit !ok}' "$(E)" \
  && grep -qx 'arquivos_alterados: \[a.sh, legado.txt, src/a.sh, src/b.sh, tests/a.sh\]' "$(E)" \
  && [ "$rc" = 0 ] \
  && passa 'por_sprint mescla faixas pelo caminho inteiro e acumula arquivos_alterados' || quebra "por_sprint: $(mostra)"

projeto falta; entrega por_trabalho '[]'; atencao
sed -i '/`tests\/a.sh`/d' "$P/docs/entregas/w/ATENCAO.md"
recusa_igual 'arquivo do diff sem faixa no ATENCAO.md: tests/a.sh' \
  && passa 'arquivo do diff sem faixa recusa sem alterar ENTREGA' || quebra "sem faixa: $(mostra)"

projeto fora; entrega por_trabalho '[]'; atencao
printf '| `fora.sh` | M |\n' >> "$P/docs/entregas/w/ATENCAO.md"
recusa_igual 'arquivo fora do diff main...HEAD: fora.sh' \
  && passa 'caminho fora do diff recusa sem alterar ENTREGA' || quebra "caminho fora: $(mostra)"

projeto duplicado; entrega por_trabalho '[]'; atencao
printf '\n## LEITURA RÁPIDA\n| Arquivo | Mudança |\n|---|---|\n| `src/a.sh` | M |\n' >> "$P/docs/entregas/w/ATENCAO.md"
recusa_igual 'duas faixas' && passa 'arquivo em duas faixas recusa' || quebra "duas faixas: $(mostra)"

projeto marcador; entrega por_trabalho '[]'; atencao
printf '\n{{pendente}}\n' >> "$P/docs/entregas/w/ATENCAO.md"
recusa_igual 'marcador' && passa 'marcador pendente recusa' || quebra "marcador: $(mostra)"

projeto yaml; entrega por_trabalho '[]'; atencao
printf 'x\n' > "$P/src/c: d.sh"; g -C "$P" add src; g -C "$P" commit -q -m c
printf '| `src/c: d.sh` | A |\n' >> "$P/docs/entregas/w/ATENCAO.md"
recusa_igual 'o YAML sem aspas não guarda: src/c: d.sh' \
  && passa 'caminho que o YAML sem aspas não guarda recusa' || quebra "yaml: $(mostra)"

projeto renomeado; entrega por_trabalho '[]'; atencao
g -C "$P" mv src/b.sh src/b2.sh; g -C "$P" commit -q -m ren
sed -i 's|`src/b.sh`|`src/b2.sh`|' "$P/docs/entregas/w/ATENCAO.md"
roda
[ "$rc" = 0 ] && grep -qx 'arquivos_alterados: \[src/a.sh, src/b.sh, src/b2.sh, tests/a.sh\]' "$(E)" \
  && passa 'renomeado: a ponta nova tem faixa e as duas entram em arquivos_alterados' || quebra "renomeado: $(mostra)"

projeto crlf; entrega por_trabalho '[]'; atencao
awk '{printf "%s\r\n", $0}' "$(E)" > "$aux/crlf.tmp"
mv "$aux/crlf.tmp" "$(E)"
roda
[ "$rc" = 0 ] && ! grep -q $'[^\r]$' "$(E)" \
  && passa 'ENTREGA em CRLF permanece em CRLF' || quebra "CRLF: $(mostra)"

projeto evento; entrega por_trabalho '[]'; atencao; roda
evento="$P/docs/eventos/w.jsonl"
[ "$rc" = 0 ] \
  && grep -Fq '"evento":"veredito_emitido"' "$evento" \
  && grep -Fq '"detalhe":"1 olho obrigatorio, 1 leitura rapida, 1 dispensavel"' "$evento" \
  && [ -f "$P/docs/eventos/.gitignore" ] \
  && [ -z "$(git -C "$P" status --porcelain -- docs/eventos)" ] \
  && passa 'evento registra as contagens e o rastro fica ignorado' || quebra "evento: $(mostra)"

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" = 0 ]
