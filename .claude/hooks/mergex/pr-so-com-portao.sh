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
# portão `pronto` que não vale para a revisão publicada (validade-do-portao.sh
# ok=false, script ausente ou com erro de ambiente, ou refspec que o hook não
# sabe avaliar) barra com exit 2 em QUALQUER modo, inclusive `desligado`
# (spec 2026-10-07-reconciliacao-base-pos-e8, §4.5 e §13.5). Deixada passar,
# ela publicaria código que o portão não avaliou. `null` e `bloqueado` seguem
# o modo configurado, como sempre.

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

# Dois gatilhos: push da branch, e abertura de PR pela ferramenta do serviço.
ACAO=""
if printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)'; then
  ACAO="push"
elif printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])(gh|glab)[[:space:]]+(pr|mr)[[:space:]]+create([[:space:]]|$)'; then
  ACAO="abertura de pull request"
fi
[ -n "$ACAO" ] || exit 0

CWD="$(printf '%s' "$ENTRADA" | jq -r '.cwd // empty' 2>/dev/null)"
RAIZ="$(expx_raiz "${CWD:-$PWD}")"

MODO="$(expx_modo "$HOOK" "$PADRAO" "$RAIZ")"

# --------------------------------------------------------------------------
# Qual trabalho — pela branch ativa, nunca pelo ENTREGA.md mais recente
# --------------------------------------------------------------------------
# O mesmo resolvedor dos outros hooks: branch corrente casada com o `branch:`
# de EXATAMENTE UM docs/entregas/*/ENTREGA.md. Recência não prova nada: numa
# árvore que acumula entregas, o ENTREGA tocado por último pode ser de outro
# trabalho. Sem trabalho determinado, não há trabalho da mergex em curso nesta
# branch: não é assunto deste hook (precisão, regra 1).
TRAB="$(expx_trabalho_atual_por_branch "$RAIZ")" || exit 0 # guarda:HKREC
ENTREGA_REL="docs/entregas/$TRAB/ENTREGA.md"
ENTREGA="$RAIZ/$ENTREGA_REL"
BRANCH="$(git -C "$RAIZ" branch --show-current 2>/dev/null)"
HEAD_SHA="$(git -C "$RAIZ" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)"

# --------------------------------------------------------------------------
# Qual revisão o comando publica
# --------------------------------------------------------------------------
# A validade é do commit EMPURRADO, não do HEAD por suposição. A leitura do push
# é a do git-perigoso (comum/base.sh, expx_push_le); aqui se classifica a
# ORIGEM de cada refspec:
#
#   - sem refspec (`git push`, `git push origin`): a branch ativa => HEAD;
#   - origem `HEAD`, `@`, `<branch>` ou `refs/heads/<branch>` da branch do
#     trabalho (o destino não importa): a ponta dela;
#   - origem em outra branch local ou numa tag, com destino fora da branch do
#     trabalho: o push NÃO envolve a branch do trabalho;
#   - NÃO AVALIÁVEL (com `pronto`, barra em qualquer modo): origem em SHA
#     explícito, expressão (`HEAD~1`), ref remota ou nome que não se resolve;
#     outra branch, tag ou remoção (`:dst`, `--delete`) com destino na branch
#     do trabalho; `--all`/`--mirror`/`--branches`; `--tags` junto com a branch
#     do trabalho; mais de um refspec (ou mais de um push) envolvendo a branch
#     do trabalho.
#
# Push que não envolve a branch do trabalho (ex.: `git push origin main` com a
# feature ativa, `git push --tags`) mantém o comportamento de antes: `pronto`
# registrado libera; `null`/`bloqueado` seguem o modo. A abertura de PR publica
# a branch ativa: HEAD.
REV=""          # SHA da revisão publicada da branch do trabalho
ENVOLVE=0       # quantos refspecs/pushes envolvem a branch do trabalho
NAO_AVALIA=""   # por que o portão não sabe avaliar este push

