#!/usr/bin/env bash
# reconciliacao-base — registra e verifica a reconciliação de base pós-E8.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seções 5 (modelo Git), 6 (as quatro provas), 7 (artefato) e 8 (--registrar,
# --verificar).
#
# Uso:
#   reconciliacao-base.sh --registrar --entrega docs/entregas/<id>/ENTREGA.md \
#     --origem <sprintx|runx> --trabalho <id> -- <caminho>...
#   reconciliacao-base.sh --verificar --entrega docs/entregas/<id>/ENTREGA.md \
#     --origem <sprintx|runx> --trabalho <id>
#
# --registrar
#   M é HEAD; P1 = M^1; B1 = M^2; B0 = base_validada_sha do ENTREGA.md.
#   Calcula as condições estruturais, as quatro provas de cada caminho dado e o
#   inventário completo do merge (`git diff --name-only B1 M` contido em união
#   das tasks ∪ catálogo de método ∪ lista). Tudo aprovado: grava
#   docs/entregas/<id>/RECONCILIACAO-BASE-001.md e imprime `registrado=`,
#   `b0=`, `p1=`, `b1=`, `m=`. Qualquer reprovação: nada é gravado, e cada
#   motivo sai no stderr como `reconciliacao-base: <motivo>`.
#
#   Aprovado, grava também o ENTREGA.md (seção 11): base_validada_sha = B1,
#   reconciliacoes acrescida, e a entrega reaberta (estado aberto, portão e
#   causa zerados, push_feito false, entregue_em null, atualizado_em de hoje).
#   commits, seq e as demais chaves ficam intactos. A gravação parte do
#   ENTREGA.md do disco só se ele for byte a byte o de M (senão rc 3), e é tudo
#   ou nada: artefato e ENTREGA.md, ou nenhum dos dois.
#
# --verificar (só leitura: nunca grava, nunca adquire a trava C5, não exige
#   stage vazio nem pasta limpa)
#   Lê os RECONCILIACAO-BASE-NNN.md do disco e, para toda a cadeia, recalcula
#   do Git o que eles afirmam, com as MESMAS funções de prova do registro:
#   schema e assinatura; numeração contínua, `anterior`, `b0_sha` = `b1_sha`
#   da anterior, estados (só a última `ativa`), M em ordem na linha de primeiro
#   pai de HEAD; âncora (o `b0_sha` do 001 é o `base_validada_sha` do
#   ENTREGA.md em M); estrutura; as quatro provas (plano e catálogo da árvore
#   do M de cada uma, `<início>` da prova 2 = M anterior); status_base,
#   blob_b1, blob_m e diff_b1_m_sha256 de cada caminho; inventário B1..M
#   (aceitando também os caminhos das reconciliações anteriores); a lista
#   `reconciliacoes` e o `base_validada_sha` do ENTREGA.md do disco; e, por
#   caminho, `HEAD:<caminho>` igual ao `blob_m` da reconciliação mais recente
#   que o lista. Nenhum campo do artefato é aceito sem recálculo.
#   Saída (só stdout): `ok=true` e `coberto<TAB><caminho><TAB><NNN>` por
#   caminho; ou `ok=false` e `motivo<TAB><código><TAB><detalhe>` por falha,
#   todas relatadas. rc 5 se houver falha de contrato, senão 4.
#
#   Toda prova é recalculada do Git; nenhum caminho é aceito por estar listado.
#   Não há opção de força, nem variável de ambiente que relaxe prova.
#
# Códigos: 0 registrado/verificado; 1 ambiente (fora de repositório,
#   temporário, trava não criada); 2 trava C5 ocupada; 3 stage não vazio ou
#   merge em andamento; 4 prova reprovada (estrutura, uma das quatro provas,
#   inventário, campo recalculado, cobertura); 5 contrato do artefato, da cadeia
#   ou do ENTREGA.md inválido, ou reconciliação já registrada; 6 base validada
#   indeterminável; 64 uso.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAVA_SH="$AQUI/trava-do-e1.sh"
CONTRATO_SH="$AQUI/contrato-de-commit.sh"
CATALOGO_SH="$AQUI/catalogo-de-metodo.sh"
OWNERSHIP_SH="$AQUI/ownership-da-task.sh"
ARTEFATO_SH="$AQUI/reconciliacao-artefato.sh"

for dependencia in "$TRAVA_SH" "$CONTRATO_SH" "$CATALOGO_SH" "$OWNERSHIP_SH" "$ARTEFATO_SH"; do
  [ -r "$dependencia" ] || { printf 'reconciliacao-base: dependência indisponível: %s\n' "$dependencia" >&2; exit 1; }
done
# shellcheck source=trava-do-e1.sh
. "$TRAVA_SH"
# shellcheck source=catalogo-de-metodo.sh
. "$CATALOGO_SH"
# shellcheck source=reconciliacao-artefato.sh
. "$ARTEFATO_SH"
set +e

# Caminho exatamente como no Git, qualquer que seja a configuração do
# repositório: sem escape de nome (quotepath) e pathspec sempre literal. Vale
# também para o rb_diff_sha da biblioteca, que roda neste processo.
unset GIT_GLOB_PATHSPECS GIT_ICASE_PATHSPECS GIT_NOGLOB_PATHSPECS
export GIT_LITERAL_PATHSPECS=1
# (advice.graftFileDeprecated: o GIT_GRAFT_FILE abaixo não polui o stderr;
# core.commitGraph=false: os pais vêm dos objetos, não de um commit-graph local)
export GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=advice.graftFileDeprecated GIT_CONFIG_VALUE_1=false \
  GIT_CONFIG_KEY_2=core.commitGraph GIT_CONFIG_VALUE_2=false
# Ancestralidade e objetos só do Git, nunca de enxertos locais: refs/replace e
# .git/info/grafts falsificariam os pais de M. Exportado, para que os filhos
# (contrato-de-commit.sh, ownership-da-task.sh) herdem.
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null # guarda:EST
g() { git -c core.quotepath=false "$@"; }

NL='
'
TAB='	'

MODO=""
ENTREGA=""
ORIGEM=""
TRABALHO=""
SEPARADOR=0

uso() {
  [ -z "${1:-}" ] || printf 'reconciliacao-base: %s\n' "$1" >&2
  printf '%s\n' \
    'uso: reconciliacao-base.sh --registrar --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id> -- <caminho>...' \
    '     reconciliacao-base.sh --verificar --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id>' >&2
  exit 64
}

TMP_DIR=""
TOKEN=""
LIBERAR_NA_SAIDA=0
TMP_ENTREGA=""
DESTINO=""
ARTEFATO_NOVO=0 # 1 enquanto o artefato recém-criado depende da troca do ENTREGA.md

encerrar() {
  local rc="$1"
  # saída (inclusive por sinal) antes da troca do ENTREGA.md: nem artefato nem
  # temporários ficam; o ENTREGA.md original não foi tocado
  if [ "$ARTEFATO_NOVO" = 1 ] && [ -n "$DESTINO" ]; then rm -f "$DESTINO" "$DESTINO.tmp.$$"; fi # guarda:JANELA
  [ -z "$TMP_ENTREGA" ] || rm -f "$TMP_ENTREGA"
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  if [ "$LIBERAR_NA_SAIDA" = 1 ] && [ -n "$TOKEN" ]; then
    liberar "$TOKEN" >/dev/null 2>&1
  fi
  exit "$rc"
}
trap 'encerrar $?' EXIT

