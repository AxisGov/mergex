#!/usr/bin/env bash
#
# Bancada da ordem explícita de `ENTREGA.commits` — a chave `seq`.
#
# `commits` preservava a ordem de registro só pela posição física da lista. A
# posição não tem identidade: não sobrevive a uma reordenação, não distingue
# duas passagens da mesma task e não diz, numa retomada, qual foi o último
# registro. A `seq` dá identidade a essa ordem.
#
# A bancada cobre a leitura única (ordem efetiva por item), a regra do prefixo
# legado, o cálculo do próximo seq, o que PARA o contrato (duplicata, buraco,
# regressão, mistura inválida) e o escritor que o E1 usa.
#
# Sem rede, sem jq, sem git. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-sequencia-commits.sh
#      SEQ=<outro script> bash scripts/ci/test-sequencia-commits.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEQ="${SEQ:-$REPO/.claude/skills/mergex/scripts/sequencia-de-commits.sh}"
PROVA="${PROVA:-$REPO/.claude/skills/mergex/scripts/prova-de-commit.sh}"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

E="$D/ENTREGA.md"

# ---------------------------------------------------------------------------
# Fixture. Cada item é `<seq|->:<task>:<commit>`; `-` é item LEGADO (sem seq).
# Sem item nenhum, a lista nasce `commits: []`, como no E0 de entrega nova.
# ---------------------------------------------------------------------------
entrega() { # <arquivo> <versionado> <item>...
  local arq="$1" versionado="$2" item s t c; shift 2
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-teste\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: %s\n' "$versionado"
    printf 'branch: feature/ft-teste\nbranch_base: main\n'
    if [ "$#" -eq 0 ]; then
      printf 'commits: []\n'
    else
      printf 'commits:\n'
      for item in "$@"; do
        s="${item%%:*}"; t="${item#*:}"; c="${t#*:}"; t="${t%%:*}"
        [ "$s" = - ] || printf -- '  - seq: %s\n    task: %s\n    commit: %s\n' "$s" "$t" "$c"
        [ "$s" = - ] && printf -- '  - task: %s\n    commit: %s\n' "$t" "$c"
      done
    fi
    printf 'modulo_afetado: []\narquivos_alterados: []\nfaixa_atencao: []\nraio: null\n'
    printf 'atencao:\n  olho_obrigatorio: 0\n  leitura_rapida: 0\n  dispensavel: 0\n'
    printf 'portao: null\nfalhas_portao: []\ncausa: null\ndesvios: []\n'
    printf 'push_feito: false\npr_url: null\npr_estado: null\n'
    printf 'criado_em: 2026-09-20\natualizado_em: 2026-09-20\nentregue_em: null\n'
    printf -- '---\n\n# Entrega\n\nProsa da entrega.\n'
  } > "$arq"
}

valido()   { # <descrição> <item>...
  local desc="$1"; shift
  entrega "$E" true "$@"
  if bash "$SEQ" --validar "$E" >/dev/null 2>&1; then ok "$desc → válida"
  else falha "$desc — recusada: $(bash "$SEQ" --validar "$E" 2>&1)"; fi
}

invalido() { # <descrição> <item>...
  local desc="$1" saida rc; shift
  entrega "$E" true "$@"
  saida="$(bash "$SEQ" --validar "$E" 2>&1)"; rc=$?
  if [ "$rc" = 1 ]; then ok "$desc → PARA ($(printf '%s' "$saida" | head -1))"
  else falha "$desc — não parou (código $rc): $saida"; fi
}

proximo() { # <esperado> <descrição> <item>...
  local esperado="$1" desc="$2" obtido; shift 2
  entrega "$E" true "$@"
  obtido="$(bash "$SEQ" --proximo "$E" 2>&1)"
  if [ "$obtido" = "$esperado" ]; then ok "$desc → próximo = $esperado"
  else falha "$desc — próximo deu '$obtido', esperava '$esperado'"; fi
}

# ---------------------------------------------------------------------------
echo "1-2. Lista moderna: o próximo seq é o maior efetivo + 1"
# ---------------------------------------------------------------------------
proximo 1 "caso 1 — ENTREGA nova, commits: []"
valido   "caso 1 — commits: [] é lista válida"
proximo 2 "caso 2 — com seq 1 existente" 1:T-01.01:a3f19c2
valido   "caso 2 — seq 1 sozinho" 1:T-01.01:a3f19c2
proximo 4 "três itens modernos em sequência" 1:T-01.01:a3f19c2 2:T-01.02:7b2e401 3:T-01.03:5be75d3

