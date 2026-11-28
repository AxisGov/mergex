#!/usr/bin/env bash
#
# Bancada da DM-360 — a revisão de uma task sem arquivos entra no histórico.
#
# A task sem arquivos (`cria: []` e `altera: []`, DM-356) não tem commit de E1, e o E1
# das outras tasks só leva a revisão da task atual (DM-240). O catálogo de método passa
# a incluir `docs/entregas/<trabalho>/revisao/<id>.json` de cada task sem arquivos nos
# checkpoints cumulativos (pre-e2, pre-e6, e8), e o pre-e2 a commita.
#
# Uso: bash scripts/ci/test-dm360-revisao-sem-arquivos.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
PERSISTE="${PERSISTE:-$SCRIPTS/persistir-metodo.sh}"
FECHA="${FECHA:-$SCRIPTS/fechamento-do-e1.sh}"
CATALOGO="${CATALOGO:-$SCRIPTS/catalogo-de-metodo.sh}"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 — obteve '$3', esperava '$2'"; fi; }

TRAB='ft-d360'
PASTA_REL="docs/sprintx/features/$TRAB"
TASKS_REL="$PASTA_REL/sprint-01/tasks.md"
ENTREGA_REL="docs/entregas/$TRAB/ENTREGA.md"
REVISAO_REL="docs/entregas/$TRAB/revisao"

# T-01.01 tem arquivo; T-01.02 é sem arquivos e concluída; T-01.0a é sem arquivos com
# id fora do formato T-NN.MM.
repo() { # <dir>
  local dir="$1"
  git init -q -b "feature/$TRAB" "$dir" 2>/dev/null || return 1
  (
    cd "$dir" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src "$PASTA_REL/sprint-01" "docs/entregas/$TRAB"
    printf 'base a\n' > src/a.js
    cat > "$TASKS_REL" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: $TRAB
tasks:
  - id: T-01.01
    titulo: Alterar A
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: [src/a.js]
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-01.02
    titulo: Rodar a revisao do CodeAnt
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: []
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-01.0a
    titulo: Id fora do formato
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: []
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-1.1
    titulo: Um digito
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: []
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
  - id: T-001.02
    titulo: Tres digitos
    status: concluida
    suite: verde
    arquivos:
      cria: []
      altera: []
    teste_integracao: cobre integracao
    teste_funcional: cobre fluxo
---
YAML
    cat > "$PASTA_REL/ORQUESTRADOR.md" <<YAML
---
kind: orquestrador
trabalho_id: $TRAB
---
YAML
    cat > "$ENTREGA_REL" <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: $TRAB
entregue_por: mergex
estado: aberto
versionado: true
branch: feature/$TRAB
branch_base: main
commits: []
desvios: []
criado_em: 2026-11-28
atualizado_em: 2026-11-28
---
YAML
    git add -A && git commit -qm 'chore: base'
  )
}

evidencia() { # <dir> <nome>
  mkdir -p "$1/$REVISAO_REL"
  printf '{"task":"%s"}\n' "$2" > "$1/$REVISAO_REL/$2"
}

metodo() { # <dir> <acao> <checkpoint>
  (cd "$1" && bash "$PERSISTE" "$2" --entrega "$ENTREGA_REL" \
    --origem sprintx --trabalho "$TRAB" --checkpoint "$3")
}

so_revisao() { grep -F "$REVISAO_REL/" | LC_ALL=C sort | tr '\n' ' '; }
no_commit() { git -C "$1" show --name-only --format= HEAD | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' '; }
sujo() { [ -n "$(git -C "$1" status --porcelain --untracked-files=all -- "$2")" ]; }

echo '1. O catálogo lista só a revisão da task sem arquivos com id T-NN.MM'
R="$D/lista"; repo "$R"
evidencia "$R" T-01.01.json          # task com arquivos, não é a atual
evidencia "$R" T-01.02.json          # task sem arquivos
evidencia "$R" T-01.02.json.tmp      # nome fora do contrato
evidencia "$R" T-01.0a.json          # task sem arquivos com id fora do formato
evidencia "$R" T-1.1.json            # um dígito: o E1 não aceita como evidência
evidencia "$R" T-001.02.json         # três dígitos: idem
for cp in pre-e2 pre-e6 e8; do
  igual "$cp: só revisao/T-01.02.json" "$REVISAO_REL/T-01.02.json " \
    "$(metodo "$R" --listar "$cp" 2>/dev/null | so_revisao)"
