# shellcheck shell=bash
#
# Parte da bancada R1: scripts/ci/test-r1-reconciliacao-base.sh a carrega com
# `.`, na ordem de definição, e roda os grupos. Esta parte só define funções e
# variáveis, e não roda sozinha. Grupos: verificar, cadeia e legado.

[ "${BASH_SOURCE[0]}" != "$0" ] || { echo "${0##*/}: parte da bancada R1; rode scripts/ci/test-r1-reconciliacao-base.sh" >&2; exit 64; }

# --- apoio do grupo verificar ------------------------------------------------

# v_ok <desc> <esperado> — `--verificar` (array `v`) com rc 0, stdout
# exatamente <esperado> e stderr vazio.
v_ok() {
  local desc="$1" esperado="$2" out rc
  out="$("${v[@]}" 2>"$VT/err")"; rc=$?
  if [ "$rc" = 0 ] && [ "$out" = "$esperado" ] && [ ! -s "$VT/err" ]; then ok "$desc"
  else falha "$desc — rc=$rc out=$(printf '%s' "$out" | tr '\n\t' '|>') err=$(tr '\n' ' ' < "$VT/err")"; fi
}

# v_motivo <desc> <rc> <código> <trecho> — `--verificar` com o rc, `ok=false`
# na primeira linha, nenhuma linha `coberto`, uma linha
# `motivo<TAB><código><TAB>...<trecho>...` e stderr vazio: um rc vindo da causa
# errada não passa.
v_motivo() {
  local desc="$1" esperado="$2" cod="$3" trecho="$4" out rc
  out="$("${v[@]}" 2>"$VT/err")"; rc=$?
  if [ "$rc" != "$esperado" ]; then falha "$desc — rc=$rc, esperava $esperado: $(printf '%s' "$out" | tr '\n\t' '|>')"; return; fi
  if [ "$(printf '%s\n' "$out" | sed -n 1p)" != ok=false ] || printf '%s\n' "$out" | grep -q '^coberto'; then
    falha "$desc — saída sem ok=false ou com coberto: $(printf '%s' "$out" | tr '\n\t' '|>')"; return
  fi
  [ -s "$VT/err" ] && { falha "$desc — stderr não vazio: $(tr '\n' ' ' < "$VT/err")"; return; }
  if printf '%s\n' "$out" | COD="$cod" TRECHO="$trecho" awk -F'\t' \
      '$1 == "motivo" && $2 == ENVIRON["COD"] && index($3, ENVIRON["TRECHO"]) { f = 1 } END { exit !f }'; then
    ok "$desc"
  else falha "$desc — sem motivo $cod com '$trecho': $(printf '%s' "$out" | tr '\n\t' '|>')"; fi
}

# _leitura — foto do que o --verificar não pode mudar: status (sem refresh
# oportunista do índice) e o índice byte a byte.
_leitura() {
  GIT_OPTIONAL_LOCKS=0 git status --porcelain=v1 -z --untracked-files=all | rb_sha256
  rb_sha256 < "$(git rev-parse --git-path index)"
}

AR=docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
AR2=docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
AR3=docs/entregas/ft-rec/RECONCILIACAO-BASE-003.md

grupo_verificar() {
  local d v out rc antes tok campo valor esperado lateral VT
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  VT="$(mktemp -d)"; TMPS+=("$VT")
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)

  # sem reconciliação nenhuma: ok, nada coberto
  v_ok "sem artefato e reconciliacoes []: ok=true sem coberto" "ok=true"
  rc_igual "--verificar recusa lista de caminhos" 64 "${v[@]}" -- "$FX_NOVO1"
  rc_igual "--verificar com --registrar é uso" 64 "${v[@]}" --registrar
  rc_igual "--verificar recusa --force" 64 "${v[@]}" --force

  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  rc_igual "verifica o registro" 0 "${v[@]}"
  [ "$("${v[@]}" | grep -c '^coberto	')" = 2 ] && ok "dois cobertos" || falha "cobertura"
  esperado="ok=true