# ---------------------------------------------------------------------------
echo
echo "3-4, 9. Prefixo legado: ordem efetiva pela posição, sem migrar nada"
# ---------------------------------------------------------------------------
proximo 3 "caso 3 — dois itens legados" -:T-01.01:aaa1111 -:T-01.02:bbb2222
valido   "caso 3 — lista totalmente legada" -:T-01.01:aaa1111 -:T-01.02:bbb2222
proximo 4 "caso 4 — dois legados e o seq 3" -:T-01.01:aaa1111 -:T-01.02:bbb2222 3:T-01.03:ccc3333
valido   "caso 9 — prefixo legado seguido de seq correto" \
  -:T-01.01:aaa1111 -:T-01.02:bbb2222 3:T-01.03:ccc3333 4:T-01.04:ddd4444
proximo 5 "caso 9 — próximo depois do prefixo legado" \
  -:T-01.01:aaa1111 -:T-01.02:bbb2222 3:T-01.03:ccc3333 4:T-01.04:ddd4444
proximo 2 "um único item legado" -:T-01.01:aaa1111

# ---------------------------------------------------------------------------
echo
echo "5-8, 10, 13. O que PARA o contrato"
# ---------------------------------------------------------------------------
invalido "caso 5 — seq duplicado"  1:T-01.01:aaa1111 1:T-01.02:bbb2222
invalido "caso 5 — duplicado adiante" 1:T-01.01:aaa1111 2:T-01.02:bbb2222 2:T-01.03:ccc3333
invalido "caso 6 — buraco (1, 3)"  1:T-01.01:aaa1111 3:T-01.02:bbb2222
invalido "caso 7 — regressão (1, 3, 2)" 1:T-01.01:aaa1111 3:T-01.02:bbb2222 2:T-01.03:ccc3333
invalido "caso 8 — item sem seq depois de item tipado" 1:T-01.01:aaa1111 -:T-01.02:bbb2222
invalido "caso 8 — legado ensanduichado" -:T-01.01:aaa1111 2:T-01.02:bbb2222 -:T-01.03:ccc3333
invalido "caso 10 — prefixo legado seguido de seq errado" \
  -:T-01.01:aaa1111 -:T-01.02:bbb2222 4:T-01.03:ccc3333
invalido "caso 10 — o primeiro moderno volta a 1 depois do prefixo legado" \
  -:T-01.01:aaa1111 -:T-01.02:bbb2222 1:T-01.03:ccc3333
invalido "caso 13 — dois modernos com a ordem física trocada" \
  2:T-01.02:bbb2222 1:T-01.01:aaa1111
invalido "a lista não começa em 1" 2:T-01.01:aaa1111
invalido "seq zero não é positivo"  0:T-01.01:aaa1111
invalido "seq negativo não é positivo" -1:T-01.01:aaa1111

entrega "$E" true 1:T-01.01:aaa1111
sed 's/^  - seq: 1$/  - seq: dois/' "$E" > "$E.x" && mv "$E.x" "$E"
bash "$SEQ" --validar "$E" >/dev/null 2>&1 \
  && falha "seq não numérico foi aceito" || ok "seq não numérico → PARA"
entrega "$E" true 1:T-01.01:aaa1111
sed 's/^  - seq: 1$/  - seq: {{n}}/' "$E" > "$E.x" && mv "$E.x" "$E"
bash "$SEQ" --validar "$E" >/dev/null 2>&1 \
  && falha "marcador de template em seq foi aceito" || ok "marcador de template em seq → PARA"

# O contrato inválido PARA; ele nunca é consertado escolhendo outro número.
entrega "$E" true 1:T-01.01:aaa1111 1:T-01.02:bbb2222
bash "$SEQ" --proximo "$E" >/dev/null 2>&1 \
  && falha "--proximo calculou sobre lista inválida" \
  || ok "--proximo não devolve número sobre lista inválida"
antes="$(cat "$E")"
bash "$SEQ" --acrescentar "$E" T-01.03 ccc3333 >/dev/null 2>&1
[ "$(cat "$E")" = "$antes" ] \
  && ok "--acrescentar não toca a ENTREGA com sequência inválida" \
  || falha "--acrescentar gravou sobre lista inválida"

