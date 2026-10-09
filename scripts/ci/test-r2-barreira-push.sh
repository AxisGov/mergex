#!/usr/bin/env bash
#
# Bancada da barreira de push (R2, DM-184).
#
# O pre-push do Git decide só pelo que o Git entrega (refs e SHAs), pela mesma
# regra (portao-regras.sh -> validade-do-portao.sh --rev) e pelo mesmo modo
# (pr-so-com-portao em .expx/hooks.json). Grupos: `prepush` (Task 14),
# `ativacao` e `entrypoints` (Task 15); os de CI (16) e modo (17) entram
# depois, na ordem de definição. Caso que depende de um ambiente ausente (Git
# for Windows sobre \\wsl.localhost) imprime NAO_EXECUTADO e nunca conta como ok.
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
ATV="$S/ativacao-pre-push.sh"
REGISTRA="$S/registrar-portao.sh"
CAUSA="$S/causa-do-portao.sh"
ZERO=0000000000000000000000000000000000000000

OK=0; FALHOU=0; NAOEXEC=0
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

# _arvore_entregas <repo> <n> — commit (na branch atual) com n ENTREGA.md
# simples (docs/entregas/e<i>/ENTREGA.md, branch: feature/e<i>) e as variantes
# de leitura de `branch:` que catalogo_fm aceita ou recusa:
#   alvo     `branch: "feature/alvo"` com CRLF (casa)
#   esp      `branch: feature/esp` com espaços no fim, e `---  ` (casa)
#   base     só `branch_base: feature/alvo` (não casa)
#   corpo    `branch: feature/alvo` depois do frontmatter (não casa)
#   sem-fm   primeira linha não é `---` (não casa)
#   segunda  segunda chave `branch:` (só a primeira vale; não casa)
# Imprime o SHA do commit.
_arvore_entregas() {
  local r="$1" n="$2" i b
  ( cd "$r" || exit 1
    rm -f .git/fx-idx
    _e() { printf '%s' "$2" | git hash-object -w --stdin > .git/fx-blob \
      && GIT_INDEX_FILE=.git/fx-idx git update-index --add --cacheinfo "100644,$(cat .git/fx-blob),docs/entregas/$1/ENTREGA.md"; }
    i=1
    while [ "$i" -le "$n" ]; do
      _e "e$i" "$(printf -- '---\nkind: entrega\ntrabalho_id: e%s\nbranch: feature/e%s\nbranch_base: main\n---\n\n# Entrega\n' "$i" "$i")" || exit 1
      i=$((i + 1))
    done
    _e alvo "$(printf -- '---\r\nkind: entrega\r\nbranch: "feature/alvo"\r\n---\r\n')" || exit 1
    _e esp "$(printf -- '---  \nbranch: feature/esp   \n---\n')" || exit 1
    _e base "$(printf -- '---\nbranch_base: feature/alvo\n---\n')" || exit 1
    _e corpo "$(printf -- '---\nkind: entrega\n---\nbranch: feature/alvo\n')" || exit 1
    _e sem-fm "$(printf -- 'branch: feature/alvo\n---\n')" || exit 1
    _e segunda "$(printf -- '---\nbranch: feature/outra\nbranch: feature/alvo\n---\n')" || exit 1
    b="$(GIT_INDEX_FILE=.git/fx-idx git write-tree)" || exit 1
    rm -f .git/fx-idx .git/fx-blob
    git commit-tree "$b" -m "entregas: $n" )
}

# entregas_custo <tmp> — pr_entrega_da_ref com 2 e com 300 ENTREGA.md na
# árvore: o resultado é o mesmo, com a mesma quantidade de processos Git
# (contados por um git de mentira no PATH que registra cada chamada)
entregas_custo() {
  local t="$1" r="$1/muitas" real c2 c300 n2 n300 out2 out300 rc
  real="$(command -v git)"
  mkdir -p "$t/gitstub" && git init -q "$r" && git -C "$r" config user.email teste@expx.local && git -C "$r" config user.name "Teste Expx"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$t/git-chamadas" "$real" > "$t/gitstub/git"
  chmod +x "$t/gitstub/git"
  c2="$(_arvore_entregas "$r" 2)" && c300="$(_arvore_entregas "$r" 300)" || { falha "árvores de entregas não montaram"; return; }
  # roda pr_entrega_da_ref <ref> <sha> e imprime "<saída>|<rc>|<chamadas git>"
  _conta() {
    : > "$t/git-chamadas"
    ( PATH="$t/gitstub:$PATH"; . "$REGRAS" || exit 9; arvore_ambiente_git
      o="$(pr_entrega_da_ref "$r" "$1" "$2" "$ZERO")"; rc=$?
      printf '%s|%s|' "$o" "$rc" )
    wc -l < "$t/git-chamadas" | tr -d ' '
  }
  out2="$(_conta refs/heads/feature/alvo "$c2")"; out300="$(_conta refs/heads/feature/alvo "$c300")"
  n2="${out2##*|}"; n300="${out300##*|}"
  [ "${out300%|*}" = "docs/entregas/alvo/ENTREGA.md|0" ] && [ "${out2%|*}" = "docs/entregas/alvo/ENTREGA.md|0" ] \
    && ok "pr_entrega_da_ref com 300 ENTREGA.md: acha a entrega (aspas e CRLF)" || falha "pr_entrega_da_ref: 2 [$out2] 300 [$out300]"
  out300="$(_conta refs/heads/feature/esp "$c300")"
  [ "${out300%|*}" = "docs/entregas/esp/ENTREGA.md|0" ] && ok "pr_entrega_da_ref: espaços no fim do valor e do ---" || falha "esp: [$out300]"
  [ "$n300" = "$n2" ] && [ "$n300" -le 6 ] \
    && ok "custo independe das entregas na árvore ($n300 processos Git com 2 ou 300 ENTREGA.md)" || falha "custo: $n2 processos Git com 2 entregas, $n300 com 300"
  out300="$(_conta refs/heads/feature/e150 "$c300")"
  [ "${out300%|*}" = "docs/entregas/e150/ENTREGA.md|0" ] && ok "pr_entrega_da_ref: entrega comum no meio de 300" || falha "e150: [$out300]"
  out300="$(_conta refs/heads/feature/nenhuma "$c300")"
  [ "${out300%|*}" = "|0" ] && ok "pr_entrega_da_ref: branch que nenhuma entrega declara não é aplicável" || falha "nenhuma: [$out300]"
  out300="$(_conta refs/heads/main "$c300")"
  [ "${out300%|*}" = "|0" ] && ok "pr_entrega_da_ref: branch_base não casa com branch" || falha "main: [$out300]"
  out300="$(_conta refs/heads/feature/outra "$c300")"
  [ "${out300%|*}" = "docs/entregas/segunda/ENTREGA.md|0" ] && ok "pr_entrega_da_ref: só a primeira chave branch: vale" || falha "outra: [$out300]"
  # duas entregas declaram a mesma branch: falha fechada
  c2="$( cd "$r" && b="$(printf -- '---\nbranch: feature/e1\n---\n' | git hash-object -w --stdin)" \
    && GIT_INDEX_FILE=.git/fx-idx git read-tree "$c300" \
    && GIT_INDEX_FILE=.git/fx-idx git update-index --add --cacheinfo "100644,$b,docs/entregas/dup/ENTREGA.md" \
    && git commit-tree "$(GIT_INDEX_FILE=.git/fx-idx git write-tree)" -m dup; rm -f .git/fx-idx )"
  out2="$(_conta refs/heads/feature/e1 "$c2")"
  [ "${out2%|*}" = "|1" ] && ok "pr_entrega_da_ref: duas entregas declarando a mesma branch falham fechado" || falha "dup: [$out2]"
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

  # árvore de um commit do intervalo e blob do ENTREGA.md do SHA enviado (o
  # segundo falta já na leitura das entregas da ref, antes da validade)
  for x in arvore_intervalo blob_entrega; do
    mkdir -p "$t/obj-$x"; cp -a "$d" "$t/obj-$x/repo"
    case "$x" in
      arvore_intervalo)
        fx_commit_metodo "$t/obj-$x/repo" pre-e6 docs/entregas/ft-rec/PR.md || falha "commit de método na cópia"
        o="$(git rev-parse "$v8^{tree}")" ;;
      blob_entrega) o="$(git rev-parse "$v8:docs/entregas/ft-rec/ENTREGA.md")" ;;
    esac
    f="$t/obj-$x/repo/.git/objects/$(printf '%s' "$o" | cut -c1-2)/$(printf '%s' "$o" | cut -c3-)"
    [ -f "$f" ] && ok "controle: $x é objeto solto na cópia" || falha "controle: $x não é solto"
    rm -f "$f"
    ( cd "$t/obj-$x/repo" && fx_remoto_bare "$t/obj-$x/repo" && \
      out="$(fx_push_real "$t/obj-$x/repo" origin feature/ft-rec)" && printf '%s\n' "$out" ) > "$t/obj-$x/saida" 2>/dev/null
    PUSH_ERR="$(sed -n 's/^stderr=//p' "$t/obj-$x/saida")"
    [ "$(sed -n 's/^rc=//p' "$t/obj-$x/saida")" = 1 ] && [ "$(sed -n 's/^ref=//p' "$t/obj-$x/saida")" = - ] \
      && ok "objeto ausente que não é commit ($x): push barrado" || falha "objeto ausente ($x): $(tr '\n' '|' < "$t/obj-$x/saida")"
    err_tem "objeto ausente ($x): diagnóstico historia_incompleta" "historia_incompleta"
    err_tem "objeto ausente ($x): diagnóstico indica buscar os objetos" "busque os objetos que faltam"
    err_sem "objeto ausente ($x): não é erro de ambiente" "erro de ambiente"
  done

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

  # ---- caminho com caractere de controle sob docs/entregas: barra ---------------
  # commits montados por plumbing sobre v8, cada um com uma entrega num diretório
  # com TAB ou LF no nome, declarando branch: feature/ctrl (a única que a declara)
  local nome cc
  for x in tab lf; do
    case "$x" in tab) nome="$(printf 'tab\tx')" ;; lf) nome="$(printf 'lf\nx')" ;; esac
    cc="$( b="$(printf -- '---\nkind: entrega\ntrabalho_id: ctrl\nbranch: feature/ctrl\n---\n' | git hash-object -w --stdin)" \
      && GIT_INDEX_FILE="$t/idx-ctrl" git read-tree "$v8" \
      && GIT_INDEX_FILE="$t/idx-ctrl" git update-index --add --cacheinfo "100644,$b,docs/entregas/$nome/ENTREGA.md" \
      && git commit-tree "$(GIT_INDEX_FILE="$t/idx-ctrl" git write-tree)" -p "$v8" -m "docs: entrega com $x no caminho"; rm -f "$t/idx-ctrl" )"
    [ -n "$cc" ] && git cat-file -e "$cc:docs/entregas/$nome/ENTREGA.md" 2>/dev/null \
      && ok "controle: entrega com $x no caminho do diretório" || falha "controle: commit com $x não montou"
    FX_PUSH_REF=refs/heads/feature/ctrl push_espera "caminho com $x sob docs/entregas barra o push" 1 - "$d" origin "$cc:refs/heads/feature/ctrl"
    err_tem "caminho com $x: diagnóstico de caractere de controle" "caractere de controle"
  done
  FX_PUSH_REF=refs/heads/feature/ctrl push_espera "controle: a mesma ref sem o caminho com controle (não aplicável) passa" 0 "$v8" "$d" origin "$v8:refs/heads/feature/ctrl"

  # ---- custo: centenas de ENTREGA.md na árvore, processos Git constantes ------------
  entregas_custo "$t"

  # ---- o validador de push direto: sinal, linhas e uso ------------------------------
  fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/QA-PACOTE.md; v9="$(git rev-parse HEAD)"
  ( cd "$t/link" && git push -q origin feature/ft-rec ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(git ls-remote origin refs/heads/feature/ft-rec | cut -f1)" = "$v9" ] \
    && ok "push por link simbólico com o SHA válido passa (o resultado é o da validade)" || falha "push por link válido: rc=$rc"
  printf 'refs/heads/feature/ft-rec %s refs/heads/feature/ft-rec %s\n' "$p2" "$v9" > "$t/linha"
  bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha" >/dev/null 2>&1; rc=$?
  MERGEX_PRE_PUSH_SINAL="$t/sinal" bash "$PP" --pre-push origin "$FX_REMOTO" < "$t/linha" >/dev/null 2>&1
  [ "$?" = "$rc" ] && [ "$rc" = 1 ] && [ "$(cat "$t/sinal")" = "mergex-pre-push $p2 barra" ] \
    && ok "MERGEX_PRE_PUSH_SINAL só acrescenta o sinal (SHA avaliado e decisão), sem mudar a decisão" || falha "sinal: rc=$rc $(cat "$t/sinal" 2>/dev/null)"
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
# Ativação no E0 e prova funcional no E2 (Task 15)
# ---------------------------------------------------------------------------

nao_executado() { NAOEXEC=$((NAOEXEC+1)); printf '  NAO_EXECUTADO: %s\n' "$1"; }

# o diretório de hooks efetivo, pelo próprio Git
hooks_de() { git -C "$1" rev-parse --path-format=absolute --git-path hooks; }

# assinatura <arquivo> — conteúdo, modo e mtime (com nanossegundos quando há)
assinatura() {
  { sha256sum < "$1"; stat -c '%y %a %i' "$1" 2>/dev/null || stat -f '%Fm %p %i' "$1"; } | tr '\n' ' '
}

# atv <dir> <modo> [entrega] — roda ativacao-pre-push.sh a partir de <dir>;
# a saída (stdout e stderr) fica em ATV_OUT e o código em ATV_RC
ATV_OUT=""; ATV_RC=""
atv() {
  ATV_OUT="$(cd "$1" && bash "$ATV" "$2" --entrega "${3:-docs/entregas/ft-rec/ENTREGA.md}" 2>&1)"; ATV_RC=$?
}
atv_espera() { # <desc> <rc> <dir> <modo> [entrega]
  atv "$3" "$4" "${5:-}"
  if [ "$ATV_RC" = "$2" ]; then ok "$1"; else falha "$1 — rc=$ATV_RC (esperava $2): $(printf '%s' "$ATV_OUT" | tr '\n' '|')"; fi
}
out_tem() { # <desc> <texto fixo> — na última saída do ativacao
  case "$ATV_OUT" in *"$2"*) ok "$1" ;; *) falha "$1 — sem '$2' na saída: $(printf '%s' "$ATV_OUT" | tr '\n' '|')" ;; esac
}

