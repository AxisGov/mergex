#!/usr/bin/env bash
# shellcheck shell=bash
#
# Parte da bancada R1: scripts/ci/test-r1-reconciliacao-base.sh a carrega com
# `.`, na ordem de definição, e roda os grupos. Esta parte só define funções e
# variáveis, e não roda sozinha. Grupos: v9, v9_robusto, barreira, raso e portao.

[ "${BASH_SOURCE[0]}" != "$0" ] || { echo "${0##*/}: parte da bancada R1; rode scripts/ci/test-r1-reconciliacao-base.sh" >&2; exit 64; }

# ---------------------------------------------------------------------------
# V9 executável (Task 11): portao-v9.sh e a barreira do checkpoint
# ---------------------------------------------------------------------------

# v9_espera <desc> <rc> <saída exata> — portao-v9.sh (array `v` do grupo) com
# o rc e a saída exatos e o stderr vazio.
v9_espera() {
  local desc="$1" esperado="$2" saida="$3" out rc err
  err="$(mktemp)"; TMPS+=("$err")
  out="$("${v[@]}" 2>"$err")"; rc=$?
  if [ "$rc" = "$esperado" ] && [ "$out" = "$saida" ] && [ ! -s "$err" ]; then ok "$desc"
  else falha "$desc — rc=$rc (esperava $esperado) out=$(printf '%s' "$out" | tr '\n\t' '|>') err=$(tr '\n' ' ' < "$err")"; fi
}

# v9_sem_prova <desc> <trecho> — rc 3, `resultado=v9_sem_prova`, uma linha
# `motivo` com o trecho e nenhuma linha `fora_do_plano` nem `base=`.
v9_sem_prova() {
  local desc="$1" trecho="$2" out rc
  out="$("${v[@]}" 2>/dev/null)"; rc=$?
  if [ "$rc" != 3 ]; then falha "$desc — rc=$rc, esperava 3: $(printf '%s' "$out" | tr '\n\t' '|>')"; return; fi
  if ! printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
      || printf '%s\n' "$out" | grep -Eq '^(fora_do_plano|base=|resultado=(ok|v9)$)'; then
    falha "$desc — saída fora do contrato: $(printf '%s' "$out" | tr '\n\t' '|>')"; return
  fi
  if printf '%s\n' "$out" | TRECHO="$trecho" awk '/^motivo\t/ && index($0, ENVIRON["TRECHO"]) { f = 1 } END { exit !f }'; then ok "$desc"
  else falha "$desc — sem motivo com '$trecho': $(printf '%s' "$out" | tr '\n\t' '|>')"; fi
}

# _v9_commit <mensagem> <arquivo>... — commita só os arquivos dados
_v9_commit() {
  local m="$1"; shift
  git add -- "$@" && git commit -q -m "$m" -- "$@"
}

grupo_v9() {
  local d v t out tk lt e x
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")

  # ---- o fluxo do plano: antes e depois do registro, ref parada, produto ----
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  v=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  rc_igual "antes do registro: V9 reprova os dois" 1 "${v[@]}"
  [ "$("${v[@]}" | grep -c '^fora_do_plano	')" = 2 ] && ok "nomeia os dois" || falha "lista de desvios"
  v9_espera "antes do registro: base_validada_sha de HEAD, saída exata" 1 \
    "$(printf 'base=%s\norigem_base=registrada_e0\nresultado=v9\nfora_do_plano\t%s\nfora_do_plano\t%s' "$FX_B0" "$FX_NOVO2" "$FX_NOVO1")"
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  rc_igual "depois do registro: V9 aprova" 0 "${v[@]}"
  v9_espera "depois do registro: base é o b1_sha da reconciliação (sem commit dos artefatos)" 0 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  git branch -f main "$FX_B0"
  rc_igual "ref local desatualizada não muda o resultado" 0 "${v[@]}"
  v9_espera "ref local desatualizada: mesma base" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  git branch -f main "$(git commit-tree "$(git mktree < /dev/null)" -m orfao)"
  v9_espera "ref de base num commit sem relação: mesma base" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  git branch -q -D main
  v9_espera "ref de base inexistente: mesma base" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"

  # só leitura: status e índice intactos; temporários removidos
  lt="$(_leitura)"; mkdir -p "$t/tmp"
  TMPDIR="$t/tmp" "${v[@]}" >/dev/null 2>&1
  TMPDIR="$t/tmp" "${v[@]}" --force >/dev/null 2>&1
  [ "$(_leitura)" = "$lt" ] && ok "só leitura: status e índice intactos" || falha "a V9 mudou o status ou o índice"
  [ -z "$(ls -A "$t/tmp")" ] && ok "temporários removidos" || falha "temporários deixados: $(ls -A "$t/tmp" | tr '\n' ' ')"

  echo x > extra.ts; git add extra.ts; git commit -qm "produto fora do plano"
  rc_igual "arquivo de produto fora do plano reprova" 1 "${v[@]}"
  v9_espera "produto fora do plano: só ele é nomeado" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\textra.ts' "$FX_B1")"

  # isenções: pasta do trabalho, docs/entregas/<id>/, HISTORICO na SprintX
  mkdir -p docs/sprintx/estimativas docs/entregas/outro
  printf 'h\n' > docs/sprintx/estimativas/HISTORICO.md
  printf 'n\n' > docs/sprintx/features/ft-rec/notas.md
  printf 'n\n' > docs/entregas/ft-rec/NOTAS.md
  _v9_commit "metodo" docs/sprintx/estimativas/HISTORICO.md docs/sprintx/features/ft-rec/notas.md docs/entregas/ft-rec/NOTAS.md
  v9_espera "isenções de método (pasta, entrega, HISTORICO na SprintX) não são desvio" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\textra.ts' "$FX_B1")"
  printf 'o\n' > docs/sprintx/estimativas/outro.md
  printf 'o\n' > docs/entregas/outro/ENTREGA.md
  _v9_commit "fora" docs/sprintx/estimativas/outro.md docs/entregas/outro/ENTREGA.md
  v9_espera "outro arquivo de estimativas e a entrega de outro trabalho são desvio" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tdocs/entregas/outro/ENTREGA.md\nfora_do_plano\tdocs/sprintx/estimativas/outro.md\nfora_do_plano\textra.ts' "$FX_B1")"

  # reconciliado alterado depois de M: --verificar ok=false → v9_sem_prova
  printf 'export const depois = 1;\n' >> "$FX_NOVO1"; _v9_commit "muda o reconciliado" "$FX_NOVO1"
  v9_sem_prova "reconciliado alterado depois de M: v9_sem_prova" "ok=false"
  cd "$REPO" || return

  # ---- sem reconciliação: base de HEAD:ENTREGA, nunca do disco ------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  sed "s/^base_validada_sha: .*/base_validada_sha: $FX_M/" "$FX_ENTREGA" > "$t/e" && cat "$t/e" > "$FX_ENTREGA"
  out="$("${v[@]}" 2>/dev/null)"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = "base=$FX_B0" ] && ok "base do disco divergente: vale a de HEAD" || falha "base do disco: $(printf '%s' "$out" | tr '\n\t' '|>')"
  printf '%s\n' "$out" | grep -q "^aviso	.*$FX_M.*$FX_B0" && ok "divergência relatada numa linha aviso" || falha "sem aviso: $(printf '%s' "$out" | tr '\n\t' '|>')"
  [ "$(printf '%s\n' "$out" | grep -c '^fora_do_plano	')" = 2 ] && ok "base do disco divergente: os dois continuam desvio" || falha "base do disco escondeu desvio"
  rc_igual "base do disco divergente: rc 1" 1 "${v[@]}"
  git restore -- "$FX_ENTREGA"

  # plano sujo no disco não amplia o aceito; commitado, amplia
  tk=docs/sprintx/features/ft-rec/sprint-01/tasks.md
  sed "s#cria: \[tests/ui/ft-rec.test.ts\]#cria: [tests/ui/ft-rec.test.ts, $FX_NOVO1]#" "$tk" > "$t/tk" && cat "$t/tk" > "$tk"
  grep -Fq "$FX_NOVO1" "$tk" && ! git diff --quiet -- "$tk" \
    && ok "controle: o plano do disco (sujo) declara $FX_NOVO1" || falha "controle: a edição do plano não pegou"
  v9_espera "tasks.md sujo declarando arquivo fora do plano: V9 reprova" 1 \
    "$(printf 'base=%s\norigem_base=registrada_e0\nresultado=v9\nfora_do_plano\t%s\nfora_do_plano\t%s' "$FX_B0" "$FX_NOVO2" "$FX_NOVO1")"
  _v9_commit "plano" "$tk"
  v9_espera "controle: o plano commitado amplia o aceito" 1 \
    "$(printf 'base=%s\norigem_base=registrada_e0\nresultado=v9\nfora_do_plano\t%s' "$FX_B0" "$FX_NOVO2")"
  cd "$REPO" || return

  # ---- artefato com contrato quebrado: ok=false → v9_sem_prova ------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  sed 's/^estado: ativa$/estado: superada/' "$AR" > "$t/a" && cat "$t/a" > "$AR"
  rc_igual "controle: --verificar reprova o artefato editado" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  v9_sem_prova "--verificar com ok=false: v9_sem_prova, nada coberto" "ok=false"
  cd "$REPO" || return

  # ---- caminho com espaço, acento e apóstrofo -------------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=caminho_especial fx_cenario "$d" || { falha "caminho_especial não montou"; return; }
  cd "$d" || return
  out="$("${v[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -Fxq "fora_do_plano	$FX_ESPECIAL" \
    && ok "caminho especial fora do plano listado exato (sem quoting)" || falha "caminho especial: $(printf '%s' "$out" | tr '\n\t' '|>')"
  [ "$(printf '%s\n' "$out" | grep -c '^fora_do_plano	')" = 3 ] && ok "caminho especial: três desvios" || falha "caminho especial: contagem"
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" "$FX_ESPECIAL" >/dev/null
  v9_espera "caminho especial coberto: aceito" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  cd "$REPO" || return

  # ---- RunX: HISTORICO.md não é isento --------------------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=runx fx_cenario "$d" || { falha "runx não montou"; return; }
  cd "$d" || return
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  v=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec)
  v9_espera "RunX registrada: aprova" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  mkdir -p docs/sprintx/estimativas; printf 'h\n' > docs/sprintx/estimativas/HISTORICO.md
  _v9_commit "historico" docs/sprintx/estimativas/HISTORICO.md
  v9_espera "RunX: HISTORICO.md é desvio" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tdocs/sprintx/estimativas/HISTORICO.md' "$FX_B1")"
  cd "$REPO" || return
  v=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)

  # ---- legado sem a chave: merge-base único, só leitura ---------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  lt="$(_leitura)"
  v9_espera "legado sem base_validada_sha: merge-base único com branch_base (inferida_leitura)" 1 \
    "$(printf 'base=%s\norigem_base=inferida_leitura\nresultado=v9\nfora_do_plano\t%s\nfora_do_plano\t%s' "$FX_B1" "$FX_NOVO2" "$FX_NOVO1")"
  [ "$(_leitura)" = "$lt" ] && git diff --quiet HEAD -- "$FX_ENTREGA" && ok "legado: nada gravado" || falha "legado: a V9 gravou"
  git branch -q -m main base-antiga
  v9_sem_prova "legado com branch_base inexistente: v9_sem_prova" "branch_base"
  git branch -q -m base-antiga main
  x="$(git commit-tree "$FX_M^{tree}" -p "$FX_P1" -p "$FX_B1" -m gemeo)"
  git branch -f main "$x"
  [ "$(git merge-base --all HEAD main | grep -c .)" = 2 ] && ok "controle: dois merge-bases" || falha "controle: merge-bases"
  v9_sem_prova "legado com dois merge-bases: v9_sem_prova" "merge-base"
  cd "$REPO" || return

  # ---- base com um merge -s ours que DESCARTOU a pasta do trabalho ----------
  # A árvore da base não tem a pasta; só a história tem (o 2º pai do merge). A
  # simplificação de histórico do rev-list com pathspec segue o pai TREESAME e
  # esconde esse commit; a guarda (b) precisa de --full-history (CodeAnt
  # 4235520258). Legado, para a base ser o merge-base único com branch_base.
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  # S: sobre B0, toca a pasta do trabalho (sem Trabalho: e fora de ENTREGA.commits)
  git switch -q --detach "$FX_B0" && mkdir -p docs/sprintx/features/ft-rec \
    && printf 'lateral\n' > docs/sprintx/features/ft-rec/lateral.md \
    && git add docs/sprintx/features/ft-rec/lateral.md && git commit -qm 'lateral: toca a pasta do trabalho' || { falha "S não montou"; cd "$REPO"; return; }
  x="$(git rev-parse HEAD)"
  # B2: merge -s ours de S em B1 (árvore de B1, S na história); main passa a ser B2
  git switch -q --detach "$FX_B1" && git merge -q -s ours -m 'merge -s ours: descarta a pasta do trabalho' "$x" || { falha "B2 não montou"; cd "$REPO"; return; }
  x="$(git rev-parse HEAD)"
  git branch -f main "$x"
  # HEAD passa a descender de B2 sem mudar a árvore de M: merge-base único = B2
  git switch -q feature/ft-rec || { falha "volta à feature"; cd "$REPO"; return; }
  git update-ref refs/heads/feature/ft-rec "$(git commit-tree "$FX_M^{tree}" -p "$FX_M" -p "$x" -m 'merge: traz B2')"
  [ "$(git merge-base --all HEAD main)" = "$x" ] && [ -z "$(git ls-tree main docs/sprintx)" ] && [ -z "$(git status --porcelain)" ] \
    && [ -z "$(git rev-list -n1 main -- docs/sprintx/features/ft-rec docs/entregas/ft-rec)" ] \
    && [ "$(git rev-list -n1 --full-history main -- docs/sprintx/features/ft-rec docs/entregas/ft-rec)" = "$x" ] \
    && ok "controle: a base é B2 (merge-base único), sem a pasta na árvore; o rev-list simplificado não a vê, o --full-history vê" \
    || falha "controle do merge -s ours: mb=$(git merge-base --all HEAD main | tr '\n' ' ') simples='$(git rev-list -n1 main -- docs/sprintx/features/ft-rec)' full='$(git rev-list -n1 --full-history main -- docs/sprintx/features/ft-rec)'"
  v9_sem_prova "base com merge -s ours que descartou a pasta do trabalho: v9_sem_prova (a base contém o trabalho)" "toca a pasta do trabalho"
  cd "$REPO" || return

  # ---- chave presente e inválida em HEAD; contexto divergente --------------
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=entrega_base_null fx_cenario "$d" || { falha "entrega_base_null não montou"; return; }
  cd "$d" || return
  v9_sem_prova "base_validada_sha null em HEAD: v9_sem_prova" "base_validada_sha malformada"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  e=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec)
  rc_igual "origem divergente do ENTREGA.md: rc 3" 3 "${e[@]}"

  # ---- uso ------------------------------------------------------------------
  rc_igual "--force é uso inválido" 64 "${v[@]}" --force
  rc_igual "opção desconhecida é uso inválido" 64 "${v[@]}" --sem-prova
  rc_igual "sem argumentos é uso inválido" 64 bash "$V9"
  rc_igual "sem --verificar é uso inválido" 64 bash "$V9" --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  rc_igual "--entrega fora de docs/entregas/<id>/ENTREGA.md é uso inválido" 64 bash "$V9" --verificar --entrega outro.md --origem sprintx --trabalho ft-rec
  rc_igual "origem inválida é uso inválido" 64 bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem n/a --trabalho ft-rec
  cd "$REPO" || return
}

