#!/usr/bin/env bash
#
# Bancada do E3 — artefatos de método (L4 e D4), precedência dos critérios O e
# reconhecimento específico.
#
# Cada cenário monta um repositório temporário, roda o classificador da skill
# e confere, por arquivo, a FAIXA, o CRITÉRIO e um trecho do MOTIVO. Contagem
# não basta: uma faixa certa pelo motivo errado é um defeito escondido.
#
# Sem rede, sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-atencao-metodo.sh
#      CLASSIFICADOR=<outro script> bash scripts/ci/test-atencao-metodo.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFICADOR="${CLASSIFICADOR:-$REPO/.claude/skills/mergex/scripts/classificar-atencao.sh}"
FIXTURES="$REPO/scripts/ci/fixtures/e2e-p0-2"
T="$(printf '\t')"

OK=0; FALHOU=0
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
novo_repo() {
  R="$(mktemp -d)"; TMPS="$TMPS $R"
  git -C "$R" init -q -b main . 2>/dev/null || { git -C "$R" init -q . && git -C "$R" checkout -q -b main; }
  git -C "$R" config user.email teste@expx.local
  git -C "$R" config user.name Teste
  git -C "$R" config core.autocrlf false
  printf 'base\n' > "$R/README.md"
  git -C "$R" add README.md && git -C "$R" commit -qm base
}

escreve() { # <caminho> — conteúdo pela entrada padrão
  mkdir -p "$(dirname "$R/$1")"
  cat > "$R/$1"
}

commit_tudo() { git -C "$R" add -A && git -C "$R" commit -qm "${1:-trabalho}"; }

fm() { # <kind> <trabalho_id> [linhas extras...]
  local kind="$1" tid="$2"; shift 2
  printf -- '---\nexpx_schema: 1\nexpx_tool: %s\nkind: %s\ntrabalho_id: %s\n' "${TOOL:-sprintx}" "$kind" "$tid"
  local l; for l in "$@"; do printf '%s\n' "$l"; done
  printf -- '---\n\n# conteúdo\n'
}

# Trabalho sprintx completo: branch, ENTREGA.md, pasta canônica com ORQUESTRADOR.
trabalho_sprintx() { # <id>
  local id="$1"
  git -C "$R" checkout -q -b "feature/$id"
  TOOL=sprintx fm entrega "$id" "branch: feature/$id" "entregue_por: mergex" | escreve "docs/entregas/$id/ENTREGA.md"
  TOOL=sprintx fm orquestrador "$id" | escreve "docs/sprintx/features/$id/ORQUESTRADOR.md"
}

trabalho_runx() { # <id>
  local id="$1"
  git -C "$R" checkout -q -b "fix/$id"
  TOOL=runx fm entrega "$id" "branch: fix/$id" "entregue_por: mergex" | escreve "docs/entregas/$id/ENTREGA.md"
  TOOL=runx fm orquestrador "$id" | escreve "docs/manutencao/$id/ORQUESTRADOR.md"
}

# classifica <base> — lê "caminho TAB critérios..." da entrada padrão
classifica() {
  SAIDA="$(bash "$CLASSIFICADOR" --raiz "$R" --base "$1")"
}

# espera <caminho> <faixa> <prefixo do critério> <trecho do motivo> [descrição]
espera() {
  local caminho="$1" faixa="$2" criterio="$3" trecho="$4" desc="${5:-$1}"
  local l f j
  l="$(printf '%s\n' "$SAIDA" | awk -F'\t' -v c="$caminho" '$1 == c { print; exit }')"
  f="$(printf '%s' "$l" | cut -f2)"
  j="$(printf '%s' "$l" | cut -f3-)"
  if [ -z "$l" ]; then
    FALHOU=$((FALHOU+1)); printf '  FALHA %s — arquivo ausente da saída\n' "$desc"; return
  fi
  if [ "$f" != "$faixa" ]; then
    FALHOU=$((FALHOU+1)); printf '  FALHA %s — faixa "%s", esperava "%s" (%s)\n' "$desc" "$f" "$faixa" "$j"; return
  fi
  case "$j" in
    "$criterio"*) ;;
    *) FALHOU=$((FALHOU+1)); printf '  FALHA %s — critério "%s", esperava prefixo "%s"\n' "$desc" "$j" "$criterio"; return ;;
  esac
  case "$j" in
    *"$trecho"*) OK=$((OK+1)); printf '  ok    %s — %s %s\n' "$desc" "$f" "$criterio" ;;
    *) FALHOU=$((FALHOU+1)); printf '  FALHA %s — motivo "%s" não contém "%s"\n' "$desc" "$j" "$trecho" ;;
  esac
}

# ---------------------------------------------------------------------------
echo "Ordem declarada pelo classificador"
# ---------------------------------------------------------------------------
if [ "$(bash "$CLASSIFICADOR" --ordem)" = 'O1 O2 O3 O4 O5 O6 O7 O8 O9 O10 L1 L2 L3 L4 D1 D2 D3 D4 PADRAO' ]; then
  OK=$((OK+1)); echo '  ok    O1..O10, L1..L4, D1..D4, padrão'
else
  FALHOU=$((FALHOU+1)); echo '  FALHA ordem dos critérios alterada'
fi

# ---------------------------------------------------------------------------
echo
echo "Cenário A — produto de risco continua OLHO OBRIGATÓRIO ao lado de artefato de método"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-a
S=docs/sprintx/features/ft-a
printf 'module.exports = login\n' | escreve src/auth/login.js
printf 'module.exports = {}\n' | escreve src/util/formata.js
fm decisoes ft-a | escreve "$S/00-DECISOES.md"
commit_tudo
classifica main <<EOF
src/auth/login.js${T}O4: cria a sessão do usuário (T-01.02)
src/util/formata.js
$S/00-DECISOES.md
$S/ORQUESTRADOR.md
EOF
espera src/auth/login.js "OLHO OBRIGATÓRIO" "O4" "cria a sessão" "login com O4"
espera src/util/formata.js "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "produto sem evidência cai no padrão"
espera "$S/00-DECISOES.md" "LEITURA RÁPIDA" "L4" "decisões e hipóteses" "decisões ao lado do produto de risco"

