#!/usr/bin/env bash
#
# O PR de planejamento (DM-259, DM-260): a marca na entrega (`sprint_atual` e
# `prs`), o leitor único dela (`entrega-de-planejamento.sh`) e quem o consome.
#
# Uso: bash scripts/ci/test-pr-de-planejamento.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$raiz/.claude/skills/mergex/scripts"
leitor="$scripts/entrega-de-planejamento.sh"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }
# confere <nome> <condição já avaliada: 0 passa>
confere() { if [ "$2" = 0 ]; then passa "$1"; else quebra "$1"; fi; }

aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# entrega <arquivo> <linhas extras do frontmatter> — uma ENTREGA.md válida para
# causa-do-portao e sequencia-de-commits, com as linhas dadas antes do fim.
entrega() {
  mkdir -p "$(dirname "$1")"
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: entrega' \
      'trabalho_id: login' 'entregue_por: mergex' 'estado: aberto' 'versionado: true' \
      'commits: []' 'portao: null' 'portao_sha: null' 'falhas_portao: []' 'causa: null' \
      'pr_url: null' 'pr_estado: null'
    [ -z "$2" ] || printf '%s\n' "$2"
    printf '%s\n' '---' '' '# Entrega'
  } > "$1"
}
PLAN_ABERTO='sprint_atual: planejamento
prs:
  - sprint: planejamento
    url: null
    estado: null
    merge_sha: null
    merge: null'

# le <arquivo> [args] — stdout em $aux/out, código em $rc
le() { local f="$1"; shift; bash "$leitor" --entrega "$f" "$@" >"$aux/out" 2>"$aux/err"; rc=$?; }

echo '== entrega-de-planejamento.sh =='

entrega "$aux/antiga.md" ''
le "$aux/antiga.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = 'planejamento=nao' ]; confere 'entrega antiga sem as chaves: nao' $?

entrega "$aux/aberto.md" "$PLAN_ABERTO"
le "$aux/aberto.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$(printf 'planejamento=sim\nestado=null\nmerge_sha=null')" ]
confere 'planejamento aberto: sim, estado null' $?

entrega "$aux/so-sprint.md" 'sprint_atual: planejamento'
le "$aux/so-sprint.md"
[ "$rc" = 2 ]; confere 'sprint_atual sem prs: sai 2' $?

entrega "$aux/so-prs.md" 'sprint_atual: null
prs:
  - sprint: planejamento
    url: null
    estado: aberto
    merge_sha: null
    merge: null'
le "$aux/so-prs.md"
[ "$rc" = 2 ]; confere 'prs com planejamento nao merged e sprint_atual null: sai 2' $?

entrega "$aux/segundo.md" 'sprint_atual: planejamento
prs:
  - sprint: 01
    url: null
    estado: null
    merge_sha: null
    merge: null
  - sprint: planejamento
    url: null
    estado: null
    merge_sha: null
    merge: null'
le "$aux/segundo.md"
[ "$rc" = 2 ]; confere 'prs com planejamento em segundo: sai 2' $?

entrega "$aux/fluxo.md" 'sprint_atual: planejamento
prs: [{sprint: planejamento, url: null, estado: null, merge_sha: null, merge: null}]'
le "$aux/fluxo.md"
[ "$rc" = 2 ]; confere 'prs em fluxo [{...}]: ilegivel, sai 2' $?

entrega "$aux/enum.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: pronto/')"
le "$aux/enum.md"
[ "$rc" = 2 ]; confere 'estado fora do enum: sai 2' $?

entrega "$aux/auto.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: merged/; s/merge_sha: null/merge_sha: 0123456789abcdef0123456789abcdef01234567/; s/merge: null/merge: automatico/')"
le "$aux/auto.md"
[ "$rc" = 2 ]; confere 'planejamento com merge automatico: sai 2' $?

entrega "$aux/merged.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: merged/; s/merge_sha: null/merge_sha: 0123456789abcdef0123456789abcdef01234567/; s/merge: null/merge: humano/')"
le "$aux/merged.md"
[ "$rc" = 0 ] && grep -qx 'estado=merged' "$aux/out" \
  && grep -qx 'merge_sha=0123456789abcdef0123456789abcdef01234567' "$aux/out"
confere 'planejamento merged: estado e merge_sha' $?

entrega "$aux/retomada.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/^sprint_atual: planejamento/sprint_atual: null/; s/estado: null/estado: merged/; s/merge_sha: null/merge_sha: 0123456789abcdef0123456789abcdef01234567/; s/merge: null/merge: humano/')"
le "$aux/retomada.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = 'planejamento=nao' ]
confere 'depois da retomada (sprint_atual null, planejamento merged): nao' $?

entrega "$aux/sem-chave.md" "$(printf '%s
' "$PLAN_ABERTO" | grep -v 'merge_sha')"
le "$aux/sem-chave.md"
[ "$rc" = 2 ]; confere 'item de prs sem uma das cinco chaves: sai 2' $?

le "$aux/nao-existe.md"
[ "$rc" = 2 ]; confere 'entrega ausente: sai 2' $?

bash "$leitor" --entrega >/dev/null 2>&1; [ "$?" = 64 ]; confere 'uso errado: sai 64' $?

# --rev: o frontmatter do commit, não o do disco
git init -q -b main "$aux/repo"
entrega "$aux/repo/docs/entregas/login/ENTREGA.md" "$PLAN_ABERTO"
g -C "$aux/repo" add -A; g -C "$aux/repo" commit -q -m planejamento
entrega "$aux/repo/docs/entregas/login/ENTREGA.md" ''
(cd "$aux/repo" && bash "$leitor" --entrega docs/entregas/login/ENTREGA.md --rev HEAD) >"$aux/out" 2>&1
[ "$(head -1 "$aux/out")" = 'planejamento=sim' ]; confere '--rev le o commit, nao o disco' $?
(cd "$aux/repo" && bash "$leitor" --entrega docs/entregas/login/ENTREGA.md --rev nao-existe) >/dev/null 2>&1
[ "$?" = 2 ]; confere '--rev que nao resolve: sai 2' $?

# Os validadores de sempre leem a entrega com `prs` (o bloco não é chave de topo)
bash "$scripts/causa-do-portao.sh" --validar "$aux/aberto.md" >/dev/null 2>&1 \
  && bash "$scripts/sequencia-de-commits.sh" --validar "$aux/aberto.md" >/dev/null 2>&1
confere 'causa-do-portao --validar e sequencia-de-commits --validar aceitam a entrega com prs' $?

printf '\n%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
