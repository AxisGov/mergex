#!/usr/bin/env bash
# pr-so-com-portao — PreToolUse em execução de comando.
#
# Barra o push e a abertura de pull request quando o portão de prontidão não
# registrou PRONTO, ou quando o PRONTO registrado não vale para a revisão que o
# comando publica.
#
# O portão (E2) barra e explica; sem ele, o trabalho incompleto chega ao
# revisor — que é exatamente o recurso caro que a skill existe para poupar.
#
# Modo padrão: AVISO (hook de método). FALHA ABERTA — menos numa condição:
# o portão `pronto` que não se prova válido para a revisão publicada barra com
# exit 2 em QUALQUER modo, inclusive `desligado` (spec
# 2026-10-07-reconciliacao-base-pos-e8, §4.5 e §13.5). Entram nela:
# validade-do-portao.sh ok=false, script ausente ou que não se calcula, refspec
# que o hook não sabe avaliar e push que o hook não consegue ler. Deixada
# passar, ela publicaria código que o portão não avaliou. `null` e `bloqueado`
# seguem o modo configurado, como sempre.
#
# Tudo sai do Git, nunca do disco: a branch EMPURRADA decide o trabalho (o
# ENTREGA.md da árvore da revisão empurrada que declara aquela branch), e o
# `portao` é lido de <revisão>:ENTREGA.md.

HOOK="pr-so-com-portao"
PADRAO="aviso"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../comum/base.sh
. "$DIR/../comum/base.sh"
# A mesma instalação publica hooks e skill lado a lado em .claude/.
VALIDADE="$DIR/../../skills/mergex/scripts/validade-do-portao.sh"

ENTRADA="$(cat)"
[ "$(printf '%s' "$ENTRADA" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0

CMD="$(printf '%s' "$ENTRADA" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

# Saída antecipada: sem `push` nem `create`, não há o que publicar.
case "$CMD" in *push*|*create*) ;; *) exit 0 ;; esac

CWD="$(printf '%s' "$ENTRADA" | jq -r '.cwd // empty' 2>/dev/null)"
DIR_INICIAL="${CWD:-$PWD}"
RAIZ="$(expx_raiz "$DIR_INICIAL")"
MODO="$(expx_modo "$HOOK" "$PADRAO" "$RAIZ")"

# --------------------------------------------------------------------------
# Itens: (repositório, branch empurrada, revisão empurrada, motivo de não
# avaliável). Um push que não se reduz a repositório + branch é INDETERMINADO.
# --------------------------------------------------------------------------
IT_RAIZ=(); IT_BRANCH=(); IT_REV=(); IT_NA=()
INDET=""        # por que algum push não se reduz a branch e repositório
RAIZES=""       # repositórios tocados (para decidir se há trabalho da mergex)
ACAO=""

item() { # <raiz> <branch> <rev|""> <motivo-nao-avaliavel|"">
  local n="${#IT_RAIZ[@]}"
  IT_RAIZ[$n]="$1"; IT_BRANCH[$n]="$2"; IT_REV[$n]="$3"; IT_NA[$n]="$4"
}
indeterminado() { [ -n "$INDET" ] || INDET="$1"; }

