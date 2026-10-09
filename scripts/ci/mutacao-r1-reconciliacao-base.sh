#!/usr/bin/env bash
# Controle e 38 mutantes da reconciliação de base pós-E8 (R1), da barreira de
# push da DM-184 (R2) e da seleção da entrega pelo conteúdo (DM-185). Os 17
# primeiros são a lista da spec (seção 21); os 8 seguintes completam a barreira
# de push; os 13 últimos (26-38) são os da seleção pelo conteúdo.
#
# Cada mutante altera só uma CÓPIA temporária do repositório (git ls-files ->
# tar -> git init + commit), nunca o repositório real. A regra geral é a do
# plano: TODAS as linhas terminadas em `# guarda:<ID>` viram `: # mutante <ID>`,
# com a indentação preservada. A troca é conferida (linhas `# mutante <ID>` =
# linhas marcadas antes, nenhuma marca restante) e os .sh mutados passam por
# `bash -n` antes da suíte; troca que não confere ou sintaxe quebrada é
# `invalido`, nunca `morto`.
#
# Onde `:` sozinho quebraria a sintaxe ou faria outra coisa que não a mutação
# da tabela, a troca é a mínima que realiza a descrição (sempre na linha
# marcada, que termina em `# mutante <ID>`):
#   - continuação `|| guarda` (linha anterior termina em `\`): `|| :`;
#   - braço de case `*) guarda ;;`: `*) : ;;`;
#   - `if|elif <cond>; then` (O10): `if false; then` (o critério nunca se aplica);
#   - `cmd > estado || guarda`, cujo estado outras guardas leem (P3: a união e o
#     catálogo, que o inventário também usa; V9SHA: `cs=`): mantém `cmd`,
#     a guarda vira `|| :`;
#   - V9SHA: as atribuições de BASE (pela reconciliação, pela base validada e
#     pelo legado) passam a usar o merge-base de HEAD com a REF `branch_base`
#     (o defeito original, `branch_base...HEAD`); o `elif` que escolhe o
#     caminho do SHA é mantido (fluxo, não guarda); as demais guardas, `:`;
#   - PPSHA: o `pre-push` passa `git rev-parse HEAD` (o checkout) no lugar do
#     SHA enviado a `pr_decide_ref`, e `--rev "$sl"` some (a validade cai no
#     HEAD padrão);
#   - P2FP: a linha marcada é a do `rev-list` da prova 2; a mutação é a literal
#     da tabela, que só remove `--first-parent` dela.
# Exceções com semântica própria (plano, Task 21, e decisão do controlador):
#   - SEQ: a linha marcada (CHAVES_GRAVADAS) fica; o mutante ACRESCENTA ao
#     registro, logo depois de `entrega_reconciliacoes`, uma chamada a
#     `sequencia-de-commits.sh --acrescentar` sobre o ENTREGA.md novo (este
#     arquivo está na lista de escritores esperados do validador do contrato);
#   - ATVHP: a linha marcada fica; o mutante ACRESCENTA ao braço `instalar)`
#     de ativacao-pre-push.sh um `git config core.hooksPath` (o E0 grava
#     core.hooksPath);
#   - ATVSOB: a guarda `! existe || gerenciado || terceiro` vira `:` E o
#     `set -C` da instalação é desfeito: o chamador gerenciado é escrito POR
#     CIMA do pre-push de terceiro (sobrescrita de verdade, que as checagens de
#     hash da bancada têm de pegar);
#   - CIATIVO: a verificação vira `:` e a frase-alvo entra no reference
#     12-barreira-de-push.md;
#   - E2SEMHOOK: as linhas de registrar-portao.sh e de persistir-metodo.sh são
#     neutralizadas juntas.
# Exceções da DM-185 (seleção da entrega pelo conteúdo; `troca_marca`: a linha
# marcada vira o corpo abaixo, sempre terminada em `# mutante <ID>`):
#   - CINOME (troca): o CI seleciona pela regra do nome, `pr_entrega_da_ref
#     "$RAIZ" "$REF" "$SHA" "$SHA"` (a regra legada pelo --branch), em vez de
#     `pr_entregas_do_intervalo`;
#   - BRDIV (troca): a divergência entre --branch e o branch: da entrega barra
#     (`_pr_sai barra branch_divergente`) em vez de só avisar;
#   - CIFULL2 (literal): só a opção sai, `set -- "$@"` no lugar de
#     `set -- "$@" --full-history`;
#   - CIMBALL (literal): vários merge-bases passam a aceitar o primeiro
#     (`n=1`) em vez de `base_ambigua`;
#   - CIDEL (literal): o `case` dos status aceitos perde o `D` (`A|M|T`).
# CIDIFF, CIHIST, CIAGREG, PPBASE, PPLEG, PPTRL, PPCOB e M3CHAM seguem a troca
# geral por `:`.
#
# Morto: alguma suíte alvo sai com rc != 0 POR FALHA DE CASO (linha `  FALHA`
# e resumo `<n> ok, <m> falha(s)` com m > 0; no validador do contrato,
# `contract check failed:`). rc != 0 sem falha de caso é erro de ambiente:
# não conta como morto. Um erro de execução do script mutado DENTRO de um caso
# (rc inesperado, variável não definida, comando ausente) aparece como caso
# reprovado e conta como morto: o `bash -n` prévio só pega erro de sintaxe.
#
# Diafonia: `r2 ativacao`, `r2 entrypoints` e `.claude/hooks/teste.sh` fazem
# `pgrep`/`pkill` global de `sleep 3077`/`sleep 3119`. As suítes e os mutantes
# que as usam rodam em SÉRIE, sozinhos, depois do lote paralelo (no controle e
# na matriz).
#
# Uso: bash scripts/ci/mutacao-r1-reconciliacao-base.sh [controle | <ID>]
#   sem argumento: controle + os 38 mutantes; `controle`: só o controle;
#   <ID>: controle das suítes daquele ID + o mutante.
# rc 0 só com controle verde e todos os mutantes executados mortos.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARALELO=4
INICIO="$(date +%s)"