# ---------------------------------------------------------------------------
echo
echo "Cenário B — decisão, premissa, plano e fechamento conhecidos vão para LEITURA RÁPIDA (L4)"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-b
S=docs/sprintx/features/ft-b
fm decisoes ft-b | escreve "$S/00-DECISOES.md"
printf '# Premissas pendentes do BuildX\n\n### PR-01 — x\n' | escreve "$S/BUILDX-PREMISSAS.md"
fm plano ft-b | escreve "$S/sprint-01/tasks.md"
fm tasks ft-b | escreve "$S/sprint-02/tasks.md"
fm sprint ft-b | escreve "$S/sprint-02/sprint.md"
fm fases ft-b | escreve "$S/sprint-02/fases.md"
fm fechamento ft-b | escreve "$S/FECHAMENTO.md"
fm estimativa ft-b | escreve "$S/00-ESTIMATIVA.md"
printf '# Auditoria\n\nVEREDITO: SIM\n' | escreve "$S/00-AUDITORIA.md"
printf '# Lacunas\n' | escreve "$S/base/00-LACUNAS.md"
commit_tudo
classifica main <<EOF
$S/00-DECISOES.md
$S/BUILDX-PREMISSAS.md
$S/sprint-01/tasks.md
$S/sprint-02/tasks.md
$S/sprint-02/sprint.md
$S/sprint-02/fases.md
$S/FECHAMENTO.md
$S/00-ESTIMATIVA.md
$S/00-AUDITORIA.md
$S/base/00-LACUNAS.md
$S/ORQUESTRADOR.md
EOF
espera "$S/00-DECISOES.md" "LEITURA RÁPIDA" "L4" "decisões e hipóteses do trabalho (00-DECISOES.md, origem sprintx)"
espera "$S/BUILDX-PREMISSAS.md" "LEITURA RÁPIDA" "L4" "premissas assumidas pela buildx"
espera "$S/sprint-01/tasks.md" "LEITURA RÁPIDA" "L4" "sprint-NN/tasks.md" "tasks condensado (kind: plano)"
espera "$S/sprint-02/tasks.md" "LEITURA RÁPIDA" "L4" "sprint-NN/tasks.md" "tasks em três arquivos (kind: tasks)"
espera "$S/sprint-02/sprint.md" "LEITURA RÁPIDA" "L4" "critério de saída da sprint"
espera "$S/sprint-02/fases.md" "LEITURA RÁPIDA" "L4" "fases e critérios de saída"
espera "$S/FECHAMENTO.md" "LEITURA RÁPIDA" "L4" "risco residual"
espera "$S/00-ESTIMATIVA.md" "LEITURA RÁPIDA" "L4" "premissas e invalidadores"
espera "$S/00-AUDITORIA.md" "LEITURA RÁPIDA" "L4" "auditoria do plano"
espera "$S/base/00-LACUNAS.md" "LEITURA RÁPIDA" "L4" "lacunas da investigação"
espera "$S/ORQUESTRADOR.md" "LEITURA RÁPIDA" "L4" "objetivo, mapa e rota"

# ---------------------------------------------------------------------------
echo
echo "Cenário C — artefato mecânico conhecido vai para DISPENSÁVEL (D4) só com a prova mecânica"
# ---------------------------------------------------------------------------
novo_repo
H=docs/sprintx/estimativas/HISTORICO.md
{
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: estimativa_historico\ntrabalho_id: null\natualizado_em: 2026-09-01\nunidade: h\nentradas:\n'
  printf '  - trabalho_id: ft-antigo\n    task_id: T-01.01\n    real: 1\n'
  printf 'calibracao: []\n---\n\n# Histórico\n\n| Trabalho | Task | Real |\n|---|---|---|\n| ft-antigo | T-01.01 | 1 h |\n'
} | escreve "$H"
commit_tudo historico
trabalho_sprintx ft-c
S=docs/sprintx/features/ft-c
fm bloqueios ft-c 'bloqueios: []' | escreve "$S/00-BLOQUEIOS.md"
fm base_indice ft-c 'areas:' '  - arquivo: modulo.md' '    lacunas: 1' | escreve "$S/base/00-INDICE.md"
printf '# Módulo\n' | escreve "$S/base/modulo.md"
commit_tudo
# O HISTORICO fica SUJO, como na hora do E3: só acrescenta entradas e linhas deste trabalho.
awk '
  /^calibracao:/ && !feito { print "  - trabalho_id: ft-c"; print "    task_id: T-01.01"; print "    real: 2"; feito = 1 }
  { print }
  END { print "| ft-c | T-01.01 | 2 h |" }
' "$R/$H" > "$R/$H.novo" && sed 's/^atualizado_em: .*/atualizado_em: 2026-09-16/' "$R/$H.novo" > "$R/$H" && rm -f "$R/$H.novo"
classifica main <<EOF
$H
$S/00-BLOQUEIOS.md
$S/base/00-INDICE.md
$S/base/modulo.md
docs/entregas/ft-c/ENTREGA.md
EOF
espera "$H" "DISPENSÁVEL" "D4" "só acrescenta entradas de ft-c" "HISTORICO só com entradas deste trabalho"
espera "$S/00-BLOQUEIOS.md" "DISPENSÁVEL" "D4" "bloqueios: [] e nenhum B-NN"
espera "$S/base/00-INDICE.md" "DISPENSÁVEL" "D4" "as 1 área(s) listadas existem"
espera "$S/base/modulo.md" "LEITURA RÁPIDA" "L4" "listada no índice" "área da base listada no índice"
espera docs/entregas/ft-c/ENTREGA.md "DISPENSÁVEL" "D4" "gravado pela própria mergex"

echo "  -- a prova falha: o mesmo artefato sobe para LEITURA RÁPIDA, nunca fica DISPENSÁVEL"
sed 's/^# Histórico$/# Histórico — nova lição sobre estimativa/' "$R/$H" > "$R/$H.novo" && mv "$R/$H.novo" "$R/$H"
classifica main <<EOF
$H
EOF
espera "$H" "LEITURA RÁPIDA" "L4" "D4 não provado: remove ou reescreve linha existente" "HISTORICO com prosa reescrita"
git -C "$R" checkout -q -- "$H" 2>/dev/null
printf '  - trabalho_id: ft-outro\n' > /dev/null
awk '/^calibracao:/ && !f { print "  - trabalho_id: ft-outro"; f = 1 } { print }' "$R/$H" > "$R/$H.novo" && mv "$R/$H.novo" "$R/$H"
classifica main <<EOF
$H
EOF
espera "$H" "LEITURA RÁPIDA" "L4" "acrescenta entrada de outro trabalho: ft-outro" "HISTORICO com entrada de outro trabalho"
classifica "" <<EOF
$H
EOF
espera "$H" "LEITURA RÁPIDA" "L4" "sem --base" "HISTORICO sem base para provar"
fm bloqueios ft-c 'bloqueios:' '  - id: B-01' | escreve "$S/00-BLOQUEIOS.md"
fm base_indice ft-c 'areas:' '  - arquivo: sumiu.md' | escreve "$S/base/00-INDICE.md"
classifica main <<EOF
$S/00-BLOQUEIOS.md
$S/base/00-INDICE.md
EOF
espera "$S/00-BLOQUEIOS.md" "LEITURA RÁPIDA" "L4" "D4 não provado: a lista de bloqueios não está vazia" "bloqueio registrado"
espera "$S/base/00-INDICE.md" "LEITURA RÁPIDA" "L4" "o índice lista arquivo inexistente: sumiu.md" "índice inconsistente"

