#!/usr/bin/env bash
#
# A entrega por sprint (Task S1; DM-263 e DM-264): o E0 `--sprint` fixa o modo e a
# sprint, a sprint seguinte só abre depois do merge da anterior (a partir da main), o
# E8 e o E9 gravam o item da sprint registrada, e a V9 da sprint seguinte só vê ela.
#
# Uso: bash scripts/ci/test-entrega-por-sprint.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$raiz/.claude/skills/mergex/scripts"
ref="$raiz/.claude/skills/mergex/references"
leitor="$scripts/entrega-de-planejamento.sh"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }
confere() { if [ "$2" = 0 ]; then passa "$1"; else quebra "$1"; fi; }
mostra() { sed 's/^/        /' "$@"; }

aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# bloco <arquivo> <marca> — o bloco cercado do reference que contém a marca
bloco() {
  awk -v m="$2" '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                  dentro = 1; buf = ""; achou = 0; next }
       dentro { buf = buf $0 "\n"; if (index($0, m)) achou = 1 }' "$1"
}

# entrega <arquivo> <linhas extras do frontmatter>
entrega() {
  mkdir -p "$(dirname "$1")"
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: entrega' \
      'trabalho_id: plan' 'entregue_por: mergex' 'estado: aberto' 'versionado: true' \
      'commits: []' 'portao: null' 'portao_sha: null' 'falhas_portao: []' 'causa: null' \
      'pr_url: null' 'pr_estado: null'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf '%s\n' '---' '' '# Entrega'
  } > "$1"
}
SHA_A=0123456789abcdef0123456789abcdef01234567
SHA_B=89abcdef0123456789abcdef0123456789abcdef
SHA_C=fedcba9876543210fedcba9876543210fedcba98
item() { # <sprint> <estado> <merge_sha> <merge> <base_sha>
  printf '  - sprint: %s\n    url: null\n    estado: %s\n    merge_sha: %s\n    merge: %s\n    base_sha: %s\n' "$@"
}
le() { local f="$1"; shift; bash "$leitor" --entrega "$f" "$@" >"$aux/out" 2>"$aux/err"; rc=$?; }
linha() { sed -n "s/^$1=//p" "$aux/out"; }

echo '== o leitor: entrega, sprint_atual e os itens de sprint =='

entrega "$aux/antiga.md" ''
le "$aux/antiga.md"
[ "$rc" = 0 ] && [ "$(linha entrega)" = por_trabalho ] && [ "$(linha entrega_origem)" = padrao ] \
  && [ "$(linha sprint_atual)" = null ]
confere 'entrega antiga sem as chaves: por_trabalho (padrao), sprint_atual null' $?

entrega "$aux/s01.md" "entrega: por_sprint
sprint_atual: 01
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 aberto null null null)"
le "$aux/s01.md"
[ "$rc" = 0 ] && [ "$(sed -n 1p "$aux/out")" = planejamento=nao ] && [ "$(linha entrega)" = por_sprint ] \
  && [ "$(linha entrega_origem)" = registrada ] && [ "$(linha sprint_atual)" = 01 ] \
  && [ "$(linha atual_estado)" = aberto ] && [ "$(linha fechada)" = planejamento ] \
  && [ "$(linha fechada_merge_sha)" = $SHA_A ] && [ "$(linha planejamento_merge_sha)" = $SHA_A ] \
  && [ "$(grep -c '^pr=' "$aux/out")" = 2 ]
confere 'sprint 01 aberta: por_sprint registrada, sprint_atual 01, a fechada e o planejamento' $?
[ "$rc" = 0 ] || mostra "$aux/err"

entrega "$aux/s02.md" "entrega: por_sprint
sprint_atual: 02
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 merged $SHA_C humano $SHA_A)
$(item 02 null null null null)"
le "$aux/s02.md"
[ "$rc" = 0 ] && [ "$(linha sprint_atual)" = 02 ] && [ "$(linha fechada)" = 01 ] && [ "$(linha fechada_merge_sha)" = $SHA_C ]
confere 'sprint 02 com a 01 merged: a fechada e a 01' $?

