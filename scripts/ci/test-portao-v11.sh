#!/usr/bin/env bash
#
# Bancada da V11 — task concluída sem prova de commit do E1.
#
# A V11 responde UMA pergunta: cada task `concluida` do plano executado tem
# pelo menos um item em `ENTREGA.commits` com `task` igual ao id dela e um
# `commit` válido? Ela não olha `suite` (V2), nem os testes declarados (V3),
# nem o status das não concluídas (V1). Ela cruza `tasks.md` com
# `ENTREGA.commits`, e só isso.
#
# Cobre os casos obrigatórios do contrato, o portão completo (V1–V10 OK e só a
# V11 falhando, com a causa derivada e lida por `git show`) e o E1 tardio.
#
# Sem rede, sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-portao-v11.sh
#      PROVA=<outro script> bash scripts/ci/test-portao-v11.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROVA="${PROVA:-$REPO/.claude/skills/mergex/scripts/prova-de-commit.sh}"
CAUSA="${CAUSA:-$REPO/.claude/skills/mergex/scripts/causa-do-portao.sh}"
FIXTURES="$REPO/scripts/ci/fixtures/e2e-p0-2"

OK=0; FALHOU=0
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT
D="$(mktemp -d)"; TMPS="$TMPS $D"

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# ---------------------------------------------------------------------------
# Fixtures mínimas: um plano e uma ENTREGA, nos dois formatos de sprint.
# ---------------------------------------------------------------------------

# plano <arquivo> <kind> <id:status> ... — o formato NUNCA muda o resultado da V11.
plano() {
  local arq="$1" kind="$2" par id st; shift 2
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: %s\ntrabalho_id: ft-teste\n' "$kind"
    [ "$kind" = plano ] && printf 'sprint:\n  titulo: Sprint de teste\n  status: concluido\n'
    printf 'fases:\n  - id: F-01.1\n    titulo: Fase\n    tasks: [T-01.01]\n'
    printf 'tasks:\n'
    for par in "$@"; do
      id="${par%%:*}"; st="${par##*:}"
      printf -- '  - id: %s\n    titulo: Task %s\n    fase: F-01.1\n    status: %s\n' "$id" "$id" "$st"
      printf '    objetivo: Fazer a coisa da task %s\n    suite: verde\n' "$id"
      printf '    teste_integracao: integra\n    teste_funcional: funciona\n'
    done
    printf -- '---\n\n# Plano\n\nProsa do plano.\n'
  } > "$arq"
}

# entrega <arquivo> <versionado> <task:sha> ... — `-` sem nenhum item (commits: [])
entrega() {
  local arq="$1" versionado="$2" par; shift 2
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-teste\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: %s\n' "$versionado"
    printf 'branch: feature/ft-teste\nbranch_base: main\n'
    if [ "$#" -eq 0 ]; then
      printf 'commits: []\n'
    else
      printf 'commits:\n'
      for par in "$@"; do
        printf -- '  - task: %s\n    commit: %s\n' "${par%%:*}" "${par#*:}"
      done
    fi
    printf 'modulo_afetado: []\narquivos_alterados: []\nfaixa_atencao: []\nraio: null\n'
    printf 'atencao:\n  olho_obrigatorio: 0\n  leitura_rapida: 0\n  dispensavel: 0\n'
    printf 'portao: null\nfalhas_portao: []\ncausa: null\ndesvios: []\n'
    printf 'push_feito: false\npr_url: null\npr_estado: null\n'
    printf -- '---\n\n# Entrega\n\nProsa da entrega.\n'
  } > "$arq"
}

# verifica <esperado> <descrição> <ENTREGA> <tasks...> — confere só a 1ª linha
verifica() {
  local esperado="$1" desc="$2" obtido; shift 2
  obtido="$(bash "$PROVA" --verificar "$@" 2>&1 | head -1)"
  if [ "$obtido" = "V11=$esperado" ]; then ok "$desc → $esperado"
  else falha "$desc — obteve '${obtido}', esperava 'V11=$esperado'"; fi
}

