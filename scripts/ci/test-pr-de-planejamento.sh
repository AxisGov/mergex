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
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$(printf 'planejamento=nao\nplanejamento_merge_sha=0123456789abcdef0123456789abcdef01234567')" ]
confere 'depois da retomada (sprint_atual null, planejamento merged): nao, com o merge do planejamento' $?

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

echo '== E0 e V9 de planejamento =='

ref="$raiz/.claude/skills/mergex/references"
# bloco <arquivo> <marca> — o bloco cercado do reference que contém a marca
bloco() {
  awk -v m="$2" '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                  dentro = 1; buf = ""; achou = 0; next }
       dentro { buf = buf $0 "\n"; if (index($0, m)) achou = 1 }' "$1"
}

# O E0 --planejamento não escreve com artefato do planejamento sujo
bloco "$ref/00-abertura.md" 'planejamento não commitado' | sed 's|<slug>|plan|g' > "$aux/e0-pre.sh"
[ -s "$aux/e0-pre.sh" ]; confere '00-abertura tem o bloco da pre-condicao do E0 --planejamento' $?
git init -q -b main "$aux/e0"
mkdir -p "$aux/e0/docs/sprintx/features/plan"
printf 'plano\n' > "$aux/e0/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
g -C "$aux/e0" add -A; g -C "$aux/e0" commit -q -m plano
# e0_escreve <dir> — o bloco e, só se ele passar, a primeira escrita do E0 (a pasta da entrega)
e0_escreve() { (cd "$1" && bash "$aux/e0-pre.sh" && mkdir -p docs/entregas/plan) >/dev/null 2>"$aux/err"; rc=$?; }
e0_escreve "$aux/e0"
[ "$rc" = 0 ] && [ -d "$aux/e0/docs/entregas/plan" ]
confere 'E0 --planejamento com o planejamento commitado: segue e escreve' $?
rm -rf "$aux/e0/docs/entregas"
printf 'mais\n' >> "$aux/e0/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
e0_escreve "$aux/e0"
[ "$rc" = 1 ] && grep -q '00-PLANEJAMENTO.md' "$aux/err" && [ ! -e "$aux/e0/docs/entregas" ]
confere 'E0 --planejamento com artefato do planejamento sujo: recusa sem escrever' $?
g -C "$aux/e0" checkout -q -- .
printf 'novo\n' > "$aux/e0/docs/sprintx/features/plan/01-tasks.md"
e0_escreve "$aux/e0"
[ "$rc" = 1 ] && grep -q '01-tasks.md' "$aux/err" && [ ! -e "$aux/e0/docs/entregas" ]
confere 'E0 --planejamento com artefato do planejamento fora do indice: recusa sem escrever' $?
# so a pasta canonica serve: com so a pasta antiga (docs/<slug>/), suja ou nao, recusa
git init -q -b main "$aux/e0-legado"
mkdir -p "$aux/e0-legado/docs/plan"; printf 'plano\n' > "$aux/e0-legado/docs/plan/ORQUESTRADOR.md"
g -C "$aux/e0-legado" add -A; g -C "$aux/e0-legado" commit -q -m plano
printf 'sujo\n' >> "$aux/e0-legado/docs/plan/ORQUESTRADOR.md"
(cd "$aux/e0-legado" && bash "$aux/e0-pre.sh") >/dev/null 2>"$aux/err"; rc=$?
[ "$rc" = 1 ] && grep -q 'docs/sprintx/features/plan' "$aux/err"
confere 'E0 --planejamento so com a pasta antiga docs/<slug>/: recusa' $?

grep -q -- '--planejamento' "$ref/00-abertura.md" \
  && grep -q 'sprint: planejamento' "$ref/00-abertura.md" \
  && grep -q '`commits` não vazio' "$ref/00-abertura.md" \
  && grep -q 'já `merged`' "$ref/00-abertura.md"
confere '00-abertura nomeia --planejamento, o item prs e as recusas' $?
awk '/^### Retomada depois do PR de planejamento/ { d = 1 } d' "$ref/00-abertura.md" > "$aux/retomada.txt"
grep -q 'estado: merged' "$aux/retomada.txt" && grep -q 'merge_sha' "$aux/retomada.txt" \
  && grep -q 'ancestral' "$aux/retomada.txt" && grep -q 'E9' "$aux/retomada.txt"