# para <rc> <motivo> — encerra sem gravar nada.
para() {
  printf 'reconciliacao-base: %s\n' "$2" >&2
  exit "$1"
}

# ---------------------------------------------------------------------------
# Falhas, nos dois modos. O registro para na primeira falha dura e relata
# todas as reprovações de prova no stderr; a verificação acumula cada falha
# como `motivo<TAB><código><TAB><detalhe>` e segue para a reconciliação
# seguinte. Uma implementação de prova, dois modos.
# ---------------------------------------------------------------------------
PREFIXO=""   # (verificar) o artefato em exame, à frente de cada detalhe
MOTIVOS=""   # (verificar) arquivo com as linhas `motivo`
FALHA_5=0    # (verificar) houve falha de contrato
FALHA_4=0    # (verificar) houve falha de prova, estrutura ou cobertura

# motivo <rc> <código> <detalhe> — (verificar) acumula uma falha
motivo() {
  printf 'motivo\t%s\t%s\n' "$2" "$(printf '%s%s' "$PREFIXO" "$3" | tr '\t\n\r' '   ')" >> "$MOTIVOS"
  if [ "$1" = 5 ]; then FALHA_5=1; else FALHA_4=1; fi
}

# falha_dura <rc> <código> <mensagem> — falha que impede seguir com a
# reconciliação em exame: o registro encerra; a verificação acumula o motivo,
# e quem chamou devolve 1.
falha_dura() {
  [ "$MODO" = verificar ] || para "$1" "$3"
  motivo "$1" "$2" "$3"
}

# Condição estrutural reprovada: as provas não são calculáveis sobre ela.
estrutura() { falha_dura 4 estrutura "estrutura[$1]: $2"; }

FALHAS=0
reprova() { # <mensagem> [código]
  if [ "$MODO" = verificar ]; then motivo 4 "${2:-prova}" "$1"
  else printf 'reconciliacao-base: %s\n' "$1" >&2; fi
  FALHAS=$((FALHAS + 1))
}

# ---------------------------------------------------------------------------
# Escrita do ENTREGA.md (spec, seção 11). Só mexem em chave de TOPO do
# frontmatter; o corpo depois do `---` de fechamento é copiado byte a byte.
# Trabalham sempre numa cópia (nunca no ENTREGA.md do repositório).
# ---------------------------------------------------------------------------
ENTREGA_ERRO=""

# _entrega_fecha <arquivo> — número da linha do `---` de fechamento
_entrega_fecha() {
  awk '
    NR == 1 { if ($0 !~ /^---[ \t]*\r?$/) exit 1; next }
    /^---[ \t]*\r?$/ { print NR; achou = 1; exit }
    END { exit !achou }
  ' "$1"
}

# _entrega_troca <arquivo> <chave> <texto> — o texto (uma ou mais linhas,
# inclusive a da própria chave) substitui a chave de topo e as linhas de
# continuação dela (indentadas ou `- `); chave ausente: entra antes do `---`
# de fechamento. Chave de topo repetida é recusada. Linha aninhada com o mesmo
# nome não conta: só a coluna 0.
_entrega_troca() {
  local arq="$1" chave="$2" texto="$3" n fm novo
  ENTREGA_ERRO=""
  n="$(_entrega_fecha "$arq")" || { ENTREGA_ERRO="frontmatter ausente ou sem fechamento"; return 1; }
  fm="$arq.fm.$$"; novo="$arq.novo.$$"
  head -n "$n" "$arq" | NOVO="$texto" CHAVE="$chave" awk '
    BEGIN { chave = ENVIRON["CHAVE"]; texto = ENVIRON["NOVO"]; estado = 0 }
    function emite(   i, m, linhas) {
      m = split(texto, linhas, "\n")
      for (i = 1; i <= m; i++) print linhas[i] cr
    }
    NR == 1 { cr = ($0 ~ /\r$/) ? "\r" : ""; print; estado = 1; next }
    estado == 1 && /^---[ \t]*\r?$/ { if (!feito) { emite(); feito = 1 } estado = 2; print; next }
    estado == 1 {
      # chave de topo entre aspas: não é reconhecida como a chave, e inserir
      # outra duplicaria a chave no YAML
      if ($0 ~ /^["\047]/) {
        q = $0; sub(/^["\047]/, "", q); sub(/["\047].*/, "", q)
        if (q == chave) { erro = 1; exit 6 }
      }
      # o bloco de uma chave (como em sequencia-de-commits.sh) só termina na
      # próxima chave de topo ou no fechamento; linha vazia, comentário e linha
      # indentada ou `- ` no meio pertencem a ele
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        pula = 0
        if (index($0, chave ":") == 1) {
          if (feito) { erro = 1; exit 4 }
          emite(); feito = 1; pula = 1; next
        }
        print; next
      }
      if (pula) {
        if ($0 ~ /^[ \t]/ || $0 ~ /^#/ || $0 ~ /^[ \t]*\r?$/ || $0 ~ /^-([ \t]|\r?$)/) next
        erro = 1; exit 7
      }
      print; next
    }
    END { if (!erro && estado != 2) exit 5 }
  ' > "$fm"
  case $? in
    0) ;;
    4) rm -f "$fm"; ENTREGA_ERRO="chave de topo repetida: $chave"; return 1 ;;
    6) rm -f "$fm"; ENTREGA_ERRO="chave de topo entre aspas: $chave"; return 1 ;;
    7) rm -f "$fm"; ENTREGA_ERRO="o bloco de $chave tem linha que não se reconhece com segurança"; return 1 ;;
    *) rm -f "$fm"; ENTREGA_ERRO="não foi possível reescrever $chave"; return 1 ;;
  esac
  { cat "$fm"; tail -n "+$((n + 1))" "$arq"; } > "$novo" 2>/dev/null \
    && cat "$novo" > "$arq" 2>/dev/null \
    || { rm -f "$fm" "$novo"; ENTREGA_ERRO="não foi possível gravar $chave"; return 1; }
  rm -f "$fm" "$novo"
}

# entrega_define <arquivo> <chave> <valor>
entrega_define() {
  case "$2" in ''|*[!a-z0-9_]*) ENTREGA_ERRO="chave inválida: $2"; return 1 ;; esac
  case "$3" in *"$NL"*) ENTREGA_ERRO="valor com quebra de linha: $2"; return 1 ;; esac
  _entrega_troca "$1" "$2" "$2: $3"
}

# entrega_reconciliacoes <arquivo> <tsv> — o bloco inteiro da lista. O tsv tem
# `numero<TAB>arquivo<TAB>b1_sha<TAB>m_sha` por linha; vazio grava `[]`.
entrega_reconciliacoes() {
  local texto
  if [ -s "$2" ]; then
    texto="$(awk -F'\t' 'BEGIN { print "reconciliacoes:" }
      NF != 4 { exit 1 }
      { printf "  - numero: %s\n    arquivo: %s\n    b1_sha: %s\n    m_sha: %s\n", $1, $2, $3, $4 }' "$2")" \
      || { ENTREGA_ERRO="reconciliacoes: o tsv exige quatro colunas"; return 1; }
  else
    texto='reconciliacoes: []'
  fi
  _entrega_troca "$1" reconciliacoes "$texto"
}

# _entrega_tem <arquivo> <chave> — a chave de topo existe no frontmatter
_entrega_tem() {
  awk -v c="$2" '
    NR == 1 { next }
    /^---[ \t]*\r?$/ { exit }
    index($0, c ":") == 1 { achou = 1; exit }
    END { exit !achou }
  ' "$1"
}

