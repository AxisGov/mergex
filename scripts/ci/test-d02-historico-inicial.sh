#!/usr/bin/env bash
# Bancada do P0.2 / reparo D-02 — primeiro HISTORICO global da sprintx.
#
# O piloto C7-C travou no primeiro trabalho SprintX de um projeto: a sprintx
# criou `docs/sprintx/estimativas/HISTORICO.md` do template, como o contrato
# dela manda, e o lifecycle recusava todo HISTORICO untracked. Aqui a primeira
# criação entra pelo próprio persistir-metodo.sh depois da prova integral de
# ownership (DM-174). Depois dela, o HISTORICO tracked é provado pelo mesmo
# leitor, HEAD contra working tree (DM-175): entradas antigas imutáveis,
# entradas novas só do trabalho corrente, calibração e prosa recalculáveis.
#
# O grupo contrato é diferencial contra o contrato PUBLICADO da sprintx: o que
# o contrato permite (sinais em bloco, prosa, heading e tabela humana, menção
# incidental a task, comentário YAML, o literal {{...}} da instrução do
# template) passa; o que fere ownership ou a estrutura (marcador em dado,
# outro trabalho, sinais ambíguos, YAML inválido) barra.
#
# Uso: bash scripts/ci/test-d02-historico-inicial.sh [central|checkpoints|negativos|contrato|subsequente|tracked|e1]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
PERSISTE="${PERSISTE:-$SCRIPTS/persistir-metodo.sh}"
FECHA="${FECHA:-$SCRIPTS/fechamento-do-e1.sh}"
CONTRATO="${CONTRATO:-$SCRIPTS/contrato-de-commit.sh}"

OK=0
FALHOU=0
ok() { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU + 1)); printf '  FALHA %s\n' "$1"; }
igual() { # <descricao> <obtido> <esperado>
  if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 (esperava '$3', obteve '$2')"; fi
}

D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D"' EXIT

TRAB='issue-123-rotulo-parecer'
BRANCH="feature/$TRAB"
PASTA="docs/sprintx/features/$TRAB"
HIST='docs/sprintx/estimativas/HISTORICO.md'
ENT="docs/entregas/$TRAB/ENTREGA.md"

# O HISTORICO que a sprintx gravou no C7-C, byte a byte: primeiro trabalho do
# projeto, duas tasks concluídas em duas sprints, sem F3.5, prosa livre que
# cita as próprias tasks e nenhuma tabela de calibração.
historico_c7c() { # <arquivo>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'MD'
---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: 2026-09-26
unidade: h
entradas:
  - trabalho_id: issue-123-rotulo-parecer
    task_id: T-01.01
    tipo_task: teste
    area: accountability
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.12
    duracao_observada: 0.12
    desvio: null
    registrado_em: 2026-09-26
  - trabalho_id: issue-123-rotulo-parecer
    task_id: T-02.01
    tipo_task: ui
    area: accountability
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.13
    duracao_observada: 0.13
    desvio: null
    registrado_em: 2026-09-26
calibracao: []
---

# Histórico de esforço — calibração das estimativas

Uma linha por task concluída, com o esforço real medido. É a única base de calibração real do projeto: sem ele, toda estimativa fica com confiança no máximo MÉDIA.

Unidade: hora de trabalho focado. O real é o esforço efetivamente gasto na task — escrever os dois testes, implementar, rodar a suíte e verificar o critério de aceite. Não inclui reunião, revisão, deploy nem ida e volta com o cliente: esses são "não incluído" na estimativa e precisam continuar fora aqui, senão a calibração fica corrompida.

## Entradas

| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio |
|---|---|---|---|---|---|---|---|---|
| issue-123-rotulo-parecer | T-01.01 | teste | accountability | — | — | — | 0,12 h | — |
| issue-123-rotulo-parecer | T-02.01 | ui | accountability | — | — | — | 0,13 h | — |

Este é o **primeiro** trabalho a alimentar o histórico do projeto: o arquivo nasceu aqui.

A F3.5 **não rodou** neste trabalho (o acionamento não pediu estimativa), então não existe
`00-ESTIMATIVA.md` e os campos `estimado_min`, `estimado_max`, `estimado_media` e `desvio` são
`null` nas duas entradas, como o contrato manda. O `real` continua alimentando a comparabilidade
por tipo e por área nas estimativas futuras.

## Sobre o `real` destas duas entradas

O `real` foi medido, não estimado, e **coincide com a `duracao_observada`** que sai do rastro
(`task_iniciada` → `task_concluida`): 7m17s na T-01.01 e 7m30s na T-02.01. As duas coincidem porque
a execução foi **contínua, sem interrupção** — nenhuma das duas janelas tem pausa no meio.

Isso é a exceção, não a regra: tempo de parede normalmente **não** é esforço, e uma task "aberta"
por seis horas pode ter tido vinte minutos de trabalho e um almoço no meio. Por isso as duas chaves
existem separadas, e a `duracao_observada` nunca substitui o `real` — aqui elas apenas têm o mesmo
valor, e o registro diz por quê.

**Ressalva de comparabilidade, para quem for calibrar em cima disto:** as duas entradas vêm de
execução por agente, em sessão não interativa, num diff de 6 linhas de produto. Um `real` de 0,12 h
não descreve o esforço que a mesma task custaria a uma pessoa, e comparar estas entradas com
entradas de origem humana mistura duas populações. Se o projeto passar a registrar as duas origens,
vale separá-las antes de calcular fator.

## Calibração por tipo de task

`desvio_medio` é a média dos desvios das entradas encerradas daquele tipo. `1,0` é o alvo; `1,4` significa que aquele tipo de task leva, em média, 40% a mais que o estimado.

`calibracao: []` — **nenhum fator é calculável ainda**. Sem `00-ESTIMATIVA.md`, não há estimado com
que comparar o real, então nenhuma das duas entradas produz desvio. E, mesmo que produzisse, a regra
do fator exige **3 ou mais** entradas encerradas do mesmo tipo: há uma de `teste` e uma de `ui`.

**Regra do fator.** O desvio de um tipo só vira fator de correção nas estimativas seguintes a partir de **3 entradas encerradas** daquele tipo — abaixo disso é ruído. Quando aplicado, o fator é **sempre declarado na saída da estimativa**, nunca embutido em silêncio.

## Como se calcula o desvio

```
desvio_task = real / media_task_estimada          # media_task = (o + 4m + p) / 6
desvio_medio_do_tipo = media dos desvio_task daquele tipo
```

## Como esta tabela é alimentada

Ao concluir cada task na F6, o esforço real daquela task é anotado. Ao fim do trabalho, a F6 acrescenta as entradas aqui e recalcula a tabela de calibração por tipo. Detalhe em `references/06-execucao.md`; o uso na estimativa, em `references/07-estimativa.md`.
MD
}

# HISTORICO de um trabalho ANTERIOR, já versionado: base do caminho tracked.
historico_anterior() { # <arquivo>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'MD'
---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: 2026-09-01
unidade: h
entradas:
  - trabalho_id: trabalho-anterior
    task_id: T-01.01
    tipo_task: api
    area: cadastro
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 1.5
    desvio: null
    registrado_em: 2026-09-01
calibracao: []
---

# Histórico de esforço — calibração das estimativas

## Entradas

| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio |
|---|---|---|---|---|---|---|---|---|
| trabalho-anterior | T-01.01 | api | cadastro | — | — | — | 1,5 h | — |
MD
}