# estado_git <dir> — tudo que a prova não pode mudar: refs locais e do remoto
# bare, HEAD, índice e árvore de trabalho
estado_git() {
  git -C "$1" for-each-ref --format='%(refname) %(objectname)'
  git -C "$1" rev-parse HEAD
  printf -- '-- remoto\n'
  git -C "$FX_REMOTO" for-each-ref --format='%(refname) %(objectname)'
  printf -- '-- índice\n'
  git -C "$1" ls-files -s | sha256sum
  git -C "$1" status --porcelain=v1 --untracked-files=all
}

# hook_direto <dir> <sinal> — executa o pre-push efetivo como controle, com
# MERGEX_PRE_PUSH_SINAL=<sinal> e uma linha de protocolo para o HEAD do
# cenário (portão vencido: a MergeX barra); imprime o código
hook_direto() {
  local h; h="$(git -C "$1" rev-parse HEAD)"
  printf 'refs/heads/feature/ft-rec %s refs/heads/feature/ft-rec %s\n' "$h" "$ZERO" > "$2.entrada"
  ( cd "$1" && MERGEX_PRE_PUSH_SINAL="$2" "$(hooks_de "$1")/pre-push" controle file:///dev/null < "$2.entrada" >/dev/null 2>&1 ); printf '%s\n' "$?"
}
# barrou_no_sinal <dir> <sinal> — a MergeX decidiu `barra` para o HEAD
barrou_no_sinal() { grep -Fxq "mergex-pre-push $(git -C "$1" rev-parse HEAD) barra" "$2"; }

COMPOSICAO='portao-push.sh --pre-push "$@"'

# gfw_unc <tmp> — o caso Git for Windows: cenário no WSL, diretório efetivo e
# prova pelo Git Bash do Windows sobre \\wsl.localhost\... (sem o ambiente:
# NAO_EXECUTADO, que não conta como ok)
gfw_unc() {
  local t="$1" gb="/mnt/c/Program Files/Git/bin/bash.exe" d w a out ef hk desc
  desc="git for windows: diretório efetivo sobre UNC"
  command -v wslpath >/dev/null 2>&1 || { nao_executado "$desc — git for windows indisponível (sem wslpath: fora do WSL)"; return; }
  [ -f "$gb" ] || { nao_executado "$desc — git for windows indisponível ($gb ausente)"; return; }
  "$gb" -c 'command -v git >/dev/null' >/dev/null 2>&1 \
    || { nao_executado "$desc — git for windows indisponível (o Git Bash não executa pelo interop do WSL)"; return; }
  d="$t/gfw/repo"
  fx_cenario "$d" || { falha "$desc — cenário não montou"; return; }
  w="$(wslpath -w "$d" | tr '\\' '/')"; a="$(wslpath -w "$ATV" | tr '\\' '/')"
  case "$w" in //*) ;; *) nao_executado "$desc — o cenário não tem caminho UNC ($w)"; return ;; esac
  cat > "$t/gfw/roda.sh" <<'EOF'
# Roda no Git Bash do Windows: <repositório UNC> <ativacao UNC> <modo>...
cd "$1" || { printf 'cd=falhou\n'; exit 90; }
# "dubious ownership" do Git for Windows sobre UNC: safe.directory só neste
# processo, num arquivo de config global TEMPORÁRIO (GIT_CONFIG_GLOBAL) — a
# config global do usuário não é lida nem escrita. Não basta GIT_CONFIG_COUNT:
# arvore_ambiente_git (portao-push, validade) o redefine para o ambiente fixo.
g="$(mktemp)" || exit 92
printf '[safe]\n\tdirectory = %%(prefix)/%s\n' "$1" > "$g"
export GIT_CONFIG_GLOBAL="$(cygpath -m "$g")"
printf 'uname=%s\n' "$(uname -s)"
printf 'git=%s\n' "$(git --version)"
printf 'efetivo=%s\n' "$(git rev-parse --path-format=absolute --git-path hooks)"
a="$2"; shift 2
s="$(mktemp)" || exit 91
for m in "$@"; do
  bash "$a" "$m" --entrega docs/entregas/ft-rec/ENTREGA.md > "$s" 2>&1; rc=$?
  sed "s/^/saida$m=/" "$s"; printf 'rc%s=%s\n' "$m" "$rc"
done
rm -f "$s" "$g"
EOF
  out="$("$gb" "$(wslpath -w "$t/gfw/roda.sh")" "$w" "$a" --instalar --provar 2>&1)"
  printf '%s\n' "$out" > "$t/gfw/saida"
  ef="$(printf '%s\n' "$out" | sed -n 's/^efetivo=//p')"
  hk="$d/.git/hooks/pre-push"
  case "$(printf '%s\n' "$out" | sed -n 's/^uname=//p')" in
    MINGW*|MSYS*) ok "controle: $desc — roda no Git Bash do Windows ($(printf '%s\n' "$out" | sed -n 's/^git=//p'))" ;;
    *) falha "$desc — não rodou no Git Bash: $(tr '\n' '|' < "$t/gfw/saida")"; return ;;
  esac
  [ "$ef" = "$w/.git/hooks" ] && ok "$desc: o Git for Windows resolve o diretório efetivo pelo caminho UNC ($ef)" \
    || falha "$desc — efetivo=$ef (esperava $w/.git/hooks)"
  [ "$(printf '%s\n' "$out" | sed -n 's/^rc--instalar=//p')" = 0 ] && [ -f "$hk" ] && grep -Fxq '# mergex: pre-push gerenciado' "$hk" \
    && ok "$desc: --instalar pelo Git Bash grava o chamador no diretório comum do WSL" || falha "$desc — instalar: $(tr '\n' '|' < "$t/gfw/saida")"
  [ "$(printf '%s\n' "$out" | sed -n 's/^rc--provar=//p')" = 0 ] \
    && ok "$desc: --provar pelo Git Bash aprova" || falha "$desc — provar: $(tr '\n' '|' < "$t/gfw/saida")"
  [ -z "$(git -C "$d" config --get-all core.hooksPath)" ] && ok "$desc: core.hooksPath intocado" || falha "$desc — core.hooksPath gravado"
  # controle negativo: sem o hook, a mesma prova pelo Git Bash reprova
  rm -f "$hk"
  out="$("$gb" "$(wslpath -w "$t/gfw/roda.sh")" "$w" "$a" --provar 2>&1)"
  printf '%s\n' "$out" >> "$t/gfw/saida"
  [ "$(printf '%s\n' "$out" | sed -n 's/^rc--provar=//p')" = 1 ] \
    && ok "$desc: sem o pre-push, --provar pelo Git Bash reprova" || falha "$desc — provar sem hook: $(printf '%s' "$out" | tr '\n' '|')"
  [ -z "${MERGEX_GFW_SAIDA:-}" ] || cp "$t/gfw/saida" "$MERGEX_GFW_SAIDA"
}

