#!/usr/bin/env bash
#
# A entrega por sprint (Task S1; DM-264 e DM-265): o E0 `--sprint` fixa o modo e a
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
# e9 <dir> — o registro do E9 persistido pelo checkpoint e9-merge (DM-311), como o
# passo 7 do 09-revisao manda; antes, o teste commitava à mão, sem Metodo:
e9() {
  (cd "$1" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    bash "$scripts/persistir-metodo.sh" --persistir --entrega docs/entregas/plan/ENTREGA.md \
      --origem sprintx --trabalho plan --checkpoint e9-merge) >"$aux/e9.out" 2>"$aux/e9.err" \
    || { mostra "$aux/e9.err"; return 1; }
  git -C "$1" log -1 --format=%B | grep -qx 'Metodo: e9-merge' || { echo "        (o commit do e9-merge sem Metodo: e9-merge)"; return 1; }
}

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

# decisao do dono (2026-11-16, DM-330): o PR de planejamento e opcional no por_sprint
entrega "$aux/s01-sem-plan.md" "entrega: por_sprint
sprint_atual: 01
prs:
$(item 01 aberto null null null)"
le "$aux/s01-sem-plan.md"
[ "$rc" = 0 ] && [ "$(linha sprint_atual)" = 01 ] && [ "$(linha entrega)" = por_sprint ]   && [ -z "$(linha fechada)" ] && [ "$(grep -c '^pr=' "$aux/out")" = 1 ]
r=$?; [ "$r" = 0 ] || mostra "$aux/err"
confere 'sprint 01 sem o item de planejamento (DM-330): legivel, sem fechada' "$r"
entrega "$aux/s02-sem-plan.md" "entrega: por_sprint
sprint_atual: 02
prs:
$(item 01 merged $SHA_C humano $SHA_A)
$(item 02 null null null null)"
le "$aux/s02-sem-plan.md"
[ "$rc" = 0 ] && [ "$(linha fechada)" = 01 ] && [ "$(linha fechada_merge_sha)" = $SHA_C ]
confere 'sprint 02 sem o item de planejamento, com a 01 merged: a fechada e a 01' $?

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

echo '== o escopo das tasks do portao (conselhos, onda 2) =='

# plano <arquivo> <id> <status> — um tasks.md condensado com uma task
plano() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
    'tasks:' "  - id: $2" "    status: $3" '    teste_integracao: t' '    teste_funcional: f' \
    '    suite: parcial' '    arquivos:' '      cria: []' '      altera: []' '---' > "$1"
}
pasta="$aux/pasta"
plano "$pasta/sprint-01/tasks.md" T-01.01 concluida
plano "$pasta/sprint-02/tasks.md" T-02.01 pendente
mkdir -p "$pasta/sprint-notas"   # nome fora de sprint-NN: não é sprint
# da raiz do "repositório" (o $aux, fora de qualquer Git): a pasta tem de resolver dentro dela
escopo() { local f="$1" p="${2:-$pasta}"; cd "$aux" && le "$f" --escopo-de-tasks --pasta "$p"; local r=$rc; cd - >/dev/null; rc=$r; }

escopo "$aux/s02.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$(printf 'escopo=sprint:02\ntasks=%s' "$pasta/sprint-02/tasks.md")" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
confere 'por_sprint com sprint_atual 02: o escopo e so a sprint-02' "$r"
escopo "$aux/antiga.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$(printf 'escopo=trabalho\ntasks=%s\ntasks=%s' "$pasta/sprint-01/tasks.md" "$pasta/sprint-02/tasks.md")" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
confere 'por_trabalho: o escopo e o trabalho inteiro, em ordem, sem pasta fora de sprint-NN' "$r"
entrega "$aux/plan.md" "sprint_atual: planejamento
prs:
$(item planejamento aberto null null null)"
escopo "$aux/plan.md"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = 'escopo=planejamento' ]
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
confere 'PR de planejamento: escopo=planejamento, sem tasks' "$r"
entrega "$aux/entre.md" "entrega: por_sprint
sprint_atual: null
prs:
$(item planejamento merged $SHA_A humano $SHA_B)"
escopo "$aux/entre.md"
[ "$rc" = 2 ] && [ ! -s "$aux/out" ]
confere 'por_sprint sem sprint aberta (entre o planejamento e a 01): sai 2, sem escopo' $?
mkdir -p "$aux/so01/sprint-01"; cp "$pasta/sprint-01/tasks.md" "$aux/so01/sprint-01/"
escopo "$aux/s02.md" "$aux/so01"
[ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'sprint-02' "$aux/err"
confere 'sprint_atual 02 sem sprint-02/tasks.md: sai 2' $?
mkdir -p "$aux/buraco"; cp -R "$pasta/sprint-01" "$pasta/sprint-02" "$aux/buraco/"; mkdir -p "$aux/buraco/sprint-03"
escopo "$aux/antiga.md" "$aux/buraco"
[ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'sprint-03' "$aux/err"
confere 'por_trabalho com sprint-03 sem tasks.md: sai 2 (nenhuma sprint e omitida)' $?
mkdir -p "$aux/dir/sprint-02/tasks.md"
escopo "$aux/s02.md" "$aux/dir"
[ "$rc" = 2 ] && [ ! -s "$aux/out" ]
confere 'tasks.md que nao e arquivo regular: sai 2' $?
escopo "$aux/s02.md" "$aux/nao-existe"
[ "$rc" = 2 ] && [ ! -s "$aux/out" ]
confere 'pasta do trabalho inexistente: sai 2' $?
# Nome de pasta com quebra de linha (CodeAnt no mergex#93): o grep por linha aceitava
# o prefixo `sprint-NN` e o caminho emitido se partia em duas linhas `tasks=`
mkdir -p "$aux/nl/sprint-01" "$aux/nl/sprint-02"$'\n'"lixo"
cp "$pasta/sprint-01/tasks.md" "$aux/nl/sprint-01/"; cp "$pasta/sprint-01/tasks.md" "$aux/nl/sprint-02"$'\n'"lixo/"
escopo "$aux/antiga.md" "$aux/nl"
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$(printf 'escopo=trabalho\ntasks=%s' "$aux/nl/sprint-01/tasks.md")" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
confere 'pasta com quebra de linha no nome nao e sprint-NN: fica fora do escopo' "$r"
# sprint-NN que é link para fora da pasta (CodeAnt no login#93): o [ -d ] segue o link, e
# as tasks de fora entravam no escopo. Recusa (sai 2), nos dois ramos; nunca omite.
mkdir -p "$aux/fora/sprint-09" "$aux/lnk/sprint-01"
cp "$pasta/sprint-01/tasks.md" "$aux/lnk/sprint-01/"; cp "$pasta/sprint-01/tasks.md" "$aux/fora/sprint-09/"
ln -s "$aux/fora/sprint-09" "$aux/lnk/sprint-02" 2>/dev/null
if [ -L "$aux/lnk/sprint-02" ]; then
  escopo "$aux/antiga.md" "$aux/lnk"
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'sprint-02' "$aux/err"
  r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
  confere 'por_trabalho com sprint-NN que e link: sai 2, sem as tasks de fora' "$r"
  escopo "$aux/s02.md" "$aux/lnk"
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'sprint-02' "$aux/err"
  r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
  confere 'sprint_atual 02 com sprint-02 que e link: sai 2' "$r"
  # a propria --pasta, ou um ancestral, que e link para fora da raiz (CodeAnt no login#95)
  fora2="$(mktemp -d)"; mkdir -p "$fora2/trab/sprint-02"; cp "$pasta/sprint-01/tasks.md" "$fora2/trab/sprint-02/"
  ln -s "$fora2/trab" "$aux/pasta-link"; ln -s "$fora2" "$aux/anc-link"
  escopo "$aux/s02.md" "$aux/pasta-link"
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'fora da raiz' "$aux/err"
  r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
  confere '--pasta que e link para fora da raiz: sai 2, sem as tasks de fora' "$r"
  escopo "$aux/s02.md" "$aux/anc-link/trab"
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && grep -q 'fora da raiz' "$aux/err"
  r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
  confere 'ancestral da --pasta que e link para fora da raiz: sai 2' "$r"
  rm -rf "$fora2"
else
  printf '  pula  sprint-NN que e link (este sistema nao cria link simbolico; o CI em Linux cobre)\n'
fi
bash "$leitor" --entrega "$aux/s02.md" --rev HEAD --escopo-de-tasks --pasta "$pasta" >/dev/null 2>&1
[ "$?" = 64 ]; confere '--escopo-de-tasks nao aceita --rev (o escopo e lido do disco)' $?
bash "$leitor" --entrega "$aux/s02.md" --escopo-de-tasks >/dev/null 2>&1
[ "$?" = 64 ]; confere '--escopo-de-tasks sem --pasta: uso (64)' $?
bash "$leitor" --entrega "$aux/s02.md" --pasta "$pasta" >/dev/null 2>&1
[ "$?" = 64 ]; confere '--pasta so com --escopo-de-tasks: uso (64)' $?

# A sprint 01 entregue com a 02 pendente: no escopo, V11 passa e a V1 nao ve a 02
entrega "$aux/v11.md" "entrega: por_sprint
sprint_atual: 01
prs:
$(item planejamento merged $SHA_A humano $SHA_B)
$(item 01 null null null null)"
sed -i "s/^commits: \[\]\$/commits:\n  - seq: 1\n    task: T-01.01\n    commit: $SHA_C/" "$aux/v11.md"
escopo "$aux/v11.md"
lista="$(sed -n 's/^tasks=//p' "$aux/out")"
# shellcheck disable=SC2086
[ "$rc" = 0 ] && [ "$lista" = "$pasta/sprint-01/tasks.md" ] \
  && [ "$(bash "$scripts/prova-de-commit.sh" --verificar "$aux/v11.md" $lista 2>/dev/null | sed -n 1p)" = V11=OK ] \
  && ! grep -q 'status: pendente' $lista
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
confere 'sprint 01 entregue com a 02 pendente: o escopo e a 01, V11 OK e nenhuma task pendente' "$r"

# O bloco do 02-prontidao calcula o escopo pelo leitor, e V11 e V12 o usam
bloco "$ref/02-prontidao.md" 'escopo-de-tasks' \
  | sed 's|<trabalho_id>|plan|g; s|<slug>|plan|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/#bash '$scripts'/#g" > "$aux/escopo.sh"
mkdir -p "$aux/blk/docs/entregas/plan" "$aux/blk/docs/sprintx/features"
cp "$aux/s02.md" "$aux/blk/docs/entregas/plan/ENTREGA.md"; cp -R "$pasta" "$aux/blk/docs/sprintx/features/plan"
r="$(cd "$aux/blk" && bash -c ". '$aux/escopo.sh' && printf '%s' \"\$tasks_do_escopo\"" 2>"$aux/err")"
[ -s "$aux/escopo.sh" ] && [ "$r" = docs/sprintx/features/plan/sprint-02/tasks.md ]
r=$?; [ "$r" = 0 ] || mostra "$aux/escopo.sh" "$aux/err"
confere '02-prontidao: o bloco do escopo devolve so a sprint do PR (por_sprint)' "$r"
bloco "$ref/02-prontidao.md" 'prova-de-commit.sh --verificar' | grep -q '\$tasks_do_escopo' \
  && bloco "$ref/02-prontidao.md" 'portao-v12.sh --verificar' | grep -q '\$tasks_do_escopo' \
  && ! grep -q 'sprint-\*/tasks.md' "$ref/02-prontidao.md" \
  && grep -Fq 'Leia o frontmatter de cada `tasks.md` do escopo' "$ref/02-prontidao.md" \
  && grep -Fq 'A **V9 não**' "$ref/02-prontidao.md" \
  && grep -Fq 'escopo-de-tasks' "$ref/integracao/sprintx.md" \
  && grep -Fq 'tasks.md` do escopo' "$ref/03-atencao-humana.md" \
  && grep -Fq 'tasks.md` do escopo' "$ref/04-descricao-pr.md" \
  && grep -Fq 'tasks do escopo' "$ref/05-pacote-qa.md"
confere 'V1, V11 e V12 no escopo; a V9 na uniao; E3, E4, E5 e a integracao com a sprintx citam o escopo' $?

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
# a base validada do --abrir-sprint é SHA local: o tamanho do formato do repositório (DM-315)
for formato in sha1 sha256; do
  git init -q --object-format="$formato" "$aux/oid-$formato"
  h="$(printf 'x' | git -C "$aux/oid-$formato" hash-object --stdin)"
  case "$formato" in sha1) outro="${h}000000000000000000000000" ;; sha256) outro="${h:0:40}" ;; esac
  (cd "$aux/oid-$formato" && bash "$leitor" --abrir-sprint 02 --base-validada-sha "$outro" --entrega "$aux/s01.md") >"$aux/out" 2>"$aux/err"; rc=$?
  [ "$rc" = 64 ] && grep -q 'base_validada_sha inválido' "$aux/err"
  confere "$formato: --abrir-sprint recusa base_validada_sha no tamanho do outro formato" $?
  (cd "$aux/oid-$formato" && bash "$leitor" --abrir-sprint 02 --base-validada-sha "$h" --entrega "$aux/s01.md") >"$aux/out" 2>"$aux/err"; rc=$?
  [ "$rc" != 64 ] && ! grep -q 'base_validada_sha inválido' "$aux/err"
  confere "$formato: --abrir-sprint aceita base_validada_sha de ${#h} hex como forma" $?
