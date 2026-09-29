#!/usr/bin/env bash
# git-perigoso — PreToolUse em execução de comando.
#
# Barra as operações onde o erro não tem volta:
#   - push forçado, em qualquer forma
#   - push ou commit direto na branch principal
#   - reescrita de histórico já enviado
#   - descarte de alteração local
#   - limpeza destrutiva de arquivo não rastreado
#
# O falso positivo aqui é raro; o custo do falso negativo é o trabalho de
# outra pessoa perdido.
#
# Modo padrão: BLOQUEIO (hook de segurança, falha fechada).
#
# Regra 1 do desenho: casar com PRECISÃO. Uma regra frouxa que barre qualquer
# coisa contendo "push" atrapalha o dev o dia inteiro. Todo casamento aqui
# exige `git` como programa e a forma real da opção.
#
# Caminho e id com o namespace da skill (DM-171): `.claude/hooks/mergex/
# git-perigoso.sh`, modo em `.expx/hooks.json` sob `mergex/git-perigoso`. A
# sprintx publica um hook de mesmo nome, com regras próprias, em
# `.claude/hooks/sprintx/git-perigoso.sh` sob `sprintx/git-perigoso`: nenhum
# dos dois sobrescreve o outro, e o modo de um nunca desliga o outro. O id sem
# namespace (`git-perigoso`) não é lido: um "desligado" antigo não rebaixa
# este hook.

HOOK="mergex/git-perigoso"
PADRAO="bloqueio"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../comum/base.sh
. "$DIR/../comum/base.sh"

ENTRADA="$(cat)"

# jq é dependência declarada dos hooks (hooks/README.md): é ele que lê o
# payload. Sem jq, o `tool_name` sairia vazio e o hook devolveria sucesso sem
# ter avaliado nada — falha aberta silenciosa num hook de segurança (DM-171).
# Aqui não há parser alternativo: se o payload cru menciona `git`, a chamada
# é barrada por contrato de instalação; o resto segue, porque não é assunto
# deste hook. Sem jq, o modo em `.expx/hooks.json` também não pode ser lido —
# nem o "desligado".
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "$ENTRADA" | grep -Eq '(^|[^A-Za-z0-9_./\\-])git([[:space:]]|\\[nrt]|"|$)' || exit 0
  printf '%s\n' \
"mergex/git-perigoso — dependência ausente: jq

Este hook de segurança lê o comando pelo jq, e o jq não está no PATH. Sem ele
não há como provar que o comando git é seguro, então a chamada foi barrada em
vez de passar sem avaliação.