# ---------------------------------------------------------------------------
echo
echo "Cenário D — arquivo desconhecido em docs/sprintx não ganha nada pelo diretório"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-d
S=docs/sprintx/features/ft-d
printf '# notas soltas\n' | escreve "$S/NOTAS.md"
printf 'module.exports = 42\n' | escreve "$S/regra.js"
printf '# calibragem\n' | escreve docs/sprintx/estimativas/CALIBRAGEM.md
printf '# arquivo solto\n' | escreve docs/sprintx/LEIA.md
printf '# fora do padrão\n' | escreve "$S/sprint-1/tasks.md"
printf '# subpasta\n' | escreve "$S/base/extra/area.md"
printf '# base não listada\n' | escreve "$S/base/nao-listada.md"
TOOL=sprintx fm orquestrador ft-outra | escreve docs/sprintx/features/ft-outra/ORQUESTRADOR.md
TOOL=sprintx fm decisoes ft-outra | escreve docs/sprintx/features/ft-outra/00-DECISOES.md
commit_tudo
classifica main <<EOF
$S/NOTAS.md
$S/regra.js
docs/sprintx/estimativas/CALIBRAGEM.md
docs/sprintx/LEIA.md
$S/sprint-1/tasks.md
$S/base/extra/area.md
$S/base/nao-listada.md
docs/sprintx/features/ft-outra/00-DECISOES.md
EOF
espera "$S/NOTAS.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "arquivo novo na pasta do trabalho"
espera "$S/regra.js" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "código dentro da pasta do trabalho"
espera docs/sprintx/estimativas/CALIBRAGEM.md "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "vizinho do HISTORICO"
espera docs/sprintx/LEIA.md "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "arquivo solto em docs/sprintx"
espera "$S/sprint-1/tasks.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "sprint sem dois dígitos"
espera "$S/base/extra/area.md" "OLHO OBRIGATÓRIO" "padrão" "não listado no base/00-INDICE.md" "subpasta da base fora do índice"
espera "$S/base/nao-listada.md" "OLHO OBRIGATÓRIO" "padrão" "não listado no base/00-INDICE.md" "base fora do índice"
espera docs/sprintx/features/ft-outra/00-DECISOES.md "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "decisões de OUTRO trabalho"

# ---------------------------------------------------------------------------
echo
echo "Cenário E — frontmatter falso não compra rebaixamento"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-e
S=docs/sprintx/features/ft-e
fm decisoes ft-e | escreve "$S/DECISOES-EXTRA.md"
fm decisoes ft-e | escreve src/regras.md
fm decisoes ft-e | escreve docs/sprintx/decisoes.md
fm base_indice ft-e | escreve "$S/00-DECISOES.md"
fm decisoes ft-outro | escreve "$S/FECHAMENTO.md"
fm auditoria ft-e | escreve "$S/00-AUDITORIA.md"
TOOL=sprintx fm entrega ft-e 'branch: feature/outra-branch' | escreve docs/entregas/ft-e/PR.md
commit_tudo
classifica main <<EOF
$S/DECISOES-EXTRA.md
src/regras.md
docs/sprintx/decisoes.md
$S/00-DECISOES.md
$S/FECHAMENTO.md
$S/00-AUDITORIA.md
docs/entregas/ft-e/PR.md
$S/ORQUESTRADOR.md${T}L4: eu garanto que é só leitura
src/qualquer.js${T}D4: declarado dispensável por quem chamou
EOF
espera "$S/DECISOES-EXTRA.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "expx_tool sprintx + kind decisoes em nome inventado"
espera src/regras.md "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "frontmatter sprintx em src/"
espera docs/sprintx/decisoes.md "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo" "frontmatter sprintx fora da pasta do trabalho"
espera "$S/00-DECISOES.md" "OLHO OBRIGATÓRIO" "padrão" "kind 'base_indice' não confere com decisoes" "caminho canônico com kind trocado"
espera "$S/FECHAMENTO.md" "OLHO OBRIGATÓRIO" "padrão" "kind 'decisoes' não confere com fechamento" "kind de outro artefato"
espera "$S/00-AUDITORIA.md" "OLHO OBRIGATÓRIO" "padrão" "o contrato não define kind" "kind inventado onde o contrato não tem frontmatter"
espera docs/entregas/ft-e/PR.md "OLHO OBRIGATÓRIO" "padrão" "o contrato não define kind" "PR.md com frontmatter inventado"
espera "$S/ORQUESTRADOR.md" "LEITURA RÁPIDA" "L4" "ignorado: L4" "L4 declarado por quem chama é ignorado"
espera src/qualquer.js "OLHO OBRIGATÓRIO" "padrão" "ignorado: D4" "D4 declarado por quem chama é ignorado"

echo "  -- sinais de contexto que precisam bater juntos"
novo_repo; trabalho_sprintx ft-e2
S=docs/sprintx/features/ft-e2
fm decisoes ft-e2 | escreve "$S/00-DECISOES.md"
commit_tudo
TOOL=runx fm entrega ft-e2 'branch: feature/ft-e2' | escreve docs/entregas/ft-e2/ENTREGA.md
classifica main <<EOF
$S/00-DECISOES.md
EOF
espera "$S/00-DECISOES.md" "OLHO OBRIGATÓRIO" "padrão" "diverge do expx_tool do ENTREGA.md" "pasta sprintx com ENTREGA declarando runx"
git -C "$R" checkout -q -- docs/entregas/ft-e2/ENTREGA.md
TOOL=sprintx fm entrega ft-e3 'branch: feature/ft-e2' | escreve docs/entregas/ft-e3/ENTREGA.md
classifica main <<EOF
$S/00-DECISOES.md
EOF
espera "$S/00-DECISOES.md" "OLHO OBRIGATÓRIO" "padrão" "trabalho corrente não determinado" "dois ENTREGA.md na mesma branch"
rm -rf "$R/docs/entregas/ft-e3"
git -C "$R" update-index --chmod=+x "$S/00-DECISOES.md"
classifica main <<EOF
$S/00-DECISOES.md
EOF
espera "$S/00-DECISOES.md" "OLHO OBRIGATÓRIO" "padrão" "executável" "artefato registrado como executável"

