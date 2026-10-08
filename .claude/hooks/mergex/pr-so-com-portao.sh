#!/usr/bin/env bash
# pr-so-com-portao — PreToolUse em execução de comando.
#
# Barra o push e a abertura de pull request quando o portão de prontidão não
# registrou PRONTO, ou quando um PRONTO registrado não vale mais.
#
# O portão (E2) barra e explica; sem ele, o trabalho incompleto chega ao
# revisor — que é exatamente o recurso caro que a skill existe para poupar.
#
# DECIDE PELO ESTADO DO REPOSITÓRIO, NÃO PELA LEITURA DO COMANDO. Ler o shell
# por texto nunca cobre tudo (xargs, função, config de push, subshell,
# plumbing). Por isso:
#
#   1. Gatilho largo: o comando contém, como palavra, um termo de publicação
#      (`push`, `send-pack`, `subtree`, ou `pr`/`mr` seguido de `create`/`new`),
#      em qualquer posição — dentro de aspas, função, xargs ou subshell.
#   2. Varredura: no repositório do cwd e em cada diretório literal citado no
#      comando que seja outro repositório (`cd X`, `-C X`, `env -C X`,
#      `--git-dir=X`, `--work-tree=X`, `GIT_DIR=X`), para CADA branch local, o
#      `docs/entregas/<id>/ENTREGA.md` da ponta dela que declara essa branch e
#      registra `portao: pronto` tem de valer:
#      `validade-do-portao.sh --verificar --entrega <ENTREGA> --rev <ponta>`.
#      Vencido, ausente ou que não se calcula: exit 2 em QUALQUER modo,
#      `desligado` inclusive (spec 2026-10-07-reconciliacao-base-pos-e8, §4.5 e
#      §13.5) — qualquer que seja o comando com termo de publicação.
#   3. Refinamento: a leitura por token do push (comum/base.sh) só decide o
#      caso `null`/`bloqueado`, que segue o modo configurado quando o comando
#      empurra a branch daquele trabalho, e dá contexto à mensagem.
#
# É uma barreira de AGENTE, não de segurança contra adversário. A garantia
# forte é rodar validade-do-portao.sh no CI ou num hook `pre-push` (README).

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

# --------------------------------------------------------------------------
# 1. Gatilho largo — termo de publicação como palavra, em qualquer lugar
# --------------------------------------------------------------------------
P_='(^|[^A-Za-z0-9_-])'; _S='([^A-Za-z0-9_-]|$)'
tem_termo() {
  printf '%s' "$CMD" | grep -Eq "${P_}(push|send-pack|subtree)${_S}" && return 0
  printf '%s' "$CMD" | grep -Eq "${P_}(pr|mr)[^A-Za-z0-9_-](.*[^A-Za-z0-9_-])?(create|new)${_S}"
}
tem_termo || exit 0 # guarda:HKGATILHO

CWD="$(printf '%s' "$ENTRADA" | jq -r '.cwd // empty' 2>/dev/null)"
DIR_INICIAL="${CWD:-$PWD}"
RAIZ="$(expx_raiz "$DIR_INICIAL")"
MODO="$(expx_modo "$HOOK" "$PADRAO" "$RAIZ")"

# Valor literal: sem expansão, glob nem aspas internas. O hook lê o texto.
literal() {
  case "$1" in
    ''|-|*'$'*|*'`'*|*'~'*|*'*'*|*'?'*|*'['*|*'"'*|*"'"*|*'\'*) return 1 ;;
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
TAB="$(printf '\t')"
ponta() { git -C "$1" rev-parse --verify -q "refs/heads/$2^{commit}" 2>/dev/null; }

# --------------------------------------------------------------------------
# 2. Varredura do estado — o cwd e os diretórios literais do comando
# --------------------------------------------------------------------------
# Diretórios candidatos: o cwd e todo valor literal de `cd`, `pushd`, `-C`,
# `--chdir`, `--git-dir`, `--work-tree`, `GIT_DIR=`, `GIT_WORK_TREE=` e
# `GIT_COMMON_DIR=`, em qualquer segmento. Um candidato que não é repositório
# Git é ignorado; um valor com expansão não se lê (risco residual, README).
CANDIDATOS="$DIR_INICIAL
"
candidato() {
  local v
  literal "$1" || return 0
  v="$(absoluto "$DIR_INICIAL" "$1")" || return 0
  CANDIDATOS="$CANDIDATOS$v
"
}
while IFS= read -r SEG; do
  [ -n "$SEG" ] || continue
  set -f
  # shellcheck disable=SC2086
  set -- $SEG
  set +f
  while [ "$#" -gt 0 ]; do
    T="$(expx_sem_aspas "$1")"
    case "$T" in
      cd|pushd|-C|--chdir|--git-dir|--work-tree) candidato "$(expx_sem_aspas "${2:-}")" ;; # guarda:HKOUTROS
      --chdir=*|--git-dir=*|--work-tree=*|GIT_DIR=*|GIT_WORK_TREE=*|GIT_COMMON_DIR=*) candidato "${T#*=}" ;; # guarda:HKOUTROS
    esac
    shift
  done