# Valor literal: sem expansão, glob nem aspas internas. O hook lê o texto.
literal() {
  case "$1" in
    ''|*'$'*|*'`'*|*'~'*|*'*'*|*'?'*|*'['*|*'"'*|*"'"*|*'\'*) return 1 ;;
  esac
  return 0
}
absoluto() { # <base> <caminho>
  case "$2" in
    /*|[A-Za-z]:*) printf '%s' "$2" ;;
    *) [ -n "$1" ] || return 1; printf '%s/%s' "$1" "$2" ;;
  esac
}
nome_de_branch() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9@][A-Za-z0-9._/@-]*$'; }
ponta() { git -C "$1" rev-parse --verify -q "refs/heads/$2^{commit}" 2>/dev/null; }

# --------------------------------------------------------------------------
# O repositório do push: diretório do segmento (com `cd` literal), `-C`,
# `--git-dir`, `--work-tree`. Valor que não se resolve, ou `GIT_*=` no
# ambiente do comando, torna o push indeterminado.
# --------------------------------------------------------------------------
REPO=""; REPO_ERRO=""
resolve_repo() {
  local d="$DIR_SEG" i t v n gd1 gd2
  local args=()
  REPO=""; REPO_ERRO=""
  [ -n "$d" ] || { REPO_ERRO="o diretório do comando depende de um cd que não se resolve"; return 1; }
  [ "$EXPX_PUSH_AMBIENTE_GIT" = 0 ] || { REPO_ERRO="variável GIT_* no ambiente do push"; return 1; }
  n="${#EXPX_PUSH_GLOBAIS[@]}"; i=0
  while [ "$i" -lt "$n" ]; do
    t="${EXPX_PUSH_GLOBAIS[$i]}"; i=$((i + 1))
    case "$t" in
      -C|--git-dir|--work-tree)
        v="${EXPX_PUSH_GLOBAIS[$i]:-}"; i=$((i + 1))
        literal "$v" || { REPO_ERRO="$t com valor que não se resolve: $v"; return 1; }
        v="$(absoluto "$d" "$v")" || { REPO_ERRO="$t relativo sem diretório"; return 1; }
        if [ "$t" = -C ]; then d="$v"; else args[${#args[@]}]="$t=$v"; fi ;;
      --git-dir=*|--work-tree=*)
        v="${t#*=}"
        literal "$v" || { REPO_ERRO="${t%%=*} com valor que não se resolve: $v"; return 1; }
        v="$(absoluto "$d" "$v")" || { REPO_ERRO="${t%%=*} relativo sem diretório"; return 1; }
        args[${#args[@]}]="${t%%=*}=$v" ;;
      -c|--namespace|--exec-path|--super-prefix|--attr-source|--config-env) i=$((i + 1)) ;;
      *) ;;
    esac
  done
  REPO="$(git -C "$d" ${args[@]+"${args[@]}"} rev-parse --show-toplevel 2>/dev/null)" \
    || { REPO=""; REPO_ERRO="o repositório de destino não se resolve"; return 1; }
  if [ "${#args[@]}" -gt 0 ]; then
    gd1="$(git -C "$d" "${args[@]}" rev-parse --absolute-git-dir 2>/dev/null)"
    gd2="$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null)"
    [ -n "$gd1" ] && [ "$gd1" = "$gd2" ] || { REPO=""; REPO_ERRO="--git-dir/--work-tree não correspondem a um checkout"; return 1; }
  fi
  RAIZES="$RAIZES$REPO
"
  return 0
}

# classifica <raiz> <origem> — CO_TIPO: head | branch | commit | vazia | nao_resolve
CO_TIPO=""; CO_BRANCH=""
classifica() {
  local r="$1" s="$2"
  CO_TIPO=""; CO_BRANCH=""
  case "$s" in
    '') CO_TIPO=vazia; return 0 ;;
    HEAD|@) CO_TIPO=head; return 0 ;;
  esac
  nome_de_branch "$s" || { CO_TIPO=nao_resolve; return 0; }
  case "$s" in
    refs/heads/*)
      if git -C "$r" show-ref --verify --quiet "$s"; then CO_TIPO=branch; CO_BRANCH="${s#refs/heads/}"
      else CO_TIPO=nao_resolve; fi
      return 0 ;;
  esac
  if git -C "$r" show-ref --verify --quiet "refs/heads/$s"; then
    CO_TIPO=branch; CO_BRANCH="$s"; return 0
  fi
  if git -C "$r" rev-parse --verify -q "$s^{commit}" >/dev/null 2>&1; then
    CO_TIPO=commit; return 0       # SHA, tag, ref remota
  fi
  CO_TIPO=nao_resolve
}

# avalia_push — o segmento que expx_push_le acabou de ler
avalia_push() {
  local i tok r src dst dstn amplo=0 tags=0 apaga=0 primeiro atual head b
  ACAO="${ACAO:-push}"
  resolve_repo || { indeterminado "$REPO_ERRO"; return 0; }
  atual="$(git -C "$REPO" branch --show-current 2>/dev/null)"
  head="$(git -C "$REPO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
  primeiro="${#IT_RAIZ[@]}"

  i=0
  while [ "$i" -lt "${#EXPX_PUSH_OPCOES[@]}" ]; do
    case "${EXPX_PUSH_OPCOES[$i]}" in
      --all|--mirror|--branches) amplo=1 ;;
      --tags) tags=1 ;;
      --delete) apaga=1 ;;
      --*) ;;
      -*d*) apaga=1 ;;
    esac
    i=$((i + 1))
  done

  if [ "$amplo" = 1 ]; then
    # Todas as branches locais sobem: cada uma, não avaliável.
    while IFS= read -r b; do
      [ -n "$b" ] && item "$REPO" "$b" "$(ponta "$REPO" "$b")" "--all/--mirror empurram todas as branches"
    done <<EOF
$(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
EOF
    return 0
  fi

  if [ "${#EXPX_PUSH_REFSPECS[@]}" = 0 ]; then
    # Só `--tags`: empurra tags, não branch. Sem nada: a branch ativa.
    [ "$tags" = 1 ] && [ "$apaga" = 0 ] && return 0
    [ "$apaga" = 0 ] || { indeterminado "--delete sem refspec"; return 0; }
    [ -n "$atual" ] || { indeterminado "push sem refspec com HEAD destacado"; return 0; }
    item "$REPO" "$atual" "$head" ""
    return 0
  fi

  i=0
  while [ "$i" -lt "${#EXPX_PUSH_REFSPECS[@]}" ]; do
    tok="${EXPX_PUSH_REFSPECS[$i]}"; i=$((i + 1))
    r="${tok#+}"
    case "$r" in
      *:*) src="${r%%:*}"; dst="${r#*:}" ;;
      *)   src="$r"; dst="$r" ;;
    esac
    # Com --delete, cada refspec nomeia o ref remoto a apagar.
    [ "$apaga" = 0 ] || { src=""; dst="$r"; }
    dstn="${dst#refs/heads/}"
    case "$dstn" in HEAD|@) dstn="$atual" ;; esac
    if [ -z "$dstn" ] || ! nome_de_branch "$dstn"; then
      indeterminado "o destino do refspec '$tok' não se resolve"; continue
    fi
    classifica "$REPO" "$src"
    case "$CO_TIPO" in
      head)
        [ -n "$atual" ] || { indeterminado "refspec '$tok' com HEAD destacado"; continue; }
        item "$REPO" "$atual" "$head" ""
        [ "$dstn" = "$atual" ] || item "$REPO" "$dstn" "" "o refspec '$tok' publica outra origem nesta branch" ;;
      branch)
        item "$REPO" "$CO_BRANCH" "$(ponta "$REPO" "$CO_BRANCH")" ""
        [ "$dstn" = "$CO_BRANCH" ] || item "$REPO" "$dstn" "" "o refspec '$tok' publica outra origem nesta branch" ;;
      commit|vazia)
        item "$REPO" "$dstn" "" "o refspec '$tok' publica um commit ou uma remoção nesta branch" ;;
      *)
        indeterminado "a origem do refspec '$tok' não se resolve" ;;
    esac
  done
  if [ "$tags" = 1 ]; then
    i="$primeiro"
    while [ "$i" -lt "${#IT_RAIZ[@]}" ]; do
      [ -n "${IT_NA[$i]}" ] || IT_NA[$i]="--tags junto com a branch"
      i=$((i + 1))
    done
  fi
}

# avalia_pr <segmento> — `gh|glab ... pr|mr ... create`, com flags globais
# antes do subcomando (`gh -R o/r pr create`). 0 se era uma abertura de PR.
avalia_pr() {
  local t v achou=0 pr=0 cabeca="" proximo=""
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  for t in "$@"; do
    v="$(expx_sem_aspas "$t")"
    if [ -n "$proximo" ]; then cabeca="$v"; proximo=""; continue; fi
    if [ "$achou" = 0 ]; then
      case "${v##*/}" in gh|glab) achou=1 ;; esac
      continue
    fi
    case "$pr:$v" in
      0:pr|0:mr) pr=1; continue ;;
      1:create) pr=2; continue ;;
    esac
    if [ "$pr" = 2 ]; then
      case "$v" in
        -H|--head|-s|--source-branch) proximo=1 ;;
        --head=*|--source-branch=*) cabeca="${v#*=}" ;;
      esac
    fi
  done
  [ "$pr" = 2 ] || return 1
  ACAO="${ACAO:-abertura de pull request}"
  [ -n "$DIR_SEG" ] || { indeterminado "o diretório do comando depende de um cd que não se resolve"; return 0; }
  REPO="$(git -C "$DIR_SEG" rev-parse --show-toplevel 2>/dev/null)" \
    || { indeterminado "o repositório da abertura de PR não se resolve"; return 0; }
  RAIZES="$RAIZES$REPO