# entrega_lista_reconciliacoes <arquivo> — a lista `reconciliacoes` do
# frontmatter, na forma que entrega_reconciliacoes grava, como
# `numero<TAB>arquivo<TAB>b1_sha<TAB>m_sha` por item (nada para `[]` ou chave
# ausente). Qualquer outra forma: rc 1.
entrega_lista_reconciliacoes() {
  awk '
    function fecha() {
      if (!item) return
      if (!("arquivo" in it) || !("b1_sha" in it) || !("m_sha" in it)) bad = 1
      print n "\t" it["arquivo"] "\t" it["b1_sha"] "\t" it["m_sha"]
      split("", it); item = 0
    }
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[ \t]*$/) { bad = 1; exit } next }
    /^---[ \t]*$/ { fechou = 1; exit }
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
      if (em) { fecha(); em = 0 }
      if ($0 !~ /^reconciliacoes:/) next
      if (visto) { bad = 1; exit }
      visto = 1
      v = $0; sub(/^reconciliacoes:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "[]") next
      if (v != "") { bad = 1; exit }
      em = 1; next
    }
    em && /^  - numero: [^ \t]+[ \t]*$/ { fecha(); n = $0; sub(/^  - numero: /, "", n); sub(/[ \t]+$/, "", n); item = 1; next }
    em && item && /^    (arquivo|b1_sha|m_sha): [^ \t]+[ \t]*$/ {
      k = $0; sub(/^    /, "", k); v = k; sub(/:.*/, "", k); sub(/^[^:]*: /, "", v); sub(/[ \t]+$/, "", v)
      if (k in it) { bad = 1; exit }
      it[k] = v; next
    }
    em { bad = 1; exit }
    END { if (em) fecha(); if (bad || !fechou) exit 1 }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Funções de prova (seções 5 e 6), comuns aos dois modos. Nada que esteja só
# no disco entra numa prova: o ENTREGA.md e a pasta do trabalho (plano e
# catálogo) são lidos da árvore de M.
# ---------------------------------------------------------------------------

contem() { grep -Fxq -e "$2" "$1"; }

# modo_em <commit> <caminho> — o modo do caminho na árvore do commit (vazio se ausente)
modo_em() { g ls-tree -z "$1" -- "$2" 2>/dev/null | tr '\0' '\n' | sed -n '1s/ .*//p'; }

# le_entrega_m <M> <destino> — o ENTREGA.md de M em <destino>, com o contexto
# explícito (kind, trabalho, origem) igual ao registrado.
le_entrega_m() {
  local m="$1" dest="$2" modo
  modo="$(modo_em "$m" "$ENTREGA")"
  [ -n "$modo" ] || { falha_dura 5 entrega "$ENTREGA ausente no commit M $m"; return 1; }
  case "$modo" in 100644|100755) ;; *) falha_dura 5 entrega "$ENTREGA não é arquivo regular em M (modo $modo)"; return 1 ;; esac
  g cat-file blob "$m:$ENTREGA" > "$dest" 2>/dev/null || { falha_dura 5 entrega "$ENTREGA ilegível em M"; return 1; }
  [ "$(catalogo_fm "$dest" kind)" = entrega ] || { falha_dura 5 entrega "$ENTREGA não declara kind: entrega"; return 1; }
  [ "$(catalogo_fm "$dest" trabalho_id)" = "$TRABALHO" ] || { falha_dura 5 entrega 'trabalho explícito diverge de ENTREGA.trabalho_id'; return 1; }
  [ "$(catalogo_fm "$dest" expx_tool)" = "$ORIGEM" ] || { falha_dura 5 entrega 'origem explícita diverge de ENTREGA.expx_tool'; return 1; }
}

# materializa_m <M> <dir> — a árvore de M materializada em <dir> só no
# necessário para resolver a pasta do trabalho e ler o plano: as três pastas
# candidatas, blob por blob. Link simbólico ou submódulo dentro delas: o plano
# não é lido (rc 5). Define RAIZ_M (físico) e PASTA (resolvida em M).
materializa_m() {
  local m="$1" raiz item modo caminho destino
  mkdir -p "$2" 2>/dev/null || { falha_dura 1 ambiente 'não foi possível criar a árvore temporária de M'; return 1; }
  # caminho absoluto físico: é o prefixo que todo destino da materialização tem
  raiz="$(cd "$2" && pwd -P)" || { falha_dura 1 ambiente 'árvore temporária de M inacessível'; return 1; }
  g ls-tree -r -z --full-tree "$m" -- "docs/sprintx/features/$TRABALHO" "docs/$TRABALHO" "docs/manutencao/$TRABALHO" \
    > "$raiz.lista" 2>/dev/null || { falha_dura 4 prova "prova 3: árvore de M ilegível"; return 1; }
  while IFS= read -r -d '' item <&3; do
    modo="${item%% *}"; caminho="${item#*	}"
    # a união separa os tasks.md por linha: um nome com quebra de linha (ou
    # outro caractere de controle) desviaria a leitura para o disco
    case "$caminho" in *"$NL"*|*"$TAB"*|*[[:cntrl:]]*) falha_dura 5 arvore "pasta do trabalho em M com caminho inválido: $(printf '%s' "$caminho" | tr '[:cntrl:]' '?')"; return 1 ;; esac # guarda:P3
    # componente vazio, `.` ou `..` (árvore forjada com git mktree) escreveria
    # fora da árvore temporária: recusado antes de qualquer escrita
    case "/$caminho/" in */./*|*/../*|*//*) falha_dura 5 arvore "pasta do trabalho em M com caminho inválido (componente vazio, . ou ..): $caminho"; return 1 ;; esac # guarda:P3
    case "$modo" in
      100644|100755) ;;
      *) falha_dura 5 arvore "pasta do trabalho em M tem link simbólico ou submódulo (modo $modo): $caminho"; return 1 ;;
    esac
    mkdir -p "$raiz/$(dirname "$caminho")" 2>/dev/null || { falha_dura 4 prova "prova 3: não foi possível materializar $caminho de M"; return 1; }
    destino="$(cd "$raiz/$(dirname "$caminho")" && pwd -P)" || { falha_dura 4 prova "prova 3: não foi possível materializar $caminho de M"; return 1; }
    # defesa em profundidade: o diretório de destino, resolvido, fica dentro do temporário
    case "$destino/" in "$raiz"/*) ;; *) falha_dura 5 arvore "pasta do trabalho em M: destino fora da árvore temporária: $caminho"; return 1 ;; esac # guarda:P3
    g cat-file blob "$m:$caminho" > "$destino/${caminho##*/}" 2>/dev/null \
      || { falha_dura 4 prova "prova 3: não foi possível ler $caminho de M"; return 1; }
  done 3< "$raiz.lista"
  # Sem subshell: o CATALOGO_ERRO da função chega ao motivo.
  catalogo_pasta_do_trabalho "$raiz" "$ORIGEM" "$TRABALHO" > "$raiz.pasta" \
    || { falha_dura 4 prova "prova 3: pasta do trabalho não determinável em M: $CATALOGO_ERRO"; return 1; }
  PASTA="$(cat "$raiz.pasta")"
  RAIZ_M="$raiz"
}

