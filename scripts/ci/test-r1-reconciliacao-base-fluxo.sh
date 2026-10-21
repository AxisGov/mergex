#!/usr/bin/env bash
# shellcheck shell=bash
#
# Parte da bancada R1: scripts/ci/test-r1-reconciliacao-base.sh a carrega com
# `.`, na ordem de definição, e roda os grupos. Esta parte só define funções e
# variáveis, e não roda sozinha. Grupos: fluxo e invariantes.

[ "${BASH_SOURCE[0]}" != "$0" ] || { echo "${0##*/}: parte da bancada R1; rode scripts/ci/test-r1-reconciliacao-base.sh" >&2; exit 64; }

# ---------------------------------------------------------------------------
# Fluxo ponta a ponta depois da reconciliação (Task 20, spec seção 16)
# ---------------------------------------------------------------------------

# fl_saida <etapa> [err] — o stdout (ou o stderr) gravado da etapa no último
# fx_fluxo_completo
fl_saida() { cat "$FX_FLUXO_DIR/$1.${2:-out}" 2>/dev/null; }

# fl_rc <desc> <etapa> — a etapa saiu 0
fl_rc() {
  if [ "$(cat "$FX_FLUXO_DIR/$2.rc" 2>/dev/null)" = 0 ]; then ok "$1"
  else falha "$1 — rc=$(cat "$FX_FLUXO_DIR/$2.rc" 2>/dev/null) $(fl_saida "$2" | tr '\n\t' '|>') $(fl_saida "$2" err | tr '\n' '|')"; fi
}

# fl_metodo <desc> <commit> <pai> <checkpoint> <caminho>... — o commit tem um
# pai (o dado), é método válido do checkpoint e toca exatamente os caminhos
fl_metodo() {
  local desc="$1" c="$2" pai="$3" cp="$4" toca esperado; shift 4
  toca="$(git diff-tree --no-commit-id --name-only -r --no-renames "$c" | LC_ALL=C sort)"
  esperado="$(printf '%s\n' "$@" | LC_ALL=C sort)"
  if [ "$(git rev-list --parents -n1 "$c")" = "$c $pai" ] \
    && bash "$CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint "$cp" --commit "$c" >/dev/null 2>&1 \
    && [ "$toca" = "$esperado" ]; then ok "$desc"
  else falha "$desc — commit $c, pais $(git rev-list --parents -n1 "$c" | cut -d' ' -f2-), toca: $(printf '%s' "$toca" | tr '\n' '|')"; fi
}

# fl_validade_ok <desc> <etapa> — a saída gravada é a validade aprovada
fl_validade_ok() {
  [ "$(fl_saida "$2" | grep -v '^aviso=')" = "$(printf 'ok=true\nprimeiro_commit=-')" ] \
    && ok "$1" || falha "$1 — $(fl_saida "$2" | tr '\n' '|')"
}

# fl_secao <arquivo> <título> — as linhas da seção `## <título>` (até a seguinte)
fl_secao() {
  awk -v t="## $2" 'index($0, "## ") == 1 { dentro = (index($0, t) == 1); next } dentro' "$1"
}