"
  if [ -n "$cabeca" ]; then
    { nome_de_branch "$cabeca" && git -C "$REPO" show-ref --verify --quiet "refs/heads/$cabeca"; } \
      || { indeterminado "branch do PR que não se resolve: $cabeca"; return 0; }
    item "$REPO" "$cabeca" "$(ponta "$REPO" "$cabeca")" ""
  else
    v="$(git -C "$REPO" branch --show-current 2>/dev/null)"
    [ -n "$v" ] || { indeterminado "abertura de PR com HEAD destacado"; return 0; }
    item "$REPO" "$v" "$(git -C "$REPO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" ""
  fi
  return 0
}

# parece_push <segmento> — um `git ... push` que a leitura por token não lê
# (lançador fora da lista de executores, `\git`, `/usr/bin/git`): uma palavra
# `git` seguida, depois das opções, de `push`. Citação (`echo`, `grep`...) e o
# próprio `git` como programa (a leitura por token já decidiu) não contam.
parece_push() {
  local t v w depois=0 pula=0 p
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  while [ "$#" -gt 0 ]; do
    case "$(expx_sem_aspas "$1")" in [_[:alpha:]]*=*) shift ;; *) break ;; esac
  done
  [ "$#" -gt 0 ] || return 1
  p="$(expx_sem_aspas "$1")"
  [ "$p" = git ] && return 1
  case "${p##*/}" in
    echo|printf|grep|egrep|fgrep|rg|ag|cat|sed|awk|man|less|more|head|tail|tee) return 1 ;;
  esac
  for t in "$@"; do
    v="$(expx_sem_aspas "$t")"
    if [ "$pula" = 1 ]; then pula=0; continue; fi
    w="${v#\\}"; w="${w##*/}"
    if [ "$depois" = 1 ]; then
      case "$v" in
        push) return 0 ;;
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path) pula=1; continue ;;
        -*) continue ;;
      esac
      depois=0
    fi
    [ "$w" = git ] && depois=1
  done
  return 1
}