done
igual 'reconciliacao-base (estreito) não leva revisão' '' \
  "$(metodo "$R" --listar reconciliacao-base 2>/dev/null | so_revisao)"

echo '2. O pre-e2 commita a revisão da task sem arquivos'
saida="$(metodo "$R" --persistir pre-e2 2>&1)"; rc=$?
igual 'pre-e2: código' 0 "$rc"
igual 'pre-e2: o commit leva só revisao/T-01.02.json' "$REVISAO_REL/T-01.02.json " "$(no_commit "$R")"
sujo "$R" "$REVISAO_REL/T-01.01.json" && ok 'revisão de task com arquivos fica na árvore' \
  || falha 'revisão de task com arquivos foi commitada'
sujo "$R" "$REVISAO_REL/T-01.02.json.tmp" && ok 'T-01.02.json.tmp fica na árvore' \
  || falha 'T-01.02.json.tmp foi commitado'
sujo "$R" "$REVISAO_REL/T-01.0a.json" && ok 'id fora do formato fica na árvore' \
  || falha 'id fora do formato foi commitado'
for x in T-1.1 T-001.02; do
  sujo "$R" "$REVISAO_REL/$x.json" && ok "$x.json fica na árvore" \
    || falha "$x.json foi commitado"
done
metodo "$R" --verificar pre-e2 >/dev/null 2>&1
igual 'depois do pre-e2 o método está limpo' 0 "$?"

echo '3. O E1 de outra task não commita a revisão da task sem arquivos (DM-240 intacta)'
R="$D/e1"; repo "$R"
printf 'muda\n' >> "$R/src/a.js"
evidencia "$R" T-01.01.json
evidencia "$R" T-01.02.json
MSG="$D/e1.msg"
printf 'fix(src): fecha T-01.01\n\nObjetivo da task.\n\nTask: T-01.01\nTrabalho: %s\n' "$TRAB" > "$MSG"
saida="$(cd "$R" && bash "$FECHA" --fechar --entrega "$ENTREGA_REL" --task T-01.01 \
  --mensagem "$MSG" -- src/a.js 2>&1)"; rc=$?
igual "E1 T-01.01: código ($saida)" 0 "$rc"
igual 'E1 T-01.01: leva o produto e a revisão da task atual' \
  "$REVISAO_REL/T-01.01.json src/a.js " "$(no_commit "$R")"
sujo "$R" "$REVISAO_REL/T-01.02.json" && ok 'E1: a revisão da task sem arquivos fica na árvore' \
  || falha 'E1: a revisão da task sem arquivos entrou no commit da task'

echo '4. Ownership com erro: as revisões ficam fora e o resto do catálogo segue'
F="$D/falso"; mkdir -p "$F"
cp "$CATALOGO" "$F/catalogo-de-metodo.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$F/ownership-da-task.sh"
R="$D/lista"
(
  . "$F/catalogo-de-metodo.sh"
  s="$(catalogo_metodo "$R" sprintx "$TRAB" "$PASTA_REL" pre-e2)"; rc=$?
  [ "$rc" = 0 ] && [ -z "$CATALOGO_ERRO" ] \
    && printf '%s\n' "$s" | grep -qx "docs/entregas/$TRAB/ENTREGA.md" \
    && ! printf '%s\n' "$s" | grep -q '/revisao/'
) && ok 'ownership saiu 1: sem revisões, com ENTREGA.md e sem erro' \
  || falha 'ownership com erro derrubou o catálogo ou deixou revisão entrar'
saida="$(cd "$R" && bash -c '. "$1"; catalogo_metodo "$2" sprintx "$3" "$4" reconciliacao-base' _ \
  "$F/catalogo-de-metodo.sh" "$R" "$TRAB" "$PASTA_REL" 2>/dev/null)"; rc=$?
igual 'checkpoint estreito não consulta o ownership' 0 "$rc"

echo
printf 'test-dm360-revisao-sem-arquivos: %d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