# fl_passos <rótulo> — os passos 1 a 10 do último fx_fluxo_completo, um a um,
# no repositório do cwd (a árvore em que o fluxo rodou)
fl_passos() {
  local r="$1" e=docs/entregas/ft-rec/ENTREGA.md ar=docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  local a=docs/entregas/ft-rec/ATENCAO.md hk f out olho
  hk="$(git rev-parse --path-format=absolute --git-path hooks)/pre-push"

  # 1. E0: o chamador gerenciado no diretório efetivo, sem core.hooksPath
  fl_rc "$r 1: ativacao-pre-push --instalar sai 0" 01-instalar
  [ -x "$hk" ] && [ "$(sed -n 2p "$hk")" = '# mergex: pre-push gerenciado' ] \
    && ok "$r 1: o chamador gerenciado está no diretório efetivo do Git" || falha "$r 1: sem chamador gerenciado em $hk"
  [ -z "$(git config --get core.hooksPath)" ] \
    && ok "$r 1: core.hooksPath vazio (o pre-push é o do diretório padrão do Git)" || falha "$r 1: core.hooksPath=$(git config --get core.hooksPath)"

  # 2. registro dos dois testes
  fl_rc "$r 2: --registrar dos dois testes sai 0" 02-registrar
  out="$(fl_saida 02-registrar)"
  printf '%s\n' "$out" | grep -Fxq 'registrado=RECONCILIACAO-BASE-001.md' && printf '%s\n' "$out" | grep -Fxq "m=$FX_M" \
    && printf '%s\n' "$out" | grep -Fxq "b1=$FX_B1" \
    && ok "$r 2: registrado o 001 sobre M e B1" || falha "$r 2: $(printf '%s' "$out" | tr '\n' '|')"

  # 3. checkpoint reconciliacao-base
  fl_rc "$r 3: persistir-metodo --checkpoint reconciliacao-base sai 0" 03-reconciliacao-base
  fl_metodo "$r 3: o commit reconciliacao-base sobre M toca só o ENTREGA.md e o 001" \
    "$FX_FLUXO_RECONC" "$FX_M" reconciliacao-base "$e" "$ar"

  # 4. barreira
  fl_rc "$r 4: barreira --verificar --checkpoint reconciliacao-base sai 0" 04-barreira
  out="$(fl_saida 04-barreira)"
  [ "$(printf '%s\n' "$out" | sed -n 1p)" = ok=true ] && [ "$(printf '%s\n' "$out" | wc -l)" = 3 ] \
    && printf '%s\n' "$out" | grep -Fxq "coberto	$FX_NOVO1	001" && printf '%s\n' "$out" | grep -Fxq "coberto	$FX_NOVO2	001" \
    && ok "$r 4: ok=true com os dois caminhos cobertos pelo 001" || falha "$r 4: $(printf '%s' "$out" | tr '\n\t' '|>')"

  # 5. V9 e prova funcional
  fl_rc "$r 5: portao-v9 sai 0" 05-v9
  out="$(fl_saida 05-v9)"
  printf '%s\n' "$out" | grep -Fxq resultado=ok && printf '%s\n' "$out" | grep -Fxq "base=$FX_B1" \
    && printf '%s\n' "$out" | grep -Fxq origem_base=reconciliacao && ! printf '%s\n' "$out" | grep -q '^fora_do_plano' \
    && ok "$r 5: V9 ok sobre B1 da reconciliação, sem fora_do_plano" || falha "$r 5: $(printf '%s' "$out" | tr '\n\t' '|>')"
  fl_rc "$r 5: ativacao-pre-push --provar sai 0" 05-provar

  # 6. portão gravado só pelo registrar-portao
  fl_rc "$r 6: registrar-portao --resultado pronto sai 0" 06-registrar-portao
  out="$(fl_saida 06-registrar-portao)"
  printf '%s\n' "$out" | grep -Fxq 'RESULTADO: PRONTO' && printf '%s\n' "$out" | grep -Fxq "portao_sha=$FX_FLUXO_RECONC" \
    && [ "$FX_FLUXO_PORTAO" = "$FX_FLUXO_RECONC" ] \
    && ok "$r 6: PRONTO com portao_sha = o HEAD avaliado (o commit reconciliacao-base)" || falha "$r 6: $(printf '%s' "$out" | tr '\n' '|')"

  # 7. E3 com O10 e checkpoint pre-e6
  fl_rc "$r 7: E3 (classificar-atencao --reconciliados) sai 0" 07-e3
  fl_rc "$r 7: persistir-metodo --checkpoint pre-e6 sai 0" 07-pre-e6
  fl_metodo "$r 7: o commit pre-e6 toca só o ENTREGA.md e o ATENCAO.md" "$FX_FLUXO_PRE_E6" "$FX_FLUXO_RECONC" pre-e6 "$e" "$a"
  [ "$(git show "$FX_FLUXO_PRE_E6:$e" | sed -n 's/^portao: //p')" = pronto ] \
    && [ "$(git show "$FX_FLUXO_PRE_E6:$e" | sed -n 's/^portao_sha: //p')" = "$FX_FLUXO_PORTAO" ] \
    && ok "$r 7: o pre-e6 persiste portao: pronto e o portao_sha do registrar-portao" || falha "$r 7: portão persistido diferente"
  git show "$FX_FLUXO_PRE_E6:$a" > "$FX_FLUXO_DIR/atencao-head.md"
  olho="$(fl_secao "$FX_FLUXO_DIR/atencao-head.md" 'OLHO OBRIGATÓRIO')"
  for f in "$FX_NOVO1" "$FX_NOVO2"; do
    printf '%s\n' "$olho" | grep -F "| \`$f\` |" | grep -Fq 'O10: arquivo reconciliado da base (RECONCILIACAO-BASE-001.md)' \
      && ok "$r 7: ATENCAO.md tem $f em OLHO OBRIGATÓRIO por O10 (cita o 001)" || falha "$r 7: $f sem O10 no OLHO OBRIGATÓRIO"
  done
  [ "$(grep -c 'O10:' "$FX_FLUXO_DIR/atencao-head.md")" = 2 ] \
    && ok "$r 7: O10 só nos dois reconciliados" || falha "$r 7: O10 em $(grep -c 'O10:' "$FX_FLUXO_DIR/atencao-head.md") linhas"

  # 8. validade
  fl_rc "$r 8: validade-do-portao depois do pre-e6 sai 0" 08-validade
  fl_validade_ok "$r 8: validade ok=true depois do pre-e6" 08-validade

  # 9. checkpoint e8
  fl_rc "$r 9: E7 (retomada do PR existente) sai 0" 09-e7
  fl_rc "$r 9: persistir-metodo --checkpoint e8 sai 0" 09-e8
  fl_metodo "$r 9: o commit e8 toca só o PR.md" "$FX_FLUXO_E8" "$FX_FLUXO_PRE_E6" e8 docs/entregas/ft-rec/PR.md

  # 10. validade
  fl_rc "$r 10: validade-do-portao depois do e8 sai 0" 10-validade
  fl_validade_ok "$r 10: validade ok=true depois do e8" 10-validade
  [ "$(git rev-parse HEAD)" = "$FX_FLUXO_E8" ] && [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] \
    && [ -z "$(git diff --cached --name-only)" ] \
    && ok "$r 10: HEAD é o commit e8, árvore limpa e stage vazio" || falha "$r 10: $(git status --porcelain | tr '\n' '|')"
}

