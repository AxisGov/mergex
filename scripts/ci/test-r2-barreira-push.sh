#!/usr/bin/env bash
#
# Bancada da barreira de push (R2, DM-184).
#
# O pre-push do Git decide só pelo que o Git entrega (refs e SHAs), pela mesma
# regra (portao-regras.sh -> validade-do-portao.sh --rev) e pelo mesmo modo
# (pr-so-com-portao em .expx/hooks.json). Grupos: `prepush` (Task 14); os de
# ativação (15), CI (16) e modo (17) entram depois, na ordem de definição.
#
# Todo push daqui é REAL, contra o remoto bare local criado no temporário do
# teste (fx_remoto_bare): nunca rede, nunca o origin do repositório real.
#
# Uso: bash scripts/ci/test-r2-barreira-push.sh <grupo>... | todos

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$REPO/.claude/skills/mergex/scripts"
PP="$S/portao-push.sh"
REGRAS="$S/portao-regras.sh"
VALIDADE="$S/validade-do-portao.sh"
RB="$S/reconciliacao-base.sh"
PERSISTE="$S/persistir-metodo.sh"
ZERO=0000000000000000000000000000000000000000

OK=0; FALHOU=0
TMPS=""
trap 'cd "$REPO" 2>/dev/null; for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# rc_igual <desc> <rc> <cmd...> — exige o rc informado
rc_igual() {
  local desc="$1" esperado="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$esperado" ]; then ok "$desc"; else falha "$desc — rc=$rc, esperava $esperado"; fi
}

# push_espera <desc> <rc> <ref esperada|-> <dir> <args do git push>... — push
# REAL pela fixture; exige o rc do git push e o SHA da ref FX_PUSH_REF no
# remoto depois dele. O stderr do push fica em PUSH_ERR (para err_tem/err_sem).
PUSH_ERR=""
push_espera() {
  local desc="$1" rce="$2" refe="$3" dir="$4" out rc ref; shift 4
  out="$(fx_push_real "$dir" "$@")"
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  ref="$(printf '%s\n' "$out" | sed -n 's/^ref=//p')"
  PUSH_ERR="$(printf '%s\n' "$out" | sed -n 's/^stderr=//p')"
  if [ "$rc" = "$rce" ] && [ "$ref" = "$refe" ]; then ok "$desc"
  else falha "$desc — rc=$rc (esperava $rce), ref=$ref (esperava $refe); stderr: $(tr '\n' '|' < "${PUSH_ERR:-/dev/null}" 2>/dev/null)"; fi
}

# err_tem <desc> <texto fixo> / err_sem — o stderr do último push
err_tem() {
  if grep -Fq -- "$2" "$PUSH_ERR" 2>/dev/null; then ok "$1"; else falha "$1 — sem '$2' no stderr: $(tr '\n' '|' < "$PUSH_ERR" 2>/dev/null)"; fi
}
err_sem() {
  if ! grep -Fq -- "$2" "$PUSH_ERR" 2>/dev/null; then ok "$1"; else falha "$1 — '$2' no stderr: $(tr '\n' '|' < "$PUSH_ERR" 2>/dev/null)"; fi
}

# val_motivo <rev> — o motivo da validade sobre <rev> no cwd (ok quando vale)
val_motivo() {
  local out
  out="$(bash "$VALIDADE" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md --rev "$1" 2>/dev/null)"
  if [ "$(printf '%s\n' "$out" | sed -n 1p)" = ok=true ]; then printf 'ok\n'
  else printf '%s\n' "$out" | sed -n 's/^motivo=//p'; fi
}

# modo <dir> <bloqueio|aviso|desligado|-> — o .expx/hooks.json do cenário
# (fora do índice); `-` remove o arquivo
modo() {
  mkdir -p "$1/.expx"
  if [ "$2" = - ]; then rm -f "$1/.expx/hooks.json"
  else printf '{\n  "expx_hooks": 1,\n  "hooks": {\n    "pr-so-com-portao": { "modo": "%s" }\n  }\n}\n' "$2" > "$1/.expx/hooks.json"; fi
}