# _v9_gitlink <caminho> — põe um gitlink (160000) no índice
_v9_gitlink() { git update-index --add --cacheinfo 160000,"$FX_B0","$1"; }

# _v9_gitmodules — .gitmodules com ignore = all para vendor/lib, e o plano do
# disco declarando .gitmodules (para que só o gitlink fique de fora)
_v9_gitmodules() {
  local tk=docs/sprintx/features/ft-rec/sprint-01/tasks.md
  printf '[submodule "lib"]\n\tpath = vendor/lib\n\turl = ./lib\n\tignore = all\n' > .gitmodules
  sed 's#cria: \[tests/ui/ft-rec.test.ts\]#cria: [tests/ui/ft-rec.test.ts, .gitmodules]#' "$tk" > "$tk.v9" && cat "$tk.v9" > "$tk" && rm -f "$tk.v9"
  git add -- .gitmodules "$tk"
}

# _v9_entrega_commit <sed> — reescreve o ENTREGA.md com o sed e commita
_v9_entrega_commit() {
  sed "$1" "$FX_ENTREGA" > "$FX_ENTREGA.v9" && cat "$FX_ENTREGA.v9" > "$FX_ENTREGA" && rm -f "$FX_ENTREGA.v9"
  _v9_commit "entrega" "$FX_ENTREGA"
}

# _v9_reconstroi <mensagem> — sobre B0, um commit X que cria src/evil.ts (produto
# fora do plano) com a mensagem dada, e a feature (B0..P1, primeiro pai) refeita
# por cima na branch atk. Define X.
_v9_reconstroi() {
  git switch -q --detach "$FX_B0" || return 1
  printf 'export const mal = 1;\n' > src/evil.ts
  git add src/evil.ts && printf '%s\n' "$1" | git commit -q -F - || return 1
  X="$(git rev-parse HEAD)"
  git switch -q -c atk || return 1
  git cherry-pick $(git rev-list --reverse --first-parent "$FX_B0..$FX_P1") >/dev/null 2>&1
}

# _v9_commit_rm <arquivo> — remove o arquivo num commit próprio
_v9_commit_rm() { git rm -q -- "$1" && git commit -q -m "remove $1"; }

# _v9_ambiguo — um prefixo de 4 hex que é de dois commits (gerados até colidir)
_v9_ambiguo() {
  local arv n c p vistos=""
  arv="$(git rev-parse "$FX_B0^{tree}")"
  n=0
  while [ "$n" -lt 4000 ]; do
    n=$((n + 1))
    c="$(git commit-tree "$arv" -p "$FX_B0" -m "colisao $n")"; p="${c:0:4}"
    case " $vistos " in *" $p "*) printf '%s\n' "$p"; return 0 ;; esac
    vistos="$vistos $p"
  done
  return 1
}