O que fazer:
  - Instale o jq (https://jqlang.org) e confira com: jq --version
  - Os hooks da mergex dependem de bash, jq, git e utilitários POSIX
    (.claude/hooks/README.md, \"Dependências\")." >&2
  exit 2
fi

[ "$(printf '%s' "$ENTRADA" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0

CMD="$(printf '%s' "$ENTRADA" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$CMD" ] || exit 0

# Saída antecipada: se não invoca git, este hook não tem assunto.
# É o que mantém o custo perto de zero na maioria esmagadora das chamadas.
#
# A aspa entra na lista de caracteres que podem vir ANTES do `git` porque
# `bash -c "git push"`, `sh -c '...'` e `eval "..."` embrulham o comando num
# argumento: a primeira letra do programa passa a encostar na aspa de abertura.
# Sem ela, esta linha saía com sucesso antes de qualquer regra rodar, e
# embrulhar o comando desligava o hook inteiro — não só o push. A saída sem jq
# (acima) sempre enxergou essa forma; era esta lista que estava mais estreita
# do que a de lá, e a diferença entre as duas era o bypass.
printf '%s' "$CMD" | grep -Eq '(^|[;&|`(){}'\''"[:space:]])git([[:space:]]|$)' || exit 0

CWD="$(printf '%s' "$ENTRADA" | jq -r '.cwd // empty' 2>/dev/null)"
RAIZ="$(expx_raiz "${CWD:-$PWD}")"

MODO="$(expx_modo "$HOOK" "$PADRAO" "$RAIZ")"
[ "$MODO" = "desligado" ] && exit 0

# Qual é a branch principal deste repositório: pergunta ao repositório,
# não adivinha. Sem estado próprio (regra 6 do contrato).
principal() {
  local p
  p="$(git -C "$RAIZ" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  p="${p#origin/}"
  if [ -z "$p" ]; then
    for c in main master; do
      if git -C "$RAIZ" show-ref --verify --quiet "refs/heads/$c"; then p="$c"; break; fi
    done
  fi
  printf '%s\n' "${p:-main}"
}

barra() { expx_barra "$MODO" "$RAIZ" "$HOOK" "$1" "$2"; }

# A principal e a branch ativa são lidas antes das regras porque a leitura do
# push (logo abaixo) já precisa das duas para resolver `HEAD` e reconhecer o
# destino.
PRINCIPAL="$(principal)"
ATUAL="$(git -C "$RAIZ" branch --show-current 2>/dev/null)"

# --------------------------------------------------------------------------
# 0. Leitura do push — o segmento normalizado, não a linha inteira
# --------------------------------------------------------------------------
# Regex sobre a linha inteira erra dos dois lados, e os dois erros são falha
# ABERTA num hook de segurança:
#
#   - "sem destino" virava uma FORMA de linha (opções, uma palavra solta, fim
#     do comando). Redirecionar a saída, encanar num tee ou escrever uma opção
#     DEPOIS do remoto desfazia a forma, e o push implícito em main passava;
#   - `git -C <path> push` e `git -c <k>=<v> push` deixavam de ser reconhecidos
#     como push, porque o VALOR da opção global entra numa palavra separada
#     entre `git` e `push`. Com isso saía a seção inteira — inclusive o forçado.
#
# Aqui o comando é quebrado nos separadores de segmento e cada segmento que
# começa em `git` e chega em `push` é lido POR TOKEN, como o próprio git lê:
# opções globais (algumas com valor separado), subcomando, opções do push
# (algumas com valor separado), remoto e refspecs.
#
# Não é um parser de shell: não expande variável, não resolve substituição de
# comando, não entende agrupamento e só tira um par de aspas das pontas do
# token. O que ele não classificar POSITIVAMENTE não é liberado — é barrado
# (PUSH_OBSCURO). Provar que o destino não é a principal é obrigação do hook.
#
# Todo segmento de push é lido, não só o primeiro: em `git push origin
# feature/x && git push origin main` o perigo está no segundo, e a regra
# anterior — que varria a linha inteira — já o enxergava. Ler só o primeiro
# devolveria essa cobertura para trás.

PUSH_VISTO=0        # o comando contém pelo menos um `git ... push`
PUSH_FORCA=0        # --force, -f (inclusive colado), --force-*, +refspec
PUSH_AMPLO=0        # --all, --mirror: alcança refs que o comando não nomeia
PUSH_PRINCIPAL=0    # algum destino nomeado É a principal
PUSH_SEM_DESTINO=0  # nenhum refspec: o destino é o upstream da branch ativa
PUSH_OBSCURO=0      # há destino, mas ele não foi classificado

# Uma aspa em cada ponta do token, no máximo, e só. O hook recebe a string como
# ela foi escrita: sem isto `origin "main"` não era a principal. As pontas são
# tratadas separadamente porque o par se abre e se fecha em tokens diferentes
# quando o comando inteiro está entre aspas (`bash -c "git push origin main"`
# dá os tokens `"git` e `main"`).
sem_aspas() {
  local v="$1"
  v="${v#[\"\']}"
  v="${v%[\"\']}"
  printf '%s' "$v"
}

# Destino de um refspec: o lado direito do `:` quando ele existe, o próprio
# refspec quando não existe. `HEAD` e `@` são a branch ativa.
destino_do_refspec() {
  local r
  r="$(sem_aspas "$1")"
  r="${r#+}"
  case "$r" in *:*) r="${r##*:}" ;; esac
  r="$(sem_aspas "$r")"
  r="${r#refs/heads/}"
  case "$r" in HEAD|@) r="$ATUAL" ;; esac
  printf '%s' "$r"
}

# Programas que RODAM o que vem no argumento. É esta lista que separa EXECUTAR
# de CITAR: `bash -c "git push origin main"` executa o push; `echo "git push
# origin main"` só imprime o texto. Sem a distinção, procurar o `git` em
# qualquer posição do segmento barrava toda citação — o aviso impresso, a
# mensagem de commit que fala de push, a busca por push no código. Falso
# positivo que atrapalha o dia inteiro é o que a regra 1 do desenho proíbe.
#
# Compara-se o NOME do programa, não o caminho: `/bin/sh` é o mesmo `sh`.
#
# Um lançador fora desta lista não é lido como execução de push. É uma troca
# consciente e declarada: o hook prefere não enxergar um push escondido em
# `find -exec` a barrar toda linha que apenas MENCIONA um push.
executor() {
  case "$1" in
    bash|sh|dash|zsh|ksh|ksh93|mksh|ash|busybox) return 0 ;;
    eval|command|exec|env|sudo|doas|nohup|setsid|nice|time|timeout|stdbuf|xargs) return 0 ;;
  esac
  return 1
}