# ---------------------------------------------------------------------------
echo
echo "Cenário F — artefato conhecido com critério O fica em OLHO OBRIGATÓRIO"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-f
S=docs/sprintx/features/ft-f
fm decisoes ft-f | escreve "$S/00-DECISOES.md"
fm bloqueios ft-f 'bloqueios: []' | escreve "$S/00-BLOQUEIOS.md"
fm plano ft-f | escreve "$S/sprint-01/tasks.md"
commit_tudo
classifica main <<EOF
$S/00-DECISOES.md${T}O4: D-03 decide que a sessão expira em 30 dias (origem da decisão)
$S/00-BLOQUEIOS.md${T}O1: caminho casa com a zona de risco docs/ do PERFIL.md
$S/sprint-01/tasks.md${T}O9: regressão registrada no memox (OC-2026-0001, 2026-09-01)${T}L2: camada isolada
EOF
espera "$S/00-DECISOES.md" "OLHO OBRIGATÓRIO" "O4" "sessão expira" "decisão de autenticação"
espera "$S/00-BLOQUEIOS.md" "OLHO OBRIGATÓRIO" "O1" "zona de risco" "D4 possível, mas O1 vence"
espera "$S/sprint-01/tasks.md" "OLHO OBRIGATÓRIO" "O9" "regressão" "O9 vence L2 e L4"

# ---------------------------------------------------------------------------
echo
echo "Cenário G — runx usa o catálogo dela, não o da sprintx"
# ---------------------------------------------------------------------------
novo_repo
H=docs/sprintx/estimativas/HISTORICO.md
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: estimativa_historico\ntrabalho_id: null\nentradas:\n---\n' | escreve "$H"
commit_tudo historico
trabalho_runx OC-2026-0001-frete
W=docs/manutencao/OC-2026-0001-frete
TOOL=runx
fm ocorrencia OC-2026-0001-frete | escreve "$W/00-OCORRENCIA.md"
fm causa_raiz OC-2026-0001-frete | escreve "$W/01-CAUSA-RAIZ.md"
fm qa OC-2026-0001-frete | escreve "$W/QA.md"
fm bloqueios OC-2026-0001-frete 'bloqueios: []' | escreve "$W/BLOQUEIOS.md"
fm plano OC-2026-0001-frete | escreve "$W/sprint-01/tasks.md"
fm base_indice OC-2026-0001-frete 'areas:' '  - arquivo: frete.md' | escreve "$W/base/00-INDICE.md"
printf '# Frete\n' | escreve "$W/base/frete.md"
fm decisoes OC-2026-0001-frete | escreve "$W/00-DECISOES.md"
fm bloqueios OC-2026-0001-frete 'bloqueios: []' | escreve "$W/00-BLOQUEIOS.md"
fm fechamento OC-2026-0001-frete | escreve "$W/FECHAMENTO.md"
TOOL=sprintx
commit_tudo
awk '/^entradas:/ { print; print "  - trabalho_id: OC-2026-0001-frete"; next } { print }' "$R/$H" > "$R/$H.novo" && mv "$R/$H.novo" "$R/$H"
classifica main <<EOF
$W/00-OCORRENCIA.md
$W/01-CAUSA-RAIZ.md
$W/QA.md
$W/BLOQUEIOS.md
$W/sprint-01/tasks.md
$W/base/00-INDICE.md
$W/base/frete.md
$W/ORQUESTRADOR.md
$W/00-DECISOES.md
$W/00-BLOQUEIOS.md
$W/FECHAMENTO.md
$H
docs/entregas/OC-2026-0001-frete/ENTREGA.md
EOF
espera "$W/00-OCORRENCIA.md" "LEITURA RÁPIDA" "L4" "relato e tipo da ocorrência"
espera "$W/01-CAUSA-RAIZ.md" "LEITURA RÁPIDA" "L4" "causa raiz, hipóteses e decisões"
espera "$W/QA.md" "LEITURA RÁPIDA" "L4" "veredito e roteiro do QA"
espera "$W/BLOQUEIOS.md" "DISPENSÁVEL" "D4" "origem runx" "BLOQUEIOS.md vazio da runx"
espera "$W/sprint-01/tasks.md" "LEITURA RÁPIDA" "L4" "origem runx"
espera "$W/base/00-INDICE.md" "DISPENSÁVEL" "D4" "origem runx"
espera "$W/base/frete.md" "LEITURA RÁPIDA" "L4" "listada no índice"
espera "$W/ORQUESTRADOR.md" "LEITURA RÁPIDA" "L4" "rota da ocorrência"
espera "$W/00-DECISOES.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo da runx" "00-DECISOES.md (nome da sprintx) na runx"
espera "$W/00-BLOQUEIOS.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo da runx" "00-BLOQUEIOS.md (nome da sprintx) na runx"
espera "$W/FECHAMENTO.md" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo da runx" "FECHAMENTO.md na runx"
espera "$H" "OLHO OBRIGATÓRIO" "padrão" "fora do catálogo da runx" "HISTORICO da sprintx num trabalho runx"
espera docs/entregas/OC-2026-0001-frete/ENTREGA.md "DISPENSÁVEL" "D4" "gravado pela própria mergex"

# ---------------------------------------------------------------------------
echo
echo "Cenário H — sem legadox e sem memox, artefato de método segue a regra nova"
# ---------------------------------------------------------------------------
novo_repo; trabalho_sprintx ft-h
S=docs/sprintx/features/ft-h
fm decisoes ft-h | escreve "$S/00-DECISOES.md"
fm bloqueios ft-h 'bloqueios: []' | escreve "$S/00-BLOQUEIOS.md"
printf 'x\n' | escreve src/novo.js
commit_tudo
[ ! -e "$R/docs/legado/PERFIL.md" ] && [ ! -e "$R/.claude/skills/memox/assets/memox.py" ] || { FALHOU=$((FALHOU+1)); echo '  FALHA fixture tem legadox ou memox'; }
classifica main <<EOF
$S/00-DECISOES.md
$S/00-BLOQUEIOS.md
src/novo.js${T}L3: arquivo novo com os dois testes verdes (T-01.01)
EOF
espera "$S/00-DECISOES.md" "LEITURA RÁPIDA" "L4" "decisões e hipóteses" "decisões sem legadox/memox"
espera "$S/00-BLOQUEIOS.md" "DISPENSÁVEL" "D4" "bloqueios: []" "bloqueios sem legadox/memox"
espera src/novo.js "LEITURA RÁPIDA" "L3" "dois testes verdes" "produto classificado como sempre"