# HISTORICO já versionado com um trabalho anterior calibrado — base do grupo
# tracked (DM-175). Tem as três linhas de instrução do template (com o literal
# {{...}}), calibração por tipo nas duas representações, sinais não vazios e
# uma entrada (T-03.01, sem F3.5) que só existe no frontmatter.
historico_calibrado() { # <arquivo>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'MD'
---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: 2026-09-01
unidade: h
entradas:
  - trabalho_id: trabalho-anterior
    task_id: T-01.01
    tipo_task: api
    area: cadastro
    sinais: [sem_cobertura, integracao_externa]
    estimado_min: 2
    estimado_max: 4
    estimado_media: 3
    real: 3.3
    desvio: 1.1
    registrado_em: 2026-09-01
  - trabalho_id: trabalho-anterior
    task_id: T-01.02
    tipo_task: api
    area: cadastro
    sinais: []
    estimado_min: 1
    estimado_max: 3
    estimado_media: 2
    real: 2.6
    desvio: 1.3
    registrado_em: 2026-09-01
  - trabalho_id: trabalho-anterior
    task_id: T-02.01
    tipo_task: ui
    area: tela de cadastro
    sinais: []
    estimado_min: 1
    estimado_max: 2
    estimado_media: 1.5
    real: 1.5
    duracao_observada: 2.25
    desvio: 1.0
    registrado_em: 2026-09-02
  - trabalho_id: trabalho-anterior
    task_id: T-03.01
    tipo_task: infra
    area: pipeline
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.5
    desvio: null
    registrado_em: 2026-09-02
calibracao:
  - tipo_task: api
    entradas: 2
    desvio_medio: 1.2
    fator_ativo: false
  - tipo_task: ui
    entradas: 1
    desvio_medio: 1.0
    fator_ativo: false
---

> Substitua TODOS os marcadores `{{...}}`. Roteiro operacional em `references/07-estimativa.md`.
> Este arquivo é do PROJETO, não de um trabalho: vive em `docs/sprintx/estimativas/HISTORICO.md` e acumula entradas de todos os trabalhos. Por isso `trabalho_id` no cabeçalho é `null` — o `trabalho_id` de cada linha vive dentro de `entradas:`.
> Este é o único arquivo da skill que é APENDADO, nunca sobrescrito. Trabalho novo acrescenta entradas; entrada antiga não se apaga nem se reescreve.

# Histórico de esforço — calibração das estimativas

## Entradas

| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio |
|---|---|---|---|---|---|---|---|---|
| trabalho-anterior | T-01.01 | api | cadastro | sem_cobertura, integracao_externa | 2–4 h | 3 h | 3,3 h | 1,1 |
| trabalho-anterior | T-01.02 | api | cadastro | — | 1–3 h | 2 h | 2,6 h | 1,3 |
| trabalho-anterior | T-02.01 | ui | tela de cadastro | — | 1–2 h | 1,5 h | 1,5 h | 1,0 |

A T-03.01 do trabalho anterior rodou sem a F3.5 e ficou só no frontmatter.

## Calibração por tipo de task

| Tipo de task | Entradas | Desvio médio | Fator ativo? |
|---|---|---|---|
| api | 2 | 1,2 | não — menos de 3 entradas |
| ui | 1 | 1,0 | não — menos de 3 entradas |

**Regra do fator.** O desvio de um tipo só vira fator de correção a partir de **3 entradas encerradas** daquele tipo.
MD
}

tasks_sprint() { # <arquivo> <task> <cria> <altera>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: $TRAB
tasks:
  - id: $2
    titulo: Task $2
    status: pendente
    suite: nao_executada
    arquivos:
      cria: [$3]
      altera: [$4]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
    criterio_aceite: rotulo correto
---
YAML
}

artefato() { # <arquivo> <kind>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: $2
trabalho_id: $TRAB
---
conteudo inicial
YAML
}

# O projeto antes do primeiro trabalho SprintX terminar: HEAD sem HISTORICO,
# plano e entrega versionados, produto já no HEAD.
repo_c7c() { # <dir> [anterior]
  local dir="$1" base="${2:-}"
  git init -q -b "$BRANCH" "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src test "docs/entregas/$TRAB"
    printf 'export const rotulo = "parecer";\n' > src/rotulo.js
    artefato "$PASTA/ORQUESTRADOR.md" orquestrador
    artefato "$PASTA/00-PLANEJAMENTO.md" planejamento
    tasks_sprint "$PASTA/sprint-01/tasks.md" T-01.01 test/rotulo.test.js ''
    tasks_sprint "$PASTA/sprint-02/tasks.md" T-02.01 '' src/rotulo.js
    cat > "$ENT" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: $TRAB
entregue_por: mergex
estado: aberto
versionado: true
branch: $BRANCH
branch_base: main
commits: []
desvios: []
criado_em: 2026-09-26
atualizado_em: 2026-09-26
---
YAML
    [ "$base" = anterior ] && historico_anterior "$HIST"
    [ "$base" = calibrado ] && historico_calibrado "$HIST"
    git add -A
    git commit -qm 'chore: base'
  )
}

conclui() { # <repo> <task>
  sed -i "/id: $2/,/suite:/ { s/status: pendente/status: concluida/; s/suite: nao_executada/suite: verde/ }" \
    "$1/$PASTA/sprint-0${2:3:1}/tasks.md"
}

# O estado que a F6 deixa ao fim do trabalho: tasks concluídas, orquestrador e
# entrega atualizados, FECHAMENTO novo e o primeiro HISTORICO — tudo dirty,
# stage vazio.
fim_da_f6() { # <repo>
  local repo="$1"
  conclui "$repo" T-01.01
  conclui "$repo" T-02.01
  printf 'estagio final: f6\n' >> "$repo/$PASTA/ORQUESTRADOR.md"
  artefato "$repo/$PASTA/FECHAMENTO.md" fechamento
  printf 'append da ultima task\n' >> "$repo/$ENT"
  historico_c7c "$repo/$HIST"
}

metodo() { # <repo> <acao> <checkpoint>
  (
    cd "$1" || exit 1
    bash "$PERSISTE" "$2" --entrega "$ENT" --origem sprintx --trabalho "$TRAB" --checkpoint "$3"
  )
}

commits() { git -C "$1" rev-list --count HEAD; }
staged() { git -C "$1" diff --cached --name-only; }
trava_livre() { [ ! -e "$1/$(git -C "$1" rev-parse --git-path index).mergex-e1.lock" ]; }
no_head() { git -C "$1" ls-tree --name-only HEAD -- "$HIST"; }
nomes_head() { git -C "$1" show --format= --name-only HEAD | sed '/^$/d' | LC_ALL=C sort; }