MATRIZ='1|P1|r1:provas|prova 1 desligada
2|P1D|r1:provas|prova 1 aceita status D
3|P2FP|r1:provas r1:cadeia|prova 2 sem --first-parent
4|P3|r1:provas|prova 3 desligada
5|P4|r1:provas|prova 4 desligada
6|INV|r1:provas|inventário desligado
7|ASS|r1:artefato|assinatura não conferida
8|CAD|r1:cadeia|encadeamento não conferido
9|BLOBM|r1:verificar|cobertura sem blob_m
10|V9SHA|r1:v9|V9 pela ref em vez do SHA
11|PTPROD|r1:portao|portão aceita commit de produto
12|PTMERGE|r1:portao|portão aceita merge
13|PPSHA|r2:prepush|pre-push valida o HEAD do checkout em vez do SHA enviado
14|PPMODO|r2:prepush|pre-push deixa o modo aviso afrouxar pronto vencido
15|LEG2|r1:legado|legado aceita dois merge-bases
16|SEQ|r1:entrega r1:invariantes|registro grava seq (sequencia-de-commits.sh --acrescentar)
17|O10|atencao|O10 permite faixa média
18|PPMULTI|r2:prepush|pre-push ignora uma segunda ref inválida
19|VALOBJ|r1:portao r2:prepush|objeto Git ausente classificado como erro_ambiente
20|ATVTXT|r2:ativacao|prova aceita hook que só cita a MergeX
21|ATVSOB|r2:ativacao|E0 sobrescreve um pre-push de terceiro
22|ATVHP|r2:ativacao|E0 grava core.hooksPath
23|HKNV|hooks|hook do Claude aceita --no-verify
24|CIATIVO|contrato r2:ci|contrato aceita texto que afirma CI ativo
25|E2SEMHOOK|r2:entrypoints|E2 ignora a prova funcional e emite/persiste PRONTO
26|CINOME|r2:ci|o CI seleciona pela regra do nome em vez de pr_entregas_do_intervalo
27|CIDIFF|r2:ci|seleção sem a parcela do diff de árvores
28|CIHIST|r2:ci|seleção sem a parcela dos commits não-merge
29|CIFULL2|r2:ci|parcela dos commits sem --full-history
30|CIMBALL|r2:ci|seleção aceita o primeiro de vários merge-bases
31|CIDEL|r2:ci|parcela do diff de árvores ignora o status D
32|CIAGREG|r2:ci|agregação devolve a decisão da primeira entrega
33|BRDIV|r2:ci|branch_divergente barra em vez de avisar
34|PPBASE|r2:prepush|pre-push sem a parcela do conteúdo
35|PPLEG|r2:prepush|pre-push sem a parcela legada pelo nome
36|PPTRL|r2:prepush|pre-push sem a parcela do trailer
37|PPCOB|r2:prepush|pre-push sem o aviso cobertura_indeterminada
38|M3CHAM|r2:prepush|chamador gerenciado sem conferir o validador'