# estrutura_m <M> <B0> <ref> — as condições estruturais (seção 5) que valem
# para M em qualquer momento; <ref> dá a linha de primeiro pai. Define P1 e B1.
# (A ponta da ref de base é condição do momento do registro: fica nele.)
estrutura_m() {
  local m="$1" b0="$2" ref="$3" pais npais
  g cat-file -e "$b0^{commit}" 2>/dev/null || { estrutura b0 "B0 $b0 não é commit deste repositório"; return 1; }
  pais="$(g rev-list --parents -n1 "$m" 2>/dev/null)" || { estrutura m "pais de M ilegíveis"; return 1; }
  npais=$(( $(printf '%s\n' "$pais" | wc -w) - 1 ))
  [ "$npais" = 2 ] || { estrutura pais "M $m tem $npais pai(s); o commit de integração tem exatamente dois"; return 1; } # guarda:EST
  P1="$(g rev-parse --verify -q "$m^1")" || { estrutura m 'M^1 ilegível'; return 1; }
  B1="$(g rev-parse --verify -q "$m^2")" || { estrutura m 'M^2 ilegível'; return 1; }
  g rev-list --first-parent "$ref" > "$TMP_DIR/primeiro-pai" 2>/dev/null || { estrutura primeiro_pai "linha de primeiro pai de $ref ilegível"; return 1; }
  grep -Fxq -e "$m" "$TMP_DIR/primeiro-pai" || { estrutura primeiro_pai "M $m fora da linha de primeiro pai de $ref"; return 1; } # guarda:EST
  bash "$CONTRATO_SH" --validar-integracao --trabalho "$TRABALHO" --commit "$m" >/dev/null 2>"$TMP_DIR/contrato.err" || { estrutura contrato "mensagem de M fora do contrato de integração: $(tr '\n' ' ' < "$TMP_DIR/contrato.err")"; return 1; } # guarda:EST
  g merge-base --is-ancestor "$b0" "$B1" 2>/dev/null || { estrutura b0_b1 "B0 $b0 não é ancestral de B1 $B1"; return 1; } # guarda:EST
  g merge-base --is-ancestor "$b0" "$P1" 2>/dev/null || { estrutura b0_p1 "B0 $b0 não é ancestral de P1 $P1"; return 1; } # guarda:EST
}

# uniao_e_catalogo <raiz-de-M> <pasta> — união das tasks e catálogo de método
# (prova 3 e inventário) em $UNIAO e $CATALOGO, sobre a árvore de M.
uniao_e_catalogo() {
  bash "$OWNERSHIP_SH" --uniao "$1" "$ORIGEM" "$TRABALHO" > "$UNIAO" 2>"$TMP_DIR/uniao.err" || { falha_dura 4 prova "prova 3: união das tasks não calculável: $(tr '\n' ' ' < "$TMP_DIR/uniao.err")"; return 1; } # guarda:P3
  catalogo_metodo "$1" "$ORIGEM" "$TRABALHO" "$2" e8 > "$CATALOGO" || { falha_dura 4 prova "prova 3: catálogo de método não calculável: $CATALOGO_ERRO"; return 1; } # guarda:P3
}

# provas <lista> <B0> <início> <P1> <B1> <M> — as quatro provas, para cada
# caminho da lista (seção 6). Todas são calculadas e todas as reprovações são
# relatadas; nenhuma falha de cálculo vira aprovação.
provas() {
  local lista="$1" b0="$2" inicio="$3" p1="$4" b1="$5" m="$6" f tb tm st rc_p4
  while IFS= read -r f <&3; do
    # o caminho é de arquivo (blob), nunca de diretório nem submódulo
    case "$f" in */) reprova "arquivo: $f: caminho com barra final não é arquivo"; continue ;; esac # guarda:BLOB
    tb="$(g cat-file -t "$b1:$f" 2>/dev/null)"; tm="$(g cat-file -t "$m:$f" 2>/dev/null)"
    { [ -z "$tb" ] || [ "$tb" = blob ]; } && { [ -z "$tm" ] || [ "$tm" = blob ]; } || reprova "arquivo: $f: não é arquivo (blob) em B1 (${tb:--}) ou em M (${tm:--})" # guarda:BLOB

    # prova 1: f nasceu ou mudou na base entre B0 e B1
    if g diff --no-renames --name-status -z "$b0" "$b1" -- "$f" > "$SAIDA" 2>/dev/null; then
      st="$(tr '\0' '\n' < "$SAIDA" | sed -n 1p)"
      [ -n "$st" ] || reprova "prova 1: $f: a base não criou nem alterou o caminho entre B0 e B1" # guarda:P1
      [ "$st" != D ] || reprova "prova 1: $f: a base removeu o caminho (status D); ressurreição não é ajuste" # guarda:P1D
      case "$st" in A|M|D|'') ;; *) reprova "prova 1: $f: status $st na base fora de A|M (mudança de tipo também reprova)" ;; esac # guarda:P1T
    else
      reprova "prova 1: $f: diff B0..B1 não calculável"
    fi

    # prova 2: a feature não tocou f antes do merge
    if g rev-list --first-parent "$p1" "^$inicio" -- "$f" > "$SAIDA" 2>/dev/null; then
      [ ! -s "$SAIDA" ] || reprova "prova 2: $f: a feature tocou o caminho antes do merge ($(sed -n 1p "$SAIDA"))" # guarda:P2FP
    else
      reprova "prova 2: $f: histórico da feature não calculável"
    fi

    # prova 3: f não consta das tasks nem é artefato de método
    if contem "$UNIAO" "$f" || contem "$CATALOGO" "$f"; then reprova "prova 3: $f: declarado em task ou artefato de método"; fi # guarda:P3

    # prova 4: diferença real entre B1 e M, com f presente em M
    g cat-file -e "$m:$f" 2>/dev/null || reprova "prova 4: $f: ausente em M (a integração removeu o caminho)" # guarda:P4
    g diff --quiet --no-renames "$b1" "$m" -- "$f" >/dev/null 2>&1; rc_p4=$?
    [ "$rc_p4" = 1 ] || reprova "prova 4: $f: sem diferença entre B1 e M (ou diff não calculável, rc=$rc_p4)" # guarda:P4
  done 3< "$lista"
}

# inventario <B1> <M> <lista> <anteriores> — todo caminho que o merge alterou
# em relação a B1 está na união, no catálogo, na lista ou entre os caminhos
# de reconciliações anteriores da cadeia (cuja cobertura é conferida em HEAD).
# Não existe registro parcial.
inventario() {
  local b1="$1" m="$2" lista="$3" anteriores="$4" p
  g diff --name-only -z --no-renames "$b1" "$m" > "$INVENTARIO" 2>/dev/null \
    || { falha_dura 4 inventario 'inventário: diff B1..M não calculável'; return 1; }
  while IFS= read -r -d '' p <&3; do
    case "$p" in *"$NL"*) reprova "inventário: caminho com quebra de linha alterado pelo merge" inventario; continue ;; esac
    contem "$UNIAO" "$p" || contem "$CATALOGO" "$p" || contem "$lista" "$p" || contem "$anteriores" "$p" || reprova "inventário: $p: alterado pelo merge e não declarado" inventario # guarda:INV
  done 3< "$INVENTARIO"
}