# acusa <descrição> <ids esperados, separados por espaço> <ENTREGA> <tasks...>
acusa() {
  local desc="$1" esperados="$2" obtido; shift 2
  obtido="$(bash "$PROVA" --verificar "$@" 2>/dev/null | sed '1d' | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
  if [ "$obtido" = "$esperados" ]; then ok "$desc — nomeia [$obtido]"
  else falha "$desc — nomeou '[$obtido]', esperava '[$esperados]'"; fi
}

E="$D/ENTREGA.md"; T="$D/tasks.md"; T2="$D/tasks-2.md"

# ---------------------------------------------------------------------------
echo "1. Task concluída com prova de E1"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" true T-01.01:a3f19c2
verifica OK "caso 1 — concluída com task e SHA válido em commits" "$E" "$T"
plano "$T" tasks T-01.01:concluida
verifica OK "o formato de três arquivos dá o mesmo resultado" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "2. Task concluída sem item em commits"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" true
verifica FALHA "caso 2 — concluída, commits vazio" "$E" "$T"
acusa "caso 2 — nomeia a task sem prova" "T-01.01" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "3. Só a task sem prova é nomeada"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida T-01.02:concluida
entrega "$E" true T-01.01:a3f19c2
verifica FALHA "caso 3 — uma com prova, outra sem" "$E" "$T"
acusa "caso 3 — nomeia SOMENTE T-01.02" "T-01.02" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "4-5. Task não concluída não é alvo da V11 (é da V1)"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida T-01.02:pendente
entrega "$E" true T-01.01:a3f19c2
verifica OK "caso 4 — task pendente sem commit não acusa" "$E" "$T"
plano "$T" plano T-01.01:concluida T-01.02:bloqueada
verifica OK "caso 5 — task bloqueada sem commit não acusa" "$E" "$T"
plano "$T" plano T-01.01:concluida T-01.02:em_andamento
verifica OK "task em_andamento sem commit não acusa" "$E" "$T"
plano "$T" plano T-01.02:pendente T-01.03:bloqueada
entrega "$E" true
verifica n/a "nenhuma task concluída: V11 não se aplica" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "6. Mais de um commit para a mesma task"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" true T-01.01:a3f19c2 T-01.01:7b2e401
verifica OK "caso 6 — dois commits válidos para a mesma task" "$E" "$T"
entrega "$E" true T-01.01:a3f19c2 T-01.01:a3f19c2
verifica OK "item repetido não é erro de V11 (duplicidade é de outra verificação)" "$E" "$T"
entrega "$E" true T-01.01: T-01.01:7b2e401
verifica OK "um item malformado e outro válido: a prova existe" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "7. Item de commits com task diferente não satisfaz"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" true T-01.02:a3f19c2
verifica FALHA "caso 7 — commits só tem outra task" "$E" "$T"
acusa "caso 7 — nomeia T-01.01" "T-01.01" "$E" "$T"
entrega "$E" true T-01.010:a3f19c2
verifica FALHA "id que só contém a task como prefixo não satisfaz" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "8. Item com task correta e commit vazio ou malformado não satisfaz"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
for sha in '' null '""' '{{identificador curto}}' 'TODO' 'zzzzzzz' 'a3f19' 'a3f19c2!' 'NÃO DETERMINADO'; do
  entrega "$E" true "T-01.01:$sha"
  verifica FALHA "caso 8 — commit '${sha:-<vazio>}' não é prova" "$E" "$T"
done
for sha in a3f19c2 593ab77 a3f19c2b1d4e6f8091a2b3c4d5e6f708192a3b4c; do
  entrega "$E" true "T-01.01:$sha"
  verifica OK "SHA '$sha' é prova" "$E" "$T"
done