confere 'a retomada sem --planejamento exige o planejamento merged' $?
awk '/^## Entrega de planejamento/ { d = 1; next } d && /^## / { exit } d' "$ref/02-prontidao.md" > "$aux/e2.txt"
grep -q 'V1, V2, V3 e V11' "$aux/e2.txt" && grep -q 'planejamento: nenhuma task executada' "$aux/e2.txt" \
  && grep -q 'entrega-de-planejamento.sh' "$aux/e2.txt" && grep -q -- '--planejamento' "$aux/e2.txt"
confere '02-prontidao marca V1, V2, V3 e V11 n/a na entrega de planejamento' $?
grep -q 'Saída:.*fora_do_planejamento' "$ref/02-prontidao.md"
confere '02-prontidao: a Saida da V9 cita fora_do_planejamento' $?

# A V9 de planejamento numa entrega de verdade: base por SHA, diff --no-renames
v9() { # <repo> [--planejamento] — saída em $aux/v9.out, código em $rc
  local r="$1"; shift
  (cd "$r" && bash "$scripts/portao-v9.sh" --verificar "$@" --entrega docs/entregas/plan/ENTREGA.md \
    --origem sprintx --trabalho plan) >"$aux/v9.out" 2>"$aux/v9.err"; rc=$?
}
repo_planejamento() { # <dir> — main com src/a.ts; a branch com o planejamento e a entrega commitados
  local d="$1" b
  git init -q -b main "$d"
  git -C "$d" config core.autocrlf false
  mkdir -p "$d/src"; printf 'a\n' > "$d/src/a.ts"
  g -C "$d" add -A; g -C "$d" commit -q -m base
  b="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" switch -q -c feature/plan
  mkdir -p "$d/docs/sprintx/features/plan/sprint-01" "$d/docs/eventos"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: planejamento' 'trabalho_id: plan' \
    '---' > "$d/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
    'tasks:' '  - id: T-01.01' '    status: pendente' '    arquivos:' '      cria: [src/b.ts]' \
    '      altera: []' '---' > "$d/docs/sprintx/features/plan/sprint-01/tasks.md"
  printf 'evento\n' > "$d/docs/eventos/plan.md"
  entrega "$d/docs/entregas/plan/ENTREGA.md" "base_validada_sha: $b
origem_base: registrada_e0
reconciliacoes: []
branch: feature/plan
branch_base: main
$PLAN_ABERTO"
  sed 's/^trabalho_id: login$/trabalho_id: plan/' "$d/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" \
    && mv "$aux/e.tmp" "$d/docs/entregas/plan/ENTREGA.md"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(sprintx): planejamento' -m 'Trabalho: plan'
}

repo_planejamento "$aux/v9a"
v9 "$aux/v9a" --planejamento
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out"
confere 'V9 de planejamento: so docs/sprintx, docs/entregas e docs/eventos passa' $?
[ "$rc" = 0 ] || sed 's/^/        /' "$aux/v9.out" "$aux/v9.err"

v9 "$aux/v9a"
[ "$rc" = 1 ] && grep -qx "$(printf 'fora_do_plano\tdocs/eventos/plan.md')" "$aux/v9.out" \
  && ! grep -q 'fora_do_planejamento' "$aux/v9.out"
confere 'V9 sem --planejamento nao muda (docs/eventos continua fora do plano)' $?

printf 'b\n' > "$aux/v9a/src/b.ts"
g -C "$aux/v9a" add -A; g -C "$aux/v9a" commit -q -m codigo
v9 "$aux/v9a" --planejamento
[ "$rc" = 1 ] && grep -qx 'resultado=v9' "$aux/v9.out" \
  && grep -qx "$(printf 'fora_do_planejamento\tsrc/b.ts')" "$aux/v9.out"
confere 'V9 de planejamento: src/b.ts (mesmo declarado numa task) e fora_do_planejamento' $?

repo_planejamento "$aux/v9b"
git -C "$aux/v9b" mv src/a.ts docs/sprintx/features/plan/a.ts
g -C "$aux/v9b" commit -q -m move
v9 "$aux/v9b" --planejamento
[ "$rc" = 1 ] && grep -qx "$(printf 'fora_do_planejamento\tsrc/a.ts')" "$aux/v9.out"
confere 'V9 de planejamento: renomeacao de src/a.ts para docs/sprintx/ reprova pela origem' $?

# --planejamento numa entrega comum: a V9 nao confia na opcao, confere a marca de HEAD
repo_planejamento "$aux/v9c"
sed '/^sprint_atual:/,/^    merge: null$/d' "$aux/v9c/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" \
  && mv "$aux/e.tmp" "$aux/v9c/docs/entregas/plan/ENTREGA.md"