echo "  -- sprintx no formato antigo (docs/<slug>/)"
novo_repo
git -C "$R" checkout -q -b feature/ft-legado
TOOL=sprintx fm entrega ft-legado 'branch: feature/ft-legado' | escreve docs/entregas/ft-legado/ENTREGA.md
fm orquestrador ft-legado | escreve docs/ft-legado/ORQUESTRADOR.md
fm decisoes ft-legado | escreve docs/ft-legado/00-DECISOES.md
commit_tudo
classifica main <<EOF
docs/ft-legado/00-DECISOES.md
EOF
espera docs/ft-legado/00-DECISOES.md "LEITURA RÁPIDA" "L4" "decisões e hipóteses" "pasta legada da sprintx"

# ---------------------------------------------------------------------------
echo
echo "Reprodução do E3 do E2E real (p0-integration-test-2)"
# ---------------------------------------------------------------------------
for ft in contador-sequencial codigo-sequencial; do
  D="$FIXTURES/$ft"
  if [ ! -d "$D" ]; then FALHOU=$((FALHOU+1)); printf '  FALHA fixture ausente: %s\n' "$D"; continue; fi
  echo "  == $ft"
  novo_repo
  ( cd "$D/base" && find . -type f ) | sed 's|^\./||' | while IFS= read -r p; do
    mkdir -p "$(dirname "$R/$p")"; cp "$D/base/$p" "$R/$p"
  done
  commit_tudo base-da-feature
  git -C "$R" checkout -q -b "feature/$ft"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -Fxq "$p" "$D/sujo-no-e3.txt" && continue
    mkdir -p "$(dirname "$R/$p")"; cp "$D/head/$p" "$R/$p"
  done < "$D/arquivos.txt"
  commit_tudo tasks
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    mkdir -p "$(dirname "$R/$p")"; cp "$D/head/$p" "$R/$p"
  done < "$D/sujo-no-e3.txt"

  SAIDA="$(bash "$CLASSIFICADOR" --raiz "$R" --base main < "$D/evidencia.tsv")"
  n_saida="$(printf '%s\n' "$SAIDA" | grep -c .)"
  n_arq="$(grep -c . "$D/arquivos.txt")"
  if [ "$n_saida" = "$n_arq" ]; then OK=$((OK+1)); printf '  ok    %s arquivos classificados, nenhum de fora\n' "$n_saida"
  else FALHOU=$((FALHOU+1)); printf '  FALHA %s arquivos na saída, %s no diff\n' "$n_saida" "$n_arq"; fi
  while IFS="$T" read -r caminho faixa criterio trecho; do
    [ -n "$caminho" ] || continue
    espera "$caminho" "$faixa" "$criterio" "$trecho"
  done < "$D/esperado.tsv"
  # Nenhum arquivo do E2E pode ter caído no padrão: todos têm critério nomeado.
  if printf '%s\n' "$SAIDA" | cut -f3 | grep -q '^padrão'; then
    FALHOU=$((FALHOU+1)); echo '  FALHA algum arquivo do E2E ainda caiu no padrão'
  else
    OK=$((OK+1)); echo '  ok    nenhum arquivo do E2E caiu no padrão'
  fi
  printf '%s\n' "$SAIDA" | cut -f2 | sort | uniq -c | sed 's/^/        /'
done

# ---------------------------------------------------------------------------
echo
echo "O10 — arquivo reconciliado da base (--reconciliados)"
# ---------------------------------------------------------------------------
O10TXT='O10: arquivo reconciliado da base'
D="$(mktemp -d)"; TMPS="$TMPS $D"
ESPECIAL="docs/Relatório d'água final.md"

roda_o10() { # <lista> — entrada padrão passa para o classificador
  SAIDA="$(bash "$CLASSIFICADOR" --base main --reconciliados "$1" 2>"$D/err")"; RC=$?
}
linha_de() { printf '%s\n' "$SAIDA" | awk -F'\t' -v c="$1" '$1 == c { print; exit }'; }
confere() { # <descrição> <condição: 0 verdadeira>
  if [ "$2" = 0 ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"
  else FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; fi
}

# reconciliado com evidência D1 não desce de faixa
printf 'tests/ui/novo.test.tsx\n' > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}D1: teste novo
EOF
case "$SAIDA" in
  *"OLHO OBRIGATÓRIO"*"$O10TXT"*) confere "reconciliado com D1 fica em OLHO OBRIGATÓRIO com O10" 0 ;;
  *) confere "reconciliado com D1 fica em OLHO OBRIGATÓRIO com O10 ($SAIDA)" 1 ;;
esac
case "$SAIDA" in *D1*) confere "O10 vence: D1 não aparece na justificativa" 1 ;; *) confere "O10 vence: D1 não aparece na justificativa" 0 ;; esac

# L1 também não desce
printf 'tests/ui/novo.test.tsx\n' > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}L1: lógica
EOF
espera tests/ui/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "reconciliado com L1 sobe para OLHO"

# já tinha O anterior: múltiplos O são juntados, O10 por último
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}O5: contrato público${T}D1: x
EOF
espera tests/ui/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O5: contrato público; O10:' "$O10TXT" "O anterior mantido, O10 acrescentado"

# correspondência exata: nada de substring
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}D1: a
tests/ui/novo.test.tsx.snap${T}D1: snapshot
tests/ui/novo.test${T}D1: prefixo
xtests/ui/novo.test.tsx${T}D1: sufixo
EOF
espera tests/ui/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "exato: o caminho listado"
espera tests/ui/novo.test.tsx.snap 'DISPENSÁVEL' 'D1:' 'snapshot' "exato: .snap não é marcado"
espera tests/ui/novo.test 'DISPENSÁVEL' 'D1:' 'prefixo' "exato: prefixo não é marcado"
espera xtests/ui/novo.test.tsx 'DISPENSÁVEL' 'D1:' 'sufixo' "exato: sufixo não é marcado"