RAIZ_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mutacao-r1.XXXXXX")" || { echo 'sem diretório temporário' >&2; exit 1; }
limpa() { rm -rf "$RAIZ_TMP"; }
interrompe() {
  trap '' INT TERM
  kill -TERM 0 2>/dev/null
  wait 2>/dev/null
  limpa
  exit 130
}
trap limpa EXIT
trap interrompe INT TERM
# as suítes criam os temporários delas aqui dentro: nada fica em /tmp
mkdir -p "$RAIZ_TMP/tmp" "$RAIZ_TMP/res" "$RAIZ_TMP/ctl" || exit 1
export TMPDIR="$RAIZ_TMP/tmp"

copia() { # <nome> — cópia do repositório num Git novo, com um commit
  local d="$RAIZ_TMP/copias/$1"
  mkdir -p "$d" || return 1
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - ) || return 1
  (
    cd "$d" || exit 1
    git init -q -b main . || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config core.autocrlf false
    git add -A && git commit -qm fixture || exit 1
  ) || return 1
  printf '%s\n' "$d"
}

# marcadas <dir> <padrão> — arquivos com linhas que terminam no padrão (fora deste script)
marcadas() {
  ( cd "$1" && grep -rlIE --exclude-dir=.git --exclude='mutacao-*' -- "$2[[:space:]]*\$" . )
}
conta() { # <dir> <padrão>
  ( cd "$1" && grep -rhIE --exclude-dir=.git --exclude='mutacao-*' -- "$2[[:space:]]*\$" . | wc -l | tr -d ' ' )
}

# neutraliza <dir> <ID> — troca todas as linhas `# guarda:<ID>` (ver cabeçalho)
neutraliza() {
  local d="$1" id="$2" n0 n1 resto f
  n0="$(conta "$d" "# guarda:$id")"
  [ "$n0" -gt 0 ] || { echo "nenhuma linha marcada com $id" >&2; return 1; }
  for f in $(marcadas "$d" "# guarda:$id"); do
    ID="$id" awk '
      BEGIN { id = ENVIRON["ID"]; m = "# mutante " id }
      $0 !~ ("# guarda:" id "[ \t]*$") { print; next }
      {
        match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH); corpo = substr($0, RLENGTH + 1)
        sub(/[ \t]*# guarda:[A-Za-z0-9]+[ \t]*$/, "", corpo)
        if (id == "V9SHA" && corpo ~ /^BASE=/) {
          o = corpo; sub(/^.*; ORIGEM_BASE=/, "", o)
          print ind "BASE=\"$(g merge-base \"$HEAD_SHA\" \"$(catalogo_fm \"$ENTREGA_H\" branch_base)\" 2>/dev/null | sed -n 1p)\"; ORIGEM_BASE=" o " " m
          next
        }
        if (id == "V9SHA" && corpo ~ /^elif /) { print ind corpo " " m; next }
        if (id == "P2FP") { sub(/ --first-parent /, " ", corpo); print ind corpo " " m; next }
        if (id == "PPSHA" && corpo ~ /^pr_decide_ref /) {
          gsub(/"\$sha_local"/, "\"$(git -C \"$RAIZ\" rev-parse HEAD)\"", corpo)
          print ind corpo " " m
          next
        }
        if ((id == "P3" && corpo ~ /^(bash "\$OWNERSHIP_SH"|catalogo_metodo )/) || (id == "V9SHA" && corpo ~ /^cs=/)) {
          print ind substr(corpo, 1, index(corpo, " || ") - 1) " || : " m
          next
        }
        if (corpo ~ /^\|\|/) { print ind "|| : " m; next }
        if (corpo ~ /^\*\)/) { print ind "*) : ;; " m; next }
        if (corpo ~ /^if .*; then$/) { print ind "if false; then " m; next }
        if (corpo ~ /^elif .*; then$/) { print ind "elif false; then " m; next }
        print ind ": " m
      }' "$d/$f" > "$d/$f.mut" || return 1
    cat "$d/$f.mut" > "$d/$f" && rm -f "$d/$f.mut" || return 1
  done
  n1="$(conta "$d" "# mutante $id")"
  resto="$(conta "$d" "# guarda:$id")"
  [ "$n1" = "$n0" ] && [ "$resto" = 0 ] \
    || { echo "troca de $id não confere: $n0 marcadas, $n1 trocadas, $resto restantes" >&2; return 1; }
  echo "$id: $n1 linha(s) trocada(s) em $(marcadas "$d" "# mutante $id" | tr '\n' ' ')"
}

