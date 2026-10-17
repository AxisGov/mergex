#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'contract check failed: %s\n' "$*" >&2
  exit 1
}

skill='.claude/skills/mergex/SKILL.md'
review='.claude/skills/mergex/references/09-revisao.md'
claude_cmd='.claude/commands/mergex-revisar.md'
opencode_cmd='.opencode/commands/mergex-revisar.md'
readme='README.md'

for f in "$skill" "$review" "$claude_cmd" "$opencode_cmd" "$readme"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# E9 remains the manual review/merge boundary.
grep -Fq 'E9 REVISÃO E MERGE — MANUAL' "$skill" \
  || fail 'SKILL.md no longer declares E9 as manual'
grep -Fq 'O E9 NUNCA executa automaticamente.' "$review" \
  || fail '09-revisao.md no longer forbids automatic E9 execution'
grep -Fq 'só roda por chamada explícita do desenvolvedor' "$claude_cmd" \
  || fail 'Claude command no longer requires explicit developer invocation'

# Passo 1 lista TODOS os PRs abertos: `gh pr list` para em 30 (e `--limit N` so
# desloca o corte), e o criterio de saida do E9 exige todos.
grep -Fq 'gh api --paginate "repos/{owner}/{repo}/pulls?state=open&per_page=100"' "$review" \
  || fail '09-revisao.md Passo 1 does not page through every open PR'
grep -Fq 'glab api --paginate "projects/:id/merge_requests?state=opened&per_page=100"' "$review" \
  || fail '09-revisao.md Passo 1 does not page through every open MR on GitLab'
if grep -n -E '^[[:space:]]*gh pr list\b' "$review"; then
  fail '09-revisao.md lists PRs with `gh pr list` (stops at 30 by default)'
fi

# No E10 stage may be introduced in active skill/command/reference contracts.
# Detects E10 declared as a stage: in a heading, in bold, or as the first token of a line after
# optional structural markers (blockquote, list bullet, ordered item, table cell, heading, bold).
# Prose that only mentions E10 mid-sentence ("sem E10", "não existe E10") is not a declaration.
if grep -R -n -E \
  '^#{1,6}[[:space:]].*\bE10\b|\*\*E10\b|^[[:space:]]*((>|[-*+]|[0-9]+[.)]|\||#{1,6}|\*\*|__)[[:space:]]*)*E10\b' \
  "$skill" .claude/skills/mergex/references .claude/commands .opencode/commands; then
  fail 'E10 stage detected'
fi

# Claude and OpenCode must expose the same manual command contract.
cmp -s "$claude_cmd" "$opencode_cmd" \
  || fail 'Claude and OpenCode mergex-revisar commands diverged'

# BuildX integration must never invoke the manual review command automatically.
grep -Fq 'nunca invoca `mergex-revisar`' "$readme" \
  || fail 'README no longer preserves the BuildX -> no mergex-revisar boundary'

# R1-R6 are canonical and each criterion remains present exactly once in the normative table.
for n in 1 2 3 4 5 6; do
  count="$(grep -Fc "| R${n} |" "$review" || true)"
  [ "$count" = '1' ] || fail "R${n} normative definition count is $count, expected 1"
done

grep -Fq 'REVIEW EVIDENCE' "$review" || fail 'Review Evidence Gate missing'
grep -Fq 'SATISFEITO' "$review" || fail 'SATISFEITO verdict missing'
grep -Fq 'BLOQUEADO' "$review" || fail 'BLOQUEADO verdict missing'
grep -Fq 'Revalidação obrigatória imediatamente antes do merge' "$review" \
  || fail 'pre-merge revalidation requirement missing'
grep -Fq 'Merge atomicamente preso ao HEAD revalidado — obrigatório.' "$review" \
  || fail 'atomic head-bound merge requirement missing'
grep -Fq -- '--match-head-commit <headRefOid>' "$review" \
  || fail 'GitHub --match-head-commit binding missing'
grep -Fq 'Sem mecanismo atômico' "$review" && grep -Fq 'a mergex não executa o merge' "$review" \
  || fail 'refusal to merge without an atomic head-bound mechanism missing'

# R6 external closure by reaction: verifiable +1 on the evidence comment may count; generic reactions never do.
if grep -Fq 'Reação isolada (emoji) não é confirmação' "$review"; then
  fail 'absolute "no reaction is confirmation" rule reintroduced; verifiable +1 closure must be allowed'
fi
grep -Fq '**Reação positiva verificável.**' "$review" && grep -Fq 'hoje, só `+1`' "$review" \
  && grep -Fq 'comentário específico de evidência daquele finding' "$review" \
  || fail 'verifiable +1 reaction on the evidence comment as R6 closure missing'
grep -Fq 'Reação genérica ou ambígua não satisfaz R6' "$review" \
  || fail 'rule that generic or ambiguous reactions do not satisfy R6 missing'
grep -Fq '(resposta explícita, aprovação, ou reação positiva verificável conforme "Reação positiva' "$review" \
  || fail 'FÁBRICA-resolved branch must accept a prior verifiable positive reaction as external confirmation'

# R1: resultado de CI ausente nao e CI ausente. Pipeline que ainda nao anexou ao HEAD
# (head_pipeline nulo, rollup vazio) com CI configurado e NAO VERIFICAVEL, nunca n/a.
grep -Fq 'Resultado ausente **não** é CI ausente' "$review" \
  && grep -Fq 'R1 é `NÃO VERIFICÁVEL`, nunca `n/a`' "$review" \
  || fail 'R1 treats a CI result not yet attached as "no CI configured" (n/a)'
