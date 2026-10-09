#!/usr/bin/env bash
#
# Bancada da reconciliação de base pós-E8 (R1).
#
# Cada grupo monta um repositório Git real (fixture-reconciliacao.sh) e prova
# um aspecto do contrato. Os grupos são funções `grupo_<nome>`; os de tasks
# posteriores são acrescentados abaixo, na ordem de definição.
#
# Uso: bash scripts/ci/test-r1-reconciliacao-base.sh <grupo>... | todos
#      RB=<outro script> bash scripts/ci/test-r1-reconciliacao-base.sh <grupo>

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="${S:-$REPO/.claude/skills/mergex/scripts}"
RB="${RB:-$S/reconciliacao-base.sh}"
V9="${V9:-$S/portao-v9.sh}"
VALIDADE="${VALIDADE:-$S/validade-do-portao.sh}"
CONTRATO="${CONTRATO:-$S/contrato-de-commit.sh}"
SEQ="${SEQ:-$S/sequencia-de-commits.sh}"
CAUSA="${CAUSA:-$S/causa-do-portao.sh}"
PROVA="${PROVA:-$S/prova-de-commit.sh}"
TRAVA="${TRAVA:-$S/trava-do-e1.sh}"

# Biblioteca do artefato (rb_*): as tasks seguintes usam rb_sha256 nos testes.
# Ausente, o grupo `artefato` falha com "biblioteca ausente".
[ -r "$S/reconciliacao-artefato.sh" ] && . "$S/reconciliacao-artefato.sh"

OK=0; FALHOU=0
TMPS=""
trap 'cd "$REPO" 2>/dev/null; for d in $TMPS; do rm -rf "$d"; done' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

# afirma <desc> <cmd...> — exige rc 0
afirma() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else falha "$desc"; fi
}

# rc_igual <desc> <rc> <cmd...> — exige o rc informado
rc_igual() {
  local desc="$1" esperado="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$esperado" ]; then ok "$desc"; else falha "$desc — rc=$rc, esperava $esperado"; fi
}

# ---------------------------------------------------------------------------
# Grupos
# ---------------------------------------------------------------------------

grupo_reproducao() {
  local d dl f st rc cp c n catf
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  dl="$(mktemp -d)"; catf="$(mktemp)"; TMPS="$TMPS $dl $catf"
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  . "$S/catalogo-de-metodo.sh" || { falha "catálogo ausente"; return; }
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  [ "$(git rev-parse "$FX_M^1")" = "$FX_P1" ] && ok "M^1 é P1" || falha "M^1 diferente de P1"
  [ "$(git rev-parse "$FX_M^2")" = "$FX_B1" ] && ok "M^2 é B1" || falha "M^2 diferente de B1"
  [ "$(git rev-list --parents -n1 "$FX_M" | wc -w)" = 3 ] && ok "M tem exatamente dois pais" || falha "M não tem dois pais"
  git show -s --format=%B "$FX_M" | git interpret-trailers --parse | grep -Fxq 'Trabalho: ft-rec' \
    && ok "M tem Trabalho: ft-rec" || falha "M sem Trabalho"
  git show -s --format=%B "$FX_M" | git interpret-trailers --parse | grep -Fxq "Integra-base: $FX_B1" \
    && ok "M tem Integra-base: B1 completo" || falha "M sem Integra-base correto"
  for f in "$FX_NOVO1" "$FX_NOVO2"; do
    st="$(git diff --no-renames --name-status "$FX_B0" "$FX_B1" -- "$f" | cut -f1)"
    [ "$st" = A ] && ok "$f nasceu na base" || falha "$f não nasceu na base (status '$st')"
    git diff --quiet "$FX_B1" "$FX_M" -- "$f"; rc=$?
    [ "$rc" = 1 ] && ok "$f ajustado no merge" || falha "$f sem ajuste no merge (rc=$rc)"
    git diff --name-only "$FX_B1...HEAD" | grep -Fxq "$f" \
      && ok "$f aparece no diff da V9 (defeito)" || falha "$f não aparece no diff da V9"
  done

  # histórico E2-E8: portao_sha (não legado) e commits de método posteriores
  local pg pre2
  pg="$(git show "$FX_P1:$FX_ENTREGA" | sed -n 's/^portao_sha:[[:space:]]*//p')"
  printf '%s' "$pg" | grep -Eq '^[0-9a-f]{40}$' && ok "portao_sha tem 40 hex" || falha "portao_sha não tem 40 hex ($pg)"
  git merge-base --is-ancestor "$pg" "$FX_P1" && ok "portao_sha é ancestral de P1" || falha "portao_sha não é ancestral de P1"
  pre2="$(git log --format=%H --grep='^Metodo: pre-e2' -n1 "$FX_P1")"
  [ -n "$pre2" ] && [ "$pg" = "$pre2" ] && ok "portao_sha é o commit pre-e2" || falha "portao_sha diferente do pre-e2"
  [ "$(git show "$FX_P1:$FX_ENTREGA" | sed -n 's/^portao:[[:space:]]*//p')" = pronto ] \
    && ok "ENTREGA com portao pronto" || falha "ENTREGA sem portao pronto"
  n=0
  for c in $(git rev-list "$pg..$FX_P1"); do
    n=$((n+1))
    [ "$(git rev-list --parents -n1 "$c" | wc -w)" = 2 ] && ok "$n: commit de um pai" || falha "$n: commit com mais de um pai"
    cp="$(git show -s --format=%B "$c" | git interpret-trailers --parse | sed -n 's/^Metodo:[[:space:]]*//p')"
    case "$cp" in
      pre-e6|e8) ok "$n: Metodo $cp" ;;
      *) falha "$n: Metodo '$cp' fora de pre-e6|e8"; continue ;;
    esac
    bash "$CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint "$cp" --commit "$c" >/dev/null 2>&1 \
      && ok "$n: contrato de método válido" || falha "$n: contrato de método inválido"
    catalogo_metodo "$d" sprintx ft-rec docs/sprintx/features/ft-rec "$cp" > "$catf" || { falha "$n: catálogo falhou"; continue; }
    if git diff-tree --no-commit-id --name-only -r "$c" | grep -vxFf "$catf" | grep -q .; then
      falha "$n: toca caminho fora do catálogo de $cp"
    else ok "$n: só caminhos do catálogo de $cp"; fi
  done
  [ "$n" = 2 ] && ok "dois commits de método entre portao_sha e P1" || falha "esperava 2 commits em portao_sha..P1, achou $n"
  git ls-tree -r --name-only "$FX_P1" | grep -Fxq docs/entregas/ft-rec/QA.md \
    && falha "QA.md (só RunX) não deveria existir" || ok "sem QA.md"
  cd "$REPO" || return

  # variante legado: as quatro chaves ausentes do frontmatter
  fx_cenario "$dl" legado || { falha "cenário legado não montou"; return; }
  cd "$dl" || return
  if git show "$FX_P1:$FX_ENTREGA" | awk 'NR>1 && /^---/ {exit} NR>1' \
      | grep -Eq '^(base_validada_sha|origem_base|reconciliacoes|portao_sha):'; then
    falha "legado: chave de base presente no ENTREGA"
  else ok "legado: sem as quatro chaves"; fi
  [ "$(git show "$FX_P1:$FX_ENTREGA" | sed -n 's/^portao:[[:space:]]*//p')" = pronto ] \
    && ok "legado: portao pronto" || falha "legado: portao não é pronto"
  cd "$REPO" || return
}

grupo_contrato() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  rc_igual "M válido é integração" 0 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M"
  [ "$(bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M" | sed -n 's/^b1=//p')" = "$FX_B1" ] \
    && ok "b1 é o segundo pai" || falha "b1 divergente"
  [ "$(bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M" | sed -n 's/^classe=//p')" = integracao_base ] \
    && ok "classe=integracao_base" || falha "classe divergente"
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\nTask: T-01.01\n' "$FX_B1" > m1
  rc_igual "Task junto com Integra-base reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m1
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$(git rev-parse --short "$FX_B1")" > m2
  rc_igual "SHA abreviado reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m2
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_B1" > mv
  local c1 c3
  c1="$(git commit-tree -p "$FX_P1" -F mv "$FX_M^{tree}")"
  rc_igual "commit de um pai com trailers válidos reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$c1"
  c3="$(git commit-tree -p "$FX_P1" -p "$FX_B1" -p "$FX_B0" -F mv "$FX_M^{tree}")"
  rc_igual "commit de três pais com trailers válidos reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$c3"
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$FX_P1" > m3
  rc_igual "mensagem válida em arquivo é integração" 0 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m3
  local cx; cx="$(git commit-tree -p "$FX_P1" -p "$FX_B1" -F m3 "$FX_M^{tree}")"
  rc_igual "segundo pai diferente do trailer reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$cx"
  rc_igual "--arquivo e --commit juntos são uso inválido" 64 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M" --arquivo m3
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\nIntegra-base: %s\n' "$FX_B1" "$FX_B1" > m4
  rc_igual "dois Integra-base reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m4
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\nMetodo: e8\n' "$FX_B1" > m5
  rc_igual "Metodo junto com Integra-base reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m5
  printf 'x\n\nTrabalho: outro\nIntegra-base: %s\n' "$FX_B1" > m6
  rc_igual "Trabalho divergente reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m6
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$(printf '%s' "$FX_B1" | tr a-f A-F)" > m7
  rc_igual "SHA em maiúsculas reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m7
  rc_igual "integração rejeita --task" 64 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --task T-01.01 --arquivo m3
  rc_igual "integração rejeita --checkpoint" 64 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --checkpoint e8 --arquivo m3
  rc_igual "E1 rejeita Integra-base" 2 bash "$CONTRATO" --validar-e1 --trabalho ft-rec --task T-01.01 --arquivo m1
  printf 'x\n\nTrabalho: ft-rec\nMetodo: e8\nIntegra-base: %s\n' "$FX_B1" > m8
  rc_igual "método rejeita Integra-base" 2 bash "$CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint e8 --arquivo m8
  rc_igual "checkpoint reconciliacao-base é método válido" 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-rec --checkpoint reconciliacao-base --arquivo "$REPO/scripts/ci/fixtures/r1/metodo-reconciliacao.txt"
  cd "$REPO" || return
}