# insere_depois <arquivo> <linha exata> <linha nova> — exatamente uma ocorrência
insere_depois() {
  local arq="$1"
  [ "$(grep -Fxc -- "$2" "$arq")" = 1 ] || return 1
  A="$2" B="$3" awk '{ print } $0 == ENVIRON["A"] { print ENVIRON["B"] }' "$arq" > "$arq.mut" || return 1
  cat "$arq.mut" > "$arq" && rm -f "$arq.mut"
}

# troca_marca <dir> <ID> <arquivo> <corpo> — exceção de troca/literal: neutraliza
# (a linha vira `: # mutante <ID>`) e o `:` é substituído pelo <corpo> exato,
# na mesma linha, com a indentação preservada e terminando em `# mutante <ID>`
troca_marca() {
  local d="$1" id="$2" arq="$d/$3"
  neutraliza "$d" "$id" || return 1
  [ "$(grep -c -- "# mutante $id[[:space:]]*\$" "$arq")" = 1 ] \
    || { echo "$id: a linha marcada não está em $3" >&2; return 1; }
  ID="$id" CORPO="$4" awk '
    BEGIN { m = "# mutante " ENVIRON["ID"] }
    $0 ~ (m "[ \t]*$") { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) ENVIRON["CORPO"] " " m; next }
    { print }' "$arq" > "$arq.mut" || return 1
  cat "$arq.mut" > "$arq" && rm -f "$arq.mut" || return 1
  echo "$id: linha trocada por \`$4\` em $3"
}