# ---------------------------------------------------------------------------
echo
echo "9. E1 tardio: falha antes, passa depois — sem reordenar o que já existe"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida T-02.03:concluida
entrega "$E" true T-01.01:a3f19c2
verifica FALHA "caso 9 — antes do E1 tardio de T-02.03" "$E" "$T"
acusa "caso 9 — nomeia T-02.03" "T-02.03" "$E" "$T"
# O E1 tardio ACRESCENTA no fim; nada do histórico é reordenado.
entrega "$E" true T-01.01:a3f19c2 T-02.03:9f0c1d2
verifica OK "caso 9 — depois do E1 tardio" "$E" "$T"
[ "$(bash "$PROVA" --commits "$E" | head -1 | cut -f1)" = T-01.01 ] \
  && ok "caso 9 — o commit antigo continua sendo o primeiro item" \
  || falha "caso 9 — a ordem do histórico mudou"

# ---------------------------------------------------------------------------
echo
echo "10-11. Mesma evidência, mesmo resultado"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida T-02.03:concluida
entrega "$E" true T-01.01:a3f19c2 T-02.03:9f0c1d2
a="$(bash "$PROVA" --verificar "$E" "$T" 2>&1)"
entrega "$E" true T-02.03:9f0c1d2 T-01.01:a3f19c2
b="$(bash "$PROVA" --verificar "$E" "$T" 2>&1)"
[ "$a" = "$b" ] && ok "caso 10 — outra ordem em ENTREGA.commits, mesmo resultado" \
  || falha "caso 10 — a ordem de commits mudou o resultado"
entrega "$E" true T-01.01:a3f19c2 T-02.03:9f0c1d2
sed 's/^    objetivo: .*/    objetivo: Outro objetivo, escrito de outro jeito/; s/^# Plano/# Plano reescrito/' "$T" > "$T2"
c="$(bash "$PROVA" --verificar "$E" "$T2" 2>&1)"
[ "$a" = "$c" ] && ok "caso 11 — prosa e descrição da task mudam, mesmo resultado" \
  || falha "caso 11 — a prosa da task mudou o resultado"
d1="$(bash "$PROVA" --verificar "$E" "$T" 2>&1)"; d2="$(bash "$PROVA" --verificar "$E" "$T" 2>&1)"
[ "$d1" = "$d2" ] && ok "duas execuções sobre a mesma evidência: mesmo resultado" \
  || falha "verificação instável"

# ---------------------------------------------------------------------------
echo
echo "12. Task concluída renomeada sem atualizar commits"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.09:concluida
entrega "$E" true T-01.01:a3f19c2
verifica FALHA "caso 12 — id da task mudou, commits ficou no id antigo" "$E" "$T"
acusa "caso 12 — nomeia o id novo" "T-01.09" "$E" "$T"

# ---------------------------------------------------------------------------
echo
echo "13. Vários tasks.md do mesmo trabalho (uma sprint por arquivo)"
# ---------------------------------------------------------------------------
plano "$T"  plano T-01.01:concluida
plano "$T2" plano T-02.01:concluida T-02.02:concluida
entrega "$E" true T-01.01:a3f19c2 T-02.01:7b2e401
verifica FALHA "duas sprints, uma task sem prova" "$E" "$T" "$T2"
acusa "nomeia só a task da segunda sprint" "T-02.02" "$E" "$T" "$T2"
entrega "$E" true T-01.01:a3f19c2 T-02.01:7b2e401 T-02.02:5be75d3
verifica OK "duas sprints, todas com prova" "$E" "$T" "$T2"

# ---------------------------------------------------------------------------
echo
echo "14. versionado: false — sem versionador não há commit a exigir"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" false
verifica n/a "repositório sem versionador: V11 n/a" "$E" "$T"
bash "$PROVA" --verificar "$E" "$T" 2>&1 | grep -Fq 'motivo=sem-versionador' \
  && ok "o motivo do n/a é declarado" || falha "n/a sem motivo declarado"