done

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
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: orquestrador' 'trabalho_id: plan' '---' \
    > "$d/docs/sprintx/features/plan/ORQUESTRADOR.md"
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
  e9 "$d" || quebra "checkpoint e9-merge do registro do planejamento em $d"
  g -C "$d" merge -q --no-edit main
}

# O bloco do E0 --sprint, com a base `main` e os scripts deste checkout
bloco "$ref/00-abertura.md" 'E0 --sprint' \
  | sed 's|<trabalho_id>|plan|g; s|<slug>|plan|g; s|<base>|main|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/#bash '$scripts'/#g" > "$aux/e0s.sh"
[ -s "$aux/e0s.sh" ]; confere '00-abertura tem o bloco do E0 --sprint' $?
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$RECON_CHAMADAS"' 'printf "ok=true\n"' > "$aux/recon-falso.sh"
chmod +x "$aux/recon-falso.sh"
sed "s#bash '$scripts'/reconciliacao-base.sh#bash '$aux/recon-falso.sh'#g" "$aux/e0s.sh" > "$aux/e0s-rec.sh"
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
  [ "${3:-}" = sem-e9 ] || e9 "$d" || quebra "checkpoint e9-merge do registro da sprint 01 em $d"
}

# a sprint 01 só abre com o planejamento merged
repo "$aux/r0" por_sprint
sed 's/^    estado: merged/    estado: aberto/; s/^    merge_sha: [0-9a-f]*/    merge_sha: null/; s/^    merge: humano/    merge: null/; s/^    base_sha: [0-9a-f]*/    base_sha: null/; s/^pr_estado: .*/pr_estado: aberto/' \
  "$aux/r0/docs/entregas/plan/ENTREGA.md" > "$aux/e.tmp" && mv "$aux/e.tmp" "$aux/r0/docs/entregas/plan/ENTREGA.md"
cp "$aux/r0/docs/entregas/plan/ENTREGA.md" "$aux/r0-antes.md"
e0s "$aux/r0" 01
[ "$rc" = 1 ] && grep -q 'E9' "$aux/e0s.err" && cmp -s "$aux/r0/docs/entregas/plan/ENTREGA.md" "$aux/r0-antes.md"
confere 'E0 --sprint 01 com o planejamento ainda nao merged: recusa e manda rodar o E9, sem escrever' $?

sem_planejamento() { # <dir> — feature/plan com o plano por_sprint commitado e nenhuma entrega
  local d="$1"
  git init -q -b main "$d"; git -C "$d" config core.autocrlf false
  mkdir -p "$d/src"; printf 'a\n' > "$d/src/a.ts"
  g -C "$d" add -A; g -C "$d" commit -q -m base
  git -C "$d" switch -q -c feature/plan
  mkdir -p "$d/docs/sprintx/features/plan/sprint-01"
  printf '%s\n' '---' 'kind: planejamento' 'trabalho_id: plan' 'entrega: por_sprint' '---' \
    > "$d/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
  printf '%s\n' '---' 'kind: plano' 'trabalho_id: plan' 'tasks: []' '---' \
    > "$d/docs/sprintx/features/plan/sprint-01/tasks.md"
  g -C "$d" add -A; g -C "$d" commit -q -m 'docs(sprintx): planejamento feito fora da F5' -m 'Trabalho: plan'
}
# DM-330 (decisao do dono, 2026-11-16; substitui a recusa da DM-329): sem PR de
# planejamento, o por_sprint abre a sprint 01 e o plano vai junto no PR dela. O limite do
# PR (E7, L3) e que separa o plano grande, nao o E0
sem_entrega_diz_o_caso_1() {
  grep -q 'caso 1' "$aux/e0s.err" && grep -Fq 'docs/entregas/plan/ENTREGA.md' "$aux/e0s.err"
}
sem_planejamento "$aux/sp1"
e0s "$aux/sp1" 01
[ "$rc" = 2 ] && sem_entrega_diz_o_caso_1 && [ ! -e "$aux/sp1/docs/entregas" ] && [ -z "$(git -C "$aux/sp1" status --porcelain)" ]
r=$?; [ "$r" = 0 ] || { echo "        (saiu $rc)"; mostra "$aux/e0s.err"; }
confere 'E0 --sprint 01 sem ENTREGA.md: manda criar pelo caso 1 do passo 5, sem escrever' "$r"

sem_planejamento "$aux/sp2"
entrega "$aux/sp2/docs/entregas/plan/ENTREGA.md" 'branch: feature/plan
branch_base: main
sprint_atual: null
prs: []'
printf '%s
' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: orquestrador' 'trabalho_id: plan' '---'   > "$aux/sp2/docs/sprintx/features/plan/ORQUESTRADOR.md"
g -C "$aux/sp2" add -A; g -C "$aux/sp2" commit -q -m 'docs(mergex): entrega sem planejamento' -m 'Trabalho: plan'
cp -r "$aux/sp2" "$aux/sp3"
e0s "$aux/sp2" 01
rc_e0=$rc
le_repo "$aux/sp2"
[ "$rc_e0" = 0 ] && [ "$rc" = 0 ] && [ "$(linha entrega)" = por_sprint ] && [ "$(linha sprint_atual)" = 01 ]   && [ "$(grep -c '^pr=' "$aux/out")" = 1 ] && grep -q '^pr=01' "$aux/out"   && grep -qx "base_validada_sha: $(git -C "$aux/sp2" merge-base HEAD main)" "$aux/sp2/docs/entregas/plan/ENTREGA.md"   && grep -q 'PR da sprint 01' "$aux/e0s.err"
r=$?; [ "$r" = 0 ] || { echo "        (saiu $rc_e0)"; mostra "$aux/e0s.err" "$aux/err"; }
confere 'E0 --sprint 01 sem PR de planejamento (DM-330): abre a 01, reancora a base e avisa que o plano vai no PR dela' "$r"