# classifica_origem <origem> — trabalho | outra | vazia | nao_avalia
classifica_origem() {
  local s="$1"
  case "$s" in
    '') printf 'vazia'; return 0 ;;
    HEAD|@) printf 'trabalho'; return 0 ;;
  esac
  if [ -n "$BRANCH" ] && { [ "$s" = "$BRANCH" ] || [ "$s" = "refs/heads/$BRANCH" ]; }; then
    printf 'trabalho'; return 0
  fi
  printf '%s' "$s" | grep -Eq '^[A-Za-z0-9@][A-Za-z0-9._/@-]*$' || { printf 'nao_avalia'; return 0; }
  case "$s" in
    refs/heads/*|refs/tags/*)
      git -C "$RAIZ" show-ref --verify --quiet "$s" && printf 'outra' || printf 'nao_avalia' ;;
    refs/*) printf 'nao_avalia' ;;
    *)
      if git -C "$RAIZ" show-ref --verify --quiet "refs/heads/$s" \
      || git -C "$RAIZ" show-ref --verify --quiet "refs/tags/$s"; then
        printf 'outra'
      else
        printf 'nao_avalia'
      fi ;;
  esac
}

ponta_da_branch() {
  git -C "$RAIZ" rev-parse --verify -q "refs/heads/$BRANCH^{commit}" 2>/dev/null
}

# avalia_push — o segmento que expx_push_le acabou de ler
avalia_push() {
  local i tok r src dst dstn amplo=0 tags=0 apaga=0 env_seg=0
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
    ENVOLVE=$((ENVOLVE + 1))
    NAO_AVALIA="--all/--mirror empurram todas as branches, inclusive a do trabalho"
    return 0
  fi
  if [ "${#EXPX_PUSH_REFSPECS[@]}" = 0 ]; then
    # Só `--tags`: empurra tags, não a branch. Sem nada: a branch ativa.
    [ "$tags" = 1 ] && [ "$apaga" = 0 ] && return 0
    ENVOLVE=$((ENVOLVE + 1))
    REV="$HEAD_SHA"
    [ "$apaga" = 0 ] || NAO_AVALIA="--delete sem refspec"
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
    case "$dstn" in HEAD|@) dstn="$BRANCH" ;; esac
    case "$(classifica_origem "$src")" in
      trabalho)
        env_seg=$((env_seg + 1))
        case "$src" in HEAD|@) REV="$HEAD_SHA" ;; *) REV="$(ponta_da_branch)" ;; esac ;;
      outra|vazia)
        if [ -n "$BRANCH" ] && [ "$dstn" = "$BRANCH" ]; then
          env_seg=$((env_seg + 1))
          NAO_AVALIA="o refspec '$tok' publica outra origem (ou uma remoção) na branch do trabalho"
        fi ;;
      *)
        env_seg=$((env_seg + 1))
        NAO_AVALIA="a origem do refspec '$tok' não é a branch do trabalho nem uma branch ou tag local" ;;
    esac
  done
  if [ "$tags" = 1 ] && [ "$env_seg" -gt 0 ]; then
    NAO_AVALIA="--tags junto com a branch do trabalho"
  fi
  ENVOLVE=$((ENVOLVE + env_seg))
}

if [ "$ACAO" = push ]; then
  LIDO=0
  while IFS= read -r SEG; do
    expx_push_le "$SEG" || continue
    LIDO=1
    avalia_push
  done <<<"$(expx_push_segmentos "$CMD")"
  # O gatilho viu um push que a leitura por token não reconhece (lançador fora
  # da lista de executores, por exemplo): vale como o push da branch ativa.
  [ "$LIDO" = 1 ] || { ENVOLVE=1; REV="$HEAD_SHA"; }
  if [ "$ENVOLVE" -gt 1 ]; then
    NAO_AVALIA="mais de um refspec (ou push) envolve a branch do trabalho"
  fi
else
  ENVOLVE=1
  REV="$HEAD_SHA"
fi

# --------------------------------------------------------------------------
# O portão registrou PRONTO?
# --------------------------------------------------------------------------
# O ENTREGA.md do disco é a fonte primária do estado (como sempre): um
# `bloqueado` ou `null` recém-gravado pelo E2 vale. Sem campo no disco, vale o
# do ENTREGA commitado na revisão publicada. Um `pronto` — de onde vier — só
# libera com a prova de validade-do-portao.sh sobre a revisão publicada.
LEITURA="${REV:-$HEAD_SHA}"
PORTAO="$(expx_frontmatter_valor "$ENTREGA" portao)"
if [ -z "$PORTAO" ] && [ -n "$LEITURA" ]; then
  PORTAO="$(git -C "$RAIZ" cat-file blob "$LEITURA:$ENTREGA_REL" 2>/dev/null | expx_frontmatter_valor /dev/stdin portao)"
fi

# barra_sempre <motivo-curto> <mensagem> — exit 2 em qualquer modo
barra_sempre() {
  expx_barra bloqueio "$RAIZ" "$HOOK" "$1" "$2" # guarda:HKAVISO
}

if [ "$PORTAO" = pronto ] && [ "$ENVOLVE" -gt 0 ]; then
  if [ -n "$NAO_AVALIA" ]; then
    MSG="mergex/pr-so-com-portao — push com refspec que o portão não sabe avaliar

Trabalho: $TRAB (branch $BRANCH)
Comando:  $CMD
Por quê:  $NAO_AVALIA

O portão registrou PRONTO para uma revisão da branch do trabalho, e só vale
para ela (portao_sha + validade-do-portao.sh). Este push publica algo que o
hook não consegue reduzir a UMA revisão dessa branch — então não há como provar
que o que sobe foi avaliado pelo E2. Barra em qualquer modo do hook.

O que fazer:
  - Empurre a branch do trabalho pelo nome, sem SHA nem expressão:
      git push -u origin $BRANCH
  - Ou acione /mergex-pr, que sobe a branch e abre o PR pelos artefatos."
    expx_barra bloqueio "$RAIZ" "$HOOK" "push com refspec nao avaliavel ($TRAB)" "$MSG" # guarda:HKREFSPEC
  fi

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

  SAIDA="$(cd "$RAIZ" 2>/dev/null && bash "$VALIDADE" --verificar --entrega "$ENTREGA_REL" --rev "$REV" 2>/dev/null)"
  RC=$?
  OKV="$(printf '%s\n' "$SAIDA" | sed -n 's/^ok=//p' | head -1)"
  MOTIVO_V="$(printf '%s\n' "$SAIDA" | sed -n 's/^motivo=//p' | head -1)"
  PRIMEIRO="$(printf '%s\n' "$SAIDA" | sed -n 's/^primeiro_commit=//p' | head -1)"
  AVISOS="$(printf '%s\n' "$SAIDA" | sed -n 's/^aviso=/  - /p')"

  if [ "$RC" = 0 ] && [ "$OKV" = true ]; then
    expx_permite "$RAIZ" "$HOOK" "portao pronto e valido para $REV: $ACAO liberado"
  fi

  if [ "$RC" != 1 ] || [ "$OKV" != false ] || [ -z "$MOTIVO_V" ] || [ "$MOTIVO_V" = erro_ambiente ]; then
    barra_sempre "validade do portao nao calculavel ($TRAB)" "mergex/pr-so-com-portao — a validade do portão não pôde ser calculada

Trabalho: $TRAB
Revisão:  ${REV:-indeterminada}
Saída:    rc=$RC ${MOTIVO_V:+motivo=$MOTIVO_V}
${AVISOS:+$AVISOS
}
O portão registrou PRONTO, mas validade-do-portao.sh não conseguiu provar que
ele vale para a revisão publicada. Sem prova, o \`pronto\` não libera — em
qualquer modo do hook.

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
fi

[ "$MODO" = "desligado" ] && exit 0

case "$PORTAO" in
  pronto)
    expx_permite "$RAIZ" "$HOOK" "portao pronto: $ACAO liberado (nao envolve a branch do trabalho)"
    ;;
  bloqueado)
    MOTIVO="o portão de prontidão registrou BLOQUEADO"
    DETALHE="O portão barrou este trabalho. Ele não segue para revisão enquanto o que
falta não for corrigido — a mergex não maquia entrega incompleta (regra 6)."
    ;;
  *)
    MOTIVO="o portão de prontidão ainda não rodou"
    DETALHE="O campo 'portao' do ENTREGA.md está '${PORTAO:-null}': o E2 ainda não deu
veredito sobre esta entrega."
    ;;
esac

expx_barra "$MODO" "$RAIZ" "$HOOK" "$ACAO sem portao pronto ($TRAB)" \
"mergex/pr-so-com-portao — $ACAO antes do portão de prontidão

Trabalho: $TRAB
Portão:   ${PORTAO:-não registrado}

$DETALHE

O portão roda as onze verificações (V1..V11): tasks concluídas, suíte verde,
dois testes por task, teste de regressão, QA, auditoria, bloqueios, modo legado,
arquivos fora do escopo, segredo no diff e commit do E1 por task concluída.

O que fazer:
  - Rode o portão:  /mergex-check
  - PRONTO   → o push e o PR seguem normalmente.
  - BLOQUEADO → a saída nomeia o que falta e onde corrigir."
