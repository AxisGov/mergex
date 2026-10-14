#!/usr/bin/env bash
# Bancada R3: predecessores SprintX verificáveis e retomada estreita da V9.
#
# Uso: bash scripts/ci/test-r3-predecessores-sprintx.sh <grupo>... | todos

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${S:-$REPO/.claude/skills/mergex/scripts}"
PREDS="${PREDS:-$S/predecessores-sprintx.sh}"
V9="${V9:-$S/portao-v9.sh}"
VALIDADE="${VALIDADE:-$S/validade-do-portao.sh}"
PERSISTE="${PERSISTE:-$S/persistir-metodo.sh}"
CONTRATO="${CONTRATO:-$S/contrato-de-commit.sh}"
SEQ="${SEQ:-$S/sequencia-de-commits.sh}"
RETOMA="${RETOMA:-$S/retomar-v9-predecessores.sh}"
TRAVA="${TRAVA:-$S/trava-do-e1.sh}"
SPRINTX_PRODUTOR="$REPO/scripts/ci/fixtures/sprintx-predecessores.sh"
SPRINTX_PRODUTOR_SHA='a8150485bfa8f53a2971fc6c66d299257ab6f6d7295e269e7f65ce2137bc0cec'

OK=0; FALHOU=0
TMPS=()
trap 'cd "$REPO" 2>/dev/null; rm -rf ${TMPS[@]+"${TMPS[@]}"}' EXIT

ok()    { OK=$((OK + 1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU + 1)); printf '  FALHA %s\n' "$1"; }

rc_igual() {
  local desc="$1" esperado="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$esperado" ]; then ok "$desc"; else falha "$desc — rc=$rc, esperava $esperado"; fi
}

sha256_arquivo() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

fixture() {
  FIXTURE_DIR="$(mktemp -d)" || return 1
  TMPS+=("$FIXTURE_DIR")
  # shellcheck source=lib/fixture-predecessores.sh
  . "$REPO/scripts/ci/lib/fixture-predecessores.sh" || return 1
  fx_predecessores_cenario "$FIXTURE_DIR" || return 1
}

fixture_sha256() {
  FIXTURE_DIR="$(mktemp -d)" || return 1
  TMPS+=("$FIXTURE_DIR")
  # shellcheck source=lib/fixture-predecessores.sh
  . "$REPO/scripts/ci/lib/fixture-predecessores.sh" || return 1
  FX_PRE_OBJECT_FORMAT=sha256 fx_predecessores_cenario "$FIXTURE_DIR" || return 1
}

escreve_manifesto() { # usa a fixture corrente; não faz commit
  fx_predecessores_registra_sprintx "$FX_PRE_MANIFESTO"
}

grava_manifesto() { # usa a fixture corrente e cria um commit simples do manifesto
  escreve_manifesto || return 1
  git add -- "$FX_PRE_MANIFESTO" || return 1
  git commit -q -m 'chore(mergex): registra predecessores da fixture' \
    -m 'Trabalho: ft-pre' -m 'Metodo: predecessores'
}

v9_com_produtor() { # <produtor substituto>; usa a fixture corrente
  local produtor="$1" copia scripts
  copia="$(mktemp -d)" || return 1
  TMPS+=("$copia")
  cp -R "$REPO/.claude" "$copia/" || return 1
  scripts="$copia/.claude/skills/mergex/scripts"
  cp "$produtor" "$scripts/predecessores-sprintx.sh" || return 1
  chmod +x "$scripts/predecessores-sprintx.sh" || return 1
  bash "$scripts/portao-v9.sh" --verificar --entrega "$FX_PRE_ENTREGA" \
    --origem sprintx --trabalho ft-pre
}

grupo_verificador() {
  local d out rc
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"
  cd "$d" || return
  [ "$(git rev-parse HEAD)" = "$FX_PRE_E8" ] && ok 'fixture termina no E8 bloqueado' || falha 'fixture não termina no E8'
  [ "$(git show "$FX_PRE_E8:$FX_PRE_ENTREGA" | sed -n 's/^estado:[[:space:]]*//p')" = bloqueado ] \
    && ok 'ENTREGA final está bloqueada' || falha 'ENTREGA final não está bloqueada'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = 'resultado=ausente' ] \
    && ok 'manifesto ausente preserva o comportamento histórico' || falha "ausência divergente — rc=$rc, saída=$out"
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=ok ] \
    && [ "$(printf '%s\n' "$out" | grep -c $'^predecessor\t')" = 2 ] \
    && ok 'dois predecessores imutáveis e anteriores são aprovados' \
    || falha "predecessores válidos reprovados — rc=$rc, saída=$out"

  awk 'BEGIN{n=0} /^---$/ {n++; if(n==2) print "kind: quebrado"} {print}' \
    "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=ok ] \
    && ok 'verificador lê o manifesto de HEAD, nunca o disco' || falha "manifesto do disco contaminou a prova — rc=$rc, saída=$out"
  git restore --worktree -- "$FX_PRE_MANIFESTO"

  printf '\nMudanca posterior.\n' >> "$FX_PRE_SPEC_PATH"
  git add -- "$FX_PRE_SPEC_PATH" && git commit -q -m 'docs: altera predecessor depois do manifesto'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=v9 ] \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md\tblob_divergente' \
    && ok 'blob atual divergente é v9 conhecido' || falha "divergência não virou v9 — rc=$rc, saída=$out"
  cd "$REPO" || return

  fixture || { falha 'fixture para predecessor no nascimento não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso nascimento não foi commitado'; cd "$REPO" || return; return; }
  sed "0,/^    commit_sha: /s/^    commit_sha: .*$/    commit_sha: $FX_PRE_NASCIMENTO/" "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: predecessor igual ao nascimento'
  rc_igual 'commit igual ao nascimento falha fechado' 3 bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return

  fixture || { falha 'fixture para predecessor posterior não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso posterior não foi commitado'; cd "$REPO" || return; return; }
  posterior="$(git rev-parse HEAD)"
  sed "0,/^    commit_sha: /s/^    commit_sha: .*$/    commit_sha: $posterior/" "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: predecessor posterior ao nascimento'
  rc_igual 'commit posterior ao nascimento falha fechado' 3 bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return

  fixture || { falha 'fixture para SHA humano não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso SHA humano não foi commitado'; cd "$REPO" || return; return; }
  curto="$(sed -n 's/^    commit_sha: //p' "$FX_PRE_MANIFESTO" | sed -n '1p' | cut -c1-8)"
  sed "0,/^    commit_sha: /s/^    commit_sha: .*$/    commit_sha: $curto/" "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: predecessor usa SHA abreviado humano'
  rc_igual 'SHA abreviado humano falha fechado' 3 bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return

  fixture_sha256 || { falha 'fixture SHA-256 não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'produtor não registrou manifesto SHA-256'; cd "$REPO" || return; return; }
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=ok ] \
    && [ "$(git rev-parse --show-object-format)" = sha256 ] \
    && [ "$(sed -n 's/^    commit_sha: //p' "$FX_PRE_MANIFESTO" | sed -n '1p' | wc -c | tr -d ' ')" = 65 ] \
    && ok 'verificador aceita protocolo completo em repositório SHA-256' \
    || falha "protocolo SHA-256 foi recusado — rc=$rc, saída=$out"
  cd "$REPO" || return

  fixture || { falha 'fixture para entrada inválida não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso inválido não foi commitado'; cd "$REPO" || return; return; }
  awk 'BEGIN{n=0} /^    origem: superpowers$/ {n++; if(n==2){print "    origem: desconhecida"; next}} {print}' \
    "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: uma entrada inválida entre duas'
  rc_igual 'uma entrada inválida reprova o conjunto inteiro' 3 bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return

  fixture || { falha 'fixture para symlink não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso symlink não foi commitado'; cd "$REPO" || return; return; }
  rm -f "$FX_PRE_SPEC_PATH" && ln -s exemplo.md "$FX_PRE_SPEC_PATH"
  git add -- "$FX_PRE_SPEC_PATH" && git commit -q -m 'test: predecessor vira symlink'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md\tblob_divergente' \
    && ok 'symlink no predecessor é recusado' || falha "symlink não foi recusado — rc=$rc, saída=$out"
  cd "$REPO" || return
}

