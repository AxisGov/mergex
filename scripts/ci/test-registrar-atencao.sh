#!/usr/bin/env bash
# Bancada do registro mecânico do veredito E3 (DM-350).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRAR="$REPO/.claude/skills/mergex/scripts/registrar-atencao.sh"
OK=0; FALHOU=0
passa() { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d "$REPO/.tmp.registrar-atencao.XXXXXX")"; trap 'rm -rf "$aux"' EXIT
P=""

projeto() {
  P="$aux/$1"
  mkdir -p "$P/docs/entregas/w"
  git -C "$P" init -q -b main
}

entrega() {
  cat > "$P/docs/entregas/w/ENTREGA.md" <<EOF
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: w
entrega: $1
arquivos_alterados:
  - src/a.sh
  - src/b.sh
  - tests/a.sh
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

roda() { (cd "$P" && bash "$REGISTRAR" --entrega docs/entregas/w/ENTREGA.md > "$aux/out" 2> "$aux/err"); rc=$?; }
mostra() { printf '(rc %s) %s | err: %s' "$rc" "$(tr '\n' '|' < "$aux/out")" "$(tr '\n' '|' < "$aux/err")"; }

echo '== registrar atencao: gravacao e recusas =='

projeto trabalho; entrega por_trabalho '[]'; atencao; roda
grep -q 'olho_obrigatorio: 1' "$P/docs/entregas/w/ENTREGA.md" \
  && grep -q 'arquivo: src/a.sh' "$P/docs/entregas/w/ENTREGA.md" \
  && grep -q 'faixa: alta' "$P/docs/entregas/w/ENTREGA.md" \
  && grep -qx 'registrado=atencao' "$aux/out" \
  && [ "$rc" = 0 ] \
  && passa 'por_trabalho grava contagens e lista inteira' || quebra "por_trabalho: $(mostra)"

projeto sprint; entrega por_sprint $'\n  - arquivo: legado.txt\n    faixa: baixa\n  - arquivo: src/a.sh\n    faixa: baixa'; atencao; roda
grep -q 'arquivo: legado.txt' "$P/docs/entregas/w/ENTREGA.md" \
  && [ "$(grep -c 'arquivo: src/a.sh' "$P/docs/entregas/w/ENTREGA.md")" = 1 ] \
  && awk '/arquivo: src\/a.sh/{f=1; next} f && /faixa: alta/{ok=1} END {exit !ok}' "$P/docs/entregas/w/ENTREGA.md" \
  && [ "$rc" = 0 ] \
  && passa 'por_sprint mescla e substitui pelo caminho' || quebra "por_sprint: $(mostra)"

projeto fora; entrega por_trabalho '[]'; atencao
sed -i 's|`tests/a.sh`|`fora.sh`|' "$P/docs/entregas/w/ATENCAO.md"
cp "$P/docs/entregas/w/ENTREGA.md" "$aux/antes"
roda
[ "$rc" != 0 ] && cmp -s "$aux/antes" "$P/docs/entregas/w/ENTREGA.md" \
  && passa 'caminho fora recusa sem alterar ENTREGA' || quebra "caminho fora: $(mostra)"

projeto duplicado; entrega por_trabalho '[]'; atencao
printf '\n## LEITURA RÁPIDA\n| Arquivo | Mudança |\n|---|---|\n| `src/a.sh` | M |\n' >> "$P/docs/entregas/w/ATENCAO.md"
roda
[ "$rc" != 0 ] && passa 'arquivo em duas faixas recusa' || quebra "duas faixas: $(mostra)"

projeto marcador; entrega por_trabalho '[]'; atencao
printf '\n{{pendente}}\n' >> "$P/docs/entregas/w/ATENCAO.md"
roda
[ "$rc" != 0 ] && passa 'marcador pendente recusa' || quebra "marcador: $(mostra)"

projeto crlf; entrega por_trabalho '[]'; atencao
awk '{printf "%s\\r\\n", $0}' "$P/docs/entregas/w/ENTREGA.md" > "$aux/crlf"
mv "$aux/crlf" "$P/docs/entregas/w/ENTREGA.md"
roda
[ "$rc" = 0 ] && ! grep -q $'[^\r]$' "$P/docs/entregas/w/ENTREGA.md" \
  && passa 'ENTREGA em CRLF permanece em CRLF' || quebra "CRLF: $(mostra)"

projeto evento; entrega por_trabalho '[]'; atencao; roda
evento="$P/docs/eventos/w.jsonl"
[ "$rc" = 0 ] \
  && grep -Fq '"evento":"veredito_emitido"' "$evento" \
  && grep -Fq '"detalhe":"1 olho obrigatorio, 1 leitura rapida, 1 dispensavel"' "$evento" \
  && passa 'evento registra as contagens' || quebra "evento: $(mostra)"

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" = 0 ]