aplica() { # <dir> <ID>
  local d="$1" id="$2" rb ref atv
  atv="$d/.claude/skills/mergex/scripts/ativacao-pre-push.sh"
  case "$id" in
    SEQ)
      rb="$d/.claude/skills/mergex/scripts/reconciliacao-base.sh"
      insere_depois "$rb" \
        'entrega_reconciliacoes "$ENTREGA_NOVO" "$TMP_DIR/reconciliacoes.tsv" || para 5 "ENTREGA.md: $ENTREGA_ERRO"' \
        'bash "$AQUI/sequencia-de-commits.sh" --acrescentar "$ENTREGA_NOVO" T-01.01 "$M" >/dev/null # mutante SEQ' \
        || { echo 'SEQ: ponto do registro não encontrado' >&2; return 1; }
      [ "$(conta "$d" '# mutante SEQ')" = 1 ] || { echo 'SEQ: chamada não inserida' >&2; return 1; }
      echo "SEQ: chamada a --acrescentar inserida em .claude/skills/mergex/scripts/reconciliacao-base.sh"
      ;;
    P2FP)
      neutraliza "$d" P2FP || return 1
      [ "$(grep -c -- '--first-parent .*# mutante P2FP' "$d/.claude/skills/mergex/scripts/reconciliacao-base.sh")" = 0 ] \
        || { echo 'P2FP: --first-parent continua na linha marcada' >&2; return 1; }
      ;;
    ATVHP)
      insere_depois "$atv" '  instalar)' \
        '    git -C "$RAIZ" config core.hooksPath "$HOOKS" # mutante ATVHP' \
        || { echo 'ATVHP: braço instalar) não encontrado' >&2; return 1; }
      [ "$(conta "$d" '# mutante ATVHP')" = 1 ] || { echo 'ATVHP: config não inserida' >&2; return 1; }
      echo "ATVHP: git config core.hooksPath inserido no braço instalar) de ativacao-pre-push.sh"
      ;;
    ATVSOB)
      neutraliza "$d" ATVSOB || return 1
      [ "$(grep -c '( set -C; LINHA=' "$atv")" = 1 ] || { echo 'ATVSOB: set -C da instalação não encontrado' >&2; return 1; }
      sed 's/( set -C; LINHA=/( LINHA=/' "$atv" > "$atv.mut" && cat "$atv.mut" > "$atv" && rm -f "$atv.mut" || return 1
      [ "$(grep -c 'set -C' "$atv")" = 0 ] || { echo 'ATVSOB: set -C continua' >&2; return 1; }
      echo "ATVSOB: set -C da instalação desfeito em ativacao-pre-push.sh"
      ;;
    CIATIVO)
      neutraliza "$d" CIATIVO || return 1
      ref="$d/.claude/skills/mergex/references/12-barreira-de-push.md"
      [ -f "$ref" ] || { echo 'CIATIVO: reference ausente' >&2; return 1; }
      printf '\nCI do portão ativo em todo produto.\n' >> "$ref"
      grep -Fxq 'CI do portão ativo em todo produto.' "$ref" || return 1
      echo "CIATIVO: frase-alvo inserida em .claude/skills/mergex/references/12-barreira-de-push.md"
      ;;
    E2SEMHOOK)
      neutraliza "$d" E2SEMHOOK || return 1
      [ "$(marcadas "$d" '# mutante E2SEMHOOK' | grep -Ec 'registrar-portao\.sh|persistir-metodo\.sh')" = 2 ] \
        || { echo 'E2SEMHOOK: os dois entrypoints não foram neutralizados juntos' >&2; return 1; }
      ;;
    CINOME)
      troca_marca "$d" CINOME .claude/skills/mergex/scripts/portao-ci.sh \
        'pr_entrega_da_ref "$RAIZ" "$REF" "$SHA" "$SHA" > "$TMP_DIR/selecao" || SEL_RC=1' || return 1
      ;;
    BRDIV)
      troca_marca "$d" BRDIV .claude/skills/mergex/scripts/portao-ci.sh \
        '[ "$DECLARA" = 1 ] || { _pr_sai barra branch_divergente - "branch_divergente: o nome da branch não é o branch: da entrega" > "$TMP"; final; }' || return 1
      ;;
    CIMBALL)
      troca_marca "$d" CIMBALL .claude/skills/mergex/scripts/portao-regras.sh \
        '[ "$n" -le 1 ] || n=1' || return 1
      ;;
    CIDEL)
      troca_marca "$d" CIDEL .claude/skills/mergex/scripts/portao-regras.sh \
        'case "$st" in A|M|T) aceito=1 ;; esac' || return 1
      ;;
    CIFULL2)
      troca_marca "$d" CIFULL2 .claude/skills/mergex/scripts/portao-regras.sh \
        'set -- "$@"' || return 1
      ;;
    *) neutraliza "$d" "$id" || return 1 ;;
  esac
}

# suite <dir> <token> — roda uma suíte alvo dentro da cópia
suite() {
  local d="$1" t="$2"
  case "$t" in
    r1:*) ( cd "$d" && bash scripts/ci/test-r1-reconciliacao-base.sh "${t#r1:}" ) ;;
    r2:*) ( cd "$d" && bash scripts/ci/test-r2-barreira-push.sh "${t#r2:}" ) ;;
    hooks) ( cd "$d" && bash .claude/hooks/teste.sh ) ;;
    atencao) ( cd "$d" && bash scripts/ci/test-atencao-metodo.sh ) ;;
    contrato) ( cd "$d" && bash scripts/ci/validate-mergex-contract.sh ) ;;
    *) echo "suíte desconhecida: $t" >&2; return 99 ;;
  esac
}