coberto	$FX_NOVO2	001
coberto	$FX_NOVO1	001"
  v_ok "saída exata: ok=true e um coberto por caminho, com o NNN" "$esperado"

  # só leitura: nada muda (status, índice), com a trava C5 ocupada, e o
  # temporário (fora do repositório) some
  mkdir -p "$VT/tmpdir"
  antes="$(_leitura)"
  tok="$(bash "$TRAVA" --adquirir teste-r1 | sed -n 's/^token=//p')"
  [ -n "$tok" ] || falha "trava não adquirida"
  out="$(TMPDIR="$VT/tmpdir" "${v[@]}" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && ok "verifica com a trava C5 ocupada" || falha "trava ocupada: rc=$rc $out"
  bash "$TRAVA" --conferir "$tok" >/dev/null 2>&1 && ok "a trava continua de quem a tinha" || falha "a verificação mexeu na trava"
  bash "$TRAVA" --liberar "$tok" >/dev/null 2>&1
  [ "$(_leitura)" = "$antes" ] && ok "só leitura: status e índice idênticos" || falha "a verificação mudou status ou índice"
  [ -z "$(ls -A "$VT/tmpdir")" ] && ok "temporário removido (ok)" || falha "sobrou temporário: $(ls -A "$VT/tmpdir")"

  # artefato forjado: coerente, assinado, listando um caminho inelegível
  cp "$AR" "$VT/bak.md"
  fx_forja_artefato "$d" README.md || falha "forja não emitiu"
  rb_validar "$AR" ft-rec 1 && ok "forjado: assinatura e schema válidos" || falha "forjado inválido: $RB_ERRO"
  rc_igual "artefato forjado com assinatura válida não passa: prova recalculada" 4 "${v[@]}"
  v_motivo "forjado: o motivo cita a prova 1" 4 prova "prova 1: README.md"
  v_motivo "forjado: o motivo cita o inventário" 4 inventario "inventário: $FX_NOVO1"
  antes="$(_leitura)"
  TMPDIR="$VT/tmpdir" "${v[@]}" >/dev/null 2>&1
  [ "$(_leitura)" = "$antes" ] && [ -z "$(ls -A "$VT/tmpdir")" ] && ok "reprovação também é só leitura e sem temporário" || falha "reprovação deixou rastro"
  cp "$VT/bak.md" "$AR"

  # cada campo gravado é recalculado: adulterado e reassinado, reprova
  for campo in status_base blob_b1 blob_m diff_b1_m_sha256; do
    case "$campo" in
      status_base) valor='$2 = "M"'; esperado="status_base" ;;
      blob_b1) valor='$3 = "'"$(git rev-parse "$FX_M:$FX_NOVO1")"'"'; esperado="blob_b1" ;;
      blob_m) valor='$4 = "'"$(git rev-parse "$FX_B1:$FX_NOVO1")"'"'; esperado="blob_m" ;;
      diff_b1_m_sha256) valor='$5 = "'"$(printf 'outro' | rb_sha256)"'"'; esperado="diff_b1_m_sha256" ;;
    esac
    FX_FORJA_AWK='$1 == "'"$FX_NOVO1"'" { '"$valor"' } 1' fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" || falha "$campo: forja não emitiu"
    rb_validar "$AR" ft-rec 1 || falha "$campo: forja inválida: $RB_ERRO"
    if [ "$campo" = blob_m ]; then
      # HEAD com o conteúdo forjado: a cobertura não denuncia, só o recálculo
      git show "$FX_B1:$FX_NOVO1" > "$FX_NOVO1"; git commit -q -m "volta ao conteúdo da base" -- "$FX_NOVO1"
    fi
    v_motivo "$campo adulterado e reassinado reprova pelo recálculo" 4 campo "$FX_NOVO1: $esperado"
    if [ "$campo" = blob_m ]; then
      git show "$FX_M:$FX_NOVO1" > "$FX_NOVO1"; git commit -q -m "volta ao conteúdo de M" -- "$FX_NOVO1"
    fi
    cp "$VT/bak.md" "$AR"
  done
  v_ok "controle: o artefato registrado volta a verificar" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_NOVO1")"

  # cadeia e contrato
  mv "$AR" "$AR2"
  v_motivo "numeração com lacuna reprova" 5 numeracao "RECONCILIACAO-BASE-001.md"
  mv "$AR2" "$AR"
  sed 's/^anterior: null$/anterior: "RECONCILIACAO-BASE-000.md"/' "$VT/bak.md" > "$AR"
  v_motivo "anterior errado reprova" 5 contrato "anterior"
  cp "$VT/bak.md" "$AR"
  sed 's/^estado: ativa$/estado: superada/' "$VT/bak.md" > "$AR"
  v_motivo "a última reconciliação superada reprova" 5 estado "ativa"
  cp "$VT/bak.md" "$AR"
  printf 'x\n' > docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.bak
  v_motivo "nome fora do padrão na pasta da entrega reprova" 5 contrato "RECONCILIACAO-BASE-001.md.bak"
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.bak

  # coerência com o ENTREGA.md do disco
  cp "$FX_ENTREGA" "$VT/entrega.md"
  git show "HEAD:$FX_ENTREGA" > "$FX_ENTREGA"
  v_motivo "artefato fora de ENTREGA.reconciliacoes (registro interrompido) reprova" 5 orfao "artefato órfão: RECONCILIACAO-BASE-001.md"
  cp "$VT/entrega.md" "$FX_ENTREGA"
  mv "$AR" "$VT/fora.md"
  v_motivo "item de ENTREGA.reconciliacoes sem artefato reprova" 5 ausente "artefato ausente: RECONCILIACAO-BASE-001.md"
  mv "$VT/fora.md" "$AR"
  sed "s/^base_validada_sha: .*/base_validada_sha: $FX_B0/" "$VT/entrega.md" > "$FX_ENTREGA"
  v_motivo "base_validada_sha do disco diferente do b1_sha da última reprova" 5 entrega "base_validada_sha"
  sed "s/^    m_sha: .*/    m_sha: $FX_P1/" "$VT/entrega.md" > "$FX_ENTREGA"
  v_motivo "m_sha de ENTREGA.reconciliacoes diferente do artefato reprova" 5 entrega "m_sha"
  sed "s/^    b1_sha: .*/    b1_sha: $FX_B0/" "$VT/entrega.md" > "$FX_ENTREGA"
  v_motivo "b1_sha de ENTREGA.reconciliacoes diferente do artefato reprova" 5 entrega "b1_sha"
  cp "$VT/entrega.md" "$FX_ENTREGA"
  FX_ORIGEM_BASE=inferida_legado fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" || falha "forja legado não emitiu"
  # (Task 9) a origem inferida_legado passou a ser suportada: num 001 de uma
  # entrega que já tinha a base em P1 ela é forjada e reprova pela âncora
  v_motivo "origem_base inferida_legado com base_validada_sha em P1 reprova pela âncora" 5 ancora "já tem base_validada_sha"
  cp "$VT/bak.md" "$AR"

  # p1_sha e b1_sha gravados são os pais de M (forjados e reassinados; a
  # lista do ENTREGA.md acompanha o b1_sha forjado, para só a estrutura falar)
  FX_P1_SHA="$FX_B0" fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" || falha "forja do p1_sha"
  v_motivo "p1_sha diferente do primeiro pai de M reprova" 4 estrutura "estrutura[p1]"
  FX_B1_SHA="$FX_B0" fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja do b1_sha"
  v_motivo "b1_sha diferente do segundo pai de M reprova" 4 estrutura "estrutura[b1]"
  cp "$VT/bak.md" "$AR"; cp "$VT/entrega.md" "$FX_ENTREGA"

  # cobertura por conteúdo E modo: virar executável depois de M descobre
  git update-index --chmod=+x "$FX_NOVO1"; git commit -q -m "NOVO1 executável"
  v_motivo "reconciliado com modo mudado depois de M deixa de estar coberto" 4 cobertura "$FX_NOVO1: o modo"
  git update-index --chmod=-x "$FX_NOVO1"; git commit -q -m "NOVO1 volta a 100644"
  v_ok "controle: modo de volta ao de M" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_NOVO1")"
  v_ok "controle: verifica de novo depois das reprovações" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_NOVO1")"

  # reconciliado alterado depois de M deixa de estar coberto
  echo "// depois de M" >> "$FX_NOVO1"; git commit -qam "mexe depois de M"
  rc_igual "reconciliado alterado depois de M deixa de estar coberto" 4 "${v[@]}"
  v_motivo "alterado depois de M: o motivo é a cobertura" 4 cobertura "$FX_NOVO1"
  git rm -q --cached "$FX_NOVO1" >/dev/null; rm -f "$FX_NOVO1"; git commit -q -m "remove o reconciliado"
  v_motivo "reconciliado ausente em HEAD não está coberto" 4 cobertura "$FX_NOVO1"
  cd "$REPO" || return

  # âncora: o b0_sha do 001 é a base_validada_sha da entrega em P1 (antes do
  # merge; a variante grava B1 num commit da feature logo antes do merge)
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=b0_fora_p1 fx_cenario "$d" || { falha "variante b0_fora_p1 não montou"; return; }
  cd "$d" || return
  fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja da âncora"
  v_motivo "b0_sha do 001 diferente da base_validada_sha de P1 reprova" 5 ancora "base_validada_sha"
  cd "$REPO" || return

  # M fora da linha de primeiro pai de HEAD
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=fora_primeiro_pai fx_cenario "$d" || { falha "variante fora_primeiro_pai não montou"; return; }
  cd "$d" || return
  lateral="$(git rev-parse HEAD^2)"
  fx_emite_reconciliacao "$d" 1 "$FX_B0" "$lateral" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja do lateral"
  v_motivo "m_sha fora da linha de primeiro pai de HEAD reprova" 4 estrutura "estrutura[primeiro_pai]"
  git branch -q lateral "$lateral"
  v_motivo "m_sha na linha de primeiro pai de outra ref (não HEAD) reprova" 4 estrutura "estrutura[primeiro_pai]"
  cd "$REPO" || return

  # caminho com espaço, acento e apóstrofo (core.quotepath true no repositório)
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=caminho_especial fx_cenario "$d" || { falha "variante caminho_especial não montou"; return; }
  cd "$d" || return
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" "$FX_ESPECIAL" >/dev/null 2>&1 \
    || falha "registro do caminho especial"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_ESPECIAL" "$FX_NOVO1")"
  v_ok "caminho especial coberto exatamente, sem escape" "$esperado"
  cd "$REPO" || return

  # cadeia 001 -> 002 (dois merges de base)
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "emissão do 002"
  fx_entrega_sincroniza "$d" || falha "sincronização do ENTREGA.md"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
  v_ok "cadeia 001 -> 002 verifica; NOVO3 coberto pelo 002" "$esperado"
  cp "$AR" "$VT/c1.md"; cp "$AR2" "$VT/c2.md"
  sed 's/^estado: superada$/estado: ativa/' "$VT/c1.md" > "$AR"
  v_motivo "cadeia: 001 ativa com 002 depois reprova" 5 estado "superada"
  cp "$VT/c1.md" "$AR"
  sed 's/^anterior: .*/anterior: null/' "$VT/c2.md" > "$AR2"
  v_motivo "cadeia: anterior do 002 errado reprova" 5 contrato "anterior"
  cp "$VT/c2.md" "$AR2"
  fx_emite_reconciliacao "$d" 2 "$FX_B0" "$FX_M2" "$FX_NOVO3" || falha "emissão do 002 com b0 = B0"
  v_motivo "cadeia: b0_sha do 002 diferente do b1_sha do 001 reprova" 5 cadeia "b0_sha"
  cp "$VT/c2.md" "$AR2"
  mv "$AR" "$VT/fora.md"
  v_motivo "cadeia: sem o 001 a numeração tem lacuna" 5 numeracao "RECONCILIACAO-BASE-001.md"
  mv "$VT/fora.md" "$AR"
  v_ok "cadeia: controle depois das reprovações" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
  cd "$REPO" || return

  # cadeia em que o 002 reconcilia de novo um caminho do 001: vale o blob_m da
  # reconciliação mais recente que o lista
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" reajusta || { falha "segunda base (reajusta) não montou"; return; }
  cd "$d" || return
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" "$FX_NOVO1" || falha "emissão do 002"
  fx_entrega_sincroniza "$d" || falha "sincronização do ENTREGA.md"
  [ "$(git rev-parse "HEAD:$FX_NOVO1")" != "$(git rev-parse "$FX_M:$FX_NOVO1")" ] || falha "NOVO1 não mudou em M2"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t002\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
  v_ok "cadeia: caminho reconciliado de novo é coberto pela mais recente" "$esperado"
  cd "$REPO" || return

  # o plano de cada reconciliação é o da árvore do M dela: um commit de plano
  # entre M1 e M2 que declara NOVO3 vale para o 002
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  sed 's|altera: \[src/painel.ts\]|altera: [src/painel.ts, tests/ui/frequency-ksmv-primitives.test.tsx]|' \
    docs/sprintx/features/ft-rec/sprint-01/tasks.md > "$VT/tasks.md" && cat "$VT/tasks.md" > docs/sprintx/features/ft-rec/sprint-01/tasks.md
  git commit -q -m "docs: o plano declara a primitiva de frequencia" -- docs/sprintx/features/ft-rec/sprint-01/tasks.md
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "emissão do 002"
  fx_entrega_sincroniza "$d" || falha "sincronização do ENTREGA.md"
  v_motivo "cadeia: prova 3 do 002 usa o plano da árvore de M2" 4 prova "RECONCILIACAO-BASE-002.md: prova 3: $FX_NOVO3"
  cd "$REPO" || return

  # inventário da cadeia: caminho do 001 só passa sem relistagem se a base não
  # o tocou entre b0 e b1 do 002 E M2 tem o blob_m do 001
  local modo
  for modo in descarta ressuscita esconde; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
    fx_segunda_base "$d" "$modo" || { falha "segunda base ($modo) não montou"; continue; }
    cd "$d" || return
    FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "$modo: emissão do 001"
    fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "$modo: emissão do 002"
    fx_entrega_sincroniza "$d" || falha "$modo: sincronização"
    case "$modo" in
      descarta)
        v_motivo "cadeia: M2 descarta a mudança da base num caminho do 001 sem relistar" 4 inventario "RECONCILIACAO-BASE-002.md: inventário: $FX_NOVO1" ;;
      ressuscita)
        v_motivo "cadeia: M2 ressuscita caminho do 001 que a base removeu" 4 inventario "RECONCILIACAO-BASE-002.md: inventário: $FX_NOVO1" ;;
      esconde)
        # mesmo depois de HEAD voltar ao blob_m do 001, o M2 mudou o caminho sem declarar
        git show "$FX_M:$FX_NOVO2" > "$FX_NOVO2"; git commit -q -m "volta NOVO2" -- "$FX_NOVO2"
        v_motivo "cadeia: M2 muda caminho do 001 (base não tocou), revertido depois" 4 inventario "RECONCILIACAO-BASE-002.md: inventário: $FX_NOVO2" ;;
    esac
    cd "$REPO" || return
  done

  # o merge de integração não pode reescrever o ENTREGA.md (âncora em P1)
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=entrega_no_merge fx_cenario "$d" || { falha "variante entrega_no_merge não montou"; return; }
  cd "$d" || return
  fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja entrega_no_merge"
  v_motivo "merge que reescreve o ENTREGA.md reprova (estrutura[entrega])" 4 estrutura "estrutura[entrega]"
  cd "$REPO" || return

  # ordem dos M, isolada: 001 aponta m1 (posterior), 002 aponta m2 (anterior);
  # tudo o mais confere (CAD, âncora, estrutura, inventário)
  local idx tree0 m0 by m2o m1o
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  idx="$VT/idx-ordem"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" git read-tree "$FX_M"
  GIT_INDEX_FILE="$idx" git update-index --cacheinfo "100644,$(git rev-parse "$FX_B1:$FX_NOVO1"),$FX_NOVO1" \
    --cacheinfo "100644,$(git rev-parse "$FX_B1:$FX_NOVO2"),$FX_NOVO2"
  tree0="$(GIT_INDEX_FILE="$idx" git write-tree)"
  m0="$(printf 'merge sem ajuste\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_B1" | git commit-tree "$tree0" -p "$FX_P1" -p "$FX_B1")"
  by="$(printf 'base sem mudanca\n' | git commit-tree "$FX_B1^{tree}" -p "$FX_B1")"
  m2o="$(printf 'merge\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$by" | git commit-tree "$tree0" -p "$m0" -p "$by")"
  m1o="$(printf 'merge de novo\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_B1" | git commit-tree "$tree0" -p "$m2o" -p "$FX_B1")"
  git update-ref refs/heads/feature/ft-rec "$m1o"
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$m1o" || falha "ordem: emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$m2o" || falha "ordem: emissão do 002"
  fx_entrega_sincroniza "$d" || falha "ordem: sincronização"
  v_motivo "cadeia fora de ordem na linha de primeiro pai reprova" 5 cadeia "não é posterior"
  out="$("${v[@]}" 2>/dev/null)"
  [ "$(printf '%s\n' "$out" | grep -c '^motivo')" = 1 ] && ok "ordem: é o único motivo" || falha "ordem: outros motivos: $(printf '%s' "$out" | tr '\n\t' '|>')"
  cd "$REPO" || return
}