# --------------------------------------------------------------------------
# Leitura do comando, segmento a segmento
# --------------------------------------------------------------------------
DIR_SEG="$DIR_INICIAL"
while IFS= read -r SEG; do
  [ -n "$SEG" ] || continue
  # `cd <dir>` literal muda o diretório dos segmentos seguintes; com expansão,
  # o diretório deixa de ser conhecido.
  set -f
  # shellcheck disable=SC2086
  set -- $SEG
  set +f
  while [ "$#" -gt 0 ]; do
    case "$(expx_sem_aspas "$1")" in
      cd|pushd)
        V="$(expx_sem_aspas "${2:-}")"
        if literal "$V" && [ "$V" != - ]; then
          DIR_SEG="$(absoluto "$DIR_SEG" "$V")" || DIR_SEG=""
        else
          DIR_SEG=""
        fi ;;
    esac
    shift
  done
  if expx_push_le "$SEG"; then
    avalia_push
  elif avalia_pr "$SEG"; then
    :
  elif parece_push "$SEG"; then
    ACAO="${ACAO:-push}"; indeterminado "um push que o hook não consegue ler: $SEG" # guarda:HKFALLBACK
  fi
done <<EOF
$(expx_segmentos "$CMD")
EOF

[ -n "$ACAO" ] || exit 0

# barra_sempre <motivo-curto> <mensagem> — exit 2 em qualquer modo
barra_sempre() {
  expx_barra bloqueio "$RAIZ" "$HOOK" "$1" "$2" # guarda:HKAVISO
}

msg_nao_avalia() { # <trabalho> <por quê>
  printf '%s' "mergex/pr-so-com-portao — push com refspec que o portão não sabe avaliar

Trabalho: $1
Comando:  $CMD
Por quê:  $2

O portão PRONTO vale para UMA revisão da branch do trabalho (portao_sha +
validade-do-portao.sh). Este comando publica algo que o hook não consegue
reduzir a essa revisão — então não há como provar que o que sobe foi avaliado
pelo E2. Barra em qualquer modo do hook.

O que fazer:
  - Empurre a branch do trabalho pelo nome, sem SHA, expressão nem variável,
    a partir do checkout dela:
      git push -u origin <branch-do-trabalho>
  - Ou acione /mergex-pr, que sobe a branch e abre o PR pelos artefatos."
}