grupo_protocolo() {
  local d out rc hash
  hash="$(sha256_arquivo "$SPRINTX_PRODUTOR" 2>/dev/null)"
  [ "$hash" = "$SPRINTX_PRODUTOR_SHA" ] \
    && ok 'fixture usa o produtor SprintX certificado byte a byte' \
    || falha "fixture não usa o produtor SprintX certificado — sha=${hash:-ausente}"
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"
  cd "$d" || return
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = 'resultado=ausente' ] \
    && ok 'ausência usa resultado=ausente e rc 0' \
    || falha "protocolo de ausência ainda indisponível — rc=$rc, saída='${out:-vazia}'"
  rc_igual 'uso inválido retorna 64' 64 bash "$PREDS" --verificar --trabalho ft-pre
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  # Frontmatter estruturalmente inválido: nenhuma linha parcial é autorizada.
  sed 's/^kind: predecessores$/kind: outro/' "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: quebra schema do manifesto'
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 3 ] && [ "$(printf '%s\n' "$out" | sed -n '1p')" = resultado=v9_sem_prova ] \
    && [ "$(printf '%s\n' "$out" | grep -c $'^motivo\t')" -ge 1 ] \
    && ! printf '%s\n' "$out" | grep -q $'^predecessor\t' \
    && ok 'schema inconclusivo falha fechado sem aceitação parcial' \
    || falha "v9_sem_prova fora do protocolo — rc=$rc, saída=$out"
  cd "$REPO" || return

  fixture || { falha 'fixture para chave de topo desconhecida não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto do caso de chave desconhecida não foi commitado'; cd "$REPO" || return; return; }
  sed '/^kind: predecessores$/a\chave_desconhecida: valor' "$FX_PRE_MANIFESTO" > "$FX_PRE_MANIFESTO.tmp" \
    && mv "$FX_PRE_MANIFESTO.tmp" "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: chave de topo desconhecida'
  rc_igual 'parser fechado recusa chave de topo desconhecida' 3 bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre
  cd "$REPO" || return
}

grupo_v9() {
  local d out rc
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"; cd "$d" || return
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md' \
    && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/plans/exemplo.md' \
    && ok 'V9 histórica barra spec e plano sem manifesto' || falha "V9 ausente divergente — rc=$rc, saída=$out"
  grava_manifesto || { falha 'manifesto válido não foi commitado'; cd "$REPO" || return; return; }
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
    && ok 'V9 aceita somente os predecessores comprovados' || falha "V9 não integrou predecessores — rc=$rc, saída=$out"
  printf '\nMudanca posterior.\n' >> "$FX_PRE_SPEC_PATH"
  git add -- "$FX_PRE_SPEC_PATH" && git commit -q -m 'test: diverge predecessor depois do manifesto'
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] \
    && printf '%s\n' "$out" | grep -Fxq $'fora_do_plano\tdocs/superpowers/specs/exemplo-design.md' \
    && ! printf '%s\n' "$out" | grep -q $'^fora_do_plano\t[^\t]*\t' \
    && ok 'V9 publica fora_do_plano com exatamente duas colunas' \
    || falha "V9 expôs detalhe interno na saída pública — rc=$rc, saída=$out"
  mkdir -p docs/superpowers/outros
  printf 'nao declarado\n' > docs/superpowers/outros/nao-declarado.md
  git add -- docs/superpowers/outros/nao-declarado.md && git commit -q -m 'test: acrescenta superpowers não declarado'
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -Fq $'fora_do_plano\tdocs/superpowers/outros/nao-declarado.md' \
    && ok 'prefixo docs/superpowers não cria isenção' || falha "prefixo indevidamente aceito — rc=$rc, saída=$out"
  cd "$REPO" || return

  fixture_sha256 || { falha 'fixture SHA-256 da V9 não montou'; return; }
  cd "$FIXTURE_DIR" || return
  grava_manifesto || { falha 'manifesto SHA-256 da V9 não foi commitado'; cd "$REPO" || return; return; }
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
    && [ "$(git rev-parse --show-object-format)" = sha256 ] \
    && ok 'V9 aceita protocolo completo em repositório SHA-256' \
    || falha "V9 recusou protocolo SHA-256 — rc=$rc, saída=$out"

  local portao_sha
  portao_sha="$(git rev-parse HEAD)"
  sed -e 's/^portao: .*/portao: pronto/' \
    -e "s/^portao_sha: .*/portao_sha: $portao_sha/" \
    -e 's/^falhas_portao: .*/falhas_portao: []/' \
    -e 's/^causa: .*/causa: null/' \
    "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA"
  git add -- "$FX_PRE_ENTREGA" \
    && git commit -q -m 'chore(mergex): persiste metodo pre-e6' \
      -m $'Trabalho: ft-pre\nMetodo: pre-e6'
  out="$(bash "$VALIDADE" --verificar --entrega "$FX_PRE_ENTREGA" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'ok=true' \
    && ok 'validade do portao aceita portao_sha SHA-256 completo' \
    || falha "validade recusou portao_sha SHA-256 — rc=$rc, saída=$out"
  cd "$REPO" || return
}