# Troca a primeira linha exatamente igual a <antes> (ou a N-ésima) por <depois>.
troca_linha() { # <arquivo> <antes> <depois> [ocorrencia]
  A="$2" B="$3" N="${4:-1}" awk '$0 == ENVIRON["A"] && ++n == ENVIRON["N"] { print ENVIRON["B"]; next } { print }' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
insere_antes() { # <arquivo> <linha alvo> <texto>
  A="$2" B="$3" awk '$0 == ENVIRON["A"] && !feito { print ENVIRON["B"]; feito = 1 } { print }' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
insere_depois() { # <arquivo> <linha alvo> <texto>
  A="$2" B="$3" awk '{ print } $0 == ENVIRON["A"] && !feito { print ENVIRON["B"]; feito = 1 }' \
    "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

LINHA_T0101='| issue-123-rotulo-parecer | T-01.01 | teste | accountability | — | — | — | 0,12 h | — |'
LINHA_T0201='| issue-123-rotulo-parecer | T-02.01 | ui | accountability | — | — | — | 0,13 h | — |'

grupo_central() {
  local repo saida rc erro esperado
  printf '\nCENTRAL — o C7-C reproduzido: primeira feature, HISTORICO criado pela sprintx\n'
  repo="$D/c7c"; repo_c7c "$repo"; fim_da_f6 "$repo"

  igual 'HEAD nao contem o HISTORICO global' "$(no_head "$repo")" ''
  igual 'HISTORICO nasce untracked, como a sprintx o deixa' \
    "$(git -C "$repo" status --porcelain -- "$HIST")" "?? $HIST"
  igual 'stage vazio antes do checkpoint' "$(staged "$repo")" ''
  cp "$repo/$HIST" "$D/c7c-hist.md"

  saida="$(metodo "$repo" --persistir pre-e2 2>"$D/c7c.err")"; rc=$?
  erro="$(cat "$D/c7c.err")"
  case "$erro" in *'não tem base'*) falha "pre-e2 ainda recusa o HISTORICO untracked: $erro" ;;
    *) ok 'pre-e2 nao devolve mais "untracked nao tem base"' ;; esac
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Eq '^commit=[0-9a-f]{40}$' \
    && ok 'pre-e2 prova ownership integral e cria o commit de metodo' \
    || falha "pre-e2 nao persistiu a primeira criacao (rc=$rc; $saida; $erro)"
  esperado="$(printf '%s\n' "$HIST" "$ENT" "$PASTA/FECHAMENTO.md" "$PASTA/ORQUESTRADOR.md" \
    "$PASTA/sprint-01/tasks.md" "$PASTA/sprint-02/tasks.md" | LC_ALL=C sort)"
  igual 'commit de metodo leva o HISTORICO e os demais artefatos corretos' "$(nomes_head "$repo")" "$esperado"
  git -C "$repo" show "HEAD:$HIST" | cmp -s - "$D/c7c-hist.md" \
    && ok 'HISTORICO versionado e byte a byte o que a sprintx escreveu' \
    || falha 'HISTORICO versionado difere do arquivo da working tree'
  (cd "$repo" && bash "$CONTRATO" --validar-metodo --trabalho "$TRAB" --checkpoint pre-e2 --commit HEAD) \
    >/dev/null 2>&1 && ok 'commit satisfaz o contrato de metodo (Trabalho + Metodo, sem Task)' \
    || falha 'commit da primeira criacao viola o contrato de metodo'
  igual 'stage volta vazio' "$(staged "$repo")" ''
  trava_livre "$repo" && ok 'trava C5 liberada depois do commit' || falha 'trava C5 ficou presa'
  metodo "$repo" --verificar pre-e2 >/dev/null 2>&1
  igual '--verificar pre-e2 passa depois da primeira criacao' "$?" 0
  git -C "$repo" ls-files --error-unmatch -- "$HIST" >/dev/null 2>&1 \
    && ok 'HISTORICO passa a ser tracked' || falha 'HISTORICO continuou untracked'

  # Depois da primeira criação, o checkpoint seguinte cai na prova contra HEAD:
  # reescrever uma linha já versionada é aceito pela prova integral, mas não
  # pelo caminho tracked — e é o tracked que tem de decidir.
  troca_linha "$repo/$HIST" '    real: 0.12' '    real: 0.50'
  metodo "$repo" --persistir pre-e6 >/dev/null 2>"$D/c7c-e6.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'remove ou reescreve' "$D/c7c-e6.err" \
    && ok 'pre-e6 seguinte usa o caminho tracked e barra reescrita' \
    || falha "pre-e6 nao caiu no caminho tracked (rc=$rc; $(cat "$D/c7c-e6.err"))"
  git -C "$repo" restore --worktree -- "$HIST"
  troca_linha "$repo/$HIST" 'atualizado_em: 2026-09-26' 'atualizado_em: 2026-09-27'
  printf 'atencao\n' > "$repo/docs/entregas/$TRAB/ATENCAO.md"
  metodo "$repo" --persistir pre-e6 >/dev/null 2>&1; rc=$?
  esperado="$(printf '%s\n' "$HIST" "docs/entregas/$TRAB/ATENCAO.md" | LC_ALL=C sort)"
  [ "$rc" = 0 ] && [ "$(nomes_head "$repo")" = "$esperado" ] \
    && ok 'pre-e6 seguinte persiste acrescimo valido pelo caminho tracked' \
    || falha "pre-e6 tracked falhou (rc=$rc; $(nomes_head "$repo"))"
}

grupo_checkpoints() {
  local repo rc antes
  printf '\nCHECKPOINTS — a primeira criacao onde o lifecycle precisar\n'

  repo="$D/listar"; repo_c7c "$repo"; fim_da_f6 "$repo"
  metodo "$repo" --listar pre-e2 2>/dev/null | grep -Fxq "$HIST" \
    && ok '--listar inclui o HISTORICO inicial provado' || falha '--listar nao inclui o HISTORICO inicial'
  metodo "$repo" --verificar pre-e2 >/dev/null 2>"$D/verificar.err"; rc=$?
  [ "$rc" = 1 ] && grep -Fq "  - $HIST" "$D/verificar.err" \
    && ok '--verificar acusa o HISTORICO inicial como pendente, sem erro de base' \
    || falha "--verificar nao tratou o HISTORICO inicial como pendente (rc=$rc)"

  repo="$D/pre-e6"; repo_c7c "$repo"; fim_da_f6 "$repo"
  printf 'pr\n' > "$repo/docs/entregas/$TRAB/PR.md"
  metodo "$repo" --persistir pre-e6 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && ok 'pre-e6 persiste a primeira criacao sem pre-e2 anterior' \
    || falha "pre-e6 nao persistiu a primeira criacao (rc=$rc)"

  repo="$D/e8-valido"; repo_c7c "$repo"; fim_da_f6 "$repo"
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  metodo "$repo" --persistir e8 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && git -C "$repo" show "HEAD:$ENT" | grep -Fq 'estado: bloqueado' \
    && ok 'e8 bloqueado persiste a primeira criacao sem checkpoint anterior' \
    || falha "e8 bloqueado nao persistiu a primeira criacao (rc=$rc)"
  metodo "$repo" --verificar e8 >/dev/null 2>&1
  igual 'e8 deixa o metodo limpo' "$?" 0

  repo="$D/e8-invalido"; repo_c7c "$repo"; fim_da_f6 "$repo"
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  troca_linha "$repo/$HIST" "  - trabalho_id: $TRAB" '  - trabalho_id: outro-trabalho' 2
  cp "$repo/$HIST" "$D/e8-invalido.md"
  antes="$(commits "$repo")"
  metodo "$repo" --persistir e8 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(commits "$repo")" = "$antes" ] && [ -z "$(staged "$repo")" ] \
    && trava_livre "$repo" && cmp -s "$repo/$HIST" "$D/e8-invalido.md" \
    && ok 'e8 com primeira criacao invalida falha fechado, sem add, commit ou trava' \
    || falha "e8 aceitou primeira criacao invalida (rc=$rc)"
}

# Cada negativo roda numa cópia nova do C7-C. Nada pode virar commit, o stage
# fica vazio, a trava da execução é liberada e o arquivo fica intacto.
nega() { # <descricao> <preparo>
  local descricao="$1" preparo="$2" repo rc antes
  repo="$D/nega-$(printf '%s' "$descricao" | tr -c 'a-z0-9' '-')"
  repo_c7c "$repo"; fim_da_f6 "$repo"
  "$preparo" "$repo"
  [ -e "$repo/$HIST" ] && cp -P "$repo/$HIST" "$D/nega.antes" 2>/dev/null
  antes="$(commits "$repo")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/nega.err"; rc=$?
  if [ "$rc" != 0 ] && grep -Fq 'HISTORICO global inicial' "$D/nega.err" \
     && [ "$(commits "$repo")" = "$antes" ] && [ -z "$(staged "$repo")" ] \
     && trava_livre "$repo" && [ -z "$(no_head "$repo")" ] \
     && { [ ! -f "$repo/$HIST" ] || cmp -s "$repo/$HIST" "$D/nega.antes"; }; then
    ok "barra: $descricao"
  else
    falha "nao barrou: $descricao (rc=$rc; $(cat "$D/nega.err"))"
  fi
}

p_outro() { sed -i "s/^  - trabalho_id: $TRAB\$/  - trabalho_id: outro-trabalho/" "$1/$HIST"; }
p_mistura() { troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" '  - trabalho_id: outro-trabalho' 2; }
p_estranha() { troca_linha "$1/$HIST" '    task_id: T-02.01' '    task_id: T-03.01'; }
p_nao_concluida() { sed -i 's/status: concluida/status: bloqueada/' "$1/$PASTA/sprint-02/tasks.md"; }
p_duplicada() { troca_linha "$1/$HIST" '    task_id: T-02.01' '    task_id: T-01.01'; }
p_header() { troca_linha "$1/$HIST" 'trabalho_id: null' "trabalho_id: $TRAB"; }
p_kind() { troca_linha "$1/$HIST" 'kind: estimativa_historico' 'kind: estimativa'; }
p_tool() { troca_linha "$1/$HIST" 'expx_tool: sprintx' 'expx_tool: runx'; }
p_symlink() { # o alvo é um HISTORICO válido: só o link simbólico reprova
  local alvo="$D/alvo-$(basename "$1").md"
  mv "$1/$HIST" "$alvo"
  ln -s "$alvo" "$1/$HIST"
}
p_topo_extra() { insere_antes "$1/$HIST" 'entradas:' 'origem: outro-trabalho'; }
p_chave_entrada() { insere_depois "$1/$HIST" '    task_id: T-01.01' '    nota: herdada'; }
p_calibracao_buraco() {
  troca_linha "$1/$HIST" 'calibracao: []' 'calibracao:'
  insere_depois "$1/$HIST" 'calibracao:' '  - tipo_task: ui
    entradas: 1
    trabalho_id: outro-trabalho'
}
p_calibracao_chave_extra() { # item de calibração válido: só a chave extra denuncia
  troca_linha "$1/$HIST" 'calibracao: []' 'calibracao:
  - tipo_task: ui
    entradas: 1
    desvio_medio: 1.0
    fator_ativo: false
    trabalho_id: outro-trabalho'
}
p_linha_alheia() { # só a primeira coluna denuncia: task concluída, sem duplicata
  troca_linha "$1/$HIST" "$LINHA_T0201" '| outro-trabalho | T-02.01 | ui | accountability | — | — | — | 0,13 h | — |'
}
p_linha_duplicada() { insere_depois "$1/$HIST" "$LINHA_T0201" "$LINHA_T0101"; }
p_stage() {
  printf 'mudanca\n' >> "$1/src/rotulo.js"
  git -C "$1" add -- src/rotulo.js
}

grupo_negativos() {
  local repo rc antes staged_antes
  printf '\nNEGATIVOS — primeira criacao sem ownership integral falha fechado\n'
  nega 'entrada de outro trabalho' p_outro
  nega 'mistura de trabalho atual e outro' p_mistura
  nega 'task_id fora do trabalho atual' p_estranha
  nega 'task nao concluida' p_nao_concluida
  nega 'entrada duplicada' p_duplicada
  nega 'header trabalho_id nao-null' p_header
  nega 'kind errado' p_kind
  nega 'expx_tool errado' p_tool
  nega 'symlink no lugar do arquivo' p_symlink
  nega 'chave de topo nao atribuivel' p_topo_extra
  nega 'chave de entrada fora do contrato' p_chave_entrada
  nega 'calibracao usada como buraco para outro trabalho' p_calibracao_buraco
  nega 'calibracao valida com chave extra de outro trabalho' p_calibracao_chave_extra
  nega 'linha da tabela de outro trabalho' p_linha_alheia
  nega 'linha duplicada na tabela de entradas' p_linha_duplicada

  # Path parecido: não é o HISTORICO, não é método, não entra em commit nenhum.
  repo="$D/parecido"; repo_c7c "$repo"
  historico_c7c "$repo/docs/sprintx/estimativas/historico.md"
  historico_c7c "$repo/docs/sprintx/HISTORICO.md"
  antes="$(commits "$repo")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(commits "$repo")" = "$antes" ] && [ -z "$(staged "$repo")" ] \
    && [ -n "$(git -C "$repo" status --porcelain -- docs/sprintx/estimativas/historico.md)" ] \
    && [ -n "$(git -C "$repo" status --porcelain -- docs/sprintx/HISTORICO.md)" ] \
    && ok 'path parecido nao e tratado como HISTORICO nem commitado' \
    || falha "path parecido foi versionado (rc=$rc)"

  # HEAD já contém o HISTORICO, mas o índice o perdeu: não é primeira criação.
  repo="$D/head-contem"; repo_c7c "$repo" anterior
  git -C "$repo" rm -q --cached -- "$HIST"
  metodo "$repo" --listar pre-e2 >/dev/null 2>"$D/head.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'existe em HEAD' "$D/head.err" \
    && ok 'HEAD com HISTORICO nunca cai no caminho primeira criacao' \
    || falha "estado anomalo caiu no caminho primeira criacao (rc=$rc; $(cat "$D/head.err"))"
  staged_antes="$(staged "$repo")"; antes="$(commits "$repo")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(commits "$repo")" = "$antes" ] && [ "$(staged "$repo")" = "$staged_antes" ] \
    && ok 'persistir no estado anomalo para sem commit e sem mexer no stage' \
    || falha "estado anomalo foi persistido (rc=$rc)"

  # Stage preenchido: C5/DM-166 vencem antes de qualquer prova.
  repo="$D/stage"; repo_c7c "$repo"; fim_da_f6 "$repo"; p_stage "$repo"
  staged_antes="$(staged "$repo")"; antes="$(commits "$repo")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && [ "$(commits "$repo")" = "$antes" ] && [ "$(staged "$repo")" = "$staged_antes" ] \
    && [ "$(git -C "$repo" status --porcelain -- "$HIST")" = "?? $HIST" ] && trava_livre "$repo" \
    && ok 'stage preenchido barra a primeira criacao sem adotar nem limpar' \
    || falha "primeira criacao aceitou stage previo (rc=$rc; stage=$(staged "$repo"))"

  # Segredo: a prova de ownership não substitui o gate.
  repo="$D/segredo"; repo_c7c "$repo"; fim_da_f6 "$repo"
  troca_linha "$repo/$HIST" '    area: accountability' "    area: $(printf 'sk-%s' 'abcdef1234567890QRS')"
  antes="$(commits "$repo")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/segredo.err"; rc=$?
  [ "$rc" != 0 ] && [ "$(commits "$repo")" = "$antes" ] && grep -Fq 'segredo' "$D/segredo.err" \
    && trava_livre "$repo" \
    && ok 'gate de segredo continua barrando a primeira criacao' \
    || falha "primeira criacao pulou o gate de segredo (rc=$rc)"
}

