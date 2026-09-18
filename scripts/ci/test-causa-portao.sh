#!/usr/bin/env bash
#
# Bancada da causa do bloqueio — `falhas_portao` e `causa` no ENTREGA.md.
#
# Confere a derivação (uma causa por verificação, precedência, `indeterminada`
# quando a verificação que decidiria não pôde rodar) e o validador do schema
# (chave sempre presente, enum fechado, coerência com estado e portão, leitura
# de ENTREGA anterior às chaves). Reproduz o bloqueio do piloto (V1 + V7) num
# repositório temporário e lê a causa por `git show`, como a buildx lê.
#
# Sem rede, sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-causa-portao.sh
#      CAUSA=<outro script> bash scripts/ci/test-causa-portao.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAUSA="${CAUSA:-$REPO/.claude/skills/mergex/scripts/causa-do-portao.sh}"
FIXTURES="$REPO/scripts/ci/fixtures/e2e-p0-2"

OK=0; FALHOU=0
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT
D="$(mktemp -d)"; TMPS="$TMPS $D"

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# deriva <esperado> <descrição> <falhas...>
deriva() {
  local esperado="$1" desc="$2" obtido; shift 2
  obtido="$(bash "$CAUSA" --derivar "$@" 2>/dev/null)"
  if [ "$obtido" = "$esperado" ]; then ok "$desc → $esperado"
  else falha "$desc — obteve '${obtido}', esperava '$esperado'"; fi
}

# recusa_derivar <descrição> <falhas...>
recusa_derivar() {
  local desc="$1"; shift
  if bash "$CAUSA" --derivar "$@" >/dev/null 2>&1; then falha "$desc — a derivação aceitou"
  else ok "$desc — recusado"; fi
}

# entrega <arquivo> <estado> <portao> <falhas_portao|-> <causa|-> — `-` omite a chave
entrega() {
  local arq="$1" estado="$2" portao="$3" falhas="$4" causa="$5"
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-teste\n'
    printf 'entregue_por: mergex\nestado: %s\nversionado: true\nbranch: feature/ft-teste\n' "$estado"
    printf 'commits: []\narquivos_alterados: []\nportao: %s\n' "$portao"
    [ "$falhas" = - ] || printf 'falhas_portao: %s\n' "$falhas"
    [ "$causa" = - ]  || printf 'causa: %s\n' "$causa"
    printf 'desvios: []\npush_feito: false\npr_url: null\n---\n\n# Entrega\n'
  } > "$arq"
}

# aceita <modo> <descrição> <arquivo> <saída esperada>
aceita() {
  local modo="$1" desc="$2" arq="$3" esperado="$4" obtido
  if obtido="$(bash "$CAUSA" "$modo" "$arq" 2>&1)" && [ "$obtido" = "$esperado" ]; then ok "$desc ($obtido)"
  else falha "$desc — '$obtido', esperava aceitar com '$esperado'"; fi
}

# reprova <modo> <descrição> <arquivo> <trecho do motivo>
reprova() {
  local modo="$1" desc="$2" arq="$3" trecho="$4" obtido
  if obtido="$(bash "$CAUSA" "$modo" "$arq" 2>&1)"; then
    falha "$desc — aceitou ($obtido)"; return
  fi
  case "$obtido" in
    *"$trecho"*) ok "$desc — reprovado: ${obtido#causa-do-portao: }" ;;
    *) falha "$desc — reprovou pelo motivo errado: '$obtido' (esperava '$trecho')" ;;
  esac
}

E="$D/ENTREGA.md"

# ---------------------------------------------------------------------------
echo "1. ENTREGA aberta: causa null"
# ---------------------------------------------------------------------------
entrega "$E" aberto null '[]' null;              aceita --validar "E0: aberto, portão não rodou" "$E" 'causa=null'
entrega "$E" aberto pronto '[]' null;            aceita --validar "aberto depois do E2 PRONTO" "$E" 'causa=null'
entrega "$E" aberto bloqueado '[v1, v7]' null;   aceita --validar "aberto depois do E2 BLOQUEADO, antes do E8" "$E" 'causa=null'
entrega "$E" aberto null '[]' bloqueio_aberto;   reprova --validar "aberto com causa" "$E" 'estado aberto exige causa: null'
entrega "$E" aberto null '[v7]' null;            reprova --validar "portão não rodou, mas com falhas" "$E" 'portao null com falhas'