# ---------------------------------------------------------------------------
echo
echo "15. Sem prova não é prova: a V11 que não pôde rodar não vira OK"
# ---------------------------------------------------------------------------
verifica SEM_PROVA "ENTREGA.md inexistente" "$D/nao-existe.md" "$T"
entrega "$E" true T-01.01:a3f19c2
verifica SEM_PROVA "tasks.md inexistente" "$E" "$D/nao-existe.md"
verifica SEM_PROVA "nenhum tasks.md informado" "$E"
printf 'sem frontmatter\n' > "$D/solto.md"
verifica SEM_PROVA "ENTREGA.md sem frontmatter" "$D/solto.md" "$T"
entrega "$E" true T-01.01:a3f19c2
verifica SEM_PROVA "tasks.md sem a chave tasks" "$E" "$D/solto.md"
rc=0; bash "$PROVA" --verificar "$D/nao-existe.md" "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok "sem prova sai por 2 (nem 0 nem 1)" || falha "sem prova saiu por $rc"

# ---------------------------------------------------------------------------
echo
echo "16. A V11 não responde pelas outras verificações"
# ---------------------------------------------------------------------------
plano "$T" plano T-01.01:concluida
entrega "$E" true T-01.01:a3f19c2
sed 's/^    suite: verde/    suite: vermelha/' "$T" > "$T2"
verifica OK "suíte vermelha é da V2, não da V11" "$E" "$T2"
sed 's/^    teste_funcional: .*/    teste_funcional: /' "$T" > "$T2"
verifica OK "teste não declarado é da V3, não da V11" "$E" "$T2"

# ---------------------------------------------------------------------------
echo
echo "17. Fixtures E2E reais: entregas completas passam a V11"
# ---------------------------------------------------------------------------
n=0
for ent in "$FIXTURES"/*/head/docs/entregas/*/ENTREGA.md; do
  [ -f "$ent" ] || continue
  trab="$(basename "$(dirname "$ent")")"
  set --
  for tk in "$(dirname "$(dirname "$(dirname "$ent")")")"/sprintx/features/"$trab"/sprint-*/tasks.md; do
    [ -f "$tk" ] && set -- "$@" "$tk"
  done
  [ "$#" -gt 0 ] || { falha "fixture $trab sem tasks.md"; continue; }
  n=$((n+1))
  verifica OK "E2E real: $trab (${#} sprint(s))" "$ent" "$@"
done
[ "$n" -ge 2 ] && ok "$n entrega(s) E2E real(is) verificada(s)" || falha "fixtures E2E ausentes ($n)"

# ---------------------------------------------------------------------------
echo
echo "18. A V11 no enum do portão: falha própria, causa própria"
# ---------------------------------------------------------------------------
[ "$(bash "$CAUSA" --derivar v11)" = commit_nao_registrado ] \
  && ok "V11 sozinha → commit_nao_registrado" || falha "V11 sozinha → $(bash "$CAUSA" --derivar v11 2>&1)"
[ "$(bash "$CAUSA" --lista v11 v1)" = '[v1, v11]' ] \
  && ok "--lista grava v11 na numeração do portão" || falha "--lista: $(bash "$CAUSA" --lista v11 v1 2>&1)"
[ "$(bash "$CAUSA" --ordem)" = 'v10 v6 v7 v8 v9 v1 v2 v3 v4 v5 v11' ] \
  && ok "V11 entra por último no grupo que lê o registro da execução" \
  || falha "ordem: $(bash "$CAUSA" --ordem)"
[ "$(bash "$CAUSA" --derivar v1 v11)" = tarefa_nao_concluida ] \
  && ok "V1 + V11 → tarefa_nao_concluida (a execução não terminou)" \
  || falha "V1 + V11 → $(bash "$CAUSA" --derivar v1 v11 2>&1)"
[ "$(bash "$CAUSA" --derivar v7 v11)" = bloqueio_aberto ] \
  && ok "V7 + V11 → bloqueio_aberto" || falha "V7 + V11 → $(bash "$CAUSA" --derivar v7 v11 2>&1)"
[ "$(bash "$CAUSA" --derivar v10 v11)" = segredo_no_diff ] \
  && ok "V10 + V11 → segredo_no_diff" || falha "V10 + V11 → $(bash "$CAUSA" --derivar v10 v11 2>&1)"
[ "$(bash "$CAUSA" --derivar v11_sem_prova)" = indeterminada ] \
  && ok "V11 sem prova → indeterminada" || falha "V11 sem prova → $(bash "$CAUSA" --derivar v11_sem_prova 2>&1)"