# caminho especial e linhas vazias na lista
printf '\n%s\n\n' "$ESPECIAL" > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
${ESPECIAL}${T}D1: texto
docs/outro.md${T}D1: texto
EOF
espera "$ESPECIAL" 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "caminho com espaço, acento e apóstrofo"
espera docs/outro.md 'DISPENSÁVEL' 'D1:' 'texto' "linha vazia da lista não marca nada"
n="$(printf '%s\n' "$SAIDA" | grep -c .)"
confere "lista com linhas vazias não gera linha vazia na saída ($n linhas)" "$([ "$n" = 2 ] && echo 0 || echo 1)"

# caminho da lista ausente da entrada: o classificador emite a linha dele
printf 'a/so-na-lista.ts\n%s\n' "$ESPECIAL" > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
docs/outro.md${T}D1: texto
EOF
espera a/so-na-lista.ts 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "ausente da entrada: ainda sai em OLHO"
espera "$ESPECIAL" 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "ausente da entrada, caminho especial"
espera docs/outro.md 'DISPENSÁVEL' 'D1:' 'texto' "ausente da entrada: o resto segue igual"
# sem nenhuma entrada, só a lista
SAIDA="$(bash "$CLASSIFICADOR" --base main --reconciliados "$D/reconc.txt" </dev/null 2>/dev/null)"
espera a/so-na-lista.ts 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "entrada vazia: a lista ainda é emitida"
# caminho já presente na entrada não é emitido duas vezes
printf 'dup.ts\ndup.ts\n' > "$D/dup.txt"
roda_o10 "$D/dup.txt" <<EOF
dup.ts${T}D1: x
EOF
n="$(printf '%s\n' "$SAIDA" | grep -c '^dup.ts')"
confere "caminho na entrada e duplicado na lista sai uma vez ($n)" "$([ "$n" = 1 ] && echo 0 || echo 1)"

# lista inválida falha fechado
SAIDA="$(printf 'x.ts\n' | bash "$CLASSIFICADOR" --base main --reconciliados "$D/nao-existe.txt" 2>"$D/err")"; RC=$?
confere "lista ausente: rc != 0 ($RC)" "$([ "$RC" != 0 ] && echo 0 || echo 1)"
confere "lista ausente: motivo no stderr" "$(grep -q reconciliados "$D/err" && ! grep -q desconhecida "$D/err" && echo 0 || echo 1)"
confere "lista ausente: nenhuma classificação na saída" "$([ -z "$SAIDA" ] && echo 0 || echo 1)"
mkdir -p "$D/dir"
SAIDA="$(printf 'x.ts\n' | bash "$CLASSIFICADOR" --base main --reconciliados "$D/dir" 2>"$D/err")"; RC=$?
confere "lista ilegível (diretório): rc != 0 ($RC)" "$([ "$RC" != 0 ] && echo 0 || echo 1)"
SAIDA="$(printf 'x.ts\n' | bash "$CLASSIFICADOR" --base main --reconciliados 2>"$D/err")"; RC=$?
confere "--reconciliados sem argumento: rc != 0 ($RC)" "$([ "$RC" != 0 ] && echo 0 || echo 1)"

# lista com NNN: a justificativa cita o artefato
printf 'tests/ui/novo.test.tsx\t007\nsem-nnn.ts\n%s\t012\n' "$ESPECIAL" > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}O5: contrato
sem-nnn.ts${T}D1: x
EOF
espera tests/ui/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O5: contrato; O10:' 'O10: arquivo reconciliado da base (RECONCILIACAO-BASE-007.md)' "NNN: cita o artefato"
espera sem-nnn.ts 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "sem NNN: texto sem artefato"
l="$(linha_de sem-nnn.ts)"
case "$l" in *RECONCILIACAO-BASE*) confere "sem NNN: não cita artefato" 1 ;; *) confere "sem NNN: não cita artefato" 0 ;; esac
espera "$ESPECIAL" 'OLHO OBRIGATÓRIO' 'O10:' 'RECONCILIACAO-BASE-012.md)' "NNN: ausente da entrada, caminho especial"

# NNN inválido falha fechado
for ruim in '07' '0007' 'abc' '' '007	x'; do
  printf 'a.ts\t%s\n' "$ruim" > "$D/ruim.txt"
  SAIDA="$(printf 'a.ts\n' | bash "$CLASSIFICADOR" --base main --reconciliados "$D/ruim.txt" 2>"$D/err")"; RC=$?
  confere "NNN inválido '$ruim': rc 66 sem saída ($RC)" "$([ "$RC" = 66 ] && [ -z "$SAIDA" ] && grep -q NNN "$D/err" && echo 0 || echo 1)"
done

# maiúscula e minúscula são caminhos diferentes
printf 'Tests/UI/novo.test.tsx\n' > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}D1: minúsculo
EOF
espera tests/ui/novo.test.tsx 'DISPENSÁVEL' 'D1:' 'minúsculo' "caixa: Tests/UI não casa tests/ui"
espera Tests/UI/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "caixa: o caminho da lista sai à parte"

# lista com CRLF casa normalmente
printf 'tests/ui/novo.test.tsx\t007\r\nsem-nnn.ts\r\n' > "$D/reconc.txt"
roda_o10 "$D/reconc.txt" <<EOF
tests/ui/novo.test.tsx${T}D1: a
sem-nnn.ts${T}D1: b
EOF
espera tests/ui/novo.test.tsx 'OLHO OBRIGATÓRIO' 'O10:' 'RECONCILIACAO-BASE-007.md)' "CRLF: casa com NNN"
espera sem-nnn.ts 'OLHO OBRIGATÓRIO' 'O10:' "$O10TXT" "CRLF: casa sem NNN"

# sem --reconciliados nada muda
SAIDA="$(printf 'tests/ui/novo.test.tsx\tD1: x\n' | bash "$CLASSIFICADOR" --base main)"
espera tests/ui/novo.test.tsx 'DISPENSÁVEL' 'D1:' 'x' "sem a opção, o O10 não existe"