(cd "$aux/sp2" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t   bash "$scripts/persistir-metodo.sh" --persistir --entrega docs/entregas/plan/ENTREGA.md     --origem sprintx --trabalho plan --checkpoint e0-abertura) >"$aux/pm.out" 2>"$aux/pm.err"; rc=$?
[ "$rc" = 0 ] && git -C "$aux/sp2" log -1 --format=%B | grep -qx 'Metodo: e0-abertura'
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e0-abertura persiste a sprint 01 aberta sem PR de planejamento' "$r"

# DM-332 (CodeAnt no conselhos-municipais#346): o caso 1 e a abertura da 01 sem commit no meio.
# O ENTREGA.md ainda nao esta em HEAD, e o e0-abertura o persiste inteiro, com a prova do caso 1.
sem_planejamento "$aux/sp4"
printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: orquestrador' 'trabalho_id: plan' '---' \
  > "$aux/sp4/docs/sprintx/features/plan/ORQUESTRADOR.md"
g -C "$aux/sp4" add -A; g -C "$aux/sp4" commit -q -m 'docs(sprintx): orquestrador' -m 'Trabalho: plan'
entrega "$aux/sp4/docs/entregas/plan/ENTREGA.md" 'branch: feature/plan
branch_base: main
sprint_atual: null
prs: []'
cp -r "$aux/sp4" "$aux/sp5"
e0s "$aux/sp4" 01; rc_e0=$rc
pm_novo() { # pm_novo <repo> [verificar]
  (cd "$1" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    bash "$scripts/persistir-metodo.sh" --"${2:-persistir}" --entrega docs/entregas/plan/ENTREGA.md \
    --origem sprintx --trabalho plan --checkpoint e0-abertura) >"$aux/pm.out" 2>"$aux/pm.err"; rc=$?
}
pm_novo "$aux/sp4" verificar
[ "$rc_e0" = 0 ] && [ "$rc" != 0 ] && ! grep -qx 'ok=true' "$aux/pm.out"
r=$?; [ "$r" = 0 ] || { echo "        (e0 $rc_e0, verificar $rc)"; mostra "$aux/e0s.err" "$aux/pm.err"; }
confere 'e0-abertura --verificar com o ENTREGA.md novo, fora de HEAD: pendente, nunca ok=true' "$r"
pm_novo "$aux/sp4"
[ "$rc" = 0 ] && git -C "$aux/sp4" log -1 --format=%B | grep -qx 'Metodo: e0-abertura' \
  && [ "$(git -C "$aux/sp4" show --name-only --format= HEAD)" = docs/entregas/plan/ENTREGA.md ] \
  && [ -z "$(git -C "$aux/sp4" status --porcelain)" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e0-abertura persiste o ENTREGA.md novo da sprint 01, so ele, sem commit antes (DM-332)' "$r"
pm_novo "$aux/sp4" verificar
[ "$rc" = 0 ] && grep -qx 'ok=true' "$aux/pm.out"
confere 'depois de persistido, o e0-abertura --verificar sai ok=true' $?
# o ENTREGA.md novo que nao abre a 01 (o caso 1 puro) nao e abertura: recusa, sem commit
h="$(git -C "$aux/sp5" rev-parse HEAD)"
pm_novo "$aux/sp5"
[ "$rc" != 0 ] && grep -q 'ausente de HEAD' "$aux/pm.err" && [ "$(git -C "$aux/sp5" rev-parse HEAD)" = "$h" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e0-abertura com o ENTREGA.md novo sem a sprint 01 aberta: recusa, sem commit' "$r"

(cd "$aux/sp3" && bash "$leitor" --abrir-sprint 02 --base-validada-sha "$(git rev-parse main)"   --entrega docs/entregas/plan/ENTREGA.md) >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 1 ] && grep -q 'a próxima é a 01' "$aux/err"
confere '--abrir-sprint 02 sem nenhum item: recusa, a proxima e a 01' $?
(cd "$aux/sp3" && bash "$leitor" --abrir-sprint 01 --base-validada-sha "$(git rev-parse main)"   --entrega docs/entregas/plan/ENTREGA.md) >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && grep -qx 'aberta=01' "$aux/out"
r=$?; [ "$r" = 0 ] || mostra "$aux/err"
confere '--abrir-sprint 01 sem o item de planejamento: o escritor abre a 01' "$r"

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
mkdir -p "$aux/r1/.expx"
printf '{configuração inválida\n' > "$aux/r1/.expx/fatiamento.json"
cp "$e" "$aux/r1-antes.md"
e0s "$aux/r1" 01
[ "$rc" = 0 ] && cmp -s "$e" "$aux/r1-antes.md"
confere 'E0 --sprint 01 registrado independe da configuração atual e retoma sem mudar' $?
rm -rf "$aux/r1/.expx"
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

# DM-330 de ponta a ponta: sem PR de planejamento, a sprint 01 fica na base do E0 (registrada_e0),
# e a 02 reancora com o merge da 01 como ancora da V9 (CodeAnt no mergex#98)
d="$aux/sp9"
git init -q -b main "$d"; git -C "$d" config core.autocrlf false
mkdir -p "$d/src"; printf 'a\n' > "$d/src/a.ts"
g -C "$d" add -A; g -C "$d" commit -q -m base
b9="$(git -C "$d" rev-parse HEAD)"
git -C "$d" switch -q -c feature/plan
mkdir -p "$d/docs/sprintx/features/plan/sprint-01" "$d/docs/sprintx/features/plan/sprint-02"
printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: planejamento' 'trabalho_id: plan' \
  'entrega: por_sprint' '---' > "$d/docs/sprintx/features/plan/00-PLANEJAMENTO.md"
printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: orquestrador' 'trabalho_id: plan' '---' \
  > "$d/docs/sprintx/features/plan/ORQUESTRADOR.md"
printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
  'tasks:' '  - id: T-01.01' '    status: pendente' '    arquivos:' '      cria: [src/b.ts]' \
  '      altera: []' '---' > "$d/docs/sprintx/features/plan/sprint-01/tasks.md"
printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: plano' 'trabalho_id: plan' \
  'tasks:' '  - id: T-02.01' '    status: pendente' '    arquivos:' '      cria: [src/c.ts]' \
  '      altera: []' '---' > "$d/docs/sprintx/features/plan/sprint-02/tasks.md"
entrega "$d/docs/entregas/plan/ENTREGA.md" "base_validada_sha: $b9
origem_base: registrada_e0
reconciliacoes: []
branch: feature/plan
branch_base: main
sprint_atual: null
prs: []"
g -C "$d" add -A; g -C "$d" commit -q -m 'docs(sprintx): plano e entrega sem planejamento' -m 'Trabalho: plan'
e="$aux/sp9/docs/entregas/plan/ENTREGA.md"
# a base do E0 entre aspas continua a do E0: o --abrir-sprint sem planejamento nao a troca pela
# base nova que recebe (CodeAnt no conselhos-municipais#350)
sed "s/^base_validada_sha: .*/base_validada_sha: \"$b9\"/" "$e" > "$aux/sp9-aspas.md"
(cd "$aux/sp9" && bash "$leitor" --abrir-sprint 01 --base-validada-sha 1111111111111111111111111111111111111111 \
  --entrega "$aux/sp9-aspas.md") >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && grep -qx "base_validada_sha=$b9" "$aux/out" && ! grep -q 1111111111 "$aux/sp9-aspas.md"
confere 'sem planejamento: base do E0 entre aspas nao e trocada pela nova' $?
# a trava do ENTREGA.md (pasta + marca .dono, DM-334) sai inteira no fim, e a ocupada recusa sem gravar
[ ! -e "$aux/sp9-aspas.md.lock" ]
confere 'trava do ENTREGA.md solta depois da gravacao (sem .dono sobrando)' $?
mkdir "$aux/sp9-aspas.md.lock"; printf '1\n' > "$aux/sp9-aspas.md.lock/.dono"; ck="$(cksum < "$aux/sp9-aspas.md")"
(cd "$aux/sp9" && bash "$leitor" --abrir-sprint 02 --base-validada-sha 1111111111111111111111111111111111111111 \
  --entrega "$aux/sp9-aspas.md") >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" != 0 ] && grep -q 'entrega ocupada' "$aux/err" && [ "$(cksum < "$aux/sp9-aspas.md")" = "$ck" ]
confere 'trava do ENTREGA.md ocupada: recusa e nao grava' $?
rm -rf "$aux/sp9-aspas.md.lock"
# a marca que nao se cria, sem outra marca na pasta, nao deixa a pasta orfa; a escrita do PID que
# falha depois da marca criada tambem nao (CodeAnt no conselhos-municipais#356, DM-336)
if [ "$(id -u)" != 0 ]; then
  mkdir -p "$aux/shim-mkdir"
  printf '%s\n' '#!/usr/bin/env bash' 'command -p mkdir "$@" || exit $?' \
    'for a; do case "$a" in *.lock) chmod 555 "$a" ;; esac; done' > "$aux/shim-mkdir/mkdir"
  chmod +x "$aux/shim-mkdir/mkdir"
  (cd "$aux/sp9" && PATH="$aux/shim-mkdir:$PATH" bash "$leitor" --abrir-sprint 02 \
    --base-validada-sha 1111111111111111111111111111111111111111 --entrega "$aux/sp9-aspas.md") >"$aux/out" 2>"$aux/err"; rc=$?
  [ "$rc" != 0 ] && [ ! -e "$aux/sp9-aspas.md.lock" ] && [ "$(cksum < "$aux/sp9-aspas.md")" = "$ck" ]
  confere 'trava do ENTREGA.md: marca que nao se cria sem outra marca tira a pasta' $?
  chmod -R u+rwx "$aux/sp9-aspas.md.lock" 2>/dev/null; rm -rf "$aux/sp9-aspas.md.lock"
else
  echo "  (root ignora permissao: caso da marca que nao se cria pulado)"
fi
(cd "$aux/sp9" && trap '' XFSZ && ulimit -f 0 && bash "$leitor" --abrir-sprint 02 \
  --base-validada-sha 1111111111111111111111111111111111111111 --entrega "$aux/sp9-aspas.md") >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" != 0 ] && [ ! -e "$aux/sp9-aspas.md.lock" ] && [ "$(cksum < "$aux/sp9-aspas.md")" = "$ck" ]
confere 'trava do ENTREGA.md: PID que nao se escreve tira a marca e a pasta' $?
# noclobber herdado (`set -C`) nao impede a escrita do PID na marca recem-criada (CodeAnt no sprintx#89)
cp "$e" "$aux/sp9-noclobber.md"; printf 'set -C\n' > "$aux/noclobber.env"
(cd "$aux/sp9" && BASH_ENV="$aux/noclobber.env" bash "$leitor" --abrir-sprint 01 \
  --base-validada-sha 1111111111111111111111111111111111111111 --entrega "$aux/sp9-noclobber.md") >"$aux/out" 2>"$aux/err"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$aux/sp9-noclobber.md.lock" ]
r=$?; [ "$r" = 0 ] || sed -n 1,5p "$aux/err"
confere 'trava do ENTREGA.md: noclobber herdado adquire e solta a trava' $r
rm -rf "$aux/sp9-aspas.md.lock"
abre "$aux/sp9" 01
grep -qx 'origem_base: registrada_e0' "$e" && grep -qx "base_validada_sha: $b9" "$e" && grep -q 'PR da sprint 01' "$aux/e0s.err"
confere 'sem planejamento: a sprint 01 abre na base do E0, sem reancorar (registrada_e0)' $?
task "$aux/sp9" src/b.ts T-01.01
v9 "$aux/sp9"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out"
r=$?; [ "$r" = 0 ] || mostra "$aux/v9.out"
confere 'sem planejamento: V9 da sprint 01 passa' "$r"
fecha01 "$aux/sp9" squash
g -C "$aux/sp9" merge -q --no-edit -X ours main
abre "$aux/sp9" 02
grep -qx 'origem_base: registrada_sprint' "$e" && grep -qx "base_validada_sha: $(git -C "$aux/sp9" rev-parse main)" "$e"
confere 'sem planejamento: a sprint 02 reancora na main nova (registrada_sprint)' $?
task "$aux/sp9" src/c.ts T-02.01
v9 "$aux/sp9"
[ "$rc" = 0 ] && grep -qx 'resultado=ok' "$aux/v9.out" && grep -qx 'origem_base=registrada_sprint' "$aux/v9.out"
r=$?; [ "$r" = 0 ] || mostra "$aux/v9.out"
confere 'sem planejamento: V9 da sprint 02 passa, ancorada no merge da 01' "$r"
printf 'z\n' > "$aux/sp9/src/z.ts"; g -C "$aux/sp9" add -A; g -C "$aux/sp9" commit -q -m 'feat: z' -m 'Trabalho: plan'
v9 "$aux/sp9"
[ "$rc" = 1 ] && [ "$(grep -c '^fora_do_plano' "$aux/v9.out")" = 1 ]
confere 'sem planejamento: V9 da sprint 02 so ve a 02 (src/z.ts fora)' $?

repo "$aux/r2" por_sprint
abre "$aux/r2" 01; task "$aux/r2" src/b.ts T-01.01
e8 "$aux/r2" https://github.com/dono/repo/pull/2 aberto
g -C "$aux/r2" add -A; g -C "$aux/r2" commit -q -m 'docs(mergex): E8' -m 'Trabalho: plan'
cp -R "$aux/r2" "$aux/r9"; cp -R "$aux/r2" "$aux/r9c"
fecha01 "$aux/r2" merge
g -C "$aux/r2" merge -q --no-edit main

# Uma cadeia legítima não pode prender o trabalho entre duas sprints. O E0
# verifica a cadeia já avançada até a main nova antes de reancorar a sprint.
cp -R "$aux/r2" "$aux/rrec"
erec="$aux/rrec/docs/entregas/plan/ENTREGA.md"
sed 's/^reconciliacoes: \[\]$/reconciliacoes:\n  - numero: 001\n    arquivo: RECONCILIACAO-BASE-001.md\n    b1_sha: 1111111111111111111111111111111111111111\n    m_sha: 2222222222222222222222222222222222222222/' \
  "$erec" > "$aux/e.tmp" && mv "$aux/e.tmp" "$erec"
sed "s/^base_validada_sha: .*/base_validada_sha: $(git -C "$aux/rrec" rev-parse main)/" \
  "$erec" > "$aux/e.tmp" && mv "$aux/e.tmp" "$erec"
: > "$aux/recon-chamadas"
(cd "$aux/rrec" && RECON_CHAMADAS="$aux/recon-chamadas" sprint=02 bash "$aux/e0s-rec.sh") >"$aux/e0s.out" 2>"$aux/e0s.err"; rc=$?
le_repo "$aux/rrec"
[ "$rc" = 0 ] && [ "$(linha sprint_atual)" = 02 ] \
  && grep -q -- '--verificar --entrega docs/entregas/plan/ENTREGA.md --origem sprintx --trabalho plan' "$aux/recon-chamadas"
resultado=$?
[ "$resultado" = 0 ] || mostra "$aux/e0s.err" "$aux/recon-chamadas"
confere 'E0 da sprint 02 aceita cadeia de reconciliacao verificada na base nova' "$resultado"

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
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "$*" >> "$GH_CHAMADAS"' \
  'read -r estado merge base <<< "${GH_RESPOSTA:-}"' \
  'case "$1" in' \
  '  pr) printf "{\"state\":\"%s\",\"mergeCommit\":{\"oid\":\"%s\"},\"commits\":[{}]}\\n" "$estado" "$merge" ;;' \
  '  api) printf "{\"parents\":[{\"sha\":\"%s\"},{\"sha\":\"0123456789012345678901234567890123456789\"}]}\\n" "$base" ;;' \
  'esac' \
  'exit "${GH_RC:-0}"' > "$aux/gh-falso/gh"
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
# O topo fica com `pr_url: null`, como o --abrir-sprint o deixa: a URL do PR da sprint
# vive so no item (conselhos#208, M10). Antes, este teste reescrevia o topo e escondia
# que o E9 lia o lugar errado.
grep -qx 'pr_url: null' "$aux/e9/docs/entregas/plan/ENTREGA.md"
confere 'E9: o topo da ENTREGA fica com pr_url null na entrega por sprint' $?
: > "$aux/gh-chamadas"
(cd "$aux/e9" && env PATH="$aux/gh-falso:$PATH" GH_CHAMADAS="$aux/gh-chamadas" GH_RESPOSTA="MERGED $SHA_C $SHA_A" bash "$aux/e9.sh") >"$aux/e9.out" 2>&1; e9_rc=$?
le_repo "$aux/e9"
[ "$e9_rc" = 0 ] && [ "$rc" = 0 ] && [ "$(linha fechada)" = 01 ] && [ "$(linha fechada_merge_sha)" = $SHA_C ] \
  && grep -q 'pr view https://github.com/dono/repo/pull/2 ' "$aux/gh-chamadas"