# orcamento_caso <tmp> <dir> <rótulo> [variante] — o hook `lento` (ou
# `ignora_term`, que só morre com o KILL) chama a MergeX e dorme; com PRAZO=3
# numa cópia dos scripts, a prova reprova por estouro (a mensagem é a do
# orçamento, nunca a de término por sinal), rápido, e não deixa o
# `sleep 3077` do hook órfão
orcamento_caso() {
  local t="$1" d="$2" r="$3" v="${4:-lento}" c="$1/prazo" ini fim rc out n
  rm -rf "$c"; mkdir -p "$c" && cp -R "$S" "$c/scripts" || { falha "cópia dos scripts ($r)"; return; }
  sed 's/^PRAZO=120$/PRAZO=3/' "$S/ativacao-pre-push.sh" > "$c/scripts/ativacao-pre-push.sh"
  grep -Fxq 'PRAZO=3' "$c/scripts/ativacao-pre-push.sh" && ok "controle ($r): a cópia tem PRAZO=3" || { falha "controle ($r): PRAZO não reduzido"; return; }
  fx_hook_terceiro "$d" "$v" || { falha "hook $v"; return; }
  ini="$(date +%s)"
  out="$(cd "$d" && bash "$c/scripts/ativacao-pre-push.sh" --provar --entrega docs/entregas/ft-rec/ENTREGA.md 2>&1)"; rc=$?
  fim="$(date +%s)"
  [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -Fq 'orçamento' && ! printf '%s\n' "$out" | grep -Fq 'terminou por sinal' \
    && [ $((fim - ini)) -lt 30 ] \
    && ok "estouro do prazo reprova ($r; $((fim - ini))s)" || falha "estouro ($r): rc=$rc $((fim - ini))s $(printf '%s' "$out" | tr '\n' '|')"
  n=0; while [ "$n" -lt 10 ] && pgrep -f '^sleep 3077$' >/dev/null 2>&1; do sleep 1; n=$((n + 1)); done
  if pgrep -f '^sleep 3077$' >/dev/null 2>&1; then
    falha "estouro ($r): processo órfão do hook ($(pgrep -af '^sleep 3077$' | tr '\n' '|'))"; pkill -f '^sleep 3077$'
  else ok "estouro do prazo ($r): nenhum processo órfão do hook"; fi
  rm -rf "$c"
}

grupo_ativacao() {
  local t d h hk a1 lista1 lista2 antes depois cfg esp abs rc n
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  [ -r "$ATV" ] || falha "ativacao-pre-push.sh: No such file ($ATV)"
  export FX_PORTAO_PUSH="$PP"
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_remoto_bare "$d" || { falha "remoto bare não montou"; return; }
  git -C "$d" push -q origin feature/ft-rec main >/dev/null 2>&1 \
    && [ -n "$(git -C "$FX_REMOTO" for-each-ref)" ] && ok "controle: o remoto bare tem as refs do cenário" || falha "controle: push inicial ao bare"
  h="$(hooks_de "$d")"; hk="$h/pre-push"
  [ "$h" = "$d/.git/hooks" ] && [ ! -e "$hk" ] && [ -z "$(git -C "$d" config --get-all core.hooksPath)" ] \
    && ok "controle: sem pre-push e sem core.hooksPath" || falha "controle: estado inicial dos hooks ($h)"

  # ---- instalação e idempotência ------------------------------------------------
  lista1="$(ls -A "$h" | grep -vx pre-push)"
  atv_espera "instala sem pre-push (E0 sai 0)" 0 "$d" --instalar
  [ -f "$hk" ] && [ -x "$hk" ] && grep -Fxq '# mergex: pre-push gerenciado' "$hk" \
    && ok "instala o chamador gerenciado, executável e com o marcador" || falha "chamador gerenciado não instalado em $hk"
  a1="$(assinatura "$hk")"
  sleep 1
  atv_espera "instala sem pre-push e é idempotente (segunda execução sai 0)" 0 "$d" --instalar
  [ -f "$hk" ] && [ "$(assinatura "$hk")" = "$a1" ] && ok "instala sem pre-push e é idempotente (hash e mtime iguais)" \
    || falha "segunda instalação mudou o arquivo: $a1 / $(assinatura "$hk")"
  [ -z "$(git -C "$d" config --get-all core.hooksPath)" ] && ok "instalar não grava core.hooksPath" || falha "core.hooksPath gravado"

  # ---- a prova não toca remoto nem refs --------------------------------------------
  antes="$(estado_git "$d")"
  atv_espera "prova com o chamador gerenciado aprova" 0 "$d" --provar
  depois="$(estado_git "$d")"
  [ "$antes" = "$depois" ] && ok "prova funcional não toca remoto nem refs (refs, remoto bare, índice e árvore iguais)" \
    || falha "prova mudou o estado: $(diff <(printf '%s\n' "$antes") <(printf '%s\n' "$depois") | tr '\n' '|')"
  ( cd "$d/src" && bash "$ATV" --provar --entrega docs/entregas/ft-rec/ENTREGA.md >/dev/null 2>&1 ); rc=$?
  [ "$rc" = 0 ] && ok "prova a partir de um subdiretório aprova (a entrega é relativa à raiz)" || falha "prova do subdiretório: rc=$rc"

  # ---- reversão e E2 sem prova ---------------------------------------------------------
  [ -f "$hk" ] || falha "controle: o chamador gerenciado existe antes da reversão"
  atv_espera "reversão do chamador gerenciado sai 0" 0 "$d" --reverter
  lista2="$(ls -A "$h" | grep -vx pre-push)"
  [ ! -e "$hk" ] && [ "$lista1" = "$lista2" ] && ok "reversão remove só o chamador gerenciado" || falha "reversão: hook ainda presente ou outro arquivo mudou"
  atv_espera "E2 sem prova aprovada não emite PRONTO (--provar sai 1 sem o pre-push)" 1 "$d" --provar
  atv_espera "reversão sem pre-push sai 0" 0 "$d" --reverter

  # ---- hook de terceiro não composto --------------------------------------------------
  fx_hook_terceiro "$d" nao_composto || falha "hook de terceiro (nao_composto)"
  a1="$(assinatura "$hk")"
  sleep 1
  atv_espera "hook de terceiro não composto: E0 sai 3" 3 "$d" --instalar
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook de terceiro não composto: E0 não toca o arquivo (hash e mtime)" || falha "E0 tocou o hook de terceiro"
  out_tem "hook de terceiro não composto: a mensagem traz a instrução de composição" "$COMPOSICAO"
  out_tem "hook de terceiro não composto: parada mergex E0 BLOQUEADO — pre-push" "mergex E0 BLOQUEADO — pre-push"
  atv_espera "hook de terceiro não composto reprova na prova" 1 "$d" --provar
  atv_espera "reversão diante de hook de terceiro sai 0" 0 "$d" --reverter
  [ "$(assinatura "$hk")" = "$a1" ] && ok "reversão preserva hook de terceiro" || falha "reversão tocou o hook de terceiro"

  # ---- hook que só cita a MergeX ----------------------------------------------------------
  fx_hook_terceiro "$d" so_cita || falha "hook de terceiro (so_cita)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  grep -Fq "$PP" "$hk" && [ "$rc" = 1 ] && [ ! -s "$t/sinal" ] \
    && ok "controle: o hook cita o validador, sai 1 sozinho e não dá o sinal" || falha "controle so_cita: rc=$rc"
  atv_espera "hook que só cita a MergeX reprova" 1 "$d" --provar
  a1="$(assinatura "$hk")"
  atv_espera "hook que só cita a MergeX: E0 sai 3" 3 "$d" --instalar
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook que só cita a MergeX: E0 não toca o arquivo" || falha "E0 tocou o hook so_cita"

  # ---- hooks compostos que reprovam ----------------------------------------------------------
  fx_hook_terceiro "$d" nao_propaga || falha "hook de terceiro (nao_propaga)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" = 0 ] && barrou_no_sinal "$d" "$t/sinal" \
    && ok "controle: o hook que não propaga chama a MergeX (ela barra) e sai 0" || falha "controle nao_propaga: rc=$rc"
  atv_espera "hook composto que não propaga o código reprova" 1 "$d" --provar
  fx_hook_terceiro "$d" libera || falha "hook de terceiro (libera)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" = 0 ] && [ ! -s "$t/sinal" ] \
    && ok "controle: o hook que libera chama a MergeX sem a entrada (nenhuma ref decidida) e sai 0" || falha "controle libera: rc=$rc"
  atv_espera "hook composto que libera a ref inválida reprova" 1 "$d" --provar
  fx_hook_terceiro "$d" sinal || falha "hook de terceiro (sinal)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" -ge 128 ] && barrou_no_sinal "$d" "$t/sinal" \
    && ok "controle: o hook que termina por sinal chama a MergeX (ela barra) e morre (rc $rc)" || falha "controle sinal: rc=$rc"
  atv_espera "hook que termina por sinal reprova" 1 "$d" --provar
  a1="$(assinatura "$hk")"
  atv_espera "hook que termina por sinal: E0 sai 3" 3 "$d" --instalar
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook que termina por sinal: E0 não toca o arquivo" || falha "E0 tocou o hook sinal"

  # ---- sinal forjado e validador sem a entrada (correção 1) ----------------------------------
  fx_hook_terceiro "$d" ecoa_sinal || falha "hook de terceiro (ecoa_sinal)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" = 1 ] && ! grep -Fq "$PP" "$hk" && grep -Fxq 'mergex-pre-push invocado 1' "$t/sinal" \
    && grep -Eq '^mergex-pre-push [0-9a-f]{40} barra$' "$t/sinal" \
    && ok "controle: o hook que forja o sinal (sem citar o validador) escreve a linha antiga e uma barra com SHA arbitrário, e sai 1" \
    || falha "controle ecoa_sinal: rc=$rc"
  atv_espera "hook que forja o sinal (sem executar a MergeX) reprova" 1 "$d" --provar
  a1="$(assinatura "$hk")"
  atv_espera "hook que forja o sinal: E0 sai 3" 3 "$d" --instalar
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook que forja o sinal: E0 não toca o arquivo" || falha "E0 tocou o hook ecoa_sinal"
  fx_hook_terceiro "$d" sem_entrada || falha "hook de terceiro (sem_entrada)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" = 1 ] && [ ! -s "$t/sinal" ] \
    && ok "controle: o hook que chama a MergeX sem a entrada sai 1 sozinho, sem decisão" || falha "controle sem_entrada: rc=$rc"
  atv_espera "hook que chama a MergeX sem a entrada e sai 1 reprova" 1 "$d" --provar
  atv_espera "hook que chama a MergeX sem a entrada: E0 sai 3" 3 "$d" --instalar

  # ---- orçamento de tempo (correção 1): cópia dos scripts com o prazo reduzido ------------
  orcamento_caso "$t" "$d" "timeout disponível"
  mkdir -p "$t/sem-timeout"
  printf '#!/bin/sh\n# timeout que não mata nada: a detecção pelo comportamento o recusa\nexit 0\n' > "$t/sem-timeout/timeout"
  chmod 755 "$t/sem-timeout/timeout"
  PATH="$t/sem-timeout:$PATH" orcamento_caso "$t" "$d" "vigia em Bash, sem timeout que funcione"
  orcamento_caso "$t" "$d" "timeout disponível, hook que ignora TERM" ignora_term
  PATH="$t/sem-timeout:$PATH" orcamento_caso "$t" "$d" "vigia em Bash, hook que ignora TERM" ignora_term

  # ---- dois lados (correção 2): regra própria e validador que barra tudo -----------------
  fx_hook_terceiro "$d" regra_propria || falha "hook de terceiro (regra_propria)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  [ "$rc" = 1 ] && barrou_no_sinal "$d" "$t/sinal" \
    && ok "controle: o hook de regra própria chama a MergeX (ela barra) e sai 1 pela URL" || falha "controle regra_propria: rc=$rc"
  atv_espera "hook que não propaga o código (regra própria pela URL) reprova" 1 "$d" --provar
  out_tem "regra própria: reprovado pelo controle positivo" "controle positivo"
  a1="$(assinatura "$hk")"
  atv_espera "hook de regra própria: E0 sai 3" 3 "$d" --instalar
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook de regra própria: E0 não toca o arquivo" || falha "E0 tocou o hook regra_propria"
  fx_hook_terceiro "$d" sempre_barra || falha "hook de terceiro (sempre_barra)"
  rm -f "$t/sinal"; rc="$(hook_direto "$d" "$t/sinal")"
  printf 'refs/heads/livre-controle %s refs/heads/livre-controle %s\n' "$(git -C "$d" rev-parse HEAD)" "$ZERO" > "$t/livre"
  ( cd "$d" && MERGEX_PRE_PUSH_SINAL="$t/sinal-livre" "$hk" controle file:///dev/null < "$t/livre" >/dev/null 2>&1 ); n="$?"
  [ "$rc" = 1 ] && barrou_no_sinal "$d" "$t/sinal" && [ "$n" = 1 ] \
    && grep -Fxq "mergex-pre-push $(git -C "$d" rev-parse HEAD) barra" "$t/sinal-livre" \
    && ok "controle: no ambiente do hook sempre_barra a MergeX barra até a ref não aplicável" || falha "controle sempre_barra: rc=$rc livre=$n"
  rm -f "$t/sinal-livre" "$t/livre"
  atv_espera "hook num ambiente em que a MergeX barra tudo reprova" 1 "$d" --provar
  out_tem "sempre barra: reprovado pelo controle positivo" "controle positivo"
  atv_espera "hook num ambiente em que a MergeX barra tudo: E0 sai 3" 3 "$d" --instalar

  # ---- hook de terceiro composto --------------------------------------------------------------
  fx_hook_terceiro "$d" composto || falha "hook de terceiro (composto)"
  a1="$(assinatura "$hk")"
  sleep 1
  atv_espera "hook de terceiro composto passa na prova" 0 "$d" --provar
  atv_espera "hook de terceiro composto: E0 sai 0" 0 "$d" --instalar
  out_tem "hook de terceiro composto: reconhecido como integração externa válida" "integração externa válida"
  [ "$(assinatura "$hk")" = "$a1" ] && ok "hook de terceiro composto: E0 não toca o arquivo" || falha "E0 tocou o hook composto"
  atv_espera "reversão diante de integração externa sai 0" 0 "$d" --reverter
  [ "$(assinatura "$hk")" = "$a1" ] && ok "reversão preserva a integração externa" || falha "reversão tocou a integração externa"
  out_tem "reversão informa que a integração externa é removida pelo responsável" "integração externa"
  rm -f "$hk"

  # ---- core.hooksPath já configurado: relativo e absoluto ---------------------------------------
  mkdir -p "$d/.githooks-fx"
  git -C "$d" config core.hooksPath .githooks-fx; cfg="$(git -C "$d" config --get-all core.hooksPath)"
  [ "$(hooks_de "$d")" = "$d/.githooks-fx" ] && ok "controle: core.hooksPath relativo resolve na raiz" || falha "controle: hooksPath relativo ($(hooks_de "$d"))"
  atv_espera "core.hooksPath relativo: E0 sai 0" 0 "$d" --instalar
  [ -f "$d/.githooks-fx/pre-push" ] && [ ! -e "$hk" ] && [ "$(git -C "$d" config --get-all core.hooksPath)" = "$cfg" ] \
    && ok "core.hooksPath já configurado é respeitado e não muda (relativo)" || falha "hooksPath relativo: instalação fora do efetivo ou config mudou"
  atv_espera "core.hooksPath relativo: a prova aprova" 0 "$d" --provar
  ( cd "$d/src" && bash "$ATV" --provar --entrega docs/entregas/ft-rec/ENTREGA.md >/dev/null 2>&1 ); rc=$?
  [ "$rc" = 0 ] && ok "core.hooksPath relativo: a prova a partir de um subdiretório aprova" || falha "hooksPath relativo do subdiretório: rc=$rc"
  atv_espera "core.hooksPath relativo: reversão sai 0" 0 "$d" --reverter
  [ ! -e "$d/.githooks-fx/pre-push" ] && [ "$(git -C "$d" config --get-all core.hooksPath)" = "$cfg" ] \
    && ok "core.hooksPath relativo: reversão remove o gerenciado e não muda a config" || falha "hooksPath relativo: reversão"
  rmdir "$d/.githooks-fx"
  abs="$t/hooks absolutos"
  git -C "$d" config core.hooksPath "$abs"; cfg="$(git -C "$d" config --get-all core.hooksPath)"
  atv_espera "core.hooksPath absoluto: E0 sai 0" 0 "$d" --instalar
  [ -f "$abs/pre-push" ] && [ ! -e "$hk" ] && [ "$(git -C "$d" config --get-all core.hooksPath)" = "$cfg" ] \
    && ok "core.hooksPath já configurado é respeitado e não muda (absoluto)" || falha "hooksPath absoluto: instalação fora do efetivo ou config mudou"
  atv_espera "core.hooksPath absoluto: a prova aprova" 0 "$d" --provar
  atv_espera "core.hooksPath absoluto: reversão sai 0" 0 "$d" --reverter
  git -C "$d" config --unset core.hooksPath

  # ---- diretório com espaço, acento e apóstrofo ----------------------------------------------------
  esp="$t/raiz com espaço e ação d'água"
  fx_cenario "$esp/repo" || falha "cenário com espaço e acento não montou"
  abs="$esp/hooks d'ação"
  git -C "$esp/repo" config core.hooksPath "$abs"; cfg="$(git -C "$esp/repo" config --get-all core.hooksPath)"
  atv_espera "diretório com espaço e acento: E0 sai 0" 0 "$esp/repo" --instalar
  [ -f "$abs/pre-push" ] && [ "$(git -C "$esp/repo" config --get-all core.hooksPath)" = "$cfg" ] \
    && ok "diretório com espaço e acento: o chamador vai para o core.hooksPath configurado" || falha "espaço e acento: instalação"
  atv_espera "diretório com espaço e acento: a prova aprova" 0 "$esp/repo" --provar
  fx_hook_terceiro "$esp/repo" composto || falha "hook composto com espaço e acento"
  atv_espera "diretório com espaço e acento: hook de terceiro composto passa na prova" 0 "$esp/repo" --provar

  # ---- ativação em worktree vinculada -----------------------------------------------------------------
  fx_worktree_vinculada "$d" || { falha "worktree vinculada não montou"; return; }
  [ "$(hooks_de "$FX_WT")" = "$d/.git/hooks" ] && [ -f "$FX_WT/.git" ] \
    && ok "controle: na worktree vinculada (.git é arquivo) o diretório efetivo é o comum" || falha "controle worktree: $(hooks_de "$FX_WT")"
  atv_espera "ativação em worktree vinculada: E0 sai 0" 0 "$FX_WT" --instalar
  [ -f "$hk" ] && grep -Fxq '# mergex: pre-push gerenciado' "$hk" \
    && [ ! -e "$(git -C "$FX_WT" rev-parse --absolute-git-dir)/hooks/pre-push" ] \
    && ok "ativação em worktree vinculada (o diretório efetivo é o comum)" || falha "worktree: chamador fora do diretório comum"
  atv_espera "ativação em worktree vinculada: a prova aprova" 0 "$FX_WT" --provar

  # ---- Git for Windows sobre \\wsl.localhost ---------------------------------------------------------
  gfw_unc "$t"
  cd "$REPO" || return
}

