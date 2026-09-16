#!/usr/bin/env bash
#
# Validador de contrato da mergex — compatibilidade com os worktrees da sprintx.
#
# Checagens determinísticas sobre o texto dos contratos: o que este P0 fixou
# precisa continuar escrito, e o que ele proibiu não pode voltar. Roda em
# qualquer máquina com bash e grep, sem rede e sem dependência nova.
#
# Uso: bash scripts/ci/validate-mergex-contract.sh

set -euo pipefail

fail() {
  printf 'contract check failed: %s\n' "$*" >&2
  exit 1
}

skill='.claude/skills/mergex/SKILL.md'
abertura='.claude/skills/mergex/references/00-abertura.md'
commits='.claude/skills/mergex/references/01-commits.md'
prontidao='.claude/skills/mergex/references/02-prontidao.md'
integ_sprintx='.claude/skills/mergex/references/integracao/sprintx.md'
patch_sprintx='docs/integracao/patch-sprintx.md'
base_sh='.claude/hooks/comum/base.sh'
hook_escopo='.claude/hooks/mergex/arquivo-fora-do-plano.sh'
abrir_cmd='.claude/commands/mergex-abrir.md'
abrir_oc='.opencode/commands/mergex-abrir.md'
mergex_cmd='.claude/commands/mergex.md'
mergex_oc='.opencode/commands/mergex.md'

for f in "$skill" "$abertura" "$commits" "$prontidao" "$integ_sprintx" \
         "$patch_sprintx" "$base_sh" "$hook_escopo" "$abrir_cmd" "$abrir_oc" \
         "$mergex_cmd" "$mergex_oc"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# ---------------------------------------------------------------------------
# Caminho canônico da sprintx, com fallback legado e sem migração automática
# ---------------------------------------------------------------------------
for f in "$abertura" "$integ_sprintx" "$abrir_cmd" "$abrir_oc" "$mergex_cmd" \
         "$mergex_oc" "$skill"; do
  grep -Fq 'docs/sprintx/features/' "$f" \
    || fail "$f does not use the canonical sprintx path"
  grep -Fq 'docs/<slug>/' "$f" \
    || fail "$f dropped the legacy sprintx path fallback"
done
grep -Fq 'Nunca mova a pasta legada' "$abertura" \
  || fail 'E0 no longer forbids moving a legacy work folder'

# V6 e V7 procuram o canônico antes do legado.
grep -Fq 'docs/sprintx/features/<slug>/00-AUDITORIA.md' "$prontidao" \
  || fail 'V6 missing the canonical audit path'
grep -Fq 'docs/<slug>/00-AUDITORIA.md' "$prontidao" \
  || fail 'V6 dropped the legacy audit path'
grep -Fq 'docs/sprintx/features/<slug>/00-BLOQUEIOS.md' "$prontidao" \
  || fail 'V7 missing the canonical blockers path'

# ---------------------------------------------------------------------------
# A runx não regride: os caminhos canônicos dela continuam nos mesmos contratos
# ---------------------------------------------------------------------------
grep -Fq 'docs/manutencao/<OC-ID>-<slug>/ORQUESTRADOR.md' "$abertura" \
  || fail 'E0 lost the runx work path'
grep -Fq 'docs/manutencao/<OC-ID>-<slug>/QA.md' "$prontidao" \
  || fail 'V5 lost the runx QA path'
grep -Fq 'docs/manutencao/<trabalho_id>/' "$commits" \
  || fail 'E1 lost the runx folder among the method artifacts'

# ---------------------------------------------------------------------------
# Base informada pelo chamador: precedência mais alta, validada, sem troca muda
# ---------------------------------------------------------------------------
grep -Fq '1. **Base informada pelo chamador**' "$abertura" \
  || fail 'caller-provided base is not the highest precedence in E0'
grep -Fq 'nunca substitua silenciosamente por outra' "$abertura" \
  || fail 'E0 may silently replace an invalid explicit base'

# ---------------------------------------------------------------------------
# Adoção de branch e worktree; árvore limpa continua barrando criação/troca
# ---------------------------------------------------------------------------
grep -Fq 'Caso A — a branch ativa já é a branch do trabalho' "$abertura" \
  || fail 'E0 has no adoption case for an already-correct branch'
grep -Fq 'não execute `git switch`' "$abertura" \
  || fail 'E0 adoption still switches branches'
grep -Fq 'Caso B — a branch alvo existe e está em uso por outro worktree' "$abertura" \
  || fail 'E0 has no case for a branch checked out in another worktree'
grep -Fq 'git worktree list --porcelain' "$abertura" \
  || fail 'E0 cannot locate a branch checked out in another worktree'
grep -Fq 'nunca remova o worktree de ninguém' "$abertura" \
  || fail 'E0 no longer forbids removing someone else worktree'
grep -Fq 'Árvore limpa é pré-condição para criar ou trocar branch' "$abertura" \
  || fail 'E0 lost the clean-tree precondition wording'
grep -Fq 'Arquivo apenas não rastreado' "$abertura" \
  || fail 'E0 no longer counts untracked files in the clean-tree gate'