done <<EOF
$(expx_segmentos "$CMD")
EOF

VISTOS=""       # git-common-dir de cada repositório já varrido
FALHAS=""       # uma linha por portão pronto que não vale
REPOS=""        # raízes varridas (para o refinamento)

# varre <raiz> — para cada branch local, o ENTREGA.md pronto da ponta dela
varre() {
  local top="$1" refs objs pronto cand obj path br id saida rc okv mot pri
  refs="$(git -C "$top" for-each-ref --format='%(objectname) %(refname:short)' refs/heads 2>/dev/null)" # guarda:HKVARRE
  [ -n "$refs" ] || return 0
  objs="$(printf '%s\n' "$refs" | cut -d' ' -f1 | sort -u)"
  # Um `git grep` só, sobre as pontas: `branch:` e `portao:` de cada
  # docs/entregas/<id>/ENTREGA.md (a primeira ocorrência de cada chave vale).
  # shellcheck disable=SC2086
  pronto="$(git -C "$top" -c core.quotepath=false grep --no-color -I -E '^(branch|portao):' $objs \
      -- 'docs/entregas/*/ENTREGA.md' 2>/dev/null | awk '
    {
      l = $0; i = index(l, ":"); o = substr(l, 1, i - 1); l = substr(l, i + 1)
      i = index(l, ":"); p = substr(l, 1, i - 1); l = substr(l, i + 1)
      if (p !~ /^docs\/entregas\/[^\/]+\/ENTREGA\.md$/) next
      gsub(/\r/, "", l)
      k = l; sub(/:.*/, "", k)
      v = l; sub(/^[^:]*:[ \t]*/, "", v); gsub(/^["\047]|["\047]$/, "", v); sub(/[ \t]+$/, "", v)
      c = o SUBSEP p; vistos[c] = 1
      if (k == "branch" && !(c in B)) B[c] = v
      if (k == "portao" && !(c in P)) P[c] = v
    }
    END { for (c in vistos) if (P[c] == "pronto") { split(c, a, SUBSEP); print a[1] "\t" a[2] "\t" B[c] } }')"
  [ -n "$pronto" ] || return 0
  # Só vale o ENTREGA que declara a própria branch em que está (a entrega de
  # um trabalho integrado à main não é o portão da main).
  cand="$(printf '%s\n%s\n' "$refs" "---" "$pronto" | awk '
    $0 == "---" { fase = 1; next }
    !fase { n = index($0, " "); R[substr($0, 1, n - 1) SUBSEP substr($0, n + 1)] = 1; next }
    { split($0, a, "\t"); if ((a[1] SUBSEP a[3]) in R) print a[1] "\t" a[2] "\t" a[3] }')"
  while IFS="$TAB" read -r obj path br; do
    [ -n "$obj" ] || continue
    id="${path#docs/entregas/}"; id="${id%/ENTREGA.md}"
    if [ ! -f "$VALIDADE" ]; then
      FALHAS="${FALHAS}  - branch $br (trabalho $id): validade-do-portao.sh ausente ao lado dos hooks
"
      continue
    fi
    saida="$(cd "$top" 2>/dev/null && bash "$VALIDADE" --verificar --entrega "$path" --rev "$obj" 2>/dev/null)"; rc=$? # guarda:HKREV
    okv="$(printf '%s\n' "$saida" | sed -n 's/^ok=//p' | head -1)"
    mot="$(printf '%s\n' "$saida" | sed -n 's/^motivo=//p' | head -1)"
    pri="$(printf '%s\n' "$saida" | sed -n 's/^primeiro_commit=//p' | head -1)"
    # Só ok=true COM rc 0 prova o portão.
    [ "$rc" = 0 ] && [ "$okv" = true ] && continue
    if [ "$rc" != 1 ] || [ "$okv" != false ] || [ -z "$mot" ] || [ "$mot" = erro_ambiente ]; then
      FALHAS="${FALHAS}  - branch $br (trabalho $id): validade-do-portao.sh não se calcula (rc=$rc${mot:+, motivo=$mot})
"
    else
      FALHAS="${FALHAS}  - branch $br (trabalho $id, ponta $obj): motivo=$mot, primeiro_commit=${pri:--}
"
    fi
  done <<EOF
$cand
EOF
}

