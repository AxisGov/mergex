#!/usr/bin/env bash
#
# Bancada da revisão retroativa (DM-346) — revisao-retroativa.sh e a regra da V12.
#
# A task fechada no E1 sem revisão aprovada (último item com `revisao: null` ou `invalida`)
# ganha a revisão depois: o `revisar --retroativa` do núcleo grava a evidência com
# `commits_da_task`, o script prova, faz UM commit só de evidências e registra um item por task.
#
# As recusas usam evidência escrita no teste e não dependem do núcleo novo. Os casos de
# elegibilidade, `--aplicar` e V12 dependem do núcleo com `revisar --retroativa` (vendor em
# scripts/ci/fixtures/candidatos/expx-nucleo) e da CLI falsa (só Linux); sem um dos dois, saem
# `ok` com a nota.
#
# Uso: bash scripts/ci/test-revisao-retroativa.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$REPO/.claude/skills/mergex/scripts"
RETRO="${RETRO:-$S/revisao-retroativa.sh}"
V12="${V12:-$S/portao-v12.sh}"
SEQ="$S/sequencia-de-commits.sh"
copia="$REPO/scripts/ci/fixtures/candidatos/expx-nucleo"
nucleo_rel='.expx/marketplace/plugins/expx/nucleo/scripts'
# shellcheck source=codeant-falsa.sh
. "$REPO/scripts/ci/codeant-falsa.sh"
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done

OK=0; FALHOU=0
passa()  { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
P=""

command -v node >/dev/null 2>&1 || { echo 'test-revisao-retroativa: node ausente' >&2; exit 1; }
FALSA=0; codeant_falsa_suportada && FALSA=1
# a cópia do núcleo é plana (atualizar-nucleo-expx.sh); sem o `revisar --retroativa` nela, a bancada
# não prova nada do caminho feliz: falha, nunca pula
NOVO=0; grep -q -- '--retroativa' "$copia/expx-revisao.mjs" 2>/dev/null && NOVO=1
[ "$NOVO" = 1 ] || { echo 'test-revisao-retroativa: a copia do nucleo nao tem revisar --retroativa' >&2; exit 1; }
pula() { passa "$1 (depende do nucleo novo com revisar --retroativa e da CLI falsa: o CI em Linux cobre)"; }
nativo() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

monta_nucleo() {
  local f
  while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")" && tr -d '\r' < "$copia/$f" > "$1/$f"
  done < <(cd "$copia" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
}
printf '{"issues":[],"meta":{"reviewed_files":"__include__","total_changed":0,"skipped":[],"capped":false,"max_files":40},"error":null,"noFiles":false}\n' \
  > "$aux/resp-ok.json"
monta_nucleo "$aux/nucleo"
if [ "$FALSA" = 1 ]; then
  instala_codeant_falsa "$aux/falsa" "$aux/resp-ok.json" && nucleo_com_falsa "$aux/nucleo" "$aux/falsa" \
    || { echo 'test-revisao-retroativa: nao montou a CLI falsa' >&2; exit 1; }
fi

# --- o projeto temporário: ITENS é `task:commit:revisao` na ordem do E1 ---------------------
g() { git -C "$P" -c commit.gpgsign=false "$@"; }
projeto() {
  P="$aux/$1"; ITENS=""
  mkdir -p "$P/$nucleo_rel" && cp -R "$aux/nucleo/." "$P/$nucleo_rel/"
  g init -q -b main && g config core.autocrlf false && g config user.email t@t && g config user.name t
  printf '{"expx_fatiamento": 2, "revisao_por_task": {"modo": "obrigatoria"}}\n' > "$P/.expx/fatiamento.json"
  printf 'base\n' > "$P/base.txt"; g add -A; g commit -q -m base
  g checkout -q -b feature/w
}
escreve() { local f; for f in "$@"; do mkdir -p "$P/$(dirname "$f")"; printf 'const %s = 1;\n' "x$RANDOM" > "$P/$f"; done; }
commita() { g add -A && g commit -q -m "feat: $1" && C="$(g rev-parse --short HEAD)"; }
item() { ITENS="$ITENS $1:$2:$3"; }
entrega_arq() { printf '%s\n' "$P/docs/entregas/w/ENTREGA.md"; }
evidencia() { printf '%s\n' "$P/docs/entregas/w/revisao/$1.json"; }
entrega() {
  local tri t c r
  mkdir -p "$P/docs/entregas/w"
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: w\n'
    printf 'entregue_por: mergex\nestado: aberto\nversionado: true\nbranch: feature/w\nbranch_base: main\n'
    printf 'commits:\n'
    for tri in $ITENS; do
      t="${tri%%:*}"; r="${tri##*:}"; c="${tri#*:}"; c="${c%:*}"
      printf -- '  - task: %s\n    commit: %s\n    revisao: %s\n' "$t" "$c" "$r"
    done
    printf 'portao: null\nfalhas_portao: []\ncausa: null\npr_url: null\npr_estado: null\n---\n\n# Entrega\n'
  } > "$(entrega_arq)"
  g add docs/entregas/w/ENTREGA.md && g commit -q -m 'docs: entrega'
}
# evidencia_escrita <task> <commits,...> [<modo>] — a evidência no disco, sem o núcleo
evidencia_escrita() {
  local js
  mkdir -p "$P/docs/entregas/w/revisao"
  js="$(printf '%s' "$2" | awk -F, '{ for (i = 1; i <= NF; i++) printf "%s\"%s\"", (i > 1 ? "," : ""), $i }')"
  printf '{"expx_revisao":2,"modo":"%s","commits_da_task":[%s]}\n' "${3:-retroativa}" "$js" > "$(evidencia "$1")"
}
tarefas() {
  local par
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: w\ntasks:\n'
    for par in "$@"; do printf -- '  - id: %s\n    titulo: Task\n    status: concluida\n' "$par"; done
    printf -- '---\n\n# Tasks\n'
  } > "$aux/tasks.md"
}
# roda <modo> <task>... — o script no projeto; saída em $aux/out e $aux/err, código em $rc
roda() {
  local m="$1"; shift
  (cd "$P" && bash "$RETRO" "--$m" --entrega docs/entregas/w/ENTREGA.md --trabalho w -- "$@" \
     > "$aux/out" 2> "$aux/err"); rc=$?
}
roda_v12() {
  (cd "$P" && bash "$V12" --verificar --entrega docs/entregas/w/ENTREGA.md --trabalho w --raiz "$P" \
     -- "$aux/tasks.md" > "$aux/out" 2> "$aux/err"); rc=$?
}
revisa_retro() { # <task> <commits>
  (cd "$P" && PATH="$aux/falsa/bin:$PATH" node "$(nativo "$P/$nucleo_rel/expx-revisao.mjs")" revisar \
     --trabalho w --task "$1" --retroativa --commits "$2" > "$aux/revisar.out" 2>&1)
}
mostra() { printf '(rc %s) %s | err: %s' "$rc" "$(tr '\n' '|' < "$aux/out")" "$(tr '\n' '|' < "$aux/err" | cut -c1-300)"; }