# registra <resultado> [falha...] — registrar-portao.sh no cwd sobre a entrega
# ft-rec; a saída fica em REG_OUT e o código em REG_RC
REG_OUT=""; REG_RC=""
registra() {
  local r="$1"; shift
  if [ "$#" -gt 0 ]; then
    REG_OUT="$(bash "$REGISTRA" --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec --resultado "$r" --falhas "$@" 2>&1)"
  else
    REG_OUT="$(bash "$REGISTRA" --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec --resultado "$r" 2>&1)"
  fi
  REG_RC=$?
}

# persiste <modo> <checkpoint> — persistir-metodo.sh no cwd; saída em PER_OUT
PER_OUT=""
persiste() {
  PER_OUT="$(bash "$PERSISTE" "$1" --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec --checkpoint "$2" 2>&1)"
}

# fm_e <chave> — a chave de topo do ENTREGA.md do disco
fm_e() { awk -v c="$1" 'NR>1&&/^---/{exit} index($0,c": ")==1{sub(/^[^:]*: */,"");print;exit}' docs/entregas/ft-rec/ENTREGA.md; }

# edita_e <sed> — reescreve o ENTREGA.md do disco (fora do índice)
edita_e() {
  local e=docs/entregas/ft-rec/ENTREGA.md
  sed "$1" "$e" > "$e.tmp" && cat "$e.tmp" > "$e" && rm -f "$e.tmp"
}