# fl_push <desc> <rc> <ref esperada> <dir> <args do git push>... — push REAL
# pelo pre-push efetivo (fx_push_efetivo); exige o rc e o SHA da ref no remoto.
# O stderr fica em FL_ERR. MERGEX_PRE_PUSH_SINAL do chamador chega ao hook.
FL_ERR=""
fl_push() {
  local desc="$1" rce="$2" refe="$3" dir="$4" out rc ref; shift 4
  out="$(fx_push_efetivo "$dir" "$@")"
  rc="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  ref="$(printf '%s\n' "$out" | sed -n 's/^ref=//p')"
  FL_ERR="$(printf '%s\n' "$out" | sed -n 's/^stderr=//p')"
  if [ "$rc" = "$rce" ] && [ "$ref" = "$refe" ]; then ok "$desc"
  else falha "$desc — rc=$rc (esperava $rce), ref=$ref (esperava $refe); stderr: $(tr '\n' '|' < "${FL_ERR:-/dev/null}" 2>/dev/null)"; fi
}

# fl_pushes <rótulo> <dir> <tmp> — passos 11 e 12: o push real aceito e,
# depois de um commit de produto, o push real barrado
fl_pushes() {
  local r="$1" dir="$2" t="$3" v p out
  [ -z "$(git -C "$dir" config --get core.hooksPath)" ] \
    && ok "$r 11: core.hooksPath vazio antes do push" || falha "$r 11: core.hooksPath=$(git -C "$dir" config --get core.hooksPath)"
  v="$(git -C "$dir" rev-parse HEAD)"
  : > "$t/sinal"
  MERGEX_PRE_PUSH_SINAL="$t/sinal" fl_push "$r 11: pre-push libera o push real (ref remota = HEAD)" 0 "$v" "$dir" origin feature/ft-rec
  grep -Fxq "mergex-pre-push $v passa" "$t/sinal" \
    && ok "$r 11: quem decidiu foi o portao-push.sh pelo chamador do E0 (passa)" || falha "$r 11: sinal: $(tr '\n' '|' < "$t/sinal")"

  fx_commit_produto_apos_portao "$dir" || falha "$r 12: fx_commit_produto_apos_portao"
  p="$(git -C "$dir" rev-parse HEAD)"
  [ "$(git -C "$dir" rev-parse HEAD^)" = "$v" ] && ! git -C "$dir" show -s --format=%B HEAD | grep -q '^Metodo:' \
    && ok "$r 12: commit de produto comum depois do portão" || falha "$r 12: commit de produto"
  out="$(cd "$dir" && bash "$VALIDADE" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md 2>/dev/null)"
  [ "$(printf '%s\n' "$out" | grep -v '^aviso=')" = "$(printf 'ok=false\nmotivo=commit_de_produto\nprimeiro_commit=%s' "$p")" ] \
    && ok "$r 12: a validade vence com commit_de_produto no commit novo" || falha "$r 12: validade $(printf '%s' "$out" | tr '\n' '|')"
  : > "$t/sinal"
  MERGEX_PRE_PUSH_SINAL="$t/sinal" fl_push "$r 12: pre-push barra o push vencido (ref remota não muda)" 1 "$v" "$dir" origin feature/ft-rec
  grep -Fq commit_de_produto "$FL_ERR" \
    && ok "$r 12: o stderr do push barrado cita commit_de_produto" || falha "$r 12: stderr: $(tr '\n' '|' < "$FL_ERR")"
  grep -Fxq "mergex-pre-push $p barra" "$t/sinal" \
    && ok "$r 12: quem barrou foi o portao-push.sh pelo chamador do E0 (barra)" || falha "$r 12: sinal: $(tr '\n' '|' < "$t/sinal")"
}