grupo_consumidor() {
  local wrapper out rc sha39 sha41 controle
  fixture || { falha 'fixture do consumidor V9 não montou'; return; }
  cd "$FIXTURE_DIR" || return
  if [ -n "${R3_PREDS_CONSUMIDOR:-}" ]; then
    grava_manifesto || { falha 'manifesto real do consumidor não foi commitado'; cd "$REPO" || return; return; }
    out="$(v9_com_produtor "$R3_PREDS_CONSUMIDOR" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
      && ok 'V9 só aceita o protocolo completo do produtor real' \
      || falha "V9 aceitou produtor mutante ou perdeu a prova — rc=$rc, saída=$out"
    cd "$REPO" || return
    return
  fi
  wrapper="$FIXTURE_DIR/produtor-substituto.sh"
  sha39="$(printf '%s' "$FX_PRE_SPEC" | cut -c1-39)"
  sha41="${FX_PRE_PLANO}a"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/exemplo-design.md\t%s\t%s\n'\n" "$sha39" "$sha41"
    printf "printf 'predecessor\tdocs/superpowers/plans/exemplo.md\t%s\t%s\n'\n" "$FX_PRE_PLANO" "$FX_PRE_PLANO"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa SHA 39+41 que soma 80 hex' \
    || falha "consumidor V9 aceitou larguras combinadas — rc=$rc, saída=$out"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/../plans/exemplo.md\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
    printf "printf 'predecessor\tdocs/superpowers/specs/exemplo-design.md\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
    printf "printf 'predecessor\tdocs/superpowers/plans/exemplo.md\t%s\t%s\n'\n" "$FX_PRE_PLANO" "$FX_PRE_PLANO"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa caminho não canônico' \
    || falha "consumidor V9 aceitou caminho não canônico — rc=$rc, saída=$out"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tsrc/x.py\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa predecessor fora de docs/superpowers' \
    || falha "consumidor V9 aceitou predecessor fora da origem — rc=$rc, saída=$out"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/a: b.md\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa caminho inseguro como scalar YAML' \
    || falha "consumidor V9 aceitou scalar YAML inseguro — rc=$rc, saída=$out"

  controle="$(printf '\001')"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/controle%s.md\t%s\t%s\n'\n" "$controle" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa byte de controle no caminho' \
    || falha "consumidor V9 aceitou controle em scalar YAML — rc=$rc, saída=$out"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/trailing \t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa espaço final no caminho' \
    || falha "consumidor V9 aceitou espaço final normalizado por YAML — rc=$rc, saída=$out"

  {
    printf '%s\n' '#!/usr/bin/env bash' 'printf '\''%s\n'\'' '\''resultado=ok'\'''
    printf "printf 'predecessor\tdocs/superpowers/specs/exemplo-design.md\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
    printf "printf 'predecessor\tdocs/superpowers/specs/exemplo-design.md\t%s\t%s\n'\n" "$FX_PRE_SPEC" "$FX_PRE_SPEC"
    printf "printf 'predecessor\tdocs/superpowers/plans/exemplo.md\t%s\t%s\n'\n" "$FX_PRE_PLANO" "$FX_PRE_PLANO"
  } > "$wrapper"
  out="$(v9_com_produtor "$wrapper" 2>&1)"; rc=$?
  [ "$rc" = 3 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=v9_sem_prova' \
    && ok 'consumidor V9 recusa predecessor duplicado' \
    || falha "consumidor V9 aceitou predecessor duplicado — rc=$rc, saída=$out"
  cd "$REPO" || return
}

grupo_checkpoint() {
  local d out rc rcv rcp antes depois paths msg stage_antes stage_depois sub_origem index_antes index_depois
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  d="$FIXTURE_DIR"; cd "$d" || return

  # O executor exige o orquestrador do trabalho, mas o catálogo estreito não o adota.
  cat > docs/sprintx/features/ft-pre/ORQUESTRADOR.md <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: orquestrador
trabalho_id: ft-pre
---

# Orquestrador
EOF
  git add -- docs/sprintx/features/ft-pre/ORQUESTRADOR.md
  git commit -q -m 'docs: acrescenta orquestrador da fixture'

  printf 'x\n\nTrabalho: ft-pre\nMetodo: predecessores\n' > "$d/metodo.msg"
  rc_igual 'contrato aceita Metodo: predecessores' 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint predecessores --arquivo "$d/metodo.msg"
  printf 'x\n\nTrabalho: ft-pre\nMetodo: retomar-v9-predecessores\n' > "$d/metodo.msg"
  rc_igual 'contrato aceita Metodo: retomar-v9-predecessores' 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint retomar-v9-predecessores --arquivo "$d/metodo.msg"
  printf 'x\n\nTask: T-01.01\nTrabalho: ft-pre\nMetodo: predecessores\n' > "$d/metodo.msg"
  rc_igual 'checkpoint de método recusa Task' 2 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint predecessores --arquivo "$d/metodo.msg"
  rm -f "$d/metodo.msg"

  bash "$PERSISTE" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcv=$?
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcp=$?
  [ "$rcv" != 0 ] && [ "$rcp" != 0 ] && ! git diff --cached --name-only | grep -q . \
    && ok 'checkpoint predecessores recusa manifesto ainda ausente' \
    || falha "checkpoint aceitou manifesto ausente — verificar=$rcv, persistir=$rcp"

  escreve_manifesto || { falha 'manifesto não foi escrito'; cd "$REPO" || return; return; }
  out="$(bash "$PERSISTE" --listar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$FX_PRE_MANIFESTO" ] \
    && ok 'catálogo predecessores contém somente o manifesto' || falha "catálogo predecessores divergente — rc=$rc, saída=$out"
  printf '\narvore alheia\n' >> README.md
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores 2>&1)"; rc=$?
  [ "$rc" != 0 ] && ! git diff --cached --name-only | grep -q . \
    && ok 'árvore suja fora do manifesto recusa sem preparar stage' \
    || falha "checkpoint aceitou árvore suja fora do manifesto — rc=$rc, saída=$out"
  git restore --worktree -- README.md
  antes="$(bash "$SEQ" --ler "$FX_PRE_ENTREGA" 2>/dev/null)"
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then ok 'checkpoint predecessores foi persistido'; else falha "checkpoint predecessores falhou — rc=$rc, saída=$out"; fi
  paths="$(git diff-tree --no-commit-id --name-only -r HEAD)"
  [ "$paths" = "$FX_PRE_MANIFESTO" ] && ok 'commit predecessores toca somente o manifesto' || falha "commit predecessores tocou: $paths"
  rc_igual 'commit predecessores satisfaz o contrato' 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint predecessores --commit HEAD
  depois="$(bash "$SEQ" --ler "$FX_PRE_ENTREGA" 2>/dev/null)"
  [ "$antes" = "$depois" ] && ok 'checkpoint predecessores não consome seq nem ENTREGA.commits' || falha 'checkpoint predecessores alterou a sequência E1'

  git update-index --assume-unchanged -- "$FX_PRE_MANIFESTO"
  printf '\nbytes ocultos pelo indice\n' >> "$FX_PRE_MANIFESTO"
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores 2>&1)"; rc=$?
  [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -Fq 'mudança oculta por bits do índice' \
    && ! git diff --cached --name-only | grep -q . \
    && ok 'checkpoint predecessores falha fechado em manifesto oculto pelo índice' \
    || falha "checkpoint silenciou manifesto assume-unchanged — rc=$rc, saída=$out"
  git update-index --no-assume-unchanged -- "$FX_PRE_MANIFESTO"
  git restore --worktree -- "$FX_PRE_MANIFESTO"

  git update-index --skip-worktree -- README.md
  printf '\narvore alheia oculta\n' >> README.md
  printf '\nmanifesto dirty normal\n' >> "$FX_PRE_MANIFESTO"
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores 2>&1)"; rc=$?
  [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -Fq 'árvore suja fora do artefato esperado: README.md' \
    && ! git diff --cached --name-only | grep -q . \
    && ok 'checkpoint predecessores enxerga path alheio com skip-worktree' \
    || falha "checkpoint ignorou árvore alheia skip-worktree — rc=$rc, saída=$out"
  git update-index --no-skip-worktree -- README.md
  git restore --worktree -- README.md "$FX_PRE_MANIFESTO"

  sub_origem="$(mktemp -d)" || { falha 'origem temporária do submódulo indisponível'; cd "$REPO" || return; return; }
  TMPS+=("$sub_origem")
  git -c init.defaultBranch=main init -q "$sub_origem"
  git -C "$sub_origem" config user.name Teste
  git -C "$sub_origem" config user.email teste@fixture.invalid
  printf 'base\n' > "$sub_origem/conteudo.txt"
  git -C "$sub_origem" add -- conteudo.txt
  git -C "$sub_origem" commit -q -m 'test: base do submódulo'
  git -c protocol.file.allow=always submodule add -q "$sub_origem" submodulo-ignorado
  git add -- .gitmodules submodulo-ignorado
  git commit -q -m 'test: acrescenta submódulo ignorado'
  git config submodule.submodulo-ignorado.ignore all
  printf 'dirty\n' >> submodulo-ignorado/conteudo.txt
  printf '\nmanifesto dirty com submódulo\n' >> "$FX_PRE_MANIFESTO"
  index_antes="$(cksum < "$(git rev-parse --git-path index)")"
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores 2>&1)"; rc=$?
  index_depois="$(cksum < "$(git rev-parse --git-path index)")"
  [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -Fq 'árvore suja fora do artefato esperado: submodulo-ignorado' \
    && [ "$index_antes" = "$index_depois" ] \
    && ok 'checkpoint enxerga submódulo dirty mesmo com ignore=all e preserva o índice real' \
    || falha "checkpoint ignorou submódulo dirty — rc=$rc, saída=$out"
  git -C submodulo-ignorado restore --worktree -- conteudo.txt
  git restore --worktree -- "$FX_PRE_MANIFESTO"

  rm -f "$FX_PRE_MANIFESTO"
  bash "$PERSISTE" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcv=$?
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcp=$?
  [ "$rcv" != 0 ] && [ "$rcp" != 0 ] && ! git diff --cached --name-only | grep -q . \
    && ok 'checkpoint predecessores recusa remoção do manifesto persistido' \
    || falha "checkpoint aceitou manifesto removido — verificar=$rcv, persistir=$rcp"
  git restore --worktree -- "$FX_PRE_MANIFESTO"

  rm -f "$FX_PRE_MANIFESTO"
  ln -s 00-PLANEJAMENTO.md "$FX_PRE_MANIFESTO"
  bash "$PERSISTE" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcv=$?
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rcp=$?
  [ "$rcv" != 0 ] && [ "$rcp" != 0 ] && ! git diff --cached --name-only | grep -q . \
    && ok 'checkpoint predecessores recusa manifesto substituído por symlink' \
    || falha "checkpoint aceitou manifesto symlink — verificar=$rcv, persistir=$rcp"
  rm -f "$FX_PRE_MANIFESTO"
  git restore --worktree -- "$FX_PRE_MANIFESTO"

  sed 's/^atualizado_em: .*/atualizado_em: 2026-10-14/' "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" \
    && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA"
  out="$(bash "$PERSISTE" --listar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint retomar-v9-predecessores)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$FX_PRE_ENTREGA" ] \
    && ok 'catálogo retomar-v9-predecessores contém somente ENTREGA.md' || falha "catálogo da retomada divergente — rc=$rc, saída=$out"
  out="$(bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint retomar-v9-predecessores 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then ok 'checkpoint retomar-v9-predecessores foi persistido'; else falha "checkpoint retomada falhou — rc=$rc, saída=$out"; fi
  paths="$(git diff-tree --no-commit-id --name-only -r HEAD)"
  [ "$paths" = "$FX_PRE_ENTREGA" ] && ok 'commit de retomada toca somente ENTREGA.md' || falha "commit de retomada tocou: $paths"
  rc_igual 'commit de retomada satisfaz o contrato' 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint retomar-v9-predecessores --commit HEAD

  sed 's/^atualizado_em: .*/atualizado_em: 2026-10-15/' "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" \
    && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA"
  local trava_out token
  trava_out="$(bash "$TRAVA" --adquirir 'metodo:retomar-v9-predecessores')"; rc=$?
  token="$(printf '%s\n' "$trava_out" | sed -n 's/^token=//p')"
  git update-index --skip-worktree README.md
  printf '\ncaminho oculto durante retomada\n' >> README.md
  out_sujo="$(bash "$PERSISTE" --persistir --trava-token "$token" --entrega "$FX_PRE_ENTREGA" \
    --origem sprintx --trabalho ft-pre --checkpoint retomar-v9-predecessores 2>&1)"; rc_sujo=$?
  bash "$TRAVA" --conferir "$token" >/dev/null 2>&1; rc_trava_suja=$?
  git update-index --no-skip-worktree README.md
  git restore --worktree -- README.md
  [ "$rc_sujo" != 0 ] && [ "$rc_trava_suja" = 0 ] \
    && printf '%s\n' "$out_sujo" | grep -Fq 'árvore suja fora do artefato esperado: README.md' \
    && ok 'trava herdada recusa caminho oculto sem liberar a exclusão' \
    || falha "trava herdada aceitou caminho oculto — persistir=$rc_sujo conferir=$rc_trava_suja saída=$out_sujo"
  out="$(bash "$PERSISTE" --persistir --trava-token "$token" --entrega "$FX_PRE_ENTREGA" \
    --origem sprintx --trabalho ft-pre --checkpoint retomar-v9-predecessores 2>&1)"; rcp=$?
  bash "$TRAVA" --conferir "$token" >/dev/null 2>&1; rcv=$?
  if [ "$rc" = 0 ] && [ "$rcp" = 0 ] && [ "$rcv" = 0 ]; then
    ok 'checkpoint da retomada adota a trava do chamador sem janela'
  else
    falha "checkpoint não adotou trava válida — adquirir=$rc persistir=$rcp conferir=$rcv saída=$out"
  fi
  bash "$TRAVA" --liberar "$token" >/dev/null 2>&1

  # Stage preexistente: falha antes de adotar o manifesto e preserva bytes/paths.
  printf '\nstage alheio\n' >> README.md
  git add -- README.md
  stage_antes="$(git diff --cached --binary)"
  printf '\nmanifesto dirty\n' >> "$FX_PRE_MANIFESTO"
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rc=$?
  stage_depois="$(git diff --cached --binary)"
  [ "$rc" != 0 ] && [ "$stage_antes" = "$stage_depois" ] \
    && ! git diff --cached --name-only | grep -Fxq "$FX_PRE_MANIFESTO" \
    && ok 'stage preexistente recusa sem limpar nem adotar path extra' \
    || falha 'checkpoint alterou ou adotou stage preexistente'
  cd "$REPO" || return
}