grupo_artefato() {
  local d fx esc arq a rc chave dd tsv ret1 ret2 esp motivo
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  . "$S/reconciliacao-artefato.sh" || { falha "biblioteca ausente"; return; }
  fx="$REPO/scripts/ci/fixtures/r1"; esc="$fx/escalares-001.tsv"; arq="$fx/arquivos-001.tsv"
  a="$d/RECONCILIACAO-BASE-001.md"
  rb_emitir "$a" "$esc" "$arq" && ok "emite" || falha "emitir: $RB_ERRO"
  rb_validar "$a" ft-rec 1 && ok "valida o que emitiu" || falha "validar: $RB_ERRO"
  [ "$(rb_ler "$a" | grep -c '^arquivo	')" = 2 ] && ok "lê os dois arquivos" || falha "leitura"
  [ "$(head -n1 "$a")" = '---' ] && ok "frontmatter abre na primeira linha" || falha "sem frontmatter"
  [ "$(sed -n '2,$p' "$a" | grep -n '^---$' | head -n1 | cut -d: -f1)" -gt 1 ] && ok "frontmatter fecha" || falha "frontmatter sem fechamento"
  grep -q '^| Caminho | Status na base | Motivo |$' "$a" && ok "prosa tem a tabela por arquivo" || falha "prosa sem tabela"

  # ordem das chaves do frontmatter (spec 7.1)
  [ "$(sed -n '2,/^---$/p' "$a" | grep -E '^[a-z_0-9]+:' | sed 's/:.*//' | tr '\n' ' ')" = \
    'expx_schema expx_tool kind trabalho_id numero anterior branch branch_base origem_base b0_sha p1_sha b1_sha m_sha estado arquivos registrado_em assinatura ' ] \
    && ok "chaves na ordem da spec" || falha "ordem das chaves divergente"

  # caminho especial: ida e volta byte a byte
  esp="$(awk -F'\t' 'NR==1 {print $1}' "$arq")"
  [ "$esp" = 'tests/ui/caso com espaço e ação.test.tsx' ] || falha "fixture sem o caminho especial"
  [ "$(rb_ler "$a" | awk -F'\t' '$1=="arquivo" {print $2; exit}')" = "$esp" ] \
    && ok "rb_ler devolve o caminho especial byte a byte" || falha "caminho especial alterado na leitura"
  [ "$(rb_ler "$a" | awk -F'\t' '$1=="arquivo" {print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7}')" = "$(cat "$arq")" ] \
    && ok "rb_ler devolve as linhas do TSV de entrada idênticas" || falha "TSV não sobrevive emitir->ler"

  # aspas e barra invertida em motivo
  motivo='diz "oi" e usa C:\dir\x e \"já escapado\"'
  printf 'src/a.ts\tA\t%s\t%s\t%s\t%s\n' 1010101010101010101010101010101010101010 \
    2020202020202020202020202020202020202020 \
    1111111111111111111111111111111111111111111111111111111111111111 "$motivo" > "$d/q.tsv"
  mkdir "$d/q"
  rb_emitir "$d/q/RECONCILIACAO-BASE-001.md" "$esc" "$d/q.tsv" && ok "emite motivo com aspas e barra" || falha "emitir aspas: $RB_ERRO"
  [ "$(rb_ler "$d/q/RECONCILIACAO-BASE-001.md" | awk -F'\t' '$1=="arquivo" {print $7}')" = "$motivo" ] \
    && ok "motivo com aspas e barra sobrevive emitir->ler" || falha "motivo alterado na ida e volta"
  rb_validar "$d/q/RECONCILIACAO-BASE-001.md" ft-rec 1 && ok "motivo com aspas e barra valida" || falha "validar aspas: $RB_ERRO"

  # lista vazia
  mkdir "$d/v"; : > "$d/vazio.tsv"
  rb_emitir "$d/v/RECONCILIACAO-BASE-001.md" "$esc" "$d/vazio.tsv" && ok "emite arquivos: []" || falha "emitir vazio: $RB_ERRO"
  grep -q '^arquivos: \[\]$' "$d/v/RECONCILIACAO-BASE-001.md" && ok "lista vazia é []" || falha "lista vazia não é []"
  rb_validar "$d/v/RECONCILIACAO-BASE-001.md" ft-rec 1 && ok "valida arquivos: []" || falha "validar vazio: $RB_ERRO"

  # edição manual: numero (reprova também pelo schema)
  mkdir "$d/n"; cp "$a" "$d/n/"
  sed -i 's/^numero: 1$/numero: 2/' "$d/n/RECONCILIACAO-BASE-001.md"
  rb_validar "$d/n/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "edição manual passou" || ok "edição manual de numero reprova"

  # edição manual só de conteúdo assinado, sem violar nenhuma outra regra
  mkdir "$d/s"; cp "$a" "$d/s/"
  sed -i 's/^    blob_m: 2020202020202020202020202020202020202020$/    blob_m: 9999999999999999999999999999999999999999/' "$d/s/RECONCILIACAO-BASE-001.md"
  grep -q '9999999999999999999999999999999999999999' "$d/s/RECONCILIACAO-BASE-001.md" || falha "edição do blob_m não aplicou"
  rb_validar "$d/s/RECONCILIACAO-BASE-001.md" ft-rec 1; rc=$?
  [ "$rc" != 0 ] && ok "blob_m trocado por SHA válido reprova" || falha "blob_m trocado passou"
  case "$RB_ERRO" in *assinatura*) ok "o erro cita a assinatura" ;; *) falha "erro não cita a assinatura: $RB_ERRO" ;; esac
  # motivo não é assinado (é para o revisor): trocar o texto não quebra nada
  mkdir "$d/m"; cp "$a" "$d/m/"
  sed -i 's/O helper da feature mudou/Outro texto válido, o helper mudou/' "$d/m/RECONCILIACAO-BASE-001.md"
  rb_validar "$d/m/RECONCILIACAO-BASE-001.md" ft-rec 1 && ok "motivo reescrito não é conteúdo assinado" || falha "motivo reescrito reprovou: $RB_ERRO"

  # controles de schema: cada chave removida reprova (nome correto, pasta própria)
  for chave in expx_schema expx_tool kind trabalho_id numero anterior branch branch_base origem_base \
               b0_sha p1_sha b1_sha m_sha estado arquivos registrado_em assinatura; do
    dd="$d/k-$chave"; mkdir "$dd"
    grep -v "^$chave:" "$a" > "$dd/RECONCILIACAO-BASE-001.md"
    rb_validar "$dd/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "sem $chave passou" || ok "sem $chave reprova"
  done
  # e os itens: cada chave de item removida reprova
  for chave in caminho status_base blob_b1 blob_m diff_b1_m_sha256 motivo; do
    dd="$d/i-$chave"; mkdir "$dd"
    awk -v k="$chave" 'BEGIN{n=0} { if ($0 ~ "^    " k ":" && n==0) {n=1; next} if ($0 ~ "^  - " k ":" && n==0) {n=1; sub("^  - " k ":.*", "  - motivo_x: z"); } print }' "$a" > "$dd/RECONCILIACAO-BASE-001.md"
    rb_validar "$dd/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "item sem $chave passou" || ok "item sem $chave reprova"
  done

  # regras de valor
  mkdir "$d/e1"; sed 's/^estado: ativa$/estado: aceita/' "$a" > "$d/e1/RECONCILIACAO-BASE-001.md"
  rb_validar "$d/e1/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "estado fora do enum passou" || ok "estado fora do enum reprova"
  mkdir "$d/e2"; sed 's/^b1_sha: c*$/b1_sha: main/' "$a" > "$d/e2/RECONCILIACAO-BASE-001.md"
  rb_validar "$d/e2/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "ref no lugar de SHA passou" || ok "nome de ref no lugar de SHA reprova"
  rb_validar "$a" outro-trabalho 1 && falha "trabalho divergente passou" || ok "trabalho divergente reprova"
  rb_validar "$a" ft-rec 2 && falha "numero esperado divergente passou" || ok "numero esperado divergente reprova"
  mkdir "$d/e3"; cp "$a" "$d/e3/RECONCILIACAO-BASE-002.md"
  rb_validar "$d/e3/RECONCILIACAO-BASE-002.md" ft-rec 2 && falha "numero do arquivo diferente do nome passou" || ok "numero diferente do NNN do nome reprova"
  mkdir "$d/e4"; cp "$a" "$d/e4/qualquer.md"
  rb_validar "$d/e4/qualquer.md" ft-rec 1 && falha "nome fora do padrão passou" || ok "nome fora do padrão reprova"
  mkdir "$d/e5"; printf 'tests/x.ts\tA\t%s\t%s\t%s\tajuste {{motivo}}\n' 1010101010101010101010101010101010101010 \
    2020202020202020202020202020202020202020 1111111111111111111111111111111111111111111111111111111111111111 > "$d/e5.tsv"
  rb_emitir "$d/e5/RECONCILIACAO-BASE-001.md" "$esc" "$d/e5.tsv" && falha "motivo com {{ foi emitido" || ok "motivo com marcador de template não é emitido"
  mkdir "$d/e6"; printf 'tests/x.ts\tA\t%s\t%s\t%s\t \n' 1010101010101010101010101010101010101010 \
    2020202020202020202020202020202020202020 1111111111111111111111111111111111111111111111111111111111111111 > "$d/e6.tsv"
  sed -i 's/\t $/\t/' "$d/e6.tsv"
  rb_emitir "$d/e6/RECONCILIACAO-BASE-001.md" "$esc" "$d/e6.tsv" && falha "motivo vazio foi emitido" || ok "motivo vazio não é emitido"

  # encadeamento: 002 exige anterior = nome do 001
  mkdir "$d/c"
  sed -e 's/^numero\t1$/numero\t2/' -e 's/^anterior\tnull$/anterior\tRECONCILIACAO-BASE-001.md/' "$esc" > "$d/c/esc2.tsv"
  rb_emitir "$d/c/RECONCILIACAO-BASE-002.md" "$d/c/esc2.tsv" "$arq" && ok "emite o 002 encadeado" || falha "emitir 002: $RB_ERRO"
  rb_validar "$d/c/RECONCILIACAO-BASE-002.md" ft-rec 2 && ok "002 com anterior correto valida" || falha "validar 002: $RB_ERRO"
  sed -e 's/^anterior\tRECONCILIACAO-BASE-001.md$/anterior\tnull/' "$d/c/esc2.tsv" > "$d/c/esc2b.tsv"
  rb_emitir "$d/c/y2.md" "$d/c/esc2b.tsv" "$arq" && falha "002 com anterior null foi emitido" || ok "002 com anterior null não é emitido"
  rb_emitir "$d/c/RECONCILIACAO-BASE-001.md" "$esc" "$arq" || falha "emitir 001 de controle: $RB_ERRO"
  sed -e 's/^anterior\tnull$/anterior\tRECONCILIACAO-BASE-009.md/' "$esc" > "$d/c/esc1b.tsv"
  rb_emitir "$d/c/y.md" "$d/c/esc1b.tsv" "$arq" && falha "001 com anterior preenchido foi emitido" || ok "001 com anterior preenchido não é emitido"

  # rb_diff_sha: igual ao hash do diff do Git
  mkdir "$d/g"
  ( cd "$d/g" && git init -q . && printf 'um\n' > "f g.txt" \
    && git add . && git -c user.name=t -c user.email=t@t commit -q -m a \
    && printf 'dois\n' > "f g.txt" && git -c user.name=t -c user.email=t@t commit -q -am b ) >/dev/null 2>&1
  ret1="$(cd "$d/g" && rb_diff_sha HEAD~1 HEAD "f g.txt")"
  ret2="$(cd "$d/g" && GIT_LITERAL_PATHSPECS=1 git -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false \
    -c diff.suppressBlankEmpty=false -c diff.relative=false diff --no-ext-diff --no-textconv --no-color --binary \
    --full-index --no-renames --no-relative --src-prefix=a/ --dst-prefix=b/ -U3 --inter-hunk-context=0 \
    --diff-algorithm=myers --indent-heuristic HEAD~1 HEAD -- "f g.txt" | sha256sum | cut -d' ' -f1)"
  { [ -n "$ret1" ] && [ "$ret1" = "$ret2" ]; } && ok "rb_diff_sha é o sha256 do diff canônico (spec 7.1)" || falha "rb_diff_sha divergente ($ret1 / $ret2)"
  # independente de configuração local e do cwd
  local ret3 ret4
  ( cd "$d/g" && git config diff.noprefix true && git config diff.algorithm histogram && git config core.abbrev 12 \
    && git config diff.srcPrefix x/ && git config diff.dstPrefix y/ && git config diff.suppressBlankEmpty true \
    && mkdir -p sub ) >/dev/null 2>&1
  ret3="$(cd "$d/g" && rb_diff_sha HEAD~1 HEAD "f g.txt")"
  [ "$ret3" = "$ret1" ] && ok "rb_diff_sha ignora noprefix/algorithm/abbrev/srcPrefix locais" || falha "rb_diff_sha mudou com config local ($ret3 / $ret1)"
  ret4="$(cd "$d/g/sub" && GIT_ICASE_PATHSPECS=1 GIT_DIFF_OPTS=--unified=10 rb_diff_sha HEAD~1 HEAD "f g.txt")"
  [ "$ret4" = "$ret1" ] && ok "rb_diff_sha é da raiz, sem env de diff/pathspec do chamador" || falha "rb_diff_sha mudou no subdiretório ($ret4 / $ret1)"
  ( cd "$d/g" && git config --unset diff.noprefix && git config --unset diff.algorithm && git config --unset core.abbrev \
    && git config --unset diff.srcPrefix && git config --unset diff.dstPrefix && git config --unset diff.suppressBlankEmpty ) >/dev/null 2>&1
  # independente de enxertos locais: refs/replace e .git/info/grafts
  local ret5 ret6 falso
  ( cd "$d/g" && git replace "$(git rev-parse 'HEAD:f g.txt')" "$(printf 'tres\n' | git hash-object -w --stdin)" ) >/dev/null 2>&1
  ret5="$(cd "$d/g" && rb_diff_sha HEAD~1 HEAD "f g.txt")"
  [ "$ret5" = "$ret1" ] && ok "rb_diff_sha ignora refs/replace" || falha "rb_diff_sha seguiu refs/replace ($ret5 / $ret1)"
  ( cd "$d/g" && git replace -d "$(git rev-parse 'HEAD:f g.txt')" ) >/dev/null 2>&1
  falso="$(cd "$d/g" && printf '100644 blob %s\tf g.txt\n' "$(printf 'zero\n' | git hash-object -w --stdin)" | git mktree \
    | xargs -I{} git -c user.name=t -c user.email=t@t commit-tree {} -m falso)"
  printf '%s %s\n' "$(cd "$d/g" && git rev-parse HEAD)" "$falso" > "$d/g/.git/info/grafts"
  ret6="$(cd "$d/g" && rb_diff_sha HEAD~1 HEAD "f g.txt" 2>/dev/null)"
  [ "$ret6" = "$ret1" ] && ok "rb_diff_sha ignora .git/info/grafts" || falha "rb_diff_sha seguiu .git/info/grafts ($ret6 / $ret1)"
  rm -f "$d/g/.git/info/grafts"
  printf 'x' | rb_sha256 | grep -Eq '^[0-9a-f]{64}$' && ok "rb_sha256 devolve 64 hex" || falha "rb_sha256 sem 64 hex"

  # rb_diff_sha falha fechado: ref inexistente não vira "sem diferença"
  local out t ferr
  cd "$d/g" || return
  set +o pipefail   # a biblioteca não pode depender do pipefail do chamador
  RB_ERRO=""; out="$(rb_diff_sha deadbeef HEAD "f g.txt" 2>/dev/null)"; rc=$?
  RB_ERRO=""; rb_diff_sha deadbeef HEAD "f g.txt" >/dev/null 2>&1; rc=$?
  [ "$rc" = 1 ] && ok "rb_diff_sha com ref inexistente retorna 1" || falha "rb_diff_sha com ref ruim: rc=$rc"
  [ -z "$out" ] && ok "rb_diff_sha com ref ruim não imprime hash" || falha "rb_diff_sha com ref ruim imprimiu '$out'"
  [ -n "$RB_ERRO" ] && ok "rb_diff_sha com ref ruim preenche RB_ERRO" || falha "RB_ERRO vazio com ref ruim"
  RB_ERRO=""; rb_diff_sha HEAD~1 HEAD "f g.txt" >/dev/null 2>&1 && ok "rb_diff_sha com refs válidas retorna 0" || falha "rb_diff_sha válido falhou: $RB_ERRO"
  RB_ERRO=""; ( cd "$d" && rb_diff_sha HEAD~1 HEAD x ) >/dev/null 2>&1 && falha "rb_diff_sha fora de repositório passou" || ok "rb_diff_sha fora de repositório retorna 1"
  set -o pipefail
  cd "$REPO" || return

  # erro do parser chega ao chamador (não se perde em subshell)
  mkdir "$d/p1" "$d/p2"
  head -n 8 "$a" > "$d/p1/RECONCILIACAO-BASE-001.md"
  sed 's/^branch: .*/&\nbranch: "outra"/' "$a" > "$d/p2/RECONCILIACAO-BASE-001.md"
  for t in p1:fechamento p2:repetida; do
    RB_ERRO=""; rb_validar "$d/${t%%:*}/RECONCILIACAO-BASE-001.md" ft-rec 1 >/dev/null 2>&1; rc=$?
    { [ "$rc" = 1 ] && case "$RB_ERRO" in *frontmatter*${t##*:}*) true ;; *) false ;; esac; } \
      && ok "rb_validar (${t%%:*}) devolve o erro do parser: $RB_ERRO" || falha "rb_validar (${t%%:*}): rc=$rc RB_ERRO='$RB_ERRO'"
    RB_ERRO=""; rb_assinatura "$d/${t%%:*}/RECONCILIACAO-BASE-001.md" >/dev/null 2>&1; rc=$?
    { [ "$rc" = 1 ] && [ -n "$RB_ERRO" ]; } && ok "rb_assinatura (${t%%:*}) devolve o erro do parser" || falha "rb_assinatura (${t%%:*}): rc=$rc RB_ERRO='$RB_ERRO'"
    RB_ERRO=""; rb_ler "$d/${t%%:*}/RECONCILIACAO-BASE-001.md" >/dev/null 2>&1 && falha "rb_ler (${t%%:*}) passou" || { [ -n "$RB_ERRO" ] && ok "rb_ler (${t%%:*}) devolve o erro do parser" || falha "rb_ler sem RB_ERRO"; }
  done

  # SHA curto, maiúsculo e sha256 curto reprovam. Passam pela emissão, que assina
  # o conteúdo: a assinatura confere, então só a checagem de formato pode barrar.
  mkdir "$d/h"
  for t in b0_sha:39 b1_sha:41 m_sha:39 p1_sha:40U; do
    case "${t##*:}" in
      *U) ferr="$(printf 'C%.0s' $(seq 1 40))" ;;
      *) ferr="$(printf 'a%.0s' $(seq 1 "${t##*:}"))" ;;
    esac
    sed "s/^${t%%:*}\t.*/${t%%:*}\t$ferr/" "$esc" > "$d/h/esc.tsv"
    RB_ERRO=""; rb_emitir "$d/h/RECONCILIACAO-BASE-001.md" "$d/h/esc.tsv" "$arq" >/dev/null 2>&1 && falha "${t%%:*} ${t##*:} foi emitido" || ok "${t%%:*} ${t##*:} não é emitido"
    case "$RB_ERRO" in *"${t%%:*}"*SHA*) ok "o erro cita ${t%%:*}" ;; *) falha "erro não cita ${t%%:*}: $RB_ERRO" ;; esac
  done
  for t in 3:39 4:41 5:63 5:65 5:64U; do
    case "${t##*:}" in
      *U) ferr="$(printf 'D%.0s' $(seq 1 64))" ;;
      *) ferr="$(printf '1%.0s' $(seq 1 "${t##*:}"))" ;;
    esac
    awk -F'\t' -v OFS='\t' -v c="${t%%:*}" -v v="$ferr" 'NR == 1 { $c = v } { print }' "$arq" > "$d/h/arq.tsv"
    RB_ERRO=""; rb_emitir "$d/h/RECONCILIACAO-BASE-001.md" "$esc" "$d/h/arq.tsv" >/dev/null 2>&1 && falha "coluna ${t%%:*} tamanho ${t##*:} foi emitida" || ok "coluna ${t%%:*} com valor inválido (${t##*:}) não é emitida"
  done

  # nome 002 com número esperado 1: só o NNN do nome diverge
  mkdir "$d/n2"; cp "$a" "$d/n2/RECONCILIACAO-BASE-002.md"
  RB_ERRO=""; rb_validar "$d/n2/RECONCILIACAO-BASE-002.md" ft-rec 1 && falha "nome 002 com esperado 1 passou" || ok "NNN do nome diferente do esperado reprova"
  case "$RB_ERRO" in *nome*|*NNN*) ok "o erro cita o nome" ;; *) falha "erro não cita o nome: $RB_ERRO" ;; esac

  # caminho repetido e status_base fora do enum, na emissão
  mkdir "$d/r1"
  { sed -n 1p "$arq"; sed -n 1p "$arq"; } > "$d/r1.tsv"
  RB_ERRO=""; rb_emitir "$d/r1/RECONCILIACAO-BASE-001.md" "$esc" "$d/r1.tsv" && falha "caminho repetido foi emitido" || ok "caminho repetido não é emitido"
  case "$RB_ERRO" in *repetido*) ok "o erro cita o caminho repetido" ;; *) falha "erro não cita repetido: $RB_ERRO" ;; esac
  sed 's/\tA\t/\tX\t/' "$arq" > "$d/r2.tsv"
  RB_ERRO=""; rb_emitir "$d/r1/RECONCILIACAO-BASE-001.md" "$esc" "$d/r2.tsv" && falha "status_base X foi emitido" || ok "status_base fora do enum não é emitido"
  case "$RB_ERRO" in *status_base*) ok "o erro cita status_base" ;; *) falha "erro não cita status_base: $RB_ERRO" ;; esac

  # caminhos com ".." : só o segmento exato é recusado
  for t in 'docs/v1..v2.md:0' 'a..b:0' '..x/y:0' '../x:1' 'a/../b:1' 'a/..:1' '..:1' '/abs/x:1'; do
    printf '%s\tA\t%s\t%s\t%s\tmotivo\n' "${t%:*}" 1010101010101010101010101010101010101010 \
      2020202020202020202020202020202020202020 1111111111111111111111111111111111111111111111111111111111111111 > "$d/dd.tsv"
    RB_ERRO=""; rb_emitir "$d/r1/RECONCILIACAO-BASE-001.md" "$esc" "$d/dd.tsv" >/dev/null 2>&1; rc=$?
    [ "$rc" = "${t##*:}" ] && ok "caminho '${t%:*}': rc=$rc" || falha "caminho '${t%:*}': rc=$rc, esperava ${t##*:}"
  done

  # sem ferramenta de hash: falha fechado, isolando só sha256sum/shasum
  mkdir "$d/vazio" "$d/semhash"
  for t in cut grep sed awk; do ln -s "$(command -v $t)" "$d/semhash/$t" 2>/dev/null; done
  RB_ERRO=""; printf x > "$d/x.bin"; ferr="$( PATH="$d/semhash"; rb_sha256 < "$d/x.bin" >/dev/null 2>&1; echo "rc=$? ERRO=$RB_ERRO" )"
  case "$ferr" in
    "rc=1 ERRO="?*) ok "sem ferramenta de hash falha fechado com RB_ERRO ($ferr)" ;;
    *) falha "sem ferramenta de hash: $ferr" ;;
  esac
  ln -s "$(command -v sha256sum)" "$d/semhash/sha256sum"
  ferr="$( PATH="$d/semhash"; rb_sha256 < "$d/x.bin" )"
  printf '%s' "$ferr" | grep -Eq '^[0-9a-f]{64}$' && ok "controle: com sha256sum no mesmo PATH o hash sai" || falha "controle sem hash falhou: $ferr"
}