# sem_pronto <desc> <tmp> — registrar-portao --resultado pronto barrado: rc 3,
# a saída não tem RESULTADO: PRONTO e tem o bloqueio, e o ENTREGA.md fica byte
# a byte igual
sem_pronto() {
  local e=docs/entregas/ft-rec/ENTREGA.md
  cp "$e" "$2/antes"
  registra pronto
  if [ "$REG_RC" = 3 ] && ! printf '%s\n' "$REG_OUT" | grep -Fq 'RESULTADO: PRONTO' \
    && printf '%s\n' "$REG_OUT" | grep -Fxq 'RESULTADO: BLOQUEADO — pre-push sem prova funcional' \
    && cmp -s "$e" "$2/antes"; then ok "$1"
  else falha "$1 — rc=$REG_RC: $(printf '%s' "$REG_OUT" | tr '\n' '|')"; fi
}

grupo_entrypoints() {
  local t d e hk c0 rc hoje
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  [ -r "$REGISTRA" ] || falha "registrar-portao.sh: No such file ($REGISTRA)"
  [ -r "$ATV" ] || falha "ativacao-pre-push.sh: No such file ($ATV)"
  export FX_PORTAO_PUSH="$PP"
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  e=docs/entregas/ft-rec/ENTREGA.md; hk="$(hooks_de "$d")/pre-push"; hoje="$(date +%Y-%m-%d)"

  # uma nova tentativa de entrega (o E0 de uma retomada): aberta, portão null
  edita_e 's/^estado: .*/estado: aberto/; s/^portao: .*/portao: null/; s/^portao_sha: .*/portao_sha: null/; s/^push_feito: .*/push_feito: false/; s/^entregue_em: .*/entregue_em: null/'
  persiste --persistir pre-e2
  [ -z "$(git status --porcelain)" ] && [ "$(git show "HEAD:$e" | sed -n 's/^portao: //p')" = null ] && [ ! -e "$hk" ] \
    && ok "controle: entrega aberta (portao: null) persistida em pre-e2, sem pre-push" || falha "controle pre-e2: $PER_OUT"

  # ---- usos ----------------------------------------------------------------------------------
  rc_igual "registrar-portao: --falhas com pronto é uso" 64 bash "$REGISTRA" --entrega "$e" --origem sprintx --trabalho ft-rec --resultado pronto --falhas v1
  rc_igual "registrar-portao: bloqueado sem --falhas é uso" 64 bash "$REGISTRA" --entrega "$e" --origem sprintx --trabalho ft-rec --resultado bloqueado
  rc_igual "registrar-portao: resultado fora do enum é uso" 64 bash "$REGISTRA" --entrega "$e" --origem sprintx --trabalho ft-rec --resultado talvez
  rc_igual "registrar-portao: opção de força não existe (uso)" 64 bash "$REGISTRA" --entrega "$e" --origem sprintx --trabalho ft-rec --resultado pronto --sem-prova
  rc_igual "registrar-portao: falha desconhecida é contrato inválido" 5 bash "$REGISTRA" --entrega "$e" --origem sprintx --trabalho ft-rec --resultado bloqueado --falhas v99
  rc_igual "registrar-portao: origem divergente do ENTREGA é contrato inválido" 5 bash "$REGISTRA" --entrega "$e" --origem runx --trabalho ft-rec --resultado bloqueado --falhas v1
  [ -z "$(git status --porcelain)" ] && ok "controle: os usos recusados não gravam nada" || falha "uso recusado gravou: $(git status --porcelain | tr '\n' '|')"

  # ---- E2 sem pre-push funcional ------------------------------------------------------------
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (sem pre-push)" "$t"
  fx_hook_terceiro "$d" nao_composto || falha "hook nao_composto"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (hook de terceiro não composto)" "$t"
  fx_hook_terceiro "$d" so_cita || falha "hook so_cita"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (hook que só cita a MergeX)" "$t"
  fx_hook_terceiro "$d" ecoa_sinal || falha "hook ecoa_sinal"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (hook que forja o sinal)" "$t"
  fx_hook_terceiro "$d" sem_entrada || falha "hook sem_entrada"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (hook que chama a MergeX sem a entrada)" "$t"
  fx_hook_terceiro "$d" regra_propria || falha "hook regra_propria"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (hook que não propaga o código: regra própria)" "$t"
  fx_hook_terceiro "$d" sempre_barra || falha "hook sempre_barra"
  sem_pronto "E2 sem pre-push funcional não emite nem grava PRONTO (MergeX que barra tudo no ambiente do hook)" "$t"
  rm -f "$hk"

  # ---- BLOQUEADO não depende da prova --------------------------------------------------------
  registra bloqueado v7 v1
  [ "$REG_RC" = 0 ] && [ "$(fm_e portao)" = bloqueado ] && [ "$(fm_e falhas_portao)" = '[v1, v7]' ] \
    && printf '%s\n' "$REG_OUT" | grep -Fq 'RESULTADO: BLOQUEADO' \
    && ok "BLOQUEADO não depende da prova (grava sem pre-push)" || falha "BLOQUEADO sem pre-push: rc=$REG_RC $(printf '%s' "$REG_OUT" | tr '\n' '|')"
  rc_igual "BLOQUEADO gravado passa em causa-do-portao --validar" 0 bash "$CAUSA" --validar "$e"
  c0="$(git rev-parse HEAD)"
  persiste --persistir pre-e6; rc=$?
  [ "$rc" = 0 ] && [ "$(git rev-parse HEAD)" != "$c0" ] && [ -z "$(git status --porcelain)" ] \
    && ok "pre-e6 sem portao: pronto não exige a prova (como antes)" || falha "pre-e6 bloqueado: rc=$rc $PER_OUT"

  # ---- E2 com chamador gerenciado ------------------------------------------------------------
  ( bash "$ATV" --instalar --entrega "$e" >/dev/null 2>&1 ) || falha "controle: --instalar do gerenciado"
  registra pronto
  [ "$REG_RC" = 0 ] && printf '%s\n' "$REG_OUT" | grep -Fxq 'RESULTADO: PRONTO' && [ "$(fm_e portao)" = pronto ] \
    && [ "$(fm_e portao_sha)" = "$(git rev-parse HEAD)" ] && [ "$(fm_e falhas_portao)" = '[]' ] && [ "$(fm_e atualizado_em)" = "$hoje" ] \
    && ok "E2 com chamador gerenciado grava PRONTO (portao_sha = HEAD, falhas [], atualizado_em de hoje)" \
    || falha "E2 gerenciado: rc=$REG_RC $(printf '%s' "$REG_OUT" | tr '\n' '|')"
  rc_igual "E2 com chamador gerenciado: causa-do-portao --validar aprova" 0 bash "$CAUSA" --validar "$e"
  diff <(git show "HEAD:$e" | grep -Ev '^(portao|portao_sha|falhas_portao|atualizado_em):') \
       <(grep -Ev '^(portao|portao_sha|falhas_portao|atualizado_em):' "$e") >/dev/null \
    && ok "o registro do portão só muda portao, portao_sha, falhas_portao e atualizado_em" || falha "o registro mudou outras chaves"
  [ -z "$(git diff --cached --name-only)" ] && [ "$(git status --porcelain)" = " M $e" ] \
    && ok "registrar-portao só grava o ENTREGA.md, fora do índice" || falha "registrar-portao: $(git status --porcelain | tr '\n' '|')"
  c0="$(git rev-parse HEAD)"
  persiste --persistir pre-e6; rc=$?
  [ "$rc" = 0 ] && [ "$(git rev-parse HEAD)" != "$c0" ] && git log -1 --format=%B | grep -Fxq 'Metodo: pre-e6' \
    && [ -z "$(git status --porcelain)" ] && [ "$(val_motivo HEAD)" = ok ] \
    && ok "pre-e6 persiste pronto com pre-push funcional (gerenciado; a validade aprova o HEAD)" || falha "pre-e6 gerenciado: rc=$rc $PER_OUT"
  persiste --verificar pre-e6; rc=$?
  [ "$rc" = 0 ] && ok "pre-e6 --verificar com pronto e pre-push funcional aprova" || falha "verificar pre-e6: rc=$rc $PER_OUT"
  ( bash "$ATV" --reverter --entrega "$e" >/dev/null 2>&1 ) && [ ! -e "$hk" ] || falha "controle: reversão do gerenciado"
  persiste --verificar pre-e6; rc=$?
  [ "$rc" != 0 ] && printf '%s\n' "$PER_OUT" | grep -Fq 'pre-push sem prova funcional' \
    && ok "pre-e6 --verificar recusa pronto sem pre-push funcional" || falha "verificar pre-e6 sem hook: rc=$rc $PER_OUT"

  # ---- pre-e6 e e8 recusam persistir pronto sem a prova ---------------------------------------
  edita_e "s/^portao_sha: .*/portao_sha: $(git rev-parse HEAD)/; s/^atualizado_em: .*/atualizado_em: 2026-10-09/"
  cp "$e" "$t/antes"; c0="$(git rev-parse HEAD)"
  for x in pre-e6 e8; do
    persiste --persistir "$x"; rc=$?
    [ "$rc" != 0 ] && [ "$(git rev-parse HEAD)" = "$c0" ] && [ -z "$(git diff --cached --name-only)" ] \
      && cmp -s "$e" "$t/antes" && printf '%s\n' "$PER_OUT" | grep -Fq 'pre-push sem prova funcional' \
      && ok "$x recusa persistir pronto sem pre-push funcional (sem commit, stage intacto)" || falha "$x sem hook: rc=$rc $PER_OUT"
  done
  fx_hook_terceiro "$d" so_cita || falha "hook so_cita"
  persiste --persistir pre-e6; rc=$?
  [ "$rc" != 0 ] && [ "$(git rev-parse HEAD)" = "$c0" ] && [ -z "$(git diff --cached --name-only)" ] \
    && ok "pre-e6 recusa persistir pronto com hook que só cita a MergeX" || falha "pre-e6 so_cita: rc=$rc $PER_OUT"

  # ---- E2 e persistência com hook externo composto --------------------------------------------
  fx_hook_terceiro "$d" composto || falha "hook composto"
  registra pronto
  [ "$REG_RC" = 0 ] && printf '%s\n' "$REG_OUT" | grep -Fxq 'RESULTADO: PRONTO' && [ "$(fm_e portao_sha)" = "$(git rev-parse HEAD)" ] \
    && ok "E2 com hook externo composto grava PRONTO" || falha "E2 composto: rc=$REG_RC $(printf '%s' "$REG_OUT" | tr '\n' '|')"
  persiste --persistir pre-e6; rc=$?
  [ "$rc" = 0 ] && [ "$(git rev-parse HEAD)" != "$c0" ] && [ -z "$(git status --porcelain)" ] \
    && ok "pre-e6 persiste pronto com pre-push funcional (externo composto)" || falha "pre-e6 composto: rc=$rc $PER_OUT"
  edita_e 's/^estado: .*/estado: entregue/; s/^push_feito: .*/push_feito: true/'
  c0="$(git rev-parse HEAD)"
  persiste --persistir e8; rc=$?
  [ "$rc" = 0 ] && [ "$(git rev-parse HEAD)" != "$c0" ] && git log -1 --format=%B | grep -Fxq 'Metodo: e8' \
    && ok "e8 persiste pronto com pre-push funcional (externo composto)" || falha "e8 composto: rc=$rc $PER_OUT"
  cd "$REPO" || return
}