incoerente() { # <nome> <linhas extras>
  entrega "$aux/inc.md" "$2"; le "$aux/inc.md"; [ "$rc" = 2 ]; confere "$1" $?
}
incoerente 'sprint 02 com a 01 ainda aberta: sai 2' "entrega: por_sprint
sprint_atual: 02
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 aberto null null null)
$(item 02 null null null null)"
incoerente 'sprints fora de sequencia (01, 03): sai 2' "entrega: por_sprint
sprint_atual: 03
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 merged $SHA_C humano $SHA_A)
$(item 03 null null null null)"
incoerente 'item de sprint sem o planejamento antes: sai 2' "entrega: por_sprint
sprint_atual: 01
prs:
$(item 01 null null null null)"
incoerente 'sprint 01 com o planejamento ainda nao merged: sai 2' "entrega: por_sprint
sprint_atual: 01
prs:
$(item planejamento aberto null null null)
$(item 01 null null null null)"
incoerente 'sprint_atual 01 sem entrega: por_sprint: sai 2' "sprint_atual: 01
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 null null null null)"
incoerente 'sprint_atual que nao e o ultimo item: sai 2' "entrega: por_sprint
sprint_atual: 01
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 merged $SHA_C humano $SHA_A)
$(item 02 null null null null)"
incoerente 'entrega fora do enum: sai 2' 'entrega: por_semana'
incoerente 'sprint_atual null com item de sprint: sai 2' "entrega: por_sprint
sprint_atual: null
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 null null null null)"

bash "$scripts/causa-do-portao.sh" --validar "$aux/s02.md" >/dev/null 2>&1 \
  && bash "$scripts/sequencia-de-commits.sh" --validar "$aux/s02.md" >/dev/null 2>&1
confere 'causa-do-portao --validar e sequencia-de-commits --validar aceitam a entrega por sprint com prs' $?

echo '== o modo efetivo =='

mkdir -p "$aux/m"
printf '%s\n' '---' 'kind: planejamento' 'entrega: por_sprint' '---' > "$aux/m/plano.md"
bash "$leitor" --modo-efetivo --entrega "$aux/m/nao-existe.md" --plano "$aux/m/plano.md" --projeto por_trabalho >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && [ "$(linha entrega)" = por_sprint ] && [ "$(linha origem)" = plano ]
confere 'entrega: por_sprint no 00-PLANEJAMENTO sobrescreve por_trabalho do projeto' $?
printf '%s\n' '---' 'kind: planejamento' '---' > "$aux/m/sem.md"
bash "$leitor" --modo-efetivo --entrega "$aux/m/nao-existe.md" --plano "$aux/m/sem.md" --projeto por_sprint >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && [ "$(linha entrega)" = por_sprint ] && [ "$(linha origem)" = projeto ]
confere 'plano sem a chave: vale o do projeto' $?
printf '%s\n' '---' 'kind: planejamento' 'entrega: por_semana' '---' > "$aux/m/fora.md"
bash "$leitor" --modo-efetivo --entrega "$aux/m/nao-existe.md" --plano "$aux/m/fora.md" --projeto por_trabalho >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 1 ] && grep -q 'por_semana' "$aux/err" && [ ! -s "$aux/out" ]
confere 'valor fora do enum no plano: E0 para (1, sem modo)' $?
printf '%s\n' '---' 'kind: planejamento' 'entrega: por_trabalho' '---' > "$aux/m/trab.md"
bash "$leitor" --modo-efetivo --entrega "$aux/s01.md" --plano "$aux/m/trab.md" --projeto por_trabalho >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && [ "$(linha entrega)" = por_sprint ] && [ "$(linha origem)" = registrada ]
confere 'modo registrado uma vez: o 00-PLANEJAMENTO alterado depois nao muda o modo' $?

echo '== E0 --sprint, E8 e E9 num repositorio =='