confere 'E9 com o PR da sprint atual mergeado pelo servico: grava o item da sprint' $?
[ "$e9_rc" = 0 ] || mostra "$aux/e9.out"

echo '== os references =='
# Na entrega por sprint o `pr_url` do topo e null: toda comparacao do E9 com "o PR atual" usa a
# URL do item (`atual_url`), e a marcacao de trabalho proprio olha os itens de `prs` (katosmv/login#34).
awk '/O PR é do trabalho atual quando/ { a = 1 } a { print } /Não toque em `branch`/ { exit }' "$ref/09-revisao.md" > "$aux/e9-atual.txt"
grep -q 'atual_url' "$aux/e9-atual.txt"
confere '09-revisao: o PR mergeado e o do trabalho atual pela URL do item (atual_url) na entrega por sprint' $?
awk '/^### A marcação de trabalho próprio/ { a = 1; next } a && /^### / { exit } a' "$ref/09-revisao.md" > "$aux/e9-proprio.txt"
grep -q '`prs`' "$aux/e9-proprio.txt"
confere '09-revisao: a marcacao de trabalho proprio olha os itens de prs' $?
! grep -q 'PR atual sem pr_url' "$ref/09-revisao.md" && grep -q 'PR atual sem \$campo_url' "$ref/09-revisao.md"
confere '09-revisao: a mensagem nomeia o campo lido (atual_url ou planejamento_url)' $?
grep -F '| Aberto pela mergex nesta máquina |' "$ref/09-revisao.md" | grep -q '`prs`'
confere '09-revisao: a tabela do passo diz que a marcacao olha os itens de prs' $?
grep -q 'atual_url' "$ref/10-estado.md"
confere '10-estado: o PR do trabalho atual pela atual_url na entrega por sprint' $?
awk '/^### O PR já existe/ || /PR já existe para esta branch/ { a = 1 } a' "$ref/07-abertura-pr.md" > "$aux/e7.txt"
grep -q 'sprint anterior' "$aux/e7.txt" && grep -q 'não é retomada' "$aux/e7.txt"
confere 'PR merged da sprint anterior nao e retomada (07-abertura-pr)' $?
grep -q -- '--registrar-pr' "$ref/08-registro.md" && grep -q 'última sprint' "$ref/08-registro.md"
confere '08-registro: o item da sprint pelo --registrar-pr; memox e fim de trabalho so na ultima sprint' $?
grep -q 'união acumulada' "$ref/08-registro.md" && grep -q '`arquivos_alterados`' "$ref/08-registro.md" \
  && grep -q 'faixa_atencao.*sprint.*substitui' "$ref/08-registro.md" \
  && grep -q 'sprints anteriores' "$ref/00-schema.md"