# ---------------------------------------------------------------------------
# CI (Task 16): o mesmo portão sobre o SHA da cabeça do PR
# ---------------------------------------------------------------------------

CI="$S/portao-ci.sh"
TEMPLATE_CI="$REPO/.claude/skills/mergex/assets/ci/mergex-portao.yml"
BARREIRA_REF="$REPO/.claude/skills/mergex/references/12-barreira-de-push.md"
VALIDADOR_CONTRATO="$REPO/scripts/ci/validate-mergex-contract.sh"

# ci_roda <dir> <sha> <branch> [script] — portao-ci.sh a partir de <dir>; stdout
# em CI_OUT, stderr em CI_ERR, código em CI_RC
CI_OUT=""; CI_ERR=""; CI_RC=""
ci_roda() {
  local e b; e="$(mktemp)"; TMPS="$TMPS $e"
  # a base do PR: CI_BASE, senão a main do repositório, senão o próprio SHA
  b="${CI_BASE:-$(git -C "$1" rev-parse -q --verify "main^{commit}" 2>/dev/null || printf "%s" "$2")}"
  CI_OUT="$(cd "$1" && bash "${4:-$CI}" --verificar --sha "$2" --branch "$3" --base "$b" 2>"$e")"; CI_RC=$?
  CI_ERR="$(cat "$e")"; rm -f "$e"
}
ci_rc() { # <desc> <rc> <dir> <sha> <branch> [script]
  ci_roda "$3" "$4" "$5" "${6:-}"
  if [ "$CI_RC" = "$2" ]; then ok "$1"; else falha "$1 — rc=$CI_RC (esperava $2): $(printf '%s' "$CI_OUT $CI_ERR" | tr '\n' '|')"; fi
}
ci_err_tem() { case "$CI_ERR" in *"$2"*) ok "$1" ;; *) falha "$1 — sem '$2' no stderr: $(printf '%s' "$CI_ERR" | tr '\n' '|')" ;; esac; }
ci_err_sem() { case "$CI_ERR" in *"$2"*) falha "$1 — '$2' no stderr: $(printf '%s' "$CI_ERR" | tr '\n' '|')" ;; *) ok "$1" ;; esac; }

# remoto_novo <dir> <nome> — um bare vazio e novo como origin: o SHA remoto da
# ref é nulo, como no CI
remoto_novo() {
  local r; r="$(cd "$1/.." && pwd)/$2.git"
  git init -q --bare "$r" && git -C "$1" remote set-url origin "$r" && FX_REMOTO="$r"
}

# equivale <desc> <barra|passa> <dir> <sha> [script do pre-push] [script do ci] —
# a MESMA entrada no pre-push (push real, remoto novo) e no CI: decisões iguais
EQ_N=0
equivale() {
  local desc="$1" esp="$2" dir="$3" sha="$4" pp="${5:-$PP}" ci="${6:-$CI}" prc crc out
  EQ_N=$((EQ_N + 1))
  remoto_novo "$dir" "eq$EQ_N" || { falha "$desc — remoto novo"; return; }
  out="$(FX_PORTAO_PUSH="$pp" fx_push_real "$dir" origin "$sha:refs/heads/feature/ft-rec")"
  prc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PUSH_ERR="$(printf '%s\n' "$out" | sed -n 's/^stderr=//p')"
  ci_roda "${EQ_CIDIR:-$dir}" "$sha" feature/ft-rec "$ci"; crc="$CI_RC"
  case "$esp" in
    barra) [ "$prc" = 1 ] && [ "$crc" = 1 ] && ok "$desc: pre-push e CI barram" \
      || falha "$desc — pre-push rc=$prc, ci rc=$crc (ambos 1): $(printf '%s' "$CI_ERR" | tr '\n' '|')" ;;
    *) [ "$prc" = 0 ] && [ "$crc" = 0 ] && ok "$desc: pre-push e CI liberam" \
      || falha "$desc — pre-push rc=$prc, ci rc=$crc (ambos 0): $(printf '%s' "$CI_ERR" | tr '\n' '|')" ;;
  esac
}