# repo <dir> <modo no 00-PLANEJAMENTO> — main com src/a.ts; feature/plan com o
# planejamento (duas sprints) e a entrega de planejamento; o planejamento mergeado na
# main (merge comum), o merge registrado pelo E9 e a branch atualizada
repo() {
  local d="$1" b m
  git init -q -b main "$d"; git -C "$d" config core.autocrlf false
  mkdir -p "$d/src"; printf 'a\n' > "$d/src/a.ts"
  g -C "$d" add -A; g -C "$d" commit -q -m base
  b="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" switch -q -c feature/plan
  mkdir -p "$d/docs/sprintx/features/plan/sprint-01" "$d/docs/sprintx/features/plan/sprint-02"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: planejamento' 'trabalho_id: plan' \
    "entrega: $2" '---' > "$d/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
    'tasks:' '  - id: T-01.01' '    status: pendente' '    arquivos:' '      cria: [src/b.ts]' \
    '      altera: []' '---' > "$d/docs/sprintx/features/plan/sprint-01/tasks.md"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
    'tasks:' '  - id: T-02.01' '    status: pendente' '    arquivos:' '      cria: [src/c.ts]' \
    '      altera: []' '---' > "$d/docs/sprintx/features/plan/sprint-02/tasks.md"
  entrega "$d/docs/entregas/plan/ENTREGA.md" "base_validada_sha: $b
origem_base: registrada_e0
reconciliacoes: []
branch: feature/plan
branch_base: main
sprint_atual: planejamento
prs:
  - sprint: planejamento
    url: https://github.com/dono/repo/pull/1
    estado: aberto
    merge_sha: null
    merge: null
    base_sha: null"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(sprintx): planejamento' -m 'Trabalho: plan'
  g -C "$d" switch -q main
  printf 'o\n' > "$d/src/o.ts"; g -C "$d" add -A; g -C "$d" commit -q -m 'outra coisa na main'
  b="$(git -C "$d" rev-parse HEAD)"
  g -C "$d" merge -q --no-ff --no-edit feature/plan
  m="$(git -C "$d" rev-parse HEAD)"
  g -C "$d" switch -q feature/plan
  (cd "$d" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m" --base-sha "$b") >/dev/null \
    || echo "        (registro do planejamento falhou em $d)"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(mergex): merge do planejamento' -m 'Trabalho: plan'
  g -C "$d" merge -q --no-edit main
}

# O bloco do E0 --sprint, com a base `main` e os scripts deste checkout
bloco "$ref/00-abertura.md" 'E0 --sprint' \
  | sed 's|<trabalho_id>|plan|g; s|<slug>|plan|g; s|<base>|main|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/#bash '$scripts'/#g" > "$aux/e0s.sh"
[ -s "$aux/e0s.sh" ]; confere '00-abertura tem o bloco do E0 --sprint' $?
e0s() { # <dir> <NN> — saída em $aux/e0s.out/.err, código em $rc
  (cd "$1" && sprint="$2" bash "$aux/e0s.sh") >"$aux/e0s.out" 2>"$aux/e0s.err"; rc=$?
}
abre() { # <dir> <NN> — o E0 --sprint e o commit dele
  e0s "$1" "$2"
  [ "$rc" = 0 ] || { echo "        (E0 --sprint $2 saiu $rc)"; mostra "$aux/e0s.err"; }
  g -C "$1" add -A; g -C "$1" commit -q -m "docs(mergex): abre a sprint $2" -m 'Trabalho: plan'
}
task() { # <dir> <arquivo> <id> — o commit da task e o item em ENTREGA.commits
  local d="$1" c e="$1/docs/entregas/plan/ENTREGA.md"
  printf '%s\n' "$3" > "$d/$2"; g -C "$d" add -A; g -C "$d" commit -q -m "feat: $3" -m 'Trabalho: plan'
  c="$(git -C "$d" rev-parse HEAD)"
  awk -v c="$c" -v t="$3" '
    /^commits: \[\]$/ { print "commits:"; print "  - seq: 1"; print "    task: " t; print "    commit: " c; next }
    /^commits:$/ { print; em = 1; next }
    em && /^[A-Za-z_]/ { print "  - seq: 9"; print "    task: " t; print "    commit: " c; em = 0 }
    { print }' "$e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$e"
  g -C "$d" add -A; g -C "$d" commit -q -m "docs(mergex): registra $3" -m 'Trabalho: plan'
}
e8() { # <dir> <url> <estado>
  (cd "$1" && bash "$leitor" --registrar-pr --entrega docs/entregas/plan/ENTREGA.md --url "$2" --estado "$3") >"$aux/e8.out" 2>"$aux/e8.err"; rc=$?
}
v9() {
  (cd "$1" && bash "$scripts/portao-v9.sh" --verificar --entrega docs/entregas/plan/ENTREGA.md \
    --origem sprintx --trabalho plan) >"$aux/v9.out" 2>"$aux/v9.err"; rc=$?
}
le_repo() { (cd "$1" && bash "$leitor" --entrega docs/entregas/plan/ENTREGA.md) >"$aux/out" 2>"$aux/err"; rc=$?; }
# fecha01 <dir> <squash|merge> — o PR da sprint 01 mergeado na main (que anda depois), o
# merge registrado pelo E9 na branch e a branch ainda SEM a main
fecha01() {
  local d="$1" b m
  g -C "$d" switch -q main
  b="$(git -C "$d" rev-parse HEAD)"
  if [ "$2" = squash ]; then
    g -C "$d" merge -q --squash feature/plan >/dev/null; g -C "$d" commit -q -m 'feat: sprint 01 (#2)' -m 'Trabalho: plan'
  else
    g -C "$d" merge -q --no-ff --no-edit feature/plan
  fi
  m="$(git -C "$d" rev-parse HEAD)"
  printf 'q\n' > "$d/src/q.ts"; g -C "$d" add -A; g -C "$d" commit -q -m 'main depois da sprint 01'
  g -C "$d" switch -q feature/plan
  (cd "$d" && bash "$leitor" --registrar-merge --entrega docs/entregas/plan/ENTREGA.md --merge-sha "$m" --base-sha "$b") >/dev/null \
    || echo "        (registro da sprint 01 falhou em $d)"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(mergex): merge da sprint 01' -m 'Trabalho: plan'
}

# a sprint 01 só abre com o planejamento merged
repo "$aux/r0" por_sprint
sed 's/^    estado: merged/    estado: aberto/; s/^    merge_sha: [0-9a-f]*/    merge_sha: null/; s/^    merge: humano/    merge: null/; s/^    base_sha: [0-9a-f]*/    base_sha: null/; s/^pr_estado: .*/pr_estado: aberto/' \
  "$aux/r0/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" && mv "$aux/e.tmp" "$aux/r0/docs/entregas/plan/ENTREGA.md"
cp "$aux/r0/docs/entregas/plan/ENTREGA.md" "$aux/r0-antes.md"
e0s "$aux/r0" 01
[ "$rc" = 1 ] && grep -q 'E9' "$aux/e0s.err" && cmp -s "$aux/r0/docs/entregas/plan/ENTREGA.md" "$aux/r0-antes.md"
confere 'E0 --sprint 01 com o planejamento ainda nao merged: recusa e manda rodar o E9, sem escrever' $?

repo "$aux/r1" por_sprint
e0s "$aux/r1" 01
le_repo "$aux/r1"
e="$aux/r1/docs/entregas/plan/ENTREGA.md"
[ "$(linha entrega)" = por_sprint ] && [ "$(linha entrega_origem)" = registrada ] && [ "$(linha sprint_atual)" = 01 ] \
  && [ "$(linha atual_estado)" = null ] && grep -qx 'origem_base: registrada_sprint' "$e" \
  && grep -qx "base_validada_sha: $(git -C "$aux/r1" rev-parse main)" "$e" \
  && grep -qx 'pr_url: null' "$e" && grep -qx 'pr_estado: null' "$e"
confere 'E0 grava entrega e sprint_atual efetivos (e reancora a base na main)' $?
[ "$rc" = 0 ] || mostra "$aux/e0s.err" "$aux/err"
g -C "$aux/r1" add -A; g -C "$aux/r1" commit -q -m 'docs(mergex): abre a sprint 01' -m 'Trabalho: plan'
cp "$e" "$aux/r1-antes.md"
e0s "$aux/r1" 01
[ "$rc" = 0 ] && cmp -s "$e" "$aux/r1-antes.md"
confere 'E0 --sprint 01 de novo com a 01 aberta: retomada, nada muda' $?
e0s "$aux/r1" 03
[ "$rc" = 1 ] && grep -q 'sequência' "$aux/e0s.err" && cmp -s "$e" "$aux/r1-antes.md"
confere 'E0 recusa sprint fora de sequencia' $?

# o E8 grava o item da sprint registrada, mesmo com o 00-PLANEJAMENTO alterado depois
task "$aux/r1" src/b.ts T-01.01
printf '%s\n' '---' 'kind: planejamento' 'entrega: por_trabalho' '---' > "$aux/r1/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
rm -rf "$aux/r1/docs/sprintx/features/plan/sprint-01"
e8 "$aux/r1" https://github.com/dono/repo/pull/2 aberto
le_repo "$aux/r1"
[ "$(linha sprint_atual)" = 01 ] && [ "$(linha atual_estado)" = aberto ] \
  && awk '/^  - sprint: 01$/ { a = 1 } a && /^    url: / { print; exit }' "$e" | grep -qx '    url: https://github.com/dono/repo/pull/2' \
  && awk '/^  - sprint: planejamento$/ { a = 1 } a && /^    url: / { print; exit }' "$e" | grep -qx '    url: https://github.com/dono/repo/pull/1'
confere 'E8 grava prs com a sprint registrada mesmo com 00-PLANEJAMENTO alterado depois' $?
g -C "$aux/r1" checkout -q -- docs/sprintx
g -C "$aux/r1" add -A; g -C "$aux/r1" commit -q -m 'docs(mergex): E8 da sprint 01' -m 'Trabalho: plan'
e8 "$aux/r1" https://github.com/dono/repo/pull/2 merged
[ "$rc" = 64 ]; confere 'E8 nao grava merged (o merge e do E9): uso (64)' $?

e0s "$aux/r1" 02
[ "$rc" = 1 ] && grep -q 'sprint 01' "$aux/e0s.err"
confere 'E0 da sprint 02 recusa com o PR da 01 aberto' $?

fecha01 "$aux/r1" squash
le_repo "$aux/r1"
[ "$(linha fechada)" = 01 ] && [ "$(linha sprint_atual)" = 01 ] && grep -qx 'pr_estado: merged' "$e"
confere 'E9 registra o merge da sprint 01 no item dela' $?
e0s "$aux/r1" 02
[ "$rc" = 1 ] && grep -q 'atualizada' "$aux/e0s.err"
confere 'E0 da sprint 02 recusa com a branch sem a main' $?
e0s "$aux/r1" 01
[ "$rc" = 1 ] && grep -q 'imutável' "$aux/e0s.err"
confere 'E0 --sprint 01 depois do merge da 01: sprint fechada e imutavel' $?

# depois do squash, a branch e a main mudaram o ENTREGA.md: o da branch (com o registro do merge) vence
g -C "$aux/r1" merge -q --no-edit -X ours main
abre "$aux/r1" 02
le_repo "$aux/r1"
[ "$(linha sprint_atual)" = 02 ] && grep -qx "base_validada_sha: $(git -C "$aux/r1" rev-parse main)" "$e"
confere 'E0 da sprint 02 depois do merge da 01 e da main na branch: abre a 02 na main nova' $?
task "$aux/r1" src/c.ts T-02.01
v9 "$aux/r1"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out" && grep -qx 'origem_base=registrada_sprint' "$aux/v9.out"
confere 'squash da sprint 01: V9 da sprint 02 passa' $?
[ "$rc" = 0 ] || mostra "$aux/v9.out"
printf 'z\n' > "$aux/r1/src/z.ts"; g -C "$aux/r1" add -A; g -C "$aux/r1" commit -q -m 'feat: z' -m 'Trabalho: plan'
v9 "$aux/r1"
[ "$rc" = 1 ] && [ "$(grep -c '^fora_do_plano' "$aux/v9.out")" = 1 ] && grep -qx "$(printf 'fora_do_plano\tsrc/z.ts')" "$aux/v9.out"
confere 'squash da sprint 01: V9 da sprint 02 so ve a 02 (src/z.ts fora; a 01 e a main nao)' $?

repo "$aux/r2" por_sprint
abre "$aux/r2" 01; task "$aux/r2" src/b.ts T-01.01
e8 "$aux/r2" https://github.com/dono/repo/pull/2 aberto
g -C "$aux/r2" add -A; g -C "$aux/r2" commit -q -m 'docs(mergex): E8' -m 'Trabalho: plan'
fecha01 "$aux/r2" merge
g -C "$aux/r2" merge -q --no-edit main
abre "$aux/r2" 02; task "$aux/r2" src/c.ts T-02.01
v9 "$aux/r2"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out"
confere 'merge comum da sprint 01 (commits da 01 na base): V9 da sprint 02 passa' $?
[ "$rc" = 0 ] || mostra "$aux/v9.out"

# a base da sprint 02 sem o merge da 01: v9_sem_prova
e2="$aux/r2/docs/entregas/plan/ENTREGA.md"
b1="$(git -C "$aux/r2" log --format=%H -n1 -- docs/entregas/plan/ENTREGA.md)"
sed "s/^base_validada_sha: .*/base_validada_sha: $(git -C "$aux/r2" show "$(git -C "$aux/r2" rev-list -n1 --grep='abre a sprint 01' HEAD):docs/entregas/plan/ENTREGA.md" | sed -n 's/^base_validada_sha: //p')/" \
  "$e2" > "$aux/e.tmp" && mv "$aux/e.tmp" "$e2"
g -C "$aux/r2" add -A; g -C "$aux/r2" commit -q -m volta
v9 "$aux/r2"
[ "$rc" = 3 ] && grep -qx 'resultado=v9_sem_prova' "$aux/v9.out"
confere 'V9 da sprint 02 com a base de volta a da sprint 01 (rebaixamento): v9_sem_prova' $?

# o E9 lê o PR da sprint atual no serviço, como o de planejamento
mkdir -p "$aux/gh-falso"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$GH_CHAMADAS"\n[ -z "${GH_RESPOSTA:-}" ] || printf "%%s\\n" "$GH_RESPOSTA"\nexit "${GH_RC:-0}"\n' > "$aux/gh-falso/gh"
chmod +x "$aux/gh-falso/gh"
bloco "$ref/09-revisao.md" 'gh pr view "$pr_url" --json state,mergeCommit' \
  | sed 's|<trabalho_id>|plan|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/entrega-de-planejamento\.sh#bash '$leitor'#" > "$aux/e9.sh"
mkdir -p "$aux/e9/docs/entregas/plan"
entrega "$aux/e9/docs/entregas/plan/ENTREGA.md" "entrega: por_sprint
sprint_atual: 01
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
  - sprint: 01
    url: https://github.com/dono/repo/pull/2
    estado: aberto
    merge_sha: null
    merge: null
    base_sha: null"
sed 's#^pr_url: null#pr_url: https://github.com/dono/repo/pull/2#' "$aux/e9/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" \
  && mv "$aux/e.tmp" "$aux/e9/docs/entregas/plan/ENTREGA.md"
: > "$aux/gh-chamadas"
(cd "$aux/e9" && env PATH="$aux/gh-falso:$PATH" GH_CHAMADAS="$aux/gh-chamadas" GH_RESPOSTA="MERGED $SHA_C $SHA_A" bash "$aux/e9.sh") >"$aux/e9.out" 2>&1; rc=$?
le_repo "$aux/e9"
[ "$rc" = 0 ] && [ "$(linha fechada)" = 01 ] && [ "$(linha fechada_merge_sha)" = $SHA_C ] \
  && grep -q 'pr view https://github.com/dono/repo/pull/2 ' "$aux/gh-chamadas"
confere 'E9 com o PR da sprint atual mergeado pelo servico: grava o item da sprint' $?
[ "$rc" = 0 ] || mostra "$aux/e9.out"

echo '== os references =='
awk '/^### O PR já existe/ || /PR já existe para esta branch/ { a = 1 } a' "$ref/07-abertura-pr.md" > "$aux/e7.txt"
grep -q 'sprint anterior' "$aux/e7.txt" && grep -q 'não é retomada' "$aux/e7.txt"
confere 'PR merged da sprint anterior nao e retomada (07-abertura-pr)' $?
grep -q -- '--registrar-pr' "$ref/08-registro.md" && grep -q 'última sprint' "$ref/08-registro.md"
confere '08-registro: o item da sprint pelo --registrar-pr; memox e fim de trabalho so na ultima sprint' $?
grep -q -- '--sprint' "$ref/integracao/sprintx.md" && grep -q 'atualiza a branch a partir da main' "$ref/integracao/sprintx.md"
confere 'integracao/sprintx: a F6 passa --sprint ao E0 e atualiza a branch a partir da main' $?
grep -q '`entrega`.*`por_trabalho`.*`por_sprint`' "$ref/00-schema.md" \
  && grep -q '`sprint_atual`.*`planejamento`.*`NN`.*`null`' "$ref/00-schema.md"
confere '00-schema: modo e sprint atual cobrem a entrega por sprint' $?
grep -q 'entrega: {{por_trabalho | por_sprint}}' "$raiz/.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md" \
  && grep -q 'sprint_atual: {{planejamento | NN | null}}' "$raiz/.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md"
confere 'TEMPLATE-ENTREGA: inclui o modo e a sprint registrada pelo E0' $?
grep -q 'bash scripts/ci/test-entrega-por-sprint.sh' "$raiz/.github/workflows/ci.yml"
confere 'CI executa a bancada de entrega por sprint' $?

printf '\n%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