mkdir -p "$aux/v9c/docs/sprintx/features/plan"; printf 'x\n' > "$aux/v9c/docs/sprintx/features/plan/nota.md"
g -C "$aux/v9c" add -A; g -C "$aux/v9c" commit -q -m comum
v9 "$aux/v9c" --planejamento
[ "$rc" = 3 ] && grep -qx 'resultado=v9_sem_prova' "$aux/v9.out" && grep -q 'não é a de planejamento' "$aux/v9.out"
confere 'V9 --planejamento numa entrega comum: v9_sem_prova (nao confia na opcao)' $?
# --planejamento so existe na SprintX: a RunX nao tem PR de planejamento
(cd "$aux/v9a" && bash "$scripts/portao-v9.sh" --verificar --planejamento --entrega docs/entregas/plan/ENTREGA.md \
  --origem runx --trabalho plan) >"$aux/v9.out" 2>"$aux/v9.err"; rc=$?
[ "$rc" = 64 ] && grep -q 'runx' "$aux/v9.err"
confere 'V9 --planejamento com --origem runx: uso (64)' $?

echo '== A primeira sprint depois do merge do planejamento (DM-261) =='

# O bloco da retomada do E0 (pré-condições e a base nova), com a base `main`
bloco "$ref/00-abertura.md" 'origem_base=registrada_sprint' \
  | sed 's|<trabalho_id>|plan|g; s|<base>|main|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/entrega-de-planejamento\.sh#bash '$leitor'#" > "$aux/e0-retomada.sh"