prepara_retomada() {
  fixture || return 1
  CENARIO_DIR="$FIXTURE_DIR"
  cd "$CENARIO_DIR" || return 1
  cat > docs/sprintx/features/ft-pre/ORQUESTRADOR.md <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: orquestrador
trabalho_id: ft-pre
---

# Orquestrador
EOF
  git add -- docs/sprintx/features/ft-pre/ORQUESTRADOR.md
  git commit -q -m 'docs: acrescenta orquestrador da fixture'
  escreve_manifesto || return 1
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1 || return 1
  [ -z "$(git status --porcelain=v1 --untracked-files=all)" ]
}

muda_entrega() { # <expressão sed> — altera e commita a entrega da fixture
  sed "$1" "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA" || return 1
  git add -- "$FX_PRE_ENTREGA" && git commit -q -m 'test: varia estado terminal da entrega'
}

espera_recusa() { # <descrição> <expressão sed>
  local desc="$1" expr="$2" rc
  prepara_retomada || { falha "$desc: cenário não montou"; return; }
  muda_entrega "$expr" || { falha "$desc: variante não commitou"; cd "$REPO" || return; return; }
  bash "$RETOMA" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre >/dev/null 2>&1; rc=$?
  [ "$rc" != 0 ] && ok "$desc" || falha "$desc: retomada aceitou estado proibido"
  cd "$REPO" || return
}