# falha_de_caso <token> <log> — o rc != 0 veio de caso reprovado?
falha_de_caso() {
  case "$1" in
    contrato) grep -q '^contract check failed:' "$2" ;;
    *) grep -q '^  FALHA ' "$2" && grep -Eq '^[0-9]+ ok, [1-9][0-9]* falha' "$2" ;;
  esac
}
primeiro_caso() { # <token> <log>
  case "$1" in
    contrato) grep -m1 '^contract check failed:' "$2" ;;
    *) grep -m3 '^  FALHA ' "$2" | sed 's/^  FALHA //' | cut -c1-160 | paste -sd'|' - ;;
  esac | cut -c1-500
}

# executa <n> <ID> <tokens> — resultado em res/<n>: n|ID|estado|suítes|rcs|caso
executa() {
  local n="$1" id="$2" toks="$3" d t rc rcs="" sts="" estado=vivo caso="" mudados f log erro=0
  d="$(copia "m$n-$id")" || { printf '%s|%s|invalido|%s|-|cópia falhou\n' "$n" "$id" "${toks// /+}" > "$RAIZ_TMP/res/$n.res"; return; }
  if ! aplica "$d" "$id" > "$RAIZ_TMP/res/$n.aplica" 2>&1; then
    printf '%s|%s|invalido|%s|-|%s\n' "$n" "$id" "${toks// /+}" "$(tr '\n' ' ' < "$RAIZ_TMP/res/$n.aplica")" > "$RAIZ_TMP/res/$n.res"; return
  fi
  mudados="$(cd "$d" && git diff --name-only)"
  for f in $mudados; do
    case "$f" in *.sh)
      bash -n "$d/$f" 2>>"$RAIZ_TMP/res/$n.aplica" \
        || { printf '%s|%s|invalido|%s|-|bash -n reprovou %s\n' "$n" "$id" "${toks// /+}" "$f" > "$RAIZ_TMP/res/$n.res"; return; } ;;
    esac
  done
  ( cd "$d" && git add -A && git commit -qm "mutante $id" ) || { printf '%s|%s|invalido|%s|-|commit da mutação falhou\n' "$n" "$id" "${toks// /+}" > "$RAIZ_TMP/res/$n.res"; return; }
  for t in $toks; do
    log="$RAIZ_TMP/res/$n.${t//:/-}.log"
    suite "$d" "$t" > "$log" 2>&1; rc=$?
    rcs="${rcs:+$rcs+}$rc"; sts="${sts:+$sts+}$t"
    if [ "$rc" != 0 ]; then
      if falha_de_caso "$t" "$log"; then
        estado=morto
        caso="${caso:+$caso ; }[$t] $(primeiro_caso "$t" "$log")"
      else
        erro=1
      fi
    fi
  done
  [ "$estado" = morto ] || [ "$erro" = 0 ] || { estado=invalido; caso="rc != 0 sem falha de caso: $(tail -n 3 "$RAIZ_TMP/res/$n."*.log | tr '\n' ' ' | cut -c1-220)"; }
  printf '%s|%s|%s|%s|%s|%s\n' "$n" "$id" "$estado" "$sts" "$rcs" "$caso" > "$RAIZ_TMP/res/$n.res"
  rm -rf "$d"
}

# controle <tokens...> — cada suíte numa cópia sem mutação; todas verdes
# serial <tokens> — algum token usa pgrep/pkill global (ver cabeçalho)?
serial() {
  case " $* " in *" r2:ativacao "*|*" r2:entrypoints "*|*" hooks "*) return 0 ;; esac
  return 1
}