# ---------------------------------------------------------------------------
echo
echo "11. A mesma task pode aparecer mais de uma vez, com seq diferentes"
# ---------------------------------------------------------------------------
valido "caso 11 — T-04.03 em seq 2 e em seq 7" \
  1:T-04.01:aaa1111 2:T-04.03:bbb2222 3:T-04.02:ccc3333 4:T-04.04:ddd4444 \
  5:T-04.05:eee5555 6:T-04.06:fff6666 7:T-04.03:9f3c1aa
proximo 8 "caso 11 — a repetição não altera o próximo" \
  1:T-04.01:aaa1111 2:T-04.03:bbb2222 3:T-04.02:ccc3333 4:T-04.04:ddd4444 \
  5:T-04.05:eee5555 6:T-04.06:fff6666 7:T-04.03:9f3c1aa
invalido "a mesma task não autoriza reusar o seq" \
  1:T-04.03:aaa1111 1:T-04.03:bbb2222

# ---------------------------------------------------------------------------
echo
echo "16. versionado: false — commits: [] continua válida"
# ---------------------------------------------------------------------------
entrega "$E" false
bash "$SEQ" --validar "$E" >/dev/null 2>&1 \
  && ok "caso 16 — versionado: false com commits: [] é válida" \
  || falha "caso 16 — recusada: $(bash "$SEQ" --validar "$E" 2>&1)"

# ---------------------------------------------------------------------------
echo
echo "Leitura única: ordem efetiva, seq, task e commit por item"
# ---------------------------------------------------------------------------
entrega "$E" true -:T-01.01:aaa1111 -:T-01.02:bbb2222 3:T-01.03:ccc3333
esperado='1	1	T-01.01	aaa1111
2	2	T-01.02	bbb2222
3	3	T-01.03	ccc3333'
obtido="$(bash "$SEQ" --ler "$E" 2>&1)"
[ "$obtido" = "$esperado" ] \
  && ok "a leitura devolve ordem efetiva, seq, task e commit da lista mista" \
  || falha "leitura mista deu:
$obtido"

entrega "$E" true
[ -z "$(bash "$SEQ" --ler "$E" 2>&1)" ] \
  && ok "commits: [] não devolve item nenhum" || falha "commits: [] devolveu item"

entrega "$E" true 1:T-01.01:aaa1111
a="$(bash "$SEQ" --ler "$E")"; b="$(bash "$SEQ" --ler "$E")"
[ "$a" = "$b" ] && ok "duas leituras da mesma evidência dão o mesmo resultado" \
  || falha "leitura instável"

printf 'sem frontmatter\n' > "$D/solto.md"
bash "$SEQ" --ler "$D/solto.md" >/dev/null 2>&1 \
  && falha "arquivo sem frontmatter foi lido" || ok "arquivo sem frontmatter → erro"
bash "$SEQ" --ler "$D/nao-existe.md" >/dev/null 2>&1 \
  && falha "arquivo inexistente foi lido" || ok "arquivo inexistente → erro"

# ---------------------------------------------------------------------------
echo
echo "12, 14, 15. O escritor: acrescenta no fim, com seq, e não migra o passado"
# ---------------------------------------------------------------------------
entrega "$E" true
bash "$SEQ" --acrescentar "$E" T-01.01 a3f19c2 >/dev/null 2>&1
[ "$(bash "$SEQ" --ler "$E")" = '1	1	T-01.01	a3f19c2' ] \
  && ok "caso 1 — o primeiro append numa ENTREGA vazia grava seq 1" \
  || falha "primeiro append: $(bash "$SEQ" --ler "$E" 2>&1)"
grep -Fq '  - seq: 1' "$E" && ok "caso 15 — o item gravado traz seq explícito" \
  || falha "caso 15 — item gravado sem seq"
grep -Fq 'commits: []' "$E" && falha "a lista vazia sobreviveu ao append" \
  || ok "commits: [] virou lista de itens"

bash "$SEQ" --acrescentar "$E" T-01.02 7b2e401 >/dev/null 2>&1
[ "$(bash "$SEQ" --proximo "$E")" = 3 ] && ok "caso 2 — dois appends seguidos: próximo = 3" \
  || falha "dois appends: próximo = $(bash "$SEQ" --proximo "$E" 2>&1)"