grep -Fq 'nunca cria uma segunda branch para o mesmo trabalho' "$abertura" \
  || fail 'E0 no longer forbids a second branch for the same work'
grep -Fq 'adota a branch e o worktree' "$skill" \
  || fail 'SKILL.md does not describe E0 adoption'
grep -Fq 'F1 da sprintx é a dona' "$integ_sprintx" \
  || fail 'integration doc no longer names sprintx F1 as branch/worktree owner'

# A raiz é a que o versionador informa; num worktree, `.git` é arquivo.
grep -Fq 'num worktree é `arquivo`, não diretório' "$skill" \
  || fail 'SKILL.md still assumes .git is a directory when anchoring docs/entregas/'

# ---------------------------------------------------------------------------
# Suíte por task: parcial e verde valem; vermelha e nao_executada barram
# ---------------------------------------------------------------------------
grep -Fq 'Suíte da task: `parcial` ou `verde`' "$commits" \
  || fail 'E1 still demands a green whole suite per task'
grep -Fq '`parcial` e `verde` são registros válidos' "$prontidao" \
  || fail 'V2 does not accept suite: parcial'
grep -Fq '`vermelha` e `nao_executada` são FALHA' "$prontidao" \
  || fail 'V2 no longer fails on red or unexecuted suites'
grep -Fq 'evidência da suíte inteira no fechamento de cada sprint' "$prontidao" \
  || fail 'V2 dropped the whole-suite evidence requirement'

# ---------------------------------------------------------------------------
# Artefato de método do próprio trabalho não é desvio; produto fora do plano é
# ---------------------------------------------------------------------------
grep -Fq 'artefatos de método do próprio trabalho' "$commits" \
  || fail 'E1 does not define method artifacts'
grep -Fq 'docs/sprintx/features/<trabalho_id>/' "$commits" \
  || fail 'E1 does not scope the method-artifact exemption to the work folder'
grep -Fq 'Commit de artefatos de método' "$commits" \
  || fail 'E1 has no deterministic moment for method artifacts'
grep -Fq 'continua sendo desvio' "$commits" \
  || fail 'E1 no longer treats undeclared product files as deviations'
grep -Fq 'artefatos de método do próprio trabalho não são desvio' "$prontidao" \
  || fail 'V9 does not exempt the work own method artifacts'

# ---------------------------------------------------------------------------
# Trabalho corrente do hook de escopo: pela branch, nunca por recência
# ---------------------------------------------------------------------------
grep -Fq 'expx_trabalho_atual_por_branch()' "$base_sh" \
  || fail 'base.sh does not define the branch-based current-work resolver'
grep -Fq 'branch --show-current' "$base_sh" \
  || fail 'the resolver does not read the current branch'

# O helper histórico do rastro continua existindo. A IMPLEMENTAÇÃO dele não é
# contrato: o que este script protege é que o hook de escopo não dependa dela.
grep -Fq 'expx_trabalho_id()' "$base_sh" \
  || fail 'expx_trabalho_id was removed from base.sh'

# Só o código conta: o comentário do hook cita o helper antigo justamente para
# dizer que não o usa.
grep -Fq 'expx_trabalho_atual_por_branch' "$hook_escopo" \
  || fail 'scope hook does not use the branch-based resolver'
if grep -v '^[[:space:]]*#' "$hook_escopo" | grep -Fq 'expx_trabalho_id'; then
  fail 'scope hook still resolves the current work by most recent ENTREGA.md'
fi
if grep -Fq 'estado.json' "$hook_escopo"; then
  fail 'scope hook must never read estado.json to decide the current work'
fi

# A regra está escrita no contrato, não só no código.
grep -Fq 'exatamente um' "$commits" \
  || fail 'E1 does not state the exactly-one rule for identifying the current work'
grep -Fq 'nunca por recência' "$commits" \
  || fail 'E1 does not forbid resolving the current work by recency'

# ---------------------------------------------------------------------------
# O comando manual de revisão nunca é encadeado por contrato nenhum
# ---------------------------------------------------------------------------
# `09-revisao.md` fica fora da varredura: é o reference do PRÓPRIO E9, onde o
# comando é o assunto. Esta varredura existe para pegar menção solta em
# QUALQUER OUTRO contrato, do tipo "ao terminar, rode /mergex-revisar".
encontrou=0
while IFS= read -r linha; do
  [ -n "$linha" ] || continue
  case "$linha" in
    .claude/skills/mergex/references/09-revisao.md:*) continue ;;
    *não*|*NÃO*|*nunca*|*NUNCA*|*nenhum*|*Nenhum*|*manual*|*MANUAL*|*explícit*|*Explícit*|*jamais*) continue ;;
  esac
  printf 'unqualified mergex-revisar mention: %s\n' "$linha" >&2
  encontrou=1
done <<EOF
$(grep -RIn -- 'mergex-revisar' \
    .claude/skills/mergex/references .claude/skills/mergex/assets docs/integracao \
    "$mergex_cmd" "$abrir_cmd" .claude/commands/mergex-pr.md \
    .claude/commands/mergex-check.md 2>/dev/null || true)
EOF
[ "$encontrou" = '0' ] || fail 'mergex-revisar mentioned without an explicit prohibition'

printf 'contract checks passed\n'