grupo_ci() {
  local t d v1 p1 vv x pn n1 c a o e frase mainsha co orf ordem pais mg
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  [ -r "$CI" ] || falha "portao-ci.sh: No such file ($CI)"
  export FX_PORTAO_PUSH="$PP"
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_remoto_bare "$d" || { falha "remoto bare não montou"; return; }
  modo "$d" aviso
  cd "$d" || return
  git switch -q --detach || { falha "HEAD não destacou"; return; }

  # ---- ci reprova o SHA que o pre-push barraria; aprova o que ele libera --------
  fx_portao_em "$d" HEAD; v1="$(git rev-parse HEAD)"
  equivale "ci aprova o SHA que o pre-push libera (pronto válido)" passa "$d" "$v1"
  ci_err_sem "ci aprova o válido: nenhum diagnóstico" "mergex ci"
  case "$CI_OUT" in *decisao=passa*motivo=portao_valido*) ok "ci imprime decisao=passa e motivo=portao_valido" ;; *) falha "saída do ci válido: $(printf '%s' "$CI_OUT" | tr '\n' '|')" ;; esac
  produto "$d" vencido1; p1="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = commit_de_produto ] && ok "controle: HEAD vencido por produto" || falha "controle: HEAD não venceu"
  equivale "ci reprova o SHA que o pre-push barraria (pronto vencido)" barra "$d" "$p1"
  ci_err_tem "ci vencido: diagnóstico cita commit_de_produto" "commit_de_produto"
  case "$CI_OUT" in *decisao=barra*) ok "ci imprime decisao=barra" ;; *) falha "saída do ci vencido: $(printf '%s' "$CI_OUT" | tr '\n' '|')" ;; esac

  # ausente: pronto legado sem portao_sha, e ENTREGA.md ausente do SHA enviado
  # (a ponta local da branch ainda a declara)
  fx_portao_em "$d" HEAD; vv="$(git rev-parse HEAD)"
  fx_portao_sem_sha "$d"; x="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = portao_sha_ausente ] && ok "controle: pronto sem portao_sha" || falha "controle: legado"
  equivale "ci reprova o SHA que o pre-push barraria (portão ausente: pronto sem portao_sha)" barra "$d" "$x"
  ci_err_tem "ci sem portao_sha: instrução de rodar o E2" "rode o E2"
  pn="$( GIT_INDEX_FILE="$t/idx-sem" git read-tree "$vv" \
    && GIT_INDEX_FILE="$t/idx-sem" git update-index --force-remove docs/entregas/ft-rec/ENTREGA.md \
    && git commit-tree "$(GIT_INDEX_FILE="$t/idx-sem" git write-tree)" -p "$vv" -m "docs: sem entrega"; rm -f "$t/idx-sem" )"
  git cat-file -e "$pn:docs/entregas/ft-rec/ENTREGA.md" 2>/dev/null && falha "controle: o ENTREGA.md continua no SHA sem entrega" || ok "controle: SHA sem ENTREGA.md"
  equivale "ci reprova o SHA que o pre-push barraria (ENTREGA.md ausente do SHA enviado)" barra "$d" "$pn"

  # clone no formato do actions/checkout: objetos, HEAD destacado e nenhuma refs/heads
  mainsha="$(git rev-parse main)"
  co="$t/checkout"; cp -a "$d" "$co" || { falha "cópia do checkout"; return; }
  git -C "$co" rev-parse -q --verify "$vv^{commit}" >/dev/null && git -C "$co" update-ref --no-deref HEAD "$vv" \
    && for h in $(git -C "$co" for-each-ref --format="%(refname)" refs/heads); do git -C "$co" update-ref -d "$h"; done
  [ -z "$(git -C "$co" for-each-ref refs/heads)" ] && [ "$(git -C "$co" rev-parse --abbrev-ref HEAD)" = HEAD ] \
    && ok "controle: o clone do checkout não tem refs/heads e o HEAD é destacado" || falha "controle: o clone do checkout tem refs/heads"
  CI_BASE="$mainsha" EQ_CIDIR="$co" equivale "ci reprova o SHA que remove o ENTREGA.md (clone sem refs/heads, como o actions/checkout)" barra "$d" "$pn"
  ci_err_tem "SHA que remove o ENTREGA.md: diagnóstico do portão não pronto" "portao_nao_pronto"
  CI_BASE="$mainsha" EQ_CIDIR="$co" equivale "ci reprova o SHA vencido (clone sem refs/heads)" barra "$d" "$p1"
  CI_BASE="$mainsha" EQ_CIDIR="$co" equivale "ci aprova o SHA válido (clone sem refs/heads)" passa "$d" "$vv"
  CI_BASE="$mainsha" ci_rc "ci: --sha ausente no clone barra (entrega_indeterminada)" 1 "$co" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa feature/ft-rec
  ci_err_tem "ci: --sha ausente no clone: diagnóstico" "entrega_indeterminada"
  CI_BASE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ci_rc "ci: --base que não é objeto no clone: historia_incompleta barra" 1 "$co" "$pn" feature/ft-rec
  ci_err_tem "ci: --base ausente: diagnóstico historia_incompleta" "historia_incompleta"
  orf="$(git -C "$co" commit-tree "$(git -C "$co" hash-object -t tree -w /dev/null)" -m orfao)"
  # sem merge-base (clone completo): a história do PR é a do SHA inteiro, sem fechar à toa
  CI_BASE="$orf" ci_rc "ci: --base sem merge-base, SHA que apaga um ENTREGA.md da própria história: barra (história inteira)" 1 "$co" "$pn" feature/ft-rec
  ci_err_tem "ci: sem merge-base: a história inteira acha o ENTREGA.md apagado" "portao_nao_pronto"
  CI_BASE="$mainsha" ci_rc "ci: branch órfã sem merge-base e sem ENTREGA.md na história não é aplicável: passa" 0 "$co" "$orf" feature/ft-rec
  case "$CI_OUT" in *motivo=ref_nao_aplicavel*) ok "ci: branch órfã: motivo ref_nao_aplicavel" ;; *) falha "branch órfã: $(printf '%s' "$CI_OUT $CI_ERR" | tr '\n' '|')" ;; esac
  # merge cuja árvore descarta o docs/entregas do PR (git rev-list simplificaria a história)
  for ordem in vv_main main_vv; do
    case "$ordem" in vv_main) pais="-p $vv -p $mainsha" ;; main_vv) pais="-p $mainsha -p $vv" ;; esac
    # a árvore de vv com o docs/entregas da main (que não o tem): TREESAME à main nesse caminho
    [ -z "$(git -C "$d" ls-tree "$mainsha" -- docs/entregas)" ] || falha "controle: a main tem docs/entregas"
    mg="$( GIT_INDEX_FILE="$t/idx-mg" git -C "$d" read-tree "$vv" \
      && GIT_INDEX_FILE="$t/idx-mg" git -C "$d" rm -r -q -f --cached docs/entregas \
      && git -C "$d" commit-tree "$(GIT_INDEX_FILE="$t/idx-mg" git -C "$d" write-tree)" $pais -m "merge descarta docs/entregas ($ordem)"; rm -f "$t/idx-mg" )"
    [ -n "$mg" ] && [ -z "$(git -C "$d" ls-tree "$mg" -- docs/entregas)" ] && ok "controle: merge ($ordem) sem docs/entregas, como a main" || { falha "controle: merge $ordem não montou"; continue; }
    git -C "$d" update-ref "refs/tmp/mg-$ordem" "$mg" && git -C "$co" fetch -q "$d" "refs/tmp/mg-$ordem:refs/tmp/mg-$ordem" \
      || { falha "merge $ordem não montou"; continue; }
    CI_BASE="$mainsha" EQ_CIDIR="$co" equivale "ci reprova o merge que descarta o ENTREGA.md do PR ($ordem; clone sem refs/heads)" barra "$d" "$mg"
    ci_err_tem "merge ($ordem): diagnóstico do portão não pronto" "portao_nao_pronto"
  done
  CI_BASE="$pn" ci_rc "ci: base igual ao SHA sem ENTREGA.md declarando: não aplicável (controle da regra de aplicabilidade)" 0 "$co" "$pn" feature/ft-rec

  # historia_incompleta: clone raso, com a mesma entrada no pre-push e no CI
  git push -q origin "$vv:refs/heads/feature/ft-rec" >/dev/null 2>&1 || falha "push do portão válido ao remoto"
  cd "$t" || return
  git clone -q --depth 1 -b feature/ft-rec "file://$FX_REMOTO" "$t/raso" 2>/dev/null || falha "clone --depth 1"
  git -C "$t/raso" config user.email teste@expx.local; git -C "$t/raso" config user.name "Teste Expx"
  git -C "$t/raso" config commit.gpgsign false
  [ "$(git -C "$t/raso" rev-parse --is-shallow-repository)" = true ] && ok "controle: clone --depth 1 é raso" || falha "controle: clone não é raso"
  fx_commit_metodo "$t/raso" pre-e6 docs/entregas/ft-rec/PR.md || falha "commit no clone raso"
  modo "$t/raso" aviso
  equivale "ci reprova o SHA que o pre-push barraria (historia_incompleta, clone raso)" barra "$t/raso" "$(git -C "$t/raso" rev-parse HEAD)"
  ci_err_tem "ci clone raso: diagnóstico historia_incompleta" "historia_incompleta"
  ci_err_tem "ci clone raso: diagnóstico indica git fetch --unshallow" "git fetch --unshallow"
  printf '%s\n' "$CI_ERR" > "$t/err-ci-historia"
  cd "$d" || return

  # erro_ambiente: o validador ausente (cópia dos scripts sem ele)
  mkdir -p "$t/sem-validade"; cp "$S"/*.sh "$t/sem-validade/"; rm -f "$t/sem-validade/validade-do-portao.sh"
  equivale "ci reprova o SHA que o pre-push barraria (erro_ambiente, validador ausente)" barra "$d" "$vv" \
    "$t/sem-validade/portao-push.sh" "$t/sem-validade/portao-ci.sh"
  ci_err_tem "ci validador ausente: diagnóstico erro_ambiente" "erro_ambiente"
  ci_err_tem "ci validador ausente: diagnóstico de ambiente" "erro de ambiente"
  printf '%s\n' "$CI_ERR" > "$t/err-ci-ambiente"
  ! grep -Fq "erro de ambiente" "$t/err-ci-historia" && ! grep -Fq "unshallow" "$t/err-ci-ambiente" \
    && ok "ci: historia_incompleta e erro_ambiente com diagnósticos distintos" || falha "ci: diagnósticos não distintos"
  mkdir -p "$t/sem-regras"; cp "$CI" "$t/sem-regras/"
  ci_rc "ci sem portao-regras.sh ao lado: erro_ambiente barra" 1 "$d" "$vv" feature/ft-rec "$t/sem-regras/portao-ci.sh"
  ci_err_tem "ci sem as regras: diagnóstico erro_ambiente" "erro_ambiente"

  # ---- ci usa o SHA do PR, não o HEAD local ----------------------------------------
  git switch -q --detach "$vv"
  [ "$(git rev-parse HEAD)" = "$vv" ] && [ "$(val_motivo HEAD)" = ok ] && ok "controle: HEAD local válido" || falha "controle: HEAD válido"
  ci_rc "ci usa o SHA do PR (HEAD local válido, SHA vencido): barra" 1 "$d" "$p1" feature/ft-rec
  ci_err_tem "ci: o diagnóstico é o do SHA vencido" "commit_de_produto"
  git switch -q --detach "$p1"
  [ "$(val_motivo HEAD)" = commit_de_produto ] && ok "controle: HEAD local vencido" || falha "controle: HEAD vencido"
  ci_rc "ci usa o SHA do PR (HEAD local vencido, SHA válido): passa" 0 "$d" "$vv" feature/ft-rec
  git switch -q --detach "$vv"

  # ---- null no CI segue o modo de .expx/hooks.json ---------------------------------
  entrega_commit "$d" 's/^portao: .*/portao: null/' pre-e6; n1="$(git rev-parse HEAD)"
  [ "$(val_motivo HEAD)" = portao_nao_pronto ] && ok "controle: portao null" || falha "controle: portao null"
  modo "$d" bloqueio
  equivale "null no CI segue o modo: bloqueio barra como o pre-push" barra "$d" "$n1"
  ci_err_tem "null em bloqueio: diagnóstico do portão não autorizado" "portao: null"
  modo "$d" aviso
  equivale "null no CI segue o modo: aviso libera como o pre-push" passa "$d" "$n1"
  ci_roda "$d" "$n1" feature/ft-rec
  ci_err_tem "null em aviso: diagnóstico em stderr" "portao: null"
  case "$CI_OUT" in *decisao=avisa*motivo=portao_null*) ok "ci imprime decisao=avisa e motivo=portao_null" ;; *) falha "saída do ci null/aviso: $(printf '%s' "$CI_OUT" | tr '\n' '|')" ;; esac
  modo "$d" desligado
  equivale "null no CI segue o modo: desligado libera como o pre-push" passa "$d" "$n1"
  ci_err_sem "null em desligado: sem diagnóstico" "mergex ci"
  modo "$d" -
  equivale "null no CI sem .expx/hooks.json: aviso (o padrão) libera" passa "$d" "$n1"
  printf '{"hooks":{"pr-so-com-portao":{"modo":"bloquear"}}}\n' > "$d/.expx/hooks.json"
  equivale "null no CI com modo inválido: falha fechada, barra" barra "$d" "$n1"
  modo "$d" desligado
  # o modo nunca afrouxa pronto vencido
  ci_rc "o modo desligado não afrouxa o pronto vencido" 1 "$d" "$p1" feature/ft-rec

  # ---- ref que não é a branch do trabalho: não aplicável ---------------------------
  ci_rc "residual: PR de branch com outro nome não é aplicável (SHA vencido passa; risco documentado)" 0 "$d" "$p1" feature/ft-rec-2
  case "$CI_OUT" in *motivo=ref_nao_aplicavel*) ok "ci imprime motivo=ref_nao_aplicavel" ;; *) falha "saída: $(printf '%s' "$CI_OUT" | tr '\n' '|')" ;; esac

  # ---- uso --------------------------------------------------------------------------
  cd "$d" || return
  rc_igual "ci sem argumentos: uso" 64 bash "$CI"
  rc_igual "ci sem --branch: uso" 64 bash "$CI" --verificar --sha "$v1" --base "$v1"
  rc_igual "ci sem --base: uso" 64 bash "$CI" --verificar --sha "$v1" --branch feature/ft-rec
  rc_igual "ci com --base abreviado: uso" 64 bash "$CI" --verificar --sha "$v1" --branch feature/ft-rec --base "$(printf '%s' "$v1" | cut -c1-12)"
  rc_igual "ci com --branch refs/heads/...: uso" 64 bash "$CI" --verificar --sha "$v1" --branch refs/heads/feature/ft-rec --base "$v1"
  rc_igual "ci com --branch inválido (a..b): uso" 64 bash "$CI" --verificar --sha "$v1" --branch a..b --base "$v1"
  rc_igual "ci com --branch começando por hífen: uso" 64 bash "$CI" --verificar --sha "$v1" --branch --x --base "$v1"
  rc_igual "ci com --branch vazio: uso" 64 bash "$CI" --verificar --sha "$v1" --base "$v1" --branch ""
  rc_igual "ci com SHA abreviado: uso" 64 bash "$CI" --verificar --sha "$(printf '%s' "$v1" | cut -c1-12)" --branch feature/ft-rec --base "$v1"
  rc_igual "ci com nome de ref no lugar do SHA: uso" 64 bash "$CI" --verificar --sha HEAD --branch feature/ft-rec --base "$v1"
  rc_igual "ci com SHA em maiúsculas: uso" 64 bash "$CI" --verificar --sha AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA --branch feature/ft-rec --base "$v1"
  rc_igual "ci sem --verificar: uso" 64 bash "$CI" --sha "$v1" --branch feature/ft-rec --base "$v1"
  rc_igual "ci com opção desconhecida: uso" 64 bash "$CI" --verificar --sha "$v1" --branch feature/ft-rec --base "$v1" --force
  rc_igual "ci não tem opção de força: --force no lugar do SHA" 64 bash "$CI" --verificar --force "$v1" --branch feature/ft-rec --base "$v1"

  # ---- template ----------------------------------------------------------------------
  [ -f "$TEMPLATE_CI" ] || falha "template ausente: $TEMPLATE_CI"
  grep -Eq '^[[:space:]]*fetch-depth: 0[[:space:]]*$' "$TEMPLATE_CI" \
    && ok "template fixa fetch-depth 0" || falha "template sem fetch-depth: 0"
  grep -Fq 'ref: ${{ github.event.pull_request.head.sha }}' "$TEMPLATE_CI" \
    && ok "template faz checkout do SHA da cabeça do PR" || falha "template sem checkout de pull_request.head.sha"
  grep -Fq 'PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}' "$TEMPLATE_CI" \
    && ok "template passa o SHA da cabeça do PR ao portao-ci.sh" || falha "template sem o SHA do PR no step"
  grep -Fq 'PR_HEAD_REF: ${{ github.event.pull_request.head.ref }}' "$TEMPLATE_CI" \
    && ok "template passa a branch de origem do PR" || falha "template sem a branch do PR"
  c="$(grep -F 'portao-ci.sh' "$TEMPLATE_CI" | grep -v '^[[:space:]]*#')"
  case "$c" in *'portao-ci.sh --verificar --sha "$PR_HEAD_SHA" --branch "$PR_HEAD_REF" --base "$PR_BASE_SHA"'*) ok "template chama portao-ci.sh --verificar com o SHA e a branch do PR" ;; *) falha "template sem a chamada de portao-ci.sh: $c" ;; esac
  case "$c" in *'${{'*) falha "template interpola expressão no shell (injeção): $c" ;; *) ok "template não interpola o evento no texto do shell" ;; esac
  grep -Fq 'PR_BASE_SHA: ${{ github.event.pull_request.base.sha }}' "$TEMPLATE_CI" \
    && ok "template passa o SHA da base do PR" || falha "template sem a base do PR"
  grep -Eq '^[[:space:]]*pull_request:[[:space:]]*$' "$TEMPLATE_CI" && ok "template roda em pull_request" || falha "template sem on: pull_request"
  sed -n '1p' "$TEMPLATE_CI" | grep -Fq 'TEMPLATE' && grep -Fq 'NÃO o' "$TEMPLATE_CI" \
    && ok "template declara no topo que é template e que esta branch não o ativa" || falha "template sem a declaração de template"

  # ---- nenhum workflow ativo ------------------------------------------------------------
  [ -z "$(git -C "$REPO" ls-files .github/workflows)" ] && ok "nenhum workflow ativo nesta branch (git ls-files .github/workflows vazio)" \
    || falha "há arquivo versionado em .github/workflows"
  [ -z "$(git -C "$REPO" ls-files | grep -E '(^|/)\.github/workflows/')" ] \
    && ok "nenhum caminho versionado sob .github/workflows em qualquer nível" || falha "caminho sob .github/workflows"

  # ---- documentação não afirma CI ativo ---------------------------------------------------
  frase='CI do portão ativo'
  grep -Fq 'Esta branch não ativa CI em nenhum produto' "$BARREIRA_REF" \
    && ok "o reference diz que esta branch não ativa CI em produto" || falha "o reference não diz que a branch não ativa CI"
  grep -Fq 'ft-rec-2' "$BARREIRA_REF" && grep -Fq 'Riscos residuais do CI' "$BARREIRA_REF" \
    && ok "o reference documenta o risco residual do PR de branch com outro nome" || falha "reference sem o risco residual de I2"
  grep -Fq 'CODEOWNERS' "$BARREIRA_REF" && grep -Fq '.expx/**' "$BARREIRA_REF" && grep -Fq '.github/**' "$BARREIRA_REF" \
    && grep -Fq 'autor do PR controla a cabeça do PR' "$BARREIRA_REF" \
    && ok "o reference documenta que o autor do PR controla o modo e os scripts, e recomenda CODEOWNERS" || falha "reference sem o limite de I3"
  grep -Fq 'ft-rec-2' "$CI" && grep -Fq 'CODEOWNERS' "$CI" \
    && ok "o cabeçalho de portao-ci.sh documenta os riscos residuais" || falha "portao-ci.sh sem os riscos residuais"
  grep -Fxq '## CI' "$BARREIRA_REF" && ok "o reference tem a seção CI" || falha "o reference sem a seção '## CI'"
  ( cd "$REPO" && bash "$VALIDADOR_CONTRATO" ) >/dev/null 2>&1 && ok "o validador do contrato aprova o repositório (nenhum arquivo afirma CI ativo)" \
    || falha "o validador do contrato reprova o repositório"
  grep -Fq '# guarda:CIATIVO' "$VALIDADOR_CONTRATO" && ok "o validador tem a linha de guarda CIATIVO" || falha "validador sem # guarda:CIATIVO"
  # cópia com a frase-alvo no reference: o validador reprova (e sem ela, aprova)
  c="$t/copia"; mkdir -p "$c"
  git -C "$REPO" ls-files -co --exclude-standard -z | ( cd "$REPO" && tar --null -T - -cf - ) | ( cd "$c" && tar -xf - ) \
    && ( cd "$c" && git init -q && git config user.email teste@expx.local && git config user.name "Teste Expx" && git add -A ) >/dev/null 2>&1 \
    || { falha "cópia do repositório não montou"; return; }
  ( cd "$c" && bash scripts/ci/validate-mergex-contract.sh ) >/dev/null 2>&1 \
    && ok "controle: a cópia sem a frase-alvo é aprovada pelo validador" || falha "controle: a cópia limpa reprova"
  cp "$c/.claude/skills/mergex/references/12-barreira-de-push.md" "$t/ref.bak"
  printf '\n%s em todo produto.\n' "$frase" >> "$c/.claude/skills/mergex/references/12-barreira-de-push.md"
  ( cd "$c" && git add -A && bash scripts/ci/validate-mergex-contract.sh ) >"$t/saida-val" 2>&1; a=$?
  [ "$a" != 0 ] && grep -Fq 'CI' "$t/saida-val" \
    && ok "a frase-alvo num arquivo versionado faz o validador reprovar" || falha "validador aprovou a frase-alvo (rc=$a): $(tr '\n' '|' < "$t/saida-val")"
  cp "$t/ref.bak" "$c/.claude/skills/mergex/references/12-barreira-de-push.md"
  printf '\n%s\n' 'CI DO PORTAO ATIVO' >> "$c/docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md"
  ( cd "$c" && git add -A && bash scripts/ci/validate-mergex-contract.sh ) >"$t/saida-val" 2>&1; a=$?
  [ "$a" != 0 ] && ok "a frase-alvo em maiúsculas e sem acento, em outro arquivo versionado, também reprova" || falha "validador aprovou a variante (rc=$a)"

  # ---- PR #192 ----------------------------------------------------------------------------------
  grep -Fq 'PR #192' "$BARREIRA_REF" && grep -Fq 'rascunho' "$BARREIRA_REF" \
    && grep -Fq 'instalação da MergeX nova com o `pre-push` ativo' "$BARREIRA_REF" \
    && grep -Fq 'check de CI correspondente com a proteção de merge' "$BARREIRA_REF" \
    && grep -Fq 'os gates' "$BARREIRA_REF" \
    && ok "PR #192 fica em rascunho até instalação, CI e gates (os três itens no reference)" || falha "reference sem a condição do PR #192 com os três itens"
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
# NAO_EXECUTADO nunca conta como ok: fica listado à parte
[ "$NAOEXEC" -eq 0 ] || echo "$NAOEXEC caso(s) NAO_EXECUTADO (não contados como ok)"
[ "$FALHOU" -eq 0 ]