# produto <dir> <nome> — commit de produto (sem Metodo:)
produto() {
  ( cd "$1" && printf 'export const %s = 1;\n' "$2" > "src/$2.ts" && git add "src/$2.ts" && git commit -q -m "feat: $2" )
}

# entrega_commit <dir> <sed> [metodo] — reescreve o ENTREGA.md e commita (com
# Metodo: <metodo> e Trabalho: ft-rec quando dado)
entrega_commit() {
  ( cd "$1" || exit 1
    e=docs/entregas/ft-rec/ENTREGA.md
    sed "$2" "$e" > "$e.tmp" && cat "$e.tmp" > "$e" && rm -f "$e.tmp" && git add -- "$e" || exit 1
    if [ -n "${3:-}" ]; then git commit -q -m "docs(mergex): entrega" -m "Trabalho: ft-rec
Metodo: $3"
    else git commit -q -m "docs: entrega"; fi )
}

# ---------------------------------------------------------------------------
# Grupos
# ---------------------------------------------------------------------------

grupo_prepush() {
  local t d c v1 v2 v3 v4 v5 v6 v7 v8 v9 p1 p2 n1 n2 l out rc m pp2 conta o f
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  [ -r "$PP" ] || falha "portao-push.sh: No such file ($PP)"
  export FX_PORTAO_PUSH="$PP"
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_remoto_bare "$d" || { falha "remoto bare não montou"; return; }
  case "$FX_REMOTO" in "$t"/*) ok "controle: o remoto é o bare local do temporário" ;; *) falha "remoto fora do temporário: $FX_REMOTO" ;; esac
  modo "$d" aviso
  cd "$d" || return

  # ---- pronto válido, vencido e o SHA enviado ---------------------------------
  fx_portao_em "$d" HEAD; v1="$(git rev-parse HEAD)"
  push_espera "pronto válido passa" 0 "$v1" "$d" origin feature/ft-rec
  err_sem "pronto válido: nenhum diagnóstico da barreira" "mergex pre-push"
  produto "$d" vencido1; p1="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = commit_de_produto ] && ok "controle: HEAD vencido por produto" || falha "controle: HEAD não venceu"
  push_espera "pronto vencido barra" 1 "$v1" "$d" origin feature/ft-rec
  err_tem "pronto vencido: diagnóstico cita commit_de_produto" "commit_de_produto"

  fx_portao_em "$d" HEAD; v2="$(git rev-parse HEAD)"
  produto "$d" vencido2; p2="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = commit_de_produto ] && [ "$(val_motivo "$v2")" = ok ] \
    && ok "controle: HEAD vencido e o commit anterior válido" || falha "controle: HEAD/v2"
  push_espera "push de commit anterior ao HEAD valida o SHA enviado (válido, HEAD vencido: passa)" 0 "$v2" "$d" origin "$v2:refs/heads/feature/ft-rec"
  fx_portao_em "$d" HEAD; v3="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = ok ] && ok "controle: HEAD válido de novo" || falha "controle: HEAD não ficou válido"
  push_espera "push de commit anterior ao HEAD valida o SHA enviado (vencido, HEAD válido: barra)" 1 "$v2" "$d" origin "$p2:refs/heads/feature/ft-rec"
  push_espera "controle: o HEAD válido passa" 0 "$v3" "$d" origin feature/ft-rec

  # ---- legado sem portao_sha ---------------------------------------------------
  fx_portao_sem_sha "$d"; l="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = portao_sha_ausente ] && ok "controle: pronto sem portao_sha" || falha "controle: legado"
  push_espera "pronto legado sem portao_sha barra" 1 "$v3" "$d" origin feature/ft-rec
  err_tem "pronto legado: instrução de rodar o E2 de novo" "rode o E2"
  fx_portao_em "$d" HEAD; v4="$(git rev-parse HEAD)"
  push_espera "controle: portão regravado passa" 0 "$v4" "$d" origin feature/ft-rec

  # ---- ENTREGA ausente e ilegível no SHA enviado (em modo desligado) ---------
  modo "$d" desligado
  git rm -q docs/entregas/ft-rec/ENTREGA.md && git commit -q -m "docs: remove a entrega"
  git cat-file -e "HEAD:docs/entregas/ft-rec/ENTREGA.md" 2>/dev/null && falha "controle: ENTREGA ainda no HEAD" || ok "controle: ENTREGA ausente no SHA enviado"
  push_espera "ENTREGA ausente no SHA enviado barra (aplicável pela ponta remota anterior)" 1 "$v4" "$d" origin feature/ft-rec
  git show "HEAD~1:docs/entregas/ft-rec/ENTREGA.md" > docs/entregas/ft-rec/ENTREGA.md
  fx_portao_em "$d" HEAD; v5="$(git rev-parse HEAD)"
  push_espera "controle: ENTREGA de volta passa" 0 "$v5" "$d" origin feature/ft-rec
  entrega_commit "$d" '1s/.*/--- quebrado/'
  [ "$(git show HEAD:docs/entregas/ft-rec/ENTREGA.md | sed -n 1p)" = "--- quebrado" ] && ok "controle: frontmatter quebrado no SHA enviado" || falha "controle: frontmatter"
  push_espera "ENTREGA ilegível barra" 1 "$v5" "$d" origin feature/ft-rec
  git show "HEAD~1:docs/entregas/ft-rec/ENTREGA.md" > docs/entregas/ft-rec/ENTREGA.md
  fx_portao_em "$d" HEAD; v6="$(git rev-parse HEAD)"
  push_espera "controle: ENTREGA legível passa" 0 "$v6" "$d" origin feature/ft-rec

  # ---- portao: null nos três modos ----------------------------------------------
  entrega_commit "$d" 's/^portao: .*/portao: null/' pre-e6; n1="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = portao_nao_pronto ] && ok "controle: portao null" || falha "controle: portao null"
  modo "$d" bloqueio
  push_espera "null nos três modos: bloqueio barra" 1 "$v6" "$d" origin feature/ft-rec
  err_tem "null em bloqueio: diagnóstico do portão não autorizado" "portao: null"
  modo "$d" desligado
  push_espera "null nos três modos: desligado passa" 0 "$n1" "$d" origin feature/ft-rec
  err_sem "null em desligado: sem diagnóstico" "mergex pre-push"
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/PR.md; n2="$(git rev-parse HEAD)"
  modo "$d" aviso
  push_espera "null nos três modos: aviso passa" 0 "$n2" "$d" origin feature/ft-rec
  err_tem "null em aviso: diagnóstico em stderr" "portao: null"

  # pr_modo_null: as formas do .expx/hooks.json
  ( . "$REGRAS" || exit 9
    r="$t/modos"; mkdir -p "$r/.expx"
    [ "$(pr_modo_null "$r")" = aviso ] || exit 1
    printf '{"expx_hooks":1,"hooks":{}}\n' > "$r/.expx/hooks.json"; [ "$(pr_modo_null "$r")" = aviso ] || exit 2
    for x in bloqueio aviso desligado; do
      printf '{"hooks":{"pr-so-com-portao":{"modo":"%s"}}}\n' "$x" > "$r/.expx/hooks.json"; [ "$(pr_modo_null "$r")" = "$x" ] || exit 3
    done
    printf '{"hooks":{"pr-so-com-portao":{"modo":"bloquear"}}}\n' > "$r/.expx/hooks.json"
    [ "$(pr_modo_null "$r")" = bloqueio ] || exit 4
    pr_modo_null "$r" >/dev/null && exit 5
    printf '{"hooks":{"pr-so-com-portao":{"modo":true}}}\n' > "$r/.expx/hooks.json"; [ "$(pr_modo_null "$r")" = bloqueio ] || exit 6
    printf '{"hooks": \n' > "$r/.expx/hooks.json"; [ "$(pr_modo_null "$r")" = bloqueio ] || exit 7
    : > "$r/.expx/hooks.json"; [ "$(pr_modo_null "$r")" = bloqueio ] || exit 8
    exit 0 ); rc=$?
  [ "$rc" = 0 ] && ok "pr_modo_null: sem arquivo ou sem a chave aviso; modo inválido, não texto, JSON quebrado ou vazio: bloqueio" \
    || falha "pr_modo_null — caso $rc"

  # ---- duas refs, a segunda inválida ---------------------------------------------
  fx_portao_em "$d" HEAD; v7="$(git rev-parse HEAD)"
  fixture_switch_exato feature/ft-dois -c feature/ft-dois
  mkdir -p docs/entregas/ft-dois
  sed -e 's/^trabalho_id: ft-rec$/trabalho_id: ft-dois/' -e 's#^branch: feature/ft-rec$#branch: feature/ft-dois#' -e '/^portao_sha:/d' \
    docs/entregas/ft-rec/ENTREGA.md > docs/entregas/ft-dois/ENTREGA.md
  git add docs/entregas/ft-dois/ENTREGA.md && git commit -q -m "docs: entrega ft-dois sem portao_sha"
  fixture_switch_exato feature/ft-rec feature/ft-rec
  [ "$(val_motivo HEAD)" = ok ] && ok "controle: a primeira ref (feature/ft-rec) é válida" || falha "controle: primeira ref"
  push_espera "duas refs, a segunda inválida, barra o push inteiro" 1 "$n2" "$d" origin feature/ft-rec feature/ft-dois
  FX_PUSH_REF=refs/heads/feature/ft-dois push_espera "duas refs: a segunda não chega ao remoto" 1 - "$d" origin feature/ft-rec feature/ft-dois
  push_espera "controle: a primeira ref sozinha passa" 0 "$v7" "$d" origin feature/ft-rec

  # ---- tag e ref fora da branch do trabalho -------------------------------------
  git tag fx-tag "$p2"
  FX_PUSH_REF=refs/tags/fx-tag push_espera "tag passa (mesmo num commit vencido)" 0 "$p2" "$d" origin fx-tag
  FX_PUSH_REF=refs/heads/outra push_espera "ref fora da branch do trabalho passa" 0 "$p2" "$d" origin "$p2:refs/heads/outra"

  # ---- cd, bash -c e link simbólico: o pre-push decide ----------------------------
  produto "$d" vencido3
  [ "$(val_motivo HEAD)" = commit_de_produto ] && ok "controle: HEAD vencido" || falha "controle: HEAD vencido3"
  _fx_pre_push_minimo "$d" "$PP" || falha "chamador mínimo"
  ( cd "$d/src" && git push -q origin feature/ft-rec ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && [ "$(git ls-remote origin refs/heads/feature/ft-rec | cut -f1)" = "$v7" ] \
    && ok "push com cd para um subdiretório é decidido pelo pre-push (barra)" || falha "push com cd: rc=$rc"
  bash -c 'git -C "$1" push -q origin feature/ft-rec' _ "$d" >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && [ "$(git ls-remote origin refs/heads/feature/ft-rec | cut -f1)" = "$v7" ] \
    && ok "push com bash -c é decidido pelo pre-push (barra)" || falha "push com bash -c: rc=$rc"
  ln -s "$d" "$t/link"
  ( cd "$t/link" && git push -q origin feature/ft-rec ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && [ "$(git ls-remote origin refs/heads/feature/ft-rec | cut -f1)" = "$v7" ] \
    && ok "push por link simbólico é decidido pelo pre-push (barra)" || falha "push por link: rc=$rc"

  # ---- objeto ausente (cópia do cenário, remoto novo) -----------------------------
  fx_portao_em "$d" HEAD; v8="$(git rev-parse HEAD)"
  o="$(git rev-parse HEAD~1)"
  mkdir -p "$t/obj"; cp -a "$d" "$t/obj/repo"
  f="$t/obj/repo/.git/objects/$(printf '%s' "$o" | cut -c1-2)/$(printf '%s' "$o" | cut -c3-)"
  [ -f "$f" ] && ok "controle: o objeto do portao_sha é solto na cópia" || falha "controle: objeto do portao_sha não é solto"
  rm -f "$f"
  ( cd "$t/obj/repo" && fx_remoto_bare "$t/obj/repo" && \
    out="$(fx_push_real "$t/obj/repo" origin feature/ft-rec)" && printf '%s\n' "$out" ) > "$t/obj/saida" 2>/dev/null
  PUSH_ERR="$(sed -n 's/^stderr=//p' "$t/obj/saida")"
  [ "$(sed -n 's/^rc=//p' "$t/obj/saida")" = 1 ] && [ "$(sed -n 's/^ref=//p' "$t/obj/saida")" = - ] \
    && ok "objeto ausente é historia_incompleta: push barrado" || falha "objeto ausente: $(tr '\n' '|' < "$t/obj/saida")"
  err_tem "objeto ausente: diagnóstico historia_incompleta" "historia_incompleta"
  err_tem "objeto ausente: diagnóstico indica buscar os objetos" "busque os objetos que faltam"
  cp "$PUSH_ERR" "$t/err-historia"

  # ---- validador ausente ----------------------------------------------------------
  mkdir -p "$t/sem-validade"; cp "$S"/*.sh "$t/sem-validade/"; rm -f "$t/sem-validade/validade-do-portao.sh"
  FX_PORTAO_PUSH="$t/sem-validade/portao-push.sh" push_espera "validador ausente é erro_ambiente e barra" 1 "$v7" "$d" origin feature/ft-rec
  err_tem "validador ausente: diagnóstico erro_ambiente" "erro_ambiente"
  err_tem "validador ausente: diagnóstico de ambiente" "erro de ambiente"
  cp "$PUSH_ERR" "$t/err-ambiente"
  ! grep -Fq "erro de ambiente" "$t/err-historia" && ! grep -Fq "unshallow" "$t/err-ambiente" \
    && ! grep -Fq "busque os objetos" "$t/err-ambiente" \
    && ok "historia_incompleta e erro_ambiente com diagnósticos distintos" || falha "diagnósticos não distintos"

  # ---- custo: 50 branches entregues, uma ref no push ---------------------------------
  for i in $(seq 1 50); do
    GIT_INDEX_FILE="$t/idx" git read-tree HEAD
    sed -e "s/^trabalho_id: ft-rec\$/trabalho_id: ft-c$i/" -e "s#^branch: feature/ft-rec\$#branch: feature/ft-c$i#" \
      docs/entregas/ft-rec/ENTREGA.md | git hash-object -w --stdin > "$t/blob"
    GIT_INDEX_FILE="$t/idx" git update-index --add --cacheinfo "100644,$(cat "$t/blob"),docs/entregas/ft-c$i/ENTREGA.md"
    c="$(git commit-tree "$(GIT_INDEX_FILE="$t/idx" git write-tree)" -p HEAD -m "docs: entrega ft-c$i")"
    git update-ref "refs/heads/feature/ft-c$i" "$c"
  done
  rm -f "$t/idx" "$t/blob"
  [ "$(git for-each-ref refs/heads/feature/ft-c* | wc -l | tr -d ' ')" = 50 ] && ok "controle: 50 branches locais com ENTREGA.md próprio" || falha "controle: 50 branches"
  mkdir -p "$t/stub"; cp "$S"/*.sh "$t/stub/"; mv "$t/stub/validade-do-portao.sh" "$t/stub/validade-real.sh"
  conta="$t/chamadas"; : > "$conta"
  printf '#!/usr/bin/env bash\nprintf "chamada\\n" >> %q\nexec bash "$(dirname "$0")/validade-real.sh" "$@"\n' "$conta" > "$t/stub/validade-do-portao.sh"
  FX_PORTAO_PUSH="$t/stub/portao-push.sh" push_espera "custo: o push de uma ref válida passa" 0 "$v8" "$d" origin feature/ft-rec
  n="$(wc -l < "$conta" | tr -d ' ')"
  [ "$n" -le 1 ] && [ "$n" -ge 1 ] && ok "custo independe das branches entregues (1 chamada da validade com 50 branches)" \
    || falha "custo: $n chamadas da validade para uma ref"

  # ---- o validador de push direto: sinal, linhas e uso ------------------------------
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/QA-PACOTE.md; v9="$(git rev-parse HEAD)"
  ( cd "$t/link" && git push -q origin feature/ft-rec ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(git ls-remote origin refs/heads/feature/ft-rec | cut -f1)" = "$v9" ] \
    && ok "push por link simbólico com o SHA válido passa (o resultado é o da validade)" || falha "push por link válido: rc=$rc"
  printf 'refs/heads/feature/ft-rec %s refs/heads/feature/ft-rec %s\n' "$p2" "$v9" > "$t/linha"
  bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha" >/dev/null 2>&1; rc=$?
  MERGEX_PRE_PUSH_SINAL="$t/sinal" bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha" >/dev/null 2>&1
  [ "$?" = "$rc" ] && [ "$rc" = 1 ] && grep -Eq '^mergex-pre-push invocado [0-9]+$' "$t/sinal" \
    && ok "MERGEX_PRE_PUSH_SINAL só acrescenta o sinal, sem mudar a decisão" || falha "sinal: rc=$rc $(cat "$t/sinal" 2>/dev/null)"
  printf 'refs/heads/feature/ft-rec %s refs/heads/feature/ft-rec\n' "$v9" > "$t/linha"
  rc_igual "linha do protocolo malformada barra" 1 bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha"
  : > "$t/linha"
  rc_igual "entrada vazia libera" 0 bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha"
  rc_igual "sem argumentos: uso" 64 bash "$PP"
  rc_igual "sem a url: uso" 64 bash "$PP" --pre-push origin < "$t/linha"
  rc_igual "opção desconhecida: uso" 64 bash "$PP" --pre-push origin "$FX_REMOTO" --sem-prova < "$t/linha"

  # ---- clone raso -------------------------------------------------------------------
  cd "$t" || return
  git clone -q --depth 1 -b feature/ft-rec "file://$FX_REMOTO" "$t/raso" 2>/dev/null || falha "clone --depth 1"
  git -C "$t/raso" config user.email teste@expx.local; git -C "$t/raso" config user.name "Teste Expx"
  git -C "$t/raso" config commit.gpgsign false
  [ "$(git -C "$t/raso" rev-parse --is-shallow-repository)" = true ] && ok "controle: clone --depth 1 é raso" || falha "controle: clone não é raso"
  fx_commit_metodo "$t/raso" pre-e6 docs/entregas/ft-rec/PR.md || falha "commit no clone raso"
  push_espera "clone raso barra com historia_incompleta" 1 "$v9" "$t/raso" origin feature/ft-rec
  err_tem "clone raso: diagnóstico historia_incompleta" "historia_incompleta"
  err_tem "clone raso: diagnóstico indica git fetch --unshallow" "git fetch --unshallow"

  # ---- exclusão de branch (com HEAD vencido) -------------------------------------------
  cd "$d" || return
  produto "$d" vencido4
  push_espera "exclusão de branch passa" 0 - "$d" origin :feature/ft-rec
  cd "$REPO" || return

  # ---- reconciliação e ordem ---------------------------------------------------------------
  local t2 d2 b e ar
  t2="$(mktemp -d)"; TMPS="$TMPS $t2"; d2="$t2/repo"
  fx_cenario "$d2" || { falha "cenário de reconciliação não montou"; return; }
  fx_remoto_bare "$d2" || { falha "remoto bare (reconciliação)"; return; }
  cd "$d2" || return
  e="$FX_ENTREGA"; ar=docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  b=(bash "$RB" --verificar --checkpoint reconciliacao-base --entrega "$e" --origem sprintx --trabalho ft-rec)
  bash "$RB" --registrar --entrega "$e" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 \
    || falha "registro da reconciliação"
  out="$("${b[@]}" 2>/dev/null)"; rc=$?
  [ "$rc" = 5 ] && printf '%s\n' "$out" | grep -Fxq "motivo	persistencia	$e" \
    && ok "barreira: reconciliação registrada e não persistida dá persistencia (rc 5)" || falha "barreira não persistida: rc=$rc $(printf '%s' "$out" | tr '\n\t' '|>')"
  bash "$PERSISTE" --persistir --entrega "$e" --origem sprintx --trabalho ft-rec --checkpoint reconciliacao-base >/dev/null 2>&1 \
    || falha "persistir-metodo reconciliacao-base"
  rc_igual "barreira: depois do checkpoint reconciliacao-base, rc 0" 0 "${b[@]}"
  [ "$(git show "HEAD:$e" | sed -n 's/^portao: //p')" = null ] && ok "controle: a reconciliação devolveu o portão a null" || falha "controle: portão depois da reconciliação"
  m="$(git rev-parse HEAD)"
  modo "$d2" bloqueio
  push_espera "ordem: sem portão pronto o push segue o modo (bloqueio barra)" 1 - "$d2" origin feature/ft-rec
  modo "$d2" aviso
  push_espera "ordem: sem portão pronto o push segue o modo (aviso passa)" 0 "$m" "$d2" origin feature/ft-rec
  err_tem "ordem: aviso do portão não autorizado" "portao: null"

  fx_portao_em "$d2" HEAD; v1="$(git rev-parse HEAD)"
  push_espera "controle: portão depois da reconciliação passa" 0 "$v1" "$d2" origin feature/ft-rec
  fx_commit_metodo "$d2" reconciliacao-base "$e"
  [ "$(val_motivo HEAD)" = commit_de_produto ] && ok "controle: reconciliacao-base depois do portão dá commit_de_produto" || falha "controle: $(val_motivo HEAD)"
  push_espera "ordem: commit reconciliacao-base depois do portão barra o push" 1 "$v1" "$d2" origin feature/ft-rec
  err_tem "ordem: diagnóstico commit_de_produto" "commit_de_produto"

  fx_portao_em "$d2" HEAD; v2="$(git rev-parse HEAD)"
  printf '\nadulterado no disco\n' >> "$ar"
  printf 'artefato solto\n' > docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  "${b[@]}" >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok "controle: a barreira da reconciliação reprova o disco adulterado (rc $rc)" || falha "controle: barreira aprovou o disco adulterado"
  push_espera "ordem: o pre-push não reexecuta a reconciliação" 0 "$v2" "$d2" origin feature/ft-rec
  cd "$REPO" || return
}

# ---------------------------------------------------------------------------
# Despacho
# ---------------------------------------------------------------------------

# Ordem de definição: lida do próprio arquivo (declare -F ordenaria por nome).
GRUPOS="$(sed -n 's/^grupo_\([a-z0-9_]*\)() {.*/\1/p' "${BASH_SOURCE[0]}" | tr '\n' ' ')"

[ "$#" -ge 1 ] || { echo "uso: $0 <grupo>... | todos" >&2; exit 64; }

SEL=""
for g in "$@"; do
  if [ "$g" = todos ]; then SEL="$SEL $GRUPOS"
  else
    case " $GRUPOS " in
      *" $g "*) SEL="$SEL $g" ;;
      *) echo "grupo desconhecido: $g (grupos: $GRUPOS)" >&2; exit 64 ;;
    esac
  fi
done

for g in $SEL; do
  echo "== $g"
  "grupo_$g"
  cd "$REPO" || exit 1
done

echo
echo "$OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ]