# ---------------------------------------------------------------------------
echo
echo "19. Portão completo: V1–V10 OK e SOMENTE a V11 falha"
# ---------------------------------------------------------------------------
R="$(mktemp -d)"; TMPS="$TMPS $R"
git -C "$R" init -q -b main . 2>/dev/null || { git -C "$R" init -q . && git -C "$R" checkout -q -b main; }
git -C "$R" config user.email teste@expx.local
git -C "$R" config user.name Teste
git -C "$R" config core.autocrlf false
printf 'base\n' > "$R/README.md"
git -C "$R" add README.md; git -C "$R" commit -qm base
git -C "$R" checkout -q -b feature/ft-v11

W="$R/docs/sprintx/features/ft-v11"
mkdir -p "$W/sprint-01" "$R/docs/entregas/ft-v11" "$R/src"

# V1 OK: as duas tasks concluídas. V2 OK: suite verde e o fechamento registrado.
# V3 OK: os dois testes declarados. V4/V5 n/a (sprintx). V8 n/a (sem PERFIL.md).
cat > "$W/sprint-01/tasks.md" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-v11
sprint:
  titulo: Sprint unica
  status: concluido
  criterio_saida: a suite inteira passa
fases:
  - id: F-01.1
    titulo: Fase unica
    status: concluido
    tasks: [T-01.01, T-01.02]
tasks:
  - id: T-01.01
    titulo: Primeira task
    fase: F-01.1
    status: concluida
    objetivo: Criar o modulo
    arquivos:
      cria: [src/a.js]
      altera: []
    teste_integracao: integra
    teste_funcional: funciona
    criterio_aceite: passa
    suite: verde
  - id: T-01.02
    titulo: Segunda task
    fase: F-01.1
    status: concluida
    objetivo: Criar o outro modulo
    arquivos:
      cria: [src/b.js]
      altera: []
    teste_integracao: integra
    teste_funcional: funciona
    criterio_aceite: passa
    suite: verde
---

# Plano

## Portão da sprint — suíte inteira

Sprint concluída. Saída da suíte: 0 falhas.
YAML

# V6 OK: auditoria aprovada. V7 OK: nenhum bloqueio aberto.
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: auditoria\ntrabalho_id: ft-v11\n---\n\nVEREDITO: SIM\n' > "$W/00-AUDITORIA.md"
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: bloqueios\ntrabalho_id: ft-v11\nbloqueios: []\n---\n\nNenhum bloqueio.\n' > "$W/00-BLOQUEIOS.md"

# V9 OK: só os arquivos declarados e os artefatos de método deste trabalho.
# V10 OK: nada parecido com segredo.
printf 'module.exports = function a() { return 1 }\n' > "$R/src/a.js"
printf 'module.exports = function b() { return 2 }\n' > "$R/src/b.js"

# O E1 commitou a T-01.01 e, por falha operacional, NÃO commitou a T-01.02.
git -C "$R" add src/a.js docs; git -C "$R" commit -qm 'feat(src): Primeira task'
SHA1="$(git -C "$R" rev-parse --short HEAD)"
git -C "$R" add src/b.js; git -C "$R" commit -qm 'feat(src): Segunda task'

ENT="$R/docs/entregas/ft-v11/ENTREGA.md"