# ---------------------------------------------------------------------------
echo
echo "2. ENTREGA pronta/entregue: causa null"
# ---------------------------------------------------------------------------
entrega "$E" entregue pronto '[]' null;              aceita --validar "entregue com portão pronto" "$E" 'causa=null'
entrega "$E" entregue pronto '[]' tarefa_nao_concluida; reprova --validar "entregue com causa" "$E" 'estado entregue exige causa: null'
entrega "$E" entregue pronto '[v9]' null;            reprova --validar "pronto com falha registrada" "$E" 'portao pronto com falhas'
entrega "$E" entregue bloqueado '[v9]' null;         reprova --validar "entregue com portão bloqueado" "$E" 'estado entregue exige portao: pronto'

# ---------------------------------------------------------------------------
echo
echo "3. Bloqueio por uma causa canônica: uma causa por verificação"
# ---------------------------------------------------------------------------
deriva tarefa_nao_concluida    "V1 sozinha"  v1
deriva suite_reprovada         "V2 sozinha"  v2
deriva teste_nao_declarado     "V3 sozinha"  v3
deriva regressao_nao_declarada "V4 sozinha"  v4
deriva qa_nao_aprovado         "V5 sozinha"  v5
deriva auditoria_reprovada     "V6 sozinha"  v6
deriva bloqueio_aberto         "V7 sozinha"  v7
deriva legado_incompleto       "V8 sozinha"  v8
deriva arquivo_fora_do_plano   "V9 sozinha"  v9
deriva segredo_no_diff         "V10 sozinha" v10
entrega "$E" bloqueado bloqueado '[v9]' arquivo_fora_do_plano; aceita --validar "bloqueado por V9" "$E" 'causa=arquivo_fora_do_plano'
entrega "$E" bloqueado bloqueado '[v9]' tarefa_nao_concluida;  reprova --validar "causa do enum, mas não a derivada" "$E" "não é a derivada"

# ---------------------------------------------------------------------------
echo
echo "4. Várias falhas: precedência V10; V6..V9; V1..V5"
# ---------------------------------------------------------------------------
[ "$(bash "$CAUSA" --ordem)" = 'v10 v6 v7 v8 v9 v1 v2 v3 v4 v5' ] && ok "ordem declarada" || falha "ordem alterada: $(bash "$CAUSA" --ordem)"
deriva bloqueio_aberto       "V1 + V7: task bloqueada é sintoma do B-NN" v1 v7
deriva tarefa_nao_concluida  "V1 + V5: QA ausente é sintoma da execução" v1 v5
deriva tarefa_nao_concluida  "V1 + V2 + V3" v1 v2 v3
deriva suite_reprovada       "V2 + V4 + V5" v2 v4 v5
deriva auditoria_reprovada   "V6 + V7: plano volta à F3" v6 v7
deriva bloqueio_aberto       "V7 + V9" v7 v9
deriva arquivo_fora_do_plano "V9 + V1" v1 v9
deriva segredo_no_diff       "V10 vence tudo" v1 v6 v7 v9 v10
entrega "$E" bloqueado bloqueado '[v1, v2, v9]' arquivo_fora_do_plano; aceita --validar "bloqueado com três falhas" "$E" 'causa=arquivo_fora_do_plano'
entrega "$E" bloqueado bloqueado '[v7, v1]' bloqueio_aberto;           reprova --validar "lista fora da numeração do portão" "$E" 'fora da numeração'
[ "$(bash "$CAUSA" --lista v9 v1 v10_sem_prova)" = '[v1, v9, v10_sem_prova]' ] && ok "--lista grava na numeração do portão" || falha "--lista: $(bash "$CAUSA" --lista v9 v1 v10_sem_prova)"

# ---------------------------------------------------------------------------
echo
echo "5. Mesma evidência, mesma causa"
# ---------------------------------------------------------------------------
a="$(bash "$CAUSA" --derivar v1 v7 v9)"; b="$(bash "$CAUSA" --derivar v1 v7 v9)"; c="$(bash "$CAUSA" --derivar v9 v7 v1)"
[ -n "$a" ] && [ "$a" = "$b" ] && [ "$a" = "$c" ] && ok "duas execuções e outra ordem de entrada → $a" || falha "derivação instável: '$a' '$b' '$c'"
entrega "$E" bloqueado bloqueado '[v1, v7]' bloqueio_aberto
a="$(bash "$CAUSA" --validar "$E" 2>&1)"; b="$(bash "$CAUSA" --validar "$E" 2>&1)"
[ "$a" = "$b" ] && [ "$a" = 'causa=bloqueio_aberto' ] && ok "validação repetida → $a" || falha "validação instável: '$a' '$b'"