# Cada positivo roda numa cópia nova do C7-C com a variação aplicada: o pre-e2
# persiste, o HISTORICO entra byte a byte, stage vazio, trava livre e o
# --verificar seguinte fica limpo.
aceita() { # <descricao> <preparo>
  local descricao="$1" preparo="$2" repo rc saida
  repo="$D/aceita-$(printf '%s' "$descricao" | tr -c 'a-z0-9' '-')"
  repo_c7c "$repo"; fim_da_f6 "$repo"
  "$preparo" "$repo"
  cp "$repo/$HIST" "$D/aceita.antes"
  saida="$(metodo "$repo" --persistir pre-e2 2>"$D/aceita.err")"; rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Eq '^commit=[0-9a-f]{40}$' \
     && git -C "$repo" show "HEAD:$HIST" | cmp -s - "$D/aceita.antes" \
     && [ -z "$(staged "$repo")" ] && trava_livre "$repo" \
     && metodo "$repo" --verificar pre-e2 >/dev/null 2>&1; then
    ok "aceita: $descricao"
  else
    falha "nao aceitou: $descricao (rc=$rc; $(cat "$D/aceita.err"))"
  fi
}

# DEVEM PASSAR — forma permitida pelo contrato publicado da sprintx.
v_sinais_inline() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: [sem_cobertura, integracao_externa]'; }
v_sinais_bloco() {
  troca_linha "$1/$HIST" '    sinais: []' '    sinais:
      - sem_cobertura
      - integracao_externa'
}
v_sinais_bloco_aspas() {
  troca_linha "$1/$HIST" '    sinais: []' '    sinais:
      - "sem_cobertura"
      - integracao_externa  # declarado na estimativa' 2
}
v_paragrafo() {
  insere_depois "$1/$HIST" "$LINHA_T0201" '
Observação da equipe: as duas tasks rodaram no mesmo dia, uma depois da outra.'
}
v_heading() {
  insere_antes "$1/$HIST" '## Calibração por tipo de task' '## Notas da equipe

Nenhuma interrupção relevante durante a execução.
'
}
v_tabela_humana() { # mesmo cabeçalho da oficial, mas fora de "## Entradas"
  printf '\n## Comparação com outro projeto\n\n| Trabalho | Task | Real |\n|---|---|---|\n| outro-trabalho | T-07.03 | 3 h |\n' \
    >> "$1/$HIST"
}
v_tabela_humana_na_secao() { # depois da oficial, com outro cabeçalho
  insere_depois "$1/$HIST" "$LINHA_T0201" '
| Nota | Valor |
|---|---|
| revisão | sem ressalva |'
}
v_mencao_task() {
  printf '\nA T-99.99 citada aqui é só um exemplo de id, não uma entrada.\n' >> "$1/$HIST"
}
v_mencao_trabalho() {
  printf '\nNo YAML de outro projeto se lê trabalho_id: outro-trabalho, e isso não é entrada daqui.\n' >> "$1/$HIST"
}
v_exemplo_codigo() {
  printf '\n```yaml\n  - trabalho_id: outro-trabalho\n    task_id: T-99.99\n```\n' >> "$1/$HIST"
}
v_comentario_linha() { insere_antes "$1/$HIST" 'calibracao: []' '# outro-trabalho registrou aqui'; }
v_comentario_fim() {
  troca_linha "$1/$HIST" '    real: 0.12' '    real: 0.12  # medido no rastro, sem pausa'
  troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB # dono desta entrada" 2
  troca_linha "$1/$HIST" 'calibracao: []' 'calibracao: [] # sem estimativa, sem fator'
}
v_comentario_recuado() {
  insere_depois "$1/$HIST" '    task_id: T-01.01' '      # comentario com recuo arbitrario'
}