echo '== revisao retroativa: uso e --listar =='

projeto uso; escreve src/a.ts; commita T-01.01; item T-01.01 "$C" null; entrega
(cd "$P" && bash "$RETRO" --verificar --entrega docs/entregas/outro/ENTREGA.md --trabalho w -- T-01.01 > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 64 ] && passa 'entrega fora do caminho canonico: 64' || quebra "entrega fora do canonico: $(mostra)"
roda listar T-01.01 T-01.02
[ "$rc" = 64 ] && passa '--listar com duas tasks: 64' || quebra "--listar com duas tasks: $(mostra)"

projeto listar; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" invalida
escreve src/b.ts; commita T-01.01; c2="$(g rev-parse HEAD)"; item T-01.01 "$C" null
escreve src/c.ts; commita T-01.02; item T-01.02 "$C" ok; entrega
roda listar T-01.01
[ "$rc" = 0 ] && [ "$(cat "$aux/out")" = "$c1,$c2" ] \
  && passa '--listar: os commits registrados da task, SHA completo, por virgula' || quebra "--listar: $(mostra)"

echo '== revisao retroativa: recusas (evidencia escrita no teste) =='

# último item com revisao ok: não é elegível
projeto rec-ok; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" ok; entrega
evidencia_escrita T-01.01 "$c1"
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'revisao ok, nao null nem invalida' "$aux/err" \
  && passa 'ultimo item com revisao ok: recusa' || quebra "ultimo item ok: $(mostra)"

# commits_da_task divergente dos registrados
projeto rec-div; escreve src/a.ts; commita T-01.01; item T-01.01 "$C" null; entrega
evidencia_escrita T-01.01 "$(g rev-parse HEAD~2)"
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'commits_da_task diverge' "$aux/err" \
  && passa 'commits_da_task divergente: recusa' || quebra "commits_da_task divergente: $(mostra)"