# ---------------------------------------------------------------------------
echo
echo "6. Chave ausente reprova a gravação nova"
# ---------------------------------------------------------------------------
entrega "$E" bloqueado bloqueado '[v7]' -;  reprova --validar "bloqueado sem a chave causa" "$E" 'chave causa ausente'
entrega "$E" aberto null '[]' -;            reprova --validar "aberto sem a chave causa" "$E" 'chave causa ausente'
entrega "$E" bloqueado bloqueado - bloqueio_aberto; reprova --validar "sem falhas_portao" "$E" 'chave falhas_portao ausente'
entrega "$E" bloqueado bloqueado '[v7]' null; reprova --validar "bloqueado com causa null" "$E" 'exige causa não nula'
entrega "$E" bloqueado bloqueado '[]' indeterminada; reprova --validar "bloqueado sem falha registrada" "$E" 'portao bloqueado sem falhas'
entrega "$E" bloqueado pronto '[]' null;    reprova --validar "estado bloqueado com portão pronto" "$E" 'exige portao: bloqueado'

# ---------------------------------------------------------------------------
echo
echo "7. Causa ou falha fora do enum reprova"
# ---------------------------------------------------------------------------
entrega "$E" bloqueado bloqueado '[v1, v7]' falha_tecnica;  reprova --validar "falha_tecnica" "$E" "causa fora do enum: 'falha_tecnica'"
entrega "$E" bloqueado bloqueado '[v7]' decisao_humana;     reprova --validar "classe da buildx como causa" "$E" 'causa fora do enum'
entrega "$E" bloqueado bloqueado '[v7]' Bloqueio_Aberto;    reprova --validar "enum com maiúscula" "$E" 'causa fora do enum'
entrega "$E" bloqueado bloqueado '[v11]' bloqueio_aberto;   reprova --validar "falha v11" "$E" 'falha desconhecida'
entrega "$E" bloqueado bloqueado '[v7, v7_sem_prova]' bloqueio_aberto; reprova --validar "vN e vN_sem_prova juntos" "$E" 'registrada duas vezes'
entrega "$E" bloqueado bloqueado 'v7' bloqueio_aberto;      reprova --validar "falhas_portao fora de lista" "$E" 'não é lista'
recusa_derivar "derivar sem falha nenhuma"
recusa_derivar "derivar falha desconhecida" v7 x1