controle_um() { # <token>
  local t="$1" d
  d="$(copia "ctl-${t//:/-}")" || { echo "$t|copia" > "$RAIZ_TMP/ctl/${t//:/-}"; return; }
  suite "$d" "$t" > "$RAIZ_TMP/ctl/${t//:/-}.log" 2>&1
  echo "$t|$?" > "$RAIZ_TMP/ctl/${t//:/-}"
  rm -rf "$d"
}

controle() {
  local t ativos=0 verde=0 linha
  for t in "$@"; do
    serial "$t" && continue
    ( controle_um "$t" ) < /dev/null &
    ativos=$((ativos + 1))
    if [ "$ativos" -ge "$PARALELO" ]; then wait; ativos=0; fi
  done
  wait
  for t in "$@"; do
    serial "$t" || continue
    ( controle_um "$t" ) < /dev/null
  done
  for t in "$@"; do
    linha="$(cat "$RAIZ_TMP/ctl/${t//:/-}" 2>/dev/null)"
    if [ "$linha" = "$t|0" ]; then echo "ok    controle $t"
    else
      verde=1
      echo "FALHA controle $t (${linha#*|})"
      grep -m5 -E '^  FALHA |contract check failed|NAO_EXECUTADO' "$RAIZ_TMP/ctl/${t//:/-}.log" 2>/dev/null | sed 's/^/        /'
    fi
  done
  return "$verde"
}

tempo() { echo "tempo: $(( $(date +%s) - INICIO ))s"; }

# --- seleção ------------------------------------------------------------------
[ "$#" -le 1 ] || { echo "uso: $0 [controle | <ID>]" >&2; exit 64; }
SEL="$MATRIZ"
if [ "$#" = 1 ] && [ "$1" != controle ]; then
  SEL="$(printf '%s\n' "$MATRIZ" | awk -F'|' -v id="$1" '$2 == id')"
  [ -n "$SEL" ] || { echo "ID desconhecido: $1" >&2; exit 64; }
fi
TOKENS="$(printf '%s\n' "$SEL" | cut -d'|' -f3 | tr ' ' '\n' | awk 'NF && !v[$0]++' | tr '\n' ' ')"

echo "Controle - cópia sem mutação: $TOKENS"
# shellcheck disable=SC2086
if controle $TOKENS; then echo 'controle verde'
else echo 'controle VERMELHO: sem controle verde não há matriz' >&2; tempo; exit 1; fi
[ "${1:-}" != controle ] || { tempo; exit 0; }
echo

ativos=0
while IFS='|' read -r n id toks _desc; do
  [ -n "$n" ] || continue
  # shellcheck disable=SC2086
  serial $toks && continue
  ( executa "$n" "$id" "$toks" ) < /dev/null &
  ativos=$((ativos + 1))
  if [ "$ativos" -ge "$PARALELO" ]; then wait; ativos=0; fi
done <<EOF
$SEL
EOF
wait
# os que usam pgrep/pkill global: um de cada vez, sem nada em paralelo
while IFS='|' read -r n id toks _desc; do
  [ -n "$n" ] || continue
  # shellcheck disable=SC2086
  serial $toks || continue
  ( executa "$n" "$id" "$toks" ) < /dev/null
done <<EOF
$SEL
EOF
# mutante sem resultado (subshell morto no meio): invalido, nunca omitido
while IFS='|' read -r n id toks _desc; do
  [ -n "$n" ] && [ ! -f "$RAIZ_TMP/res/$n.res" ] || continue
  printf '%s|%s|invalido|%s|-|sem resultado\n' "$n" "$id" "${toks// /+}" > "$RAIZ_TMP/res/$n.res"
done <<EOF
$SEL
EOF

mortos=0; vivos=0; invalidos=0; total=0
while IFS='|' read -r n id estado sts rcs caso; do
  total=$((total + 1))
  case "$estado" in
    morto) mortos=$((mortos + 1)) ;;
    vivo) vivos=$((vivos + 1)) ;;
    *) invalidos=$((invalidos + 1)) ;;
  esac
  printf '%s %s %s %s %s\n' "$n" "$id" "$estado" "$sts" "$rcs"
  [ -z "$caso" ] || printf '      caso: %s\n' "$caso"
done < <(cat "$RAIZ_TMP"/res/*.res 2>/dev/null | grep -av '^$' | LC_ALL=C sort -t'|' -k1,1n)
esperado="$(printf '%s\n' "$SEL" | grep -c .)"

echo
printf '%d mortos, %d vivos\n' "$mortos" "$vivos"
[ "$invalidos" = 0 ] || printf '%d invalido(s)\n' "$invalidos"
tempo
[ "$total" = "$esperado" ] && [ "$mortos" = "$esperado" ] && [ "$vivos" = 0 ] && [ "$invalidos" = 0 ]