# campos_caminho <B0> <B1> <M> <caminho> — os campos do artefato para o
# caminho, do Git: CAMPO_ST (status B0..B1), CAMPO_BB, CAMPO_BM, CAMPO_DS.
# Todos são calculados; o que não se calcula fica vazio, e CAMPO_ERRO guarda o
# primeiro problema (rc 1).
campos_caminho() {
  local b0="$1" b1="$2" m="$3" f="$4"
  CAMPO_ERRO=""
  CAMPO_ST="$(g diff --no-renames --name-status -z "$b0" "$b1" -- "$f" 2>/dev/null | tr '\0' '\n' | sed -n 1p)"
  case "$CAMPO_ST" in A|M) ;; *) CAMPO_ERRO="status de $f mudou durante o registro" ;; esac
  CAMPO_BB="$(g rev-parse --verify -q "$b1:$f" 2>/dev/null)" || { CAMPO_BB=""; [ -n "$CAMPO_ERRO" ] || CAMPO_ERRO="blob de $f em B1 ilegível"; }
  CAMPO_BM="$(g rev-parse --verify -q "$m:$f" 2>/dev/null)" || { CAMPO_BM=""; [ -n "$CAMPO_ERRO" ] || CAMPO_ERRO="blob de $f em M ilegível"; }
  RB_ERRO=""
  if rb_diff_sha "$b1" "$m" "$f" > "$SAIDA"; then CAMPO_DS="$(cat "$SAIDA")"
  else CAMPO_DS=""; [ -n "$CAMPO_ERRO" ] || CAMPO_ERRO="$RB_ERRO"; fi
  [ -z "$CAMPO_ERRO" ]
}

# ---------------------------------------------------------------------------
# --verificar
# ---------------------------------------------------------------------------

# _r <índice> <chave> — escalar do artefato lido
_r() { awk -F'\t' -v k="$2" '$1 == "escalar" && $2 == k { print $3; exit }' "$TMP_DIR/r$1.lido"; }

verificar() {
  local dir="docs/entregas/$TRABALHO" nome arq n i j num nnn lido b0 p1 b1 m ob est ant ex br
  local inicio prev bv lm lp f st bb bm ds h numero arquivo eb1 em idx ENTREGA_D=""
  MOTIVOS="$TMP_DIR/motivos"; : > "$MOTIVOS"
  # nem o refresh oportunista do índice: a verificação não grava nada
  export GIT_OPTIONAL_LOCKS=0

  # O ENTREGA.md do disco: contexto e a lista de reconciliações.
  if [ -f "$ENTREGA" ] && [ ! -L "$ENTREGA" ] && cat "$ENTREGA" > "$TMP_DIR/entrega-disco.md" 2>/dev/null; then
    ENTREGA_D="$TMP_DIR/entrega-disco.md"
    [ "$(catalogo_fm "$ENTREGA_D" kind)" = entrega ] || motivo 5 entrega "$ENTREGA não declara kind: entrega"
    [ "$(catalogo_fm "$ENTREGA_D" trabalho_id)" = "$TRABALHO" ] || motivo 5 entrega 'trabalho explícito diverge de ENTREGA.trabalho_id'
    [ "$(catalogo_fm "$ENTREGA_D" expx_tool)" = "$ORIGEM" ] || motivo 5 entrega 'origem explícita diverge de ENTREGA.expx_tool'
    if ! entrega_lista_reconciliacoes "$ENTREGA_D" > "$TMP_DIR/lista-entrega" 2>/dev/null; then
      motivo 5 entrega "$ENTREGA: reconciliacoes fora da forma {numero, arquivo, b1_sha, m_sha}"
      ENTREGA_D=""
    fi
  else
    motivo 5 entrega "$ENTREGA ausente ou não é arquivo regular"
  fi

  # Os artefatos da pasta da entrega, em ordem de byte. Nome fora do padrão
  # (inclusive sobra de gravação) é contrato inválido.
  : > "$TMP_DIR/artefatos"
  for arq in "$dir"/RECONCILIACAO-BASE-*; do
    [ -e "$arq" ] || [ -L "$arq" ] || continue
    nome="${arq##*/}"
    case "$nome" in
      RECONCILIACAO-BASE-[0-9][0-9][0-9].md) printf '%s\n' "$nome" >> "$TMP_DIR/artefatos" ;;
      *) PREFIXO="$nome: "; motivo 5 contrato "nome fora do padrão RECONCILIACAO-BASE-NNN.md"; PREFIXO="" ;;
    esac
  done
  LC_ALL=C sort -o "$TMP_DIR/artefatos" "$TMP_DIR/artefatos"

  # Schema e assinatura de cada um; numeração contínua a partir de 001.
  n=0
  while IFS= read -r nome <&3; do
    n=$((n + 1)); PREFIXO="$nome: "
    printf '%s\n' "$nome" > "$TMP_DIR/nome$n"
    [ "$nome" = "$(printf 'RECONCILIACAO-BASE-%03d.md' "$n")" ] \
      || motivo 5 numeracao "numeração com lacuna: na posição $n esperava $(printf 'RECONCILIACAO-BASE-%03d.md' "$n")"
    arq="$dir/$nome"
    if [ ! -f "$arq" ] || [ -L "$arq" ]; then motivo 5 contrato "não é arquivo regular"; continue; fi
    num="$(printf '%s' "$nome" | sed 's/^RECONCILIACAO-BASE-0*\([0-9][0-9]*\)\.md$/\1/')"
    RB_ERRO=""
    rb_validar "$arq" "$TRABALHO" "$num" || { motivo 5 contrato "$RB_ERRO"; continue; }
    RB_ERRO=""
    rb_ler "$arq" > "$TMP_DIR/r$n.lido" || { rm -f "$TMP_DIR/r$n.lido"; motivo 5 contrato "$RB_ERRO"; continue; }
    awk -F'\t' '$1 == "arquivo" { print $2 }' "$TMP_DIR/r$n.lido" > "$TMP_DIR/lista$n"
  done 3< "$TMP_DIR/artefatos"
  PREFIXO=""

  # Cadeia e provas, reconciliação a reconciliação, com as funções do registro.
  : > "$TMP_DIR/anteriores"
  : > "$TMP_DIR/cobertura"
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1)); j=$((i - 1))
    # os caminhos das reconciliações anteriores (para o inventário desta)
    [ ! -f "$TMP_DIR/lista$j" ] || cat "$TMP_DIR/lista$j" >> "$TMP_DIR/anteriores"
    [ -f "$TMP_DIR/r$i.lido" ] || continue
    nome="$(cat "$TMP_DIR/nome$i")"; PREFIXO="$nome: "
    nnn="$(printf '%s' "$nome" | sed 's/^RECONCILIACAO-BASE-\([0-9]*\)\.md$/\1/')"
    b0="$(_r "$i" b0_sha)"; p1="$(_r "$i" p1_sha)"; b1="$(_r "$i" b1_sha)"; m="$(_r "$i" m_sha)"
    ob="$(_r "$i" origem_base)"; est="$(_r "$i" estado)"; ant="$(_r "$i" anterior)"
    ex="$(_r "$i" expx_tool)"; br="$(_r "$i" branch)"
    awk -F'\t' -v nnn="$nnn" '$1 == "arquivo" { print $2 "\t" nnn "\t" $5 }' "$TMP_DIR/r$i.lido" >> "$TMP_DIR/cobertura"

    [ "$ex" = "$ORIGEM" ] || motivo 5 contrato "expx_tool ($ex) diverge da origem $ORIGEM"
    if [ -n "$ENTREGA_D" ]; then
      [ "$br" = "$(catalogo_fm "$ENTREGA_D" branch)" ] || motivo 5 contrato "branch ($br) diverge de ENTREGA.branch"
    fi
    if [ "$i" = "$n" ]; then
      [ "$est" = ativa ] || motivo 5 estado "a última reconciliação da cadeia tem de estar ativa (está $est)"
    else
      [ "$est" = superada ] || motivo 5 estado "reconciliação seguida de outra tem de estar superada (está $est)"
    fi

    if [ "$i" = 1 ]; then
      case "$ob" in
        registrada_e0) ;;
        inferida_legado) motivo 5 origem_base 'origem_base inferida_legado ainda não suportada'; continue ;;
        *) motivo 5 origem_base "origem_base $ob não abre a cadeia"; continue ;;
      esac
      inicio="$b0"
    else
      [ "$ob" = reconciliacao_anterior ] || motivo 5 origem_base "origem_base $ob fora de reconciliacao_anterior"
      [ -f "$TMP_DIR/r$j.lido" ] || continue
      prev="$(cat "$TMP_DIR/nome$j")"
      [ "$ant" = "$prev" ] || motivo 5 anterior "anterior ($ant) não é $prev"
      [ "$b0" = "$(_r "$j" b1_sha)" ] || motivo 5 cadeia "b0_sha ($b0) diverge do b1_sha de $prev ($(_r "$j" b1_sha))" # guarda:CAD
      inicio="$(_r "$j" m_sha)"
    fi

    # o ENTREGA.md de M e a âncora da cadeia
    le_entrega_m "$m" "$TMP_DIR/entrega-m$i.md" || continue
    if [ "$i" = 1 ]; then
      bv="$(catalogo_fm "$TMP_DIR/entrega-m$i.md" base_validada_sha)"
      [ "$b0" = "$bv" ] || motivo 5 ancora "b0_sha ($b0) diverge da base_validada_sha da entrega em M (${bv:-ausente})" # guarda:ANCORA
    fi

    # estrutura: os pais de M são os do artefato; M na linha de primeiro pai
    # de HEAD, depois do M anterior
    estrutura_m "$m" "$b0" HEAD || continue
    [ "$P1" = "$p1" ] || { estrutura p1 "p1_sha ($p1) não é o primeiro pai de M ($P1)"; continue; }
    [ "$B1" = "$b1" ] || { estrutura b1 "b1_sha ($b1) não é o segundo pai de M ($B1)"; continue; }
    if [ "$i" -gt 1 ]; then
      lm="$(grep -Fxn -e "$m" "$TMP_DIR/primeiro-pai" | sed -n '1s/:.*//p')"
      lp="$(grep -Fxn -e "$inicio" "$TMP_DIR/primeiro-pai" | sed -n '1s/:.*//p')"
      { [ -n "$lp" ] && [ "$lm" -lt "$lp" ]; } || motivo 5 cadeia "M não é posterior ao M de $prev na linha de primeiro pai de HEAD"
    fi

    # as quatro provas, com o plano e o catálogo da árvore deste M
    materializa_m "$m" "$TMP_DIR/arvore-m$i" || continue
    uniao_e_catalogo "$RAIZ_M" "$PASTA" || continue
    provas "$TMP_DIR/lista$i" "$b0" "$inicio" "$P1" "$B1" "$m"

    # cada campo gravado é recalculado do Git
    while IFS="$TAB" read -r f st bb bm ds <&4; do
      [ -n "$f" ] || continue
      campos_caminho "$b0" "$B1" "$m" "$f"
      [ "$st" = "$CAMPO_ST" ] || motivo 4 campo "$f: status_base registrado $st, recalculado ${CAMPO_ST:-vazio}" # guarda:CAMPO
      [ "$bb" = "$CAMPO_BB" ] || motivo 4 campo "$f: blob_b1 registrado $bb, recalculado ${CAMPO_BB:-ilegível}" # guarda:CAMPO
      [ "$bm" = "$CAMPO_BM" ] || motivo 4 campo "$f: blob_m registrado $bm, recalculado ${CAMPO_BM:-ilegível}" # guarda:CAMPO
      [ "$ds" = "$CAMPO_DS" ] || motivo 4 campo "$f: diff_b1_m_sha256 registrado $ds, recalculado ${CAMPO_DS:-incalculável}" # guarda:CAMPO
    done 4<<EOF