# --- apoio do grupo provas ---------------------------------------------------

# rc_motivo <desc> <rc> <trecho> <cmd...> — exige o rc e o trecho no stderr:
# um rc 4 vindo da causa errada não passa.
rc_motivo() {
  local desc="$1" esperado="$2" trecho="$3" rc err; shift 3
  err="$("$@" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" != "$esperado" ]; then falha "$desc — rc=$rc, esperava $esperado: $err"; return; fi
  case "$err" in
    *"$trecho"*) ok "$desc" ;;
    *) falha "$desc — stderr sem '$trecho': $err" ;;
  esac
}

# o diff canônico da spec 7.1, escrito por extenso (não pela biblioteca)
_diff_canonico() { # <b1> <m> <caminho>
  GIT_LITERAL_PATHSPECS=1 git -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false \
    -c diff.suppressBlankEmpty=false -c diff.relative=false diff --no-ext-diff --no-textconv --no-color --binary \
    --full-index --no-renames --no-relative --src-prefix=a/ --dst-prefix=b/ -U3 --inter-hunk-context=0 \
    --diff-algorithm=myers --indent-heuristic "$1" "$2" -- "$3"
}

# foto da árvore: status, conteúdo não commitado e HEAD
_foto() {
  git status --porcelain=v1 --untracked-files=all
  git diff | rb_sha256
  git rev-parse HEAD
}

# reprova <desc> <rc> <trecho> <caminho>... — registro reprovado não grava nada
# e devolve a trava C5. Usa o array `r` do grupo.
reprova() {
  local desc="$1" esperado="$2" trecho="$3" antes antes_rb; shift 3
  antes="$(_foto)"
  antes_rb="$(ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md 2>/dev/null)"
  rc_motivo "$desc" "$esperado" "$trecho" "${r[@]}" "$@"
  if [ "$(_foto)" = "$antes" ] && [ "$(ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md 2>/dev/null)" = "$antes_rb" ]; then
    ok "$desc: nada gravado"
  else falha "$desc: a árvore mudou"; fi
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "$desc: trava livre" || falha "$desc: trava presa"
}

# desfaz — devolve a árvore ao estado anterior ao registro (sem git clean)
desfaz() {
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md
  git restore -- "$FX_ENTREGA"
}

# registra_ok <desc> <caminho>... — rc 0, saída, artefato válido e provas no
# artefato iguais às recalculadas do Git; só o artefato é gravado.
registra_ok() {
  local desc="$1" out a lido f st bb bm ds t antes esperado; shift
  antes="$(git status --porcelain=v1 --untracked-files=all)"
  out="$("${r[@]}" "$@" 2>&1)" || { falha "$desc — rc=$?: $out"; return; }
  ok "$desc"
  a=docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  esperado="registrado=RECONCILIACAO-BASE-001.md
b0=$FX_B0
p1=$FX_P1
b1=$FX_B1
m=$FX_M"
  [ "$out" = "$esperado" ] && ok "$desc: saída registrado/b0/p1/b1/m" || falha "$desc: saída divergente: $out"
  rb_validar "$a" ft-rec 1 && ok "$desc: artefato válido" || { falha "$desc: artefato inválido: $RB_ERRO"; return; }
  lido="$(rb_ler "$a")"
  for t in "anterior	null" "origem_base	registrada_e0" "estado	ativa" "b0_sha	$FX_B0" \
           "p1_sha	$FX_P1" "b1_sha	$FX_B1" "m_sha	$FX_M" "branch	feature/ft-rec" "branch_base	main"; do
    printf '%s\n' "$lido" | grep -Fxq "escalar	$t" && ok "$desc: $t" || falha "$desc: escalar ${t%%	*} divergente"
  done
  [ "$(printf '%s\n' "$lido" | awk -F'\t' '$1 == "arquivo" { print $2 }' | LC_ALL=C sort)" \
    = "$(printf '%s\n' "$@" | LC_ALL=C sort)" ] && ok "$desc: caminhos exatamente os dados" || falha "$desc: caminhos divergentes"
  while IFS=$'\t' read -r _ f st bb bm ds _; do
    [ -n "$f" ] || continue
    [ "$st" = "$(git -c core.quotepath=false diff --no-renames --name-status -z "$FX_B0" "$FX_B1" -- ":(literal)$f" | tr '\0' '\n' | head -n1)" ] \
      && [ "$bb" = "$(git rev-parse "$FX_B1:$f")" ] && [ "$bm" = "$(git rev-parse "$FX_M:$f")" ] \
      && [ "$ds" = "$(_diff_canonico "$FX_B1" "$FX_M" "$f" | rb_sha256)" ] \
      && ok "$desc: status, blobs e diff de '$f' conferem com o Git" || falha "$desc: provas gravadas de '$f' divergem do Git"
  done <<EOF
$(printf '%s\n' "$lido" | grep '^arquivo	')
EOF
  # o registro grava o artefato e o ENTREGA.md, e mais nada
  esperado="$(printf '%s\n %s\n?? %s\n' "$antes" "M $FX_ENTREGA" "$a" | sed '/^$/d' | LC_ALL=C sort -u)"
  [ "$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort -u)" = "$esperado" ] \
    && ok "$desc: só o artefato e o ENTREGA.md foram gravados" || falha "$desc: gravou além do artefato e do ENTREGA.md"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "$desc: trava livre" || falha "$desc: trava presa"
}

