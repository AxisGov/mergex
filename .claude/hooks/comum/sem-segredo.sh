#!/usr/bin/env bash
# sem-segredo — PreToolUse em execução de comando e em escrita.
#
# Roda antes de cada commit, não só no portão final. Segredo que entra no
# histórico não sai por reverter o commit.
#
# Compartilhado por todas as skills; é na mergex que ele fecha a porta que
# importa, porque é a skill que commita.
#
# Modo padrão: BLOQUEIO (hook de segurança, falha fechada).

HOOK="sem-segredo"
PADRAO="bloqueio"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=base.sh
. "$DIR/base.sh"

ENTRADA="$(cat)"
FERRAMENTA="$(printf '%s' "$ENTRADA" | jq -r '.tool_name // empty' 2>/dev/null)"
CWD="$(printf '%s' "$ENTRADA" | jq -r '.cwd // empty' 2>/dev/null)"
RAIZ="$(expx_raiz "${CWD:-$PWD}")"

MODO="$(expx_modo "$HOOK" "$PADRAO" "$RAIZ")"
[ "$MODO" = "desligado" ] && exit 0

# --------------------------------------------------------------------------
# O que este hook inspeciona
# --------------------------------------------------------------------------
# Bash: só o que vai virar histórico — commit. O resto do terminal não é
#       assunto deste hook (regra 1: casar com precisão).
# Write/Edit: o conteúdo que está sendo escrito no arquivo.
ALVO=""
ORIGEM=""

case "$FERRAMENTA" in
  Bash)
    CMD="$(printf '%s' "$ENTRADA" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    [ -n "$CMD" ] || exit 0
    # Só interessa commit. `git commit -m "..."` carrega a mensagem, e o que
    # está em preparação é o que vai para o histórico.
    # Sem `-q`, de propósito: base.sh liga `pipefail`, e um grep que casa na
    # primeira linha e sai dá SIGPIPE ao printf quando o comando passa do buffer
    # do pipe; o pipeline devolvia 141 e este `|| exit 0` pulava a varredura de
    # `git commit -m x` seguido de 70 KB de linhas — com chave privada em
    # preparação (rodada extra da revisão). Sem `-q` o grep lê até o fim.
    printf '%s' "$CMD" | grep -E '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' >/dev/null || exit 0
    # A varredura é sobre o que ENTRA no histórico: as linhas adicionadas do que
    # está preparado. A removida (tirar um segredo é a remediação) e o contexto
    # do diff não são conteúdo novo. Só dentro de um bloco `@@` uma linha com `+`
    # é conteúdo — fora dele, `+++ b/<arquivo>` é cabeçalho, e uma linha
    # adicionada que começa com `++ ` também chega como `+++ `. O `+` inicial
    # sai, para os limites à esquerda valerem.
    # O índice não basta: `-a`, `-i`, `-o` e pathspec levam ao commit o que só
    # está na árvore de trabalho, e reconhecer cada forma do comando seria
    # frágil. As alterações não preparadas dos arquivos rastreados entram sempre:
    # na dúvida, o hook barra (um segredo não preparado de outro arquivo também).
    # --no-ext-diff e --no-textconv: um diff.external, GIT_EXTERNAL_DIFF ou textconv
    # configurado trocaria o texto do diff (com /bin/true, por nada) e o segredo
    # passaria sem ser visto (conselhos#210, P7). --text: arquivo binário ou com
    # atributo -diff sairia como "Binary files differ", sem bloco @@ (login#30).
    ALVO="$( { git -C "$RAIZ" diff --cached --text --no-ext-diff --no-textconv --no-color -U0
               git -C "$RAIZ" diff --text --no-ext-diff --no-textconv --no-color -U0; } 2>/dev/null \
      | awk '/^diff --git / { h = 0; next } /^@@/ { h = 1; next } h && /^\+/ { print substr($0, 2) }')"
    # Some a mensagem inline, que também vai para o histórico.
    ALVO="$ALVO
$CMD"
    # E a mensagem por arquivo (`-F <arq>`, `-F<arq>`, `--file <arq>`,
    # `--file=<arq>`, `-F` ao fim de opções curtas sem argumento, como `-aF`),
    # todas as ocorrências (conselhos#210, P4). O caminho é relativo ao cwd do
    # evento. `-F -` (stdin), arquivo ilegível ou forma que não se resolve: na
    # dúvida, barra — a mensagem iria para o histórico sem ser vista.
    MSG_NAO_VARRIDA=""
    while IFS= read -r arg_f; do
      [ -n "$arg_f" ] || continue
      arq_f="${arg_f#--file=}"; arq_f="${arq_f#--file}"
      case "$arq_f" in -*F*) arq_f="${arq_f#*F}" ;; esac
      arq_f="${arq_f#"${arq_f%%[![:space:]]*}"}"
      case "$arq_f" in \"*\") arq_f="${arq_f#\"}"; arq_f="${arq_f%\"}" ;; \'*\') arq_f="${arq_f#\'}"; arq_f="${arq_f%\'}" ;; esac
      case "$arq_f" in ''|-) MSG_NAO_VARRIDA="${MSG_NAO_VARRIDA}  - ${arg_f}