# ---------------------------------------------------------------------------
echo
echo "Cenário R — reconciliação, planejamento, predecessores e preflight (login #27/#28)"
# ---------------------------------------------------------------------------
# Antes, os quatro caíam em OLHO OBRIGATÓRIO pelo padrão: o classificador não os tinha no
# catálogo, e o catalogo-de-metodo.sh (que os commita) os tinha. DM-280.
novo_repo; trabalho_sprintx ft-r
S=docs/sprintx/features/ft-r; E=docs/entregas/ft-r
fm planejamento ft-r | escreve "$S/00-PLANEJAMENTO.md"
fm predecessores ft-r | escreve "$S/00-PREDECESSORES.md"
printf '# Preflight\n\nok\n' | escreve "$S/PREFLIGHT.md"
fm reconciliacao_base ft-r | escreve "$E/RECONCILIACAO-BASE-001.md"
fm reconciliacao_base ft-r | escreve "$E/RECONCILIACAO-BASE-002.md"
fm reconciliacao_base ft-r | escreve "$E/RECONCILIACAO-BASE-1.md"
fm entrega ft-r "branch: feature/ft-r" | escreve "$E/RECONCILIACAO-BASE-003.md"
commit_tudo
D="$(mktemp -d)"; TMPS="$TMPS $D"
printf 'src/reconciliado.ts\t001\n' > "$D/reconc.txt"
SAIDA="$(bash "$CLASSIFICADOR" --raiz "$R" --base main --reconciliados "$D/reconc.txt" <<EOF
$S/00-PLANEJAMENTO.md
$S/00-PREDECESSORES.md
$S/PREFLIGHT.md
$E/RECONCILIACAO-BASE-001.md
$E/RECONCILIACAO-BASE-002.md
$E/RECONCILIACAO-BASE-1.md
$E/RECONCILIACAO-BASE-003.md
EOF
)"
espera "$S/00-PLANEJAMENTO.md" "LEITURA RÁPIDA" "L4" "planejamento" "00-PLANEJAMENTO.md: L4"
espera "$S/00-PREDECESSORES.md" "LEITURA RÁPIDA" "L4" "predecessores" "00-PREDECESSORES.md: L4"
espera "$S/PREFLIGHT.md" "LEITURA RÁPIDA" "L4" "preflight" "PREFLIGHT.md: L4"
espera "$E/RECONCILIACAO-BASE-001.md" "DISPENSÁVEL" "D4" "prova mecânica" "reconciliação coberta pelo --verificar (001): D4"
espera "$E/RECONCILIACAO-BASE-002.md" "LEITURA RÁPIDA" "L4" "D4 não provado" "reconciliação sem linha do --verificar (002): L4"
espera "$E/RECONCILIACAO-BASE-1.md" "OLHO OBRIGATÓRIO" "padrão" "fora da forma RECONCILIACAO-BASE-NNN.md" "nome de reconciliação malformado: padrão"
espera "$E/RECONCILIACAO-BASE-003.md" "OLHO OBRIGATÓRIO" "padrão" "kind" "reconciliação com kind errado: padrão"
# sem a lista, o --verificar não rodou (ou não cobriu nada): L4
SAIDA="$(printf '%s\n' "$E/RECONCILIACAO-BASE-001.md" | bash "$CLASSIFICADOR" --raiz "$R" --base main)"
espera "$E/RECONCILIACAO-BASE-001.md" "LEITURA RÁPIDA" "L4" "D4 não provado" "reconciliação sem --reconciliados: L4"
# linha sem caminho não prova nada (reconciliação com arquivos: [] também fica em L4)
printf '\t001\n' > "$D/sem-caminho.txt"
SAIDA="$(printf '%s\n' "$E/RECONCILIACAO-BASE-001.md" | bash "$CLASSIFICADOR" --raiz "$R" --base main --reconciliados "$D/sem-caminho.txt" 2>/dev/null)"
espera "$E/RECONCILIACAO-BASE-001.md" "LEITURA RÁPIDA" "L4" "D4 não provado" "lista com NNN mas sem caminho: L4"
# critério O vence D4
SAIDA="$(printf '%s\tO4: altera a regra de cálculo\n' "$E/RECONCILIACAO-BASE-001.md" | bash "$CLASSIFICADOR" --raiz "$R" --base main --reconciliados "$D/reconc.txt")"
espera "$E/RECONCILIACAO-BASE-001.md" "OLHO OBRIGATÓRIO" "O4" "regra de cálculo" "O vence D4 na reconciliação"

# ---------------------------------------------------------------------------
echo
echo "Cenário — base em subpasta (DM-288): a área listada vale como a da raiz da base"
# ---------------------------------------------------------------------------
# O conselhos#216 tinha `arquivo: dominio/regras.md` no índice: a SprintX aceitou da F1
# à F5 e o E2 recusou ("enumera caminho fora da base"). A subpasta é da base; `..`,
# caminho absoluto, `\` e link simbólico continuam fora.
CATBASE="$REPO/.claude/skills/mergex/scripts/catalogo-de-metodo.sh"
novo_repo; trabalho_sprintx ft-sub
S=docs/sprintx/features/ft-sub
fm base_indice ft-sub 'areas:' '  - arquivo: modulo.md' '  - arquivo: dominio/regras.md' | escreve "$S/base/00-INDICE.md"
printf '# Módulo\n' | escreve "$S/base/modulo.md"
printf '# Regras\n' | escreve "$S/base/dominio/regras.md"
printf '# solta\n' | escreve "$S/base/dominio/solta.md"
commit_tudo
classifica main <<LISTA
$S/base/00-INDICE.md
$S/base/dominio/regras.md
$S/base/dominio/solta.md
LISTA
espera "$S/base/00-INDICE.md" "DISPENSÁVEL" "D4" "as 2 área(s) listadas existem" "índice com área em subpasta"
espera "$S/base/dominio/regras.md" "LEITURA RÁPIDA" "L4" "listada no índice" "área em subpasta listada"
espera "$S/base/dominio/solta.md" "OLHO OBRIGATÓRIO" "padrão" "não listado no base/00-INDICE.md" "subpasta fora do índice"
base_cat="$( (. "$CATBASE" && catalogo_base "$R" ft-sub "$S") 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s\n' "$base_cat" | grep -qxF "$S/base/dominio/regras.md"; then
  OK=$((OK+1)); echo "  ok    catalogo_base aceita a área em subpasta"
else
  FALHOU=$((FALHOU+1)); echo "  FALHA catalogo_base com área em subpasta (rc=$rc): $base_cat"
fi
for fora in '../fora.md' 'dominio/../../fora.md' '/abs/fora.md' 'dominio\regras.md'; do
  fm base_indice ft-sub 'areas:' "  - arquivo: $fora" | escreve "$S/base/00-INDICE.md"
  base_cat="$( (. "$CATBASE" && catalogo_base "$R" ft-sub "$S" >/dev/null; printf '%s' "$CATALOGO_ERRO") 2>&1)"
  if printf '%s' "$base_cat" | grep -qF 'fora da base'; then
    OK=$((OK+1)); echo "  ok    catalogo_base recusa $fora"
  else
    FALHOU=$((FALHOU+1)); echo "  FALHA catalogo_base aceitou $fora: $base_cat"
  fi
  classifica main <<LISTA