grupo_provas() {
  local d t r variante lista l antes c
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  . "$S/catalogo-de-metodo.sh" || { falha "catálogo ausente"; return; }

  # catalogo_pasta_do_trabalho: as regras de persistir-metodo.sh
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  mkdir -p "$d/docs/sprintx/features/fc" "$d/docs/fl" "$d/docs/sprintx/features/fd" "$d/docs/fd" "$d/docs/manutencao/rx"
  [ "$(catalogo_pasta_do_trabalho "$d" sprintx fc)" = docs/sprintx/features/fc ] && ok "pasta: SprintX canônica" || falha "pasta canônica"
  [ "$(catalogo_pasta_do_trabalho "$d" sprintx fl)" = docs/fl ] && ok "pasta: SprintX legada" || falha "pasta legada"
  if catalogo_pasta_do_trabalho "$d" sprintx fd >/dev/null; then falha "pasta: duas pastas passou"
  else case "$CATALOGO_ERRO" in *"duas pastas"*) ok "pasta: duas pastas SprintX é erro" ;; *) falha "pasta: erro '$CATALOGO_ERRO'" ;; esac; fi
  catalogo_pasta_do_trabalho "$d" sprintx nada >/dev/null && falha "pasta SprintX ausente passou" || ok "pasta: SprintX ausente é erro"
  [ "$(catalogo_pasta_do_trabalho "$d" runx rx)" = docs/manutencao/rx ] && ok "pasta: RunX" || falha "pasta RunX"
  catalogo_pasta_do_trabalho "$d" runx nada >/dev/null && falha "pasta RunX ausente passou" || ok "pasta: RunX ausente é erro"
  catalogo_pasta_do_trabalho "$d" n/a fc >/dev/null && falha "pasta de origem n/a passou" || ok "pasta: origem sem pasta é erro"

  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  antes="$(_foto)"
  registra_ok "registra os dois testes da base" "$FX_NOVO1" "$FX_NOVO2"
  desfaz
  [ "$(_foto)" = "$antes" ] && ok "sem o artefato e com o ENTREGA.md restaurado, a árvore volta ao estado anterior" || falha "árvore não voltou"

  reprova "inventário: falta um caminho alterado pelo merge" 4 "inventário: $FX_NOVO2" "$FX_NOVO1"
  reprova "prova 3: caminho das tasks" 4 "prova 3: src/painel.ts" "$FX_NOVO1" "$FX_NOVO2" src/painel.ts
  reprova "prova 3: artefato de método" 4 "prova 3: $FX_ENTREGA" "$FX_NOVO1" "$FX_NOVO2" "$FX_ENTREGA"
  reprova "prova 1: arquivo que a base não tocou" 4 "prova 1: README.md" "$FX_NOVO1" "$FX_NOVO2" README.md
  reprova "prova 2: arquivo tocado pela feature" 4 "prova 2: tests/ui/ft-rec.test.ts" "$FX_NOVO1" "$FX_NOVO2" tests/ui/ft-rec.test.ts

  # pathspec literal: um glob não casa os dois testes da base
  reprova "glob na lista é caminho literal" 4 "prova 1: tests/ui/*-ksmv-primitives.test.tsx:" \
    "$FX_NOVO1" "$FX_NOVO2" 'tests/ui/*-ksmv-primitives.test.tsx'

  # plano e entrega lidos do disco: têm de estar iguais a HEAD
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  awk -v nova="      altera: [src/painel.ts, $FX_NOVO2]" '/^      altera: / { print nova; next } { print }' \
    docs/sprintx/features/ft-rec/sprint-01/tasks.md > "$t/tasks.md" && cat "$t/tasks.md" > docs/sprintx/features/ft-rec/sprint-01/tasks.md
  grep -Fq "$FX_NOVO2" docs/sprintx/features/ft-rec/sprint-01/tasks.md || falha "tasks.md não foi editado"
  reprova "tasks.md editado sem commit declarando NOVO2" 3 "pasta do trabalho com alteração não commitada" "$FX_NOVO1"
  git restore -- docs/sprintx/features/ft-rec/sprint-01/tasks.md
  printf 'rascunho\n' > docs/sprintx/features/ft-rec/RASCUNHO.md
  reprova "arquivo não rastreado na pasta do trabalho" 3 "pasta do trabalho com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  rm -f docs/sprintx/features/ft-rec/RASCUNHO.md
  printf 'rascunho\n' > docs/entregas/ft-rec/NOTAS.md
  reprova "arquivo não rastreado na pasta da entrega" 3 "pasta do trabalho com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  rm -f docs/entregas/ft-rec/NOTAS.md

  # pasta da entrega: só o que o próprio registro grava fica tolerado
  printf '\nNota local.\n' >> "$FX_ENTREGA"
  # a pasta limpa tolera o ENTREGA.md alterado; a gravação não: nunca se
  # sobrescreve edição alheia (rc 3, nada gravado)
  reprova "ENTREGA.md alterado: a pasta limpa tolera, a gravação recusa" 3 "ENTREGA.md com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  printf 'qualquer\n' > docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  local err_a
  err_a="$("${r[@]}" "$FX_NOVO1" "$FX_NOVO2" 2>&1 >/dev/null)"; c=$?
  { [ "$c" = 5 ] && case "$err_a" in *"artefato órfão de registro interrompido: RECONCILIACAO-BASE-001.md"*) true ;; *) false ;; esac; } \
    && ok "artefato não rastreado + ENTREGA.md alterado: segue para a regra seguinte (rc 5)" \
    || falha "artefato não rastreado + ENTREGA.md alterado: rc=$c $err_a"
  case "$err_a" in *"pasta do trabalho com alteração"*) falha "o motivo foi a pasta suja: $err_a" ;; *) ok "o motivo não é a pasta suja" ;; esac
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  printf 'pacote\n' > docs/entregas/ft-rec/QA.md
  reprova "QA.md não rastreado na pasta da entrega" 3 "QA.md" "$FX_NOVO1" "$FX_NOVO2"
  rm -f docs/entregas/ft-rec/QA.md
  git restore -- "$FX_ENTREGA"
  printf '\nmais\n' >> docs/entregas/ft-rec/ATENCAO.md
  reprova "ATENCAO.md alterado na pasta da entrega" 3 "ATENCAO.md" "$FX_NOVO1" "$FX_NOVO2"
  git restore -- docs/entregas/ft-rec/ATENCAO.md
  for c in RECONCILIACAO-BASE-001.md.bak RECONCILIACAO-BASE-x.md RECONCILIACAO-BASE-0001.md; do
    printf 'x\n' > "docs/entregas/ft-rec/$c"
    reprova "$c não rastreado na pasta da entrega" 3 "$c" "$FX_NOVO1" "$FX_NOVO2"
    rm -f "docs/entregas/ft-rec/$c"
  done
  # artefato existente como link simbólico quebrado também é reconciliação existente
  ln -s /nao/existe docs/entregas/ft-rec/RECONCILIACAO-BASE-007.md
  reprova "RECONCILIACAO-BASE-007.md link quebrado" 5 "artefato órfão de registro interrompido: RECONCILIACAO-BASE-007.md" "$FX_NOVO1" "$FX_NOVO2"
  rm -f docs/entregas/ft-rec/RECONCILIACAO-BASE-007.md

  # plano escondido do status (ignorado, skip-worktree, assume-unchanged): a
  # união vem de M, então NOVO2 continua fora e o inventário reprova
  local tk; tk=docs/sprintx/features/ft-rec/sprint-01/tasks.md
  mkdir -p docs/sprintx/features/ft-rec/sprint-02
  sed -e "s|altera: \[src/painel.ts\]|altera: [src/painel.ts, $FX_NOVO2]|" -e 's/T-01\.01/T-02.01/g' "$tk" \
    > docs/sprintx/features/ft-rec/sprint-02/tasks.md
  cp .git/info/exclude "$t/exclude.bak" 2>/dev/null || : > "$t/exclude.bak"
  printf 'docs/sprintx/features/ft-rec/sprint-02/\n' >> .git/info/exclude
  [ -z "$(git status --porcelain --untracked-files=all -- docs/sprintx/features/ft-rec)" ] || falha "sprint-02 não ficou ignorada"
  reprova "tasks.md ignorado (.git/info/exclude) declarando NOVO2" 4 "inventário: $FX_NOVO2" "$FX_NOVO1"
  rm -rf docs/sprintx/features/ft-rec/sprint-02; cat "$t/exclude.bak" > .git/info/exclude
  for c in skip-worktree assume-unchanged; do
    git update-index "--$c" "$tk"
    sed "s|altera: \[src/painel.ts\]|altera: [src/painel.ts, $FX_NOVO2]|" "$tk" > "$t/tasks.md" && cat "$t/tasks.md" > "$tk"
    [ -z "$(git status --porcelain --untracked-files=all -- docs/sprintx/features/ft-rec)" ] || falha "$c: tasks.md visível no status"
    reprova "tasks.md com --$c declarando NOVO2" 4 "inventário: $FX_NOVO2" "$FX_NOVO1"
    git update-index "--no-$c" "$tk"; git restore -- "$tk"
  done

  # ENTREGA.md sujo (tolerado) não entra nas provas: vale a versão de M
  sed 's/^branch_base: main$/branch_base: HEAD/' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  sed "s/^base_validada_sha: .*/base_validada_sha: $(git rev-parse "$FX_P1~4")/" "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  reprova "ENTREGA.md sujo (branch_base HEAD, B0 do plano): vale a versão de M e a gravação recusa" 3 \
    "ENTREGA.md com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  git restore -- "$FX_ENTREGA"

  # prova 4 com o git falhando no diff --quiet: erro nunca vira diferença
  mkdir -p "$t/shim"
  printf '#!/usr/bin/env bash\nq=0; c=0\nfor a in "$@"; do case "$a" in --quiet) q=1 ;; --cached) c=1 ;; esac; done\n[ "$q" = 1 ] && [ "$c" = 0 ] && exit 128\nexec %s "$@"\n' \
    "$(command -v git)" > "$t/shim/git"
  chmod +x "$t/shim/git"
  rc_motivo "prova 4: erro do git no diff não aprova" 4 "prova 4: $FX_NOVO1: sem diferença entre B1 e M (ou diff não calculável, rc=128)" \
    env PATH="$t/shim:$PATH" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md >/dev/null 2>&1 && falha "erro do git gravou" || ok "erro do git: nada gravado"

  # pathspec do chamador não muda o registro válido
  local r_orig; r_orig=("${r[@]}")
  r=(env GIT_ICASE_PATHSPECS=1 GIT_GLOB_PATHSPECS=1 "${r_orig[@]}")
  registra_ok "GIT_ICASE_PATHSPECS/GIT_GLOB_PATHSPECS do chamador" "$FX_NOVO1" "$FX_NOVO2"
  r=("${r_orig[@]}")
  desfaz

  # contexto explícito, uso e pré-condições
  rc_motivo "origem divergente do ENTREGA.md" 5 "expx_tool" \
    bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "--entrega de outro trabalho é uso" 64 bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho outro -- "$FX_NOVO1"
  for c in --force --sem-prova --desconhecida; do
    rc_igual "opção $c recusada" 64 bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec "$c" -- "$FX_NOVO1" "$FX_NOVO2"
  done
  rc_igual "sem --registrar é uso" 64 bash "$RB" --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "sem -- é uso" 64 bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  reprova "caminho repetido na lista é uso" 64 "repetido" "$FX_NOVO1" "$FX_NOVO2" "$FX_NOVO1"
  reprova "caminho absoluto é uso" 64 "caminho" "$FX_NOVO1" "$FX_NOVO2" /etc/passwd
  printf '\n' >> README.md; git add README.md
  rc_motivo "stage não vazio" 3 "stage" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  git restore --staged README.md; git restore README.md
  git switch -q -c outra
  reprova "branch ativa diverge de ENTREGA.branch" 5 "branch" "$FX_NOVO1" "$FX_NOVO2"
  git switch -q feature/ft-rec
  git branch -q -D outra
  [ "$(_foto)" = "$antes" ] && ok "fixture intacta depois dos casos de reprovação" || falha "fixture alterada"
  cd "$REPO" || return

  local rce
  for variante in base_removeu integracao_removeu renomeado resolucao_igual_base m_um_pai pais_trocados \
    fora_primeiro_pai m_sem_integra_base m_com_metodo substring_declarado tipo_mudou b0_fora_b1 b0_fora_p1 \
    b0_ref entrega_kind entrega_trabalho entrega_sem_branch_base entrega_symlink plano_symlink entrega_no_merge; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"
    FX_VARIANTE="$variante" fx_cenario "$d" || { falha "variante $variante não montou"; continue; }
    cd "$d" || return
    lista=(); while IFS= read -r l; do lista+=("$l"); done <<EOF