# A definicao NORMATIVA (a linha | R1 | da tabela) tem que dizer o mesmo: o texto
# explicativo sozinho nao basta, e uma linha R1 contraditoria passaria.
r1="$(grep -F '| R1 |' "$review")"
printf '%s\n' "$r1" | grep -Fq '`n/a` (sem CI configurado: nenhuma configuração de CI no HEAD e nenhum check reportado pela plataforma para ele' \
  && printf '%s\n' "$r1" | grep -Fq 'inclusive o pipeline que ainda não anexou ao HEAD' \
  || fail 'the normative R1 row does not define n/a as no CI config in HEAD and a not-yet-attached pipeline as NAO VERIFICAVEL'
# CI externo (Jenkins, CircleCI, app de checks) nao deixa arquivo de workflow no
# HEAD: um check reportado pela plataforma tambem e CI configurado, e vermelho e FALHOU
printf '%s\n' "$r1" | grep -Fq 'check reportado pela plataforma para o HEAD também é CI configurado' \
  || fail 'the normative R1 row lets an external CI check (no workflow file) become n/a'
grep -Fq 'Check reportado é CI configurado' "$review" \
  || fail 'the CI source row does not count a reported external check as configured CI'
# CI externo que ainda nao reportou nada para o HEAD so aparece como check obrigatorio
# da protecao da base: sem conferir isso, ele viraria n/a e o gate passaria sem resultado
printf '%s\n' "$r1" | grep -Fq 'nem check obrigatório na proteção da base' \
  && grep -Fq 'check obrigatório sem resultado no HEAD é R1 `NÃO VERIFICÁVEL`' "$review" \
  || fail 'R1 becomes n/a while the base protection requires a check that has not reported'
# os checks obrigatorios do GitHub vem de dois mecanismos, cada um no seu endpoint: so os
# rulesets deixariam um check obrigatorio da protecao classica de fora; leitura que falha
# nao prova ausencia de check obrigatorio
grep -Fq 'gh api repos/<dono>/<repo>/branches/<base>' "$review" \
  && grep -Fq 'gh api repos/<dono>/<repo>/rules/branches/<base>' "$review" \
  && grep -Fq 'leitura de qualquer dos dois que falha também é R1 `NÃO VERIFICÁVEL`, nunca `n/a`' "$review" \
  && printf '%s\n' "$r1" | grep -Fq 'lida com sucesso na proteção clássica e nos rulesets' \
  || fail 'R1 reads only the rulesets (or treats a failed read as no required check): classic branch protection checks are missed'
# PR empilhado (base = branch de outro PR aberto) nao passa a frente da predecessora:
# a fila e topologica antes de ser de impacto
grep -Fq '### Antes do impacto: PRs empilhados' "$review" \
  && grep -Fq 'a ordem é **topológica antes de ser de impacto**' "$review" \
  && grep -Fq '`empilhado sobre #<n>`' "$review" \
  || fail 'the E9 queue orders by impact only: a stacked PR can be merged before its predecessor'
# a base tambem e relida na revalidacao pre-merge: mudar depois do passo 7 nao escapa
grep -Fq 'threads e findings relevantes; a base' "$review" \
  && grep -Fq '(HEAD, rascunho, CI, decisão de review, threads, base)' "$review" \
  || fail 'the pre-merge revalidation does not reread the base: a stacked PR can still land on its predecessor branch'
# GitHub aceita as duas extensoes de workflow
grep -Fq '`.github/workflows/*.yml` ou `*.yaml`' "$review" \
  || fail 'CI detection omits .github/workflows/*.yaml'

# REVIEW_REQUIRED nao e pedido de mudanca (R2 nao muda), mas o servico recusa o
# merge: o PR nao e oferecido, vai para os inelegiveis com o motivo nomeado
grep -Fq '`REVIEW_REQUIRED` não muda R2, mas o serviço recusaria o merge' "$review" \
  && grep -Fq 'review obrigatório pendente (`reviewDecision: REVIEW_REQUIRED`' "$review" \
  || fail 'a PR with reviewDecision REVIEW_REQUIRED can be offered for a merge the service will reject'

# sem canal de escrita, o handoff e NAO VERIFICAVEL (09-revisao.md, "O pacote de
# remediacao"): o template tem de oferecer esse estado, nao so NAO PERSISTIDO
grep -Fq 'NÃO PERSISTIDO (handoff NÃO VERIFICÁVEL;' .claude/skills/mergex/assets/TEMPLATE-revisao.md \
  || fail 'TEMPLATE-revisao.md does not mark an unpersisted REVIEW REMEDIATION handoff as NAO VERIFICAVEL'
# o bloco CONFLITO tem o campo da pergunta a quem decidir (analista-de-conflito
# exige uma por trecho): sem ele, o relatorio feito pelo template a omite
grep -Fq '  O que perguntar a quem decidir:' .claude/skills/mergex/assets/TEMPLATE-revisao.md \
  && grep -Fq '{{pergunta}}' .claude/skills/mergex/assets/TEMPLATE-revisao.md \
  && grep -Fq '  O que perguntar a quem decidir:' "$review" \
  || fail 'the CONFLITO block in TEMPLATE-revisao.md (or 09-revisao.md) has no field for the question to whoever decides'

# o comando nao pode exigir recomendacao de todo PR: PR BLOQUEADO nao recebe
# recomendacao de merge (09-revisao.md, passo 6; TEMPLATE-revisao.md)
grep -Fq 'a recomendação em uma linha (ausente quando o gate está `BLOQUEADO`)' "$claude_cmd" \
  || fail 'mergex-revisar asks for a recommendation on every PR, including BLOQUEADO'

printf 'contract checks passed\n'