$(awk -F'\t' '$1 == "arquivo" { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' "$TMP_DIR/r$i.lido")
EOF

    inventario "$B1" "$m" "$TMP_DIR/lista$i" "$TMP_DIR/anteriores"
  done
  PREFIXO=""

  # Coerência com o ENTREGA.md do disco: a lista é exatamente a cadeia.
  if [ -n "$ENTREGA_D" ]; then
    j=0
    while IFS="$TAB" read -r numero arquivo eb1 em <&3; do
      [ -n "$numero$arquivo" ] || continue
      j=$((j + 1))
      idx="$(grep -Fxn -e "$arquivo" "$TMP_DIR/artefatos" | sed -n '1s/:.*//p')"
      if [ -z "$idx" ]; then motivo 5 ausente "artefato ausente: $arquivo (listado em ENTREGA.reconciliacoes)"; continue; fi # guarda:COERENCIA
      { [ "$numero" = "$j" ] && [ "$idx" = "$j" ]; } || motivo 5 entrega "ENTREGA.reconciliacoes: o item $j ($numero, $arquivo) não segue a ordem da cadeia"
      [ -f "$TMP_DIR/r$idx.lido" ] || continue
      [ "$eb1" = "$(_r "$idx" b1_sha)" ] || motivo 5 entrega "ENTREGA.reconciliacoes: b1_sha de $arquivo diverge do artefato" # guarda:COERENCIA
      [ "$em" = "$(_r "$idx" m_sha)" ] || motivo 5 entrega "ENTREGA.reconciliacoes: m_sha de $arquivo diverge do artefato" # guarda:COERENCIA
    done 3< "$TMP_DIR/lista-entrega"
    while IFS= read -r nome <&3; do
      cut -f2 "$TMP_DIR/lista-entrega" | grep -Fxq -e "$nome" || motivo 5 orfao "artefato órfão: $nome (fora de ENTREGA.reconciliacoes)" # guarda:COERENCIA
    done 3< "$TMP_DIR/artefatos"
    if [ "$n" -gt 0 ] && [ -f "$TMP_DIR/r$n.lido" ]; then
      bv="$(catalogo_fm "$ENTREGA_D" base_validada_sha)"
      [ "$bv" = "$(_r "$n" b1_sha)" ] || motivo 5 entrega "ENTREGA.base_validada_sha (${bv:-ausente}) não é o b1_sha da última reconciliação" # guarda:COERENCIA
    fi
  fi

  # Cobertura: por caminho, a reconciliação mais recente que o lista; o
  # conteúdo em HEAD tem de ser o blob_m dela.
  awk -F'\t' '{ if (!($1 in u)) o[++k] = $1; u[$1] = $0 } END { for (i = 1; i <= k; i++) print u[o[i]] }' \
    "$TMP_DIR/cobertura" > "$TMP_DIR/cobertura.ultima"
  : > "$TMP_DIR/cobertos"
  while IFS="$TAB" read -r f nnn bm <&3; do
    h="$(g rev-parse --verify -q "HEAD:$f" 2>/dev/null)" || h=""
    [ "$h" = "$bm" ] || { motivo 4 cobertura "$f: o conteúdo em HEAD (${h:-ausente}) não é o blob_m de RECONCILIACAO-BASE-$nnn.md ($bm)"; continue; } # guarda:BLOBM
    printf 'coberto\t%s\t%s\n' "$f" "$nnn" >> "$TMP_DIR/cobertos"
  done 3< "$TMP_DIR/cobertura.ultima"

  if [ "$FALHA_5" = 1 ] || [ "$FALHA_4" = 1 ]; then
    printf 'ok=false\n'
    cat "$MOTIVOS"
    [ "$FALHA_5" = 1 ] && return 5
    return 4
  fi
  printf 'ok=true\n'
  LC_ALL=C sort "$TMP_DIR/cobertos"
  return 0
}