# Fix round 1: submódulo, sanidade da base, guardas da árvore de HEAD, renomeação.
grupo_v9_robusto() {
  local d v t out modo x plano msg r
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")
  v=(bash "$V9" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec)
  r=(bash "$RB" --registrar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec --)

  # ---- submódulo depois de M: nunca escondido, nunca isento ------------------
  for modo in config gitmodules; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
    cd "$d" || return
    "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1
    _v9_gitlink vendor/lib
    case "$modo" in config) git config diff.ignoreSubmodules all ;; gitmodules) _v9_gitmodules ;; esac
    git commit -q -m "submodulo fora do plano"
    v9_espera "submódulo depois de M com $modo ignore=all: fora do plano" 1 \
      "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tvendor/lib' "$FX_B1")"
    cd "$REPO" || return
  done
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1
  _v9_gitlink docs/entregas/ft-rec/sub
  git commit -q -m "submodulo na pasta da entrega"
  v9_espera "submódulo na pasta da entrega não é isento" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tdocs/entregas/ft-rec/sub' "$FX_B1")"
  _v9_gitlink docs/sprintx/features/ft-rec/sub
  git commit -q -m "submodulo na pasta do trabalho"
  v9_sem_prova "submódulo na pasta do trabalho em HEAD: o plano não é lido" "submódulo (modo 160000)"
  cd "$REPO" || return

  # ---- submódulo criado DENTRO do merge M: registro, verificação e V9 --------
  for modo in config gitmodules; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_merge_sem_commit "$d" || { falha "merge sem commit não montou"; return; }
    cd "$d" || return
    _v9_gitlink vendor/lib
    case "$modo" in config) git config diff.ignoreSubmodules all ;; gitmodules) _v9_gitmodules ;; esac
    msg="$t/m-$modo"; printf 'merge: integra a main na feature ft-rec\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_B1" > "$msg"
    git commit -q -F "$msg"
    FX_M="$(git rev-parse HEAD)"
    [ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] && ok "controle ($modo): M com dois pais" || falha "controle ($modo): M não é merge"
    rc_motivo "submódulo no merge ($modo): --registrar reprova pelo inventário" 4 "vendor/lib" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
    rc_motivo "submódulo no merge ($modo): o gitlink nunca é reconciliado" 4 "vendor/lib" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" vendor/lib
    [ ! -e "$AR" ] && ok "submódulo no merge ($modo): nada registrado" || falha "submódulo no merge ($modo): registrou"
    fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja ($modo)"
    out="$(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec 2>/dev/null)"; x=$?
    [ "$x" = 4 ] && printf '%s\n' "$out" | grep -q '^motivo	inventario	.*vendor/lib' \
      && ok "submódulo no merge ($modo): --verificar reprova pelo inventário" || falha "submódulo no merge ($modo): verificar rc=$x $(printf '%s' "$out" | tr '\n\t' '|>')"
    v9_sem_prova "submódulo no merge ($modo): V9 sem prova" "ok=false"
    cd "$REPO" || return
  done

  # ---- base que contém o trabalho: v9_sem_prova -----------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  git branch -f main HEAD
  v9_sem_prova "legado com a ref de base movida para HEAD" "é o próprio HEAD"
  git branch -f main "$FX_B1"
  _v9_entrega_commit 's#^branch_base: main$#branch_base: feature/ft-rec#'
  v9_sem_prova "legado com branch_base = a própria branch" "é o próprio HEAD"
  cd "$REPO" || return

  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $FX_M/"
  v9_sem_prova "base_validada_sha = M commitado" "a base contém o trabalho"
  cd "$REPO" || return

  # só o trailer Trabalho: um commit lateral da base com o trailer
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(printf 'parte do trabalho na base\n\nTrabalho: ft-rec\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $x/"
  v9_sem_prova "base com commit Trabalho: ft-rec no histórico" "Trabalho: ft-rec"
  cd "$REPO" || return

  # só ENTREGA.commits: o commit do plano (sem trailer) listado e usado como base
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  plano="$(git rev-parse "$FX_P1~4")"
  git show -s --format=%B "$plano" | grep -q '^Trabalho:' && falha "controle: o commit do plano tem trailer" || ok "controle: o commit do plano não tem trailer"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $plano/; s/^    commit: \(.*\)$/    commit: \1\n  - seq: 2\n    task: T-01.01\n    commit: $plano/"
  v9_sem_prova "base que contém um commit de ENTREGA.commits" "ENTREGA.commits"
  cd "$REPO" || return

  # ---- base ancorada na entrega (a) e sem a pasta do trabalho (b) -----------
  # S1: X (cria src/evil.ts, sem trailer) logo depois de B0 e a feature refeita
  # por cima; com base_validada_sha = X commitado, evil.ts sumiria do diff
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (S1)"
  out="$("${v[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -Fxq 'fora_do_plano	src/evil.ts' && ok "controle S1a: com a base de E0, evil.ts é desvio" || falha "controle S1a: $(printf '%s' "$out" | tr '\n\t' '|>')"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $X/"
  v9_sem_prova "S1b: base_validada_sha commitado diferente do das outras versões do ENTREGA.md" "bases diferentes"
  cd "$REPO" || return

  # trailer fora da forma canônica num commit lateral usado como base: (a)
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(printf 'parte do trabalho\n\nTrabalho:ft-rec\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $x/"
  v9_sem_prova "trailer escrito de outro jeito (Trabalho:ft-rec) na base" "bases diferentes"
  cd "$REPO" || return

  # ---- âncora em todas as versões do ENTREGA.md (fix round 3) --------------
  # R3/R3b/R3c/R3d: um lado saído de X traz o ENTREGA.md com base X por merge
  local modo_m
  for modo_m in R3 R3b R3c R3d; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
    cd "$d" || return
    _v9_reconstroi "chore: utilitario" || falha "reconstrução ($modo_m)"
    cp "$FX_ENTREGA" "$t/e-$modo_m"
    [ "$modo_m" != R3c ] || _v9_commit_rm "$FX_ENTREGA"
    git switch -q --detach "$X" && git switch -q -c lado
    mkdir -p docs/entregas/ft-rec
    sed "s/^base_validada_sha: .*/base_validada_sha: $X/" "$t/e-$modo_m" > "$FX_ENTREGA"; git add -- "$FX_ENTREGA"
    if [ "$modo_m" = R3d ]; then
      GIT_COMMITTER_DATE='2001-01-01T00:00:00' GIT_AUTHOR_DATE='2001-01-01T00:00:00' git commit -q -m "docs: entrega"
    else git commit -q -m "docs: entrega"; fi
    case "$modo_m" in
      R3b) git merge -q --no-ff --no-commit atk >/dev/null 2>&1
           git show "lado:$FX_ENTREGA" > "$FX_ENTREGA"; git add -- "$FX_ENTREGA"; git commit -q -m "merge: traz a feature" ;;
      R3c) git switch -q atk; git merge -q --no-ff -m "merge: traz a entrega" lado >/dev/null 2>&1 || falha "R3c: o merge não foi limpo" ;;
      *)   git switch -q atk; git merge -q --no-ff --no-commit lado >/dev/null 2>&1
           git show "lado:$FX_ENTREGA" > "$FX_ENTREGA"
           [ "$modo_m" != R3d ] || printf '\nNota do merge.\n' >> "$FX_ENTREGA"
           git add -- "$FX_ENTREGA"; git commit -q -m "merge: traz o lado" ;;
    esac
    [ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] && [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$X" ] \
      && ok "controle $modo_m: HEAD é merge com a base X" || falha "controle $modo_m: montagem"
    v9_sem_prova "$modo_m: ENTREGA.md trazido por merge com outra base" "bases diferentes"
    cd "$REPO" || return
  done

  # R8: a chave tirada num commit (rebaixamento a legado) e a ref de base em X
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (R8)"
  _v9_entrega_commit '/^base_validada_sha:/d; /^origem_base:/d; /^reconciliacoes:/d; /^portao_sha:/d'
  git branch -f main "$X"
  v9_sem_prova "R8: rebaixamento a legado com a ref de base em X" "rebaixamento a legado"
  cd "$REPO" || return

  # fluxo normal em P1 (E0, E1, E2): git mv e ENTREGA.md recriado com o mesmo valor
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  git switch -q -c p1 "$FX_P1"
  out="$(printf 'base=%s\norigem_base=registrada_e0\nresultado=ok' "$FX_B0")"
  v9_espera "fluxo normal em P1 (pre-e2, pre-e6, e8): aprova" 0 "$out"
  git mv "$FX_ENTREGA" docs/entregas/ft-rec/ENTREGA-velho.md && git commit -q -m "move a entrega"
  git mv docs/entregas/ft-rec/ENTREGA-velho.md "$FX_ENTREGA" && git commit -q -m "devolve a entrega"
  v9_espera "ENTREGA.md movido e devolvido (git mv): aprova" 0 "$out"
  cp "$FX_ENTREGA" "$t/e-p1"; _v9_commit_rm "$FX_ENTREGA"
  cp "$t/e-p1" "$FX_ENTREGA"; _v9_commit "recria a entrega" "$FX_ENTREGA"
  v9_espera "ENTREGA.md recriado com o mesmo valor: aprova" 0 "$out"
  _v9_commit_rm "$FX_ENTREGA"
  sed "s/^base_validada_sha: .*/base_validada_sha: $FX_B1/" "$t/e-p1" > "$FX_ENTREGA"; _v9_commit "recria com outra base" "$FX_ENTREGA"
  v9_sem_prova "ENTREGA.md recriado com outro valor" "bases diferentes"
  cd "$REPO" || return

  # residual: âncora nascida errada (R5). O ENTREGA.md já nasce com a base num
  # commit só de produto (sem marca, sem tocar a pasta); todas as versões
  # concordam. Documentado, não corrigido.
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  git switch -q --detach "$FX_B0"
  printf 'export const mal = 1;\n' > src/evil.ts; git add src/evil.ts; git commit -q -m "chore: utilitario"; X="$(git rev-parse HEAD)"
  git switch -q -c atk
  for x in $(git rev-list --reverse --first-parent "$FX_B0..$FX_P1"); do
    git cherry-pick -n "$x" >/dev/null 2>&1
    if git diff --cached --name-only | grep -Fxq "$FX_ENTREGA"; then
      sed "s/^base_validada_sha: .*/base_validada_sha: $X/" "$FX_ENTREGA" > "$t/e-r5" && cat "$t/e-r5" > "$FX_ENTREGA"; git add -- "$FX_ENTREGA"
    fi
    git commit -q -C "$x"
  done
  v9_espera "residual: âncora nascida errada (comportamento atual: aprova)" 0 \
    "$(printf 'base=%s\norigem_base=registrada_e0\nresultado=ok' "$X")"
  cd "$REPO" || return

  # S3 (legado, só a regra b): a ref movida para o commit do plano
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  git branch -f main "$(git rev-parse "$FX_P1~4")"
  v9_sem_prova "S3: legado com a base num commit que toca a pasta do trabalho" "toca a pasta do trabalho ou a entrega"
  cd "$REPO" || return

  # S5f (legado, só o trailer): i18n.commitEncoding UTF-16 local não desliga a guarda
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "$(printf 'chore: utilitario\n\nTrabalho: ft-rec')" || falha "reconstrução (S5)"
  git branch -f main "$X"
  v9_sem_prova "S5: legado com base que tem o trailer canônico" "Trabalho: ft-rec"
  git config i18n.commitEncoding UTF-16
  v9_sem_prova "S5f: com i18n.commitEncoding UTF-16 o trailer continua visto" "Trabalho: ft-rec"
  git config --unset i18n.commitEncoding
  cd "$REPO" || return

  # residual: legado com ref movida (S2b). A spec lê a ref no legado e o Git
  # local não distingue: X sem trailer e sem tocar a pasta, a ref movida para
  # ele, aprova. Documentado, não corrigido.
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (S2)"
  git branch -f main "$FX_B1"
  out="$("${v[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -Fxq 'fora_do_plano	src/evil.ts' && ok "residual (controle): ref em B1, evil.ts é desvio" || falha "residual (controle): $(printf '%s' "$out" | tr '\n\t' '|>')"
  git branch -f main "$X"
  v9_espera "residual: legado com ref movida (comportamento atual: aprova)" 0 \
    "$(printf 'base=%s\norigem_base=inferida_leitura\nresultado=ok' "$X")"
  cd "$REPO" || return

  # ---- ENTREGA.commits com entrada que não resolve para um único commit -----
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_entrega_commit 's/^commits:$/commits:\n  - seq: 0\n    task: T-00.00\n    commit: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef/'
  v9_sem_prova "S6c: ENTREGA.commits com SHA inexistente" "não resolve para um único commit"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(_v9_ambiguo)" || falha "S6b: colisão de prefixo não gerada"
  git rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1 && falha "controle S6b: $x resolve" || ok "controle S6b: $x é ambíguo"
  _v9_entrega_commit "s/^commits:\$/commits:\n  - seq: 0\n    task: T-00.00\n    commit: $x/"
  v9_sem_prova "S6b: ENTREGA.commits com abreviação ambígua" "não resolve para um único commit"
  cd "$REPO" || return

  # ---- branch_base inválida (legado) ----------------------------------------
  for x in HEAD '@{-1}' '@'; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "legado não montou"; return; }
    cd "$d" || return
    _v9_entrega_commit "s#^branch_base: main\$#branch_base: $x#"
    v9_sem_prova "legado com branch_base: $x" "branch_base"
    cd "$REPO" || return
  done

  # ---- chave presente e ilegível: nunca cai no legado por ref ---------------
  for x in entrega_base_vazia entrega_base_aspas; do
    d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE="$x" fx_cenario "$d" || { falha "$x não montou"; return; }
    cd "$d" || return
    v9_sem_prova "$x: v9_sem_prova, sem legado por ref" "base_validada_sha malformada"
    cd "$REPO" || return
  done

  # ---- duas reconciliações: a base é o b1_sha da ÚLTIMA ----------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "emissão do 002"
  fx_entrega_sincroniza "$d" || falha "sincronização"
  v9_espera "duas reconciliações: base é o b1_sha do 002" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B2")"
  cd "$REPO" || return

  # ---- renomeação para a pasta isenta: o caminho antigo continua no diff ----
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1
  git mv README.md docs/entregas/ft-rec/README.md; git commit -q -m "move produto para a pasta da entrega"
  v9_espera "produto renomeado para docs/entregas/<id>/: o caminho antigo é desvio" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tREADME.md' "$FX_B1")"
  cd "$REPO" || return

  # ---- guardas da árvore de HEAD (biblioteca comum) --------------------------
  local alvo; alvo="$(mktemp -d)"; TMPS+=("$alvo")
  for x in plano_tab plano_symlink plano_nl; do
    d="$(mktemp -d)"; TMPS+=("$d"); FX_NL_ALVO="$alvo" FX_VARIANTE="$x" fx_cenario "$d" || { falha "$x não montou"; return; }
    cd "$d" || return
    case "$x" in plano_symlink) out="link simbólico ou submódulo" ;; *) out="caminho inválido" ;; esac
    v9_sem_prova "$x em HEAD: v9_sem_prova" "$out"
    cd "$REPO" || return
  done
}