# DEVEM BARRAR — ownership ou estrutura.
p_marcador_tabela() {
  troca_linha "$1/$HIST" "$LINHA_T0201" \
    '| issue-123-rotulo-parecer | T-02.01 | {{tipo_task}} | accountability | — | — | — | 0,13 h | — |'
}
p_marcador_fm() { troca_linha "$1/$HIST" '    area: accountability' '    area: {{area}}'; }
p_marcador_fm_comentario() { insere_antes "$1/$HIST" 'calibracao: []' '# preencher {{tipo_task}}'; }
# DM-175: "{{...}}" em prosa humana é texto, não dado pendente. O próprio
# TEMPLATE-HISTORICO da sprintx diz "Substitua TODOS os marcadores `{{...}}`".
v_marcador_prosa() {
  printf '\n{{Trabalho que rodou sem a F3.5 entra assim}}\n' >> "$1/$HIST"
}
# O arquivo criado do template com todos os dados substituídos, mas com as
# três linhas de instrução do template mantidas logo depois do frontmatter.
v_instrucao_template() {
  insere_antes "$1/$HIST" '# Histórico de esforço — calibração das estimativas' \
'> Substitua TODOS os marcadores `{{...}}`. Roteiro operacional em `references/07-estimativa.md`.
> Este arquivo é do PROJETO, não de um trabalho: vive em `docs/sprintx/estimativas/HISTORICO.md` e acumula entradas de todos os trabalhos. Por isso `trabalho_id` no cabeçalho é `null` — o `trabalho_id` de cada linha vive dentro de `entradas:`.
> Este é o único arquivo da skill que é APENDADO, nunca sobrescrito. Trabalho novo acrescenta entradas; entrada antiga não se apaga nem se reescreve.
'
}
p_marcador_calibracao() { # linha-modelo da tabela oficial de calibração
  insere_depois "$1/$HIST" '`calibracao: []` — **nenhum fator é calculável ainda**. Sem `00-ESTIMATIVA.md`, não há estimado com' \
'que comparar o real.

| Tipo de task | Entradas | Desvio médio | Fator ativo? |
|---|---|---|---|
| {{tipo_task}} | {{n}} | {{desvio}} | não — menos de 3 entradas |
'
}
# Isolados: só a regra nomeada barra; a tabela oficial não denuncia.
p_outro_sem_linha() {
  troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" '  - trabalho_id: outro-trabalho' 2
  grep -vxF -- "$LINHA_T0201" "$1/$HIST" > "$1/$HIST.tmp" && mv "$1/$HIST.tmp" "$1/$HIST"
}
p_real_texto() { troca_linha "$1/$HIST" '    real: 0.12' '    real: doze minutos'; }
p_estimado_texto() { troca_linha "$1/$HIST" '    estimado_max: null' '    estimado_max: tres'; }
p_registrado_formato() { troca_linha "$1/$HIST" '    registrado_em: 2026-09-26' '    registrado_em: 26/09/2026'; }
p_sem_area() { troca_linha "$1/$HIST" '    area: accountability' '    area:'; }
p_sem_real() { grep -vxF '    real: 0.13' "$1/$HIST" > "$1/$HIST.tmp" && mv "$1/$HIST.tmp" "$1/$HIST"; }
p_cabecalho_renomeado() {
  troca_linha "$1/$HIST" '| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio |' \
    '| Job | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio |'
}
p_segunda_oficial_alheia() { # sub-heading não tira a tabela da seção Entradas
  insere_depois "$1/$HIST" "$LINHA_T0201" '
### Mais entradas

| Trabalho | Task | Tipo |
|---|---|---|
| outro-trabalho | T-02.01 | ui |'
}
p_tabela_sem_barra() { # GFM renderiza sem a barra inicial: não pode escapar da prova
  insere_depois "$1/$HIST" "$LINHA_T0201" '
Trabalho | Task | Tipo
---|---|---
outro-trabalho | T-02.01 | ui'
}
p_sinais_escalar() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: sem_cobertura'; }
p_sinais_aberta() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: [sem_cobertura, integracao_externa'; }
p_sinais_nula() { troca_linha "$1/$HIST" '    sinais: []' '    sinais:'; }
p_sinais_recuo() {
  troca_linha "$1/$HIST" '    sinais: []' '    sinais:
      - sem_cobertura
        - integracao_externa'
}
p_sinais_mapa() {
  troca_linha "$1/$HIST" '    sinais: []' '    sinais:
      - trabalho_id: outro-trabalho'
}
p_sinais_aninhada() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: [sem_cobertura, [integracao_externa]]'; }
p_sinais_item_vazio() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: [sem_cobertura, , integracao_externa]'; }
p_sinais_virgula() {
  troca_linha "$1/$HIST" '    sinais: []' '    sinais:
      - sem_cobertura, integracao_externa'
}
p_chave_sem_espaco() { troca_linha "$1/$HIST" 'kind: estimativa_historico' 'kind:estimativa_historico'; }
p_chave_recuada() { troca_linha "$1/$HIST" '    real: 0.12' '      real: 0.12'; }
p_item_recuo() { troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" "    - trabalho_id: $TRAB" 2; }
p_aspas_abertas() { troca_linha "$1/$HIST" '    area: accountability' '    area: "accountability'; }
p_escalar_bloco() {
  troca_linha "$1/$HIST" '    area: accountability' '    area: |
      accountability'
}
p_fm_aberto() { awk '$0 == "---" && ++n == 2 { next } { print }' "$1/$HIST" > "$1/$HIST.tmp" && mv "$1/$HIST.tmp" "$1/$HIST"; }
# O relaxamento de comentário não pode esconder o valor efetivo.
p_hash_colado() { troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB#outro-trabalho"; }
p_comentario_disfarca() {
  troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" "  - trabalho_id: outro-trabalho # $TRAB" 2
}
p_comentario_task() { troca_linha "$1/$HIST" '    task_id: T-02.01' '    task_id: T-03.01 # T-02.01'; }
p_aspas_com_hash() { troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" "  - trabalho_id: \"$TRAB # x\""; }

# A8 — o mesmo ownership do C7-C noutra formatação válida: sinais em bloco e
# uma observação humana a mais. A mergex não pode depender do byte do piloto.
historico_c7c_variante() { # <arquivo>
  historico_c7c "$1"
  troca_linha "$1" '    sinais: []' '    sinais:
      - sem_cobertura
      - arquivo_novo_isolado'
  troca_linha "$1" '    sinais: []' '    sinais:
      - sem_cobertura'
  insere_depois "$1" "$LINHA_T0201" '
> Observação humana: a T-02.01 dependeu do rótulo criado na T-01.01.'
}

grupo_contrato() {
  local repo rc
  printf '\nCONTRATO — diferencial contra o contrato publicado da sprintx (A7/A8)\n'
  aceita '1 sinais inline' v_sinais_inline
  aceita '2 sinais multilinha' v_sinais_bloco
  aceita '2b sinais multilinha com aspas e comentario' v_sinais_bloco_aspas
  aceita '3 paragrafo humano adicional' v_paragrafo
  aceita '4 heading humano adicional' v_heading
  aceita '5 tabela humana com cabecalho igual fora de entradas' v_tabela_humana
  aceita '5b tabela humana depois da oficial' v_tabela_humana_na_secao
  aceita '6 mencao a T-99-99 em frase humana' v_mencao_task
  aceita '6b mencao a trabalho-id em frase humana' v_mencao_trabalho
  aceita '6c exemplo em bloco de codigo' v_exemplo_codigo
  aceita '7 comentario YAML de linha inteira' v_comentario_linha
  aceita '7b comentario YAML ao fim da linha' v_comentario_fim
  aceita '7c comentario YAML com recuo arbitrario' v_comentario_recuado
  aceita '8c literal {{...}} em prosa humana e texto, nao dado' v_marcador_prosa
  aceita '8d criado do template, dados substituidos, instrucao {{...}} mantida' v_instrucao_template

  nega '8 marcador na linha-modelo da tabela' p_marcador_tabela
  nega '8b marcador no frontmatter' p_marcador_fm
  nega '8e marcador em comentario do frontmatter' p_marcador_fm_comentario
  nega '8f marcador na linha-modelo da tabela de calibracao' p_marcador_calibracao
  nega '9 entradas trabalho-id de outro trabalho' p_outro
  nega '9b outro trabalho sem linha na tabela oficial' p_outro_sem_linha
  nega '9c real nao numerico' p_real_texto
  nega '9d estimado nao numerico' p_estimado_texto
  nega '9e registrado_em fora de AAAA-MM-DD' p_registrado_formato
  nega '9f entrada sem area' p_sem_area
  nega '9g entrada sem real' p_sem_real
  nega '10 task-id de outro trabalho' p_estranha
  nega '10b task-id nao concluida' p_nao_concluida
  nega '11 duplicata de entrada' p_duplicada
  nega '12 linha de dados da tabela oficial de outro trabalho' p_linha_alheia
  nega '12b tabela oficial sob sub-heading com outro trabalho' p_segunda_oficial_alheia
  nega '12c tabela de entradas com cabecalho renomeado' p_cabecalho_renomeado
  nega '12d tabela de entradas sem barra inicial com outro trabalho' p_tabela_sem_barra
  nega '13 sinais escalar' p_sinais_escalar
  nega '13b sinais inline sem fechamento' p_sinais_aberta
  nega '13c sinais sem valor' p_sinais_nula
  nega '13d sinais com recuo inconsistente' p_sinais_recuo
  nega '13e sinais com item chave-valor' p_sinais_mapa
  nega '13f sinais aninhada' p_sinais_aninhada
  nega '13g sinais com item vazio' p_sinais_item_vazio
  nega '13h sinais com virgula ambigua em bloco' p_sinais_virgula
  nega '14 chave sem espaco depois dos dois pontos' p_chave_sem_espaco
  nega '14b chave de entrada mais recuada' p_chave_recuada
  nega '14c item com recuo inconsistente' p_item_recuo
  nega '14d aspas sem fechamento' p_aspas_abertas
  nega '14e texto multilinha em bloco' p_escalar_bloco
  nega '14f frontmatter sem fechamento' p_fm_aberto
  nega '15 hash colado nao e comentario' p_hash_colado
  nega '15b comentario nao disfarca outro trabalho' p_comentario_disfarca
  nega '15c comentario nao disfarca task estranha' p_comentario_task
  nega '15d hash entre aspas e valor' p_aspas_com_hash

  # A8: o C7-C real já passa no grupo central; a variante tem de passar igual,
  # e o checkpoint seguinte continua no caminho tracked.
  repo="$D/variante"; repo_c7c "$repo"; fim_da_f6 "$repo"
  historico_c7c_variante "$repo/$HIST"
  cp "$repo/$HIST" "$D/variante.md"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/variante.err"; rc=$?
  [ "$rc" = 0 ] && git -C "$repo" show "HEAD:$HIST" | cmp -s - "$D/variante.md" \
    && metodo "$repo" --verificar pre-e2 >/dev/null 2>&1 \
    && ok 'A8: variante C7-C (sinais em bloco + observacao humana) persiste byte a byte' \
    || falha "A8: variante C7-C recusada (rc=$rc; $(cat "$D/variante.err"))"
  troca_linha "$repo/$HIST" 'atualizado_em: 2026-09-26' 'atualizado_em: 2026-09-27'
  metodo "$repo" --persistir pre-e6 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nomes_head "$repo")" = "$HIST" ] \
    && ok 'A8: depois da variante, pre-e6 segue pelo caminho tracked' \
    || falha "A8: pre-e6 depois da variante falhou (rc=$rc)"
}

grupo_subsequente() {
  local repo rc remocoes
  printf '\nSUBSEQUENTE — HISTORICO ja versionado continua provado contra HEAD\n'
  repo="$D/subsequente"; repo_c7c "$repo" anterior
  cp "$repo/$HIST" "$D/anterior.md"
  conclui "$repo" T-01.01
  troca_linha "$repo/$HIST" 'atualizado_em: 2026-09-01' 'atualizado_em: 2026-09-26'
  insere_antes "$repo/$HIST" 'calibracao: []' "  - trabalho_id: $TRAB
    task_id: T-01.01
    tipo_task: teste
    area: accountability
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.12
    desvio: null
    registrado_em: 2026-09-26"
  printf '%s\n' "$LINHA_T0101" >> "$repo/$HIST"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/sub.err"; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && ok 'acrescimo do trabalho atual sobre HISTORICO anterior passa' \
    || falha "caminho tracked recusou acrescimo valido (rc=$rc; $(cat "$D/sub.err"))"
  remocoes="$(git -C "$repo" diff HEAD~1 HEAD -U0 -- "$HIST" | grep -E '^-[^-]' | grep -v '^-atualizado_em:')"
  igual 'evidencia do trabalho anterior preservada byte a byte' "$remocoes" ''
  git -C "$repo" show "HEAD:$HIST" | grep -Fxq '| trabalho-anterior | T-01.01 | api | cadastro | — | — | — | 1,5 h | — |' \
    && ok 'linha do trabalho anterior segue no HEAD' || falha 'linha do trabalho anterior sumiu'

  repo="$D/sub-reescrita"; repo_c7c "$repo" anterior
  troca_linha "$repo/$HIST" '    real: 1.5' '    real: 9.9'
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/sub2.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'remove ou reescreve' "$D/sub2.err" \
    && ok 'controle: reescrever evidencia antiga continua barrando' \
    || falha "caminho tracked aceitou reescrita (rc=$rc)"

  repo="$D/sub-remocao"; repo_c7c "$repo" anterior
  grep -v '^| trabalho-anterior ' "$repo/$HIST" > "$D/sem-linha.md" && cp "$D/sem-linha.md" "$repo/$HIST"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/sub3.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'remove ou reescreve' "$D/sub3.err" \
    && ok 'controle: remover evidencia antiga continua barrando' \
    || falha "caminho tracked aceitou remocao (rc=$rc)"

  repo="$D/sub-alheio"; repo_c7c "$repo" anterior
  insere_antes "$repo/$HIST" 'calibracao: []' '  - trabalho_id: outro-trabalho'
  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok 'controle: acrescimo de outro trabalho continua barrando' \
    || falha 'caminho tracked aceitou entrada de outro trabalho'
}

# ---------------------------------------------------------------------------
# TRACKED — DM-175: append-only quanto às entradas, não quanto aos bytes.
# ---------------------------------------------------------------------------
LINHA_ANT_T0101='| trabalho-anterior | T-01.01 | api | cadastro | sem_cobertura, integracao_externa | 2–4 h | 3 h | 3,3 h | 1,1 |'
LINHA_ANT_T0201='| trabalho-anterior | T-02.01 | ui | tela de cadastro | — | 1–2 h | 1,5 h | 1,5 h | 1,0 |'
LINHA_NOVA_T0101="| $TRAB | T-01.01 | api | accountability | — | 1–3 h | 2 h | 3 h | 1,5 |"
LINHA_NOVA_T0201="| $TRAB | T-02.01 | ui | accountability | sem_cobertura | 1–2 h | 1,5 h | 2,1 h | 1,4 |"

entrada_nova() { # <trabalho> <task> <tipo> [area]
  printf '  - trabalho_id: %s\n    task_id: %s\n    tipo_task: %s\n    area: %s\n    sinais: []\n    estimado_min: 1\n    estimado_max: 3\n    estimado_media: 2\n    real: 3\n    desvio: 1.5\n    registrado_em: 2026-09-26' \
    "$1" "$2" "$3" "${4:-accountability}"
}

# O acréscimo que a F6 do trabalho corrente faz, sem recalibrar nada ainda:
# duas entradas novas e as duas linhas da tabela oficial.
acrescimo_f6() { # <repo>
  local h="$1/$HIST"
  insere_antes "$h" 'calibracao:' "$(entrada_nova "$TRAB" T-01.01 api)
  - trabalho_id: $TRAB
    task_id: T-02.01
    tipo_task: ui
    area: accountability
    sinais: [sem_cobertura]
    estimado_min: 1
    estimado_max: 2
    estimado_media: 1.5
    real: 2.1
    desvio: 1.4
    registrado_em: 2026-09-26"
  insere_depois "$h" "$LINHA_ANT_T0201" "$LINHA_NOVA_T0101
$LINHA_NOVA_T0201"
}

remove_entrada() { # <arquivo> <trabalho> <task> — só no frontmatter
  T="  - trabalho_id: $2" K="    task_id: $3" awk '
    function despeja(   i) { if (n && !(tem_t && tem_k)) for (i = 1; i <= n; i++) print buf[i]; n = 0; tem_t = tem_k = 0 }
    fm < 2 && $0 == "---" { despeja(); fm++; print; next }
    fm == 1 && /^  - / { despeja(); dentro = 1 }
    fm == 1 && /^[a-z]/ { despeja(); dentro = 0 }
    fm == 1 && dentro { buf[++n] = $0; if ($0 == ENVIRON["T"]) tem_t = 1; if ($0 == ENVIRON["K"]) tem_k = 1; next }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

repo_tracked() { # <dir>
  repo_c7c "$1" calibrado
  conclui "$1" T-01.01
  conclui "$1" T-02.01
  acrescimo_f6 "$1"
}

aceita_t() { # <descricao> <preparo>
  local descricao="$1" preparo="$2" repo rc saida
  repo="$D/tracked-aceita-$(printf '%s' "$descricao" | tr -c 'a-z0-9' '-')"
  repo_tracked "$repo"
  "$preparo" "$repo"
  cp "$repo/$HIST" "$D/tracked.antes"
  saida="$(metodo "$repo" --persistir pre-e2 2>"$D/tracked.err")"; rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Eq '^commit=[0-9a-f]{40}$' \
     && nomes_head "$repo" | grep -Fxq "$HIST" \
     && git -C "$repo" show "HEAD:$HIST" | cmp -s - "$D/tracked.antes" \
     && [ -z "$(staged "$repo")" ] && trava_livre "$repo" \
     && metodo "$repo" --verificar pre-e2 >/dev/null 2>&1; then
    ok "tracked aceita: $descricao"
  else
    falha "tracked nao aceitou: $descricao (rc=$rc; $(cat "$D/tracked.err"))"
  fi
}

nega_t() { # <descricao> <preparo> [trecho esperado no erro]
  local descricao="$1" preparo="$2" trecho="${3:-HISTORICO global}" repo rc antes head_antes
  repo="$D/tracked-nega-$(printf '%s' "$descricao" | tr -c 'a-z0-9' '-')"
  repo_tracked "$repo"
  "$preparo" "$repo"
  [ -e "$repo/$HIST" ] && cp "$repo/$HIST" "$D/tracked.antes"
  antes="$(commits "$repo")"; head_antes="$(git -C "$repo" rev-parse "HEAD:$HIST")"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/tracked.err"; rc=$?
  if [ "$rc" != 0 ] && grep -Fq -- "$trecho" "$D/tracked.err" \
     && [ "$(commits "$repo")" = "$antes" ] && [ -z "$(staged "$repo")" ] \
     && trava_livre "$repo" && [ "$(git -C "$repo" rev-parse "HEAD:$HIST")" = "$head_antes" ] \
     && { [ ! -e "$repo/$HIST" ] || cmp -s "$repo/$HIST" "$D/tracked.antes"; }; then
    ok "tracked barra: $descricao"
  else
    falha "tracked nao barrou: $descricao (rc=$rc; $(cat "$D/tracked.err"))"
  fi
}

# DEVEM PASSAR
t_nada() { :; }
t_ui_1_para_2() { troca_linha "$1/$HIST" '    entradas: 1' '    entradas: 2'; }
t_desvio_medio() { troca_linha "$1/$HIST" '    desvio_medio: 1.0' '    desvio_medio: 1.2'; }
t_fator_cruza() {
  troca_linha "$1/$HIST" '    entradas: 2' '    entradas: 3'
  troca_linha "$1/$HIST" '    desvio_medio: 1.2' '    desvio_medio: 1.3'
  troca_linha "$1/$HIST" '    fator_ativo: false' '    fator_ativo: true'
}
t_tabela_calibracao() {
  troca_linha "$1/$HIST" '| api | 2 | 1,2 | não — menos de 3 entradas |' '| api | 3 | 1,3 | sim, aplicado como fator ×1,3 |'
  troca_linha "$1/$HIST" '| ui | 1 | 1,0 | não — menos de 3 entradas |' '| ui | 2 | 1,2 | não — menos de 3 entradas |'
}
t_atualizado_em() { troca_linha "$1/$HIST" 'atualizado_em: 2026-09-01' 'atualizado_em: 2026-09-26'; }
t_comentario() {
  insere_antes "$1/$HIST" 'calibracao:' '# recalibrado ao fechar issue-123-rotulo-parecer'
  insere_depois "$1/$HIST" '## Calibração por tipo de task' '
<!-- recalculada pela F6 em 2026-09-26 -->
Observação da equipe: o tipo api passou a ter fator ativo.'
}
t_sinais_bloco() {
  troca_linha "$1/$HIST" '    sinais: [sem_cobertura, integracao_externa]' '    sinais:
      - sem_cobertura
      - "integracao_externa"  # como na estimativa'
}
t_marcador_prosa() {
  grep -Fq 'Substitua TODOS os marcadores `{{...}}`' "$1/$HIST" || return 1
  insere_depois "$1/$HIST" 'A T-03.01 do trabalho anterior rodou sem a F3.5 e ficou só no frontmatter.' '
Ao copiar o template, os marcadores `{{...}}` são trocados pelos dados; esta frase fica.'
}
t_recalibracao_completa() {
  t_ui_1_para_2 "$1"; t_desvio_medio "$1"; t_fator_cruza "$1"; t_tabela_calibracao "$1"
  t_atualizado_em "$1"; t_comentario "$1"
}

# DEVEM BARRAR
n_remove() { remove_entrada "$1/$HIST" trabalho-anterior T-03.01; }
n_real() { troca_linha "$1/$HIST" '    real: 3.3' '    real: 3.9'; }
n_trabalho() { troca_linha "$1/$HIST" '  - trabalho_id: trabalho-anterior' "  - trabalho_id: $TRAB" 4; }
n_task() { troca_linha "$1/$HIST" '    task_id: T-03.01' '    task_id: T-03.02'; }
n_estimativa() { troca_linha "$1/$HIST" '    estimado_max: 4' '    estimado_max: 5'; }
n_sinais() { troca_linha "$1/$HIST" '    sinais: [sem_cobertura, integracao_externa]' '    sinais: [sem_cobertura]'; }
n_outro_trabalho() { insere_antes "$1/$HIST" 'calibracao:' "$(entrada_nova outro-trabalho T-02.01 ui)"; }
n_nao_concluida() { insere_antes "$1/$HIST" 'calibracao:' "$(entrada_nova "$TRAB" T-03.01 infra)"; }
n_duplicada() { insere_antes "$1/$HIST" 'calibracao:' "$(entrada_nova "$TRAB" T-01.01 api)"; }
n_marcador_fm() { troca_linha "$1/$HIST" '    area: accountability' '    area: {{area}}' 2; }
n_marcador_linha() {
  troca_linha "$1/$HIST" "$LINHA_NOVA_T0201" "| $TRAB | T-02.01 | {{tipo_task}} | accountability | sem_cobertura | 1–2 h | 1,5 h | 2,1 h | 1,4 |"
}
n_remove_linha() { grep -vxF -- "$LINHA_ANT_T0101" "$1/$HIST" > "$1/$HIST.tmp" && mv "$1/$HIST.tmp" "$1/$HIST"; }
n_linha_sem_entrada() { insere_depois "$1/$HIST" "$LINHA_NOVA_T0201" "| $TRAB | T-03.01 | infra | accountability | — | — | — | 1 h | — |"; }
n_apagado() { rm -f "$1/$HIST"; }
n_real_texto() { troca_linha "$1/$HIST" '    real: 2.1' '    real: duas horas'; }
n_cal_fator_sem_base() { troca_linha "$1/$HIST" '    fator_ativo: false' '    fator_ativo: true'; }
n_cal_entradas_texto() { troca_linha "$1/$HIST" '    entradas: 2' '    entradas: duas'; }
n_cal_desvio_texto() { troca_linha "$1/$HIST" '    desvio_medio: 1.2' '    desvio_medio: alto'; }
n_cal_fator_texto() { troca_linha "$1/$HIST" '    fator_ativo: false' '    fator_ativo: sim'; }
n_cal_conta_demais() {
  troca_linha "$1/$HIST" '    entradas: 1' '    entradas: 5'
  troca_linha "$1/$HIST" '    fator_ativo: false' '    fator_ativo: true' 2
}
n_cal_tipo_repetido() { troca_linha "$1/$HIST" '  - tipo_task: ui' '  - tipo_task: api'; }
n_cal_tipo_fora() { troca_linha "$1/$HIST" '  - tipo_task: ui' '  - tipo_task: mobile'; }
n_cal_sem_fator() { grep -vxF '    fator_ativo: false' "$1/$HIST" > "$1/$HIST.tmp" && mv "$1/$HIST.tmp" "$1/$HIST"; }

grupo_tracked() {
  local repo rc
  printf '\nTRACKED — entradas imutaveis, calibracao derivada, prosa humana (DM-175)\n'
  aceita_t '1 HEAD com trabalho A, worktree acrescenta trabalho B' t_nada
  aceita_t '2 calibracao de um tipo muda de 1 para 2 entradas' t_ui_1_para_2
  aceita_t '3 desvio_medio muda' t_desvio_medio
  aceita_t '4 fator_ativo muda ao cruzar 3 entradas' t_fator_cruza
  aceita_t '5 tabela humana de calibracao recalculada' t_tabela_calibracao
  aceita_t '6 atualizado_em muda' t_atualizado_em
  aceita_t '7 comentario humano acrescentado (YAML e corpo)' t_comentario
  aceita_t '8 sinais antigos de inline para bloco, mesma lista' t_sinais_bloco
  aceita_t '9 literal {{...}} permanece e aparece na prosa' t_marcador_prosa
  aceita_t '9b recalibracao completa da F6' t_recalibracao_completa

  nega_t '10 remove entrada historica' n_remove 'remove ou reescreve'
  nega_t '11 muda real de entrada historica' n_real 'remove ou reescreve'
  nega_t '12 muda trabalho_id historico' n_trabalho 'remove ou reescreve'
  nega_t '13 muda task_id historico' n_task 'remove ou reescreve'
  nega_t '14 muda estimativa historica' n_estimativa 'remove ou reescreve'
  nega_t '15 muda sinais semanticamente' n_sinais 'remove ou reescreve'
  nega_t '16 acrescenta entrada de outro trabalho' n_outro_trabalho 'outro trabalho'
  nega_t '17 acrescenta task nao concluida' n_nao_concluida 'não é concluída'
  nega_t '18 nova entrada duplicada' n_duplicada 'duplicada'
  nega_t '19 marcador pendente no frontmatter' n_marcador_fm 'marcador'
  nega_t '20 marcador pendente em linha oficial de dados' n_marcador_linha 'marcador'
  nega_t '21 remove linha antiga da tabela oficial de Entradas' n_remove_linha 'remove ou reescreve'
  nega_t '22 linha oficial sem entrada no frontmatter' n_linha_sem_entrada 'sem entrada'
  nega_t '23 HISTORICO tracked apagado' n_apagado 'remove ou reescreve'
  nega_t '24 nova entrada fora do schema (real texto)' n_real_texto 'real'
  nega_t '25 calibracao com fator ativo abaixo de 3 entradas' n_cal_fator_sem_base 'fator_ativo'
  nega_t '26 calibracao com entradas nao inteiro' n_cal_entradas_texto 'entradas'
  nega_t '27 calibracao com desvio_medio nao numerico' n_cal_desvio_texto 'desvio_medio'
  nega_t '28 calibracao com fator_ativo nao booleano' n_cal_fator_texto 'fator_ativo'
  nega_t '29 calibracao conta mais entradas do que existem' n_cal_conta_demais 'mais entradas'
  nega_t '30 calibracao repete tipo' n_cal_tipo_repetido 'repetida'
  nega_t '31 calibracao com tipo fora do enum' n_cal_tipo_fora 'enum'
  nega_t '32 calibracao sem fator_ativo' n_cal_sem_fator 'fator_ativo'

  # HEAD fora do contrato: não há base estruturada, então nada é provado.
  repo="$D/tracked-head-invalido"; repo_c7c "$repo" calibrado
  sed -i 's/^expx_tool: sprintx$/expx_tool: teste/' "$repo/$HIST"
  git -C "$repo" commit -qam 'chore: historico fora do contrato'
  conclui "$repo" T-01.01; conclui "$repo" T-02.01; acrescimo_f6 "$repo"
  sed -i 's/^expx_tool: teste$/expx_tool: sprintx/' "$repo/$HIST"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/tracked.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'em HEAD fora do contrato' "$D/tracked.err" && [ -z "$(staged "$repo")" ] \
    && ok 'tracked barra: HEAD fora do contrato nao serve de base' \
    || falha "HEAD fora do contrato virou base (rc=$rc; $(cat "$D/tracked.err"))"

  # Checkpoints seguintes: o mesmo leitor em pre-e6 e e8.
  repo="$D/tracked-checkpoints"; repo_tracked "$repo"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1 || falha 'tracked checkpoints: pre-e2 falhou'
  t_recalibracao_completa "$repo"
  printf 'pr\n' > "$repo/docs/entregas/$TRAB/PR.md"
  metodo "$repo" --persistir pre-e6 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && ok 'tracked: pre-e6 persiste a recalibracao depois do pre-e2' \
    || falha "tracked: pre-e6 recusou recalibracao (rc=$rc)"
  troca_linha "$repo/$HIST" '    real: 2.1' '    real: 2.4'
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  metodo "$repo" --persistir e8 >/dev/null 2>"$D/tracked.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq 'remove ou reescreve' "$D/tracked.err" && [ -z "$(staged "$repo")" ] \
    && ok 'tracked: e8 barra reescrita de entrada ja versionada pelo pre-e2' \
    || falha "tracked: e8 aceitou reescrita (rc=$rc; $(cat "$D/tracked.err"))"
  troca_linha "$repo/$HIST" '    real: 2.4' '    real: 2.1'
  metodo "$repo" --persistir e8 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && git -C "$repo" show "HEAD:$ENT" | grep -Fq 'estado: bloqueado' \
    && metodo "$repo" --verificar e8 >/dev/null 2>&1 \
    && ok 'tracked: e8 bloqueado persiste depois de desfeita a reescrita' \
    || falha "tracked: e8 bloqueado falhou (rc=$rc)"
}

grupo_e1() {
  local repo rc msg
  printf '\nE1 — o HISTORICO inicial e metodo, nunca produto da task\n'
  repo="$D/e1"; repo_c7c "$repo"
  conclui "$repo" T-01.01
  printf 'test("rotulo", () => {});\n' > "$repo/test/rotulo.test.js"
  historico_c7c "$repo/$HIST"
  conclui "$repo" T-02.01
  msg="$D/e1.msg"
  printf 'test(rotulo): cobre rotulo do parecer\n\nTask: T-01.01\nTrabalho: %s\n' "$TRAB" > "$msg"
  (cd "$repo" && bash "$FECHA" --fechar --entrega "$ENT" --task T-01.01 --mensagem "$msg" \
    -- test/rotulo.test.js) >"$D/e1.out" 2>&1; rc=$?
  [ "$rc" = 0 ] && ok 'E1 de produto fecha com HISTORICO inicial untracked na arvore' \
    || falha "E1 de produto barrou (rc=$rc; $(tail -n 5 "$D/e1.out"))"
  igual 'E1 commita somente o produto da task' "$(nomes_head "$repo")" 'test/rotulo.test.js'
  igual 'HISTORICO continua untracked depois do E1' \
    "$(git -C "$repo" status --porcelain -- "$HIST")" "?? $HIST"

  metodo "$repo" --persistir pre-e2 >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && ok 'somente persistir-metodo versiona o HISTORICO inicial' \
    || falha "pre-e2 depois do E1 nao versionou o HISTORICO (rc=$rc)"
}

grupo="${1:-all}"
case "$grupo" in
  all) grupo_central; grupo_checkpoints; grupo_negativos; grupo_contrato; grupo_subsequente; grupo_tracked; grupo_e1 ;;
  central) grupo_central ;;
  checkpoints) grupo_checkpoints ;;
  negativos) grupo_negativos ;;
  contrato) grupo_contrato ;;
  subsequente) grupo_subsequente ;;
  tracked) grupo_tracked ;;
  e1) grupo_e1 ;;
  *) printf 'grupo desconhecido: %s\n' "$grupo" >&2; exit 64 ;;
esac

printf '\n---------------------------------------------\n'
printf '%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