"; continue ;; esac
      case "$arq_f" in /*) ;; *) arq_f="${CWD:-$PWD}/$arq_f" ;; esac
      if [ -f "$arq_f" ] && [ -r "$arq_f" ]; then
        ALVO="$ALVO
$(cat -- "$arq_f" 2>/dev/null)"
      else
        MSG_NAO_VARRIDA="${MSG_NAO_VARRIDA}  - ${arg_f}
"
      fi
    done <<EXPX_ARQ_F
$(printf '%s' "$CMD" | grep -aEo -e "(^|[[:space:]])(--file(=|[[:space:]]+)|-[aeinopqsvz]*F[[:space:]]*)(\"[^\"]*\"|'[^']*'|[^[:space:];&|]+)" | sed 's/^[[:space:]]*//')
EXPX_ARQ_F
    # Não rastreado que o MESMO comando adiciona (`git add novo.env && git commit`)
    # não está em diff nenhum quando este hook roda (login#30). Com `add` e `commit`
    # no comando, os não rastreados e não ignorados entram na varredura, todos (o
    # pathspec do add não é interpretado: na dúvida, varre). Link não é seguido (o
    # commit leva o alvo, não o conteúdo). Acima de 1 MiB por arquivo, ou de 8 MiB
    # somados, barra: o que não se lê não passa. Sem `add`, não rastreado não entra.
    if printf '%s' "$CMD" | grep -E '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+add([[:space:]]|$)' >/dev/null; then
      total_nr=0
      while IFS= read -r -d '' nr; do
        caminho_nr="$RAIZ/$nr"
        [ -L "$caminho_nr" ] && continue
        [ -f "$caminho_nr" ] || continue
        tam_nr="$(wc -c < "$caminho_nr" 2>/dev/null | tr -d ' ')"
        case "$tam_nr" in ''|*[!0-9]*) MSG_NAO_VARRIDA="${MSG_NAO_VARRIDA}  - não rastreado ilegível: ${nr}
"; continue ;; esac
        total_nr=$((total_nr + tam_nr))
        if [ "$tam_nr" -gt 1048576 ] || [ "$total_nr" -gt 8388608 ]; then
          MSG_NAO_VARRIDA="${MSG_NAO_VARRIDA}  - não rastreado grande demais para varrer: ${nr}
"; continue
        fi
        ALVO="$ALVO
$(cat -- "$caminho_nr" 2>/dev/null | tr -d '\000')"
      done < <(git -C "$RAIZ" ls-files -o --exclude-standard -z 2>/dev/null)
    fi
    if [ -n "$MSG_NAO_VARRIDA" ]; then
      expx_barra "$MODO" "$RAIZ" "$HOOK" "conteúdo do commit não varrido" \
"mergex/sem-segredo — parte do que entra no commit não pôde ser varrida

${MSG_NAO_VARRIDA}
A mensagem vem de stdin (\`-F -\`) ou de um arquivo que não se lê a partir
do diretório do comando, ou um arquivo não rastreado que o mesmo comando
adiciona é grande demais para varrer. Isso iria para o histórico sem passar
pela varredura.

O que fazer: grave a mensagem num arquivo legível e passe o caminho em -F, ou
use -m; adicione o arquivo grande num comando separado, depois de conferido."
    fi
    ORIGEM="o que está em preparação ou alterado nos arquivos rastreados"
    ;;
  Write|Edit|NotebookEdit)
    ALVO="$(printf '%s' "$ENTRADA" | jq -r '
      [.tool_input.content?, .tool_input.new_string?, .tool_input.new_source?]
      | map(select(. != null)) | join("\n")' 2>/dev/null)"
    [ -n "$ALVO" ] || exit 0
    ORIGEM="o conteúdo sendo escrito"
    ;;
  *) exit 0 ;;
esac

[ -n "$ALVO" ] || exit 0

# --------------------------------------------------------------------------
# Os sinais — a tabela única, em skills/mergex/scripts/segredo-tabela.sh
# --------------------------------------------------------------------------
# A mesma do pre-push (portao-push.sh, DM-279). Sem ela, o hook de segurança
# barra: falha fechada.
TABELA="$DIR/../../skills/mergex/scripts/segredo-tabela.sh"
# shellcheck source=../../skills/mergex/scripts/segredo-tabela.sh
if [ ! -r "$TABELA" ] || ! . "$TABELA" || ! command -v segredo_varrer >/dev/null 2>&1; then
  expx_barra "$MODO" "$RAIZ" "$HOOK" "tabela de segredo indisponível" \
"mergex/sem-segredo — a tabela de sinais de segredo não está disponível

Esperada em: $TABELA

Sem ela, nada do que $ORIGEM traz pode ser varrido. Reinstale a mergex
(o hook e a skill vêm juntos) antes de continuar."
fi
segredo_varrer


if [ -n "$ACHADOS" ]; then
  expx_barra "$MODO" "$RAIZ" "$HOOK" "segredo em $ORIGEM" \
"mergex/sem-segredo — segredo encontrado em $ORIGEM

$ACHADOS
Segredo que entra no histórico não sai por reverter o commit.

O que fazer:
  1. Tire o valor do arquivo e ponha em variável de ambiente ou cofre.
  2. Deixe no código só a referência (ex.: process.env.API_KEY).
  3. Se o valor é fictício, torne isso óbvio (xxxx, <coloque-aqui>, example).
  4. Se já foi commitado antes, rotacione a credencial — reverter não basta.

Valores acima estão mascarados de propósito."
fi

expx_permite "$RAIZ" "$HOOK" "sem segredo em $ORIGEM"