grupo_retomada() {
  local d out rc antes depois paths hoje alvo conteudo_antes conteudo_depois
  prepara_retomada || { falha 'cenário pronto para retomada não montou'; return; }
  d="$CENARIO_DIR"
  sed 's/^atualizado_em: .*/atualizado_em: 2000-01-01/' "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" \
    && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA" \
    && git add -- "$FX_PRE_ENTREGA" && git commit -q -m 'test: deixa timestamp terminal antigo' \
    || { falha 'cenário com timestamp antigo não foi commitado'; cd "$REPO" || return; return; }
  antes="$(git status --porcelain=v1 --untracked-files=all)$(git rev-parse HEAD)"
  out="$(bash "$RETOMA" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  depois="$(git status --porcelain=v1 --untracked-files=all)$(git rev-parse HEAD)"
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'ok=true' && printf '%s\n' "$out" | grep -Fxq 'proxima=E2' \
    && [ "$antes" = "$depois" ] && ok '--verificar aprova sem escrever' || falha "--verificar divergente — rc=$rc, saída=$out"
  out="$(bash "$RETOMA" --aplicar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'proxima=E2' \
    && ok '--aplicar reabre e manda ao E2' || falha "--aplicar falhou — rc=$rc, saída=$out"
  [ "$(sed -n 's/^estado:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = aberto ] \
    && [ "$(sed -n 's/^portao:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = null ] \
    && [ "$(sed -n 's/^portao_sha:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = null ] \
    && [ "$(sed -n 's/^falhas_portao:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = '[]' ] \
    && [ "$(sed -n 's/^causa:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = null ] \
    && [ "$(sed -n 's/^desvios:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = '[]' ] \
    && ok 'somente o estado terminal é limpo para a reexecução' || falha 'campos da reabertura divergentes'
  hoje="$(date +%Y-%m-%d)"
  [ "$(sed -n 's/^atualizado_em:[[:space:]]*//p' "$FX_PRE_ENTREGA")" = "$hoje" ] \
    && ok 'retomada atualiza atualizado_em em toda gravação' || falha 'retomada preservou timestamp antigo'
  paths="$(git diff-tree --no-commit-id --name-only -r HEAD)"
  [ "$paths" = "$FX_PRE_ENTREGA" ] && ok 'checkpoint da retomada toca somente ENTREGA.md' || falha "retomada tocou: $paths"
  rc_igual 'commit da retomada satisfaz o contrato' 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-pre --checkpoint retomar-v9-predecessores --commit HEAD
  rc_igual 'repetição depois de reaberto é recusada' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return

  prepara_retomada || { falha 'cenário para temporário previsível não montou'; return; }
  d="$CENARIO_DIR"; cd "$d" || return
  alvo="$(mktemp)" || { falha 'alvo externo temporário indisponível'; cd "$REPO" || return; return; }
  TMPS+=("$alvo")
  printf 'sentinela externa\n' > "$alvo"
  conteudo_antes="$(cksum < "$alvo")"
  printf '%s\n' 'ENTREGA.md.retomar.*' '.ENTREGA.md.retomar.*' >> .git/info/exclude
  out="$(ALVO="$alvo" ENTREGA="$FX_PRE_ENTREGA" RETOMA="$RETOMA" bash -c '
    ln -s "$ALVO" "$ENTREGA.retomar.$$"
    exec bash "$RETOMA" --aplicar --entrega "$ENTREGA" --origem sprintx --trabalho ft-pre
  ' 2>&1)"; rc=$?
  conteudo_depois="$(cksum < "$alvo")"
  [ "$rc" = 0 ] && [ "$conteudo_antes" = "$conteudo_depois" ] \
    && ok 'temporário imprevisível não segue symlink pré-posicionado' \
    || falha "temporário previsível tocou alvo externo — rc=$rc, saída=$out"
  cd "$REPO" || return

  espera_recusa 'estado diferente de bloqueado é recusado' 's/^estado: bloqueado$/estado: entregue/'
  espera_recusa 'portão diferente de bloqueado é recusado' 's/^portao: bloqueado$/portao: pronto/'
  espera_recusa 'falhas diferentes de [v9] são recusadas' 's/^falhas_portao: \[v9\]$/falhas_portao: [v1, v9]/'
  espera_recusa 'causa diferente é recusada' 's/^causa: arquivo_fora_do_plano$/causa: bloqueio_aberto/'
  espera_recusa 'push já feito é recusado' 's/^push_feito: false$/push_feito: true/'
  espera_recusa 'PR presente é recusado' 's/^pr_url: null$/pr_url: https:\/\/example.invalid\/1/'
  espera_recusa 'reconciliação pendente é recusada' 's/^reconciliacoes: \[\]$/reconciliacoes: [RECONCILIACAO-BASE-001.md]/'

  prepara_retomada || { falha 'cenário para desvio adicional não montou'; return; }
  sed '/^  - docs\/superpowers\/plans\/exemplo.md$/a\  - docs/superpowers/specs/nao-declarado.md' "$FX_PRE_ENTREGA" > "$FX_PRE_ENTREGA.tmp" \
    && mv "$FX_PRE_ENTREGA.tmp" "$FX_PRE_ENTREGA"
  git add -- "$FX_PRE_ENTREGA" && git commit -q -m 'test: acrescenta desvio não coberto'
  rc_igual 'desvio não coberto pelo manifesto é recusado' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return

  fixture || { falha 'cenário sem manifesto não montou'; return; }
  d="$FIXTURE_DIR"; cd "$d" || return
  rc_igual 'V9 ainda vermelha é recusada' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return

  fixture || { falha 'cenário inconclusivo não montou'; return; }
  d="$FIXTURE_DIR"; cd "$d" || return
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: quebrado' '---' > "$FX_PRE_MANIFESTO"
  git add -- "$FX_PRE_MANIFESTO" && git commit -q -m 'test: manifesto inconclusivo'
  rc_igual 'V9 sem prova é recusada' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return

  prepara_retomada || { falha 'cenário para disco sujo não montou'; return; }
  printf '\ndivergencia de disco\n' >> "$FX_PRE_ENTREGA"
  rc_igual 'ENTREGA.md do disco diferente de HEAD é recusado' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return

  prepara_retomada || { falha 'cenário para stage sujo não montou'; return; }
  printf '\nstage sujo\n' >> README.md; git add -- README.md
  rc_igual 'stage ou árvore sujos são recusados' 3 bash "$RETOMA" --verificar \
    --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre
  cd "$REPO" || return
}
grupo_contrato() {
  local f enum
  enum='pre-e2 | reconciliacao-base | predecessores | retomar-v9-predecessores | pre-e6 | e8'
  for f in .claude/commands/mergex.md .claude/commands/mergex-check.md \
           .opencode/commands/mergex.md .opencode/commands/mergex-check.md; do
    grep -Fq 'predecessores-sprintx.sh' "$REPO/$f" \
      && grep -Fq 'resultado=v9_sem_prova' "$REPO/$f" \
      && grep -Fq 'retomar-v9-predecessores.sh' "$REPO/$f" \
      && grep -Fq 'references/13-predecessores-sprintx.md' "$REPO/$f" \
      && ok "$f publica fonte, falha fechada e retomada" \
      || falha "$f não publica o contrato completo de predecessores"
  done
  for f in .claude/commands/mergex-check.md .opencode/commands/mergex-check.md; do
    grep -Fq 'todas as V1–V11' "$REPO/$f" \
      && ok "$f exige o E2 completo depois da retomada" \
      || falha "$f reduz a retomada a uma verificação parcial"
  done
  for f in .claude/commands/mergex-retomar-v9.md .opencode/commands/mergex-retomar-v9.md; do
    grep -Fq -- '--entrega docs/entregas/<trabalho>/ENTREGA.md' "$REPO/$f" \
      && grep -Fq -- '--origem sprintx' "$REPO/$f" \
      && grep -Fq -- '--trabalho <trabalho>' "$REPO/$f" \
      && ok "$f publica a invocação completa da retomada" \
      || falha "$f omite argumento obrigatório da retomada"
  done
  cmp -s "$REPO/.claude/commands/mergex.md" "$REPO/.opencode/commands/mergex.md" \
    && ok 'entrypoint mergex é idêntico nos dois harnesses' || falha 'entrypoint mergex diverge entre harnesses'
  cmp -s "$REPO/.claude/commands/mergex-check.md" "$REPO/.opencode/commands/mergex-check.md" \
    && ok 'entrypoint mergex-check é idêntico nos dois harnesses' || falha 'entrypoint mergex-check diverge entre harnesses'
  cmp -s "$REPO/.claude/commands/mergex-retomar-v9.md" "$REPO/.opencode/commands/mergex-retomar-v9.md" \
    && ok 'entrypoint de retomada é idêntico nos dois harnesses' || falha 'entrypoint de retomada diverge entre harnesses'
  for f in .claude/skills/mergex/SKILL.md .claude/skills/mergex/references/01-commits.md \
           .claude/skills/mergex/references/08-registro.md .claude/skills/mergex/references/11-reconciliacao-base.md \
           .claude/hooks/README.md; do
    grep -Fq "$enum" "$REPO/$f" && ok "$f publica o enum de seis checkpoints" \
      || falha "$f diverge do enum de checkpoints"
  done
  for dm in DM-187 DM-188 DM-189 DM-190; do
    grep -q "^| $dm |" "$REPO/.claude/skills/mergex/DECISOES-DA-SKILL.md" \
      && ok "$dm está no registro append-only" || falha "$dm ausente"
  done
  grep -Fq 'registrar → validar → checkpoint predecessores → verificar retomada →' \
      "$REPO/.claude/skills/mergex/references/integracao/sprintx.md" \
    && grep -Fq 'aplicar/checkpoint retomada → pre-e2 → E2 completo' \
      "$REPO/.claude/skills/mergex/references/integracao/sprintx.md" \
    && ok 'integração SprintX publica a ordem operacional completa' \
    || falha 'ordem operacional de predecessores ausente'
  grep -Fq 'MergeX anterior não entende o manifesto' "$REPO/README.md" \
    && grep -Fq 'PRs de SprintX e MergeX' "$REPO/README.md" \
    && ok 'README registra a compatibilidade coordenada' || falha 'README omite a compatibilidade coordenada'
  grep -Fq 'Em repositório Git, o resultado `PRONTO` exige prova prévia do `pre-push` funcional; registrar `BLOQUEADO` não depende dessa prova' \
      "$REPO/.claude/skills/mergex/SKILL.md" \
    && grep -Fq 'Fora de um repositório Git, a prova para `PRONTO` é dispensada' \
      "$REPO/.claude/skills/mergex/SKILL.md" \
    && ok 'resumo do E2 distingue PRONTO, BLOQUEADO e a exceção normativa sem Git' \
    || falha 'SKILL diverge do contrato de prova do pre-push no E2'
  grep -Fq -- '--trava-token "$TOKEN"' "$RETOMA" \
    && ok 'retomada transfere a mesma trava ao checkpoint' \
    || falha 'retomada ainda libera a trava antes do checkpoint'
}

e2_fixture_completo() {
  local tasks="docs/sprintx/features/ft-pre/sprint-01/tasks.md" out rc
  [ "$(grep -c '^[[:space:]]*- id: T-' "$tasks")" = 6 ] \
    && [ "$(grep -c '^[[:space:]]*status: concluida$' "$tasks")" = 6 ] || return 1
  printf 'V1=OK\n'
  [ "$(grep -c '^[[:space:]]*suite: verde$' "$tasks")" = 6 ] || return 1
  printf 'V2=OK\n'
  [ "$(grep -c '^[[:space:]]*teste_integracao:' "$tasks")" = 6 ] \
    && [ "$(grep -c '^[[:space:]]*teste_funcional:' "$tasks")" = 6 ] || return 1
  printf 'V3=OK\nV4=n/a\nV5=n/a\nV6=n/a\nV7=OK\nV8=n/a\n'
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' || return 1
  printf 'V9=OK\n'
  ! git diff "$FX_PRE_BASE...HEAD" | grep -Eqi '(BEGIN [A-Z ]*PRIVATE KEY|password[[:space:]]*=|token[[:space:]]*=)' || return 1
  printf 'V10=OK\n'
  out="$(bash "$S/prova-de-commit.sh" --verificar "$FX_PRE_ENTREGA" "$tasks")"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'V11=OK' || return 1
  printf 'V11=OK\n'
}

grupo_mp27b() {
  local out rc tasks_antes commits_antes base_antes rec_antes seq_antes remoto_antes paths
  fixture || { falha 'fixture MP2.7b não montou'; return; }
  cd "$FIXTURE_DIR" || return
  tasks_antes="$(git rev-parse "HEAD:docs/sprintx/features/ft-pre/sprint-01/tasks.md")"
  commits_antes="$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n '/^commits:/,/^[A-Za-z_][A-Za-z0-9_]*:/p')"
  base_antes="$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n 's/^base_validada_sha:[[:space:]]*//p')"
  rec_antes="$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n 's/^reconciliacoes:[[:space:]]*//p')"
  seq_antes="$(bash "$SEQ" --ler "$FX_PRE_ENTREGA")"
  remoto_antes="$(git remote)"
  [ "$(git rev-parse HEAD)" = "$FX_PRE_E8" ] && ok 'MP2.7b parte do E8 bloqueado' || falha 'MP2.7b não parte do E8 bloqueado'

  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: orquestrador' \
    'trabalho_id: ft-pre' '---' '' '# Orquestrador' > docs/sprintx/features/ft-pre/ORQUESTRADOR.md
  git add -- docs/sprintx/features/ft-pre/ORQUESTRADOR.md \
    && git commit -q -m 'docs: materializa orquestrador da fixture' \
    || { falha 'orquestrador da fixture não foi commitado'; cd "$REPO" || return; return; }
  escreve_manifesto || { falha 'registrador SprintX da fixture falhou'; cd "$REPO" || return; return; }
  [ "$(grep -c '^  - caminho:' "$FX_PRE_MANIFESTO")" = 2 ] \
    && ok 'registrador SprintX produz os dois predecessores' || falha 'registrador SprintX produziu manifesto divergente'
  bash "$PERSISTE" --persistir --entrega "$FX_PRE_ENTREGA" --origem sprintx \
    --trabalho ft-pre --checkpoint predecessores >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && ok 'checkpoint predecessores fecha o registro' || falha "checkpoint predecessores falhou — rc=$rc"
  out="$(bash "$PREDS" --verificar --rev HEAD --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
    && ok 'manifesto persistido valida por conteúdo e história' || falha "manifesto não validou — rc=$rc, saída=$out"
  out="$(bash "$V9" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'resultado=ok' \
    && ok 'V9 fica verde com predecessores exatos' || falha "V9 não ficou verde — rc=$rc, saída=$out"
  out="$(bash "$RETOMA" --verificar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'proxima=E2' \
    && ok 'retomada é verificada antes da escrita' || falha "verificação da retomada falhou — rc=$rc, saída=$out"
  out="$(bash "$RETOMA" --aplicar --entrega "$FX_PRE_ENTREGA" --origem sprintx --trabalho ft-pre 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Fxq 'proxima=E2' \
    && ok 'retomada aplica o checkpoint e exige E2' || falha "aplicação da retomada falhou — rc=$rc, saída=$out"
  paths="$(git diff-tree --no-commit-id --name-only -r HEAD)"
  [ "$paths" = "$FX_PRE_ENTREGA" ] && ok 'checkpoint da retomada toca somente ENTREGA.md' \
    || falha "checkpoint da retomada tocou: $paths"
  out="$(e2_fixture_completo)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^V\([1-9]\|10\|11\)=')" = 11 ] \
    && printf '%s\n' "$out" | grep -Fxq 'V9=OK' \
    && ok 'E2 completo V1–V11 roda novamente' || falha "E2 pós-retomada incompleto — rc=$rc, saída=$out"
  [ "$(git rev-parse "HEAD:docs/sprintx/features/ft-pre/sprint-01/tasks.md")" = "$tasks_antes" ] \
    && [ "$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n '/^commits:/,/^[A-Za-z_][A-Za-z0-9_]*:/p')" = "$commits_antes" ] \
    && [ "$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n 's/^base_validada_sha:[[:space:]]*//p')" = "$base_antes" ] \
    && [ "$(git show "HEAD:$FX_PRE_ENTREGA" | sed -n 's/^reconciliacoes:[[:space:]]*//p')" = "$rec_antes" ] \
    && [ "$(bash "$SEQ" --ler "$FX_PRE_ENTREGA")" = "$seq_antes" ] \
    && ok 'tasks, commits E1, seq, base e reconciliações permanecem imutáveis' \
    || falha 'retomada alterou uma invariante congelada'
  [ "$(git remote)" = "$remoto_antes" ] && [ -z "$remoto_antes" ] \
    && ok 'fluxo não cria remoto, push nem PR' || falha 'fluxo tocou configuração remota'
  [ -z "$(git status --porcelain=v1 --untracked-files=all)" ] \
    && ok 'fluxo termina com árvore e stage limpos' || falha 'fluxo deixou escrita fora dos dois checkpoints'
  cd "$REPO" || return
}

roda_grupo() {
  case "$1" in
    verificador) grupo_verificador ;;
    protocolo) grupo_protocolo ;;
    v9) grupo_v9 ;;
    consumidor) grupo_consumidor ;;
    checkpoint) grupo_checkpoint ;;
    retomada) grupo_retomada ;;
    contrato) grupo_contrato ;;
    mp27b) grupo_mp27b ;;
    *) printf 'grupo desconhecido: %s\n' "$1" >&2; exit 64 ;;
  esac
}

if [ "$#" -eq 0 ]; then set -- todos; fi
if [ "$1" = todos ]; then set -- verificador protocolo v9 consumidor checkpoint retomada contrato mp27b; fi
for grupo in "$@"; do
  printf '\n%s\n' "== $grupo =="
  roda_grupo "$grupo"
done

printf '\n---------------------------------------------\n%d ok, %d falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" -eq 0 ]