grupo_barreira() {
  local d b out rc esperado t
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  b=(bash "$RB" --verificar --checkpoint reconciliacao-base --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  out="$("${b[@]}" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = ok=true ] && ok "sem reconciliação e ENTREGA.md persistido: ok=true" || falha "barreira sem reconciliação: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  rc_igual "--checkpoint diferente de reconciliacao-base é uso" 64 bash "$RB" --verificar --checkpoint pre-e6 --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  rc_igual "--checkpoint e8 é uso" 64 bash "$RB" --verificar --checkpoint e8 --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  rc_igual "--checkpoint sem valor é uso" 64 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --checkpoint
  rc_igual "--checkpoint repetido é uso" 64 "${b[@]}" --checkpoint reconciliacao-base
  rc_igual "--checkpoint no --registrar é uso" 64 bash "$RB" --registrar --checkpoint reconciliacao-base --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1"
  [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] && ok "uso inválido não grava nada" || falha "uso inválido gravou"

  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  rc_igual "controle: --verificar simples aprova o registrado" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && ok "registrado sem checkpoint: rc 5" || falha "registrado sem checkpoint: rc=$rc"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = ok=false ] && ! printf '%s\n' "$out" | grep -q '^coberto' \
    && ok "registrado sem checkpoint: ok=false sem coberto" || falha "registrado sem checkpoint: $(printf '%s' "$out" | tr '\n\t' '|>')"
  printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$FX_ENTREGA" \
    && ok "motivo de persistência do ENTREGA.md" || falha "sem motivo do ENTREGA.md: $(printf '%s' "$out" | tr '\n\t' '|>')"
  printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$AR" \
    && ok "motivo de persistência do artefato" || falha "sem motivo do artefato: $(printf '%s' "$out" | tr '\n\t' '|>')"

  bash "$S/persistir-metodo.sh" --persistir --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --checkpoint reconciliacao-base >/dev/null 2>&1 \
    && ok "checkpoint reconciliacao-base persistido" || falha "persistir-metodo falhou"
  esperado="$(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec 2>/dev/null)"
  out="$("${b[@]}" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$esperado" ] && [ "$(printf '%s\n' "$out" | grep -c '^coberto	')" = 2 ] \
    && ok "depois do checkpoint: ok, mesma saída do --verificar" || falha "depois do checkpoint: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"

  printf '\nNota acrescentada depois do commit.\n' >> "$AR"
  rc_igual "controle: o --verificar simples aceita a edição da prosa" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && [ "$(printf '%s\n' "$out" | grep -c '^motivo')" = 1 ] && printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$AR" \
    && ok "artefato editado depois do commit: rc 5, só a persistência" || falha "artefato editado: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"

  # o índice não é prova: assume-unchanged e skip-worktree não escondem a edição
  local bit
  for bit in assume-unchanged skip-worktree; do
    git update-index "--$bit" -- "$AR"
    git diff --quiet HEAD -- "$AR" && ok "controle: com --$bit o índice não vê a edição" || falha "controle: --$bit"
    out="$("${b[@]}" 2>/dev/null)"; rc=$?
    [ "$rc" = 5 ] && printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$AR" \
      && ok "artefato editado com --$bit: rc 5" || falha "artefato editado com --$bit: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
    git update-index "--no-$bit" -- "$AR"
  done
  git restore -- "$AR"
  rc_igual "controle: restaurado, a barreira aprova" 0 "${b[@]}"

  # disco devolvido ao pré-registro (ENTREGA.md de M, sem o 001), escondido do índice
  git show "$FX_M:$FX_ENTREGA" > "$t/e-m" && cat "$t/e-m" > "$FX_ENTREGA"; mv "$AR" "$t/ar"
  git update-index --assume-unchanged -- "$FX_ENTREGA" "$AR"
  rc_igual "controle: o --verificar simples aprova o disco pré-registro" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && printf '%s\n' "$out" | grep -Fq "motivo	persistencia	" \
    && ok "disco pré-registro escondido do índice: rc 5" || falha "disco pré-registro: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  git update-index --no-assume-unchanged -- "$FX_ENTREGA" "$AR"
  git restore -- "$FX_ENTREGA"; mv "$t/ar" "$AR"
  rc_igual "controle: devolvido, a barreira aprova" 0 "${b[@]}"

  printf '\nNota.\n' >> "$FX_ENTREGA"; git add -- "$FX_ENTREGA"
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$FX_ENTREGA" \
    && ok "ENTREGA.md no stage e não commitado: rc 5" || falha "ENTREGA.md no stage: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  git restore --staged --worktree -- "$FX_ENTREGA"
  rc_igual "controle: ENTREGA.md devolvido, a barreira aprova" 0 "${b[@]}"

  # HEAD com um artefato que o disco não tem (o ENTREGA.md, igual a HEAD, não o lista)
  cp "$AR" docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  _v9_commit "artefato a mais em HEAD" docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  rc_igual "controle: o --verificar simples aprova o disco" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && printf '%s\n' "$out" | grep -q "^motivo	persistencia	.*RECONCILIACAO-BASE-002.md" \
    && ok "conjunto de artefatos em HEAD diferente do disco: rc 5" || falha "conjunto de artefatos: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  cd "$REPO" || return
}