$FX_LISTA_VARIANTE
EOF
    rce=4
    case "$variante" in
      base_removeu|renomeado) c="prova 1: README.md" ;;
      integracao_removeu|resolucao_igual_base) c="prova 4: $FX_NOVO2" ;;
      m_um_pai) c="estrutura[pais]" ;;
      fora_primeiro_pai) c="estrutura[base]" ;;
      substring_declarado) c="inventário: tests/ui/ft-rec.test: " ;;
      tipo_mudou) c="prova 1: README.md: status T" ;;
      b0_fora_b1) c="estrutura[b0_b1]" ;;
      b0_fora_p1) c="estrutura[b0_p1]" ;;
      entrega_no_merge) c="estrutura[entrega]" ;;
      b0_ref) rce=5; c="base_validada_sha não é SHA" ;;
      entrega_kind) rce=5; c="não declara kind: entrega" ;;
      entrega_trabalho) rce=5; c="diverge de ENTREGA.trabalho_id" ;;
      entrega_sem_branch_base) rce=5; c="ENTREGA.branch_base ausente" ;;
      entrega_symlink) rce=5; c="não é arquivo regular" ;;
      plano_symlink) rce=5; c="link simbólico ou submódulo" ;;
      *) c="estrutura[contrato]" ;;
    esac
    reprova "variante $variante reprova" "$rce" "$c" "${lista[@]}"
    cd "$REPO" || return
  done

  # catálogo vem de M: um 00-INDICE.md só no disco (ignorado) não transforma
  # em método a área que o merge criou
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=merge_area_base fx_cenario "$d" || { falha "variante merge_area_base não montou"; return; }
  cd "$d" || return
  printf -- '---\nexpx_schema: 1\nkind: base_indice\ntrabalho_id: ft-rec\nareas:\n  - arquivo: notas.md\n---\n' \
    > docs/sprintx/features/ft-rec/base/00-INDICE.md
  printf 'docs/sprintx/features/ft-rec/base/00-INDICE.md\n' >> .git/info/exclude
  [ -z "$(git status --porcelain --untracked-files=all -- docs/sprintx/features/ft-rec)" ] || falha "00-INDICE.md não ficou ignorado"
  reprova "00-INDICE.md só no disco não vira catálogo" 4 "inventário: docs/sprintx/features/ft-rec/base/notas.md" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # a pasta do trabalho é resolvida em M: uma pasta legada só no disco
  # (ignorada) não cria a ambiguidade "duas pastas"
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  mkdir -p docs/ft-rec; printf 'x\n' > docs/ft-rec/rascunho.md
  printf 'docs/ft-rec/\n' >> .git/info/exclude
  registra_ok "pasta legada só no disco não muda a resolução" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # nome com quebra de linha na pasta do trabalho em M: a lista de tasks.md da
  # união é separada por linha, e `foo<NL>/abs/tasks.md` viraria um tasks.md
  # do disco. A materialização recusa o nome (rc 5) antes de qualquer prova.
  local alvo; alvo="$(mktemp -d)"; TMPS="$TMPS $alvo"
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_NL_ALVO="$alvo" FX_VARIANTE=plano_nl fx_cenario "$d" || { falha "variante plano_nl não montou"; return; }
  cd "$d" || return
  sed "s|altera: \[src/painel.ts\]|altera: [src/painel.ts, $FX_NOVO2]|" docs/sprintx/features/ft-rec/sprint-01/tasks.md > "$alvo/tasks.md"
  grep -Fq "$FX_NOVO2" "$alvo/tasks.md" || falha "o tasks.md do disco não declara NOVO2"
  [ "$(git ls-tree -r --name-only -z HEAD -- docs/sprintx/features/ft-rec | tr '\0' '\n' | grep -Fxc "$alvo/tasks.md")" = 1 ] \
    || falha "M não tem o caminho com quebra de linha"
  reprova "caminho com quebra de linha em M aponta para tasks.md do disco" 5 \
    "pasta do trabalho em M com caminho inválido" "$FX_NOVO1"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=plano_tab fx_cenario "$d" || { falha "variante plano_tab não montou"; return; }
  cd "$d" || return
  reprova "caminho com TAB na pasta do trabalho em M" 5 "pasta do trabalho em M com caminho inválido" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # componente `..` numa árvore de M (git mktree) nunca escreve fora do
  # temporário. M' = M + ft-rec/<40 x ..>/<alvo>/escrito.txt; o índice esparso
  # é ajustado para casar com M' (o índice comum recusa o caminho).
  # O mesmo com componente `.` (fica dentro do temporário, mas também é recusado).
  local fora cadeia comp i ftrec feat sx docs raiz mlinha osx odocs oraiz pontual
  for pontual in .. .; do
  fora="$(mktemp -d)"; TMPS="$TMPS $fora"
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  cadeia="$(printf 'escrito fora do temporário\n' | git hash-object -w --stdin)"
  cadeia="$(printf '100644 blob %s\tescrito.txt\n' "$cadeia" | git mktree)"
  comp="$fora"
  while [ -n "$comp" ] && [ "$comp" != / ]; do
    cadeia="$(printf '040000 tree %s\t%s\n' "$cadeia" "${comp##*/}" | git mktree)"
    comp="${comp%/*}"
  done
  i=0; while [ "$i" -lt 40 ]; do cadeia="$(printf '040000 tree %s\t%s\n' "$cadeia" "$pontual" | git mktree)"; i=$((i + 1)); done
  ftrec="$( { git ls-tree HEAD:docs/sprintx/features/ft-rec; printf '040000 tree %s\t%s\n' "$cadeia" "$pontual"; } | git mktree)"
  feat="$( { git ls-tree HEAD:docs/sprintx/features | grep -v '	ft-rec$'; printf '040000 tree %s\tft-rec\n' "$ftrec"; } | git mktree)"
  sx="$( { git ls-tree HEAD:docs/sprintx | grep -v '	features$'; printf '040000 tree %s\tfeatures\n' "$feat"; } | git mktree)"
  docs="$( { git ls-tree HEAD:docs | grep -v '	sprintx$'; printf '040000 tree %s\tsprintx\n' "$sx"; } | git mktree)"
  raiz="$( { git ls-tree HEAD | grep -v '	docs$'; printf '040000 tree %s\tdocs\n' "$docs"; } | git mktree)"
  mlinha="$(git log -1 --format=%B HEAD | git commit-tree "$raiz" -p "$FX_P1" -p "$FX_B1")"
  git config index.sparse true
  git sparse-checkout set --cone src tests docs/entregas >/dev/null 2>&1 || falha "sparse-checkout falhou"
  osx="$(git rev-parse HEAD:docs/sprintx)"; odocs="$(git rev-parse HEAD:docs)"; oraiz="$(git rev-parse 'HEAD^{tree}')"
  git update-ref HEAD "$mlinha"
  perl -e 'use Digest::SHA qw(sha1); my $p = shift; local $/; open(my $f, "<:raw", $p) or die; my $b = <$f>; close $f;
    substr($b, -20) = ""; while (@ARGV) { my ($a, $n) = (pack("H*", shift), pack("H*", shift)); $b =~ s/\Q$a\E/$n/g; }
    open($f, ">:raw", $p) or die; print $f $b, sha1($b); close $f' .git/index "$osx" "$sx" "$odocs" "$docs" "$oraiz" "$raiz" \
    || falha "índice esparso não ajustado"
  git ls-tree -r --name-only --full-tree HEAD -- docs/sprintx/features/ft-rec | grep -Fq "/$pontual/" || falha "M' sem componente $pontual"
  git diff --cached --quiet || falha "o índice não casa com M' ($pontual)"
  reprova "componente $pontual numa árvore de M" 5 "pasta do trabalho em M com caminho inválido (componente vazio, . ou ..)" \
    "$FX_NOVO1" "$FX_NOVO2"
  [ ! -e "$fora/escrito.txt" ] && ok "componente $pontual: nada escrito fora do temporário" || falha "componente $pontual: escreveu $fora/escrito.txt"
  cd "$REPO" || return
  done

  # canônica e legada em M: erro, com o motivo do catálogo no stderr
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=duas_pastas fx_cenario "$d" || { falha "variante duas_pastas não montou"; return; }
  cd "$d" || return
  reprova "canônica e legada em M" 4 "pasta do trabalho não determinável em M: há duas pastas SprintX para ft-rec" \
    "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # RunX: a pasta docs/manutencao/<t> de M é a pasta do trabalho
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=runx fx_cenario "$d" || { falha "variante runx não montou"; return; }
  cd "$d" || return
  r_orig=("${r[@]}")
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec --)
  registra_ok "RunX com docs/manutencao/ft-rec em M registra" "$FX_NOVO1" "$FX_NOVO2"
  r=("${r_orig[@]}")
  cd "$REPO" || return

  # enxertos locais (refs/replace e .git/info/grafts) não falsificam os pais de M
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=m_um_pai fx_cenario "$d" || { falha "variante m_um_pai não montou"; return; }
  cd "$d" || return
  git replace --graft "$FX_M" "$FX_P1" "$FX_B1"
  [ "$(git rev-list --parents -n1 HEAD | wc -w)" = 3 ] || falha "replace --graft não enxertou dois pais"
  reprova "m_um_pai com git replace --graft" 4 "estrutura[pais]" "$FX_NOVO1" "$FX_NOVO2"
  git replace -d "$FX_M" >/dev/null
  printf '%s %s %s\n' "$FX_M" "$FX_P1" "$FX_B1" > .git/info/grafts
  [ "$(git rev-list --parents -n1 HEAD 2>/dev/null | wc -w)" = 3 ] || falha ".git/info/grafts não enxertou dois pais"
  reprova "m_um_pai com .git/info/grafts" 4 "estrutura[pais]" "$FX_NOVO1" "$FX_NOVO2"
  rm -f .git/info/grafts
  cd "$REPO" || return

  # branch_base sujo no disco não afrouxa a condição estrutural da base
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=fora_primeiro_pai fx_cenario "$d" || { falha "variante fora_primeiro_pai não montou"; return; }
  cd "$d" || return
  sed 's|^branch_base: main$|branch_base: feature/ft-rec|' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  grep -q '^branch_base: feature/ft-rec$' "$FX_ENTREGA" || falha "branch_base não foi editado"
  reprova "fora_primeiro_pai com branch_base sujo = feature/ft-rec" 4 "estrutura[base]"
  cd "$REPO" || return

  # diretório nunca é caminho reconciliado
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=diretorio fx_cenario "$d" || { falha "variante diretorio não montou"; return; }
  cd "$d" || return
  reprova "diretório na lista reprova" 4 "arquivo: tests/base: não é arquivo (blob)" \
    "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts tests/base
  reprova "caminho com barra final reprova" 4 "arquivo: tests/base/: caminho com barra final" \
    "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts tests/base/
  registra_ok "controle: só os arquivos do diretório registram" "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts
  cd "$REPO" || return
  for variante in caminho_especial base_alterou; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"
    FX_VARIANTE="$variante" fx_cenario "$d" || { falha "variante $variante não montou"; continue; }
    cd "$d" || return
    lista=(); while IFS= read -r l; do lista+=("$l"); done <<EOF
$FX_LISTA_VARIANTE
EOF
    registra_ok "variante $variante registra" "${lista[@]}"
    case "$variante" in
      caminho_especial)
        { [ "${#lista[@]}" = 3 ] && [ "${lista[2]}" = "$FX_ESPECIAL" ]; } && ok "a lista traz o caminho especial inteiro" || falha "lista partida"
        rb_ler docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md | awk -F'\t' '$1 == "arquivo" { print $2 }' \
          | grep -Fxq -- "$FX_ESPECIAL" && ok "o artefato tem exatamente o caminho especial" || falha "caminho especial alterado no artefato" ;;
      base_alterou)
        rb_ler docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md | grep -q '^arquivo	README.md	M	' \
          && ok "README.md registrado com status_base M" || falha "status_base de README.md" ;;
    esac
    cd "$REPO" || return
  done

  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_merge_sem_commit "$d" || { falha "merge sem commit não montou"; return; }
  cd "$d" || return
  reprova "merge em andamento" 3 "merge em andamento" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  bash "$TRAVA" --adquirir teste-r1 >/dev/null
  rc_motivo "trava C5 ocupada" 2 "trava" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md >/dev/null 2>&1 && falha "trava ocupada gravou" || ok "trava ocupada: nada gravado"
  cd "$REPO" || return
}

# Frontmatter do ENTREGA.md, uma linha por chave de topo: `chave<TAB>bloco`,
# com as linhas de continuação (aninhadas) coladas por \001. Linhas em ordem.
_blocos() { # <arquivo>
  awk '
    NR == 1 { next }
    /^---[ \t]*\r?$/ { exit }
    /^[A-Za-z0-9_]+:/ { if (chave != "") print chave "\t" bloco; chave = $0; sub(/:.*/, "", chave); bloco = $0; next }
    { bloco = bloco "\001" $0 }
    END { if (chave != "") print chave "\t" bloco }
  ' "$1"
}

# Corpo depois do `---` de fechamento, byte a byte.
_corpo() { # <arquivo>
  local n; n="$(awk 'NR == 1 { next } /^---[ \t]*\r?$/ { print NR; exit }' "$1")"
  tail -n "+$((n + 1))" "$1"
}

# Linha de uma chave de topo (valor), sem CR.
_chave() { # <arquivo> <chave>
  awk -v c="$2" 'NR > 1 && /^---[ \t]*\r?$/ { exit } index($0, c ": ") == 1 { sub(/^[^:]*: */, ""); sub(/\r$/, ""); print; exit }' "$1"
}