# --- apoio do grupo cadeia ---------------------------------------------------

# _sem_estado <artefato> — o artefato sem a linha `estado:` de topo
_sem_estado() { grep -v '^estado: ' "$1"; }

# _instantaneo — bytes, inode e mtime (ns) do ENTREGA.md e dos artefatos, e a
# lista da pasta da entrega: uma reexecução noop não pode mudar nada disso.
_instantaneo() {
  ls -A docs/entregas/ft-rec
  for f in "$FX_ENTREGA" docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md; do
    [ -e "$f" ] || continue
    printf '%s %s %s\n' "$(rb_sha256 < "$f")" "$(stat -c '%i %y' "$f")" "$f"
  done
}

grupo_cadeia() {
  local d r v out c t lido tt esperado caso antes ls_antes x m2x lateral pid i
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")

  # ---- cadeia 001 -> 002 sem commit entre os registros (brief) -------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d"; fx_segunda_base "$d"; cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  rc_igual "registra M1 com HEAD em M2" 0 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  { grep -q "^m_sha: $FX_M\$" "$AR" && grep -q "^b1_sha: $FX_B1\$" "$AR"; } \
    && ok "o 001 registra o M informado (M1), não HEAD" || falha "001: m_sha/b1_sha não são os de M1"
  cp "$AR" "$t/a1.md"; cp "$FX_ENTREGA" "$t/e1.md"

  # o ENTREGA.md do disco só pode diferir do de M nas chaves que o registro
  # grava, e com os valores que a cadeia verificada implica
  for caso in pr_url corpo portao atualizado base; do
    case "$caso" in
      pr_url) sed 's|^pr_url: null$|pr_url: https://exemplo.invalid/pr/1|' "$t/e1.md" > "$FX_ENTREGA" ;;
      corpo) { cat "$t/e1.md"; printf '\nNota local.\n'; } > "$FX_ENTREGA" ;;
      portao) sed 's/^portao: null$/portao: pronto/' "$t/e1.md" > "$FX_ENTREGA" ;;
      atualizado) sed 's/^atualizado_em: .*/atualizado_em: ontem/' "$t/e1.md" > "$FX_ENTREGA" ;;
      base) sed "s/^base_validada_sha: .*/base_validada_sha: $FX_B0/" "$t/e1.md" > "$FX_ENTREGA" ;;
    esac
    cmp -s "$FX_ENTREGA" "$t/e1.md" && falha "disco ($caso): a edição não pegou"
    case "$caso" in
      pr_url) reprova "disco: chave fora das gravadas difere de M" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" -- ;;
      corpo) reprova "disco: corpo difere de M" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" -- ;;
      portao) reprova "disco: portao com valor que a cadeia não implica" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" -- ;;
      atualizado) reprova "disco: atualizado_em fora de AAAA-MM-DD" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" -- ;;
      base) reprova "disco: base_validada_sha diferente do b1_sha da última" 5 "base_validada_sha" --merge "$FX_M2" -- ;;
    esac
  done
  cp "$t/e1.md" "$FX_ENTREGA"

  rc_igual "registra M2 sem arquivos" 0 "${r[@]}" --merge "$FX_M2" --
  rc_igual "cadeia 001→002 verifica" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  grep -q '^estado: superada' docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md && ok "001 superada" || falha "001 não superada"
  grep -q "^b0_sha: $FX_B1" docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md && ok "002 encadeia em B1" || falha "encadeamento"
  grep -q '^arquivos: \[\]' docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md && ok "002 com arquivos: []" || falha "lista vazia"
  lido="$(rb_ler "$AR2")"
  for tt in "anterior	RECONCILIACAO-BASE-001.md" "origem_base	reconciliacao_anterior" "estado	ativa" "numero	2" \
            "p1_sha	$FX_M" "b1_sha	$FX_B2" "m_sha	$FX_M2" "branch	feature/ft-rec"; do
    printf '%s\n' "$lido" | grep -Fxq "escalar	$tt" && ok "002: $tt" || falha "002: escalar ${tt%%	*} divergente"
  done
  rb_validar "$AR2" ft-rec 2 && ok "002 válido" || falha "002 inválido: $RB_ERRO"
  rb_validar "$AR" ft-rec 1 && ok "001 superada continua com assinatura válida" || falha "001 superada inválida: $RB_ERRO"
  { grep -q '^estado: ativa$' "$t/a1.md" && [ "$(_sem_estado "$AR")" = "$(_sem_estado "$t/a1.md")" ]; } \
    && ok "001: só a linha estado mudou (ativa -> superada)" || falha "001 mudou além do estado"
  [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B2" ] && ok "ENTREGA: base validada avança para B2" || falha "ENTREGA: base_validada_sha"
  esperado="reconciliacoes:
  - numero: 1
    arquivo: RECONCILIACAO-BASE-001.md
    b1_sha: $FX_B1
    m_sha: $FX_M
  - numero: 2
    arquivo: RECONCILIACAO-BASE-002.md
    b1_sha: $FX_B2
    m_sha: $FX_M2"
  [ "$(awk '/^reconciliacoes:/ { f = 1; print; next } f && /^[ \t]/ { print; next } f { exit }' "$FX_ENTREGA")" = "$esperado" ] \
    && ok "ENTREGA: reconciliacoes com 001 e 002, na ordem" || falha "ENTREGA: bloco reconciliacoes divergente"
  entrega_confere "cadeia" "$t/e1.md" "$FX_ENTREGA" $GRAVADAS
  [ "$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort)" = " M $FX_ENTREGA
?? $AR
?? $AR2" ] && ok "cadeia: só ENTREGA.md e os dois artefatos na árvore" || falha "cadeia: status inesperado"
  rc_igual "registrar M1 de novo depois de M2 reprova" 5 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  rc_motivo "M1 depois de M2: o motivo é a reconciliação já registrada" 5 "anterior à última" \
    "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"

  # reexecução idempotente do último M: noop, nada gravado
  antes="$(_instantaneo)"
  out="$("${r[@]}" --merge "$FX_M2" -- 2>&1)"; c=$?
  { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ]; } \
    && ok "reexecução do último M com a mesma lista: rc 0 e noop=true" || falha "noop: rc=$c $out"
  [ "$(_instantaneo)" = "$antes" ] && ok "noop: artefatos e ENTREGA.md intactos (bytes, inode, mtime)" || falha "noop gravou"
  out="$("${r[@]}" -- 2>&1)"; c=$?
  { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ]; } \
    && ok "sem --merge (M = HEAD = M2): noop" || falha "noop sem --merge: rc=$c $out"
  [ "$(_instantaneo)" = "$antes" ] && ok "noop sem --merge: nada gravado" || falha "noop sem --merge gravou"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "noop: trava livre" || falha "noop: trava presa"
  reprova "mesmo M com outra lista reprova" 5 "outra lista" --merge "$FX_M2" -- "$FX_NOVO3"
  # o noop nunca mascara edição alheia no ENTREGA.md do disco
  cp "$FX_ENTREGA" "$t/e2.md"
  sed 's|^pr_url: null$|pr_url: https://exemplo.invalid/pr/1|' "$t/e2.md" > "$FX_ENTREGA"
  reprova "noop com pr_url editado no disco" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" --
  sed 's/^portao: null$/portao: pronto/' "$t/e2.md" > "$FX_ENTREGA"
  reprova "noop com portao: pronto no disco" 3 "ENTREGA.md com alteração não commitada" --merge "$FX_M2" --
  cp "$t/e2.md" "$FX_ENTREGA"

  mv docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md docs/entregas/ft-rec/RECONCILIACAO-BASE-003.md
  rc_igual "lacuna na numeração reprova" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  mv docs/entregas/ft-rec/RECONCILIACAO-BASE-003.md docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  sed -i 's/^anterior: .*/anterior: null/' docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  rc_igual "anterior errado reprova" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  cd "$REPO" || return

  # ---- 001: a mesma lista em outra ordem é noop; outra lista, rc 5 ---------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  antes="$(_instantaneo)"
  out="$("${r[@]}" -- "$FX_NOVO2" "$FX_NOVO1" 2>&1)"; c=$?
  { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ]; } \
    && ok "001: mesma lista em outra ordem é noop" || falha "001 noop: rc=$c $out"
  [ "$(_instantaneo)" = "$antes" ] && ok "001 noop: nada gravado" || falha "001 noop gravou"
  reprova "001: mesmo M com lista menor reprova" 5 "outra lista" -- "$FX_NOVO1"
  cd "$REPO" || return

  # ---- ordem: o merge mais antigo ainda não registrado vem primeiro ---------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  reprova "M2 (--merge) antes de M1 reprova pela ordem" 5 "não é o merge mais antigo ainda não registrado" --merge "$FX_M2" -- "$FX_NOVO3"
  reprova "M2 (HEAD) antes de M1 reprova pela ordem" 5 "não é o merge mais antigo ainda não registrado" -- "$FX_NOVO3"
  rc_igual "--merge sem valor é uso" 64 "${r[@]}" --merge
  rc_igual "--merge com nome de ref é uso" 64 "${r[@]}" --merge main -- "$FX_NOVO1" "$FX_NOVO2"
  reprova "--merge com SHA inexistente" 4 "estrutura[m]" --merge 0000000000000000000000000000000000000000 -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "--verificar não aceita --merge" 64 "${v[@]}" --merge "$FX_M"
  rc_igual "--merge abreviado registra o M1" 0 "${r[@]}" --merge "$(git rev-parse --short=12 "$FX_M")" -- "$FX_NOVO1" "$FX_NOVO2"
  grep -q "^m_sha: $FX_M\$" "$AR" && ok "--merge abreviado: m_sha com 40 hex" || falha "--merge abreviado: m_sha"
  rc_igual "depois do M1, o M2 (HEAD) registra" 0 "${r[@]}" -- "$FX_NOVO3"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
  [ "$("${v[@]}" 2>&1)" = "$esperado" ] && ok "cadeia em ordem verifica; NOVO3 coberto pelo 002" || falha "verificação da cadeia em ordem: $("${v[@]}" 2>&1 | tr '\n\t' '|>')"
  cd "$REPO" || return

  # --merge fora da linha de primeiro pai de HEAD (guarda EST)
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=fora_primeiro_pai fx_cenario "$d" || { falha "variante fora_primeiro_pai não montou"; return; }
  cd "$d" || return
  lateral="$(git rev-parse HEAD^2)"
  reprova "--merge fora da linha de primeiro pai de HEAD" 4 "estrutura[primeiro_pai]" --merge "$lateral" -- "$FX_NOVO1" "$FX_NOVO2"
  # fora da linha e sem o ENTREGA.md: a linha de primeiro pai fala antes
  reprova "--merge de B1 (sem ENTREGA.md) dá estrutura[primeiro_pai]" 4 "estrutura[primeiro_pai]" --merge "$FX_B1" -- "$FX_NOVO1" "$FX_NOVO2"
  x="$(printf 'pr auxiliar\n' | git commit-tree "$FX_B1^{tree}" -p "$FX_B1")"
  m2x="$(printf 'Merge pull request #7 from outra/branch\n' | git commit-tree "$FX_B1^{tree}" -p "$FX_B1" -p "$x")"
  reprova "--merge de um merge de PR na main dá estrutura[primeiro_pai]" 4 "estrutura[primeiro_pai]" --merge "$m2x" -- "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # um merge que não é de integração trava a fila: a mensagem o nomeia
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  x="$(printf 'auxiliar\n' | git commit-tree "$FX_M^{tree}" -p "$FX_M")"
  m2x="$(printf 'merge: traz a branch auxiliar\n\nTrabalho: ft-rec\n' | git commit-tree "$FX_M^{tree}" -p "$FX_M" -p "$x")"
  lateral="$(printf 'merge: integra a main de novo\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_B1" | git commit-tree "$FX_M^{tree}" -p "$m2x" -p "$FX_B1")"
  git update-ref refs/heads/feature/ft-rec "$lateral"
  reprova "merge sem Integra-base na fila: a ordem cita o SHA dele" 5 "o merge $m2x" --
  reprova "merge sem Integra-base na fila: precisa ser registrado ou resolvido" 5 "precisa ser registrado ou resolvido antes" --
  cd "$REPO" || return

  # M^2 do merge seguinte não descende do b1_sha da última reconciliação
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  x="$(printf 'base paralela\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  m2x="$(printf 'merge: integra a base paralela\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$x" | git commit-tree "$FX_M^{tree}" -p "$FX_M" -p "$x")"
  git update-ref refs/heads/feature/ft-rec "$m2x"
  reprova "M^2 que não descende do b1_sha da última reprova pela ordem" 5 "não descende do b1_sha" --
  cd "$REPO" || return

  # ---- órfão de registro interrompido -------------------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "emissão do órfão"
  reprova "artefato órfão reprova com instrução" 5 \
    "artefato órfão de registro interrompido: RECONCILIACAO-BASE-002.md; remova-o e registre de novo" -- "$FX_NOVO3"
  rm -f "$AR2"
  rc_igual "removido o órfão, o M2 registra" 0 "${r[@]}" -- "$FX_NOVO3"
  cd "$REPO" || return

  # ---- antes do ponto de commit (o mv do ENTREGA.md): SIGTERM desfaz tudo --
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  mkdir -p "$t/shim-lento"
  _shim_bloqueio "$t/shim-lento/mv" '*/ENTREGA.md|ENTREGA.md' antes "$t/marca-janela"
  cp "$AR" "$t/janela-a1.md"; cp "$FX_ENTREGA" "$t/janela-e.md"; ls_antes="$(ls -A docs/entregas/ft-rec)"; antes="$(_foto)"
  local tdj; tdj="$(mktemp -d)"; TMPS+=("$tdj")
  env TMPDIR="$tdj" PATH="$t/shim-lento:$PATH" "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1 &
  pid=$!
  _espera_ponto "$pid" "$t/marca-janela" "janela"
  [ -e "$AR2" ] && ok "janela: 002 emitido, antes do mv do ENTREGA.md" || falha "janela: o registro não chegou à janela"
  _interrompe "$pid" TERM "$t/marca-janela" "janela"
  [ ! -e "$AR2" ] && ok "janela: nenhum 002" || falha "janela: ficou o 002"
  cmp -s "$AR" "$t/janela-a1.md" && ok "janela: 001 intacta (ativa)" || falha "janela: 001 mudou"
  cmp -s "$FX_ENTREGA" "$t/janela-e.md" && ok "janela: ENTREGA.md intacto" || falha "janela: ENTREGA.md mudou"
  [ "$(ls -A docs/entregas/ft-rec)" = "$ls_antes" ] && ok "janela: nenhum temporário na pasta da entrega" || falha "janela: sobra: $(ls -A docs/entregas/ft-rec | tr '\n' ' ')"
  [ "$(_foto)" = "$antes" ] && ok "janela: árvore como antes" || falha "janela: árvore mudou"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "janela: trava livre" || falha "janela: trava presa"
  [ -z "$(ls -A "$tdj")" ] && ok "janela: temporário do registro removido" || falha "janela: sobrou temporário: $(ls -A "$tdj" | tr '\n' ' ')"
  rc_igual "janela: sem o shim, o M2 registra" 0 "${r[@]}" -- "$FX_NOVO3"
  cd "$REPO" || return

  # ---- depois do ponto de commit: o registro fica efetivado; o anterior ainda
  # `ativa` é resíduo detectável, que o --registrar do mesmo M completa ------
  #   g2:    SIGTERM logo depois do rename do ENTREGA.md (mv real, depois dorme)
  #   term:  SIGTERM com o mv do anterior parado
  #   kill:  SIGKILL do grupo de processos com o mv do anterior parado
  #   falha: o mv do anterior falha
  local modo_int real_mv tdi
  real_mv="$(command -v mv)"
  for modo_int in g2 term kill falha; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
    fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
    cd "$d" || return
    "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "$modo_int: registro do 001"
    cp "$FX_ENTREGA" "$t/int-e0.md"; cp "$AR" "$t/int-a1.md"
    mkdir -p "$t/shim-$modo_int"
    case "$modo_int" in
      g2) _shim_bloqueio "$t/shim-$modo_int/mv" '*/ENTREGA.md|ENTREGA.md' depois "$t/marca-$modo_int" ;;
      term|kill) _shim_bloqueio "$t/shim-$modo_int/mv" '*/RECONCILIACAO-BASE-001.md' antes "$t/marca-$modo_int" ;;
      falha) printf '#!/usr/bin/env bash\nfor a in "$@"; do ultimo="$a"; done\ncase "$ultimo" in */RECONCILIACAO-BASE-001.md) echo "mv: recusado de propósito" >&2; exit 1 ;; esac\nexec %s "$@"\n' "$real_mv" > "$t/shim-$modo_int/mv"
        chmod +x "$t/shim-$modo_int/mv" ;;
    esac
    # o temporário do registro fica num TMPDIR do teste: o SIGKILL impede o
    # encerrar do script de removê-lo, e a limpeza da suíte o remove
    tdi="$(mktemp -d)"; TMPS+=("$tdi")
    if [ "$modo_int" = falha ]; then
      out="$(env TMPDIR="$tdi" PATH="$t/shim-$modo_int:$PATH" "${r[@]}" -- "$FX_NOVO3" 2>&1 >/dev/null)"; c=$?
      { [ "$c" = 1 ] && case "$out" in *"registro efetivado"*"rode --registrar de novo"*) true ;; *) false ;; esac; } \
        && ok "falha: mv do anterior falha depois do ponto de commit: rc 1 e instrução" || falha "falha: rc=$c $out"
    else
      if [ "$modo_int" = kill ]; then
        setsid env TMPDIR="$tdi" PATH="$t/shim-$modo_int:$PATH" "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1 &
      else
        env TMPDIR="$tdi" PATH="$t/shim-$modo_int:$PATH" "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1 &
      fi
      pid=$!
      _espera_ponto "$pid" "$t/marca-$modo_int" "$modo_int"
      { [ -e "$AR2" ] && ! cmp -s "$FX_ENTREGA" "$t/int-e0.md"; } && ok "$modo_int: chegou depois do ponto de commit" || falha "$modo_int: não chegou ao ponto de commit"
      if [ "$modo_int" = kill ]; then _interrompe "$pid" KILL "$t/marca-$modo_int" "$modo_int"; else _interrompe "$pid" TERM "$t/marca-$modo_int" "$modo_int"; fi
      # SIGKILL deixa a trava C5 órfã: liberá-la é decisão humana
      [ "$modo_int" = kill ] && rm -rf "$(bash "$TRAVA" --caminho | sed 's/^trava=//')"
    fi
    # o temporário do registro: só o SIGKILL o deixa, e dentro do TMPDIR do
    # teste (nunca em /tmp); nos demais modos o encerrar o removeu
    if [ "$modo_int" = kill ]; then
      [ "$(find "$tdi" -mindepth 1 -maxdepth 1 -name 'mergex-reconciliacao.*' | wc -l)" = 1 ] \
        && ok "kill: a sobra do temporário ficou no TMPDIR do teste" || falha "kill: temporário fora do TMPDIR do teste: $(ls -A "$tdi" | tr '\n' ' ')"
    else
      [ -z "$(ls -A "$tdi")" ] && ok "$modo_int: temporário do registro removido" || falha "$modo_int: sobrou temporário: $(ls -A "$tdi" | tr '\n' ' ')"
    fi
    { [ -e "$AR2" ] && grep -q '^    arquivo: RECONCILIACAO-BASE-002.md$' "$FX_ENTREGA" && [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B2" ] \
      && rb_validar "$AR2" ft-rec 2; } && ok "$modo_int: registro efetivado (002 e ENTREGA.md coerentes)" || falha "$modo_int: registro desfeito ou incoerente"
    cmp -s "$AR" "$t/int-a1.md" && ok "$modo_int: o 001 continua ativa, intacto" || falha "$modo_int: o 001 mudou"
    if [ "$modo_int" = kill ]; then
      ls docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.superada.* >/dev/null 2>&1 && ok "kill: sobra .superada.<pid>" || falha "kill: sem a sobra"
    else
      ls docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.superada.* >/dev/null 2>&1 && falha "$modo_int: sobrou temporário do anterior" || ok "$modo_int: sem temporário do anterior"
    fi
    ls docs/entregas/ft-rec/ENTREGA.md.registro.* >/dev/null 2>&1 && falha "$modo_int: sobrou ENTREGA.md.registro" || ok "$modo_int: sem ENTREGA.md.registro"
    bash "$TRAVA" --status >/dev/null 2>&1 && ok "$modo_int: trava livre" || falha "$modo_int: trava presa"
    out="$("${v[@]}" 2>&1)"; c=$?
    { [ "$c" = 5 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = ok=false ] && ! printf '%s\n' "$out" | grep -q '^coberto' \
      && printf '%s\n' "$out" | grep -q 'registro interrompido: rode --registrar de novo com o mesmo --merge/M'; } \
      && ok "$modo_int: --verificar dá rc 5 'registro interrompido'" || falha "$modo_int: --verificar rc=$c $(printf '%s' "$out" | tr '\n\t' '|>')"
    reprova "$modo_int: outro M com o resíduo não registra" 5 "registro interrompido" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
    out="$("${r[@]}" -- "$FX_NOVO3" 2>&1)"; c=$?
    { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ] && printf '%s\n' "$out" | grep -Fxq completado=superada; } \
      && ok "$modo_int: o --registrar do mesmo M completa (noop=true, completado=superada)" || falha "$modo_int: completar rc=$c $(printf '%s' "$out" | tr '\n' '|')"
    { grep -q '^estado: superada$' "$AR" && [ "$(_sem_estado "$AR")" = "$(_sem_estado "$t/int-a1.md")" ] && rb_validar "$AR" ft-rec 1; } \
      && ok "$modo_int: 001 superada, só a linha estado mudou" || falha "$modo_int: 001 depois de completar"
    ls docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.superada.* >/dev/null 2>&1 && falha "$modo_int: a sobra ficou" || ok "$modo_int: nenhuma sobra"
    esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
    [ "$("${v[@]}" 2>&1)" = "$esperado" ] && ok "$modo_int: depois de completar, a cadeia verifica" || falha "$modo_int: $("${v[@]}" 2>&1 | tr '\n\t' '|>')"
    out="$("${r[@]}" -- "$FX_NOVO3" 2>&1)"
    { [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ] && ! printf '%s\n' "$out" | grep -q '^completado='; } \
      && ok "$modo_int: reexecução seguinte é noop puro" || falha "$modo_int: noop depois: $(printf '%s' "$out" | tr '\n' '|')"
    cd "$REPO" || return
  done

  # ---- o resíduo é reconhecido pela estrutura, nunca pelo texto ------------
  local frase='registro interrompido: rode --registrar de novo com o mesmo --merge/M' err
  # X1b/X1c/X2b: cadeia 001 -> 002 completa; o 001 traz a frase num valor
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "X: registro do 001"
  "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1 || falha "X: registro do 002"
  cp "$AR" "$t/x-a1.md"; cp "$AR2" "$t/x-a2.md"
  sed "s|^estado: superada\$|estado: $frase|" "$t/x-a1.md" > "$AR"
  reprova "X1b: 001 com a frase no estado não completa (cadeia ilegível)" 5 "cadeia ilegível: RECONCILIACAO-BASE-001.md" -- "$FX_NOVO3"
  sed "s|^expx_tool: sprintx\$|expx_tool: $frase|" "$t/x-a1.md" > "$AR"
  reprova "X1c: 001 com a frase no expx_tool não completa" 5 "cadeia ilegível: RECONCILIACAO-BASE-001.md" -- "$FX_NOVO3"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" README.md || falha "X2: forja do 002"
  sed "s|^estado: superada\$|estado: $frase|" "$t/x-a1.md" > "$AR"
  reprova "X2b: 002 forjado com README + 001 com a frase: rc da falha real" 5 "cadeia ilegível: RECONCILIACAO-BASE-001.md" -- "$FX_NOVO3" README.md
  rc_igual "X2b: --verificar reprova" 5 "${v[@]}"
  cp "$t/x-a1.md" "$AR"; cp "$t/x-a2.md" "$AR2"
  # sufixo não numérico não é sobra: o registro recusa a pasta suja (3) e a
  # verificação, o nome fora do padrão (5)
  cp "$AR" "$AR.superada.12a"
  reprova "sobra com sufixo não numérico não é sobra (registro)" 3 "RECONCILIACAO-BASE-001.md.superada.12a" -- "$FX_NOVO3"
  out="$("${v[@]}" 2>&1)"; c=$?
  { [ "$c" = 5 ] && printf '%s\n' "$out" | grep -q 'RECONCILIACAO-BASE-001.md.superada.12a: nome fora do padrão'; } \
    && ok "sobra com sufixo não numérico não é sobra (verificar: nome fora do padrão)" || falha "sufixo não numérico: rc=$c $(printf '%s' "$out" | tr '\n\t' '|>')"
  rm -f "$AR.superada.12a"
  # só a sobra, com a penúltima já superada: não é resíduo de registro
  # interrompido (falta a penúltima ativa) e nada a remove sozinho
  cp "$AR" "$AR.superada.777"
  reprova "só a sobra (penúltima já superada): rc 5, nada completado" 5 "a cadeia de reconciliações existente não verifica" -- "$FX_NOVO3"
  [ -f "$AR.superada.777" ] && ok "só a sobra: ela continua lá" || falha "só a sobra: foi removida"
  rm -f "$AR.superada.777"
  cd "$REPO" || return

  # resíduo legítimo (o mv do anterior falha depois do ponto de commit)
  # combinado com outra falha: nunca completa
  _residuo() { # <dir>
    fx_cenario "$1" && fx_segunda_base "$1" ajusta && cd "$1" || return 1
    "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || return 1
    env PATH="$t/shim-falha:$PATH" "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1
    [ -e "$AR2" ] && grep -q '^estado: ativa$' "$AR"
  }
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" README.md || falha "resíduo+prova: forja do 002"
  reprova "resíduo + prova reprovada no 002: rc 4, sem conclusão" 4 "prova 1: README.md" -- "$FX_NOVO3" README.md
  grep -q '^estado: ativa$' "$AR" && ok "resíduo + prova: o 001 continua ativa" || falha "resíduo + prova: o 001 mudou"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  sed -i 's/^estado: ativa$/estado: quebrado/' "$AR2"
  reprova "resíduo + última ilegível: rc 5 cadeia ilegível, sem conclusão" 5 "cadeia ilegível: RECONCILIACAO-BASE-002.md" -- "$FX_NOVO3"
  cd "$REPO" || return
  # X9: resíduo + a frase num campo não assinado da última que só a
  # verificação lê (branch): o artefato é lido, mas a falha não é resíduo
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  sed -i "s|^branch: .*|branch: \"$frase\"|" "$AR2"
  rb_validar "$AR2" ft-rec 2 || falha "X9: o 002 com a frase no branch deveria continuar válido: $RB_ERRO"
  reprova "X9: resíduo + frase no branch da última: rc 5, sem conclusão" 5 "branch ($frase) diverge de ENTREGA.branch" -- "$FX_NOVO3"
  grep -q '^estado: ativa$' "$AR" && ok "X9: o 001 continua ativa" || falha "X9: o 001 mudou"
  cd "$REPO" || return
  # X7: sobra rastreada nunca é removida pelo registro. O commit da sobra tira
  # HEAD do merge: o registro roda com --merge M2, o mesmo M da última, para
  # chegar à conclusão; a cadeia a reprova (não é resíduo) antes dela.
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  printf 'commitada\n' > "$AR.superada.99"
  git add -f -- "$AR.superada.99" && git commit -q -m "sobra commitada" -- "$AR.superada.99" || falha "X7: commit da sobra"
  cp "$AR" "$t/x7-a1.md"
  reprova "X7: sobra rastreada (--merge M2): rc 5 pela cadeia, nada removido" 5 \
    "cadeia existente: RECONCILIACAO-BASE-001.md.superada.99: sobra rastreada: RECONCILIACAO-BASE-001.md.superada.99; remova-a com um commit" --merge "$FX_M2" -- "$FX_NOVO3"
  { [ -f "$AR.superada.99" ] && [ "$(cat "$AR.superada.99")" = commitada ] && ! git status --porcelain=v1 | grep -q '^ D'; } \
    && ok "X7: a sobra rastreada ficou, intacta, sem ' D'" || falha "X7: a sobra rastreada foi removida ou mudou"
  { grep -q '^estado: ativa$' "$AR" && cmp -s "$AR" "$t/x7-a1.md"; } && ok "X7: o 001 continua ativa, intacto" || falha "X7: o 001 mudou"
  cd "$REPO" || return
  # sobra que não é arquivo regular (diretório vazio, link simbólico): não é
  # resíduo; rc 5 `sobra inválida`, validada antes de qualquer escrita
  local tipo_sobra
  for tipo_sobra in diretorio link; do
    d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
    cp "$AR" "$t/si-a1.md"; printf 'alvo\n' > "$t/si-alvo"
    case "$tipo_sobra" in
      diretorio) mkdir "$AR.superada.88" ;;
      link) ln -s "$t/si-alvo" "$AR.superada.88" ;;
    esac
    ls_antes="$(ls -A docs/entregas/ft-rec)"
    out="$("${v[@]}" 2>&1)"; c=$?
    { [ "$c" = 5 ] && printf '%s\n' "$out" | grep -Fq 'sobra inválida: RECONCILIACAO-BASE-001.md.superada.88; remova-a'; } \
      && ok "sobra $tipo_sobra: --verificar rc 5 'sobra inválida'" || falha "sobra $tipo_sobra: --verificar rc=$c $(printf '%s' "$out" | tr '\n\t' '|>')"
    reprova "sobra $tipo_sobra: rc 5 'sobra inválida' pela cadeia, nada gravado" 5 \
      "cadeia existente: RECONCILIACAO-BASE-001.md.superada.88: sobra inválida: RECONCILIACAO-BASE-001.md.superada.88; remova-a" -- "$FX_NOVO3"
    { grep -q '^estado: ativa$' "$AR" && cmp -s "$AR" "$t/si-a1.md"; } && ok "sobra $tipo_sobra: o 001 continua ativa, intacto" || falha "sobra $tipo_sobra: o 001 mudou"
    [ "$(ls -A docs/entregas/ft-rec)" = "$ls_antes" ] && ok "sobra $tipo_sobra: pasta da entrega como antes" || falha "sobra $tipo_sobra: pasta mudou: $(ls -A docs/entregas/ft-rec | tr '\n' ' ')"
    if [ "$tipo_sobra" = diretorio ]; then
      [ -d "$AR.superada.88" ] && ok "sobra diretorio: o diretório ficou" || falha "sobra diretorio: removido"
    else
      { [ -L "$AR.superada.88" ] && [ "$(cat "$t/si-alvo")" = alvo ]; } && ok "sobra link: o link e o alvo ficaram" || falha "sobra link: link ou alvo mudou"
    fi
    cd "$REPO" || return
  done
  # o prefixo da sobra é exatamente o nome de um artefato da cadeia
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  cp "$AR" "$t/sp-a1.md"
  cp "$AR" docs/entregas/ft-rec/RECONCILIACAO-BASE-009.md.superada.123
  reprova "sobra de 009 sem 009 na cadeia: rc 5 pela cadeia, nada completado" 5 \
    "cadeia existente: RECONCILIACAO-BASE-009.md.superada.123: sobra sem artefato na cadeia: RECONCILIACAO-BASE-009.md.superada.123; remova-a" -- "$FX_NOVO3"
  { [ -f docs/entregas/ft-rec/RECONCILIACAO-BASE-009.md.superada.123 ] && cmp -s "$AR" "$t/sp-a1.md"; } \
    && ok "sobra de 009: ela ficou e o 001 continua ativa" || falha "sobra de 009: removida ou 001 mudou"
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-009.md.superada.123
  cp "$AR" docs/entregas/ft-rec/RECONCILIACAO-BASE-xyz.superada.5
  reprova "RECONCILIACAO-BASE-xyz.superada.5 não é sobra (registro: pasta suja)" 3 "RECONCILIACAO-BASE-xyz.superada.5" -- "$FX_NOVO3"
  out="$("${v[@]}" 2>&1)"; c=$?
  { [ "$c" = 5 ] && printf '%s\n' "$out" | grep -Fq 'RECONCILIACAO-BASE-xyz.superada.5: nome fora do padrão'; } \
    && ok "RECONCILIACAO-BASE-xyz.superada.5 não é sobra (verificar: nome fora do padrão)" || falha "xyz: rc=$c $(printf '%s' "$out" | tr '\n\t' '|>')"
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-xyz.superada.5
  rc_igual "prefixo: removidas as duas, o mesmo M completa" 0 "${r[@]}" -- "$FX_NOVO3"
  grep -q '^estado: superada$' "$AR" && ok "prefixo: o 001 ficou superada" || falha "prefixo: o 001 não ficou superada"
  cd "$REPO" || return
  # a remoção da sobra falha: nenhum erro deixa o 001 superada com rc ≠ 0
  # (as sobras saem antes da marcação); a reexecução, sem a falha, completa
  d="$(mktemp -d)"; TMPS+=("$d"); _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  cp "$AR" "$AR.superada.321"; cp "$AR" "$t/rm-a1.md"
  mkdir -p "$t/shim-rm"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in *.superada.[0-9]*) echo "rm: recusado de propósito" >&2; exit 1 ;; esac; done\nexec %s "$@"\n' "$(command -v rm)" > "$t/shim-rm/rm"
  chmod +x "$t/shim-rm/rm"
  out="$(env PATH="$t/shim-rm:$PATH" "${r[@]}" -- "$FX_NOVO3" 2>&1 >/dev/null)"; c=$?
  { [ "$c" = 1 ] && case "$out" in *"não foi possível remover a sobra RECONCILIACAO-BASE-001.md.superada.321"*) true ;; *) false ;; esac; } \
    && ok "rm da sobra falha: rc 1 com instrução" || falha "rm da sobra falha: rc=$c $out"
  { grep -q '^estado: ativa$' "$AR" && cmp -s "$AR" "$t/rm-a1.md"; } && ok "rm da sobra falha: o 001 continua ativa, intacto" || falha "rm da sobra falha: o 001 ficou superada com rc ≠ 0"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.superada.* 2>/dev/null | grep -v '\.superada\.321$' | grep -q . \
    && falha "rm da sobra falha: ficou temporário do anterior" || ok "rm da sobra falha: nenhum temporário além da sobra"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "rm da sobra falha: trava livre" || falha "rm da sobra falha: trava presa"
  out="$("${r[@]}" -- "$FX_NOVO3" 2>&1)"; c=$?
  { [ "$c" = 0 ] && printf '%s\n' "$out" | grep -Fxq completado=superada && grep -q '^estado: superada$' "$AR" && [ ! -e "$AR.superada.321" ]; } \
    && ok "rm da sobra falha: a reexecução completa" || falha "rm da sobra falha: reexecução rc=$c $(printf '%s' "$out" | tr '\n' '|')"
  cd "$REPO" || return

  # três elos com a ANTEPENÚLTIMA ativa: não é resíduo, não completa
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" reajusta || { falha "segunda base não montou"; return; }
  fx_terceira_base "$d" || { falha "terceira base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 \
    && "${r[@]}" --merge "$FX_M2" -- "$FX_NOVO3" "$FX_NOVO1" >/dev/null 2>&1 \
    && "${r[@]}" -- "$FX_NOVO4" >/dev/null 2>&1 || falha "antepenúltima: cadeia de três"
  sed -i 's/^estado: superada$/estado: ativa/' "$AR"
  err="$("${r[@]}" -- "$FX_NOVO4" 2>&1 >/dev/null)"; c=$?
  { [ "$c" = 5 ] && ! printf '%s' "$err" | grep -q 'registro interrompido'; } \
    && ok "antepenúltima ativa: rc 5, sem instrução de registro interrompido" || falha "antepenúltima: rc=$c $err"
  grep -q '^estado: ativa$' "$AR" && grep -q '^estado: superada$' "$AR2" && ok "antepenúltima: nada completado" || falha "antepenúltima: estados mudaram"
  out="$("${v[@]}" 2>&1)"
  printf '%s' "$out" | grep -q 'registro interrompido' && falha "antepenúltima: o --verificar fala em registro interrompido" || ok "antepenúltima: o --verificar não fala em registro interrompido"
  cd "$REPO" || return

  # SIGKILL ANTES do ponto de commit: nenhuma sobra .superada; o órfão tem
  # instrução que leva ao registro
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "kill-antes: registro do 001"
  cp "$AR" "$t/ka-a1.md"; cp "$FX_ENTREGA" "$t/ka-e.md"
  tdi="$(mktemp -d)"; TMPS+=("$tdi")
  mkdir -p "$t/shim-ka"
  _shim_bloqueio "$t/shim-ka/mv" '*/ENTREGA.md|ENTREGA.md' antes "$t/marca-ka"
  setsid env TMPDIR="$tdi" PATH="$t/shim-ka:$PATH" "${r[@]}" -- "$FX_NOVO3" >/dev/null 2>&1 &
  pid=$!
  _espera_ponto "$pid" "$t/marca-ka" "kill-antes"
  _interrompe "$pid" KILL "$t/marca-ka" "kill-antes"
  rm -rf "$(bash "$TRAVA" --caminho | sed 's/^trava=//')"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md.superada.* >/dev/null 2>&1 && falha "kill-antes: ficou sobra .superada" || ok "kill-antes: nenhuma sobra .superada (preparada só depois do ponto de commit)"
  { [ -e "$AR2" ] && cmp -s "$AR" "$t/ka-a1.md" && cmp -s "$FX_ENTREGA" "$t/ka-e.md"; } && ok "kill-antes: 002 órfão, 001 e ENTREGA.md intactos" || falha "kill-antes: estado inesperado"
  reprova "kill-antes: o ENTREGA.md.registro sobra (pasta suja)" 3 "ENTREGA.md.registro" -- "$FX_NOVO3"
  rm -f docs/entregas/ft-rec/ENTREGA.md.registro.*
  reprova "kill-antes: o 002 órfão, com instrução" 5 "artefato órfão de registro interrompido: RECONCILIACAO-BASE-002.md; remova-o e registre de novo" -- "$FX_NOVO3"
  rm -f "$AR2"
  rc_igual "kill-antes: seguida a instrução, o M2 registra" 0 "${r[@]}" -- "$FX_NOVO3"
  cd "$REPO" || return
  # órfão + sobra (estado de versão anterior): a instrução nomeia os dois
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "órfão+sobra: registro do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "órfão+sobra: emissão do órfão"
  cp "$AR" "$AR.superada.4242"
  reprova "órfão + sobra: a instrução nomeia os dois" 5 \
    "artefato órfão de registro interrompido: RECONCILIACAO-BASE-002.md; remova RECONCILIACAO-BASE-002.md e RECONCILIACAO-BASE-001.md.superada.4242 e registre de novo" -- "$FX_NOVO3"
  rm -f "$AR2" "$AR.superada.4242"
  rc_igual "órfão + sobra: seguida a instrução, o M2 registra" 0 "${r[@]}" -- "$FX_NOVO3"
  cd "$REPO" || return

  # ---- a cadeia existente é verificada antes de servir de base -------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" README.md && fx_entrega_sincroniza "$d" || falha "forja do 001"
  rb_validar "$AR" ft-rec 1 || falha "001 forjado inválido: $RB_ERRO"
  reprova "001 forjado (assinatura válida) com caminho inelegível: o 002 não registra" 4 "cadeia existente: RECONCILIACAO-BASE-001.md: prova 1: README.md" -- "$FX_NOVO3"
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "forja do 001 superada"
  reprova "001 superada como última: contrato da cadeia, o 002 não registra" 5 "cadeia existente: RECONCILIACAO-BASE-001.md: a última reconciliação da cadeia tem de estar ativa" -- "$FX_NOVO3"
  # mesmo M e mesma lista do 001, mas a falha não é o resíduo de um registro
  # interrompido: nada é completado
  reprova "001 superada como última, mesmo M: não completa" 5 "a última reconciliação da cadeia tem de estar ativa" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- checkpoint commitado entre M1 e M2 (fluxo real) ---------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  fx_persiste_reconciliacao "$d" || falha "checkpoint reconciliacao-base"
  [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] && ok "checkpoint: árvore limpa" || falha "checkpoint: árvore suja"
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  git diff --name-only "$FX_B2" "$FX_M2" | grep -Fxq "$AR" && ok "checkpoint: o 001 está no diff B2..M2" || falha "checkpoint: 001 fora do diff B2..M2"
  out="$("${r[@]}" -- "$FX_NOVO3" 2>&1)"; c=$?
  esperado="registrado=RECONCILIACAO-BASE-002.md
b0=$FX_B1
p1=$(git rev-parse "$FX_M2^1")
b1=$FX_B2
m=$FX_M2"
  [ "$c" = 0 ] && ok "checkpoint: com o 001 commitado antes do M2, registra o 002" || falha "checkpoint: rc=$c $out"
  [ "$out" = "$esperado" ] && ok "checkpoint: saída registrado/b0/p1/b1/m" || falha "checkpoint: saída $(printf '%s' "$out" | tr '\n' '|')"
  rc_igual "checkpoint: a cadeia verifica" 0 "${v[@]}"
  [ "$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort)" = " M $FX_ENTREGA
 M $AR
?? $AR2" ] && ok "checkpoint: 001 e ENTREGA.md alterados, 002 novo" || falha "checkpoint: status inesperado"
  cd "$REPO" || return

  # ---- condição 2 da cadeia: M2 muda só o modo de um caminho do 001 --------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  git update-index --chmod=+x "$FX_NOVO2"; chmod +x "$FX_NOVO2"
  m2x="$(git log -1 --format=%B HEAD | git commit-tree "$(git write-tree)" -p "$FX_M" -p "$FX_B2")"
  git update-ref refs/heads/feature/ft-rec "$m2x"
  [ "$(git ls-tree HEAD -- "$FX_NOVO2" | cut -c1-6)" = 100755 ] || falha "modo: M2 sem o modo trocado"
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "modo: registro do 001"
  reprova "M2 muda só o modo de um caminho do 001: o inventário reprova" 4 "inventário: $FX_NOVO2" -- "$FX_NOVO3"
  cd "$REPO" || return

  # ---- três elos: 001 -> 002 (relista NOVO1) -> 003 ------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" reajusta || { falha "segunda base (reajusta) não montou"; return; }
  fx_terceira_base "$d" || { falha "terceira base não montou"; return; }
  cd "$d" || return
  rc_igual "três elos: 001 (--merge M1)" 0 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "três elos: 002 (--merge M2) relista NOVO1" 0 "${r[@]}" --merge "$FX_M2" -- "$FX_NOVO3" "$FX_NOVO1"
  rc_igual "três elos: 003 (HEAD = M3)" 0 "${r[@]}" -- "$FX_NOVO4"
  { grep -q "^b0_sha: $FX_B2\$" "$AR3" && grep -q '^anterior: "RECONCILIACAO-BASE-002.md"$' "$AR3" \
    && grep -q '^estado: superada$' "$AR" && grep -q '^estado: superada$' "$AR2" && grep -q '^estado: ativa$' "$AR3"; } \
    && ok "três elos: 003 encadeia em B2; 001 e 002 superadas" || falha "três elos: encadeamento ou estados"
  [ "$(git rev-parse "$FX_M3:$FX_NOVO1")" = "$(git rev-parse "$FX_M2:$FX_NOVO1")" ] \
    && [ "$(git rev-parse "$FX_M3:$FX_NOVO1")" != "$(git rev-parse "$FX_M:$FX_NOVO1")" ] \
    || falha "três elos: M3 não herda NOVO1 do M2"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t002\ncoberto\t%s\t002\ncoberto\t%s\t003' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3" "$FX_NOVO4")"
  [ "$("${v[@]}" 2>&1)" = "$esperado" ] && ok "três elos: verifica; NOVO1 coberto pelo 002 (o mais recente)" || falha "três elos: $("${v[@]}" 2>&1 | tr '\n\t' '|>')"
  cd "$REPO" || return
}

# --- apoio do grupo legado ---------------------------------------------------

# _ultimas_chaves <arquivo> <n> — as n últimas chaves de topo do frontmatter
_ultimas_chaves() {
  awk 'NR == 1 { next } /^---[ \t]*\r?$/ { exit } /^[A-Za-z_][A-Za-z0-9_]*:/ { k = $0; sub(/:.*/, "", k); print k }' "$1" \
    | tail -n "$2" | tr '\n' ' '
}

# _shim_merge_base <dir> — um `git` que responde `merge-base --all` com
# $FX_SHIM_MB e repassa todo o resto ao git real: simula o merge-base que não é
# ancestral de B1, inalcançável com o Git real (o merge-base é ancestral comum
# por definição, e enxertos e refs/replace estão desligados no script).
_shim_merge_base() {
  mkdir -p "$1"
  cat > "$1/git" <<EOF
#!/usr/bin/env bash
mb=0; todos=0
for a in "\$@"; do case "\$a" in merge-base) mb=1 ;; --all) todos=1 ;; esac; done
if [ "\$mb" = 1 ] && [ "\$todos" = 1 ]; then printf '%s\n' "\$FX_SHIM_MB"; exit 0; fi
exec $(command -v git) "\$@"
EOF
  chmod +x "$1/git"
}