# evidência sem modo retroativa
projeto rec-modo; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" null; entrega
evidencia_escrita T-01.01 "$c1" normal
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'sem modo retroativa' "$aux/err" \
  && passa 'evidencia sem modo retroativa: recusa' || quebra "evidencia sem modo: $(mostra)"

# produto sujo além das evidências
projeto rec-sujo; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" invalida; entrega
evidencia_escrita T-01.01 "$c1"; escreve src/x.ts
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'arvore suja fora das evidencias' "$aux/err" \
  && passa 'produto sujo alem das evidencias: recusa' || quebra "produto sujo: $(mostra)"
roda aplicar T-01.01
[ "$rc" = 3 ] && [ "$(g log -1 --format=%s)" = 'docs: entrega' ] && [ -z "$(g diff --cached --name-only)" ] \
  && passa 'produto sujo: --aplicar recusa sem commit' || quebra "produto sujo no aplicar: $(mostra)"

# sequência de commits inválida em outra task: recusa antes do commit (o --acrescentar a barraria depois)
projeto rec-seq; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"
item T-01.01 "$C" null; item T-01.02 "$C" null; entrega
awk '$0 == "  - task: T-01.02" { print "  - seq: 1"; print "    task: T-01.02"; next } { print }' \
  "$(entrega_arq)" > "$aux/entrega.seq" && cat "$aux/entrega.seq" > "$(entrega_arq)"
g add docs/entregas/w/ENTREGA.md && g commit -q -m 'docs: entrega com seq fora da sequencia'
evidencia_escrita T-01.01 "$c1"
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'sequencia de commits invalida' "$aux/err" \
  && passa 'sequencia de commits invalida: recusa antes do commit' || quebra "sequencia invalida: $(mostra)"

# ENTREGA.md sem permissão de escrita: recusa antes do commit
projeto rec-ro; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" null; entrega
evidencia_escrita T-01.01 "$c1"; chmod a-w "$(entrega_arq)"
if [ -w "$(entrega_arq)" ]; then
  passa 'ENTREGA.md somente leitura: recusa (usuario ignora a permissao aqui; o CI em Linux cobre)'
else
  roda verificar T-01.01
  [ "$rc" = 3 ] && grep -q 'ENTREGA.md sem permissao de escrita' "$aux/err" \
    && passa 'ENTREGA.md somente leitura: recusa' || quebra "ENTREGA somente leitura: $(mostra)"
fi
chmod u+w "$(entrega_arq)"

# ENTREGA do disco diverge do HEAD
projeto rec-disco; escreve src/a.ts; commita T-01.01; c1="$(g rev-parse HEAD)"; item T-01.01 "$C" null; entrega
evidencia_escrita T-01.01 "$c1"; printf '\nnota\n' >> "$(entrega_arq)"
roda verificar T-01.01
[ "$rc" = 3 ] && grep -q 'ENTREGA.md do disco diverge de HEAD' "$aux/err" \
  && passa 'ENTREGA do disco diverge do HEAD: recusa' || quebra "ENTREGA divergente: $(mostra)"

echo '== revisao retroativa: nucleo novo e CLI falsa =='

if [ "$FALSA" = 0 ] || [ "$NOVO" = 0 ]; then
  for c in 'ultimo item null: elegivel' 'ultimo item invalida, commit compartilhado por duas tasks: elegivel' \
           '--aplicar: um commit so de evidencias, trailers e itens com revisao ok' \
           'V12 depois do --aplicar: OK' 'V12 com evidencia adulterada: FALHA retroativa-divergente' \
           'evidencia reescrita depois da prova: --aplicar recusa sem commit'; do
    pula "$c"
  done