[ -s "$aux/e0-retomada.sh" ]; confere '00-abertura tem o bloco da retomada depois do planejamento' $?
e0r() { (cd "$1" && bash "$aux/e0-retomada.sh") >"$aux/e0r.out" 2>"$aux/e0r.err"; rc=$?; }
# reancora <dir> — aplica a saída do bloco como o E0 a grava (passo 5, caso 2) e commita
reancora() {
  local d="$1" e="$1/docs/entregas/plan/ENTREGA.md" nb
  nb="$(sed -n 's/^base_validada_sha=//p' "$aux/e0r.out")"
  sed "s/^sprint_atual: planejamento/sprint_atual: null/; s/^pr_url: .*/pr_url: null/; s/^pr_estado: .*/pr_estado: null/; s/^base_validada_sha: .*/base_validada_sha: $nb/; s/^origem_base: .*/origem_base: registrada_sprint/" "$e" > "$aux/e.tmp" \
    && mv "$aux/e.tmp" "$e"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(mergex): retomada da primeira sprint' -m 'Trabalho: plan'
}
# sprint1 <dir> — o código da task T-01.01 (src/b.ts, declarado no plano)
sprint1() {
  printf 'b\n' > "$1/src/b.ts"
  g -C "$1" add -A; g -C "$1" commit -q -m 'feat: b' -m 'Trabalho: plan'
}
# repo_mergeado <dir> <merge|squash> — o planejamento mergeado na main (que andou
# antes e depois), a branch atualizada a partir da main e o merge registrado (E9)
repo_mergeado() {
  local d="$1" m
  repo_planejamento "$d"
  g -C "$d" switch -q main
  printf 'o\n' > "$d/src/o.ts"; g -C "$d" add -A; g -C "$d" commit -q -m 'outra coisa na main'
  if [ "$2" = squash ]; then
    g -C "$d" merge -q --squash feature/plan >/dev/null
    g -C "$d" commit -q -m 'docs(sprintx): planejamento (#1)' -m 'Trabalho: plan'
  else
    g -C "$d" merge -q --no-ff --no-edit feature/plan
  fi
  m="$(git -C "$d" rev-parse HEAD)"
  printf 'p\n' > "$d/src/p.ts"; g -C "$d" add -A; g -C "$d" commit -q -m 'main depois do planejamento'
  g -C "$d" switch -q feature/plan
  g -C "$d" merge -q --no-edit main
  (cd "$d" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m") >/dev/null 2>&1
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(mergex): merge do planejamento registrado' -m 'Trabalho: plan'
}

repo_mergeado "$aux/s1a" merge
e0r "$aux/s1a"
[ "$rc" = 0 ] && grep -qx 'origem_base=registrada_sprint' "$aux/e0r.out" \
  && [ "$(sed -n 's/^base_validada_sha=//p' "$aux/e0r.out")" = "$(git -C "$aux/s1a" rev-parse main)" ]
confere 'E0 da primeira sprint com o planejamento merged: a base nova e a da main atualizada' $?
[ "$rc" = 0 ] || sed 's/^/        /' "$aux/e0r.out" "$aux/e0r.err"
reancora "$aux/s1a"; sprint1 "$aux/s1a"
v9 "$aux/s1a"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out" && grep -qx 'origem_base=registrada_sprint' "$aux/v9.out" \
  && grep -qx "base=$(git -C "$aux/s1a" rev-parse main)" "$aux/v9.out"
confere 'V9 da primeira sprint depois do merge do planejamento: passa com a base nova' $?
[ "$rc" = 0 ] || sed 's/^/        /' "$aux/v9.out" "$aux/v9.err"
(cd "$aux/s1a" && bash "$leitor" --entrega docs/entregas/plan/ENTREGA.md) > "$aux/out" 2>&1
[ "$(cat "$aux/out")" = "$(printf 'planejamento=nao\nplanejamento_merge_sha=%s' "$(git -C "$aux/s1a" rev-parse 'main~1')")" ]
confere 'depois da reancoragem, o leitor diz nao com o merge do planejamento' $?
# mais uma task depois: a V9 continua passando (a reancoragem é uma só)
printf 'c\n' >> "$aux/s1a/src/b.ts"; g -C "$aux/s1a" add -A; g -C "$aux/s1a" commit -q -m 'feat: b2' -m 'Trabalho: plan'
v9 "$aux/s1a"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out"
confere 'V9 da primeira sprint com mais commits: continua passando' $?
# produto fora do plano na sprint continua v9
printf 'z\n' > "$aux/s1a/src/z.ts"; g -C "$aux/s1a" add -A; g -C "$aux/s1a" commit -q -m 'feat: z' -m 'Trabalho: plan'
v9 "$aux/s1a"
[ "$rc" = 1 ] && grep -qx "$(printf 'fora_do_plano\tsrc/z.ts')" "$aux/v9.out" && ! grep -q 'src/[op]\.ts' "$aux/v9.out"
confere 'V9 da primeira sprint: so o que a sprint mudou conta (src/z.ts fora; o que veio da main nao)' $?

repo_mergeado "$aux/s1b" squash
e0r "$aux/s1b"; reancora "$aux/s1b"; sprint1 "$aux/s1b"
v9 "$aux/s1b"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out" && grep -qx 'origem_base=registrada_sprint' "$aux/v9.out"
confere 'V9 da primeira sprint depois do planejamento mergeado por squash: passa' $?
[ "$rc" = 0 ] || sed 's/^/        /' "$aux/v9.out" "$aux/v9.err"

# sem o merge registrado (o E9 não rodou): o E0 recusa e manda rodar o E9
repo_planejamento "$aux/s1c"
g -C "$aux/s1c" switch -q main; g -C "$aux/s1c" merge -q --no-ff --no-edit feature/plan
g -C "$aux/s1c" switch -q feature/plan; g -C "$aux/s1c" merge -q --no-edit main
e0r "$aux/s1c"
[ "$rc" = 1 ] && grep -q 'E9' "$aux/e0r.err" && [ ! -s "$aux/e0r.out" ]
confere 'E0 da primeira sprint sem o merge do planejamento registrado: recusa e manda rodar o E9' $?
# a V9 nao aceita registrada_sprint sem o merge registrado na entrega de HEAD
sed "s/^base_validada_sha: .*/base_validada_sha: $(git -C "$aux/s1c" rev-parse main)/; s/^origem_base: .*/origem_base: registrada_sprint/" \
  "$aux/s1c/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" && mv "$aux/e.tmp" "$aux/s1c/docs/entregas/plan/ENTREGA.md"
g -C "$aux/s1c" add -A; g -C "$aux/s1c" commit -q -m forja; sprint1 "$aux/s1c"
v9 "$aux/s1c"
[ "$rc" = 3 ] && grep -qx 'resultado=v9_sem_prova' "$aux/v9.out" && grep -q 'registrada_sprint sem o merge do planejamento' "$aux/v9.out"
confere 'V9 com registrada_sprint sem o merge do planejamento registrado: v9_sem_prova' $?

# a branch sem a main: o E0 recusa
repo_planejamento "$aux/s1d"
g -C "$aux/s1d" switch -q main; g -C "$aux/s1d" merge -q --no-ff --no-edit feature/plan
m_d="$(git -C "$aux/s1d" rev-parse HEAD)"
g -C "$aux/s1d" switch -q feature/plan
(cd "$aux/s1d" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m_d") >/dev/null 2>&1
e0r "$aux/s1d"
[ "$rc" = 1 ] && grep -q 'atualizada' "$aux/e0r.err" && [ ! -s "$aux/e0r.out" ]
confere 'E0 da primeira sprint com a branch sem a main: recusa' $?

# o trabalho levou produto antes do merge do planejamento: a base nova nao o esconde
repo_planejamento "$aux/s1e"
printf 'x\n' > "$aux/s1e/src/x.ts"; g -C "$aux/s1e" add -A; g -C "$aux/s1e" commit -q -m 'feat: x' -m 'Trabalho: plan'
g -C "$aux/s1e" switch -q main; g -C "$aux/s1e" merge -q --no-ff --no-edit feature/plan
m_e="$(git -C "$aux/s1e" rev-parse HEAD)"
g -C "$aux/s1e" switch -q feature/plan; g -C "$aux/s1e" merge -q --no-edit main
(cd "$aux/s1e" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m_e") >/dev/null 2>&1
g -C "$aux/s1e" add -A; g -C "$aux/s1e" commit -q -m registro
e0r "$aux/s1e"; reancora "$aux/s1e"; sprint1 "$aux/s1e"
v9 "$aux/s1e"
[ "$rc" = 3 ] && grep -qx 'resultado=v9_sem_prova' "$aux/v9.out" && grep -q 'src/x.ts' "$aux/v9.out"
confere 'V9 da primeira sprint com produto do trabalho antes do merge do planejamento: v9_sem_prova' $?

# o merge_sha registrado fora da base nova: v9_sem_prova
repo_mergeado "$aux/s1f" merge
e0r "$aux/s1f"; reancora "$aux/s1f"
sed "s/^base_validada_sha: .*/base_validada_sha: $(git -C "$aux/s1f" rev-parse 'main~2')/" \
  "$aux/s1f/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" && mv "$aux/e.tmp" "$aux/s1f/docs/entregas/plan/ENTREGA.md"
g -C "$aux/s1f" add -A; g -C "$aux/s1f" commit -q --amend --no-edit; sprint1 "$aux/s1f"
v9 "$aux/s1f"
[ "$rc" = 3 ] && grep -qx 'resultado=v9_sem_prova' "$aux/v9.out" && grep -q 'não contém o merge do planejamento' "$aux/v9.out"
confere 'V9 com registrada_sprint e a base sem o merge do planejamento: v9_sem_prova' $?

# com reconciliação já registrada, a reancoragem deixaria a cadeia sem âncora: o E0 recusa
repo_mergeado "$aux/s1g" merge
sed 's/^reconciliacoes: \[\]$/reconciliacoes:\
  - arquivo: RECONCILIACAO-BASE-001.md/' "$aux/s1g/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" \
  && mv "$aux/e.tmp" "$aux/s1g/docs/entregas/plan/ENTREGA.md"
e0r "$aux/s1g"
[ "$rc" = 1 ] && grep -q 'reconcilia' "$aux/e0r.err" && [ ! -s "$aux/e0r.out" ]
confere 'E0 da primeira sprint com reconciliacao ja registrada: recusa sem reancorar' $?

# rebase-merge: P é o último commit reaplicado na main (não é merge) e a V9 passa
repo_planejamento "$aux/s1h"
g -C "$aux/s1h" switch -q main
printf 'o\n' > "$aux/s1h/src/o.ts"; g -C "$aux/s1h" add -A; g -C "$aux/s1h" commit -q -m 'outra coisa na main'
g -C "$aux/s1h" cherry-pick feature/plan >/dev/null
m_h="$(git -C "$aux/s1h" rev-parse HEAD)"
g -C "$aux/s1h" switch -q feature/plan; g -C "$aux/s1h" merge -q --no-edit main
(cd "$aux/s1h" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m_h") >/dev/null 2>&1
g -C "$aux/s1h" add -A; g -C "$aux/s1h" commit -q -m registro
e0r "$aux/s1h"; reancora "$aux/s1h"; sprint1 "$aux/s1h"
v9 "$aux/s1h"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out"
confere 'V9 da primeira sprint depois do planejamento por rebase-merge: passa' $?
[ "$rc" = 0 ] || sed 's/^/        /' "$aux/v9.out" "$aux/v9.err"

# o merge do planejamento traz produto sem a marca do trabalho: a diferença P^1..P o pega
repo_planejamento "$aux/s1i"
printf 'u\n' > "$aux/s1i/src/u.ts"; g -C "$aux/s1i" add -A; g -C "$aux/s1i" commit -q -m 'sem marca'
g -C "$aux/s1i" switch -q main; g -C "$aux/s1i" merge -q --no-ff --no-edit feature/plan
m_i="$(git -C "$aux/s1i" rev-parse HEAD)"
g -C "$aux/s1i" switch -q feature/plan; g -C "$aux/s1i" merge -q --no-edit main
(cd "$aux/s1i" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m_i") >/dev/null 2>&1
g -C "$aux/s1i" add -A; g -C "$aux/s1i" commit -q -m registro
e0r "$aux/s1i"; reancora "$aux/s1i"; sprint1 "$aux/s1i"
v9 "$aux/s1i"
[ "$rc" = 3 ] && grep -q 'o merge do planejamento .* traz src/u.ts' "$aux/v9.out"
confere 'V9 com produto sem marca dentro do merge do planejamento: v9_sem_prova' $?

# âncora: uma versão volta à base anterior depois da reancoragem (rebaixamento)
repo_mergeado "$aux/s1j" merge
cp "$aux/s1j/docs/entregas/plan/ENTREGA.md" "$aux/s1j-antes.md"
e0r "$aux/s1j"; reancora "$aux/s1j"
cp "$aux/s1j/docs/entregas/plan/ENTREGA.md" "$aux/s1j-depois.md"
cp "$aux/s1j-antes.md" "$aux/s1j/docs/entregas/plan/ENTREGA.md"; g -C "$aux/s1j" add -A; g -C "$aux/s1j" commit -q -m volta
cp "$aux/s1j-depois.md" "$aux/s1j/docs/entregas/plan/ENTREGA.md"; g -C "$aux/s1j" add -A; g -C "$aux/s1j" commit -q -m de-novo
sprint1 "$aux/s1j"
v9 "$aux/s1j"
[ "$rc" = 3 ] && grep -q 'rebaixamento' "$aux/v9.out"
confere 'V9: versao registrada_e0 depois da reancoragem (rebaixamento): v9_sem_prova' $?

# âncora: duas versões registrada_sprint com bases diferentes
repo_mergeado "$aux/s1k" merge
e0r "$aux/s1k"; reancora "$aux/s1k"
sed "s/^base_validada_sha: .*/base_validada_sha: $(git -C "$aux/s1k" rev-parse 'main~1')/" \
  "$aux/s1k/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" && mv "$aux/e.tmp" "$aux/s1k/docs/entregas/plan/ENTREGA.md"
g -C "$aux/s1k" add -A; g -C "$aux/s1k" commit -q -m outra-base; sprint1 "$aux/s1k"
v9 "$aux/s1k"
[ "$rc" = 3 ] && grep -q 'registrada_sprint com outra base' "$aux/v9.out"
confere 'V9: duas versoes registrada_sprint com bases diferentes: v9_sem_prova' $?

echo '== E8 e E9: o registro do PR de planejamento =='

SHA_M=0123456789abcdef0123456789abcdef01234567
# --registrar-merge: só o item de planejamento ainda não merged
entrega "$aux/reg.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: aberto/')"
bash "$leitor" --registrar-merge --entrega "$aux/reg.md" --merge-sha "$SHA_M" >/dev/null 2>&1; rc=$?
le "$aux/reg.md"
[ "$rc" = 0 ] && grep -qx 'estado=merged' "$aux/out" && grep -qx "merge_sha=$SHA_M" "$aux/out" \
  && grep -qx '    merge: humano' "$aux/reg.md" && grep -qx 'pr_estado: merged' "$aux/reg.md" \
  && grep -qx 'trabalho_id: login' "$aux/reg.md" && grep -qx '# Entrega' "$aux/reg.md"
confere '--registrar-merge grava prs[0] merged, merge humano e pr_estado merged, sem tocar o resto' $?
cp "$aux/reg.md" "$aux/reg-antes.md"
bash "$leitor" --registrar-merge --entrega "$aux/reg.md" --merge-sha "$SHA_M" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && cmp -s "$aux/reg.md" "$aux/reg-antes.md"
confere '--registrar-merge de novo com o mesmo sha: nada muda' $?
bash "$leitor" --registrar-merge --entrega "$aux/reg.md" --merge-sha "fedcba9876543210fedcba9876543210fedcba98" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && cmp -s "$aux/reg.md" "$aux/reg-antes.md"
confere '--registrar-merge com outro sha num planejamento ja merged: recusa sem escrever' $?
cp "$aux/antiga.md" "$aux/antiga-antes.md"
bash "$leitor" --registrar-merge --entrega "$aux/antiga.md" --merge-sha "$SHA_M" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && cmp -s "$aux/antiga.md" "$aux/antiga-antes.md"
confere '--registrar-merge numa entrega comum: recusa sem escrever' $?
# ENTREGA.md que e link simbolico: recusa sem tocar o alvo (no Windows o link pode nao ser criavel)
entrega "$aux/alvo.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: aberto/')"
cp "$aux/alvo.md" "$aux/alvo-antes.md"
ln -s "$aux/alvo.md" "$aux/link.md" 2>/dev/null
if [ -L "$aux/link.md" ]; then
  bash "$leitor" --registrar-merge --entrega "$aux/link.md" --merge-sha "$SHA_M" >/dev/null 2>"$aux/err"; rc=$?
  [ "$rc" = 1 ] && [ -L "$aux/link.md" ] && cmp -s "$aux/alvo.md" "$aux/alvo-antes.md" && grep -q 'link simbólico' "$aux/err"
  confere '--registrar-merge num ENTREGA.md que e link simbolico: recusa sem tocar o alvo' $?
else
  passa '--registrar-merge num ENTREGA.md que e link simbolico: pulado (link simbolico nao criavel aqui)'
fi
# CRLF: o fim de linha de cada linha fica como estava (no Git Bash, o awk do MSYS
# tira o CR na leitura sem BINMODE); o resto do arquivo fica byte a byte
entrega "$aux/crlf.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's/estado: null/estado: aberto/')"
sed 's/$/\r/' "$aux/crlf.md" > "$aux/crlf.tmp" && mv "$aux/crlf.tmp" "$aux/crlf.md"
crs_antes="$(tr -cd '\r' < "$aux/crlf.md" | wc -c | tr -d ' ')"
bash "$leitor" --registrar-merge --entrega "$aux/crlf.md" --merge-sha "$SHA_M" >/dev/null 2>&1; rc=$?
crs_depois="$(tr -cd '\r' < "$aux/crlf.md" | wc -c | tr -d ' ')"
[ "$rc" = 0 ] && [ "$crs_antes" -gt 0 ] && [ "$crs_depois" = "$crs_antes" ] \
  && [ "$(grep -c 'merged' "$aux/crlf.md")" = 2 ] && ! ls "$aux"/crlf.md.tmp.* >/dev/null 2>&1
confere "--registrar-merge num arquivo CRLF mantem os CR ($crs_antes antes, $crs_depois depois) e nao deixa temporario" $?
entrega "$aux/reg2.md" "$PLAN_ABERTO"
bash "$leitor" --registrar-merge --entrega "$aux/reg2.md" --merge-sha 'nao-e-sha' >/dev/null 2>&1
[ "$?" = 64 ]; confere '--registrar-merge com sha invalido: uso (64)' $?

# O bloco real do E9, com um `gh` falso no PATH (nunca o serviço)
bloco "$ref/09-revisao.md" 'gh pr view "$pr_url" --json state,mergeCommit' \
  | sed 's|<trabalho_id>|login|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/entrega-de-planejamento\.sh#bash '$leitor'#" > "$aux/e9.sh"
[ -s "$aux/e9.sh" ]; confere '09-revisao tem o bloco que le o PR de planejamento no servico' $?
mkdir -p "$aux/gh-falso"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GH_CHAMADAS"\n[ -z "${GH_RESPOSTA:-}" ] || printf "%%s\\n" "$GH_RESPOSTA"\nexit "${GH_RC:-0}"\n' > "$aux/gh-falso/gh"
chmod +x "$aux/gh-falso/gh"
repo_e9() { # <dir> — a entrega de planejamento com o PR aberto
  mkdir -p "$1"
  entrega "$1/docs/entregas/login/ENTREGA.md" "$(printf '%s\n' "$PLAN_ABERTO" | sed 's#    url: null#    url: https://github.com/dono/repo/pull/9#; s/estado: null/estado: aberto/')"
  sed 's#^pr_url: null#pr_url: https://github.com/dono/repo/pull/9#' "$1/docs/entregas/login/ENTREGA.md" > "$aux/e.tmp" \
    && mv "$aux/e.tmp" "$1/docs/entregas/login/ENTREGA.md"
}
e9() { # <dir> [VAR=valor...]
  local d="$1"; shift
  (cd "$d" && env PATH="$aux/gh-falso:$PATH" GH_CHAMADAS="$aux/gh-chamadas" "$@" bash "$aux/e9.sh") >"$aux/e9.out" 2>&1; rc=$?
}
repo_e9 "$aux/e9a"
: > "$aux/gh-chamadas"
e9 "$aux/e9a" GH_RESPOSTA="MERGED $SHA_M"
(cd "$aux/e9a" && bash "$leitor" --entrega docs/entregas/login/ENTREGA.md) > "$aux/out" 2>&1
[ "$rc" = 0 ] && grep -qx 'estado=merged' "$aux/out" && grep -qx "merge_sha=$SHA_M" "$aux/out" \
  && grep -q 'pr view https://github.com/dono/repo/pull/9' "$aux/gh-chamadas"
confere 'E9 com o PR de planejamento mergeado pelo servico: grava prs[0] merged com o mergeCommit' $?
repo_e9 "$aux/e9b"; cp "$aux/e9b/docs/entregas/login/ENTREGA.md" "$aux/e9b-antes.md"
e9 "$aux/e9b" GH_RC=1
cmp -s "$aux/e9b/docs/entregas/login/ENTREGA.md" "$aux/e9b-antes.md" && [ "$rc" != 0 ]
confere 'gh sem resposta: nao grava' $?
e9 "$aux/e9b" GH_RESPOSTA="OPEN "
cmp -s "$aux/e9b/docs/entregas/login/ENTREGA.md" "$aux/e9b-antes.md" && [ "$rc" = 0 ]
confere 'PR de planejamento ainda aberto: nao grava' $?
e9 "$aux/e9b" GH_RESPOSTA="MERGED "
cmp -s "$aux/e9b/docs/entregas/login/ENTREGA.md" "$aux/e9b-antes.md" && [ "$rc" != 0 ]
confere 'MERGED sem mergeCommit: nao grava' $?
# GitLab: o MR do planejamento lido com o glab (API do projeto), nunca com o gh
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GH_CHAMADAS"\n[ -z "${GLAB_RESPOSTA:-}" ] || printf "%%s\\n" "$GLAB_RESPOSTA"\nexit "${GLAB_RC:-0}"\n' > "$aux/gh-falso/glab"
chmod +x "$aux/gh-falso/glab"
repo_e9 "$aux/e9g"
sed 's#https://github.com/dono/repo/pull/9#https://gitlab.com/dono/repo/-/merge_requests/9#' "$aux/e9g/docs/entregas/login/ENTREGA.md" > "$aux/e.tmp" \
  && mv "$aux/e.tmp" "$aux/e9g/docs/entregas/login/ENTREGA.md"
: > "$aux/gh-chamadas"
e9 "$aux/e9g" GLAB_RESPOSTA="{\"iid\": 9, \"state\": \"merged\", \"merge_commit_sha\": \"$SHA_M\"}"
(cd "$aux/e9g" && bash "$leitor" --entrega docs/entregas/login/ENTREGA.md) > "$aux/out" 2>&1
[ "$rc" = 0 ] && grep -qx "merge_sha=$SHA_M" "$aux/out" \
  && grep -q 'api projects/:id/merge_requests/9' "$aux/gh-chamadas" && ! grep -q '^pr view' "$aux/gh-chamadas"
confere 'E9 no GitLab: o MR de planejamento mergeado e lido pelo glab e registrado' $?
# pr_url entre aspas (YAML valido): o servico recebe a URL sem elas
repo_e9 "$aux/e9q"
sed 's#^pr_url: \(.*\)$#pr_url: "\1"#' "$aux/e9q/docs/entregas/login/ENTREGA.md" > "$aux/e.tmp" \
  && mv "$aux/e.tmp" "$aux/e9q/docs/entregas/login/ENTREGA.md"
: > "$aux/gh-chamadas"
e9 "$aux/e9q" GH_RESPOSTA="MERGED $SHA_M"
[ "$rc" = 0 ] && grep -q '^pr view https://github.com/dono/repo/pull/9 ' "$aux/gh-chamadas"
confere 'E9 com pr_url entre aspas: le o PR pela URL sem as aspas' $?
(cd "$aux/e9b" && env PATH="$(dirname "$(command -v bash)"):/usr/bin:/bin" bash -c 'command -v gh' >/dev/null 2>&1) \
  || { e9 "$aux/e9b" PATH="$(dirname "$(command -v bash)"):/usr/bin:/bin"
       cmp -s "$aux/e9b/docs/entregas/login/ENTREGA.md" "$aux/e9b-antes.md" && [ "$rc" != 0 ]
       confere 'sem ferramenta do servico: nao grava' $?; }

grep -q 'prs` (o primeiro item' "$ref/08-registro.md" && grep -q 'entrega-de-planejamento.sh' "$ref/08-registro.md"
confere '08-registro grava prs[0]' $?
grep -q 'O PR de planejamento nunca tem merge automático' "$ref/09-revisao.md"
confere '09-revisao diz que o PR de planejamento nunca tem merge automatico' $?
grep -q 'pulou a revisão por passar de 100 arquivos não é finding nem pendência' "$ref/09-revisao.md"
confere '09-revisao diz que o pulo do app por mais de 100 arquivos nao e pendencia' $?

printf '\n%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