# entrega_confere <desc> <antes.md> <depois.md> <chave-gravada>... — as chaves
# de topo fora da lista ficam byte a byte iguais (mesma ordem, mesmo bloco
# aninhado); o corpo depois do frontmatter também.
entrega_confere() {
  local desc="$1" antes="$2" depois="$3" k ka kd; shift 3
  ka="$(_blocos "$antes" | cut -f1 | tr '\n' ' ')"; kd="$(_blocos "$depois" | cut -f1 | tr '\n' ' ')"
  # as chaves que o registro insere entram antes do fechamento: a ordem das
  # que já existiam não muda
  for k in "$@"; do ka="$(printf '%s' "$ka" | sed "s/ $k / /; s/^$k //")"; kd="$(printf '%s' "$kd" | sed "s/ $k / /; s/^$k //")"; done
  [ "$ka" = "$kd" ] && ok "$desc: mesmas chaves de topo, na mesma ordem" || falha "$desc: chaves de topo diferentes ($ka | $kd)"
  local excl="" bad=""
  for k in "$@"; do excl="$excl $k "; done
  while IFS="$(printf '\t')" read -r k b; do
    case "$excl" in *" $k "*) continue ;; esac
    [ "$b" = "$(_blocos "$depois" | awk -F'\t' -v k="$k" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }')" ] || bad="$bad $k"
  done <<EOF
$(_blocos "$antes")
EOF
  [ -z "$bad" ] && ok "$desc: demais chaves intactas (inclusive commits, seq, branch, trabalho_id, kind, expx_tool)" || falha "$desc: chaves alteradas:$bad"
  [ "$(_corpo "$antes" | rb_sha256)" = "$(_corpo "$depois" | rb_sha256)" ] && cmp -s <(_corpo "$antes") <(_corpo "$depois") \
    && ok "$desc: corpo depois do frontmatter byte a byte igual" || falha "$desc: corpo alterado"
}

GRAVADAS="base_validada_sha estado portao portao_sha falhas_portao causa push_feito entregue_em atualizado_em reconciliacoes"

# --- apoio dos testes de interrupção -----------------------------------------
# A ordem dos eventos é decidida por marcador, nunca por `sleep` fixo: o `mv`
# do PATH chega ao ponto exato, grava o próprio pid no marcador e bloqueia;
# o teste espera o marcador (com limite), sinaliza o script, espera-o com
# `wait` e só então mata o shim que ficou órfão.
SHIM_NOME=r1-shim-bloqueado

# _shim_bloqueio <arquivo> <padrão> <antes|depois> <marcador> — escreve um
# `mv` que, quando o último argumento casa com <padrão> (padrão de `case`),
# roda o `mv` real primeiro (só em `depois`), grava o próprio pid em
# <marcador> (escrita atômica) e bloqueia num `sleep` com argv[0] próprio
# (`$SHIM_NOME`) até o teste matá-lo. Os demais `mv` passam direto.
_shim_bloqueio() {
  local arq="$1" padrao="$2" quando="$3" marca="$4" real
  real="$(command -v mv)"
  rm -f "$marca" "$marca.tmp"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do ultimo="$a"; done\n'
    printf 'case "$ultimo" in %s)\n' "$padrao"
    [ "$quando" = depois ] && printf '  %q "$@"\n' "$real"
    printf '  printf "%%s\\n" "$$" > %q && %q %q %q\n' "$marca.tmp" "$real" "$marca.tmp" "$marca"
    # 300 s: teto para um órfão se a suíte for abortada no meio do caso
    printf '  exec -a %s sleep 300 ;;\nesac\n' "$SHIM_NOME"
    printf 'exec %q "$@"\n' "$real"
  } > "$arq"
  chmod +x "$arq"
}