# Fix round 4 (N6): repositório raso é recusado pela V9 e pela reconciliação.
RASO_MOTIVO='repositório raso: história incompleta'

# raso_v9 <desc> — V9 rc 3 com o motivo do raso como PRIMEIRO motivo (exato:
# o motivo repassado do --verificar, com prefixo, não serve)
raso_v9() {
  local out rc
  out="$("${v[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 3 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = resultado=v9_sem_prova ] \
    && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "motivo	$RASO_MOTIVO" ] \
    && ! printf '%s\n' "$out" | grep -Eq '^(base=|fora_do_plano)' \
    && ok "$1" || falha "$1 — rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
}

# raso_verificar <desc> [--checkpoint reconciliacao-base] — rc 4, ok=false e só
# o motivo estrutura[raso]
raso_verificar() {
  local desc="$1" out rc; shift
  out="$(bash "$RB" --verificar "$@" --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec 2>/dev/null)"; rc=$?
  [ "$rc" = 4 ] && [ "$out" = "$(printf 'ok=false\nmotivo\testrutura\testrutura[raso]: %s' "$RASO_MOTIVO")" ] \
    && ok "$desc" || falha "$desc — rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
}

# raso_registrar <desc> <caminho>... — rc 4 estrutura[raso], nada gravado
raso_registrar() {
  local desc="$1" err rc antes; shift
  antes="$(git status --porcelain=v1 --untracked-files=all | rb_sha256)"
  err="$(bash "$RB" --registrar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec -- "$@" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 4 ] && [ "$err" = "reconciliacao-base: estrutura[raso]: $RASO_MOTIVO" ] \
    && [ ! -e docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md ] \
    && [ "$(git status --porcelain=v1 --untracked-files=all | rb_sha256)" = "$antes" ] \
    && ok "$desc" || falha "$desc — rc=$rc $(printf '%s' "$err" | tr '\n' '|')"
}