# --------------------------------------------------------------------------
# Push indeterminado: barra onde há trabalho da mergex (algum
# docs/entregas/<id>/ENTREGA.md na árvore do HEAD dos repositórios tocados).
# --------------------------------------------------------------------------
if [ -n "$INDET" ]; then
  HA_TRABALHO=0
  while IFS= read -r R; do
    [ -n "$R" ] || continue
    if git -C "$R" -c core.quotepath=false ls-tree -r --name-only HEAD -- docs/entregas 2>/dev/null \
       | grep -Eq '^docs/entregas/[^/]+/ENTREGA\.md$'; then
      HA_TRABALHO=1; break
    fi
  done <<EOF
$RAIZES
$(git -C "$DIR_INICIAL" rev-parse --show-toplevel 2>/dev/null)
EOF
  if [ "$HA_TRABALHO" = 1 ]; then
    expx_barra bloqueio "$RAIZ" "$HOOK" "push nao avaliavel" "$(msg_nao_avalia indeterminado "$INDET")" # guarda:HKREFSPEC
  fi
fi

# --------------------------------------------------------------------------
# O trabalho de cada branch empurrada — pela árvore da revisão empurrada
# --------------------------------------------------------------------------
W_RAIZ=(); W_ID=(); W_REV=(); W_LER=(); W_NA=()
i=0
while [ "$i" -lt "${#IT_RAIZ[@]}" ]; do
  R="${IT_RAIZ[$i]}"; B="${IT_BRANCH[$i]}"; V="${IT_REV[$i]}"; NA="${IT_NA[$i]}"
  i=$((i + 1))
  # De onde se lê o ENTREGA: a revisão empurrada; sem ela (remoção, commit
  # solto), a ponta local da branch; sem branch local, o HEAD.
  L="$V"
  [ -n "$L" ] || L="$(ponta "$R" "$B")"
  [ -n "$L" ] || L="$(git -C "$R" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
  TID="$(expx_trabalho_por_branch_na_revisao "$R" "$B" "$L")"; RC=$? # guarda:HKREC
  case "$RC" in
    0) ;;
    1) continue ;;          # a branch não é de trabalho da mergex
    *) expx_barra bloqueio "$RAIZ" "$HOOK" "trabalho indeterminado ($B)" \
         "$(msg_nao_avalia "? (branch $B)" "mais de uma entrega da revisão $L declara a branch $B, ou a árvore não se lê")" ;;
  esac
  j=0; achou=""
  while [ "$j" -lt "${#W_RAIZ[@]}" ]; do
    if [ "${W_RAIZ[$j]}" = "$R" ] && [ "${W_ID[$j]}" = "$TID" ]; then achou="$j"; break; fi
    j=$((j + 1))
  done
  if [ -n "$achou" ]; then
    W_NA[$achou]="${NA:-mais de um refspec (ou push) envolve a branch do trabalho}"
  else
    j="${#W_RAIZ[@]}"
    W_RAIZ[$j]="$R"; W_ID[$j]="$TID"; W_REV[$j]="$V"; W_LER[$j]="$L"; W_NA[$j]="$NA"
  fi
done

# --------------------------------------------------------------------------
# O portão de cada trabalho afetado — de <revisão>:ENTREGA.md, nunca do disco
# --------------------------------------------------------------------------
MODO_TRAB=""; MODO_PORTAO=""
j=0
while [ "$j" -lt "${#W_RAIZ[@]}" ]; do
  R="${W_RAIZ[$j]}"; TRAB="${W_ID[$j]}"; REV="${W_REV[$j]}"; L="${W_LER[$j]}"; NA="${W_NA[$j]}"
  j=$((j + 1))
  ENTREGA_REL="docs/entregas/$TRAB/ENTREGA.md"
  PORTAO="$(git -C "$R" cat-file blob "$L:$ENTREGA_REL" 2>/dev/null | expx_frontmatter_valor /dev/stdin portao)"

  if [ "$PORTAO" != pronto ]; then
    [ -n "$MODO_TRAB" ] || { MODO_TRAB="$TRAB"; MODO_PORTAO="$PORTAO"; }
    continue
  fi

  [ -z "$NA" ] || expx_barra bloqueio "$RAIZ" "$HOOK" "push com refspec nao avaliavel ($TRAB)" "$(msg_nao_avalia "$TRAB" "$NA")" # guarda:HKREFSPEC

  if [ ! -f "$VALIDADE" ]; then
    barra_sempre "validade do portao ausente ($TRAB)" "mergex/pr-so-com-portao — validade do portão indisponível

Trabalho: $TRAB
Portão:   pronto