# _proc_campo <pid> <n> — campo <n> de /proc/<pid>/stat (3 = estado, 5 = pgid)
_proc_campo() {
  local s; s="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  printf '%s\n' "${s##*) }" | awk -v n="$(($2 - 2))" '{ print $n }'
}

# _vivo <pid> — o processo existe e não é zumbi
_vivo() { local st; st="$(_proc_campo "$1" 3)" && [ -n "$st" ] && [ "$st" != Z ]; }

# _mata_shim <marcador> — mata o shim cujo pid está no marcador e espera ele
# sumir (no máximo 30 s). O shim nunca sai sozinho (bloqueia), então o pid é
# o dele; a morte é conferida, não presumida.
_mata_shim() {
  local p fim=$((SECONDS + 30))
  [ -s "$1" ] || return 0
  p="$(cat "$1")"
  kill -KILL "$p" 2>/dev/null
  while _vivo "$p" && [ "$SECONDS" -lt "$fim" ]; do sleep 0.05; done
  _vivo "$p" && falha "o shim $p não morreu em 30 s"
}

# _espera_ponto <pid> <marcador> <desc> — espera o shim chegar ao ponto
# (marcador presente): no máximo 30 s, verificando a cada 0,05 s; para antes
# se o script já não roda. Sem o marcador, falha com mensagem clara.
_espera_ponto() {
  local pid="$1" marca="$2" desc="$3" fim=$((SECONDS + 30))
  while [ ! -s "$marca" ] && [ "$SECONDS" -lt "$fim" ] && _vivo "$pid"; do sleep 0.05; done
  [ -s "$marca" ] || falha "$desc: o shim não chegou ao ponto em 30 s, ou o registro terminou antes (sem o marcador ${marca##*/})"
}

# _interrompe <pid> <TERM|KILL> <marcador> <desc> — com o shim parado no
# ponto (_espera_ponto antes), envia o sinal: TERM ao processo do script (o
# filho direto do teste, nunca o shim); KILL ao grupo de processos do script
# (iniciado com setsid, o grupo é o pid dele). Espera o script com `wait`
# antes de qualquer afirmação e mata o shim que ficou órfão.
_interrompe() {
  local pid="$1" sinal="$2" marca="$3" desc="$4"
  if [ "$sinal" = KILL ]; then
    [ "$(_proc_campo "$pid" 5)" = "$pid" ] || falha "$desc: o registro não lidera o próprio grupo de processos"
    kill -KILL -- -"$pid" 2>/dev/null
  else
    kill -TERM "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  _mata_shim "$marca"
}

grupo_entrega() {
  local d t r variante hoje1 hoje2 esperado k out c modo_antes ls_antes antes antes_commits antes_tasks
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS="$TMPS $t"

  # ---- cenário padrão: reabertura e base validada --------------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  cp "$FX_ENTREGA" "$t/antes.md"
  # o estado de partida é uma entrega entregue, com portão pronto
  [ "$(_chave "$t/antes.md" estado)" = entregue ] && [ "$(_chave "$t/antes.md" portao)" = pronto ] \
    && [ "$(_chave "$t/antes.md" push_feito)" = true ] && ok "partida: entregue, portao pronto, push feito" || falha "estado de partida inesperado"
  antes_commits="$(bash "$SEQ" --ler "$FX_ENTREGA")"
  antes_tasks="$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)"
  modo_antes="$(stat -c %a "$FX_ENTREGA")"
  ls_antes="$(ls -A docs/entregas/ft-rec)"
  hoje1="$(date +%Y-%m-%d)"
  out="$("${r[@]}" "$FX_NOVO1" "$FX_NOVO2" 2>&1)"; c=$?
  hoje2="$(date +%Y-%m-%d)"
  [ "$c" = 0 ] && ok "registra" || { falha "registro rc=$c: $out"; cd "$REPO"; return; }
  [ "$(_chave "$FX_ENTREGA" base_validada_sha)" = "$FX_B1" ] && ok "base validada avança para B1" || falha "base_validada_sha"
  [ "$FX_B1" != "$FX_B0" ] && [ "$(_chave "$t/antes.md" base_validada_sha)" = "$FX_B0" ] && ok "e antes era B0" || falha "B0 de partida"
  [ "$(_chave "$FX_ENTREGA" estado)" = aberto ] && ok "estado: aberto" || falha "estado"
  [ "$(_chave "$FX_ENTREGA" portao)" = null ] && [ "$(_chave "$FX_ENTREGA" portao_sha)" = null ] && ok "portao e portao_sha nulos" || falha "portão não zerado"
  [ "$(_chave "$FX_ENTREGA" falhas_portao)" = '[]' ] && [ "$(_chave "$FX_ENTREGA" causa)" = null ] && ok "falhas_portao [] e causa null" || falha "falhas/causa"
  [ "$(_chave "$FX_ENTREGA" push_feito)" = false ] && [ "$(_chave "$FX_ENTREGA" entregue_em)" = null ] && ok "push_feito false e entregue_em null" || falha "push/entregue_em"
  case "$(_chave "$FX_ENTREGA" atualizado_em)" in "$hoje1"|"$hoje2") ok "atualizado_em é a data do sistema (AAAA-MM-DD)" ;; *) falha "atualizado_em: $(_chave "$FX_ENTREGA" atualizado_em)" ;; esac
  esperado="reconciliacoes:
  - numero: 1
    arquivo: RECONCILIACAO-BASE-001.md
    b1_sha: $FX_B1
    m_sha: $FX_M"
  [ "$(awk '/^reconciliacoes:/ { f = 1; print; next } f && /^[ \t]/ { print; next } f { exit }' "$FX_ENTREGA")" = "$esperado" ] \
    && ok "reconciliacoes acrescida: {numero, arquivo, b1_sha, m_sha}" || falha "bloco reconciliacoes divergente"
  [ "$(grep -c '^reconciliacoes:' "$FX_ENTREGA")" = 1 ] && ok "uma só chave reconciliacoes" || falha "reconciliacoes repetida"
  entrega_confere "padrão" "$t/antes.md" "$FX_ENTREGA" $GRAVADAS
  [ "$(bash "$SEQ" --ler "$FX_ENTREGA")" = "$antes_commits" ] && ok "commits e seq intactos (--ler)" || falha "seq mudou"
  rc_igual "sequencia-de-commits --validar aceita o resultado" 0 bash "$SEQ" --validar "$FX_ENTREGA"
  [ "$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)" = "$antes_tasks" ] && ok "tasks.md intactos" || falha "tasks.md mudou"
  rc_igual "causa-do-portao aceita a reabertura" 0 bash "$CAUSA" --validar "$FX_ENTREGA"
  [ "$(bash "$CAUSA" --validar "$FX_ENTREGA" 2>&1)" = "causa=null" ] && ok "causa-do-portao lê causa=null" || falha "saída do causa-do-portao"
  [ "$(stat -c %a "$FX_ENTREGA")" = "$modo_antes" ] && ok "modo do ENTREGA.md preservado" || falha "modo do ENTREGA.md mudou"
  [ "$(ls -A docs/entregas/ft-rec)" = "$(printf '%s\nRECONCILIACAO-BASE-001.md\n' "$ls_antes" | LC_ALL=C sort)" ] \
    && ok "pasta da entrega: só o artefato novo, nenhum temporário" || falha "sobra na pasta da entrega: $(ls -A docs/entregas/ft-rec | tr '\n' ' ')"
  [ "$(git status --porcelain=v1 --untracked-files=all | LC_ALL=C sort)" = " M $FX_ENTREGA
?? docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md" ] && ok "só ENTREGA.md e artefato mudaram na árvore" || falha "status inesperado"
  rb_validar docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md ft-rec 1 && ok "artefato válido" || falha "artefato inválido: $RB_ERRO"
  cd "$REPO" || return

  # ---- edição alheia no ENTREGA.md: nunca sobrescrita ----------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  printf '\nNota de quem editou.\n' >> "$FX_ENTREGA"
  cp "$FX_ENTREGA" "$t/alheia.md"
  reprova "ENTREGA.md com edição alheia" 3 "reconciliacao-base: ENTREGA.md com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  cmp -s "$FX_ENTREGA" "$t/alheia.md" && ok "a edição alheia segue byte a byte" || falha "a edição alheia foi tocada"
  ls "docs/entregas/ft-rec" | grep -q 'registro\|\.tmp\|\.novo' && falha "temporário deixado na pasta da entrega" || ok "sem temporário na pasta da entrega"
  cd "$REPO" || return

  # ---- tudo ou nada: a substituição do ENTREGA.md falha -------------------
  # `mv` que recusa o destino ENTREGA.md (determinístico, vale também para root)
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  mkdir -p "$t/shim-mv"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do ultimo="$a"; done\ncase "$ultimo" in */ENTREGA.md|ENTREGA.md) echo "mv: recusado de propósito" >&2; exit 1 ;; esac\nexec %s "$@"\n' \
    "$(command -v mv)" > "$t/shim-mv/mv"
  chmod +x "$t/shim-mv/mv"
  cp "$FX_ENTREGA" "$t/antes-atomico.md"; ls_antes="$(ls -A docs/entregas/ft-rec)"; antes="$(_foto)"
  out="$(env PATH="$t/shim-mv:$PATH" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" 2>&1 >/dev/null)"; c=$?
  [ "$c" = 1 ] && ok "falha na substituição do ENTREGA.md: rc 1" || falha "falha forçada: rc=$c, esperava 1 ($out)"
  case "$out" in *"não foi possível atualizar o ENTREGA.md"*) ok "falha forçada: motivo" ;; *) falha "falha forçada: motivo '$out'" ;; esac
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md >/dev/null 2>&1 && falha "ficou artefato depois da falha" || ok "falha forçada: nenhum artefato"
  cmp -s "$FX_ENTREGA" "$t/antes-atomico.md" && ok "falha forçada: ENTREGA.md intacto" || falha "ENTREGA.md mudou na falha"
  [ "$(ls -A docs/entregas/ft-rec)" = "$ls_antes" ] && ok "falha forçada: pasta da entrega como antes (sem temporário)" || falha "sobra na pasta: $(ls -A docs/entregas/ft-rec | tr '\n' ' ')"
  [ "$(_foto)" = "$antes" ] && ok "falha forçada: árvore como antes" || falha "árvore mudou na falha"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "falha forçada: trava livre" || falha "trava presa depois da falha"
  # sem o impedimento, o mesmo registro passa
  registra_ok "depois da falha, o registro volta a funcionar" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- variantes do ENTREGA.md --------------------------------------------
  for variante in entrega_sem_chaves entrega_bloco entrega_crlf entrega_bloco_vazia entrega_bloco_comentario entrega_bloco_escalar entrega_bloco_col0; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"
    FX_VARIANTE="$variante" fx_cenario "$d" || { falha "variante $variante não montou"; continue; }
    cd "$d" || return
    r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
    cp "$FX_ENTREGA" "$t/v-antes.md"
    out="$("${r[@]}" "$FX_NOVO1" "$FX_NOVO2" 2>&1)"; c=$?
    [ "$c" = 0 ] && ok "$variante: registra" || { falha "$variante: rc=$c $out"; cd "$REPO"; continue; }
    entrega_confere "$variante" "$t/v-antes.md" "$FX_ENTREGA" $GRAVADAS
    for k in base_validada_sha estado portao portao_sha falhas_portao causa push_feito entregue_em; do
      case "$k" in
        base_validada_sha) esperado="$FX_B1" ;; estado) esperado=aberto ;; falhas_portao) esperado='[]' ;;
        push_feito) esperado=false ;; *) esperado=null ;;
      esac
      [ "$(_chave "$FX_ENTREGA" "$k")" = "$esperado" ] && [ "$(_blocos "$FX_ENTREGA" | awk -F'\t' -v k="$k" '$1 == k { n++ } END { print n }')" = 1 ] \
        || falha "$variante: $k não ficou '$esperado' uma só vez"
    done
    [ "$(_blocos "$FX_ENTREGA" | awk -F'\t' '$1 == "reconciliacoes" { print $2 }' | tr '\001' '|')" \
      = "reconciliacoes:|  - numero: 1|    arquivo: RECONCILIACAO-BASE-001.md|    b1_sha: $FX_B1|    m_sha: $FX_M" ] \
      || [ "$variante" = entrega_crlf ] || falha "$variante: bloco reconciliacoes"
    rc_igual "$variante: causa-do-portao aceita" 0 bash "$CAUSA" --validar "$FX_ENTREGA"
    rc_igual "$variante: sequencia --validar aceita" 0 bash "$SEQ" --validar "$FX_ENTREGA"
    case "$variante" in
      entrega_sem_chaves)
        # as chaves aninhadas homônimas ficam como estavam, e as de topo entram
        grep -Fxq '  estado: interno' "$FX_ENTREGA" && grep -Fxq '  causa: aninhada' "$FX_ENTREGA" && grep -Fxq '  push_feito: aninhado' "$FX_ENTREGA" \
          && ok "chaves aninhadas homônimas intactas" || falha "chave aninhada alterada"
        [ "$(awk '/^---/ { n++ } n == 1 && /^(causa|push_feito|reconciliacoes|atualizado_em):/ { c++ } END { print c }' "$FX_ENTREGA")" = 4 ] \
          && ok "chaves ausentes entram uma vez, no frontmatter" || falha "chaves ausentes não entraram"
        [ "$(awk '/^---/ { n++ } n == 2 && /^(causa|push_feito):/ { c++ } END { print c + 0 }' "$FX_ENTREGA")" = 0 ] \
          && ok "nada foi inserido no corpo" || falha "chave inserida depois do frontmatter" ;;
      entrega_bloco)
        grep -Fq -- '- v1' "$FX_ENTREGA" && falha "sobrou item do bloco antigo de falhas_portao" || ok "bloco antigo de falhas_portao substituído por inteiro"
        grep -Fq -- '- antiga' "$FX_ENTREGA" && falha "sobrou item do bloco antigo de causa" || ok "bloco antigo de causa substituído por inteiro" ;;
      entrega_bloco_vazia|entrega_bloco_comentario|entrega_bloco_escalar|entrega_bloco_col0)
        # o bloco antigo some por inteiro, como o leitor (sequencia/causa) o define:
        # linha em branco, comentário e itens na coluna 0 pertencem a ele
        if grep -Eq -- 'v1|v7|comentario|primeira linha|terceira linha' "$FX_ENTREGA"; then
          falha "$variante: sobrou linha do bloco antigo: $(grep -En -- 'v1|v7|comentario|primeira linha|terceira linha' "$FX_ENTREGA" | tr '\n' '|')"
        else ok "$variante: nenhuma linha órfã do bloco antigo"; fi
        [ "$(awk '/^---/ { n++ } n == 1 && /^(falhas_portao|causa):/ { c++ } END { print c }' "$FX_ENTREGA")" = 2 ] \
          && ok "$variante: falhas_portao e causa uma só vez" || falha "$variante: falhas_portao/causa repetidas ou ausentes" ;;
      entrega_crlf)
        [ "$(grep -c $'\r$' "$FX_ENTREGA")" = "$(wc -l < "$FX_ENTREGA")" ] && ok "CRLF preservado em todas as linhas" || falha "linha sem CR no ENTREGA.md" ;;
    esac
    cd "$REPO" || return
  done

  # variantes que o registro recusa sem gravar nada
  for variante in entrega_dup entrega_reconc_cheia entrega_bloco_estranho entrega_aspas_d entrega_aspas_s; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"
    FX_VARIANTE="$variante" fx_cenario "$d" || { falha "variante $variante não montou"; continue; }
    cd "$d" || return
    r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
    case "$variante" in
      entrega_dup) reprova "$variante" 5 "chave de topo repetida: estado" "$FX_NOVO1" "$FX_NOVO2" ;;
      entrega_reconc_cheia) reprova "$variante" 5 "ENTREGA.reconciliacoes não está vazia" "$FX_NOVO1" "$FX_NOVO2" ;;
      entrega_bloco_estranho) reprova "$variante" 5 "não se reconhece com segurança" "$FX_NOVO1" "$FX_NOVO2" ;;
      entrega_aspas_d) reprova "$variante" 5 "chave de topo entre aspas: estado" "$FX_NOVO1" "$FX_NOVO2" ;;
      entrega_aspas_s) reprova "$variante" 5 "chave de topo entre aspas: portao" "$FX_NOVO1" "$FX_NOVO2" ;;
    esac
    cd "$REPO" || return
  done

  # ---- interrupção na janela entre o artefato e a troca do ENTREGA.md ------
  # `mv` do destino ENTREGA.md parado (marcador) antes do mv real; o teste mata
  # o registro (SIGTERM) com o artefato já emitido e o temporário já ao lado
  # do ENTREGA.md.
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  mkdir -p "$t/shim-lento"
  _shim_bloqueio "$t/shim-lento/mv" '*/ENTREGA.md|ENTREGA.md' antes "$t/marca-interrupcao"
  cp "$FX_ENTREGA" "$t/antes-sinal.md"; ls_antes="$(ls -A docs/entregas/ft-rec)"; antes="$(_foto)"
  env PATH="$t/shim-lento:$PATH" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 &
  local pid=$!
  _espera_ponto "$pid" "$t/marca-interrupcao" "interrupção"
  [ -e docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md ] && ok "interrupção: artefato emitido e registro na janela" || falha "interrupção: o registro não chegou à janela"
  _interrompe "$pid" TERM "$t/marca-interrupcao" "interrupção"
  ls docs/entregas/ft-rec/RECONCILIACAO-BASE-*.md >/dev/null 2>&1 && falha "interrupção: ficou artefato órfão" || ok "interrupção: nenhum artefato"
  cmp -s "$FX_ENTREGA" "$t/antes-sinal.md" && ok "interrupção: ENTREGA.md original" || falha "interrupção: ENTREGA.md mudou"
  [ "$(ls -A docs/entregas/ft-rec)" = "$ls_antes" ] && ok "interrupção: nenhum temporário na pasta da entrega" || falha "interrupção: sobra na pasta: $(ls -A docs/entregas/ft-rec | tr '\n' ' ')"
  [ "$(_foto)" = "$antes" ] && ok "interrupção: árvore como antes" || falha "interrupção: árvore mudou"
  bash "$TRAVA" --status >/dev/null 2>&1 && ok "interrupção: trava livre" || falha "interrupção: trava presa"
  cd "$REPO" || return
}

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
  VT="$(mktemp -d)"; TMPS="$TMPS $VT"
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=b0_fora_p1 fx_cenario "$d" || { falha "variante b0_fora_p1 não montou"; return; }
  cd "$d" || return
  fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja da âncora"
  v_motivo "b0_sha do 001 diferente da base_validada_sha de P1 reprova" 5 ancora "base_validada_sha"
  cd "$REPO" || return

  # M fora da linha de primeiro pai de HEAD
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=fora_primeiro_pai fx_cenario "$d" || { falha "variante fora_primeiro_pai não montou"; return; }
  cd "$d" || return
  lateral="$(git rev-parse HEAD^2)"
  fx_emite_reconciliacao "$d" 1 "$FX_B0" "$lateral" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja do lateral"
  v_motivo "m_sha fora da linha de primeiro pai de HEAD reprova" 4 estrutura "estrutura[primeiro_pai]"
  git branch -q lateral "$lateral"
  v_motivo "m_sha na linha de primeiro pai de outra ref (não HEAD) reprova" 4 estrutura "estrutura[primeiro_pai]"
  cd "$REPO" || return

  # caminho com espaço, acento e apóstrofo (core.quotepath true no repositório)
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=caminho_especial fx_cenario "$d" || { falha "variante caminho_especial não montou"; return; }
  cd "$d" || return
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" "$FX_ESPECIAL" >/dev/null 2>&1 \
    || falha "registro do caminho especial"
  esperado="$(printf 'ok=true\ncoberto\t%s\t001\ncoberto\t%s\t001\ncoberto\t%s\t001' "$FX_NOVO2" "$FX_ESPECIAL" "$FX_NOVO1")"
  v_ok "caminho especial coberto exatamente, sem escape" "$esperado"
  cd "$REPO" || return

  # cadeia 001 -> 002 (dois merges de base)
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  FX_VARIANTE=entrega_no_merge fx_cenario "$d" || { falha "variante entrega_no_merge não montou"; return; }
  cd "$d" || return
  fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" && fx_entrega_sincroniza "$d" || falha "forja entrega_no_merge"
  v_motivo "merge que reescreve o ENTREGA.md reprova (estrutura[entrega])" 4 estrutura "estrutura[entrega]"
  cd "$REPO" || return

  # ordem dos M, isolada: 001 aponta m1 (posterior), 002 aponta m2 (anterior);
  # tudo o mais confere (CAD, âncora, estrutura, inventário)
  local idx tree0 m0 by m2o m1o
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"

  # ---- cadeia 001 -> 002 sem commit entre os registros (brief) -------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; fx_segunda_base "$d"; cd "$d" || return
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  x="$(printf 'base paralela\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  m2x="$(printf 'merge: integra a base paralela\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$x" | git commit-tree "$FX_M^{tree}" -p "$FX_M" -p "$x")"
  git update-ref refs/heads/feature/ft-rec "$m2x"
  reprova "M^2 que não descende do b1_sha da última reprova pela ordem" 5 "não descende do b1_sha" --
  cd "$REPO" || return

  # ---- órfão de registro interrompido -------------------------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "registro do 001"
  mkdir -p "$t/shim-lento"
  _shim_bloqueio "$t/shim-lento/mv" '*/ENTREGA.md|ENTREGA.md' antes "$t/marca-janela"
  cp "$AR" "$t/janela-a1.md"; cp "$FX_ENTREGA" "$t/janela-e.md"; ls_antes="$(ls -A docs/entregas/ft-rec)"; antes="$(_foto)"
  local tdj; tdj="$(mktemp -d)"; TMPS="$TMPS $tdj"
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
    tdi="$(mktemp -d)"; TMPS="$TMPS $tdi"
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" README.md || falha "resíduo+prova: forja do 002"
  reprova "resíduo + prova reprovada no 002: rc 4, sem conclusão" 4 "prova 1: README.md" -- "$FX_NOVO3" README.md
  grep -q '^estado: ativa$' "$AR" && ok "resíduo + prova: o 001 continua ativa" || falha "resíduo + prova: o 001 mudou"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  sed -i 's/^estado: ativa$/estado: quebrado/' "$AR2"
  reprova "resíduo + última ilegível: rc 5 cadeia ilegível, sem conclusão" 5 "cadeia ilegível: RECONCILIACAO-BASE-002.md" -- "$FX_NOVO3"
  cd "$REPO" || return
  # X9: resíduo + a frase num campo não assinado da última que só a
  # verificação lê (branch): o artefato é lido, mas a falha não é resíduo
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
  sed -i "s|^branch: .*|branch: \"$frase\"|" "$AR2"
  rb_validar "$AR2" ft-rec 2 || falha "X9: o 002 com a frase no branch deveria continuar válido: $RB_ERRO"
  reprova "X9: resíduo + frase no branch da última: rc 5, sem conclusão" 5 "branch ($frase) diverge de ENTREGA.branch" -- "$FX_NOVO3"
  grep -q '^estado: ativa$' "$AR" && ok "X9: o 001 continua ativa" || falha "X9: o 001 mudou"
  cd "$REPO" || return
  # X7: sobra rastreada nunca é removida pelo registro. O commit da sobra tira
  # HEAD do merge: o registro roda com --merge M2, o mesmo M da última, para
  # chegar à conclusão; a cadeia a reprova (não é resíduo) antes dela.
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; _residuo "$d" || { falha "resíduo não montou"; cd "$REPO"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1 || falha "kill-antes: registro do 001"
  cp "$AR" "$t/ka-a1.md"; cp "$FX_ENTREGA" "$t/ka-e.md"
  tdi="$(mktemp -d)"; TMPS="$TMPS $tdi"
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"; VT="$t"
  _shim_merge_base "$t/shim-mb"

  # ---- brief: o legado infere B0; o ambíguo falha fechado ------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado; cd "$d" || return
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d" legado; cd "$d" || return
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "cenário legado não montou"; return; }
  cd "$d" || return
  st="$(git status --porcelain=v1 --untracked-files=all)"
  git merge-base --is-ancestor "$(git merge-base "$FX_P1" "$FX_B1")" "$FX_B1" && ok "controle: com o git real, o merge-base é ancestral de B1" || falha "controle: ancestralidade"
  rc_motivo "merge-base fora de B1 (git simulado): rc 6" 6 "não é ancestral de B1" \
    env FX_SHIM_MB="$(git rev-parse "$FX_P1~3")" PATH="$t/shim-mb:$PATH" "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  _nada_gravado "merge-base fora de B1" "$st"
  cd "$REPO" || return

  # ---- P1 sem o ENTREGA.md (pais trocados) num legado: não infere ----------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=pais_trocados fx_cenario "$d" legado || { falha "pais_trocados legado não montou"; return; }
  cd "$d" || return
  reprova "legado com P1 sem o ENTREGA.md (pais trocados): rc 4, sem inferir" 4 "a base legada não é inferível" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # ---- chave presente (vazia, null, entre aspas) ou origem sem base: rc 5 ---
  for variante in entrega_base_vazia entrega_base_null entrega_base_aspas entrega_sem_base; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d" || { falha "$variante não montou"; return; }
    cd "$d" || return
    case "$variante" in entrega_sem_base) trecho="origem_base sem base_validada_sha" ;; *) trecho="base_validada_sha não é SHA de 40 hex" ;; esac
    reprova "$variante: rc 5 (contrato), sem inferir" 5 "$trecho" "$FX_NOVO1" "$FX_NOVO2"
    cd "$REPO" || return
  done

  # ---- a fonte é P1: nem o disco nem M sem a chave alimentam a inferência --
  # (merge_previo não legado: com a base de P1, a ordem fala, rc 5; inferir daria 6)
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=merge_previo fx_cenario "$d" || { falha "merge_previo não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=base_com_pai fx_cenario "$d" legado || { falha "base_com_pai não montou"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d" legado || { falha "$variante não montou"; return; }
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

# ---------------------------------------------------------------------------
# V9 executável (Task 11): portao-v9.sh e a barreira do checkpoint
# ---------------------------------------------------------------------------

# v9_espera <desc> <rc> <saída exata> — portao-v9.sh (array `v` do grupo) com
# o rc e a saída exatos e o stderr vazio.
v9_espera() {
  local desc="$1" esperado="$2" saida="$3" out rc err
  err="$(mktemp)"; TMPS="$TMPS $err"
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"

  # ---- o fluxo do plano: antes e depois do registro, ref parada, produto ----
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  sed 's/^estado: ativa$/estado: superada/' "$AR" > "$t/a" && cat "$t/a" > "$AR"
  rc_igual "controle: --verificar reprova o artefato editado" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  v9_sem_prova "--verificar com ok=false: v9_sem_prova, nada coberto" "ok=false"
  cd "$REPO" || return

  # ---- caminho com espaço, acento e apóstrofo -------------------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=caminho_especial fx_cenario "$d" || { falha "caminho_especial não montou"; return; }
  cd "$d" || return
  out="$("${v[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -Fxq "fora_do_plano	$FX_ESPECIAL" \
    && ok "caminho especial fora do plano listado exato (sem quoting)" || falha "caminho especial: $(printf '%s' "$out" | tr '\n\t' '|>')"
  [ "$(printf '%s\n' "$out" | grep -c '^fora_do_plano	')" = 3 ] && ok "caminho especial: três desvios" || falha "caminho especial: contagem"
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" "$FX_ESPECIAL" >/dev/null
  v9_espera "caminho especial coberto: aceito" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B1")"
  cd "$REPO" || return

  # ---- RunX: HISTORICO.md não é isento --------------------------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=runx fx_cenario "$d" || { falha "runx não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
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

  # ---- chave presente e inválida em HEAD; contexto divergente --------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE=entrega_base_null fx_cenario "$d" || { falha "entrega_base_null não montou"; return; }
  cd "$d" || return
  v9_sem_prova "base_validada_sha null em HEAD: v9_sem_prova" "base_validada_sha malformada"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  v=(bash "$V9" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec)
  r=(bash "$RB" --registrar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec --)

  # ---- submódulo depois de M: nunca escondido, nunca isento ------------------
  for modo in config gitmodules; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
    cd "$d" || return
    "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1
    _v9_gitlink vendor/lib
    case "$modo" in config) git config diff.ignoreSubmodules all ;; gitmodules) _v9_gitmodules ;; esac
    git commit -q -m "submodulo fora do plano"
    v9_espera "submódulo depois de M com $modo ignore=all: fora do plano" 1 \
      "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tvendor/lib' "$FX_B1")"
    cd "$REPO" || return
  done
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_merge_sem_commit "$d" || { falha "merge sem commit não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  git branch -f main HEAD
  v9_sem_prova "legado com a ref de base movida para HEAD" "é o próprio HEAD"
  git branch -f main "$FX_B1"
  _v9_entrega_commit 's#^branch_base: main$#branch_base: feature/ft-rec#'
  v9_sem_prova "legado com branch_base = a própria branch" "é o próprio HEAD"
  cd "$REPO" || return

  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $FX_M/"
  v9_sem_prova "base_validada_sha = M commitado" "a base contém o trabalho"
  cd "$REPO" || return

  # só o trailer Trabalho: um commit lateral da base com o trailer
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(printf 'parte do trabalho na base\n\nTrabalho: ft-rec\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $x/"
  v9_sem_prova "base com commit Trabalho: ft-rec no histórico" "Trabalho: ft-rec"
  cd "$REPO" || return

  # só ENTREGA.commits: o commit do plano (sem trailer) listado e usado como base
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  plano="$(git rev-parse "$FX_P1~4")"
  git show -s --format=%B "$plano" | grep -q '^Trabalho:' && falha "controle: o commit do plano tem trailer" || ok "controle: o commit do plano não tem trailer"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $plano/; s/^    commit: \(.*\)$/    commit: \1\n  - seq: 2\n    task: T-01.01\n    commit: $plano/"
  v9_sem_prova "base que contém um commit de ENTREGA.commits" "ENTREGA.commits"
  cd "$REPO" || return

  # ---- base ancorada na entrega (a) e sem a pasta do trabalho (b) -----------
  # S1: X (cria src/evil.ts, sem trailer) logo depois de B0 e a feature refeita
  # por cima; com base_validada_sha = X commitado, evil.ts sumiria do diff
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (S1)"
  out="$("${v[@]}" 2>/dev/null)"
  printf '%s\n' "$out" | grep -Fxq 'fora_do_plano	src/evil.ts' && ok "controle S1a: com a base de E0, evil.ts é desvio" || falha "controle S1a: $(printf '%s' "$out" | tr '\n\t' '|>')"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $X/"
  v9_sem_prova "S1b: base_validada_sha commitado diferente do das outras versões do ENTREGA.md" "bases diferentes"
  cd "$REPO" || return

  # trailer fora da forma canônica num commit lateral usado como base: (a)
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(printf 'parte do trabalho\n\nTrabalho:ft-rec\n' | git commit-tree "$FX_B0^{tree}" -p "$FX_B0")"
  _v9_entrega_commit "s/^base_validada_sha: .*/base_validada_sha: $x/"
  v9_sem_prova "trailer escrito de outro jeito (Trabalho:ft-rec) na base" "bases diferentes"
  cd "$REPO" || return

  # ---- âncora em todas as versões do ENTREGA.md (fix round 3) --------------
  # R3/R3b/R3c/R3d: um lado saído de X traz o ENTREGA.md com base X por merge
  local modo_m
  for modo_m in R3 R3b R3c R3d; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_reconstroi "chore: utilitario" || falha "reconstrução (R8)"
  _v9_entrega_commit '/^base_validada_sha:/d; /^origem_base:/d; /^reconciliacoes:/d; /^portao_sha:/d'
  git branch -f main "$X"
  v9_sem_prova "R8: rebaixamento a legado com a ref de base em X" "rebaixamento a legado"
  cd "$REPO" || return

  # fluxo normal em P1 (E0, E1, E2): git mv e ENTREGA.md recriado com o mesmo valor
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
  cd "$d" || return
  git branch -f main "$(git rev-parse "$FX_P1~4")"
  v9_sem_prova "S3: legado com a base num commit que toca a pasta do trabalho" "toca a pasta do trabalho ou a entrega"
  cd "$REPO" || return

  # S5f (legado, só o trailer): i18n.commitEncoding UTF-16 local não desliga a guarda
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  _v9_entrega_commit 's/^commits:$/commits:\n  - seq: 0\n    task: T-00.00\n    commit: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef/'
  v9_sem_prova "S6c: ENTREGA.commits com SHA inexistente" "não resolve para um único commit"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  x="$(_v9_ambiguo)" || falha "S6b: colisão de prefixo não gerada"
  git rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1 && falha "controle S6b: $x resolve" || ok "controle S6b: $x é ambíguo"
  _v9_entrega_commit "s/^commits:\$/commits:\n  - seq: 0\n    task: T-00.00\n    commit: $x/"
  v9_sem_prova "S6b: ENTREGA.commits com abreviação ambígua" "não resolve para um único commit"
  cd "$REPO" || return

  # ---- branch_base inválida (legado) ----------------------------------------
  for x in HEAD '@{-1}' '@'; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado || { falha "legado não montou"; return; }
    cd "$d" || return
    _v9_entrega_commit "s#^branch_base: main\$#branch_base: $x#"
    v9_sem_prova "legado com branch_base: $x" "branch_base"
    cd "$REPO" || return
  done

  # ---- chave presente e ilegível: nunca cai no legado por ref ---------------
  for x in entrega_base_vazia entrega_base_aspas; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$x" fx_cenario "$d" || { falha "$x não montou"; return; }
    cd "$d" || return
    v9_sem_prova "$x: v9_sem_prova, sem legado por ref" "base_validada_sha malformada"
    cd "$REPO" || return
  done

  # ---- duas reconciliações: a base é o b1_sha da ÚLTIMA ----------------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  fx_segunda_base "$d" ajusta || { falha "segunda base não montou"; return; }
  cd "$d" || return
  FX_ESTADO=superada fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" || falha "emissão do 001"
  fx_emite_reconciliacao "$d" 2 "$FX_B1" "$FX_M2" "$FX_NOVO3" || falha "emissão do 002"
  fx_entrega_sincroniza "$d" || falha "sincronização"
  v9_espera "duas reconciliações: base é o b1_sha do 002" 0 "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=ok' "$FX_B2")"
  cd "$REPO" || return

  # ---- renomeação para a pasta isenta: o caminho antigo continua no diff ----
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" >/dev/null 2>&1
  git mv README.md docs/entregas/ft-rec/README.md; git commit -q -m "move produto para a pasta da entrega"
  v9_espera "produto renomeado para docs/entregas/<id>/: o caminho antigo é desvio" 1 \
    "$(printf 'base=%s\norigem_base=reconciliacao\nresultado=v9\nfora_do_plano\tREADME.md' "$FX_B1")"
  cd "$REPO" || return

  # ---- guardas da árvore de HEAD (biblioteca comum) --------------------------
  local alvo; alvo="$(mktemp -d)"; TMPS="$TMPS $alvo"
  for x in plano_tab plano_symlink plano_nl; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_NL_ALVO="$alvo" FX_VARIANTE="$x" fx_cenario "$d" || { falha "$x não montou"; return; }
    cd "$d" || return
    case "$x" in plano_symlink) out="link simbólico ou submódulo" ;; *) out="caminho inválido" ;; esac
    v9_sem_prova "$x em HEAD: v9_sem_prova" "$out"
    cd "$REPO" || return
  done
}

grupo_barreira() {
  local d b out rc esperado t
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"
  v=(bash "$V9" --verificar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec)

  # ---- S2: .git/shallow no commit que pôs X, HEAD merge com X ----------------
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; t="$(mktemp -d)"; TMPS="$TMPS $d $t"; PT_MSG="$t/msg"; PT_ENTREGA=""
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"; d="$t/repo"
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
  t="$(mktemp -d)"; TMPS="$TMPS $t"; d="$t/repo"
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