# _nada_gravado <desc> <status antes> — o registro reprovado não deixou nada:
# nem alteração rastreada, nem arquivo não rastreado, nem artefato, nem trava
_nada_gravado() {
  git diff --quiet && ok "$1: git diff vazio" || falha "$1: gravou algo rastreado"
  [ "$(git status --porcelain=v1 --untracked-files=all)" = "$2" ] && ok "$1: status (com não rastreados) igual ao de antes" || falha "$1: status mudou"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-* >/dev/null 2>&1 && falha "$1: artefato gravado" || ok "$1: nenhum RECONCILIACAO-BASE-*"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "$1: trava livre" || falha "$1: trava presa"
}

grupo_legado() {
  local d r v t VT out c antes st lido tt esperado variante mb raiz trecho m2x caso
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t"); VT="$t"
  _shim_merge_base "$t/shim-mb"

  # ---- brief: o legado infere B0; o ambíguo falha fechado ------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado; cd "$d" || return
  cp "$FX_ENTREGA" "$t/antes.md"; antes="$(bash "$SEQ" --ler "$FX_ENTREGA")"
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  rc_igual "legado infere B0" 0 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  grep -q '^origem_base: inferida_legado' "$FX_ENTREGA" && ok "origem_base gravada" || falha "origem_base"
  grep -q "^b0_sha: $FX_B0" docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md && ok "B0 inferido certo" || falha "B0"

  # o 001 e o ENTREGA.md gravados
  [ "$(git merge-base --all "$FX_P1" "$FX_B1")" = "$FX_B0" ] && ok "controle: B0 é o merge-base único de P1 e B1" || falha "controle: merge-base"
  lido="$(rb_ler "$AR")"
  for tt in "origem_base	inferida_legado" "anterior	null" "numero	1" "estado	ativa" "b0_sha	$FX_B0" \
            "p1_sha	$FX_P1" "b1_sha	$FX_B1" "m_sha	$FX_M"; do
    printf '%s\n' "$lido" | grep -Fxq "escalar	$tt" && ok "001 legado: $tt" || falha "001 legado: escalar ${tt%%	*} divergente"
  done
  rb_validar "$AR" ft-rec 1 && ok "001 legado válido" || falha "001 legado inválido: $RB_ERRO"
  [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B1" ] && ok "ENTREGA: base_validada_sha = B1" || falha "ENTREGA: base_validada_sha"
  [ "$(_chave "$FX_ENTREGA" portao_sha)" = null ] && ok "ENTREGA: portao_sha null" || falha "ENTREGA: portao_sha"
  esperado="reconciliacoes:
  - numero: 1
    arquivo: RECONCILIACAO-BASE-001.md
    b1_sha: $FX_B1
    m_sha: $FX_M"
  [ "$(awk '/^reconciliacoes:/ { f = 1; print; next } f && /^[ \t]/ { print; next } f { exit }' "$FX_ENTREGA")" = "$esperado" ] \
    && ok "ENTREGA: reconciliacoes com o 001" || falha "ENTREGA: bloco reconciliacoes divergente"
  for k in base_validada_sha origem_base reconciliacoes portao_sha; do
    [ "$(grep -c "^$k:" "$FX_ENTREGA")" = 1 ] && ok "ENTREGA: $k uma vez só" || falha "ENTREGA: $k ausente ou repetida"
  done
  [ "$(_ultimas_chaves "$FX_ENTREGA" 4)" = "base_validada_sha origem_base reconciliacoes portao_sha " ] \
    && ok "ENTREGA: as chaves novas entram juntas antes do fechamento, na ordem do E0" || falha "ENTREGA: ordem $(_ultimas_chaves "$FX_ENTREGA" 4)"
  { [ "$(_chave "$FX_ENTREGA" estado)" = aberto ] && [ "$(_chave "$FX_ENTREGA" portao)" = null ] \
    && [ "$(_chave "$FX_ENTREGA" push_feito)" = false ] && [ "$(_chave "$FX_ENTREGA" entregue_em)" = null ] \
    && [ "$(_chave "$FX_ENTREGA" causa)" = null ] && [ "$(_chave "$FX_ENTREGA" falhas_portao)" = '[]' ]; } \
    && ok "ENTREGA: reaberta (estado, portão, push, entregue_em, causa, falhas)" || falha "ENTREGA: reabertura"
  entrega_confere "legado" "$t/antes.md" "$FX_ENTREGA" $GRAVADAS origem_base
  [ "$(bash "$SEQ" --ler "$FX_ENTREGA")" = "$antes" ] && ok "legado: commits e seq intactos" || falha "legado: seq mudou"
  [ "$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort)" = " M $FX_ENTREGA
?? $AR" ] && ok "legado: só ENTREGA.md e o 001 na árvore" || falha "legado: status inesperado"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "legado: trava livre" || falha "legado: trava presa"

  # a verificação aceita o 001 inferido
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  v_ok "legado: --verificar aceita o 001 inferida_legado" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_NOVO1")"
  # reexecução: noop (o ENTREGA.md do disco tem a origem_base que o de M não tem)
  antes="$(_instantaneo)"
  out="$("${r[@]}" "$FX_NOVO2" "$FX_NOVO1" 2>&1)"; c=$?
  { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ]; } \
    && ok "legado: reexecução com a mesma lista é noop" || falha "legado noop: rc=$c $out"
  [ "$(_instantaneo)" = "$antes" ] && ok "legado noop: nada gravado" || falha "legado noop gravou"
  # o ENTREGA.md do disco diz a mesma origem_base que o 001
  cp "$FX_ENTREGA" "$t/e1.md"
  sed 's/^origem_base: inferida_legado$/origem_base: registrada_e0/' "$t/e1.md" > "$FX_ENTREGA"
  v_motivo "ENTREGA.origem_base do disco divergente do 001 reprova" 5 entrega "origem_base"
  reprova "registro com ENTREGA.origem_base divergente no disco: a cadeia não verifica" 5 "origem_base" "$FX_NOVO1" "$FX_NOVO2"
  # a origem_base tolerada no disco é exatamente a linha que o registro grava
  sed 's/^origem_base: inferida_legado$/origem_base: inferida_legado /' "$t/e1.md" > "$FX_ENTREGA"
  reprova "noop com origem_base do disco fora da forma gravada" 3 "origem_base não tem o valor" "$FX_NOVO1" "$FX_NOVO2"
  cp "$t/e1.md" "$FX_ENTREGA"
  # a verificação recalcula a ancestralidade (git simulado: merge-base fora de B1)
  v=(env FX_SHIM_MB="$(git rev-parse "$FX_P1~3")" PATH="$t/shim-mb:$PATH" bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  v_motivo "--verificar: merge-base recalculado fora de B1 reprova (git simulado)" 5 ancora "não é ancestral de B1"
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)

  # ---- 002 depois do 001 legado commitado: encadeia e nunca reinfere ------
  fx_persiste_reconciliacao "$d" || falha "checkpoint do 001 legado"
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  out="$("${r[@]}" -- "$FX_NOVO3" 2>&1)"; c=$?
  [ "$c" = 0 ] && ok "002 encadeia depois do 001 legado commitado" || falha "002 depois do legado: rc=$c $out"
  lido="$(rb_ler "$AR2")"
  for tt in "origem_base	reconciliacao_anterior" "anterior	RECONCILIACAO-BASE-001.md" "b0_sha	$FX_B1" \
            "b1_sha	$FX_B2" "m_sha	$FX_M2"; do
    printf '%s\n' "$lido" | grep -Fxq "escalar	$tt" && ok "002 (nunca reinfere): $tt" || falha "002: escalar ${tt%%	*} divergente"
  done
  { [ "$(_chave "$FX_ENTREGA" origem_base)" = inferida_legado ] && [ "$(grep -c '^origem_base:' "$FX_ENTREGA")" = 1 ] \
    && [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B2" ]; } \
    && ok "ENTREGA depois do 002: origem_base inferida_legado mantida, base B2" || falha "ENTREGA depois do 002"
  v_ok "cadeia legado 001→002 verifica" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t002' "$FX_NOVO2" "$FX_NOVO1" "$FX_NOVO3")"
  # só o 001 pode ser inferida_legado (origem_base não é assinada)
  cp "$AR2" "$t/a2.md"
  sed 's/^origem_base: .*/origem_base: inferida_legado/' "$t/a2.md" > "$AR2"
  rb_validar "$AR2" ft-rec 2 && ok "forja: 002 com inferida_legado continua com assinatura válida" || falha "forja do 002 inválida: $RB_ERRO"
  v_motivo "002 com origem_base inferida_legado reprova (só o 001 infere)" 5 origem_base "fora de reconciliacao_anterior"
  cp "$t/a2.md" "$AR2"
  cd "$REPO" || return

  # ---- 002 sem commit entre os registros ----------------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  rc_igual "sem commit: 001 legado (--merge M1)" 0 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  grep -q '^origem_base: inferida_legado$' "$AR" && ok "sem commit: 001 inferida_legado" || falha "sem commit: 001 origem_base"
  out="$("${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" 2>&1)"; c=$?
  { [ "$c" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = noop=true ]; } && ok "sem commit: reexecução do 001 é noop" || falha "sem commit noop: rc=$c $out"
  rc_igual "sem commit: 002 encadeia (HEAD = M2)" 0 "${r[@]}" -- "$FX_NOVO3"
  { grep -q "^b0_sha: $FX_B1\$" "$AR2" && grep -q '^origem_base: reconciliacao_anterior$' "$AR2"; } \
    && ok "sem commit: 002 com B0 = B1 da cadeia" || falha "sem commit: 002 b0/origem"
  { [ "$(_chave "$FX_ENTREGA" origem_base)" = inferida_legado ] && [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B2" ] \
    && [ "$(_ultimas_chaves "$FX_ENTREGA" 4)" = "base_validada_sha origem_base reconciliacoes portao_sha " ]; } \
    && ok "sem commit: o ENTREGA.md (de M2, legado) mantém origem_base inferida_legado" || falha "sem commit: ENTREGA $(_ultimas_chaves "$FX_ENTREGA" 4)"
  rc_igual "sem commit: a cadeia legado verifica" 0 "${v[@]}"
  cd "$REPO" || return

  # ---- cadeia presente e base_validada_sha apagada de P1: rc 5 -------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001 legado"
  fx_persiste_reconciliacao "$d" || falha "checkpoint do 001 legado"
  sed '/^base_validada_sha:/d' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  git commit -q -m "docs: apaga a base validada" -- "$FX_ENTREGA"
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  reprova "cadeia presente e base_validada_sha apagada de P1: rc 5, sem inferir" 5 "base_validada_sha" -- "$FX_NOVO3"
  cd "$REPO" || return

  # ---- nunca reinfere: a cadeia apagada do histórico corrente --------------
  for caso in historico origem; do
    d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
    cd "$d" || return
    "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "$caso: registro do 001 legado"
    fx_persiste_reconciliacao "$d" || falha "$caso: checkpoint do 001 legado"
    git rm -q -- "$AR"
    git show "$FX_P1:$FX_ENTREGA" > "$FX_ENTREGA"
    [ "$caso" = origem ] && { sed 's/^branch_base: main$/&\norigem_base: inferida_legado/' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"; }
    git add -- "$FX_ENTREGA"; git commit -q -m "docs: apaga a cadeia de reconciliacoes"
    fx_segunda_base "$d" ajusta || { falha "$caso: segunda base não montou"; return; }
    case "$caso" in
      historico) reprova "cadeia apagada (artefato no histórico de P1): rc 5, nunca reinfere" 5 "RECONCILIACAO-BASE no histórico de P1" -- "$FX_NOVO3" ;;
      origem) reprova "cadeia apagada com origem_base em P1: rc 5, nunca reinfere" 5 "origem_base sem base_validada_sha" -- "$FX_NOVO3" ;;
    esac
    cd "$REPO" || return
  done

  # ---- brief: legado ambíguo falha fechado, sem gravar nada ----------------
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  for variante in criss_cross merge_previo; do
    d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE="$variante" fx_cenario "$d" legado; cd "$d" || return
    st="$(git status --porcelain=v1 --untracked-files=all)"
    rc_igual "legado ambíguo ($variante) falha fechado" 6 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
    git diff --quiet && ok "nada gravado ($variante)" || falha "gravou algo ($variante)"
    case "$variante" in
      criss_cross)
        [ "$(git merge-base --all "$FX_P1" "$FX_B1" | wc -l)" = 2 ] && ok "controle: dois merge-bases" || falha "controle: criss_cross sem dois merge-bases"
        trecho="2 merge-bases entre P1" ;;
      merge_previo)
        [ "$(git merge-base --all "$FX_P1" "$FX_B1" | wc -l)" = 1 ] && ok "controle: um merge-base" || falha "controle: merge_previo"
        [ -n "$(git rev-list --first-parent --merges "$FX_P1" "^$(git merge-base "$FX_P1" "$FX_B1")")" ] \
          && ok "controle: merge na linha de primeiro pai de P1" || falha "controle: merge_previo sem merge"
        trecho="contém o merge" ;;
    esac
    rc_motivo "legado ambíguo ($variante): o motivo é a condição dele" 6 "$trecho" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
    _nada_gravado "legado ambíguo ($variante)" "$st"
    cd "$REPO" || return
  done

  # ---- merge-base não ancestral de B1 (git simulado) -----------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
  cd "$d" || return
  st="$(git status --porcelain=v1 --untracked-files=all)"
  git merge-base --is-ancestor "$(git merge-base "$FX_P1" "$FX_B1")" "$FX_B1" && ok "controle: com o git real, o merge-base é ancestral de B1" || falha "controle: ancestralidade"
  rc_motivo "merge-base fora de B1 (git simulado): rc 6" 6 "não é ancestral de B1" \
    env FX_SHIM_MB="$(git rev-parse "$FX_P1~3")" PATH="$t/shim-mb:$PATH" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  _nada_gravado "merge-base fora de B1" "$st"
  cd "$REPO" || return

  # ---- P1 sem o ENTREGA.md (pais trocados) num legado: não infere ----------
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=pais_trocados fx_cenario "$d" legado || { falha "pais_trocados legado não montou"; return; }
  cd "$d" || return
  reprova "legado com P1 sem o ENTREGA.md (pais trocados): rc 4, sem inferir" 4 "a base legada não é inferível" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- chave presente (vazia, null, entre aspas) ou origem sem base: rc 5 ---
  for variante in entrega_base_vazia entrega_base_null entrega_base_aspas entrega_sem_base; do
    d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE="$variante" fx_cenario "$d" || { falha "$variante não montou"; return; }
    cd "$d" || return
    case "$variante" in entrega_sem_base) trecho="origem_base sem base_validada_sha" ;; *) trecho="base_validada_sha não é SHA de 40 hex" ;; esac
    reprova "$variante: rc 5 (contrato), sem inferir" 5 "$trecho" "$FX_NOVO1" "$FX_NOVO2"
    cd "$REPO" || return
  done

  # ---- a fonte é P1: nem o disco nem M sem a chave alimentam a inferência --
  # (merge_previo não legado: com a base de P1, a ordem fala, rc 5; inferir daria 6)
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=merge_previo fx_cenario "$d" || { falha "merge_previo não montou"; return; }
  cd "$d" || return
  sed '/^base_validada_sha:/d' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  reprova "ENTREGA.md do disco sem a chave: B0 vem de P1 (rc 5 pela ordem, não 6)" 5 "ordem:" "$FX_NOVO1" "$FX_NOVO2"
  git add -- "$FX_ENTREGA"
  m2x="$(git log -1 --format=%B "$FX_M" | git commit-tree "$(git write-tree)" -p "$FX_P1" -p "$FX_B1")"
  git update-ref refs/heads/feature/ft-rec "$m2x"
  [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] || falha "fonte: árvore suja depois de trocar M"
  reprova "ENTREGA.md de M sem a chave: B0 vem de P1 (rc 5 pela ordem, não 6)" 5 "ordem:" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- --verificar: 001 inferida_legado forjado ----------------------------
  # b0_sha diferente do merge-base (B0 com pai: a raiz também é ancestral comum)
  d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE=base_com_pai fx_cenario "$d" legado || { falha "base_com_pai não montou"; return; }
  cd "$d" || return
  rc_igual "base_com_pai: o legado registra" 0 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  v_ok "base_com_pai: verifica" "$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_NOVO1")"
  raiz="$(git rev-parse "$FX_B0^")"
  FX_ORIGEM_BASE=inferida_legado fx_emite_reconciliacao "$d" 1 "$raiz" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "forja do b0 legado"
  rb_validar "$AR" ft-rec 1 || falha "forja do b0 legado inválida: $RB_ERRO"
  v_motivo "001 inferida_legado com b0_sha diferente do merge-base único reprova" 5 ancora "não é o merge-base único"
  [ "$("${v[@]}" 2>/dev/null | grep -c '^motivo')" = 1 ] && ok "b0 forjado: só a âncora reprova" || falha "b0 forjado: $("${v[@]}" 2>&1 | tr '\n\t' '|>')"
  cd "$REPO" || return

  # criss_cross e merge_previo: 001 forjado (assinado, ENTREGA.md coerente)
  for variante in criss_cross merge_previo; do
    d="$(mktemp -d)"; TMPS+=("$d"); FX_VARIANTE="$variante" fx_cenario "$d" legado || { falha "$variante não montou"; return; }
    cd "$d" || return
    mb="$(git merge-base --all "$FX_P1" "$FX_B1" | sed -n 1p)"
    FX_ORIGEM_BASE=inferida_legado fx_emite_reconciliacao "$d" 1 "$mb" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "$variante: forja"
    fx_entrega_chaves_legado "$d" || falha "$variante: chaves do ENTREGA.md"
    [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B1" ] || falha "$variante: ENTREGA forjado sem a base B1"
    case "$variante" in criss_cross) trecho="2 merge-bases entre P1" ;; merge_previo) trecho="contém o merge" ;; esac
    v_motivo "--verificar: 001 inferida_legado forjado sobre $variante reprova" 5 ancora "$trecho"
    cd "$REPO" || return
  done
}