O portão registrou PRONTO, mas a prova de que ele vale para a revisão publicada
não pode ser calculada: scripts/validade-do-portao.sh não está ao lado dos
hooks (.claude/skills/mergex/scripts/validade-do-portao.sh). Sem prova, o
\`pronto\` não libera — em qualquer modo do hook.

O que fazer:
  - Reinstale a mergex completa (hooks e skill juntos) e tente de novo."
  fi

  SAIDA="$(cd "$R" 2>/dev/null && bash "$VALIDADE" --verificar --entrega "$ENTREGA_REL" --rev "$REV" 2>/dev/null)"
  RCV=$?
  OKV="$(printf '%s\n' "$SAIDA" | sed -n 's/^ok=//p' | head -1)"
  MOTIVO_V="$(printf '%s\n' "$SAIDA" | sed -n 's/^motivo=//p' | head -1)"
  PRIMEIRO="$(printf '%s\n' "$SAIDA" | sed -n 's/^primeiro_commit=//p' | head -1)"
  AVISOS="$(printf '%s\n' "$SAIDA" | sed -n 's/^aviso=/  - /p')"

  # Só ok=true COM rc 0 prova o portão.
  if [ "$RCV" = 0 ] && [ "$OKV" = true ]; then
    continue
  fi

  if [ "$RCV" != 1 ] || [ "$OKV" != false ] || [ -z "$MOTIVO_V" ] || [ "$MOTIVO_V" = erro_ambiente ]; then
    barra_sempre "validade do portao nao calculavel ($TRAB)" "mergex/pr-so-com-portao — a validade do portão não pôde ser calculada

Trabalho: $TRAB
Revisão:  ${REV:-indeterminada}
Saída:    rc=$RCV ${OKV:+ok=$OKV} ${MOTIVO_V:+motivo=$MOTIVO_V}
${AVISOS:+$AVISOS
}
O portão registrou PRONTO, mas validade-do-portao.sh não provou que ele vale
para a revisão publicada. Sem prova, o \`pronto\` não libera — em qualquer
modo do hook.

O que fazer:
  - Corrija o ambiente descrito acima e tente de novo.
  - Persistindo, rode o portão de novo:  /mergex-check"
  fi

  barra_sempre "portao vencido: $MOTIVO_V ($TRAB)" "mergex/pr-so-com-portao — portão vencido para a revisão publicada

Trabalho:        $TRAB
Revisão:         $REV
Motivo:          $MOTIVO_V
Primeiro commit: ${PRIMEIRO:--}
${AVISOS:+$AVISOS
}
O portão registrou PRONTO, mas ele não vale para esta revisão: depois do
commit que o E2 avaliou (portao_sha) entrou commit que o E2 não viu — produto,
teste, plano ou merge —, ou o portao_sha está ausente ou fora da história.
Publicar agora levaria ao revisor código que o portão não avaliou. Isto barra
em qualquer modo do hook.

O que fazer:
  - Rode o E2 de novo:  /mergex-check
  - PRONTO   → o push e o PR seguem normalmente.
  - BLOQUEADO → a saída nomeia o que falta e onde corrigir."
done

[ "$MODO" = "desligado" ] && exit 0
[ -n "$MODO_TRAB" ] || expx_permite "$RAIZ" "$HOOK" "$ACAO liberado"

case "$MODO_PORTAO" in
  bloqueado)
    DETALHE="O portão barrou este trabalho. Ele não segue para revisão enquanto o que
falta não for corrigido — a mergex não maquia entrega incompleta (regra 6)."
    ;;
  *)
    DETALHE="O campo 'portao' do ENTREGA.md da revisão publicada está
'${MODO_PORTAO:-null}': o E2 ainda não deu veredito sobre esta entrega."
    ;;
esac

expx_barra "$MODO" "$RAIZ" "$HOOK" "$ACAO sem portao pronto ($MODO_TRAB)" \
"mergex/pr-so-com-portao — $ACAO antes do portão de prontidão

Trabalho: $MODO_TRAB
Portão:   ${MODO_PORTAO:-não registrado}

$DETALHE

O portão roda as onze verificações (V1..V11): tasks concluídas, suíte verde,
dois testes por task, teste de regressão, QA, auditoria, bloqueios, modo legado,
arquivos fora do escopo, segredo no diff e commit do E1 por task concluída.

O que fazer:
  - Rode o portão:  /mergex-check
  - PRONTO   → o push e o PR seguem normalmente.
  - BLOQUEADO → a saída nomeia o que falta e onde corrigir."