while IFS= read -r D; do
  [ -n "$D" ] || continue
  TOP="$(git -C "$D" rev-parse --show-toplevel 2>/dev/null)" \
    || TOP="$(git -C "$(dirname "$D")" rev-parse --show-toplevel 2>/dev/null)" || continue
  [ -n "$TOP" ] || continue
  GCD="$(cd "$TOP" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || continue
  case "$VISTOS" in *"|$GCD|"*) continue ;; esac
  VISTOS="$VISTOS|$GCD|"
  REPOS="$REPOS$TOP
"
  varre "$TOP"
done <<EOF
$CANDIDATOS
EOF

# barra_sempre <motivo-curto> <mensagem> — exit 2 em qualquer modo
barra_sempre() {
  expx_barra bloqueio "$RAIZ" "$HOOK" "$1" "$2" # guarda:HKAVISO
}

if [ -n "$FALHAS" ]; then
  barra_sempre "portao pronto que nao vale" "mergex/pr-so-com-portao — portão vencido no repositório

Comando: $CMD

O comando tem um termo de publicação (push, send-pack, subtree, pr/mr
create|new), e há portão PRONTO que não vale para a ponta da branch:

$FALHAS
Depois do commit que o E2 avaliou (portao_sha) entrou commit que o E2 não viu
— produto, teste, plano ou merge —, ou o portao_sha está ausente ou fora da
história, ou a prova não pôde ser calculada. Publicar agora levaria ao revisor
código que o portão não avaliou.