$S/base/00-INDICE.md
LISTA
  espera "$S/base/00-INDICE.md" "LEITURA RÁPIDA" "L4" "fora da base" "índice com $fora"
done
mkdir -p "$R/fora-da-base" && printf '# fora\n' > "$R/fora-da-base/x.md" && ln -s "$R/fora-da-base" "$R/$S/base/atalho"
fm base_indice ft-sub 'areas:' '  - arquivo: atalho/x.md' | escreve "$S/base/00-INDICE.md"
base_cat="$( (. "$CATBASE" && catalogo_base "$R" ft-sub "$S" >/dev/null; printf '%s' "$CATALOGO_ERRO") 2>&1)"
if printf '%s' "$base_cat" | grep -qF 'link simbólico'; then
  OK=$((OK+1)); echo "  ok    catalogo_base recusa área atrás de link simbólico"
else
  FALHOU=$((FALHOU+1)); echo "  FALHA catalogo_base aceitou área atrás de link simbólico: $base_cat"
fi
classifica main <<LISTA
$S/base/00-INDICE.md
LISTA
espera "$S/base/00-INDICE.md" "LEITURA RÁPIDA" "L4" "link simbólico" "índice com área atrás de link simbólico"

# ---------------------------------------------------------------------------
echo
echo "Consistência — tudo o que o catalogo-de-metodo.sh commita, o classificador reconhece"
# ---------------------------------------------------------------------------
# Os dois catálogos divergiram uma vez (login #27/#28): o checkpoint commitava artefato que o
# E3 mandava para OLHO OBRIGATÓRIO pelo padrão. Aqui a classificação real roda sobre cada
# caminho que o catalogo_metodo emite, por origem e checkpoint, com o frontmatter que o
# próprio catálogo do classificador declara. Nenhum pode cair no padrão.
CATMET="$REPO/.claude/skills/mergex/scripts/catalogo-de-metodo.sh"
CATCLS="$(bash "$CLASSIFICADOR" --catalogo)"
kind_de() { # <origem> <chave> — o kind que o catálogo do classificador declara, ou vazio
  printf '%s\n' "$CATCLS" | awk -F'|' -v o="$1" -v c="$2" '$1 == o && $2 == c { print $3; exit }'
}
for origem in sprintx runx; do
  novo_repo
  id="cons-$origem"
  if [ "$origem" = sprintx ]; then trabalho_sprintx "$id"; P="docs/sprintx/features/$id"; else trabalho_runx "$id"; P="docs/manutencao/$id"; fi
  TOOL=$origem fm entrega "$id" "branch: $(git -C "$R" branch --show-current)" "entregue_por: mergex" \
    "reconciliacoes:" "  - arquivo: RECONCILIACAO-BASE-001.md" | escreve "docs/entregas/$id/ENTREGA.md"
  mkdir -p "$R/$P/sprint-01"
  TOOL=$origem fm base_indice "$id" "areas: [dominio.md]" | escreve "$P/base/00-INDICE.md"
  printf '# dominio\n' | escreve "$P/base/dominio.md"
  for ck in pre-e2 reconciliacao-base predecessores retomar-v9-predecessores pre-e6 e8; do
    lista="$( (. "$CATMET" && catalogo_metodo "$R" "$origem" "$id" "$P" "$ck") 2>/dev/null)"; rc=$?
    if [ "$origem" = runx ] && { [ "$ck" = predecessores ] || [ "$ck" = retomar-v9-predecessores ]; }; then
      [ "$rc" != 0 ] && { OK=$((OK+1)); echo "  ok    runx recusa o checkpoint $ck (exclusivo da sprintx)"; } \
        || { FALHOU=$((FALHOU+1)); echo "  FALHA runx aceitou o checkpoint $ck"; }
      continue
    fi
    [ "$rc" = 0 ] || { FALHOU=$((FALHOU+1)); echo "  FALHA catalogo_metodo $origem $ck falhou"; continue; }
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      [ -e "$R/$c" ] && continue
      case "$c" in
        docs/entregas/"$id"/RECONCILIACAO-BASE-*) chave="docs/entregas/<trabalho_id>/RECONCILIACAO-BASE-NNN.md"; o=mergex ;;
        docs/entregas/"$id"/*) chave="docs/entregas/<trabalho_id>/${c#docs/entregas/$id/}"; o=mergex ;;
        docs/sprintx/estimativas/HISTORICO.md) chave="$c"; o=$origem ;;
        "$P"/sprint-*/*) chave="sprint-NN/${c##*/}"; o=$origem ;;
        "$P"/base/00-*) chave="base/${c##*/}"; o=$origem ;;
        "$P"/base/*) chave="base/<area>.md"; o=$origem ;;
        *) chave="${c#$P/}"; o=$origem ;;
      esac
      k="$(kind_de "$o" "$chave" | cut -d, -f1)"
      case "$k" in
        ''|-) printf '# %s\n' "${c##*/}" | escreve "$c" ;;
        estimativa_historico) TOOL=$origem fm "$k" null | escreve "$c" ;;
        entrega) ;;
        *) TOOL=$origem fm "$k" "$id" | escreve "$c" ;;
      esac
    done <<EOF
$lista
EOF
  done
  commit_tudo
  printf 'src/x.ts\t001\n' > "$R/.reconc"
  todos="$(for ck in pre-e2 reconciliacao-base predecessores retomar-v9-predecessores pre-e6 e8; do
    (. "$CATMET" && catalogo_metodo "$R" "$origem" "$id" "$P" "$ck") 2>/dev/null; done | sort -u)"
  SAIDA="$(printf '%s\n' "$todos" | bash "$CLASSIFICADOR" --raiz "$R" --base main --reconciliados "$R/.reconc")"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    [ "$c" = src/x.ts ] && continue
    l="$(printf '%s\n' "$SAIDA" | awk -F'\t' -v c="$c" '$1 == c { print; exit }')"
    case "$l" in
      *"$T"'OLHO OBRIGATÓRIO'"$T"*) FALHOU=$((FALHOU+1)); printf '  FALHA %s (%s): %s\n' "$c" "$origem" "$(printf '%s' "$l" | cut -f3)" ;;
      '') FALHOU=$((FALHOU+1)); printf '  FALHA %s (%s): ausente da saída\n' "$c" "$origem" ;;
      *) OK=$((OK+1)); printf '  ok    %s (%s) — %s\n' "${c#$P/}" "$origem" "$(printf '%s' "$l" | cut -f2)" ;;
    esac
  done <<EOF
$todos
EOF
done

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