# portao_entrega <estado> <portao> <falhas> <causa> <task:sha>...
portao_entrega() {
  local estado="$1" portao="$2" falhas="$3" causa="$4" par; shift 4
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-v11\n'
    printf 'entregue_por: mergex\ntitulo: Portao completo com so a V11 falhando\n'
    printf 'tipo_trabalho: feature\ntipo_ocorrencia: null\nestado: %s\nversionado: true\n' "$estado"
    printf 'branch: feature/ft-v11\nbranch_base: main\n'
    if [ "$#" -eq 0 ]; then printf 'commits: []\n'; else
      printf 'commits:\n'
      for par in "$@"; do printf -- '  - task: %s\n    commit: %s\n' "${par%%:*}" "${par#*:}"; done
    fi
    printf 'modulo_afetado: [src]\narquivos_alterados: []\nfaixa_atencao: []\nraio: null\n'
    printf 'atencao:\n  olho_obrigatorio: 0\n  leitura_rapida: 0\n  dispensavel: 0\n'
    printf 'portao: %s\nfalhas_portao: %s\ncausa: %s\ndesvios: []\n' "$portao" "$falhas" "$causa"
    printf 'push_feito: false\npr_url: null\npr_estado: null\n'
    printf 'criado_em: 2026-09-20\natualizado_em: 2026-09-20\nentregue_em: null\n'
    printf -- '---\n\n# Entrega — portão completo\n'
  } > "$ENT"
}

# --- O E2 roda: V1..V10 OK, V11 FALHA ---
portao_entrega aberto null '[]' null "T-01.01:$SHA1"
verifica FALHA "portão completo — V11 é a única a falhar" "$ENT" "$W/sprint-01/tasks.md"
acusa "portão completo — o diagnóstico nomeia T-01.02" "T-01.02" "$ENT" "$W/sprint-01/tasks.md"

FALHAS="$(bash "$CAUSA" --lista v11)"
[ "$FALHAS" = '[v11]' ] && ok "portão completo — falhas_portao: $FALHAS" || falha "falhas_portao: $FALHAS"

# O E2 grava portao/falhas e NÃO grava causa; estado segue aberto.
portao_entrega aberto bloqueado "$FALHAS" null "T-01.01:$SHA1"
r="$(bash "$CAUSA" --validar "$ENT" 2>&1)"
[ "$r" = 'causa=null' ] && ok "portão completo — E2 grava bloqueado sem causa ($r)" || falha "E2: $r"

# E3 a E7 não executam: nada de faixa, contagem, push ou PR no registro.
naoi=0
grep -Fq 'faixa_atencao: []' "$ENT" || naoi=1
grep -Fq 'olho_obrigatorio: 0' "$ENT" || naoi=1
grep -Fq 'push_feito: false' "$ENT" || naoi=1
grep -Fq 'pr_url: null' "$ENT" || naoi=1
[ "$naoi" = 0 ] && ok "portão completo — E3 a E7 não deixaram registro (bloqueado não entrega)" \
  || falha "portão bloqueado com registro de E3–E7"

# O E8 fecha o bloqueio: deriva a causa, grava, valida e commita.
CAUSA_V11="$(bash "$CAUSA" --derivar v11)"
portao_entrega bloqueado bloqueado "$FALHAS" "$CAUSA_V11" "T-01.01:$SHA1"
if bash "$CAUSA" --validar "$ENT" >/dev/null 2>&1; then
  git -C "$R" add docs && git -C "$R" commit -qm 'chore(entrega): finalizar registro do trabalho ft-v11'
  ok "portão completo — o E8 validou e commitou o bloqueio"
else
  falha "portão completo — o E8 não validou: $(bash "$CAUSA" --validar "$ENT" 2>&1)"
fi
LIDO="$(git -C "$R" show feature/ft-v11:docs/entregas/ft-v11/ENTREGA.md 2>/dev/null | bash "$CAUSA" --validar - 2>&1)"
[ "$LIDO" = 'causa=commit_nao_registrado' ] \
  && ok "portão completo — git show do HEAD da feature → $LIDO" || falha "git show: '$LIDO'"
case "$LIDO" in *indeterminada*|*falha_tecnica*) falha "a V11 provada virou causa não provada" ;;
  *) ok "a V11 provada não vira indeterminada nem falha_tecnica" ;; esac