grupo_fluxo() {
  local t d
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t"); d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  fx_fluxo_completo "$d" || { falha "fluxo: ${FX_ERRO:-}"; cd "$REPO"; return; }
  ok "fluxo completo depois da reconciliação"
  fl_passos fluxo
  fx_remoto_bare "$d" || { falha "remoto bare não montou"; cd "$REPO"; return; }
  case "$FX_REMOTO" in "$t"/*) ok "controle: o remoto é o bare local do temporário" ;; *) falha "remoto fora do temporário: $FX_REMOTO" ;; esac
  fl_pushes fluxo "$d" "$t"
  cd "$REPO" || return
}

grupo_invariantes() {
  local t d plano seq hk
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t"); d="$t/repo"
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_worktree_vinculada "$d" || { falha "worktree vinculada não montou"; return; }
  cd "$FX_WT" || return
  [ -f .git ] && [ "$(git rev-parse --abbrev-ref HEAD)" = feature/ft-rec ] \
    && ok "controle: worktree vinculada (.git é arquivo) em feature/ft-rec" || falha "controle: worktree"
  plano="$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)"
  seq="$(bash "$SEQ" --ler "$FX_ENTREGA")"
  [ -n "$seq" ] && ok "controle: sequencia-de-commits --ler lê os commits" || falha "controle: --ler vazio"
  fx_fluxo_completo "$FX_WT" && ok "fluxo na worktree vinculada" || { falha "worktree: ${FX_ERRO:-}"; cd "$REPO"; return; }
  fl_passos worktree
  [ "$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)" = "$plano" ] \
    && [ "$(git rev-parse HEAD:docs/sprintx/features/ft-rec/sprint-01/tasks.md)" = "$(git rev-parse "$FX_M:docs/sprintx/features/ft-rec/sprint-01/tasks.md")" ] \
    && ok "plano intacto (tasks.md com o mesmo hash no disco e em HEAD)" || falha "plano mudou"
  [ "$(bash "$SEQ" --ler "$FX_ENTREGA")" = "$seq" ] && ok "seq intacto (sequencia-de-commits --ler idêntico)" || falha "seq mudou"
  rc_igual "V11 OK" 0 bash "$PROVA" --verificar "$FX_ENTREGA" docs/sprintx/features/ft-rec/sprint-*/tasks.md
  [ "$(bash "$PROVA" --verificar "$FX_ENTREGA" docs/sprintx/features/ft-rec/sprint-*/tasks.md 2>/dev/null | sed -n 1p)" = V11=OK ] \
    && ok "V11=OK na primeira linha" || falha "V11 diferente de OK"
  hk="$(git rev-parse --path-format=absolute --git-path hooks)"
  [ "$hk" = "$d/.git/hooks" ] && [ -x "$hk/pre-push" ] \
    && [ ! -e "$(git rev-parse --absolute-git-dir)/hooks/pre-push" ] \
    && ok "worktree: o pre-push instalado está no diretório comum (git rev-parse --git-path hooks)" || falha "worktree: diretório efetivo $hk"
  fx_remoto_bare "$FX_WT" || { falha "remoto bare não montou"; cd "$REPO"; return; }
  case "$FX_REMOTO" in "$t"/*) ok "controle: o remoto é o bare local do temporário" ;; *) falha "remoto fora do temporário: $FX_REMOTO" ;; esac
  fl_pushes worktree "$FX_WT" "$t"
  cd "$REPO" || return
}
