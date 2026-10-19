# shellcheck shell=bash
#
# Parte da bancada R1: scripts/ci/test-r1-reconciliacao-base.sh a carrega com
# `.`, na ordem de definição, e roda os grupos. Esta parte só define funções e
# variáveis, e não roda sozinha. Grupos: reproducao, contrato, artefato, provas e entrega.

[ "${BASH_SOURCE[0]}" != "$0" ] || { echo "${0##*/}: parte da bancada R1; rode scripts/ci/test-r1-reconciliacao-base.sh" >&2; exit 64; }

grupo_reproducao() {
  local d dl f st rc cp c n catf
  d="$(mktemp -d)"; TMPS+=("$d")
  dl="$(mktemp -d)"; catf="$(mktemp)"; TMPS+=("$dl" "$catf")
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
  local d; d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d")
  mkdir -p "$d/docs/sprintx/features/fc" "$d/docs/fl" "$d/docs/sprintx/features/fd" "$d/docs/fd" "$d/docs/manutencao/rx"
  [ "$(catalogo_pasta_do_trabalho "$d" sprintx fc)" = docs/sprintx/features/fc ] && ok "pasta: SprintX canônica" || falha "pasta canônica"
  [ "$(catalogo_pasta_do_trabalho "$d" sprintx fl)" = docs/fl ] && ok "pasta: SprintX legada" || falha "pasta legada"
  if catalogo_pasta_do_trabalho "$d" sprintx fd >/dev/null; then falha "pasta: duas pastas passou"
  else case "$CATALOGO_ERRO" in *"duas pastas"*) ok "pasta: duas pastas SprintX é erro" ;; *) falha "pasta: erro '$CATALOGO_ERRO'" ;; esac; fi
  catalogo_pasta_do_trabalho "$d" sprintx nada >/dev/null && falha "pasta SprintX ausente passou" || ok "pasta: SprintX ausente é erro"
  [ "$(catalogo_pasta_do_trabalho "$d" runx rx)" = docs/manutencao/rx ] && ok "pasta: RunX" || falha "pasta RunX"
  catalogo_pasta_do_trabalho "$d" runx nada >/dev/null && falha "pasta RunX ausente passou" || ok "pasta: RunX ausente é erro"
  catalogo_pasta_do_trabalho "$d" n/a fc >/dev/null && falha "pasta de origem n/a passou" || ok "pasta: origem sem pasta é erro"

  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS+=("$t")
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

  # Artefato legítimo da SprintX criado antes da reconciliação: integrações de
  # base pós-E8 não podem confundi-lo com produto fora do plano. O catálogo
  # continua fechado: um nome arbitrário na mesma pasta segue reprovado.
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=preflight_metodo fx_cenario "$d" || { falha "cenário com PREFLIGHT.md não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  antes="$(_foto)"
  registra_ok "PREFLIGHT.md da SprintX é método no inventário pós-E8" "$FX_NOVO1" "$FX_NOVO2"
  desfaz
  [ "$(_foto)" = "$antes" ] && ok "PREFLIGHT.md: árvore volta ao estado anterior" || falha "PREFLIGHT.md: árvore não voltou"
  cd "$REPO" || return

  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=preflight_e_arbitrario fx_cenario "$d" || { falha "cenário com arquivo arbitrário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  reprova "arquivo arbitrário ao lado de PREFLIGHT.md continua fora do catálogo" 4 \
    "inventário: docs/sprintx/features/ft-rec/RASCUNHO.md" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  local rce
  for variante in base_removeu integracao_removeu renomeado resolucao_igual_base m_um_pai pais_trocados \
    fora_primeiro_pai m_sem_integra_base m_com_metodo substring_declarado tipo_mudou b0_fora_b1 b0_fora_p1 \
    b0_ref entrega_kind entrega_trabalho entrega_sem_branch_base entrega_symlink plano_symlink entrega_no_merge; do
    d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  mkdir -p docs/ft-rec; printf 'x\n' > docs/ft-rec/rascunho.md
  printf 'docs/ft-rec/\n' >> .git/info/exclude
  registra_ok "pasta legada só no disco não muda a resolução" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # nome com quebra de linha na pasta do trabalho em M: a lista de tasks.md da
  # união é separada por linha, e `foo<NL>/abs/tasks.md` viraria um tasks.md
  # do disco. A materialização recusa o nome (rc 5) antes de qualquer prova.
  local alvo; alvo="$(mktemp -d)"; TMPS+=("$alvo")
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_NL_ALVO="$alvo" FX_VARIANTE=plano_nl fx_cenario "$d" || { falha "variante plano_nl não montou"; return; }
  cd "$d" || return
  sed "s|altera: \[src/painel.ts\]|altera: [src/painel.ts, $FX_NOVO2]|" docs/sprintx/features/ft-rec/sprint-01/tasks.md > "$alvo/tasks.md"
  grep -Fq "$FX_NOVO2" "$alvo/tasks.md" || falha "o tasks.md do disco não declara NOVO2"
  [ "$(git ls-tree -r --name-only -z HEAD -- docs/sprintx/features/ft-rec | tr '\0' '\n' | grep -Fxc "$alvo/tasks.md")" = 1 ] \
    || falha "M não tem o caminho com quebra de linha"
  reprova "caminho com quebra de linha em M aponta para tasks.md do disco" 5 \
    "pasta do trabalho em M com caminho inválido" "$FX_NOVO1"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS+=("$d")
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
  fora="$(mktemp -d)"; TMPS+=("$fora")
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=duas_pastas fx_cenario "$d" || { falha "variante duas_pastas não montou"; return; }
  cd "$d" || return
  reprova "canônica e legada em M" 4 "pasta do trabalho não determinável em M: há duas pastas SprintX para ft-rec" \
    "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return

  # RunX: a pasta docs/manutencao/<t> de M é a pasta do trabalho
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=runx fx_cenario "$d" || { falha "variante runx não montou"; return; }
  cd "$d" || return
  r_orig=("${r[@]}")
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem runx --trabalho ft-rec --)
  registra_ok "RunX com docs/manutencao/ft-rec em M registra" "$FX_NOVO1" "$FX_NOVO2"
  r=("${r_orig[@]}")
  cd "$REPO" || return

  # enxertos locais (refs/replace e .git/info/grafts) não falsificam os pais de M
  d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=fora_primeiro_pai fx_cenario "$d" || { falha "variante fora_primeiro_pai não montou"; return; }
  cd "$d" || return
  sed 's|^branch_base: main$|branch_base: feature/ft-rec|' "$FX_ENTREGA" > "$t/e.md" && cat "$t/e.md" > "$FX_ENTREGA"
  grep -q '^branch_base: feature/ft-rec$' "$FX_ENTREGA" || falha "branch_base não foi editado"
  reprova "fora_primeiro_pai com branch_base sujo = feature/ft-rec" 4 "estrutura[base]"
  cd "$REPO" || return

  # diretório nunca é caminho reconciliado
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=diretorio fx_cenario "$d" || { falha "variante diretorio não montou"; return; }
  cd "$d" || return
  reprova "diretório na lista reprova" 4 "arquivo: tests/base: não é arquivo (blob)" \
    "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts tests/base
  reprova "caminho com barra final reprova" 4 "arquivo: tests/base/: caminho com barra final" \
    "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts tests/base/
  registra_ok "controle: só os arquivos do diretório registram" "$FX_NOVO1" "$FX_NOVO2" tests/base/x.ts tests/base/y.ts
  cd "$REPO" || return

  # prova 2 anda só pela linha de primeiro pai (spec, seção 6). Antes de M, a
  # feature integrou um ramo lateral anterior a B0 num merge cuja resolução
  # desfez o README.md para a versão anterior a B0: na linha de primeiro pai
  # esse merge toca o README.md (a prova reprova); no histórico completo o git
  # segue o lado lateral, igual à raiz, e não vê toque nenhum (sem
  # --first-parent a prova aprovaria). O --registrar nem chega à prova: a
  # ordem barra o merge lateral antes de M. O --verificar, sobre um 001
  # forjado, chega à prova e tem de reprovar.
  local v VT
  d="$(mktemp -d)"; TMPS+=("$d")
  FX_VARIANTE=lateral_reverte fx_cenario "$d" || { falha "variante lateral_reverte não montou"; return; }
  cd "$d" || return
  [ "$(git rev-list --parents -n1 "$FX_P1" | wc -w)" = 3 ] && git merge-base --is-ancestor "$FX_B0" "$FX_P1" \
    && ! git merge-base --is-ancestor "$FX_B0" "$FX_P1^2" \
    && ok "controle: P1 é um merge lateral (segundo pai anterior a B0) e B0 é ancestral de P1" || falha "controle: lateral_reverte: estrutura de P1"
  [ "$(git show "$FX_P1:README.md")" = "$(git show "$FX_B0^:README.md")" ] && [ "$(git show "$FX_P1:README.md")" != "$(git show "$FX_B0:README.md")" ] \
    && ok "controle: o merge lateral desfez o README.md para a versão anterior a B0" || falha "controle: README.md em P1"
  [ "$(git rev-list --first-parent "$FX_P1" "^$FX_B0" -- README.md)" = "$FX_P1" ] \
    && ok "controle: pela linha de primeiro pai, só o merge lateral toca o README.md" \
    || falha "controle: linha de primeiro pai: $(git rev-list --first-parent "$FX_P1" "^$FX_B0" -- README.md | tr '\n' ' ')"
  [ -z "$(git rev-list "$FX_P1" "^$FX_B0" -- README.md)" ] \
    && ok "controle: sem --first-parent o git segue o lado lateral e não vê o toque" \
    || falha "controle: histórico completo: $(git rev-list "$FX_P1" "^$FX_B0" -- README.md | tr '\n' ' ')"
  reprova "lateral_reverte: o registro para na ordem (merge lateral antes de M), antes das provas" 5 \
    "ordem: o merge $FX_P1, anterior a M $FX_M" "$FX_NOVO1" "$FX_NOVO2" README.md
  fx_forja_artefato "$d" "$FX_NOVO1" "$FX_NOVO2" README.md && fx_entrega_sincroniza "$d" || falha "lateral_reverte: forja do 001"
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec); VT="$t"
  v_motivo "prova 2: merge lateral que desfez o README.md antes de M reprova no --verificar (só a linha de primeiro pai o vê)" 4 prova \
    "prova 2: README.md: a feature tocou o caminho antes do merge ($FX_P1)"
  [ "$("${v[@]}" 2>/dev/null | grep -c '^motivo	prova	.*prova 2: ')" = 1 ] \
    && ok "prova 2: só o README.md reprova; NOVO1 e NOVO2 passam" || falha "prova 2: motivos: $("${v[@]}" 2>/dev/null | tr '\n\t' '|>')"
  cd "$REPO" || return
  for variante in caminho_especial base_alterou; do
    d="$(mktemp -d)"; TMPS+=("$d")
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

  d="$(mktemp -d)"; TMPS+=("$d"); fx_merge_sem_commit "$d" || { falha "merge sem commit não montou"; return; }
  cd "$d" || return
  reprova "merge em andamento" 3 "merge em andamento" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  t="$(mktemp -d)"; TMPS+=("$t")

  # ---- cenário padrão: reabertura e base validada --------------------------
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  printf '\nNota de quem editou.\n' >> "$FX_ENTREGA"
  cp "$FX_ENTREGA" "$t/alheia.md"
  reprova "ENTREGA.md com edição alheia" 3 "reconciliacao-base: ENTREGA.md com alteração não commitada" "$FX_NOVO1" "$FX_NOVO2"
  cmp -s "$FX_ENTREGA" "$t/alheia.md" && ok "a edição alheia segue byte a byte" || falha "a edição alheia foi tocada"
  ls "docs/entregas/ft-rec" | grep -q 'registro\|\.tmp\|\.novo' && falha "temporário deixado na pasta da entrega" || ok "sem temporário na pasta da entrega"
  cd "$REPO" || return

  # ---- edição concorrente entre a conferência do disco e o mv (CodeAnt 4235534531) ----
  # Cópia da skill em que rb_emitir — o último passo antes da troca — edita o
  # ENTREGA.md do disco antes de emitir, como um editor salvando nesse instante.
  # O registro tem de reconferir o disco antes do mv: rc 3, a edição fica, o
  # artefato novo sai e nada mais fica na pasta da entrega.
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
  rm -rf "$t/skill" && cp -R "$S" "$t/skill" || { falha "cópia da skill"; return; }
  cat >> "$t/skill/reconciliacao-artefato.sh" <<'EOF'