# ---------------------------------------------------------------------------
echo
echo "8. ENTREGA anterior às chaves: leitura histórica sim, gravação nova não"
# ---------------------------------------------------------------------------
n=0
for leg in "$FIXTURES"/*/*/docs/entregas/*/ENTREGA.md; do
  [ -f "$leg" ] || continue
  n=$((n+1)); rel="${leg#$REPO/}"
  aceita  --validar-historico "leitura histórica: $rel" "$leg" 'causa=ausente'
  reprova --validar "gravação nova: $rel" "$leg" 'chave causa ausente'
done
[ "$n" -ge 3 ] && ok "$n ENTREGA reais anteriores às chaves" || falha "fixtures legadas ausentes ($n)"
entrega "$E" bloqueado bloqueado - -;               aceita  --validar-historico "bloqueio legado: causa não commitada, nunca inferida" "$E" 'causa=ausente'
entrega "$E" bloqueado bloqueado '[v7]' -;          reprova --validar-historico "uma chave sem a outra não é legado" "$E" 'chave causa ausente'
entrega "$E" bloqueado bloqueado '[v7]' falha_tecnica; reprova --validar-historico "leitura histórica não aceita causa inválida" "$E" 'causa fora do enum'

# ---------------------------------------------------------------------------
echo
echo "9. Causa não provada: indeterminada, nunca inventada"
# ---------------------------------------------------------------------------
deriva indeterminada   "só V1 sem prova (sem plano)"                v1_sem_prova
deriva indeterminada   "V10 sem prova antes do B-NN provado"         v7 v10_sem_prova
deriva indeterminada   "V9 sem prova antes da V1 provada"            v1 v9_sem_prova
deriva bloqueio_aberto "V7 provada antes da V9 sem prova"            v7 v9_sem_prova
entrega "$E" bloqueado bloqueado '[v1, v10_sem_prova]' indeterminada;   aceita  --validar "bloqueado indeterminado" "$E" 'causa=indeterminada'
entrega "$E" bloqueado bloqueado '[v1, v10_sem_prova]' tarefa_nao_concluida; reprova --validar "escolher a causa provada mais baixa" "$E" 'não é a derivada'
entrega "$E" bloqueado bloqueado '[v7]' indeterminada;                  reprova --validar "indeterminada com causa provada" "$E" 'não é a derivada'

# ---------------------------------------------------------------------------
echo
echo "10. Piloto: E2 BLOQUEADO com V1 e V7 (B-01 fora do ownership), lido por git show"
# ---------------------------------------------------------------------------
R="$(mktemp -d)"; TMPS="$TMPS $R"
git -C "$R" init -q -b main . 2>/dev/null || { git -C "$R" init -q . && git -C "$R" checkout -q -b main; }
git -C "$R" config user.email teste@expx.local; git -C "$R" config user.name Teste; git -C "$R" config core.autocrlf false
printf 'base\n' > "$R/README.md"; git -C "$R" add README.md; git -C "$R" commit -qm base
git -C "$R" checkout -q -b feature/ft-piloto
W="$R/docs/sprintx/features/ft-piloto"; mkdir -p "$W/sprint-04" "$R/docs/entregas/ft-piloto"
cat > "$W/sprint-04/tasks.md" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-piloto
tasks:
  - id: T-04.02
    status: concluida
    suite: verde
  - id: T-04.03
    status: bloqueada
    suite: nao_executada
---
YAML
cat > "$W/00-BLOQUEIOS.md" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: ft-piloto
bloqueios:
  - id: B-01
    task: T-04.03
    resolvido_em: null
---

| B-NN | task | bloqueio | o que destravaria |
|---|---|---|---|
| B-01 | T-04.03 | precisa alterar arquivo fora do ownership da feature | decisão sobre o dono do arquivo |
YAML
# O E2 registra o que viu: V1 FALHA (T-04.03 bloqueada), V7 FALHA (B-01 aberto); V2 e V9 OK.
FALHAS="$(bash "$CAUSA" --lista v7 v1)"
entrega "$R/docs/entregas/ft-piloto/ENTREGA.md" aberto bloqueado "$FALHAS" null
# O E8 fecha o bloqueio: deriva a causa, grava com estado bloqueado, valida e commita.
CAUSA_PILOTO="$(bash "$CAUSA" --derivar v1 v7)"
entrega "$R/docs/entregas/ft-piloto/ENTREGA.md" bloqueado bloqueado "$FALHAS" "$CAUSA_PILOTO"
if bash "$CAUSA" --validar "$R/docs/entregas/ft-piloto/ENTREGA.md" >/dev/null 2>&1; then
  git -C "$R" add docs && git -C "$R" commit -qm 'chore(entrega): finalizar registro do trabalho ft-piloto'
fi
LIDO="$(git -C "$R" show feature/ft-piloto:docs/entregas/ft-piloto/ENTREGA.md 2>/dev/null | bash "$CAUSA" --validar - 2>&1)"
[ "$FALHAS" = '[v1, v7]' ] && ok "falhas registradas: $FALHAS" || falha "falhas do piloto: $FALHAS"
[ "$LIDO" = 'causa=bloqueio_aberto' ] && ok "git show do HEAD da feature → $LIDO" || falha "git show do piloto: '$LIDO'"
case "$LIDO" in *falha_tecnica*) falha "o piloto virou falha_tecnica" ;; *) ok "o piloto não vira falha_tecnica" ;; esac
# O texto do B-01 não muda a causa: outro motivo, mesma evidência de portão.
sed 's/precisa alterar arquivo fora do ownership da feature/dependencia externa indisponivel/' "$W/00-BLOQUEIOS.md" > "$W/b" && mv "$W/b" "$W/00-BLOQUEIOS.md"
[ "$(bash "$CAUSA" --derivar v1 v7)" = "$CAUSA_PILOTO" ] && ok "narrativa do B-NN não altera a causa" || falha "a causa dependeu da narrativa"

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