else
  # null elegível
  projeto null; escreve src/a.ts src/b.ts; commita T-01.01; item T-01.01 "$C" null; entrega
  roda listar T-01.01; lista="$(cat "$aux/out")"
  revisa_retro T-01.01 "$lista"; rr=$?
  roda verificar T-01.01
  [ "$rc" = 0 ] && grep -qx 'ok=true' "$aux/out" \
    && passa 'ultimo item null: elegivel' || quebra "null elegivel (revisar $rr: $(cat "$aux/revisar.out")): $(mostra)"

  # --aplicar
  antes="$(g rev-list --count HEAD)"
  roda aplicar T-01.01
  novo="$(g rev-parse HEAD)"
  trailers="$(g show -s --format=%B HEAD | git interpret-trailers --parse)"
  arquivos="$(g show --name-only --format= HEAD)"
  ultimo="$(bash "$SEQ" --revisoes "$(entrega_arq)" | tail -n 1)"
  [ "$rc" = 0 ] && [ "$(tail -n 1 "$aux/out")" = 'proxima=E2' ] && [ "$(g rev-list --count HEAD)" = "$((antes + 1))" ] \
    && grep -qx 'Trabalho: w' <<<"$trailers" && grep -qx 'Revisao-retroativa: T-01.01' <<<"$trailers" \
    && [ "$arquivos" = 'docs/entregas/w/revisao/T-01.01.json' ] \
    && [ "$ultimo" = "$(printf '2\tT-01.01\tok')" ] \
    && grep -q "^- .*commit $novo revisou depois do fechamento" "$(entrega_arq)" \
    && grep -q "$novo" <<<"$(bash "$SEQ" --ler "$(entrega_arq)")" \
    && passa '--aplicar: um commit so de evidencias, trailers e itens com revisao ok' || quebra "--aplicar: $(mostra)"

  # V12 depois (o pre-e2 persiste a ENTREGA)
  g add docs/entregas/w/ENTREGA.md && g commit -q -m 'chore(mergex): persiste metodo pre-e2'
  tarefas T-01.01; roda_v12
  [ "$rc" = 0 ] && [ "$(head -n 1 "$aux/out")" = 'V12=OK' ] && grep -qx 'T-01.01 ok' "$aux/out" \
    && passa 'V12 depois do --aplicar: OK' || quebra "V12 depois do aplicar: $(mostra)"

  # evidência adulterada num segundo commit retroativo: FALHA retroativa-divergente
  evidencia_escrita T-01.01 "$(g rev-parse main)"
  g add -A && g commit -q -m 'chore(mergex): revisao retroativa de T-01.01' -m 'Trabalho: w
Revisao-retroativa: T-01.01'
  bash "$SEQ" --acrescentar "$(entrega_arq)" T-01.01 "$(g rev-parse HEAD)" ok >/dev/null
  g add docs/entregas/w/ENTREGA.md && g commit -q -m 'chore(mergex): persiste metodo pre-e2'
  roda_v12
  [ "$rc" = 1 ] && [ "$(head -n 1 "$aux/out")" = 'V12=FALHA' ] && grep -qx 'T-01.01 FALHA retroativa-divergente' "$aux/out" \
    && passa 'V12 com evidencia adulterada: FALHA retroativa-divergente' || quebra "V12 adulterada: $(mostra)"

  # invalida elegível, commit compartilhado por duas tasks
  projeto invalida; escreve src/a.ts src/b.ts; commita T-01.01
  item T-01.01 "$C" invalida; item T-01.02 "$C" invalida; entrega
  for t in T-01.01 T-01.02; do roda listar "$t"; revisa_retro "$t" "$(cat "$aux/out")"; done
  roda verificar T-01.01 T-01.02
  [ "$rc" = 0 ] && grep -qx 'ok=true' "$aux/out" \
    && passa 'ultimo item invalida, commit compartilhado por duas tasks: elegivel' \
    || quebra "invalida elegivel ($(cat "$aux/revisar.out")): $(mostra)"

  # evidência reescrita entre a prova e o git add: --aplicar recusa, sem commit e com o stage vazio
  projeto corrida; escreve src/a.ts; commita T-01.01; item T-01.01 "$C" null; entrega
  roda listar T-01.01; revisa_retro T-01.01 "$(cat "$aux/out")"
  corrida="$(mktemp -d)"; real_node="$(command -v node)"
  cat > "$corrida/node" <<EOS
#!/usr/bin/env bash
"$real_node" "\$@"; r=\$?
case " \$* " in *" conferir "*) printf ' ' >> "$(evidencia T-01.01)" ;; esac
exit \$r
EOS
  chmod +x "$corrida/node"
  antes="$(g rev-parse HEAD)"
  (cd "$P" && PATH="$corrida:$PATH" bash "$RETRO" --aplicar --entrega docs/entregas/w/ENTREGA.md --trabalho w \
     -- T-01.01 > "$aux/out" 2> "$aux/err"); rc=$?
  [ "$rc" = 3 ] && grep -q 'evidencia mudou depois da prova' "$aux/err" && [ "$(g rev-parse HEAD)" = "$antes" ] \
    && [ -z "$(g diff --cached --name-only)" ] \
    && passa 'evidencia reescrita depois da prova: --aplicar recusa sem commit' || quebra "corrida no aplicar: $(mostra)"
  rm -rf "$corrida"
fi

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" = 0 ]
