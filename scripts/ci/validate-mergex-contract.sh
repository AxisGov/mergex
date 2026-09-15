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

printf 'contract checks passed\n'