confere 'registro final acumula arquivos e faixas reais das sprints anteriores' $?
grep -q 'Com reconcilia' "$scripts/portao-v9.sh" \
  && grep -q 'PR fechado.*ancestral.*BASE' "$scripts/portao-v9.sh"
confere 'V9 com reconciliacao exclui da base o ultimo PR de sprint ja entregue' $?
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

grep -Fq 'rev-list --reverse --topo-order --parents "$HEAD_SHA"' "$scripts/portao-v9.sh" \
  && ! grep -Fq 'done 5< "$TMP_DIR/v-ordem"' "$scripts/portao-v9.sh"
confere 'V9 verifica rebaixamento em uma travessia do grafo, sem pares quadraticos' $?

# DM-311: o e9-merge persiste só a transição que o E9 grava, e o e8 exige o estado terminal
pm() { # <dir> <checkpoint> [persistir|verificar] — o persistir-metodo; rc em $rc
  (cd "$1" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    bash "$scripts/persistir-metodo.sh" --"${3:-persistir}" --entrega docs/entregas/plan/ENTREGA.md \
      --origem sprintx --trabalho plan --checkpoint "$2") >"$aux/pm.out" 2>"$aux/pm.err"; rc=$?
}
fecha01 "$aux/r9" merge sem-e9
e9e="docs/entregas/plan/ENTREGA.md"
for caso in alem outro naomerged; do
  d="$aux/r9-$caso"; cp -R "$aux/r9" "$d"
  case "$caso" in
    alem) printf '\nNota fora do registro do E9.\n' >> "$d/$e9e" ;;
    outro) printf 'x\n' > "$d/src/solto.ts" ;;
    naomerged) awk '{ l[NR] = $0 } /^    estado: merged$/ { u = NR } END { for (i = 1; i <= NR; i++) print (i == u ? "    estado: aberto" : l[i]) }' "$d/$e9e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$d/$e9e" ;;
  esac
  h="$(git -C "$d" rev-parse HEAD)"; pm "$d" e9-merge
  [ "$rc" = 1 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
  r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
  confere "e9-merge recusa ($caso) sem commitar nada" "$r"
done
d="$aux/r9-ok"; cp -R "$aux/r9" "$d"
pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge' && [ -z "$(git -C "$d" status --porcelain)" ] \
  && [ "$(git -C "$d" diff --name-only HEAD~1 HEAD)" = "$e9e" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e9-merge persiste o registro do merge da sprint 01, só o ENTREGA.md, com Metodo: e9-merge' "$r"
# o conteúdo provado é o que entra: um escritor entre a prova e o `git add`
# (aqui, um git falso que escreve no ENTREGA.md logo antes do add) não commita
mkdir -p "$aux/shim-add"
{ printf '#!/usr/bin/env bash\n'
  printf 'if [ "${1:-}" = add ] && [ "${2:-}" = -- ] && [ "${3:-}" = %s ]; then printf '"'"'\\nNota escrita depois da prova.\\n'"'"' >> "$3"; fi\n' "$e9e"
  printf 'exec %q "$@"\n' "$(command -v git)"; } > "$aux/shim-add/git"
chmod +x "$aux/shim-add/git"
d="$aux/r9-corrida"; cp -R "$aux/r9" "$d"
h="$(git -C "$d" rev-parse HEAD)"
PATH="$aux/shim-add:$PATH" pm "$d" e9-merge
[ "$rc" = 1 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && grep -q 'mudou entre a prova' "$aux/pm.err" \
  && grep -q 'Nota escrita depois da prova' "$d/$e9e"
r=$?; [ "$r" = 0 ] || { mostra "$aux/pm.err"; echo "        rc=$rc"; }
confere 'e9-merge recusa o ENTREGA.md que mudou entre a prova e o git add, sem commitar e sem desfazer a escrita' "$r"
# DM-319: entre o `git add` e o `git commit` rodam o gate de segredo e a
# validação da mensagem. Um `git add` de fora da trava nesse intervalo (aqui, um
# git falso que prepara outra coisa logo antes do commit) entra no commit; a
# conferência da árvore depois dele para, sem desfazer o commit local.
for caso in entrega solto pai; do
  mkdir -p "$aux/shim-commit-$caso"
  { printf '#!/usr/bin/env bash\n'
    printf 'if [ "${1:-}" = commit ]; then\n'
    if [ "$caso" = entrega ]; then
      printf '  printf '"'"'\\nNota preparada antes do commit.\\n'"'"' >> %q && %q add -- %q\n' "$e9e" "$(command -v git)" "$e9e"
    elif [ "$caso" = solto ]; then
      printf '  printf '"'"'x\\n'"'"' > src/solto.ts && %q add -- src/solto.ts\n' "$(command -v git)"
    else
      printf '  %q -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --only --allow-empty -m outro\n' "$(command -v git)"
    fi
    printf 'fi\nexec %q "$@"\n' "$(command -v git)"; } > "$aux/shim-commit-$caso/git"
  chmod +x "$aux/shim-commit-$caso/git"
  d="$aux/r9-commit-$caso"; cp -R "$aux/r9" "$d"
  h="$(git -C "$d" rev-parse HEAD)"
  PATH="$aux/shim-commit-$caso:$PATH" pm "$d" e9-merge
  [ "$rc" = 1 ] && [ "$(git -C "$d" rev-parse "HEAD~$([ "$caso" = pai ] && echo 2 || echo 1)")" = "$h" ] \
    && if [ "$caso" = pai ]; then grep -q 'outro commit entrou na branch' "$aux/pm.err" \
         && grep -q "git log $h\.\." "$aux/pm.err" && ! grep -q 'o índice mudou' "$aux/pm.err"
       else grep -q 'o índice mudou entre o git add e o git commit' "$aux/pm.err"; fi \
    && grep -q 'Não envie' "$aux/pm.err" && ! grep -q '^commit=' "$aux/pm.out"
  r=$?; [ "$r" = 0 ] || { mostra "$aux/pm.err"; echo "        rc=$rc"; }
  confere "e9-merge para quando o índice ou a branch muda entre o git add e o git commit ($caso), sem desfazer o commit local" "$r"
done
# o pai é o de antes do add: um commit de fora logo depois do write-tree (aqui,
# um git falso que commita ao fixar a árvore) não vira o pai esperado
mkdir -p "$aux/shim-wt"
{ printf '#!/usr/bin/env bash\n'
  printf 'if [ "${1:-}" = write-tree ]; then\n'
  printf '  t="$(%q write-tree)" || exit 1\n' "$(command -v git)"
  printf '  %q -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --only --allow-empty -m outro >/dev/null\n' "$(command -v git)"
  printf '  printf '"'"'%%s\\n'"'"' "$t"; exit 0\nfi\nexec %q "$@"\n' "$(command -v git)"; } > "$aux/shim-wt/git"
chmod +x "$aux/shim-wt/git"
d="$aux/r9-wt"; cp -R "$aux/r9" "$d"
h="$(git -C "$d" rev-parse HEAD)"
PATH="$aux/shim-wt:$PATH" pm "$d" e9-merge
[ "$rc" = 1 ] && [ "$(git -C "$d" rev-parse HEAD~2)" = "$h" ] && grep -q 'outro commit entrou na branch' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || { mostra "$aux/pm.err"; echo "        rc=$rc"; }
confere 'e9-merge para quando outro commit entra logo depois de fixada a árvore: o pai é o de antes do add' "$r"
# o catálogo do stage é comparado nome a nome, em NUL: um arquivo de fora cujo
# nome tem quebra de linha e repete o caminho do catálogo não se confunde com ele
mkdir -p "$aux/shim-nl"
{ printf '#!/usr/bin/env bash\n'
  printf 'if [ "${1:-}" = write-tree ]; then\n'
  printf '  n="%s"$'"'"'\\n'"'"'"%s"\n' "$e9e" "$e9e"
  printf '  mkdir -p "${n%%/*}" && printf '"'"'x\\n'"'"' > "$n" && %q add -- "$n"\nfi\n' "$(command -v git)"
  printf 'exec %q "$@"\n' "$(command -v git)"; } > "$aux/shim-nl/git"
chmod +x "$aux/shim-nl/git"
d="$aux/r9-nl"; cp -R "$aux/r9" "$d"
h="$(git -C "$d" rev-parse HEAD)"
PATH="$aux/shim-nl:$PATH" pm "$d" e9-merge
[ "$rc" = 1 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && grep -q 'diverge do catálogo exato' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || { mostra "$aux/pm.err"; echo "        rc=$rc"; }
confere 'e9-merge recusa o arquivo de fora com quebra de linha no nome que repete o caminho do catálogo' "$r"
# core.autocrlf=true: o blob é LF e o disco é CRLF; o replay parte do ENTREGA.md
# de HEAD como o checkout o escreve, e o commit leva o blob LF de sempre
d="$aux/r9-autocrlf"; cp -R "$aux/r9" "$d"
g -C "$d" config core.autocrlf true
sed 's/$/\r/' "$d/$e9e" > "$aux/e.tmp" && cat "$aux/e.tmp" > "$d/$e9e"
pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge' \
  && ! git -C "$d" show "HEAD:$e9e" | grep -q $'\r' && [ -z "$(git -C "$d" status --porcelain)" ]
r=$?; [ "$r" = 0 ] || { mostra "$aux/pm.err"; echo "        rc=$rc"; }
confere 'e9-merge com core.autocrlf=true: disco CRLF, blob LF, commit do registro' "$r"
# a base histórica que o --completar-base preenche também
d="$aux/r9-base"; cp -R "$aux/r9-ok" "$d"
le_repo "$d"; pl="$(grep '^pr=planejamento' "$aux/out")"
psha="$(printf '%s' "$pl" | cut -f3)"; pbase="$(printf '%s' "$pl" | cut -f4)"
awk -v b="$pbase" '{ sub("^    base_sha: " b "$", "    base_sha: null"); print }' "$d/$e9e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$d/$e9e"
g -C "$d" add -A; g -C "$d" commit -q -m 'docs: item legado sem base' -m 'Trabalho: plan'
(cd "$d" && bash "$leitor" --completar-base planejamento --merge-sha "$psha" --base-sha "$pbase" --entrega "$e9e") >/dev/null 2>&1
pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge'
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e9-merge persiste a base histórica do --completar-base' "$r"
# o e8 sem estado terminal: recusa no verificar e no persistir (o noop não passa mais)
d="$aux/r9-ok"
pm "$d" e8 verificar; a="$rc"; pm "$d" e8; b="$rc"
[ "$a" = 1 ] && [ "$b" = 1 ] && grep -q 'e8 sem estado terminal' "$aux/pm.err" && ! grep -qx 'noop=true' "$aux/pm.out"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 com estado: aberto recusa no verificar e no persistir, sem noop' "$r"
d="$aux/r9-e8"; cp -R "$aux/r9-ok" "$d"
sed -e 's/^estado: .*/estado: entregue/' -e 's/^portao: .*/portao: pronto/' -e 's/^entregue_em: .*/entregue_em: null/' "$d/$e9e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$d/$e9e"
pm "$d" e8
[ "$rc" = 1 ] && grep -q 'e8 com estado: entregue exige' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 com estado: entregue sem entregue_em recusa' "$r"
# entregue sem push_feito: o campo é true ou false, mas tem de existir
sed -i -e 's/^entregue_em: .*/entregue_em: 2026-11-03/' -e '/^push_feito:/d' "$d/$e9e"
pm "$d" e8
[ "$rc" = 1 ] && grep -q 'push_feito: ausente' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 com estado: entregue sem push_feito recusa' "$r"
# entregue com falha registrada: causa: null só vale com falhas_portao vazia
printf '%s\n' 'push_feito: true' 'entregue_em: 2026-11-03' > "$aux/pf"; sed -i -e '/^estado: entregue$/r '"$aux/pf" -e 's/^falhas_portao: .*/falhas_portao: [v1]/' "$d/$e9e"
grep -q '^falhas_portao:' "$d/$e9e" || sed -i 's/^estado: entregue$/estado: entregue\nfalhas_portao: [v1]/' "$d/$e9e"
pm "$d" e8
[ "$rc" = 1 ] && grep -q 'falhas_portao que não bate com causa: null' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 com estado: entregue e falhas_portao não vazia recusa' "$r"
# o bloqueado: a causa é a que falhas_portao deriva
awk '/^estado:/ && !x { print "estado: bloqueado"; print "portao: bloqueado"; print "falhas_portao: [v1]"; print "causa: suite_reprovada"; print "entregue_em: null"; print "push_feito: false"; x = 1; next }
  /^(portao|falhas_portao|causa|entregue_em|push_feito):/ { next } { print }' "$d/$e9e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$d/$e9e"
pm "$d" e8
[ "$rc" = 1 ] && grep -q 'não deriva de falhas_portao' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 bloqueado com causa que não deriva de falhas_portao recusa' "$r"
sed -i 's/^causa: suite_reprovada$/causa: tarefa_nao_concluida/' "$d/$e9e"
pm "$d" e8
[ "$rc" = 0 ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e8 com o fechamento bloqueado completo, causa derivada de falhas_portao, persiste' "$r"
# o E9 de ontem: o replay de hoje difere só na data de atualizado_em, também em CRLF
d="$aux/r9-ontem"; cp -R "$aux/r9" "$d"
sed -i 's/^atualizado_em: .*/atualizado_em: 2026-01-01/' "$d/$e9e"
pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge'
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e9-merge aceita o registro do E9 feito noutro dia (só atualizado_em difere)' "$r"
d="$aux/r9c"
sed -i 's/$/\r/' "$d/$e9e"; g -C "$d" add -A; g -C "$d" commit -q -m 'docs: ENTREGA.md em CRLF' -m 'Trabalho: plan'
fecha01 "$d" merge sem-e9
sed -i 's/^atualizado_em: [0-9-]*\r$/atualizado_em: 2026-01-01\r/' "$d/$e9e"
grep -q $'^atualizado_em: 2026-01-01\r$' "$d/$e9e" && pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge'
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e9-merge em ENTREGA.md CRLF com o registro de outro dia' "$r"

grep -q -- '--checkpoint e9-merge' "$ref/09-revisao.md" && grep -q 'checkpoint `e9-merge`' "$ref/00-abertura.md" \
  && grep -q 'estado terminal' "$ref/08-registro.md"
confere '09-revisao manda persistir o registro pelo e9-merge, 00-abertura dá a ordem, 08-registro exige o terminal no e8' $?
# o nome solto dá "command not found" fora do PATH (CodeAnt no conselhos#256,
# DM-314): o SKILL.md diz como rodar; o comando que abre a linha de um passo e
# todo bloco cercado levam o caminho completo
nomes="$(cd "$scripts" && ls ./*.sh | sed 's|^\./||; s|\.sh$||' | paste -sd'|' -)"
soltos="$(awk -v re="(^|[ \t(\"/])(bash )?([.][.][.]/)?($nomes)[.]sh( |$)" '
  FNR == 1 { dentro = 0 }
  /^ *```/ { dentro = !dentro; next }
  (dentro || /^ +`[a-z-]+[.]sh /) {
    # cada chamada pelo caminho sai antes da busca: a linha que tem uma não isenta a outra
    l = $0; gsub(/[.]claude\/skills\/mergex\/scripts\/[a-z0-9-]+[.]sh/, "<caminho>", l)
    if (l ~ re) print FILENAME ":" FNR
  }
' "$ref"/*.md "$ref"/integracao/*.md "$raiz/.claude/skills/mergex/SKILL.md" "$raiz"/.claude/commands/*.md)"
grep -Fq 'Os scripts não estão no PATH.' "$raiz/.claude/skills/mergex/SKILL.md" \
  && grep -Fq '`bash .claude/skills/mergex/scripts/persistir-metodo.sh --persistir --entrega' "$ref/09-revisao.md" \
  && [ -z "$soltos" ]
r=$?; [ "$r" = 0 ] || printf '        nome solto em: %s\n' $soltos
confere 'scripts pelo caminho: a regra no SKILL.md, o passo 7 do E9 e nenhum bloco ou passo com o nome solto' "$r"
# A entrega por trabalho não grava `pr_estado` depois do merge (DM-317): o
# serviço é a fonte do estado final, e a branch já integrada não recebe commit.
# O registro em `prs` segue só na entrega de planejamento e na de sprint.
pt='Na entrega por trabalho, o E9 não grava `pr_estado` no `ENTREGA.md`'
grep -Fq "$pt" "$ref/09-revisao.md" \
  && ! grep -Fq 'Atualize `pr_estado: merged` no `ENTREGA.md` correspondente' "$ref/09-revisao.md" \
  && grep -Fq 'na entrega por trabalho, fica com o retrato do E7' "$ref/00-schema.md" \
  && grep -Fq 'na entrega por trabalho, fica com o retrato do E7' "$ref/08-registro.md" \
  && grep -Fq 'O E9 também não o grava' "$ref/integracao/runx.md"
confere 'entrega por trabalho: o E9 não grava pr_estado depois do merge (09-revisao, schema, 08-registro, runx)' $?
# e quem tentar o e9-merge nela recebe a regra, nas duas origens
d="$aux/por-trabalho"; mkdir -p "$d/docs/entregas/plan" "$d/docs/sprintx/features/plan" "$d/docs/manutencao/plan"
g -C "$d" init -q -b fix/plan
for o in sprintx runx; do
  printf -- '---\nexpx_schema: 1\nexpx_tool: %s\nkind: entrega\ntrabalho_id: plan\nestado: entregue\nbranch: fix/plan\nbranch_base: main\npr_url: https://github.com/o/r/pull/9\npr_estado: aberto\nprs: []\natualizado_em: 2026-11-01\n---\n' "$o" > "$d/docs/entregas/plan/ENTREGA.md"
  printf -- '---\nkind: orquestrador\ntrabalho_id: plan\n---\n' | tee "$d/docs/sprintx/features/plan/ORQUESTRADOR.md" > "$d/docs/manutencao/plan/ORQUESTRADOR.md"
  g -C "$d" add -A; g -C "$d" commit -q -m "entrega por trabalho ($o)"
  sed -i 's/^pr_estado: aberto$/pr_estado: merged/' "$d/docs/entregas/plan/ENTREGA.md"
  h="$(git -C "$d" rev-parse HEAD)"
  (cd "$d" && bash "$scripts/persistir-metodo.sh" --persistir --entrega docs/entregas/plan/ENTREGA.md \
    --origem "$o" --trabalho plan --checkpoint e9-merge) >"$aux/pm.out" 2>"$aux/pm.err"; rc=$?
  [ "$rc" = 1 ] && grep -q 'entrega por trabalho' "$aux/pm.err" && grep -q 'DM-317' "$aux/pm.err" \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
  r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
  confere "e9-merge na entrega por trabalho ($o) recusa com a regra da DM-317, sem commitar" "$r"
  git -C "$d" checkout -q -- docs/entregas/plan/ENTREGA.md
done
# A entrega por sprint entre o planejamento e a sprint 01 também tem sprint_atual:
# null, e o reparo --completar-base dela segue pelo e9-merge (Codex).
d="$aux/entre-sprints"; repo "$d" por_sprint
le_repo "$d"; pl="$(grep '^pr=planejamento' "$aux/out")"
psha="$(printf '%s' "$pl" | cut -f3)"; pbase="$(printf '%s' "$pl" | cut -f4)"
awk -v b="$pbase" '/^sprint_atual: / { print "entrega: por_sprint"; print "sprint_atual: null"; next }
  { sub("^    base_sha: " b "$", "    base_sha: null"); print }' "$d/$e9e" > "$aux/e.tmp" && mv "$aux/e.tmp" "$d/$e9e"
g -C "$d" add -A; g -C "$d" commit -q -m 'docs: entre o planejamento e a sprint 01, item legado sem base' -m 'Trabalho: plan'
le_repo "$d"
grep -qx 'sprint_atual=null' "$aux/out" && grep -qx 'entrega=por_sprint' "$aux/out"
confere 'controle: entrega por sprint com sprint_atual null antes da sprint 01' $?
(cd "$d" && bash "$leitor" --completar-base planejamento --merge-sha "$psha" --base-sha "$pbase" --entrega "$e9e") >/dev/null 2>&1
pm "$d" e9-merge
[ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e9-merge'
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.err"
confere 'e9-merge persiste o --completar-base da entrega por sprint entre o planejamento e a sprint 01' "$r"

echo '== a abertura do E0 persistida antes da main seguinte (conselhos, onda 2; DM-328) =='

# A sequência do conselhos: e9-merge da sprint 01 → merge da main (anterior ao E0) →
# E0 --sprint 02 → E1 → a main entra de novo → --registrar desse merge. O
# reconciliacao-base lê B0 do ENTREGA.md de M^1; sem a abertura commitada, B0 era a
# base da sprint 01, o merge anterior ao E0 voltava à fila e a recusa dizia "ordem".
rb() { # <dir> <M> — o --registrar; saída em $aux/rb.out/.err, código em $rc
  (cd "$1" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    bash "$scripts/reconciliacao-base.sh" --registrar --entrega docs/entregas/plan/ENTREGA.md \
      --origem sprintx --trabalho plan --merge "$2" --) >"$aux/rb.out" 2>"$aux/rb.err"; rc=$?
}
# traz_main <dir> <ruim|bom> — merge da main com Trabalho/Integra-base; `ruim` deixa o
# Co-Authored-By num parágrafo separado (os controles deixam de ser trailers)
traz_main() {
  local b; b="$(git -C "$1" rev-parse main)"
  if [ "$2" = ruim ]; then
    g -C "$1" merge -q --no-ff main -m 'chore: traz a main' -m "Trabalho: plan
Integra-base: $b" -m 'Co-Authored-By: X <x@x>'
  else
    g -C "$1" merge -q --no-ff main -m 'chore: traz a main' -m "Trabalho: plan
Integra-base: $b
Co-Authored-By: X <x@x>"
  fi
}
anda_main() { # <dir> <arquivo> — um commit na main sem trocar a branch (a árvore pode estar suja)
  git -C "$1" worktree add -q "$aux/wt-main" main
  printf 'm\n' > "$aux/wt-main/$2"; g -C "$aux/wt-main" add -A; g -C "$aux/wt-main" commit -q -m "main: $2"
  git -C "$1" worktree remove --force "$aux/wt-main"
}
e1_so_task() { # <dir> <arquivo> <task> — o E1 commita só o arquivo da task (o ENTREGA.md fica sujo)
  printf '%s\n' "$3" > "$1/$2"; g -C "$1" add -- "$2"
  g -C "$1" commit -q -m "feat: $3" -m "Task: $3
Trabalho: plan"
}
# ate_e0_02 <dir> <ruim|bom> — a sprint 01 entregue e mergeada, a main na branch, o E0 --sprint 02
ate_e0_02() {
  repo "$1" por_sprint
  abre "$1" 01; task "$1" src/b.ts T-01.01
  e8 "$1" https://github.com/dono/repo/pull/2 aberto
  g -C "$1" add -A; g -C "$1" commit -q -m 'docs(mergex): E8' -m 'Trabalho: plan'
  fecha01 "$1" merge
  traz_main "$1" "$2"
  e0s "$1" 02
  [ "$rc" = 0 ] || { echo "        (E0 --sprint 02 saiu $rc)"; mostra "$aux/e0s.err"; }
}
eo="docs/entregas/plan/ENTREGA.md"

for trailers in ruim bom; do
  d="$aux/onda2-$trailers"; ate_e0_02 "$d" "$trailers"
  base02="$(sed -n 's/^base_validada_sha: //p' "$d/$eo")"
  pm "$d" e0-abertura
  [ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e0-abertura' \
    && [ "$(git -C "$d" diff --name-only HEAD~1 HEAD)" = "$eo" ] \
    && git -C "$d" show "HEAD:$eo" | grep -qx 'sprint_atual: 02'
  r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
  confere "e0-abertura persiste a abertura da sprint 02, só o ENTREGA.md (merge anterior com trailers $trailers)" "$r"
  e1_so_task "$d" src/c.ts T-02.01
  anda_main "$d" src/r.ts; traz_main "$d" bom; m2="$(git -C "$d" rev-parse HEAD)"
  g -C "$d" add -- "$eo"; g -C "$d" commit -q -m 'docs: persiste metodo pre-e2 (simulado)' -m 'Trabalho: plan
Metodo: pre-e2'
  rb "$d" "$m2"
  [ "$rc" = 0 ] && grep -qx "b0=$base02" "$aux/rb.out"
  r=$?; [ "$r" = 0 ] || mostra "$aux/rb.out" "$aux/rb.err"
  confere "com a abertura persistida, a main seguinte registra com B0 = a base da sprint 02 (trailers $trailers antes do E0)" "$r"
done

# Sem o checkpoint: a recusa nomeia a abertura não persistida, não a "ordem"
d="$aux/onda2-sem"; ate_e0_02 "$d" bom
e1_so_task "$d" src/c.ts T-02.01
anda_main "$d" src/r.ts; traz_main "$d" bom; m2="$(git -C "$d" rev-parse HEAD)"
g -C "$d" add -- "$eo"; g -C "$d" commit -q -m 'docs: persiste metodo pre-e2 (simulado)' -m 'Trabalho: plan
Metodo: pre-e2'
rb "$d" "$m2"
[ "$rc" = 5 ] && grep -q 'e0-abertura' "$aux/rb.err" && ! grep -q 'registre os merges um por vez' "$aux/rb.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/rb.out" "$aux/rb.err"
confere 'sem a abertura persistida antes de M: --registrar recusa nomeando o e0-abertura, nao a ordem' "$r"

# A retomada da mesma sprint não grava nada: noop, sem commit, mesmo com o ENTREGA.md sujo do E1
d="$aux/onda2-retoma"; ate_e0_02 "$d" bom; pm "$d" e0-abertura
e1_so_task "$d" src/c.ts T-02.01
printf '\n' >> "$d/$eo"; h="$(git -C "$d" rev-parse HEAD)"
e0s "$d" 02; e0rc=$rc
pm "$d" e0-abertura
[ "$e0rc" = 0 ] && [ "$rc" = 0 ] && grep -qx 'noop=true' "$aux/pm.out" && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
confere 'retomada do E0 --sprint 02 ja persistida: e0-abertura e noop, sem commit' "$r"

# Mudança além da abertura: recusa, sem commit
d="$aux/onda2-alem"; ate_e0_02 "$d" bom
printf '\nNota fora da abertura.\n' >> "$d/$eo"; h="$(git -C "$d" rev-parse HEAD)"
pm "$d" e0-abertura
[ "$rc" != 0 ] && grep -q 'e0-abertura' "$aux/pm.err" && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
confere 'e0-abertura com o ENTREGA.md mudado alem da abertura: recusa, sem commit' "$r"

# Sem abertura nenhuma (CodeAnt no login#93): sprint_atual, base_validada_sha e origem_base
# ausentes em HEAD e no disco eram "a mesma abertura", e o --verificar dava ok=true. Não há
# o que persistir: recusa, nos dois modos, sem commit
d="$aux/onda2-sem-abertura"; repo "$d" por_sprint
sed -i.bak -e '/^sprint_atual:/d' -e '/^base_validada_sha:/d' -e '/^origem_base:/d' "$d/$eo" && rm -f "$d/$eo.bak"
g -C "$d" add -- "$eo"; g -C "$d" commit -q -m 'docs: entrega sem abertura' -m 'Trabalho: plan'
h="$(git -C "$d" rev-parse HEAD)"
pm "$d" e0-abertura verificar
[ "$rc" != 0 ] && ! grep -qx 'ok=true' "$aux/pm.out" && grep -q 'e0-abertura' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
confere 'e0-abertura --verificar sem abertura em HEAD nem no disco: recusa, nunca ok=true' "$r"
pm "$d" e0-abertura
[ "$rc" != 0 ] && ! grep -qx 'noop=true' "$aux/pm.out" && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
confere 'e0-abertura --persistir sem abertura: recusa, sem noop e sem commit' "$r"
# base_validada_sha: ~ (o nulo do YAML) em HEAD e no disco tambem nao e abertura (CodeAnt no login#95)
d="$aux/onda2-til"; repo "$d" por_sprint
sed -i.bak -e '/^sprint_atual:/d' -e 's/^base_validada_sha:.*/base_validada_sha: ~/' -e '/^origem_base:/d' "$d/$eo" && rm -f "$d/$eo.bak"
g -C "$d" add -- "$eo"; g -C "$d" commit -q -m 'docs: entrega com base nula' -m 'Trabalho: plan'
pm "$d" e0-abertura verificar
[ "$rc" != 0 ] && ! grep -qx 'ok=true' "$aux/pm.out" && grep -q 'e0-abertura' "$aux/pm.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/pm.out" "$aux/pm.err"
confere 'e0-abertura --verificar com base_validada_sha: ~ em HEAD e no disco: recusa, nunca ok=true' "$r"

# por_trabalho: a retomada depois do planejamento também reancora, e também persiste
bloco "$ref/00-abertura.md" 'E0, retomada sem --planejamento' \
  | sed 's|<trabalho_id>|plan|g; s|<slug>|plan|g; s|<base>|main|g' \
  | sed "s#bash \.claude/skills/mergex/scripts/#bash '$scripts'/#g" > "$aux/e0r.sh"
d="$aux/onda2-trab"; repo "$d" por_trabalho
(cd "$d" && bash "$aux/e0r.sh") >"$aux/e0r.out" 2>"$aux/e0r.err"; e0rc=$?
baset="$(git -C "$d" merge-base HEAD main)"
pm "$d" e0-abertura
[ "$e0rc" = 0 ] && [ "$rc" = 0 ] && git -C "$d" log -1 --format=%B | grep -qx 'Metodo: e0-abertura' \
  && git -C "$d" show "HEAD:$eo" | grep -qx "base_validada_sha: $baset" \
  && git -C "$d" show "HEAD:$eo" | grep -qx 'sprint_atual: null'
r=$?; [ "$r" = 0 ] || mostra "$aux/e0r.out" "$aux/e0r.err" "$aux/pm.err"
confere 'por_trabalho: a retomada depois do planejamento grava pelo leitor e o e0-abertura a persiste' "$r"
e1_so_task "$d" src/b.ts T-01.01
anda_main "$d" src/r.ts; traz_main "$d" bom; m2="$(git -C "$d" rev-parse HEAD)"
g -C "$d" add -- "$eo"; g -C "$d" commit -q -m 'docs: persiste metodo pre-e2 (simulado)' -m 'Trabalho: plan
Metodo: pre-e2'
rb "$d" "$m2"
[ "$rc" = 0 ] && grep -qx "b0=$baset" "$aux/rb.out"
r=$?; [ "$r" = 0 ] || mostra "$aux/rb.out" "$aux/rb.err"
confere 'por_trabalho: a main seguinte registra com B0 = a base reancorada' "$r"

# O escritor da retomada: grava uma vez, retoma sem gravar, recusa por_sprint e o planejamento aberto
entrega "$aux/ret.md" "sprint_atual: planejamento
base_validada_sha: $SHA_B
origem_base: registrada_e0
prs:
$(item planejamento merged $SHA_A humano $SHA_B)"
ret() { (cd "$aux/oid-sha1" && bash "$leitor" --retomar-planejamento --base-validada-sha "$2" --entrega "$1") >"$aux/out" 2>"$aux/err"; rc=$?; }
ret "$aux/ret.md" "$SHA_C"
[ "$rc" = 0 ] && grep -qx 'sprint_atual: null' "$aux/ret.md" && grep -qx "base_validada_sha: $SHA_C" "$aux/ret.md" \
  && grep -qx 'origem_base: registrada_sprint' "$aux/ret.md" && grep -qx 'pr_url: null' "$aux/ret.md" \
  && grep -qx 'entrega: por_trabalho' "$aux/ret.md"
r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err" "$aux/ret.md"
confere '--retomar-planejamento grava sprint_atual null, a base, registrada_sprint e entrega por_trabalho' "$r"
cp "$aux/ret.md" "$aux/ret-antes.md"; ret "$aux/ret.md" "$SHA_C"
[ "$rc" = 0 ] && grep -qx 'retomada=sim' "$aux/out" && cmp -s "$aux/ret.md" "$aux/ret-antes.md"
confere '--retomar-planejamento repetido com a mesma base: retomada, sem gravar' $?
# A base gravada entre aspas ou com comentário YAML é a mesma base (CodeAnt no mergex#93)
for forma in "\"$SHA_C\"" "'$SHA_C'" "$SHA_C # reancorada"; do
  sed "s/^base_validada_sha: .*/base_validada_sha: $forma/" "$aux/ret-antes.md" > "$aux/ret-q.md"
  cp "$aux/ret-q.md" "$aux/ret-q-antes.md"; ret "$aux/ret-q.md" "$SHA_C"
  [ "$rc" = 0 ] && grep -qx 'retomada=sim' "$aux/out" && cmp -s "$aux/ret-q.md" "$aux/ret-q-antes.md"
  r=$?; [ "$r" = 0 ] || mostra "$aux/out" "$aux/err"
  confere "--retomar-planejamento com a base gravada como [$forma]: retomada, sem gravar" "$r"
done
ret "$aux/ret.md" "$SHA_A"
[ "$rc" = 1 ] && cmp -s "$aux/ret.md" "$aux/ret-antes.md"
confere '--retomar-planejamento ja retomado com outra base: recusa, sem gravar' $?
cp "$aux/s01.md" "$aux/ret-s.md"; ret "$aux/ret-s.md" "$SHA_C"
[ "$rc" = 1 ] && cmp -s "$aux/ret-s.md" "$aux/s01.md"
confere '--retomar-planejamento em entrega por_sprint: recusa (quem abre e o --abrir-sprint)' $?
entrega "$aux/ret-a.md" "sprint_atual: planejamento
prs:
$(item planejamento aberto null null null)"
cp "$aux/ret-a.md" "$aux/ret-a-antes.md"; ret "$aux/ret-a.md" "$SHA_C"
[ "$rc" = 1 ] && grep -q 'E9' "$aux/err" && cmp -s "$aux/ret-a.md" "$aux/ret-a-antes.md"
confere '--retomar-planejamento com o planejamento nao merged: recusa e manda rodar o E9' $?

# Os controles fora do bloco final: o contrato diz o que houve, e o registrador repete
printf '%s\n' 'chore: traz a main' '' 'Trabalho: plan' "Integra-base: $SHA_C" '' 'Co-Authored-By: X <x@x>' > "$aux/msg-ruim"
printf '%s\n' 'chore: traz a main' '' 'Trabalho: plan' "Integra-base: $SHA_C" 'Co-Authored-By: X <x@x>' > "$aux/msg-boa"
bash "$scripts/contrato-de-commit.sh" --validar-integracao --trabalho plan --arquivo "$aux/msg-ruim" >/dev/null 2>"$aux/err"; r1=$?
bash "$scripts/contrato-de-commit.sh" --validar-integracao --trabalho plan --arquivo "$aux/msg-boa" >/dev/null 2>&1; r2=$?
[ "$r1" = 2 ] && grep -q 'fora do bloco final' "$aux/err" && [ "$r2" = 0 ]
r=$?; [ "$r" = 0 ] || mostra "$aux/err"
confere 'contrato: Trabalho/Integra-base fora do bloco final recusa dizendo isso; no mesmo bloco do Co-Authored-By passa' "$r"
printf '%s\n' 'feat: x' '' 'Task: T-01.01' 'Trabalho: plan' '' 'Co-Authored-By: X <x@x>' > "$aux/msg-e1"
bash "$scripts/contrato-de-commit.sh" --validar-e1 --trabalho plan --task T-01.01 --arquivo "$aux/msg-e1" >/dev/null 2>"$aux/err"
[ "$?" = 2 ] && grep -q 'fora do bloco final' "$aux/err"
confere 'contrato: Task/Trabalho do E1 fora do bloco final tambem e nomeado' $?
d="$aux/onda2-depois"; ate_e0_02 "$d" bom; pm "$d" e0-abertura
anda_main "$d" src/r.ts; traz_main "$d" ruim
anda_main "$d" src/s.ts; traz_main "$d" bom; m2="$(git -C "$d" rev-parse HEAD)"
rb "$d" "$m2"
[ "$rc" = 5 ] && grep -q 'fora do bloco final' "$aux/rb.err"
r=$?; [ "$r" = 0 ] || mostra "$aux/rb.out" "$aux/rb.err"
confere 'registrador: o merge pendente com os controles fora do bloco final e nomeado com o motivo do contrato' "$r"

grep -Fq -- '--checkpoint e0-abertura' "$ref/00-abertura.md" \
  && grep -Fq -- '--retomar-planejamento' "$ref/00-abertura.md" \
  && grep -Fq 'e0-abertura' "$ref/integracao/sprintx.md" \
  && grep -Fq 'e0-abertura' "$ref/01-commits.md" \
  && grep -Fq 'mesmo bloco' "$ref/01-commits.md" \
  && grep -Fq 'mesmo bloco' "$ref/11-reconciliacao-base.md"
confere '00-abertura manda persistir a abertura; 01-commits e 11-reconciliacao dao o modelo com os trailers no mesmo bloco' $?

printf '\n%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