# O número que ABRE um redirecionamento sobra no fim do segmento depois da
# quebra: `git push origin main 2>/tmp/log` vira o segmento `git push origin
# main 2`. Ele é descritor porque é uma palavra INTEIRA, só de dígitos. O
# dígito colado no fim de outra palavra pertence à palavra: `git push origin
# main2>/tmp/log` empurra para `main2`, que é outra branch. Cortar o dígito
# grudado transformava `main2` na principal `main` — barrava um push legítimo —
# e comia o fim de qualquer destino terminado em número.
sem_descritor() {
  local v="$1" t
  t="${v##*[[:space:]]}"
  case "$t" in
    ''|*[!0-9]*) printf '%s' "$v" ;;
    *)           printf '%s' "${v%"$t"}" ;;
  esac
}

# Lê um segmento. Devolve 0 se ele era mesmo um `git ... push`.
le_push() {
  local tok d seg remoto_lido=0 n_refspec=0 atribuiu=0
  seg="$(sem_descritor "$1")"
  set -f                    # o segmento é texto: nada aqui vira glob
  # shellcheck disable=SC2086
  set -- $seg
  set +f

  # Prefixo de ambiente: `GIT_DIR=/tmp/x git push ...` continua sendo um push.
  # Valor com espaço (`GIT_SSH_COMMAND="ssh -v" git push`) chega partido em
  # vários tokens, então, depois da primeira atribuição, os pedaços soltos
  # também são pulados até o nome do programa.
  while [ "$#" -gt 0 ]; do
    case "$(sem_aspas "$1")" in
      [_[:alpha:]]*=*) atribuiu=1 ;;
      -*)              [ "$atribuiu" = 1 ] || break ;;
      *)               break ;;
    esac
    shift
  done
  [ "$#" -gt 0 ] || return 1

  # O `git` não é necessariamente a primeira palavra do segmento: `bash -c
  # "git push origin main"`, `sh -c ...` e `eval ...` o colocam dentro de um
  # argumento, e ele continua sendo o programa que vai rodar. Mas só quem RODA
  # o argumento pode esconder um push ali dentro — em `echo "git push origin
  # main"` a mesma palavra é só texto. Por isso o `git` é procurado adiante
  # apenas quando o programa do segmento é um executor.
  tok="$(sem_aspas "$1")"
  if [ "$tok" != git ]; then
    executor "${tok##*/}" || return 1
    while [ "$#" -gt 0 ]; do
      [ "$(sem_aspas "$1")" = git ] && break
      shift
    done
    [ "$#" -gt 0 ] || return 1
  fi
  shift

  # Opções globais do git, antes do subcomando. As desta lista levam o valor
  # numa palavra separada (`git -C <path> push`, `git -c <k>=<v> push`); as
  # demais (inclusive a forma `--git-dir=<path>`) ocupam uma palavra só.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--attr-source|--config-env)
        [ "$#" -ge 2 ] || return 1
        shift 2 ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "$(sem_aspas "${1:-}")" = push ] || return 1
  shift
  PUSH_VISTO=1

  # A aspa sai do token ANTES de qualquer comparação, e não só do remoto e do
  # refspec: quando o comando vem embrulhado, a aspa de fechamento cola na
  # última palavra, e ela costuma ser uma opção (`bash -c "git push --all"` dá
  # `--all"`). Comparar o token cru deixava `--all"`, `--mirror"` e `--force"`
  # de fora do reconhecimento — fora da principal, onde a branch ativa não
  # segura nada, o push passava inteiro.
  while [ "$#" -gt 0 ]; do
    tok="$(sem_aspas "$1")"; shift
    case "$tok" in
      --force|--force-*) PUSH_FORCA=1; continue ;;
      --all|--mirror)    PUSH_AMPLO=1; continue ;;
      # Opções do push cujo valor vem na palavra seguinte.
      --repo|--receive-pack|--exec|--push-option|-o) shift; continue ;;
      --*) continue ;;
      -*) # Aglomerado curto: `-fu` é tão forçado quanto `-f`.
          case "$tok" in *f*) PUSH_FORCA=1 ;; esac
          case "$tok" in *o)  shift ;; esac
          continue ;;
    esac

    # Primeiro posicional é o remoto; os seguintes são refspecs.
    if [ "$remoto_lido" = 0 ]; then
      remoto_lido=1
      [ "$tok" = "$PRINCIPAL" ] && PUSH_PRINCIPAL=1
      continue
    fi
    n_refspec=$((n_refspec + 1))
    case "$tok" in +*) PUSH_FORCA=1 ;; esac
    d="$(destino_do_refspec "$tok")"
    if [ "$d" = "$PRINCIPAL" ]; then
      PUSH_PRINCIPAL=1
    elif ! printf '%s' "$d" | grep -Eq '^[A-Za-z0-9@][A-Za-z0-9._/@-]*$'; then
      PUSH_OBSCURO=1
    fi
  done

  [ "$n_refspec" = 0 ] && PUSH_SEM_DESTINO=1
  return 0
}