# ---------------------------------------------------------------------------
# Argumentos. Os caminhos vêm depois de `--`, um por argumento, sem word
# splitting; vão para um arquivo, um por linha, depois de recusar os que não
# cabem numa linha.
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-reconciliacao.XXXXXX")" \
  || { printf 'reconciliacao-base: não foi possível criar diretório temporário\n' >&2; exit 1; }
LISTA="$TMP_DIR/lista"
: > "$LISTA"
UNIAO="$TMP_DIR/uniao"
CATALOGO="$TMP_DIR/catalogo"
INVENTARIO="$TMP_DIR/inventario"
SAIDA="$TMP_DIR/saida"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --registrar) [ -z "$MODO" ] || uso; MODO=registrar; shift ;;
    --verificar) [ -z "$MODO" ] || uso; MODO=verificar; shift ;;
    --entrega) [ "$#" -ge 2 ] || uso; ENTREGA="$2"; shift 2 ;;
    --origem) [ "$#" -ge 2 ] || uso; ORIGEM="$2"; shift 2 ;;
    --trabalho) [ "$#" -ge 2 ] || uso; TRABALHO="$2"; shift 2 ;;
    --) SEPARADOR=1; shift; break ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done

case "$MODO" in
  registrar) [ "$SEPARADOR" = 1 ] || uso 'falta -- antes da lista de caminhos' ;;
  verificar) [ "$SEPARADOR" = 0 ] || uso '--verificar não recebe lista de caminhos' ;;
  *) uso 'falta --registrar ou --verificar' ;;
esac
case "$ORIGEM" in sprintx|runx) ;; *) uso "origem inválida: ${ORIGEM:-ausente}" ;; esac
case "$TRABALHO" in
  ''|*[!A-Za-z0-9._-]*|.*|sprintx|manutencao|entregas|eventos|relatorios|legado|stack|projeto)
    uso "trabalho inválido: ${TRABALHO:-ausente}" ;;
esac
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
[ "$ENTREGA" = "docs/entregas/$TRABALHO/ENTREGA.md" ] || uso "--entrega deve ser docs/entregas/$TRABALHO/ENTREGA.md"

for caminho in "$@"; do
  case "$caminho" in
    ''|*"$NL"*|*"$TAB"*) uso "caminho vazio ou com quebra de linha/tabulação" ;;
    /*|./*|..|../*|*/../*|*/..|*/./*|*/.|*//*) uso "caminho fora da forma do Git (relativo à raiz, sem . ou ..): $caminho" ;;
  esac
  grep -Fxq -e "$caminho" "$LISTA" && uso "caminho repetido na lista: $caminho"
  printf '%s\n' "$caminho" >> "$LISTA"
done

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { printf 'reconciliacao-base: fora de um repositório Git\n' >&2; exit 1; }
cd "$RAIZ" || { printf 'reconciliacao-base: raiz inacessível: %s\n' "$RAIZ" >&2; exit 1; }

# Só leitura: nenhuma trava, nenhuma pré-condição de stage ou pasta limpa.
if [ "$MODO" = verificar ]; then
  verificar
  exit $?
fi

# ---------------------------------------------------------------------------
# --registrar. Pré-condições: trava C5, stage vazio, nenhum merge em andamento.
# ---------------------------------------------------------------------------
SAIDA_TRAVA="$(adquirir reconciliacao-base)"; RC_TRAVA=$?
[ "$RC_TRAVA" != 2 ] || para 2 'índice ocupado pela trava C5'
[ "$RC_TRAVA" = 0 ] || para 1 'não foi possível adquirir a trava C5 do índice'
TOKEN="$(printf '%s\n' "$SAIDA_TRAVA" | awk -F= '$1 == "token" { print $2 }')"
[ -n "$TOKEN" ] || para 1 'a trava C5 foi criada sem token'
LIBERAR_NA_SAIDA=1

if g rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  para 3 'merge em andamento (MERGE_HEAD presente): conclua o commit de integração antes de registrar'
fi
g diff --cached --quiet 2>/dev/null || para 3 'o stage não está vazio; nada foi limpo ou adotado'

# ---------------------------------------------------------------------------
# M e o que alimenta as provas. Nada que esteja só no disco entra numa prova:
# o ENTREGA.md, a pasta do trabalho (plano e catálogo) são lidos do commit M.
# ---------------------------------------------------------------------------
M="$(g rev-parse --verify -q HEAD)" || estrutura m 'HEAD ilegível'

# ENTREGA.md (versão de M): contexto explícito igual ao registrado.
ENTREGA_M="$TMP_DIR/entrega-m.md"
le_entrega_m "$M" "$ENTREGA_M" || exit 1
fm() { catalogo_fm "$ENTREGA_M" "$1"; }
BRANCH="$(g branch --show-current 2>/dev/null)" || BRANCH=""
[ -n "$BRANCH" ] || para 5 'HEAD destacado: a branch não prova o trabalho'
[ "$(fm branch)" = "$BRANCH" ] || para 5 "branch ativa ($BRANCH) diverge de ENTREGA.branch"
BRANCH_BASE="$(fm branch_base)"
[ -n "$BRANCH_BASE" ] || para 5 'ENTREGA.branch_base ausente'

materializa_m "$M" "$TMP_DIR/arvore-m" || exit 1

# A pasta do trabalho resolvida em M; no disco ela tem de estar igual a M, sem
# alteração nem arquivo não rastreado (defesa em profundidade).
g status --porcelain=v1 -z --untracked-files=all -- "$PASTA" > "$TMP_DIR/sujo" 2>/dev/null \
  || para 3 'não foi possível verificar se a pasta do trabalho está limpa'
[ ! -s "$TMP_DIR/sujo" ] || para 3 "pasta do trabalho com alteração não commitada: $(tr '\0' ' ' < "$TMP_DIR/sujo" | cut -c1-200)" # guarda:LIMPA

# Na pasta da entrega, só o que o próprio registro grava pode estar pendente
# (antes do checkpoint reconciliacao-base): ENTREGA.md alterado na árvore e
# RECONCILIACAO-BASE-NNN.md não rastreado ou alterado. Caminho casado exato.
ENTREGA_DIR="docs/entregas/$TRABALHO"
g status --porcelain=v1 -z --untracked-files=all -- "$ENTREGA_DIR" > "$TMP_DIR/sujo-entrega" 2>/dev/null \
  || para 3 'não foi possível verificar se a pasta da entrega está limpa'
while IFS= read -r -d '' registro <&3; do
  xy="${registro:0:2}"; p="${registro:3}"; tolerado=0
  if [ "$xy" = ' M' ] && [ "$p" = "$ENTREGA_DIR/ENTREGA.md" ]; then tolerado=1; fi # guarda:LIMPA
  case "$xy:$p" in "??:$ENTREGA_DIR/"RECONCILIACAO-BASE-[0-9][0-9][0-9].md|" M:$ENTREGA_DIR/"RECONCILIACAO-BASE-[0-9][0-9][0-9].md) tolerado=1 ;; esac # guarda:LIMPA
  [ "$tolerado" = 1 ] || para 3 "pasta do trabalho com alteração não commitada (entrega, fora do que o registro grava): $xy $p" # guarda:LIMPA
done 3< "$TMP_DIR/sujo-entrega"

for existente in "docs/entregas/$TRABALHO"/RECONCILIACAO-BASE-*.md; do
  [ -e "$existente" ] || [ -L "$existente" ] || continue
  para 5 "já existe reconciliação registrada ($existente); encadear reconciliações ainda não é suportado"
