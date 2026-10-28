#!/usr/bin/env bash
#
# Bancada da V12 — task concluída sem revisão por task aprovada (portao-v12.sh).
#
# A V12 pergunta ao `conferir` do núcleo do expx se cada task `concluida` com commit
# registrado tem evidência de revisão aprovada NO COMMIT dela (o do último item da task em
# `ENTREGA.commits`). A mergex nunca lê nem escreve a evidência: quem grava é o `revisar`
# do núcleo (aqui, com a CLI falsa de `codeant-falsa.sh`), quem lê é o `conferir`.
# Mapeamento: DM-238; plano 2026-10-20-mergex-limites-do-codeant-parte-2.md, B1 emendado.
#
# Os únicos casos que mexem numa evidência são os que provam que a forma antiga não passa:
# tiram `chamada.issues` ou trocam uma issue de uma evidência gravada pelo `revisar`, ou
# trocam a versão.
#
# No Git Bash do Windows os casos que precisam da CLI falsa saem com `ok` e a nota
# "(o CI em Linux cobre)": sem link simbólico confiável, o núcleo não acha o pacote.
#
# Uso: bash scripts/ci/test-portao-v12.sh
#      V12=<outro script> bash scripts/ci/test-portao-v12.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
V12="${V12:-$REPO/.claude/skills/mergex/scripts/portao-v12.sh}"
copia="$REPO/scripts/ci/fixtures/candidatos/expx-nucleo"
nucleo_rel='.expx/marketplace/plugins/expx/nucleo/scripts'
# shellcheck source=codeant-falsa.sh
. "$REPO/scripts/ci/codeant-falsa.sh"

# nenhuma FATIA_* herdada do shell de quem roda os testes muda o que se mede aqui
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done