bash "$SEQ" --validar "$E" >/dev/null 2>&1 && ok "a lista escrita pelo helper é válida" \
  || falha "o helper escreveu lista inválida: $(bash "$SEQ" --validar "$E" 2>&1)"

# Caso 14 — backfill: o prefixo legado sai do append EXATAMENTE como entrou.
entrega "$E" true -:T-01.01:aaa1111 -:T-01.02:bbb2222
legado_antes="$(grep -n -A2 -- '- task: T-01.01' "$E")"
bash "$SEQ" --acrescentar "$E" T-01.03 ccc3333 >/dev/null 2>&1
[ "$(grep -n -A2 -- '- task: T-01.01' "$E")" = "$legado_antes" ] \
  && ok "caso 14 — o helper não faz backfill do item legado" \
  || falha "caso 14 — o item legado foi reescrito"
grep -Fq '  - seq: 3' "$E" && ok "caso 3 — o primeiro moderno depois do prefixo legado é seq 3" \
  || falha "caso 3 — o append não gravou seq 3: $(bash "$SEQ" --ler "$E" 2>&1)"
[ "$(bash "$SEQ" --ler "$E" | tail -1)" = '3	3	T-01.03	ccc3333' ] \
  && ok "o item novo entrou no FIM da lista" || falha "o item novo não entrou no fim"

# Caso 12 — E1 tardio: recebe o próximo seq e não reordena o que já existe.
entrega "$E" true 1:T-01.01:aaa1111 2:T-01.03:bbb2222
bash "$SEQ" --acrescentar "$E" T-01.02 ccc3333 >/dev/null 2>&1
esperado='1	1	T-01.01	aaa1111
2	2	T-01.03	bbb2222
3	3	T-01.02	ccc3333'
[ "$(bash "$SEQ" --ler "$E")" = "$esperado" ] \
  && ok "caso 12 — o E1 tardio recebe o próximo seq, no fim, sem reordenar" \
  || falha "caso 12 — E1 tardio deu:
$(bash "$SEQ" --ler "$E")"

# O seq é GLOBAL, nunca por task: a segunda passagem da mesma task continua a série.
entrega "$E" true 1:T-04.03:aaa1111 2:T-04.04:bbb2222
bash "$SEQ" --acrescentar "$E" T-04.03 ccc3333 >/dev/null 2>&1
[ "$(bash "$SEQ" --ler "$E" | tail -1)" = '3	3	T-04.03	ccc3333' ] \
  && ok "o seq é global à ENTREGA, nunca contado por task" \
  || falha "seq por task: $(bash "$SEQ" --ler "$E" | tail -1)"

# O escritor recusa o que não é prova, em vez de gravar item pela metade.
entrega "$E" true
for sha in '' 'TODO' '{{identificador curto}}' 'zzzzzzz' 'a3f19'; do
  antes="$(cat "$E")"
  bash "$SEQ" --acrescentar "$E" T-01.01 "$sha" >/dev/null 2>&1
  [ "$(cat "$E")" = "$antes" ] && ok "o escritor recusa commit '${sha:-<vazio>}'" \
    || falha "o escritor gravou commit inválido '${sha:-<vazio>}'"
done
antes="$(cat "$E")"
bash "$SEQ" --acrescentar "$E" '' a3f19c2 >/dev/null 2>&1
[ "$(cat "$E")" = "$antes" ] && ok "o escritor recusa item sem task" \
  || falha "o escritor gravou item sem task"

# A prosa e o resto do frontmatter sobrevivem ao append.
entrega "$E" true 1:T-01.01:aaa1111
bash "$SEQ" --acrescentar "$E" T-01.02 7b2e401 >/dev/null 2>&1
n=0
grep -Fq 'kind: entrega' "$E"        || n=1
grep -Fq 'falhas_portao: []' "$E"    || n=1
grep -Fq 'entregue_em: null' "$E"    || n=1
grep -Fq 'Prosa da entrega.' "$E"    || n=1
[ "$(grep -c -- '^---$' "$E")" = 2 ] || n=1
[ "$n" = 0 ] && ok "o append preserva o resto do frontmatter e a prosa" \
  || falha "o append danificou o arquivo"