# --- E1 tardio: a T-01.02 já estava commitada; falta o registro da prova ---
SHA2="$(git -C "$R" rev-parse --short feature/ft-v11~1)"
portao_entrega aberto null '[]' null "T-01.01:$SHA1" "T-01.02:$SHA2"
verifica OK "E1 tardio — a prova registrada destrava a V11" "$ENT" "$W/sprint-01/tasks.md"
r="$(bash "$CAUSA" --validar "$ENT" 2>&1)"
[ "$r" = 'causa=null' ] && ok "E1 tardio — portão sem falhas, causa null" || falha "E1 tardio: $r"
[ "$(bash "$PROVA" --commits "$ENT" | head -1 | cut -f2)" = "$SHA1" ] \
  && ok "E1 tardio — o commit antigo não foi reordenado" || falha "E1 tardio reordenou o histórico"

# ---------------------------------------------------------------------------
echo
echo '20. A chave de ordem `seq` não muda nenhuma resposta da V11'
# ---------------------------------------------------------------------------
# Desde a P0.2-C4 todo item NOVO leva `seq` (`references/00-schema.md`, "A ordem
# de registro"). A V11 continua com a mesma pergunta e os mesmos três tipos de
# lista: totalmente legada, moderna e mista válida. Ordem, sequência e `seq`
# não são assunto dela — quebra de sequência é contrato, não portão.

# entrega_seq <arquivo> <item>... — item é `<seq|->:<task>:<sha>`; `-` é legado
entrega_seq() {
  local arq="$1" item s t c; shift
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-teste\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: true\n'
    printf 'branch: feature/ft-teste\nbranch_base: main\ncommits:\n'
    for item in "$@"; do
      s="${item%%:*}"; t="${item#*:}"; c="${t#*:}"; t="${t%%:*}"
      [ "$s" = - ] || printf -- '  - seq: %s\n    task: %s\n    commit: %s\n' "$s" "$t" "$c"
      [ "$s" = - ] && printf -- '  - task: %s\n    commit: %s\n' "$t" "$c"
    done
    printf 'modulo_afetado: []\narquivos_alterados: []\nfaixa_atencao: []\nraio: null\n'
    printf 'atencao:\n  olho_obrigatorio: 0\n  leitura_rapida: 0\n  dispensavel: 0\n'
    printf 'portao: null\nfalhas_portao: []\ncausa: null\ndesvios: []\n'
    printf 'push_feito: false\npr_url: null\npr_estado: null\n'
    printf -- '---\n\n# Entrega\n'
  } > "$arq"
}

plano "$T" plano T-01.01:concluida
entrega_seq "$E" -:T-01.01:a3f19c2
verifica OK "lista totalmente legada continua passando" "$E" "$T"
entrega_seq "$E" 1:T-01.01:a3f19c2
verifica OK "lista moderna (item começa por seq) passa" "$E" "$T"
entrega_seq "$E" -:T-09.09:aaa1111 2:T-01.01:a3f19c2
verifica OK "lista mista válida passa" "$E" "$T"
entrega_seq "$E" 1:T-01.01:zzzzzzz
verifica FALHA "task correta com commit inválido continua falhando" "$E" "$T"
acusa "e nomeia a task" "T-01.01" "$E" "$T"
entrega_seq "$E" 1:T-01.01:a3f19c2 3:T-01.02:7b2e401
verifica OK "sequência com buraco não faz a V11 regredir (é contrato)" "$E" "$T"
entrega_seq "$E" 2:T-01.02:7b2e401 1:T-01.01:a3f19c2
verifica OK "ordem física trocada não é assunto da V11" "$E" "$T"
entrega_seq "$E" 9:T-01.01:a3f19c2
verifica OK "seq não é quantidade de commits esperada para a task" "$E" "$T"
plano "$T" plano T-04.03:concluida
entrega_seq "$E" 1:T-04.01:aaa1111 2:T-04.03:bbb2222 3:T-04.02:ccc3333 \
  4:T-04.04:ddd4444 5:T-04.05:eee5555 6:T-04.06:fff6666 7:T-04.03:9f3c1aa
verifica OK "a mesma task em seq 2 e seq 7 continua provada" "$E" "$T"
[ "$(bash "$PROVA" --commits "$E" | grep -c '^T-04.03	')" = 2 ] \
  && ok "os dois itens da mesma task são lidos, não só o primeiro" \
  || falha "a leitura perdeu uma das duas passagens de T-04.03"

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