OK=0; FALHOU=0
passa()  { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
# P é o projeto da fixture, e só `projeto` o define: herdado de quem chama, `entrega` gravaria e
# commitaria a ENTREGA no checkout dele.
P=""

NODE_REAL="$(command -v node 2>/dev/null || true)"
[ -n "$NODE_REAL" ] || { echo 'test-portao-v12: node ausente (o conferir do nucleo e node)' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'test-portao-v12: jq ausente' >&2; exit 1; }
FALSA=0; codeant_falsa_suportada && FALSA=1
so_linux() { passa "$1 (o CI em Linux cobre)"; }
# no Git Bash o node nativo não entende o caminho do MSYS
nativo() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

# --- o núcleo montado (menos o ORIGEM), sem CR, com o perfil da CLI falsa no Linux -------
monta_nucleo() {
  local f
  while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")" && tr -d '\r' < "$copia/$f" > "$1/$f"
  done < <(cd "$copia" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
}
resposta() { # <arquivo> [<issues JSON>]
  printf '{"issues":%s,"meta":{"reviewed_files":"__include__","total_changed":0,"skipped":[],"capped":false,"max_files":40},"error":null,"noFiles":false}\n' \
    "${2:-[]}" > "$1"
}
resposta "$aux/resp-ok.json"
resposta "$aux/resp-achado.json" '[{"issue_content":"variavel nunca usada","relevant_file":"src/a.ts","start_line":1,"label":"bug"}]'
monta_nucleo "$aux/nucleo"
if [ "$FALSA" = 1 ]; then
  instala_codeant_falsa "$aux/falsa" "$aux/resp-ok.json" && nucleo_com_falsa "$aux/nucleo" "$aux/falsa" \
    || { echo 'test-portao-v12: nao montou a CLI falsa' >&2; exit 1; }
fi

# --- PATHs de teste ------------------------------------------------------------------------
# sem node: só os comandos que os scripts usam, cada um um embrulho (link não é confiável no Git Bash)
mkdir -p "$aux/sem-node" "$aux/espia" "$aux/corta"
for c in bash git mktemp rm mkdir cat grep cygpath find sort sed awk cut tr dirname uname head wc env ls cp mv; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$p" > "$aux/sem-node/$c"; chmod +x "$aux/sem-node/$c"
done
# espia: registra cada chamada ao node e segue para o real
printf '#!%s\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$BASH" "$aux/node.log" "$NODE_REAL" > "$aux/espia/node"
# corta: o conferir de verdade, com a última linha do stdout a menos e o mesmo código
printf '#!%s\nif [ "${2:-}" = conferir ]; then out="$("%s" "$@")"; rc=$?; printf "%%s\\n" "$out" | sed "\\$d"; exit $rc; fi\nexec "%s" "$@"\n' \
  "$BASH" "$NODE_REAL" "$NODE_REAL" > "$aux/corta/node"
# troca: no lugar do conferir, o stdout de $aux/troca.out (byte a byte) e o codigo de $aux/troca.rc
mkdir -p "$aux/troca"
printf '#!%s\nif [ "${2:-}" = conferir ]; then cat "%s"; exit "$(cat "%s")"; fi\nexec "%s" "$@"\n' \
  "$BASH" "$aux/troca.out" "$aux/troca.rc" "$NODE_REAL" > "$aux/troca/node"
chmod +x "$aux/espia/node" "$aux/corta/node" "$aux/troca/node"

# --- o projeto temporário --------------------------------------------------------------------
# projeto <nome> <modo|-> — repositório com o núcleo versionado e `.expx/fatiamento.json`
# (sem ele com `-`); ENTREGA.md e tasks.md ficam fora, em $aux. ITENS: `task:sha` na ordem do E1.
g() { git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
projeto() {
  P="$aux/$1"; ITENS=""
  mkdir -p "$P/$nucleo_rel" && cp -R "$aux/nucleo/." "$P/$nucleo_rel/"
  g init -q -b main && g config core.autocrlf false
  if [ "$2" != - ]; then
    printf '{"expx_fatiamento": 2, "revisao_por_task": {"modo": "%s"}}\n' "$2" > "$P/.expx/fatiamento.json"
  fi
  printf 'base\n' > "$P/base.txt"; g add -A; g commit -q -m base
}
escreve() { local f; for f in "$@"; do mkdir -p "$P/$(dirname "$f")"; printf 'const %s = 1;\n' "x$RANDOM" > "$P/$f"; done; }
# revisa <task> <a,b,...> [<resposta> [<stderr>]] — o `revisar` do núcleo, com a falsa no PATH
revisa() {
  [ -z "${3:-}" ] || instala_codeant_falsa "$aux/falsa" "$3" "${4:-}"
  (cd "$P" && PATH="$aux/falsa/bin:$PATH" node "$(nativo "$P/$nucleo_rel/expx-revisao.mjs")" revisar \
     --trabalho w --task "$1" --arquivos "$2" > "$aux/revisar.out" 2>&1)
  local rc=$?
  [ -z "${3:-}" ] || instala_codeant_falsa "$aux/falsa" "$aux/resp-ok.json"
  return "$rc"
}
evidencia() { printf '%s\n' "$P/docs/entregas/w/revisao/$1.json"; }
commita() { g add -A && g commit -q -m "feat: $1" && ITENS="$ITENS $1:$(g rev-parse --short HEAD)"; }
# entrega [<versionado>] [<linhas extras>] — $aux/ENTREGA.md com os ITENS e, dentro de um projeto,
# a mesma ENTREGA em docs/entregas/w/, commitada sozinha (a V12 lê a entrega do HEAD, como o E2).
# ENTREGA_SO_NO_DISCO=1 grava no projeto sem commitar.
entrega() {
  local par
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: w\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: %s\nbranch: feature/w\nbranch_base: main\n' "${1:-true}"
    if [ -z "$ITENS" ]; then printf 'commits: []\n'; else
      printf 'commits:\n'
      for par in $ITENS; do printf -- '  - task: %s\n    commit: %s\n' "${par%%:*}" "${par#*:}"; done
    fi
    printf 'portao: null\nfalhas_portao: []\ncausa: null\npr_url: null\npr_estado: null\n'
    [ -z "${2:-}" ] || printf '%s\n' "$2"
    printf -- '---\n\n# Entrega\n'
  } > "$aux/ENTREGA.md"
  if [ -n "${P:-}" ] && [ -d "$P/.git" ]; then
    mkdir -p "$P/docs/entregas/w" && cp "$aux/ENTREGA.md" "$P/docs/entregas/w/ENTREGA.md"
    [ "${ENTREGA_SO_NO_DISCO:-0}" = 1 ] && return 0
    g add docs/entregas/w/ENTREGA.md && { g diff --cached --quiet || g commit -q -m "docs: entrega"; }
  fi
}
# tarefas <id:status>... — $aux/tasks.md (kind: tasks, formato da sprintx)
tarefas() {
  local par
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: w\ntasks:\n'
    for par in "$@"; do printf -- '  - id: %s\n    titulo: Task\n    status: %s\n' "${par%%:*}" "${par##*:}"; done
    printf -- '---\n\n# Tasks\n'
  } > "$aux/tasks.md"
}
# roda [VAR=valor...] — a V12 no projeto atual; saída em $aux/out e $aux/err, código em $rc.
# A entrega é $ENTREGA_ARG (padrão: o caminho relativo commitado no projeto).
roda() {
  rm -f "$aux/node.log"
  (cd "$P" && env "$@" "$BASH" "$V12" --verificar --entrega "${ENTREGA_ARG:-docs/entregas/w/ENTREGA.md}" --trabalho w --raiz "$P" \
     -- "$aux/tasks.md" > "$aux/out" 2> "$aux/err"); rc=$?
}
primeira() { head -n 1 "$aux/out"; }
tem() { grep -qxF -- "$1" "$aux/out"; }
linhas() { wc -l < "$aux/out" | tr -d ' '; }
conferiu() { [ -f "$aux/node.log" ] && grep -q ' conferir ' "$aux/node.log"; }
chamou_node() { [ -s "$aux/node.log" ]; }
mostra() { printf '(rc %s) %s | err: %s' "$rc" "$(tr '\n' '|' < "$aux/out")" "$(tr '\n' '|' < "$aux/err" | cut -c1-300)"; }

echo '== V12: uso e casos sem revisao =='

# uso
(cd "$aux" && "$BASH" "$V12" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 64 ] && passa 'sem argumentos: 64' || quebra "sem argumentos: $(mostra)"
(cd "$aux" && "$BASH" "$V12" --verificar --entrega "$aux/ENTREGA.md" --trabalho w > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 64 ] && passa 'sem tasks.md: 64' || quebra "sem tasks.md: $(mostra)"

# fora de um repositório Git: `versionado: false` é n/a (DM-238), sem node; `versionado: true` é SEM_PROVA
fora="$aux/fora-do-git"; mkdir -p "$fora"; ITENS=""; tarefas T-01.01:concluida
for v in false true; do
  entrega "$v"; rm -f "$aux/node.log"
  (cd "$fora" && env GIT_CEILING_DIRECTORIES="$aux" PATH="$aux/sem-node" "$BASH" "$V12" --verificar \
     --entrega "$aux/ENTREGA.md" --trabalho w -- "$aux/tasks.md" > "$aux/out" 2> "$aux/err"); rc=$?
  if [ "$v" = false ]; then
    [ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=sem-versionador' && ! chamou_node \
      && passa 'fora de um repositorio Git com versionado: false: n/a sem node' \
      || quebra "fora do Git, versionado false: $(mostra)"
  else
    [ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=fora-de-um-repositorio-git' \
      && passa 'fora de um repositorio Git com versionado: true: SEM_PROVA' \
      || quebra "fora do Git, versionado true: $(mostra)"
  fi
done
# o Git falhou por outro motivo (aqui, GIT_DIR inválido): não é "sem repositório", mesmo com versionado: false
entrega false; rm -f "$aux/node.log"
(cd "$fora" && env GIT_CEILING_DIRECTORIES="$aux" GIT_DIR="$aux/nao-existe" PATH="$aux/sem-node" "$BASH" "$V12" --verificar \
   --entrega "$aux/ENTREGA.md" --trabalho w -- "$aux/tasks.md" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=git-falhou' \
  && passa 'GIT_DIR invalido com versionado: false: SEM_PROVA, nunca n/a' \
  || quebra "GIT_DIR invalido, versionado false: $(mostra)"

# sem .expx/fatiamento.json: n/a sem node
projeto sem-arquivo -; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda PATH="$aux/sem-node"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=sem-fatiamento-json' \
  && passa 'sem .expx/fatiamento.json: n/a sem node' || quebra "sem .expx/fatiamento.json: $(mostra)"
# GIT_DIR/GIT_WORK_TREE no ambiente vencem o `git -C`: apontando outro repositório, a V12
# leria outro HEAD (conselhos#210, P1). Divergente: SEM_PROVA. O mesmo repositório (o caso
# do pre-push, em que o Git exporta GIT_DIR): segue como sem o ambiente.
outro_git="$aux/outro-repo"; git init -q -b main "$outro_git"
git -C "$outro_git" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m outro
roda PATH="$aux/sem-node" GIT_DIR="$outro_git/.git"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=ambiente-git-divergente' \
  && passa 'GIT_DIR de outro repositorio: SEM_PROVA' || quebra "GIT_DIR de outro repositorio: $(mostra)"
roda PATH="$aux/sem-node" GIT_WORK_TREE="$outro_git"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=ambiente-git-divergente' \
  && passa 'GIT_WORK_TREE de outro repositorio: SEM_PROVA' || quebra "GIT_WORK_TREE de outro repositorio: $(mostra)"
roda PATH="$aux/sem-node" GIT_DIR="$P/.git"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=sem-fatiamento-json' \
  && passa 'GIT_DIR do proprio repositorio (pre-push): segue' || quebra "GIT_DIR do proprio repositorio: $(mostra)"
# Worktree irma (katosmv/login#34): o GIT_DIR dela tem o mesmo toplevel resolvido e o mesmo
# git-common-dir, mas outro HEAD. A identidade inclui o git-dir: divergente.
irma="$aux/irma-wt"; git -C "$P" worktree add -q --detach "$irma" HEAD
git -C "$irma" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m irma
roda PATH="$aux/sem-node" GIT_DIR="$(git -C "$irma" rev-parse --absolute-git-dir)"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=ambiente-git-divergente' \
  && passa 'GIT_DIR de worktree irma: SEM_PROVA' || quebra "GIT_DIR de worktree irma: $(mostra)"
git -C "$P" worktree remove --force "$irma"

# desligada: n/a sem conferir (o leitor roda, com node)
projeto desligada desligada; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda PATH="$aux/espia:$PATH"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=revisao-por-task-desligada' && chamou_node && ! conferiu \
  && passa 'desligada: n/a sem conferir' || quebra "desligada: $(mostra)"

# node ausente com .expx/fatiamento.json: SEM_PROVA em qualquer modo
for m in obrigatoria se_disponivel desligada; do
  projeto "sem-node-$m" "$m"; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
  roda PATH="$aux/sem-node"
  [ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && grep -q '^motivo=configuracao-nao-lida:3$' "$aux/out" \
    && grep -q 'node ausente' "$aux/err" && passa "node ausente ($m): SEM_PROVA" || quebra "node ausente ($m): $(mostra)"
done

# FATIA_X no ambiente: SEM_PROVA, com a mensagem da emenda, sem conferir
projeto fatia obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda FATIA_X=1 PATH="$aux/espia:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && ! conferiu \
  && grep -qF '`FATIA_X` não é mais lida (limites do CodeAnt, fixos: emenda de 2026-10-19); remova-a do ambiente' "$aux/err" \
  && passa 'FATIA_X no ambiente: SEM_PROVA' || quebra "FATIA_X no ambiente: $(mostra)"
# definida e vazia também, e mesmo sem .expx/fatiamento.json
projeto fatia-sem-arquivo -; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda FATIA_IGNORAR=
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] \
  && passa 'FATIA_IGNORAR vazia, sem .expx/fatiamento.json: SEM_PROVA' || quebra "FATIA_IGNORAR vazia: $(mostra)"

# núcleo antigo (sem expx-limites.mjs), versionado assim: SEM_PROVA
projeto antigo obrigatoria; g rm -q "$nucleo_rel/expx-limites.mjs"; g commit -q -m 'nucleo antigo'
escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda PATH="$aux/espia:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && ! conferiu && grep -q 'nucleo antigo' "$aux/err" \
  && passa 'nucleo sem expx-limites.mjs: SEM_PROVA' || quebra "nucleo sem expx-limites.mjs: $(mostra)"

# núcleo sem expx-revisao.mjs: AVISO em se_disponivel (código 0), SEM_PROVA em obrigatoria
for m in se_disponivel obrigatoria; do
  projeto "sem-revisao-$m" "$m"; g rm -q "$nucleo_rel/expx-revisao.mjs"; g commit -q -m 'sem revisao'
  escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  if [ "$m" = se_disponivel ]; then
    [ "$rc" = 0 ] && [ "$(primeira)" = 'V12=AVISO' ] && tem 'motivo=revisao-nao-conferida:nucleo-sem-expx-revisao' \
      && passa 'se_disponivel sem expx-revisao.mjs: AVISO revisao-nao-conferida, codigo 0' || quebra "se_disponivel sem expx-revisao.mjs: $(mostra)"
  else
    [ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=nucleo-sem-expx-revisao' \
      && passa 'obrigatoria sem expx-revisao.mjs: SEM_PROVA' || quebra "obrigatoria sem expx-revisao.mjs: $(mostra)"
  fi
done

# entrega de planejamento: n/a sem chamar o conferir
PLAN='sprint_atual: planejamento
prs:
  - sprint: planejamento
    url: null
    estado: null
    merge_sha: null
    merge: null'
projeto planejamento obrigatoria; escreve src/a.ts; commita T-01.01; entrega true "$PLAN"; tarefas T-01.01:concluida
roda PATH="$aux/espia:$PATH"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=planejamento: nenhuma task executada' && ! chamou_node \
  && passa 'entrega de planejamento: n/a sem chamar o conferir' || quebra "entrega de planejamento: $(mostra)"
# incoerente: sprint_atual sem prs
entrega true 'sprint_atual: planejamento'
roda PATH="$aux/espia:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && grep -q '^motivo=entrega-de-planejamento' "$aux/out" && ! conferiu \
  && passa 'entrega incoerente: SEM_PROVA' || quebra "entrega incoerente: $(mostra)"

# versionado: false e nenhuma task concluída: n/a sem conferir
projeto n-a obrigatoria; escreve src/a.ts; commita T-01.01; entrega false; tarefas T-01.01:concluida
roda PATH="$aux/espia:$PATH"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=sem-versionador' && ! conferiu \
  && passa 'versionado false: n/a' || quebra "versionado false: $(mostra)"
entrega; tarefas T-01.01:em_andamento
roda PATH="$aux/espia:$PATH"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=nenhuma-task-concluida' && ! conferiu \
  && passa 'nenhuma task concluida: n/a' || quebra "nenhuma task concluida: $(mostra)"

echo '== V12: a entrega e a do HEAD, como no E2 (correcao P1 do Login) =='

# disco diverge do HEAD: a marca de planejamento só no disco não muda o portão
# o HEAD anda depois de fixado o snapshot da entrega: o modo sai do MESMO snapshot, não do HEAD
# novo. O git do PATH, logo depois do `show` da entrega, commita `modo: desligada` no projeto.
# Do snapshot sai obrigatoria e versionado false (n/a sem-versionador); do HEAD novo sairia o
# n/a da revisão desligada.
mkdir -p "$aux/avanca"; git_real="$(command -v git)"
cat > "$aux/avanca/git" <<AVANCA
#!$BASH
"$git_real" "\$@"; rc=\$?
case " \$* " in
  *" show "*":docs/entregas/w/ENTREGA.md "*)
    if [ ! -e "$aux/avanca.marco" ]; then
      : > "$aux/avanca.marco"
      printf '{"expx_fatiamento": 2, "revisao_por_task": {"modo": "desligada"}}\n' > "\$AVANCA_P/.expx/fatiamento.json"
      "$git_real" -C "\$AVANCA_P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false \\
        commit -q -am 'o HEAD anda no meio da V12' >/dev/null 2>&1
    fi ;;
esac
exit \$rc
AVANCA
chmod +x "$aux/avanca/git"
projeto avanca obrigatoria; escreve src/a.ts; commita T-01.01; entrega false; tarefas T-01.01:concluida
rm -f "$aux/avanca.marco"
roda AVANCA_P="$P" PATH="$aux/avanca:$PATH"
[ -e "$aux/avanca.marco" ] && [ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=sem-versionador' \
  && passa 'HEAD que anda no meio da V12: o modo sai do snapshot da entrega' || quebra "HEAD que anda no meio: $(mostra)"

projeto disco obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
ENTREGA_SO_NO_DISCO=1 entrega true "$PLAN"
roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-ausente' \
  && passa 'planejamento so no disco: a V12 le o HEAD e confere a task' || quebra "planejamento so no disco: $(mostra)"
# caminho absoluto dentro da raiz: o mesmo arquivo
projeto absoluto obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
ENTREGA_ARG="$P/docs/entregas/w/ENTREGA.md" roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-ausente' \
  && passa 'entrega por caminho absoluto dentro da raiz: conferida' || quebra "absoluto dentro: $(mostra)"
# caminho fora da raiz: não está em commit nenhum do projeto
ENTREGA_ARG="$aux/ENTREGA.md" roda
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=entrega-de-planejamento-ilegivel' \
  && passa 'entrega fora da raiz: SEM_PROVA' || quebra "entrega fora da raiz: $(mostra)"
# entrega só no disco, nunca commitada: SEM_PROVA
projeto sem-commit obrigatoria; escreve src/a.ts; commita T-01.01; ENTREGA_SO_NO_DISCO=1 entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=entrega-de-planejamento-ilegivel' \
  && passa 'entrega fora do HEAD: SEM_PROVA' || quebra "entrega fora do HEAD: $(mostra)"

echo '== V12: o conferir do nucleo =='

# sem evidência: FALHA em obrigatoria, AVISO (código 0) em se_disponivel
projeto sem-ev obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 1 ] && [ "$(primeira)" = 'V12=FALHA' ] && tem 'T-01.01 FALHA evidencia-ausente' && [ "$(linhas)" = 2 ] \
  && passa 'obrigatoria sem evidencia: FALHA evidencia-ausente' || quebra "obrigatoria sem evidencia: $(mostra)"
projeto sem-ev-sd se_disponivel; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=AVISO' ] && tem 'T-01.01 AVISO evidencia-ausente' \
  && passa 'se_disponivel sem evidencia: AVISO, codigo 0' || quebra "se_disponivel sem evidencia: $(mostra)"

# id com ponto e legado: os dois conferidos de verdade (o conferir respondeu pelos dois)
projeto ponto obrigatoria; escreve src/a.ts; commita T-01.03; escreve src/b.ts; commita T-7; entrega
tarefas T-01.03:concluida T-7:concluida
roda
[ "$rc" = 1 ] && tem 'T-01.03 FALHA evidencia-ausente' && tem 'T-7 FALHA evidencia-ausente' && [ "$(linhas)" = 3 ] \
  && passa 'id com ponto (T-01.03) e legado (T-7) conferidos' || quebra "id com ponto: $(mostra)"

# task concluída sem item em commits não é alvo (é da V11)
projeto sem-item obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida T-01.02:concluida
roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-ausente' && ! grep -q '^T-01.02' "$aux/out" && [ "$(linhas)" = 2 ] \
  && passa 'task sem item em commits nao e alvo' || quebra "task sem item em commits: $(mostra)"
tarefas T-01.02:concluida
roda PATH="$aux/espia:$PATH"
[ "$rc" = 0 ] && [ "$(primeira)" = 'V12=n/a' ] && tem 'motivo=nenhuma-task-com-commit' && ! conferiu \
  && passa 'so tasks sem item em commits: n/a' || quebra "so tasks sem item: $(mostra)"

# conferir que sai 64 (id fora da forma, que o núcleo recusa): SEM_PROVA em qualquer modo
for m in obrigatoria se_disponivel; do
  projeto "c64-$m" "$m"; escreve src/a.ts; commita T-1.3; entrega; tarefas T-1.3:concluida
  roda
  [ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=conferir-saiu-64' \
    && passa "conferir 64 ($m): SEM_PROVA" || quebra "conferir 64 ($m): $(mostra)"
done

# conferir que sai com uma linha a menos: SEM_PROVA
projeto curta obrigatoria; escreve src/a.ts; commita T-01.01; escreve src/b.ts; commita T-01.02; entrega
tarefas T-01.01:concluida T-01.02:concluida
roda PATH="$aux/corta:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=conferir-saida-fora-da-forma' \
  && passa 'conferir com uma linha a menos: SEM_PROVA' || quebra "conferir com uma linha a menos: $(mostra)"

# linha a mais sem fim de linha, e motivo em branco: SEM_PROVA
projeto troca obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
printf 'T-01.01 FALHA evidencia-ausente\nlixo' > "$aux/troca.out"; echo 1 > "$aux/troca.rc"
roda PATH="$aux/troca:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=conferir-saida-fora-da-forma' \
  && passa 'conferir com uma linha a mais sem fim de linha: SEM_PROVA' || quebra "linha a mais sem fim de linha: $(mostra)"
printf 'T-01.01 AVISO  \n' > "$aux/troca.out"; echo 3 > "$aux/troca.rc"
roda PATH="$aux/troca:$PATH"
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=conferir-saida-fora-da-forma' \
  && passa 'conferir com motivo em branco: SEM_PROVA' || quebra "motivo em branco: $(mostra)"

# --raiz relativa ao diretorio de quem chama
projeto relativa obrigatoria; escreve src/a.ts; commita T-01.01; entrega; tarefas T-01.01:concluida
(cd "$aux" && "$BASH" "$V12" --verificar --entrega relativa/docs/entregas/w/ENTREGA.md --trabalho w --raiz relativa \
   -- "$aux/tasks.md" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-ausente' \
  && passa '--raiz relativa: conferida' || quebra "--raiz relativa: $(mostra)"

# 41 arquivos revisáveis: incompleta:L1:41 (antes da CLI), FALHA em se_disponivel também
projeto l1 se_disponivel
lista=""; for i in $(seq 1 41); do escreve "src/f$i.ts"; lista="$lista${lista:+,}src/f$i.ts"; done
revisa T-01.01 "$lista"; rr=$?
commita T-01.01; entrega; tarefas T-01.01:concluida
roda
[ "$rr" = 3 ] && [ "$rc" = 1 ] && [ "$(primeira)" = 'V12=FALHA' ] && tem 'T-01.01 FALHA incompleta:L1:41' \
  && passa 'task com 41 arquivos revisaveis: incompleta:L1:41, V12=FALHA em se_disponivel tambem' \
  || quebra "41 revisaveis (revisar $rr): $(mostra)"

# a evidência editada no disco depois do commit não muda o veredito
jq '.resultado = "ok" | del(.motivo)' "$(evidencia T-01.01)" > "$aux/ed.json" && cp "$aux/ed.json" "$(evidencia T-01.01)"
roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA incompleta:L1:41' \
  && passa 'evidencia editada no disco depois do commit nao muda o veredito' || quebra "evidencia editada no disco: $(mostra)"

# task com dois itens em commits: confere o commit do último
projeto dois obrigatoria; escreve src/a.ts; commita T-01.01
lista=""; for i in $(seq 1 41); do escreve "src/f$i.ts"; lista="$lista${lista:+,}src/f$i.ts"; done
revisa T-01.01 "$lista"; commita T-01.01; entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA incompleta:L1:41' && [ "$(linhas)" = 2 ] \
  && passa 'task com dois itens em commits: confere o ultimo' || quebra "dois itens: $(mostra)"

# ultimo item da task com commit invalido: SEM_PROVA, nunca o commit de um item anterior
projeto ultimo-invalido obrigatoria; escreve src/a.ts; commita T-01.01; ITENS="$ITENS T-01.01:null"
entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 2 ] && [ "$(primeira)" = 'V12=SEM_PROVA' ] && tem 'motivo=commit-invalido:T-01.01' \
  && passa 'ultimo item da task com commit invalido: SEM_PROVA' || quebra "ultimo item com commit invalido: $(mostra)"

# evidência de versão antiga (expx_revisao 1) no commit: FALHA evidencia-invalida:versao
projeto v1 obrigatoria
lista=""; for i in $(seq 1 41); do escreve "src/f$i.ts"; lista="$lista${lista:+,}src/f$i.ts"; done
revisa T-01.01 "$lista"
jq '.expx_revisao = 1' "$(evidencia T-01.01)" > "$aux/ed.json" && cp "$aux/ed.json" "$(evidencia T-01.01)"
commita T-01.01; entrega; tarefas T-01.01:concluida
roda
[ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-invalida:versao' \
  && passa 'evidencia de versao antiga (expx_revisao 1) no commit: FALHA evidencia-invalida:versao' || quebra "versao antiga: $(mostra)"

echo '== V12: evidencias gravadas pela CLI falsa =='

if [ "$FALSA" = 0 ]; then
  for c in 'obrigatoria com evidencia ok: OK' 'achado aberto: FALHA achados-abertos:1' \
           'CLI falsa com "[error] Failed to review" no stderr: FALHA incompleta:lote-falhou' \
           'evidencia v2 sem chamada.issues: FALHA evidencia-invalida:chamada' \
           'issues com achado trocado: FALHA evidencia-invalida:achados' \
           'task com dois itens em commits: o ultimo, com a evidencia ok do primeiro'; do
    so_linux "$c"
  done
else
  # ok
  projeto ok obrigatoria; escreve src/a.ts src/b.ts; revisa T-01.01 src/a.ts,src/b.ts; rr=$?
  commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  [ "$rr" = 0 ] && [ "$rc" = 0 ] && [ "$(primeira)" = 'V12=OK' ] && tem 'T-01.01 ok' && [ "$(linhas)" = 2 ] \
    && passa 'obrigatoria com evidencia ok: OK' || quebra "evidencia ok (revisar $rr: $(cat "$aux/revisar.out")): $(mostra)"

  # dois itens: o primeiro com a evidência ok; o segundo muda o arquivo sem revisar de novo
  escreve src/a.ts; commita T-01.01; entrega
  roda
  [ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-nao-bate:src/a.ts' \
    && passa 'task com dois itens em commits: o ultimo, com a evidencia ok do primeiro' || quebra "dois itens, ok no primeiro: $(mostra)"

  # achado aberto
  projeto achado obrigatoria; escreve src/a.ts; revisa T-01.01 src/a.ts "$aux/resp-achado.json"; rr=$?
  commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  [ "$rr" = 1 ] && [ "$rc" = 1 ] && tem 'T-01.01 FALHA achados-abertos:1' \
    && passa 'achado aberto: FALHA achados-abertos:1' || quebra "achado aberto (revisar $rr): $(mostra)"

  # falha de lote no stderr
  projeto lote se_disponivel; escreve src/a.ts
  revisa T-01.01 src/a.ts "$aux/resp-ok.json" '[error] Failed to review src/a.ts: 500'; rr=$?
  commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  [ "$rr" = 3 ] && [ "$rc" = 1 ] && tem 'T-01.01 FALHA incompleta:lote-falhou' \
    && passa 'CLI falsa com "[error] Failed to review" no stderr: FALHA incompleta:lote-falhou' || quebra "lote-falhou (revisar $rr): $(mostra)"

  # v2 gravada antes da #69 (sem chamada.issues)
  projeto sem-issues obrigatoria; escreve src/a.ts; revisa T-01.01 src/a.ts
  jq 'del(.chamada.issues)' "$(evidencia T-01.01)" > "$aux/ed.json" && cp "$aux/ed.json" "$(evidencia T-01.01)"
  commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  [ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-invalida:chamada' \
    && passa 'evidencia v2 sem chamada.issues: FALHA evidencia-invalida:chamada' || quebra "sem chamada.issues: $(mostra)"

  # uma issue trocada: os achados gravados não são mais os derivados
  projeto trocada obrigatoria; escreve src/a.ts; revisa T-01.01 src/a.ts "$aux/resp-achado.json"
  jq '.chamada.issues[0].label = "estilo"' "$(evidencia T-01.01)" > "$aux/ed.json" && cp "$aux/ed.json" "$(evidencia T-01.01)"
  commita T-01.01; entrega; tarefas T-01.01:concluida
  roda
  [ "$rc" = 1 ] && tem 'T-01.01 FALHA evidencia-invalida:achados' \
    && passa 'issues com achado trocado: FALHA evidencia-invalida:achados' || quebra "issue trocada: $(mostra)"
fi

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" = 0 ]