# (bancada) edição concorrente do ENTREGA.md imediatamente antes do ponto de commit
eval "rb_emitir_original() $(declare -f rb_emitir | sed 1d)"
rb_emitir() { printf '\nEdição salva durante o registro.\n' >> "$ENTREGA"; rb_emitir_original "$@"; }
EOF
  cd "$d" || return
  cp "$FX_ENTREGA" "$t/concorrente-antes.md"
  out="$(bash "$t/skill/reconciliacao-base.sh" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" 2>&1)"; c=$?
  [ "$c" = 3 ] && ok "edição concorrente antes do mv: rc 3 (o estado mudou), como a conferência do disco" || falha "edição concorrente: rc=$c: $(printf '%s' "$out" | tr '\n' '|')"
  cmp -s "$FX_ENTREGA" <(cat "$t/concorrente-antes.md"; printf '\nEdição salva durante o registro.\n') \
    && ok "edição concorrente: o ENTREGA.md do disco é o de antes mais a edição (nunca a cópia do registro)" \
    || falha "edição concorrente perdida ou ENTREGA.md diferente do esperado: $(git diff --stat -- "$FX_ENTREGA" | tail -1)"
  [ ! -e docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md ] && ok "edição concorrente: o artefato novo foi removido" || falha "artefato novo ficou"
  ls docs/entregas/ft-rec | grep -q 'registro\|\.tmp\|\.novo' && falha "edição concorrente: temporário deixado na pasta da entrega" || ok "edição concorrente: sem temporário na pasta da entrega"
  [ "$(git status --porcelain=v1 --untracked-files=all)" = " M $FX_ENTREGA" ] && ok "edição concorrente: só o ENTREGA.md editado mudou na árvore" || falha "status inesperado: $(git status --porcelain | tr '\n' '|')"
  rm -rf "$t/skill"
  cd "$REPO" || return

  # ---- tudo ou nada: a substituição do ENTREGA.md falha -------------------
  # `mv` que recusa o destino ENTREGA.md (determinístico, vale também para root)
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
    d="$(mktemp -d)"; TMPS+=("$d")
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
    d="$(mktemp -d)"; TMPS+=("$d")
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
  d="$(mktemp -d)"; TMPS+=("$d"); fx_cenario "$d" || { falha "cenário não montou"; return; }
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