Enquanto houver portão vencido, qualquer comando com termo de publicação é
barrado — inclusive citações como \`git log --grep push\` ou \`echo push\` —, em
qualquer modo do hook: o hook decide pelo estado do repositório, não pela
leitura do comando.

O que fazer:
  - Rode o E2 de novo na branch acima:  /mergex-check
  - PRONTO   → o push e o PR seguem normalmente.
  - BLOQUEADO → a saída nomeia o que falta e onde corrigir."
fi

[ "$MODO" = "desligado" ] && exit 0

# --------------------------------------------------------------------------
# 3. Refinamento — `null`/`bloqueado` da branch que o comando empurra
# --------------------------------------------------------------------------
# A leitura por token (comum/base.sh) identifica as branches empurradas; o
# trabalho de cada uma sai da árvore da revisão empurrada; o `portao`, de
# <revisão>:ENTREGA.md. `pronto` já foi decidido pela varredura.
IT_RAIZ=(); IT_BRANCH=(); IT_REV=()
ACAO=""
item() { # <raiz> <branch> <rev|"">
  local n="${#IT_RAIZ[@]}"
  IT_RAIZ[$n]="$1"; IT_BRANCH[$n]="$2"; IT_REV[$n]="$3"
}

REPO=""
resolve_repo() {
  local d="$DIR_SEG" i t v n
  local args=()
  REPO=""
  [ -n "$d" ] && [ "$EXPX_PUSH_AMBIENTE_GIT" = 0 ] || return 1
  n="${#EXPX_PUSH_GLOBAIS[@]}"; i=0
  while [ "$i" -lt "$n" ]; do
    t="${EXPX_PUSH_GLOBAIS[$i]}"; i=$((i + 1))
    case "$t" in
      -C|--git-dir|--work-tree)
        v="${EXPX_PUSH_GLOBAIS[$i]:-}"; i=$((i + 1))
        literal "$v" || return 1
        v="$(absoluto "$d" "$v")" || return 1
        if [ "$t" = -C ]; then d="$v"; else args[${#args[@]}]="$t=$v"; fi ;;
      --git-dir=*|--work-tree=*)
        v="${t#*=}"; literal "$v" || return 1
        v="$(absoluto "$d" "$v")" || return 1
        args[${#args[@]}]="${t%%=*}=$v" ;;
      -c|--namespace|--exec-path|--super-prefix|--attr-source|--config-env) i=$((i + 1)) ;;
    esac
  done
  REPO="$(git -C "$d" ${args[@]+"${args[@]}"} rev-parse --show-toplevel 2>/dev/null)" || { REPO=""; return 1; }
}

avalia_push() {
  local i tok r src dst dstn amplo=0 tags=0 apaga=0 atual head b
  ACAO="${ACAO:-push}"
  resolve_repo || return 0
  atual="$(git -C "$REPO" branch --show-current 2>/dev/null)"
  head="$(git -C "$REPO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
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
  [ "$apaga" = 0 ] || return 0          # remoção não publica código
  if [ "$amplo" = 1 ]; then
    while IFS= read -r b; do
      [ -n "$b" ] && item "$REPO" "$b" "$(ponta "$REPO" "$b")"
    done <<EOF
$(git -C "$REPO" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
EOF
    return 0
  fi
  if [ "${#EXPX_PUSH_REFSPECS[@]}" = 0 ]; then
    [ "$tags" = 1 ] && return 0
    [ -n "$atual" ] && item "$REPO" "$atual" "$head"
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
    dstn="${dst#refs/heads/}"
    case "$dstn" in HEAD|@) dstn="$atual" ;; esac
    case "$src" in
      HEAD|@) [ -n "$atual" ] && item "$REPO" "$atual" "$head" ;;
      *)
        src="${src#refs/heads/}"
        if nome_de_branch "$src" && git -C "$REPO" show-ref --verify --quiet "refs/heads/$src"; then
          item "$REPO" "$src" "$(ponta "$REPO" "$src")"
        fi ;;
    esac
    # o destino também é publicado: a branch dele, se for de um trabalho
    if [ -n "$dstn" ] && nome_de_branch "$dstn"; then item "$REPO" "$dstn" ""; fi
  done
}

# avalia_pr <segmento> — `gh|glab ... pr|mr ... create|new` (com flags antes
# do subcomando, `gh -R o/r pr create`). 0 se era uma abertura de PR.
avalia_pr() {
  local t v achou=0 pr=0 cabeca="" proximo="" programa=1
  set -f
  # shellcheck disable=SC2086
  set -- $1
  set +f
  for t in "$@"; do
    v="$(expx_sem_aspas "$t")"
    if [ -n "$proximo" ]; then cabeca="$v"; proximo=""; continue; fi
    if [ "$achou" = 0 ]; then
      # `gh`/`glab` como PROGRAMA (primeira palavra, ou depois de um executor
      # como `command`/`env`), não citado (`grep 'gh pr create'`).
      case "$v" in [_[:alpha:]]*=*) continue ;; esac
      if [ "$programa" = 1 ]; then
        case "${v##*/}" in
          gh|glab) achou=1 ;;
          *) expx_executor "${v##*/}" || programa=0 ;;
        esac
      fi
      continue
    fi
    case "$pr:$v" in
      0:pr|0:mr) pr=1; continue ;;
      1:create|1:new) pr=2; continue ;;
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
  [ -n "$DIR_SEG" ] || return 0
  REPO="$(git -C "$DIR_SEG" rev-parse --show-toplevel 2>/dev/null)" || return 0
  if [ -n "$cabeca" ]; then
    nome_de_branch "$cabeca" && item "$REPO" "$cabeca" "$(ponta "$REPO" "$cabeca")"
  else
    v="$(git -C "$REPO" branch --show-current 2>/dev/null)"
    [ -n "$v" ] && item "$REPO" "$v" "$(git -C "$REPO" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"
  fi
  return 0
}

DIR_SEG="$DIR_INICIAL"
while IFS= read -r SEG; do
  [ -n "$SEG" ] || continue
  # `cd` literal muda o diretório dos segmentos seguintes; com expansão, o
  # diretório deixa de ser conhecido. (Só refina a mensagem e o caso
  # null/bloqueado: o `pronto` vencido já foi decidido pela varredura.)
  set -f
  # shellcheck disable=SC2086
  set -- $SEG
  set +f
  while [ "$#" -gt 0 ]; do
    case "$(expx_sem_aspas "$1")" in
      cd|pushd)
        V="$(expx_sem_aspas "${2:-}")"
        if literal "$V"; then DIR_SEG="$(absoluto "$DIR_SEG" "$V")" || DIR_SEG=""; else DIR_SEG=""; fi ;;
    esac
    shift
  done
  if expx_push_le "$SEG"; then
    avalia_push
  else
    avalia_pr "$SEG" || true
  fi
done <<EOF
$(expx_segmentos "$CMD")
EOF

MODO_TRAB=""; MODO_PORTAO=""
i=0
while [ "$i" -lt "${#IT_RAIZ[@]}" ]; do
  R="${IT_RAIZ[$i]}"; B="${IT_BRANCH[$i]}"; V="${IT_REV[$i]}"
  i=$((i + 1))
  L="$V"
  [ -n "$L" ] || L="$(ponta "$R" "$B")"
  [ -n "$L" ] || continue
  TID="$(expx_trabalho_por_branch_na_revisao "$R" "$B" "$L")" || continue # guarda:HKREC
  PORTAO="$(git -C "$R" cat-file blob "$L:docs/entregas/$TID/ENTREGA.md" 2>/dev/null | expx_frontmatter_valor /dev/stdin portao)"
  [ "$PORTAO" = pronto ] && continue
  MODO_TRAB="$TID"; MODO_PORTAO="$PORTAO"
  break
done

[ -n "$MODO_TRAB" ] || expx_permite "$RAIZ" "$HOOK" "${ACAO:-comando} liberado"

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