# A continuação de linha é emendada ANTES da quebra em segmentos, porque para o
# shell ela não separa nada: barra invertida no fim da linha faz as duas linhas
# virarem UMA, e só depois é que se decide o que é programa e o que é argumento.
# Um push com a barra no fim e `origin main` na linha seguinte é um push com
# destino nomeado. Sem emendar, a segunda linha caía fora do segmento e o
# destino escrito nela deixava de ser lido: fora da principal, onde a branch
# ativa não segura nada, o push para a principal passava — e a regra anterior,
# que varria a linha inteira, já o barrava.
#
# Emenda-se SÓ o par barra-invertida+quebra. A quebra de linha solta continua
# separando comandos, porque é isso que ela faz no shell: juntar tudo faria a
# palavra de um comando virar argumento do push do comando vizinho.
#
# E a barra que continua a linha é a que NÃO está escapada. Barras andam em
# pares: `\\` é UMA barra literal, e a quebra depois dela segue sendo fim de
# comando — o push escrito na linha seguinte é um push por si e tem de ser
# lido. Apagar todo par barra+quebra sem contar a corrida de barras fundia dois
# comandos que o shell mantém separados: a palavra da linha de cima colava no
# `git` da linha de baixo, o segmento deixava de começar em `git` e o push
# sumia — falha ABERTA do mesmo tamanho da que a emenda veio consertar. Quem
# decide é a paridade: ímpar emenda, par separa.
#
# A emenda serve à LEITURA do push. As mensagens seguem mostrando o comando
# como ele foi escrito ($CMD).
emenda_continuacao() {
  local linha saida='' barras
  while IFS= read -r linha; do
    barras="${linha##*[!\\]}"          # a corrida de barras no fim da linha
    if [ $(( ${#barras} % 2 )) = 1 ]; then
      saida="$saida${linha%?}"         # ímpar: a última barra continua a linha
    else
      saida="$saida$linha"$'\n'        # par: a quebra continua separando
    fi
  done <<<"$1"
  printf '%s' "$saida"
}

# Sem continuação, não há o que emendar — e a esmagadora maioria dos comandos
# não tem. A pergunta é de expansão de parâmetro, sem processo nenhum.
case "$CMD" in
  *\\$'\n'*) CMD_PUSH="$(emenda_continuacao "$CMD")" ;;
  *)         CMD_PUSH="$CMD" ;;
esac

if printf '%s' "$CMD_PUSH" | grep -Fq push; then
  # Separadores de segmento: `&&`, `||`, `;`, `|`, `&`, subshell, crase e
  # redirecionamento. O que vem depois deles é outro comando, ou não é
  # argumento do push. Cada separador vira uma quebra de linha e o laço lê um
  # segmento por linha — a quebra que já estava no comando continua separando,
  # porque é o que ela faz no shell. `&&` e `||` viram duas quebras, e o
  # segmento vazio do meio não incomoda ninguém.
  #
  # A troca é do `tr`, não do `sed`: `s/X/\n/` com QUEBRA DE LINHA no lado
  # direito é extensão GNU, e o contrato deste repositório é bash 3.2 mais
  # utilitários POSIX (macOS incluído). No sed do BSD aquele `\n` é a letra
  # `n`: os segmentos saíam grudados numa linha só, `git status; git push
  # origin main` virava `git statusngit push origin main`, o push deixava de
  # ser reconhecido — e o hook falhava ABERTO justamente na cadeia que ele
  # existe para barrar. Em `tr`, `\n` é quebra de linha em qualquer Unix, e a
  # troca é byte a byte: um conjunto de destino do mesmo tamanho do de origem,
  # sem depender do preenchimento automático que o POSIX não garante.
  while IFS= read -r SEG; do
    case "$SEG" in *push*) le_push "$SEG" || true ;; esac
  done <<<"$(printf '%s\n' "$CMD_PUSH" | tr ';|&()`<>' '\n\n\n\n\n\n\n\n')"
fi

# --------------------------------------------------------------------------
# 1. Push forçado — em qualquer forma
# --------------------------------------------------------------------------
# --force, -f, --force-with-lease, --force-if-includes e o +refspec.
if [ "$PUSH_FORCA" = 1 ]; then
  barra "push forcado" \
"mergex/git-perigoso — push forçado

Comando: $CMD

Push forçado reescreve o que já está no remoto. O commit de outra pessoa que
estiver naquela branch desaparece do histórico, e ela só descobre no próximo
pull — quando já perdeu o trabalho.

Isto é bloqueado em qualquer forma: --force, -f, --force-with-lease e +refspec.

O que fazer:
  - Divergiu da base? Rebaseie ou faça merge da base na sua branch e empurre
    normalmente.
  - Precisa desfazer algo já enviado? Faça um commit que reverte (git revert).
    O histórico cresce, mas ninguém perde nada.
  - É mesmo necessário reescrever? É decisão humana, fora da mergex."
fi

# --------------------------------------------------------------------------
# 2. Push ou commit direto na branch principal
# --------------------------------------------------------------------------
# commit: barra quando a branch ativa É a principal
if printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  if [ -n "$ATUAL" ] && [ "$ATUAL" = "$PRINCIPAL" ]; then
    barra "commit na branch principal" \
"mergex/git-perigoso — commit direto na branch principal

Branch ativa: $ATUAL (a principal deste repositório)

O trabalho da mergex nasce numa branch própria (E0), antes da primeira linha
de código. Commit direto na principal pula a revisão inteira: não há PR, não
há classificação de atenção humana, não há portão.

O que fazer:
  - Crie a branch do trabalho e commite nela:
      git switch -c <tipo>/<trabalho_id>-<slug>
  - Ou acione /mergex-abrir, que faz isso registrando a branch no ENTREGA.md."
  fi
fi

# push para a principal — três perguntas, e nenhuma cobre a outra:
#
#   a) o push alcança refs que ele NÃO nomeia? `--all` e `--mirror` empurram a
#      principal junto, de qualquer branch. Barra sempre. (Refspec com curinga
#      cai em (d): o hook não consegue dizer o que ele alcança.)
#
#   b) o comando NOMEIA a principal como destino? Então barra, qualquer que
#      seja a branch ativa. O destino é o lado direito do `:` quando ele
#      existe (`HEAD:main`, `:main`, `feature/x:main`, `:refs/heads/main`) e o
#      próprio refspec quando não existe — o `+` do forçado e um par de aspas
#      saem antes da comparação.
#
#   c) o comando NÃO nomeia destino nenhum (`git push`, `git push origin`,
#      `git push origin --all`, `git -C <path> push`)? Então o destino é o
#      upstream da branch ativa, e só nesse caso "estou na principal" é motivo
#      suficiente. `HEAD` e `@` não caem aqui: são destino nomeado, e (b) os
#      resolve para a branch ativa.
#
#   d) o destino existe mas é ILEGÍVEL (variável, substituição de comando,
#      curinga)? Barra: o hook não provou que ele não é a principal.
#
# Aplicar (c) a qualquer push era o falso positivo: barrava `git push origin
# feature/x`, `git push origin --delete feature/x` e `git push origin
# :refs/heads/feature/x` estando em main — destinos que não tocam a principal
# e são exatamente o trabalho legítimo de quem nunca saiu dela.
#
# "Sem destino" é a AUSÊNCIA de refspec no segmento lido, não uma forma de
# linha: redirecionamento, cano e opção depois do remoto não transformam um
# push implícito em push com destino.
if [ "$PUSH_VISTO" = 1 ] && [ "$PUSH_AMPLO" = 1 ]; then
  barra "push de alcance amplo" \
"mergex/git-perigoso — push que alcança refs não nomeadas

Comando: $CMD

--all e --mirror não empurram só o que o comando escreve: empurram o conjunto
de refs do repositório, e a principal ($PRINCIPAL) está nele. --mirror ainda
apaga no remoto o que não existe aqui.

Estar fora da principal não muda isso — o alcance é do comando, não da branch.

O que fazer:
  - Empurre o que você quer empurrar, pelo nome:
      git push -u origin <sua-branch>
  - Espelhar ou empurrar tudo é decisão humana, fora da mergex."
fi

if [ "$PUSH_VISTO" = 1 ]; then
  if [ "$PUSH_PRINCIPAL" = 1 ] \
  || { [ -n "$ATUAL" ] && [ "$ATUAL" = "$PRINCIPAL" ] && [ "$PUSH_SEM_DESTINO" = 1 ]; }; then
    barra "push na branch principal" \
"mergex/git-perigoso — push direto na branch principal

Alvo: $PRINCIPAL

Código entra na principal por pull request revisado, não por push direto.
Integrar é decisão humana (regra 16 da mergex).

O que fazer:
  - Empurre a branch do trabalho e abra o PR:
      git push -u origin <sua-branch>
  - Ou acione /mergex-pr, que sobe a branch e abre o PR pelos artefatos."
  fi
fi

# Destino ilegível: variável, substituição de comando, aspas aninhadas. O hook
# vê o texto, não o valor que o shell vai produzir — não há como provar que o
# destino não é a principal, e o que não se prova não passa (falha fechada).
if [ "$PUSH_VISTO" = 1 ] && [ "$PUSH_OBSCURO" = 1 ]; then
  barra "destino de push nao classificado" \
"mergex/git-perigoso — destino de push que o hook não consegue ler

Comando: $CMD

O destino deste push só existe depois que o shell expande a linha: variável,
substituição de comando ou aspas dentro do token. O hook lê o texto, então não
tem como provar que o alvo não é a principal ($PRINCIPAL) — e um hook de
segurança não libera o que não provou.

O que fazer:
  - Escreva o destino por extenso:
      git push -u origin <sua-branch>
  - Ou acione /mergex-pr, que sobe a branch e abre o PR pelos artefatos."
fi

# --------------------------------------------------------------------------
# 3. Reescrita de histórico já enviado
# --------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(rebase|filter-branch|filter-repo)([[:space:]]|$)' \
|| printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit[^|;&]*[[:space:]]--amend([[:space:]]|$)' \
|| printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+reset[^|;&]*[[:space:]]--hard([[:space:]]|$)'; then
  # Só é perigoso se o que seria reescrito já foi enviado ao remoto.
  # Sem upstream, é histórico local: não barra (precisão, regra 1).
  UP="$(git -C "$RAIZ" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  if [ -n "$UP" ]; then
    JA_ENVIADO="$(git -C "$RAIZ" rev-list --count "$UP..HEAD" 2>/dev/null || echo 0)"
    # HEAD == upstream => todo commit local já está no remoto: reescrever mexe
    # no que os outros já têm.
    if [ "${JA_ENVIADO:-0}" = "0" ]; then
      barra "reescrita de historico ja enviado" \
"mergex/git-perigoso — reescrita de histórico já enviado

Comando: $CMD
Branch:  ${ATUAL:-?} (acompanha $UP)

Todos os commits desta branch já estão no remoto. Reescrevê-los troca os
identificadores do que outras pessoas já baixaram — e a reconciliação delas
vira conflito ou perda.

O que fazer:
  - Desfazer algo já enviado: git revert <commit> (novo commit, nada some).
  - Ajustar só o que ainda é local: confira com
      git log --oneline $UP..HEAD
    Se estiver vazio, não há nada local para ajustar.
  - Reescrever mesmo assim é decisão humana, fora da mergex."
    fi
  fi
fi

# --------------------------------------------------------------------------
# 4. Descarte de alteração local
# --------------------------------------------------------------------------
# git checkout -- <path> / git restore <path> / git stash drop|clear
DESCARTA=0
if printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+checkout[^|;&]*[[:space:]]--([[:space:]]|$)'; then
  DESCARTA=1
elif printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+rest''ore([[:space:]]|$)'; then
  # Só desfazer o stage nao toca a arvore de trabalho e nao destroi nada.
  # Barrar isso seria o falso positivo que atrapalha o dia inteiro.
  if printf '%s' "$CMD" | grep -Eq '[[:space:]]--worktree([[:space:]]|=|$)'; then
    DESCARTA=1
  elif printf '%s' "$CMD" | grep -Eq '[[:space:]]--staged([[:space:]]|=|$)'; then
    DESCARTA=0
  else
    DESCARTA=1
  fi
elif printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+stash[[:space:]]+(drop|clear)([[:space:]]|$)'; then
  DESCARTA=1
fi
if [ "$DESCARTA" = "1" ]; then
  SUJO="$(git -C "$RAIZ" status --porcelain 2>/dev/null | head -20)"
  if [ -n "$SUJO" ]; then
    barra "descarte de alteracao local" \
"mergex/git-perigoso — descarte de alteração local

Comando: $CMD

Há alteração não commitada na árvore. Este comando a joga fora, e o
versionador não guarda cópia do que nunca foi commitado — não há como voltar.

A alteração pode não ser sua: pode ser trabalho de quem estava na máquina.

Pendente agora:
$SUJO

O que fazer:
  - Guardar antes de descartar:  git stash push -m 'antes de descartar'
  - Ver o que exatamente se perde: git diff
  - Descartar mesmo assim é decisão humana, fora da mergex."
  fi
fi

# --------------------------------------------------------------------------
# 5. Limpeza destrutiva de arquivo não rastreado
# --------------------------------------------------------------------------
if printf '%s' "$CMD" | grep -Eq 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+clean([[:space:]]|$)'; then
  if printf '%s' "$CMD" | grep -Eq '[[:space:]]-[a-zA-Z]*[fdx]'; then
    ALVOS="$(git -C "$RAIZ" clean -nd 2>/dev/null | head -20)"
    barra "limpeza destrutiva" \
"mergex/git-perigoso — limpeza destrutiva de arquivos não rastreados

Comando: $CMD

git clean apaga arquivo que o versionador nunca viu. Não há histórico, não há
stash, não há recuperação. Arquivo de ambiente, dado local e trabalho ainda
não commitado de outra pessoa somem juntos.

Seria removido:
${ALVOS:-  (não foi possível pré-visualizar)}

O que fazer:
  - Veja antes, sempre:  git clean -nd
  - Remova só o que você conhece, pelo caminho, com rm.
  - Limpar em bloco é decisão humana, fora da mergex."
  fi
fi

expx_permite "$RAIZ" "$HOOK" "comando git sem operacao destrutiva"