# ---------------------------------------------------------------------------
echo
echo "RETOMADA — o próximo seq sai da ENTREGA, não da memória da sessão"
# ---------------------------------------------------------------------------
entrega "$E" true
bash "$SEQ" --acrescentar "$E" T-01.01 aaa1111 >/dev/null 2>&1
bash "$SEQ" --acrescentar "$E" T-01.02 bbb2222 >/dev/null 2>&1
# A sessão encerra: nada além do arquivo sobrevive. A sessão nova lê o arquivo.
copia="$D/retomada.md"; cp "$E" "$copia"
[ "$(bash "$SEQ" --proximo "$copia")" = 3 ] \
  && ok "sessão nova lê a ENTREGA e obtém exatamente max efetivo + 1" \
  || falha "retomada: próximo = $(bash "$SEQ" --proximo "$copia" 2>&1)"
bash "$SEQ" --acrescentar "$copia" T-01.03 ccc3333 >/dev/null 2>&1
[ "$(bash "$SEQ" --ler "$copia" | tail -1)" = '3	3	T-01.03	ccc3333' ] \
  && ok "o E1 da sessão nova continua a série sem repetir seq" \
  || falha "retomada gravou $(bash "$SEQ" --ler "$copia" | tail -1)"
# Nenhuma data e nenhum rastro entram no cálculo: só a lista decide.
entrega "$E" true 1:T-01.01:aaa1111 2:T-01.02:bbb2222
sed 's/^atualizado_em: .*/atualizado_em: 2020-01-01/; s/^criado_em: .*/criado_em: 2030-12-31/' "$E" > "$E.x" && mv "$E.x" "$E"
[ "$(bash "$SEQ" --proximo "$E")" = 3 ] \
  && ok "as datas do registro não entram no cálculo do próximo seq" \
  || falha "a data mudou o próximo seq"

# ---------------------------------------------------------------------------
echo
echo "V11 — a ordem não é assunto dela (regressão)"
# ---------------------------------------------------------------------------
planinho() { # <arquivo> <id:status>...
  local arq="$1" par; shift
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: plano\ntrabalho_id: ft-teste\n'
    printf 'tasks:\n'
    for par in "$@"; do
      printf -- '  - id: %s\n    status: %s\n    suite: verde\n' "${par%%:*}" "${par##*:}"
      printf '    teste_integracao: integra\n    teste_funcional: funciona\n'
    done
    printf -- '---\n\n# Plano\n'
  } > "$arq"
}
T="$D/tasks.md"
v11() { # <esperado> <descrição> <item>...
  local esperado="$1" desc="$2" obtido; shift 2
  entrega "$E" true "$@"
  obtido="$(bash "$PROVA" --verificar "$E" "$T" 2>&1 | head -1)"
  [ "$obtido" = "V11=$esperado" ] && ok "$desc → $esperado" \
    || falha "$desc — obteve '$obtido', esperava 'V11=$esperado'"
}
planinho "$T" T-01.01:concluida
v11 OK    "V11 com item legado válido"  -:T-01.01:a3f19c2
v11 OK    "V11 com item moderno válido" 1:T-01.01:a3f19c2
v11 OK    "V11 com lista mista válida"  -:T-02.09:aaa1111 2:T-01.01:a3f19c2
v11 FALHA "V11 com task correta e commit inválido" 1:T-01.01:zzzzzzz
planinho "$T" T-04.03:concluida
v11 OK    "V11 com a mesma task em seq 2 e seq 7" \
  1:T-04.01:aaa1111 2:T-04.03:bbb2222 3:T-04.02:ccc3333 4:T-04.04:ddd4444 \
  5:T-04.05:eee5555 6:T-04.06:fff6666 7:T-04.03:9f3c1aa
planinho "$T" T-01.01:concluida
# Sequência quebrada é contrato inválido, não assunto do portão: a V11 responde
# a pergunta dela e não passa a exigir seq nem ordem.
v11 OK    "V11 não regride com seq fora de sequência (é contrato, não portão)" \
  1:T-01.01:a3f19c2 3:T-01.02:7b2e401
v11 OK    "V11 não exige seq em leitura histórica" -:T-01.01:a3f19c2
v11 OK    "V11 não lê seq como quantidade de commits da task" 9:T-01.01:a3f19c2

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
