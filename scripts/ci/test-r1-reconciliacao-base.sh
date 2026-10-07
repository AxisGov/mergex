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
  ret2="$(cd "$d/g" && git diff --no-ext-diff --no-color --binary --no-renames HEAD~1 HEAD -- "f g.txt" | sha256sum | cut -d' ' -f1)"
  { [ -n "$ret1" ] && [ "$ret1" = "$ret2" ]; } && ok "rb_diff_sha é o sha256 do diff do Git" || falha "rb_diff_sha divergente ($ret1 / $ret2)"
  printf 'x' | rb_sha256 | grep -Eq '^[0-9a-f]{64}$' && ok "rb_sha256 devolve 64 hex" || falha "rb_sha256 sem 64 hex"

  # sem ferramenta de hash: falha fechado
  mkdir "$d/vazio"
  ( PATH="$d/vazio"; printf x | rb_sha256 ) >/dev/null 2>&1 \
    && falha "sem ferramenta de hash passou" || ok "sem ferramenta de hash falha fechado"
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