grupo_raso() {
  local d c w t out rc mg sh
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")
  v=(bash "$V9" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec)

  # ---- S2: .git/shallow no commit que pôs X, HEAD merge com X ----------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (S2)"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $X/"; c="$(git rev-parse HEAD)"
  mg="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$X" -m "merge: traz o utilitario")"; git merge -q --ff-only "$mg"
  v9_sem_prova "controle S1: sem shallow, a base X é recusada" "bases diferentes"
  printf '%s\n' "$c" > "$t/shallow-c"
  # GIT_SHALLOW_FILE do ambiente não entra: o raso que vale é o do repositório
  out="$(GIT_SHALLOW_FILE="$t/shallow-c" "${v[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -q '^motivo	.*bases diferentes' \
    && ok "GIT_SHALLOW_FILE no ambiente é ignorado" || falha "GIT_SHALLOW_FILE: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  cp "$t/shallow-c" .git/shallow
  [ "$(git rev-parse --is-shallow-repository)" = true ] && ok "controle S2: o repositório é raso" || falha "controle S2: não ficou raso"
  raso_v9 "S2: .git/shallow no commit que pôs X: v9_sem_prova"
  raso_verificar "S2: --verificar no raso: rc 4 estrutura[raso]"
  raso_verificar "S2: barreira no raso: rc 4 estrutura[raso]" --checkpoint reconciliacao-base
  rm -f .git/shallow
  cd "$REPO" || return

  # ---- .git/shallow forjado: --registrar e --verificar ----------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  printf '%s\n' "$FX_B0" > .git/shallow
  raso_registrar "--registrar com .git/shallow forjado: rc 4, nada gravado" "$FX_NOVO1" "$FX_NOVO2"
  raso_verificar "--verificar com .git/shallow forjado: rc 4"
  raso_v9 "V9 com .git/shallow forjado: v9_sem_prova"
  : > .git/shallow
  raso_v9 "V9 com .git/shallow vazio: v9_sem_prova"
  rm -f .git/shallow
  # a trava ficou livre: sem o raso, o mesmo registro passa
  rc_igual "controle: sem o raso, o --registrar passa (trava liberada)" 0 \
    bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- clone --depth real e clone completo ------------------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$REPO" || return
  git clone -q --depth 2 --no-single-branch -b feature/ft-rec "file://$d" "$t/raso" 2>/dev/null || falha "clone --depth 2"
  cd "$t/raso" || return
  git branch -q main origin/main
  [ "$(git rev-parse --is-shallow-repository)" = true ] && ok "controle: clone --depth 2 é raso" || falha "controle: clone não é raso"
  raso_registrar "--registrar em clone --depth 2: rc 4, nada gravado" "$FX_NOVO1" "$FX_NOVO2"
  raso_verificar "--verificar em clone --depth 2: rc 4"
  raso_v9 "V9 em clone --depth 2: v9_sem_prova"

  # worktree vinculada do clone raso (o shallow fica no diretório comum)
  w="$t/wt-raso"
  if git worktree add -q --detach "$w" HEAD 2>/dev/null; then
    cd "$w" || return
    [ "$(git rev-parse --is-shallow-repository)" = true ] && ok "controle: worktree vinculada rasa" || falha "controle: worktree não é rasa"
    raso_v9 "V9 em worktree vinculada de clone raso: v9_sem_prova"
    raso_verificar "--verificar em worktree vinculada rasa: rc 4"
    cd "$t/raso" || return
    git worktree remove --force "$w"
  else falha "worktree vinculada não montou"; fi
  cd "$REPO" || return

  git clone -q -b feature/ft-rec "file://$d" "$t/completo" 2>/dev/null || falha "clone completo"
  cd "$t/completo" || return
  git branch -q main origin/main
  [ "$(git rev-parse --is-shallow-repository)" = false ] && ok "controle: clone completo não é raso" || falha "controle: clone completo raso"
  rc_igual "clone completo: --registrar passa" 0 \
    bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "clone completo: --verificar passa" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  v9_espera "clone completo: V9 aprova" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"

  # worktree vinculada do completo, com o shallow forjado no diretório comum e
  # no diretório Git próprio dela
  w="$t/wt-completo"
  if git worktree add -q --detach "$w" HEAD 2>/dev/null; then
    cd "$w" || return
    rc_igual "controle: worktree vinculada completa, V9 calcula" 1 "${v[@]}"
    sh="$(git rev-parse --path-format=absolute --git-common-dir)/shallow"
    printf '%s\n' "$FX_B0" > "$sh"
    raso_v9 "worktree vinculada com shallow no diretório comum: v9_sem_prova"
    rm -f "$sh"
    sh="$(git rev-parse --path-format=absolute --git-dir)/shallow"
    printf '%s\n' "$FX_B0" > "$sh"
    raso_v9 "worktree vinculada com shallow no próprio diretório Git: v9_sem_prova"
    raso_verificar "--verificar com shallow no diretório Git da worktree: rc 4"
    rm -f "$sh"
    cd "$t/completo" || return
    git worktree remove --force "$w"
  else falha "worktree vinculada do completo não montou"; fi
  cd "$REPO" || return
}

# pt_espera <desc> <rc> <ok=...> [motivo] [primeiro] — a saída de
# validade-do-portao.sh, sem as linhas aviso=, é exatamente a esperada.
# PT_REV não vazio acrescenta `--rev "$PT_REV"`.
pt_espera() {
  local desc="$1" rc_esp="$2" okv="$3" mot="${4:-}" pri="${5:--}" out rc esp
  out="$(bash "$VALIDADE" --verificar --entrega "${PT_ENTREGA:-$FX_ENTREGA}" ${PT_REV:+--rev "$PT_REV"} 2>/dev/null)"; rc=$?
  if [ "$okv" = ok=true ]; then esp="$(printf 'ok=true\nprimeiro_commit=-')"
  else esp="$(printf 'ok=false\nmotivo=%s\nprimeiro_commit=%s' "$mot" "$pri")"; fi
  [ "$rc" = "$rc_esp" ] && [ "$(printf '%s\n' "$out" | grep -v '^aviso=')" = "$esp" ] \
    && ok "$desc" || falha "$desc — rc=$rc $(printf '%s' "$out" | tr '\n' '|')"
}

# _pt_entrega_commit <sed> — reescreve o ENTREGA.md e commita como pre-e6
_pt_entrega_commit() {
  sed "$1" "$FX_ENTREGA" > "$FX_ENTREGA.tmp" && cat "$FX_ENTREGA.tmp" > "$FX_ENTREGA" && rm -f "$FX_ENTREGA.tmp"
  git add -- "$FX_ENTREGA"
  printf 'docs(mergex): ajusta o portao\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"
  git commit -q -F "$PT_MSG" >/dev/null || falha "fixture: _pt_entrega_commit '$1' não commitou"
}

grupo_portao() {
  local d t p out rc antes c c9 m s pai solto filho e e2
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  d="$(mktemp -d)"; t="$(mktemp -d)"; TMPS+=("$d" "$t"); PT_MSG="$t/msg"; PT_ENTREGA=""
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  e="$FX_ENTREGA"
  p=(bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA")

  # ---- passos do brief ----------------------------------------------------
  fx_portao_em "$d" "$FX_P1" || falha "fx_portao_em P1"
  rc_igual "merge depois do portão invalida" 1 "${p[@]}"
  # (captura: com pipefail, o rc 1 do script reprovaria um pipe direto no grep)
  out="$("${p[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -q '^motivo=commit_merge' && ok "motivo commit_merge" || falha "motivo"
  # a passada dos merges vem antes da avaliação commit a commit: o merge é a
  # causa, não B1 (que ele trouxe)
  pt_espera "merge depois do portão: commit_merge no merge M, não em B1" 1 ok=false commit_merge "$FX_M"
  fx_portao_em "$d" HEAD; fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/PR.md
  rc_igual "commit só de método pre-e6 mantém válido" 0 "${p[@]}"
  pt_espera "commit só de método pre-e6: ok=true e primeiro_commit=-" 0 ok=true
  fx_commit_metodo "$d" e8 src/painel.ts
  rc_igual "commit Metodo: tocando produto invalida" 1 "${p[@]}"
  pt_espera "Metodo: e8 tocando produto: metodo_fora_do_catalogo no próprio commit" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD; echo y >> "$FX_NOVO2"; git commit -qam "ajuste de teste"
  rc_igual "commit de teste invalida" 1 "${p[@]}"
  pt_espera "commit de teste: commit_de_produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  fx_portao_sem_sha "$d"
  rc_igual "pronto sem portao_sha invalida" 1 "${p[@]}"
  pt_espera "pronto sem portao_sha: portao_sha_ausente" 1 ok=false portao_sha_ausente -
  solto="$(fx_commit_solto "$d")"
  fx_portao_em "$d" "$solto"
  rc_igual "portao_sha não ancestral invalida" 1 "${p[@]}"
  pt_espera "portao_sha não ancestral: portao_sha_nao_ancestral" 1 ok=false portao_sha_nao_ancestral -

  # ---- --rev: a revisão avaliada é a empurrada, não o HEAD ------------------
  fx_portao_em "$d" HEAD; fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/PR.md
  c="$(git rev-parse HEAD)"
  # o ENTREGA de HEAD passa a dizer bloqueado; o de c ainda diz pronto
  _pt_entrega_commit 's/^portao: .*/portao: bloqueado/'
  pt_espera "controle --rev: sem --rev, o ENTREGA de HEAD (bloqueado)" 1 ok=false portao_nao_pronto -
  PT_REV="$c" pt_espera "--rev lê portao e portao_sha de <rev>:ENTREGA, não de HEAD" 0 ok=true
  _pt_entrega_commit 's/^portao: .*/portao: pronto/'
  printf 'export const depoisRev = 1;\n' > src/depois-rev.ts; git add src/depois-rev.ts
  git commit -q -m "feat: produto depois do portão"
  pt_espera "controle --rev: sem --rev, o HEAD vencido por produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  PT_REV="$c" pt_espera "--rev com commit anterior válido: ok=true com o HEAD vencido" 0 ok=true
  PT_REV=HEAD pt_espera "--rev HEAD: igual a sem --rev" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  PT_REV="$(git rev-parse HEAD)" pt_espera "--rev com o SHA do HEAD vencido: commit_de_produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  PT_REV=0123456789abcdef0123456789abcdef01234567 pt_espera "--rev inexistente: erro_ambiente" 1 ok=false erro_ambiente -
  PT_REV=nao-existe pt_espera "--rev com nome que não resolve: erro_ambiente" 1 ok=false erro_ambiente -
  # portao, portao_sha e trabalho_id saem de <rev>:<ENTREGA>, não de HEAD: na
  # base B0 não há ENTREGA nenhum
  PT_REV="$FX_B0" pt_espera "--rev na base B0: o ENTREGA daquela revisão decide" 1 ok=false portao_nao_pronto -
  rc_igual "--rev duplicado: rc 64" 64 bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" --rev HEAD --rev HEAD
  rc_igual "--rev sem valor: rc 64" 64 bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" --rev
  rc_igual "--rev vazio: rc 64" 64 bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" --rev ''
  # tree e blob não são commit: erro_ambiente, sem o `error:` do git no stderr
  for c in 'HEAD^{tree}' "HEAD:$FX_ENTREGA"; do
    PT_REV="$c" pt_espera "--rev com $c: erro_ambiente" 1 ok=false erro_ambiente -
    out="$(bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" --rev "$c" 2>&1 >/dev/null)"
    [ -z "$out" ] && ok "--rev com $c: stderr vazio" || falha "--rev com $c vazou no stderr: $out"
  done

  # ---- merge só de método: commit_merge no próprio merge --------------------
  fx_portao_em "$d" HEAD
  fixture_switch_exato lado-metodo -c lado-metodo
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/QA-PACOTE.md
  fixture_switch_exato feature/ft-rec feature/ft-rec
  printf 'merge: traz o metodo\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"
  git merge -q --no-ff -F "$PT_MSG" lado-metodo
  m="$(git rev-parse HEAD)"
  pt_espera "merge com Metodo: pre-e6 trazendo só método: commit_merge no merge" 1 ok=false commit_merge "$m"
  # um commit raiz (outra história) trazido por merge, com trailers de método
  fx_portao_em "$d" HEAD
  printf 'docs(mergex): raiz\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"
  s="$(git commit-tree "HEAD^{tree}" -F "$PT_MSG")"
  m="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$s" -F "$PT_MSG")"
  git merge -q --ff-only "$m"
  pt_espera "commit raiz trazido por merge: commit_merge no merge que o trouxe" 1 ok=false commit_merge "$m"
  # dois merges no intervalo: o mais antigo
  pai="$m"
  m="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$FX_B0" -F "$PT_MSG")"
  git merge -q --ff-only "$m"
  pt_espera "dois merges depois do portão: commit_merge no mais antigo" 1 ok=false commit_merge "$pai"
  # um merge num ramo lateral, trazido por outro merge: fora da linha de
  # primeiro pai, e é o mais antigo
  fx_portao_em "$d" HEAD
  pai="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$FX_B0" -F "$PT_MSG")"
  m="$(git commit-tree "HEAD^{tree}" -p HEAD -p "$pai" -F "$PT_MSG")"
  git merge -q --ff-only "$m"
  pt_espera "merge no ramo lateral trazido por merge: commit_merge no lateral (o mais antigo)" 1 ok=false commit_merge "$pai"

  # ---- checkpoints e trabalhos fora do aceito -------------------------------
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" reconciliacao-base "$e"
  pt_espera "Metodo: reconciliacao-base depois do portão: commit_de_produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" pre-e2 "$e"
  pt_espera "Metodo: pre-e2 depois do portão: commit_de_produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  printf 'outro\n' >> docs/entregas/ft-rec/PR.md; git add docs/entregas/ft-rec/PR.md
  printf 'docs(mergex): pacote\n\nTrabalho: outro\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 com Trabalho: de outro trabalho: commit_de_produto" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"

  # ---- artefatos de reconciliação: catálogo da árvore de cada commit ---------
  fx_portao_em "$d" HEAD
  awk 'NR == 1 { print; fm = 1; next }
       fm && /^---/ { fm = 0 }
       fm && /^reconciliacoes:/ { print "reconciliacoes:"; print "  - numero: 1"; print "    arquivo: RECONCILIACAO-BASE-001.md"; next }
       { print }' "$e" > "$e.tmp" && cat "$e.tmp" > "$e" && rm -f "$e.tmp"
  printf '# reconciliação 001\n' > docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  git add -- "$e" docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  printf 'docs(mergex): reconciliacao\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 tocando RECONCILIACAO-BASE-001.md listado em reconciliacoes mantém válido" 0 ok=true
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/RECONCILIACAO-BASE-009.md
  c9="$(git rev-parse HEAD)"
  pt_espera "pre-e6 tocando RECONCILIACAO-BASE-009.md não listado invalida" 1 ok=false metodo_fora_do_catalogo "$c9"
  # o commit seguinte lista o 009: o HEAD e o disco passam a listá-lo, mas o
  # catálogo de c9 vem da árvore de c9
  awk '{ print } /^    arquivo: RECONCILIACAO-BASE-001.md$/ { print "  - numero: 9"; print "    arquivo: RECONCILIACAO-BASE-009.md" }' "$e" > "$e.tmp" \
    && cat "$e.tmp" > "$e" && rm -f "$e.tmp"
  git add -- "$e"
  printf 'docs(mergex): lista o 009\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  git show HEAD:"$e" | grep -Fxq '    arquivo: RECONCILIACAO-BASE-009.md' && ok "controle: HEAD lista o 009" || falha "controle: HEAD não lista o 009"
  pt_espera "009 listado só depois: o catálogo de c9 é o da árvore de c9" 1 ok=false metodo_fora_do_catalogo "$c9"

  # ---- renomeação de produto para dentro de docs/entregas ---------------------
  fx_portao_em "$d" HEAD
  git rm -q docs/entregas/ft-rec/ATENCAO.md
  git mv src/painel.ts docs/entregas/ft-rec/ATENCAO.md
  printf 'docs(mergex): atencao\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 renomeando produto para docs/entregas invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"

  # ---- gitlink num caminho do catálogo ----------------------------------------
  fx_portao_em "$d" HEAD
  git rm -q docs/entregas/ft-rec/PR.md
  git update-index --add --cacheinfo "160000,$FX_B0,docs/entregas/ft-rec/PR.md"
  printf 'docs(mergex): pr\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 com gitlink num caminho do catálogo invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  git rm -q --cached docs/entregas/ft-rec/PR.md
  printf '# PR\n' > docs/entregas/ft-rec/PR.md; git add docs/entregas/ft-rec/PR.md
  printf 'docs(mergex): pr de volta\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"

  # ---- link simbólico num caminho do catálogo ---------------------------------
  fx_portao_em "$d" HEAD
  git rm -q docs/entregas/ft-rec/QA-PACOTE.md
  ln -s ../../../README.md docs/entregas/ft-rec/QA-PACOTE.md; git add docs/entregas/ft-rec/QA-PACOTE.md
  printf 'docs(mergex): qa\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  [ "$(git ls-tree HEAD docs/entregas/ft-rec/QA-PACOTE.md | cut -c1-6)" = 120000 ] && ok "controle: QA-PACOTE.md é link (120000)" || falha "controle: QA-PACOTE.md não é link"
  pt_espera "pre-e6 com link simbólico num caminho do catálogo invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  # o portão com o link na árvore; o commit seguinte troca o link por arquivo
  # (modo de origem 120000)
  fx_portao_em "$d" HEAD
  rm -f docs/entregas/ft-rec/QA-PACOTE.md; printf '# QA\n' > docs/entregas/ft-rec/QA-PACOTE.md; git add docs/entregas/ft-rec/QA-PACOTE.md
  printf 'docs(mergex): qa de volta\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 trocando link simbólico do catálogo por arquivo invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"

  # ---- renomeação de produto para um caminho livre do catálogo -----------------
  fx_portao_em "$d" HEAD
  git mv README.md docs/sprintx/features/ft-rec/00-DECISOES.md
  printf 'docs(mergex): decisoes\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 renomeando produto para caminho livre do catálogo invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  # o inverso: artefato do catálogo renomeado para produto (com -M, o registro
  # de renomeação traria a origem do catálogo e esconderia o destino)
  fx_portao_em "$d" HEAD
  git mv docs/entregas/ft-rec/PR.md src/pr-renomeado.ts
  printf 'docs(mergex): pr para produto\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "pre-e6 renomeando artefato do catálogo para produto invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  git mv src/pr-renomeado.ts docs/entregas/ft-rec/PR.md
  printf 'docs(mergex): pr de volta\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"

  # ---- plano depois do portão ------------------------------------------------------
  fx_portao_em "$d" HEAD
  e2="docs/sprintx/features/ft-rec/sprint-01/tasks.md"
  sed 's/^    status: concluida$/    status: pendente/' "$e2" > "$e2.tmp" && cat "$e2.tmp" > "$e2" && rm -f "$e2.tmp"
  git add -- "$e2"
  printf 'docs(mergex): plano\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  git show HEAD:"$e2" | grep -q '^    status: pendente$' && ok "controle: T-01.01 voltou a pendente" || falha "controle: T-01.01 não mudou"
  rc_igual "pre-e6 que volta T-01.01 a pendente invalida" 1 "${p[@]}"
  pt_espera "pre-e6 alterando tasks.md: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" e8 docs/sprintx/features/ft-rec/sprint-02/tasks.md
  rc_igual "e8 que cria sprint-02/tasks.md invalida" 1 "${p[@]}"
  pt_espera "e8 criando sprint-02/tasks.md: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" pre-e6 docs/sprintx/features/ft-rec/00-PLANEJAMENTO.md
  pt_espera "pre-e6 criando 00-PLANEJAMENTO.md: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" pre-e6 docs/sprintx/features/ft-rec/sprint-01/fases.md
  pt_espera "pre-e6 criando sprint-01/fases.md: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"

  # ---- caminho com quebra de linha ou TAB ----------------------------------------
  fx_portao_em "$d" HEAD
  c="evil
docs/entregas/ft-rec/PR.md"
  mkdir -p "$(dirname "$c")"; printf 'export const x = 1;\n' > "$c"; git add -- "$c"
  printf 'docs(mergex): nl\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  rc_igual "pre-e6 com caminho evil<NL>docs/entregas/ft-rec/PR.md invalida" 1 "${p[@]}"
  pt_espera "caminho com NL: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  c="docs/entregas/ft-rec/PR	.md"
  printf 'x\n' > "$c"; git add -- "$c"
  printf 'docs(mergex): tab\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  rc_igual "pre-e6 com caminho com TAB invalida" 1 "${p[@]}"
  pt_espera "caminho com TAB: metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"

  # ---- residual: o portão se reposiciona com um commit de método ---------------
  # (indistinguível de "E2 em P, depois pre-e6": fixa o comportamento atual)
  fx_portao_em "$d" HEAD
  printf 'export const residual = 1;\n' > src/residual.ts; git add src/residual.ts
  git commit -q -m "feat: produto depois do portão"
  pt_espera "controle: produto depois do portão invalida" 1 ok=false commit_de_produto "$(git rev-parse HEAD)"
  fx_portao_em "$d" HEAD
  rc_igual "residual: portão reposicionado por commit de método" 0 "${p[@]}"

  # ---- caminho especial (espaço, acento, apóstrofo; quotepath true) ----------
  git config core.quotepath true
  fx_portao_em "$d" HEAD
  mkdir -p docs/sprintx/features/ft-rec/base
  printf -- "---\nkind: base_indice\ntrabalho_id: ft-rec\nareas:\n  - arquivo: área com espaço e d'água.md\n---\n\n# Índice\n" > docs/sprintx/features/ft-rec/base/00-INDICE.md
  printf '# área\n' > "docs/sprintx/features/ft-rec/base/área com espaço e d'água.md"
  git add -- docs/sprintx/features/ft-rec/base
  printf 'docs(mergex): base\n\nTrabalho: ft-rec\nMetodo: pre-e6\n' > "$PT_MSG"; git commit -q -F "$PT_MSG"
  pt_espera "caminho especial do catálogo (base enumerada no índice) mantém válido" 0 ok=true
  fx_commit_metodo "$d" pre-e6 "$FX_ESPECIAL"
  pt_espera "caminho especial de produto num pre-e6 invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  git config core.quotepath false

  # ---- portao e portao_sha malformados ----------------------------------------
  fx_portao_em "$d" HEAD
  _pt_entrega_commit 's/^portao: .*/portao: bloqueado/'
  pt_espera "portao bloqueado: portao_nao_pronto" 1 ok=false portao_nao_pronto -
  _pt_entrega_commit 's/^portao: .*/portao: null/'
  pt_espera "portao null: portao_nao_pronto" 1 ok=false portao_nao_pronto -
  _pt_entrega_commit '/^portao: /d'
  pt_espera "portao ausente: portao_nao_pronto" 1 ok=false portao_nao_pronto -
  fx_portao_em "$d" HEAD
  _pt_entrega_commit 's/^kind: entrega$/kind: outro/'
  pt_espera "kind diferente de entrega em HEAD:ENTREGA: portao_nao_pronto" 1 ok=false portao_nao_pronto -
  _pt_entrega_commit 's/^kind: outro$/kind: entrega/'
  fx_portao_em "$d" HEAD
  _pt_entrega_commit 's/^portao_sha:.*/portao_sha: null/'
  pt_espera "portao_sha null: portao_sha_ausente" 1 ok=false portao_sha_ausente -
  _pt_entrega_commit 's/^portao_sha:.*/portao_sha:/'
  pt_espera "portao_sha vazio: portao_sha_ausente" 1 ok=false portao_sha_ausente -
  _pt_entrega_commit "s/^portao_sha:.*/portao_sha: $(git rev-parse --short HEAD)/"
  pt_espera "portao_sha abreviado: portao_sha_ausente" 1 ok=false portao_sha_ausente -
  _pt_entrega_commit "s/^portao_sha:.*/portao_sha: $(git rev-parse HEAD | tr a-f A-F)/"
  pt_espera "portao_sha em maiúsculas: portao_sha_ausente" 1 ok=false portao_sha_ausente -
  _pt_entrega_commit 's/^portao_sha:.*/portao_sha: 0123456789abcdef0123456789abcdef01234567/'
  pt_espera "portao_sha inexistente: portao_sha_nao_ancestral" 1 ok=false portao_sha_nao_ancestral -
  # descendente de HEAD fora da branch: o intervalo seria vazio
  filho="$(git commit-tree "HEAD^{tree}" -p HEAD -m "filho solto")"
  _pt_entrega_commit "s/^portao_sha:.*/portao_sha: $filho/"
  pt_espera "portao_sha descendente fora da história de HEAD: portao_sha_nao_ancestral" 1 ok=false portao_sha_nao_ancestral -

  # ---- o disco diverge do HEAD: aviso, vale o de HEAD -------------------------
  fx_portao_em "$d" HEAD
  sed "s/^portao_sha: .*/portao_sha: $FX_B0/" "$e" > "$e.tmp" && cat "$e.tmp" > "$e" && rm -f "$e.tmp"
  pt_espera "ENTREGA do disco com outro portao_sha: vale o de HEAD (ok)" 0 ok=true
  out="$("${p[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -q '^aviso=portao_sha do disco' && ok "ENTREGA do disco divergente gera aviso=" || falha "sem aviso de divergência: $(printf '%s' "$out" | tr '\n' '|')"
  # só leitura: o status e os temporários
  antes="$(git status --porcelain=v1 --untracked-files=all)"
  mkdir -p "$t/tmpdir"
  TMPDIR="$t/tmpdir" "${p[@]}" >/dev/null 2>&1
  [ "$(git status --porcelain=v1 --untracked-files=all)" = "$antes" ] && ok "só leitura: o status não muda" || falha "o status mudou"
  [ -z "$(ls -A "$t/tmpdir")" ] && ok "temporários removidos (ok)" || falha "temporário deixado: $(ls -A "$t/tmpdir")"
  fx_commit_metodo "$d" e8 src/fora.ts
  TMPDIR="$t/tmpdir" "${p[@]}" >/dev/null 2>&1
  [ -z "$(ls -A "$t/tmpdir")" ] && ok "temporários removidos (inválido)" || falha "temporário deixado: $(ls -A "$t/tmpdir")"
  git show "HEAD:$e" > "$e"

  # ---- ENTREGA ausente em HEAD e uso -------------------------------------------
  PT_ENTREGA=docs/entregas/outro/ENTREGA.md
  pt_espera "ENTREGA ausente em HEAD: portao_nao_pronto" 1 ok=false portao_nao_pronto -
  PT_ENTREGA=""
  rc_igual "opção desconhecida: rc 64" 64 bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" --force
  rc_igual "sem --entrega: rc 64" 64 bash "$VALIDADE" --verificar
  rc_igual "sem --verificar: rc 64" 64 bash "$VALIDADE" --entrega "$FX_ENTREGA"
  rc_igual "--entrega fora de docs/entregas: rc 64" 64 bash "$VALIDADE" --verificar --entrega README.md
  # dependência ausente: o script sozinho, sem as bibliotecas ao lado
  mkdir -p "$t/so"; cp "$VALIDADE" "$t/so/validade-do-portao.sh"
  out="$(bash "$t/so/validade-do-portao.sh" --verificar --entrega "$FX_ENTREGA" 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | grep -v '^aviso=')" = "$(printf 'ok=false\nmotivo=erro_ambiente\nprimeiro_commit=-')" ] \
    && printf '%s\n' "$out" | grep -q '^aviso=dependência indisponível' \
    && ok "dependência ausente: erro_ambiente com aviso=" || falha "dependência ausente — rc=$rc $(printf '%s' "$out" | tr '\n' '|')"
  # temporário que não se cria
  TMPDIR="$t/nao-existe" pt_espera "temporário que não se cria: erro_ambiente" 1 ok=false erro_ambiente -
  # fora de um repositório Git
  mkdir -p "$t/fora"; cd "$t/fora" || return
  GIT_CEILING_DIRECTORIES="$t" pt_espera "fora de um repositório Git: erro_ambiente" 1 ok=false erro_ambiente -
  out="$(GIT_CEILING_DIRECTORIES="$t" bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA" 2>/dev/null)"
  printf '%s\n' "$out" | grep -q '^aviso=fora de um repositório Git' && ok "fora de repositório: aviso=" || falha "fora de repositório sem aviso: $(printf '%s' "$out" | tr '\n' '|')"
  cd "$REPO" || return

  # ---- repositório raso ---------------------------------------------------------
  fx_portao_em "$d" HEAD
  git clone -q --depth 2 -b feature/ft-rec "file://$d" "$t/raso" 2>/dev/null || falha "clone --depth 2"
  cd "$t/raso" || return
  [ "$(git rev-parse --is-shallow-repository)" = true ] && ok "controle: clone raso" || falha "controle: clone não é raso"
  pt_espera "repositório raso: historia_incompleta" 1 ok=false historia_incompleta -
  cd "$REPO" || return

  # ---- objeto Git necessário ausente (numa cópia; objetos soltos) ---------------
  cd "$d" || return
  fx_portao_em "$d" HEAD
  local o f
  for x in head portao_sha; do
    rm -rf "$t/obj"; cp -a "$d" "$t/obj"
    case "$x" in head) o="$(git rev-parse HEAD)" ;; portao_sha) o="$(git rev-parse HEAD~1)" ;; esac
    f="$t/obj/.git/objects/$(printf '%s' "$o" | cut -c1-2)/$(printf '%s' "$o" | cut -c3-)"
    [ -f "$f" ] && ok "controle: o commit $x é objeto solto na cópia" || falha "controle: commit $x não é solto"
    rm -f "$f"
    cd "$t/obj" || return
    pt_espera "objeto ausente é historia_incompleta, não erro_ambiente ($x removido)" 1 ok=false historia_incompleta -
    out="$("${p[@]}" 2>/dev/null)"
    printf '%s\n' "$out" | grep -q '^aviso=.*objeto Git ausente' && ok "objeto ausente ($x): aviso= próprio" || falha "objeto ausente ($x) sem aviso: $(printf '%s' "$out" | tr '\n' '|')"
    cd "$d" || return
  done
  PT_REV=0123456789abcdef0123456789abcdef01234567 pt_espera "controle: --rev inexistente com a história inteira continua erro_ambiente" 1 ok=false erro_ambiente -

  # árvore ou blob ausente (não só commit): a árvore de um commit do intervalo,
  # a árvore de <rev>, o blob do ENTREGA.md de <rev> e uma subárvore que só o
  # diff-tree lê (src/ de um commit de método que toca produto)
  local v
  for x in arvore_intervalo arvore_rev blob_entrega arvore_diff; do
    fx_portao_em "$d" HEAD; v="$(git rev-parse HEAD)"
    case "$x" in
      arvore_diff) fx_commit_metodo "$d" pre-e6 "src/fora-$x.ts" ;;
      *) fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/PR.md ;;
    esac
    case "$x" in
      arvore_intervalo) o="$(git rev-parse "$v^{tree}")" ;;
      arvore_rev) o="$(git rev-parse "HEAD^{tree}")" ;;
      blob_entrega) o="$(git rev-parse "HEAD:$FX_ENTREGA")" ;;
      arvore_diff) o="$(git rev-parse "HEAD:src")" ;;
    esac
    rm -rf "$t/obj"; cp -a "$d" "$t/obj"
    f="$t/obj/.git/objects/$(printf '%s' "$o" | cut -c1-2)/$(printf '%s' "$o" | cut -c3-)"
    [ -f "$f" ] && ok "controle: $x é objeto solto na cópia" || falha "controle: $x não é solto"
    rm -f "$f"
    cd "$t/obj" || return
    pt_espera "objeto ausente que não é commit é historia_incompleta ($x)" 1 ok=false historia_incompleta -
    out="$("${p[@]}" 2>/dev/null)"
    printf '%s\n' "$out" | grep -q '^aviso=.*objeto Git ausente' && ok "objeto ausente ($x): aviso= de história incompleta" || falha "objeto ausente ($x) sem aviso: $(printf '%s' "$out" | tr '\n' '|')"
    cd "$d" || return
  done
  # controle: sem objeto ausente, o mesmo tipo de commit mantém o motivo de sempre
  fx_portao_em "$d" HEAD; fx_commit_metodo "$d" pre-e6 src/fora-controle.ts
  pt_espera "controle: método tocando src com a história inteira continua metodo_fora_do_catalogo" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"

  # ---- risco residual 5: isenção por prefixo da V9 não vale para a validade --------
  fx_portao_em "$d" HEAD
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/x.ts
  pt_espera "isenção por prefixo: .ts em docs/entregas depois do portão invalida" 1 ok=false metodo_fora_do_catalogo "$(git rev-parse HEAD)"
  cd "$REPO" || return
}