done

B0="$(fm base_validada_sha)"
[ -n "$B0" ] || para 6 'ENTREGA.base_validada_sha ausente: base validada indeterminável'
printf '%s' "$B0" | grep -Eq '^[0-9a-f]{40}$' || para 5 "ENTREGA.base_validada_sha não é SHA de 40 hex: $B0"

# ---------------------------------------------------------------------------
# Condições estruturais (seção 5). M = HEAD; a linha de primeiro pai é a da
# branch; a ponta da ref de base é condição do momento do registro.
# ---------------------------------------------------------------------------
estrutura_m "$M" "$B0" "$BRANCH" || exit 1
PONTA_BASE="$(g rev-parse --verify -q "$BRANCH_BASE^{commit}")" || estrutura base "ref de base $BRANCH_BASE ilegível"
g merge-base --is-ancestor "$B1" "$PONTA_BASE" 2>/dev/null || estrutura base "B1 $B1 não é ancestral da ponta de $BRANCH_BASE ($PONTA_BASE)" # guarda:EST

# União das tasks e catálogo de método, as quatro provas e o inventário.
uniao_e_catalogo "$RAIZ_M" "$PASTA" || exit 1
provas "$LISTA" "$B0" "$B0" "$P1" "$B1" "$M"
: > "$TMP_DIR/anteriores"
inventario "$B1" "$M" "$LISTA" "$TMP_DIR/anteriores" || exit 1

[ "$FALHAS" = 0 ] || para 4 "$FALHAS reprovação(ões); nada foi gravado"

# ---------------------------------------------------------------------------
# Artefato (seção 7). Só depois de tudo aprovado.
# ---------------------------------------------------------------------------
NOME="RECONCILIACAO-BASE-001.md"
DESTINO="docs/entregas/$TRABALHO/$NOME"
ESC="$TMP_DIR/escalares.tsv"
ARQ="$TMP_DIR/arquivos.tsv"
{
  printf 'expx_tool\t%s\n' "$ORIGEM"
  printf 'trabalho_id\t%s\n' "$TRABALHO"
  printf 'numero\t1\n'
  printf 'anterior\tnull\n'
  printf 'branch\t%s\n' "$BRANCH"
  printf 'branch_base\t%s\n' "$BRANCH_BASE"
  printf 'origem_base\tregistrada_e0\n'
  printf 'b0_sha\t%s\n' "$B0"
  printf 'p1_sha\t%s\n' "$P1"
  printf 'b1_sha\t%s\n' "$B1"
  printf 'm_sha\t%s\n' "$M"
  printf 'estado\tativa\n'
  printf 'registrado_em\t%s\n' "$(date +%Y-%m-%d)"
} > "$ESC" || para 1 'não foi possível montar os escalares do artefato'
: > "$ARQ"
LC_ALL=C sort "$LISTA" > "$TMP_DIR/lista.ord" || para 1 'não foi possível ordenar a lista'
while IFS= read -r f <&3; do
  campos_caminho "$B0" "$B1" "$M" "$f" || para 4 "artefato: $CAMPO_ERRO"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$CAMPO_ST" "$CAMPO_BB" "$CAMPO_BM" "$CAMPO_DS" \
    "ajuste exigido pela integração da base: ver o diff B1..M deste caminho" >> "$ARQ"
done 3< "$TMP_DIR/lista.ord"

[ -d "docs/entregas/$TRABALHO" ] || para 5 "pasta da entrega ausente: docs/entregas/$TRABALHO"

# ---------------------------------------------------------------------------
# ENTREGA.md novo (seção 11). A gravação parte do arquivo do disco, e só se ele
# for byte a byte o de M: nunca se sobrescreve edição alheia. Tudo é montado
# numa cópia; o repositório só muda no fim (artefato e ENTREGA.md, ou nada).
# ---------------------------------------------------------------------------
{ [ -f "$ENTREGA" ] && [ ! -L "$ENTREGA" ] && cmp -s "$ENTREGA" "$ENTREGA_M"; } \
  || para 3 'ENTREGA.md com alteração não commitada' # guarda:DISCO

# a lista de reconciliações do ENTREGA.md só pode estar vazia: não há o que
# acrescentar a entradas sem artefato (a cadeia é de outra etapa)
RECONC_ATUAL="$(fm reconciliacoes)"
if [ -n "$RECONC_ATUAL" ] && [ "$RECONC_ATUAL" != '[]' ]; then
  para 5 'ENTREGA.reconciliacoes não está vazia e não há artefato registrado'
elif [ -z "$RECONC_ATUAL" ] && _entrega_tem "$ENTREGA_M" reconciliacoes; then
  para 5 'ENTREGA.reconciliacoes não está vazia e não há artefato registrado'
fi

ENTREGA_NOVO="$TMP_DIR/entrega-novo.md"
cp "$ENTREGA_M" "$ENTREGA_NOVO" || para 1 'não foi possível preparar o ENTREGA.md novo'
# as únicas chaves de topo que o registro grava (seq e commits nunca entram)
CHAVES_GRAVADAS='base_validada_sha estado portao portao_sha falhas_portao causa push_feito entregue_em atualizado_em' # guarda:SEQ
for chave in $CHAVES_GRAVADAS; do
  case "$chave" in
    base_validada_sha) valor="$B1" ;;
    estado) valor=aberto ;;
    portao|portao_sha|causa|entregue_em) valor=null ;;
    falhas_portao) valor='[]' ;;
    push_feito) valor=false ;;
    atualizado_em) valor="$(date +%Y-%m-%d)" ;;
    *) para 5 "ENTREGA.md: chave fora da lista que o registro grava: $chave" ;;
  esac
  entrega_define "$ENTREGA_NOVO" "$chave" "$valor" || para 5 "ENTREGA.md: $ENTREGA_ERRO"
done
printf '1\t%s\t%s\t%s\n' "$NOME" "$B1" "$M" > "$TMP_DIR/reconciliacoes.tsv"
entrega_reconciliacoes "$ENTREGA_NOVO" "$TMP_DIR/reconciliacoes.tsv" || para 5 "ENTREGA.md: $ENTREGA_ERRO"

# Tudo ou nada: o ENTREGA.md novo fica ao lado do atual (mesma pasta, mesmo
# modo), o artefato é emitido e só então o ENTREGA.md é substituído. Se a
# substituição falhar, o artefato novo é removido e o ENTREGA.md fica intacto.
TMP_ENTREGA="$ENTREGA.registro.$$"
{ cp -p "$ENTREGA" "$TMP_ENTREGA" && cat "$ENTREGA_NOVO" > "$TMP_ENTREGA"; } 2>/dev/null \
  || para 1 'não foi possível preparar o ENTREGA.md novo na pasta da entrega'
RB_ERRO=""
ARTEFATO_NOVO=1 # guarda:JANELA
rb_emitir "$DESTINO" "$ESC" "$ARQ" || para 5 "artefato não emitido: $RB_ERRO"
if ! mv "$TMP_ENTREGA" "$ENTREGA" 2>/dev/null; then
  para 1 'não foi possível atualizar o ENTREGA.md; o artefato foi removido e nada foi gravado'
fi
ARTEFATO_NOVO=0 # guarda:JANELA
TMP_ENTREGA=""

printf 'registrado=%s\n' "$NOME"
printf 'b0=%s\n' "$B0"
printf 'p1=%s\n' "$P1"
printf 'b1=%s\n' "$B1"
printf 'm=%s\n' "$M"
exit 0
