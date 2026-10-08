#!/usr/bin/env bash
# Biblioteca comum dos hooks da mergex.
#
# Contrato: expx-eventos v1. Regras que este arquivo materializa:
#   - rápido (sem rede, sem interpretador pesado, saída antecipada)
#   - silencioso quando passa
#   - falha aberta no método, fechada na segurança
#   - sem estado próprio: toda decisão sai de arquivo já existente
#   - sempre grava no rastro, inclusive quando permite

set -uo pipefail   # sem -e: hook de método não pode morrer no meio e travar o terminal

# --------------------------------------------------------------------------
# Raiz do projeto
# --------------------------------------------------------------------------
# O harness entrega o diretório de trabalho no evento; o fallback é o cwd.
#
# Quem responde primeiro é o próprio versionador: `rev-parse --show-toplevel`
# acerta em checkout normal, em `git worktree` e em qualquer subdiretório dos
# dois. É a fonte de verdade, e não custa rede.
#
# O fallback (sem git no PATH, ou fora de repositório) sobe procurando `.git`
# com `[ -e ]`, não `[ -d ]`: num worktree, `.git` é ARQUIVO (contém
# "gitdir: <principal>/.git/worktrees/<nome>"). Com `[ -d ]`, a busca pulava a
# raiz do worktree e continuava subindo — de um subdiretório dele, isso
# devolvia o subdiretório errado. Mesmo achado que a sprintx registrou na
# DS-106 do repositório dela.
expx_raiz() {
  local dir="${1:-$PWD}"
  local topo
  topo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || topo=""
  if [ -n "$topo" ]; then printf '%s\n' "$topo"; return 0; fi
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -e "$dir/.git" ]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "${1:-$PWD}"
}

# --------------------------------------------------------------------------
# Modo do hook — .expx/hooks.json
# --------------------------------------------------------------------------
# aviso | bloqueio | desligado
# Arquivo ausente ou ilegível => o padrão que o chamador declara.
# Segurança nunca é rebaixada por ausência de arquivo: só o "desligado"
# explícito desliga.
expx_modo() {
  local nome="$1" padrao="$2" raiz="$3"
  local arq="$raiz/.expx/hooks.json"
  [ -r "$arq" ] || { printf '%s\n' "$padrao"; return 0; }
  local m
  # Formato do ecossistema: {"expx_hooks":1,"hooks":{"<nome>":{"modo":"aviso"}}}
  # A forma antiga (.modos["<nome>"]) continua aceita para não quebrar quem já
  # tinha escrito o arquivo à mão.
  m="$(jq -r --arg n "$nome" '.hooks[$n].modo // .modos[$n] // empty' "$arq" 2>/dev/null)" || m=""
  case "$m" in
    aviso|bloqueio|desligado) printf '%s\n' "$m" ;;
    *) printf '%s\n' "$padrao" ;;
  esac
}

# --------------------------------------------------------------------------
# Rastro — docs/eventos/<trabalho_id>.jsonl
# --------------------------------------------------------------------------
# Uma linha JSON por evento, append-only. Chave nunca omitida: use null.
# Rotação acima de 5 MB, como manda o contrato.
expx_trabalho_id() {
  local raiz="$1"
  # O trabalho corrente é o ENTREGA.md mais recentemente modificado.
  # Sem estado próprio: a informação já está no artefato da entrega.
  local mais_novo
  mais_novo="$(ls -t "$raiz"/docs/entregas/*/ENTREGA.md 2>/dev/null | head -1)" || true
  if [ -n "${mais_novo:-}" ]; then
    basename "$(dirname "$mais_novo")"
  else
    printf 'sem-trabalho\n'
  fi
}

# --------------------------------------------------------------------------
# Trabalho CORRENTE — pela branch ativa
# --------------------------------------------------------------------------
# Diferente de expx_trabalho_id (acima), que escolhe o ENTREGA.md mais recente
# e existe para dar destino ao rastro. Recência não prova nada sobre qual é o
# trabalho de agora: numa árvore que acumula entregas — docs/entregas/ft-01,
# ft-02, ft-03 no mesmo checkout —, o arquivo tocado por último pode ser de uma
# feature encerrada semanas atrás.
#
# Aqui a pergunta é outra, e a resposta precisa ser determinística: qual
# trabalho pertence à ÁRVORE em que este comando está rodando. A única fonte
# que sabe isso é o versionador, casado com o que a própria entrega declarou.
#
# Regra, sem exceção:
#   1. branch corrente (`git branch --show-current`); vazia ou HEAD destacado
#      => não determinado;
#   2. dos `docs/entregas/*/ENTREGA.md`, considera só os que declaram
#      `branch: <branch corrente>` no frontmatter;
#   3. trabalho existe SOMENTE com EXATAMENTE UM match;
#   4. zero, dois ou mais, arquivo ilegível ou qualquer dúvida => não
#      determinado, e quem chama trata isso de forma conservadora.
#
# Nunca por mtime, nunca pelo ENTREGA mais recente, nunca por estado.json,
# nunca pela pasta da sprintx mais recente, nunca por heurística de slug.
#
# Devolve o <trabalho_id> na saída padrão e 0; ou nada e 1.
expx_frontmatter_valor() {
  # <arquivo> <chave> — valor da chave no frontmatter YAML de topo, ou vazio.
  [ -r "$1" ] || return 0
  awk -v chave="$2" '
    NR == 1 { if ($0 !~ /^---[[:space:]]*\r?$/) exit; next }
    /^---[[:space:]]*\r?$/ { exit }
    {
      linha = $0
      gsub(/\r/, "", linha)
      if (index(linha, chave ":") == 1) {
        sub(/^[^:]*:[[:space:]]*/, "", linha)
        gsub(/^["'"'"']|["'"'"']$/, "", linha)
        gsub(/[[:space:]]+$/, "", linha)
        print linha
        exit
      }
    }
  ' "$1" 2>/dev/null
}

expx_trabalho_atual_por_branch() {
  local raiz="$1"
  local branch arq id valor achados=""

  branch="$(git -C "$raiz" branch --show-current 2>/dev/null)" || return 1
  [ -n "$branch" ] || return 1

  for arq in "$raiz"/docs/entregas/*/ENTREGA.md; do
    [ -r "$arq" ] || continue
    valor="$(expx_frontmatter_valor "$arq" branch)"
    [ -n "$valor" ] && [ "$valor" = "$branch" ] || continue
    id="$(basename "$(dirname "$arq")")"
    achados="$achados $id"
  done

  # Exatamente um. Zero ou vários: não determinado.
  set -- $achados
  [ "$#" -eq 1 ] || return 1
  printf '%s\n' "$1"
}

# --------------------------------------------------------------------------
# Leitura do push — o segmento normalizado, por token
# --------------------------------------------------------------------------
# Uma leitura só, usada por `mergex/git-perigoso` (destino: a principal) e por
# `pr-so-com-portao` (origem: a revisão que o push publica). A razão de ler por
# token, e não por regex sobre a linha inteira, está no git-perigoso, seção 0.
#
# Não é um parser de shell: não expande variável, não resolve substituição de
# comando, não entende agrupamento e só tira um par de aspas das pontas do
# token. Classificar o que foi lido — e barrar o que não se classifica — é de
# quem chama.

# Uma aspa em cada ponta do token, no máximo, e só. As pontas são tratadas
# separadamente porque o par se abre e se fecha em tokens diferentes quando o
# comando inteiro está entre aspas (`bash -c "git push origin main"` dá os
# tokens `"git` e `main"`).
expx_sem_aspas() {
  local v="$1"
  v="${v#[\"\']}"
  v="${v%[\"\']}"
  printf '%s' "$v"
}

# Programas que RODAM o que vem no argumento: é esta lista que separa EXECUTAR
# (`bash -c "git push ..."`) de CITAR (`echo "git push ..."`). Compara-se o
# NOME do programa, não o caminho: `/bin/sh` é o mesmo `sh`.
expx_executor() {
  case "$1" in
    bash|sh|dash|zsh|ksh|ksh93|mksh|ash|busybox) return 0 ;;
    eval|command|exec|env|sudo|doas|nohup|setsid|nice|time|timeout|stdbuf|xargs) return 0 ;;
  esac
  return 1
}

# O número que ABRE um redirecionamento sobra no fim do segmento depois da
# quebra (`git push origin main 2>/tmp/log` vira `git push origin main 2`). Ele
# é descritor só quando é uma palavra INTEIRA de dígitos: `main2` é outra
# branch.
expx_sem_descritor() {
  local v="$1" t
  t="${v##*[[:space:]]}"
  case "$t" in
    ''|*[!0-9]*) printf '%s' "$v" ;;
    *)           printf '%s' "${v%"$t"}" ;;
  esac
}

# Emenda SÓ o par barra-invertida+quebra que continua a linha: a barra que NÃO
# está escapada (corrida ímpar de barras no fim da linha). A quebra solta
# continua separando comandos, como no shell.
expx_emenda_continuacao() {
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

# expx_push_segmentos <comando> — os segmentos que podem ser um push, um por
# linha. Separadores de segmento: `&&`, `||`, `;`, `|`, `&`, subshell, crase e
# redirecionamento; a quebra de linha que já estava no comando também separa.
# A troca é do `tr` (byte a byte, POSIX), não do `sed`: `s/X/\n/` é extensão
# GNU, e no sed do BSD o `\n` vira a letra `n` e grudaria os segmentos.
expx_push_segmentos() {
  local c="$1"
  case "$c" in
    *\\$'\n'*) c="$(expx_emenda_continuacao "$c")" ;;
  esac
  printf '%s' "$c" | grep -Fq push || return 0
  printf '%s\n' "$c" | tr ';|&()`<>' '\n\n\n\n\n\n\n\n' | grep -F push
  return 0
}

# expx_push_le <segmento> — 0 se o segmento é mesmo um `git ... push`. Deixa:
#   EXPX_PUSH_OPCOES    as opções do push, sem aspas, na ordem (o VALOR de
#                       `--repo`, `--receive-pack`, `--exec`, `--push-option`,
#                       `-o` e de aglomerado curto terminado em `o` é pulado);
#   EXPX_PUSH_TEM_REMOTO 1 quando há um primeiro posicional (o remoto);
#   EXPX_PUSH_REMOTO    esse remoto, sem aspas;
#   EXPX_PUSH_REFSPECS  os posicionais seguintes (refspecs), sem aspas.
EXPX_PUSH_OPCOES=(); EXPX_PUSH_REFSPECS=(); EXPX_PUSH_REMOTO=""; EXPX_PUSH_TEM_REMOTO=0
expx_push_le() {
  local tok seg atribuiu=0
  EXPX_PUSH_OPCOES=(); EXPX_PUSH_REFSPECS=(); EXPX_PUSH_REMOTO=""; EXPX_PUSH_TEM_REMOTO=0
  seg="$(expx_sem_descritor "$1")"
  set -f                    # o segmento é texto: nada aqui vira glob
  # shellcheck disable=SC2086
  set -- $seg
  set +f

  # Prefixo de ambiente: `GIT_DIR=/tmp/x git push ...` continua sendo um push.
  # Valor com espaço (`GIT_SSH_COMMAND="ssh -v" git push`) chega partido em
  # vários tokens, então, depois da primeira atribuição, os pedaços soltos
  # também são pulados até o nome do programa.
  while [ "$#" -gt 0 ]; do
    case "$(expx_sem_aspas "$1")" in
      [_[:alpha:]]*=*) atribuiu=1 ;;
      -*)              [ "$atribuiu" = 1 ] || break ;;
      *)               break ;;
    esac
    shift
  done
  [ "$#" -gt 0 ] || return 1

  # O `git` só é procurado adiante quando o programa do segmento é executor.
  tok="$(expx_sem_aspas "$1")"
  if [ "$tok" != git ]; then
    expx_executor "${tok##*/}" || return 1
    while [ "$#" -gt 0 ]; do
      [ "$(expx_sem_aspas "$1")" = git ] && break
      shift
    done
    [ "$#" -gt 0 ] || return 1
  fi
  shift

  # Opções globais do git, antes do subcomando. As desta lista levam o valor
  # numa palavra separada (`git -C <path> push`, `git -c <k>=<v> push`).
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--attr-source|--config-env)
        [ "$#" -ge 2 ] || return 1
        shift 2 ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "$(expx_sem_aspas "${1:-}")" = push ] || return 1
  shift

  # A aspa sai do token ANTES de qualquer comparação: quando o comando vem
  # embrulhado, a aspa de fechamento cola na última palavra (`--all"`).
  while [ "$#" -gt 0 ]; do
    tok="$(expx_sem_aspas "$1")"; shift
    case "$tok" in
      # Opções do push cujo valor vem na palavra seguinte.
      --repo|--receive-pack|--exec|--push-option|-o)
        EXPX_PUSH_OPCOES[${#EXPX_PUSH_OPCOES[@]}]="$tok"
        [ "$#" -gt 0 ] && shift
        continue ;;
      --*)
        EXPX_PUSH_OPCOES[${#EXPX_PUSH_OPCOES[@]}]="$tok"
        continue ;;
      -*) # Aglomerado curto: `-fu`; terminado em `o`, o valor vem a seguir.
        EXPX_PUSH_OPCOES[${#EXPX_PUSH_OPCOES[@]}]="$tok"
        case "$tok" in *o) [ "$#" -gt 0 ] && shift ;; esac
        continue ;;
    esac

    # Primeiro posicional é o remoto; os seguintes são refspecs.
    if [ "$EXPX_PUSH_TEM_REMOTO" = 0 ]; then
      EXPX_PUSH_TEM_REMOTO=1
      EXPX_PUSH_REMOTO="$tok"
      continue
    fi
    EXPX_PUSH_REFSPECS[${#EXPX_PUSH_REFSPECS[@]}]="$tok"
  done
  return 0
}

expx_rastro() {
  # expx_rastro <raiz> <evento> <resultado> <detalhe> <hook> [arquivos_json]
  local raiz="$1" evento="$2" resultado="$3" detalhe="$4" hook="$5"
  local arquivos="${6:-[]}"

  local id dir arq
  id="$(expx_trabalho_id "$raiz")"
  dir="$raiz/docs/eventos"
  arq="$dir/$id.jsonl"

  mkdir -p "$dir" 2>/dev/null || return 0   # rastro nunca derruba o hook

  # O rastro é ignorado pelo versionador por padrão (contrato expx-eventos).
  # Isto não é conveniência: sem o ignore, o próprio rastro suja a árvore e o
  # branch-limpa passa a barrar toda troca de branch. O ignore mora dentro de
  # docs/eventos/ para não tocar o .gitignore do projeto, que é do time.
  if [ ! -f "$dir/.gitignore" ]; then
    printf '# Rastro de eventos expx: local da maquina, nao versionado.\n*\n' \
      > "$dir/.gitignore" 2>/dev/null || true
  fi

  # Rotação: acima de 5 MB vira <id>.1.jsonl e um novo começa.
  if [ -f "$arq" ]; then
    local tam
    tam="$(wc -c < "$arq" 2>/dev/null | tr -d ' ')" || tam=0
    if [ "${tam:-0}" -gt 5242880 ]; then
      mv "$arq" "$dir/$id.1.jsonl" 2>/dev/null || true
    fi
  fi

  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg id "$id" \
    --arg ev "$evento" \
    --arg res "$resultado" \
    --arg det "$detalhe" \
    --arg hook "$hook" \
    --argjson arqs "$arquivos" \
    '{ts:$ts, expx_eventos:1, trabalho_id:$id, ferramenta:"mergex",
      origem:"hook", evento:$ev, fase:null, task:null, agente:"principal",
      resultado:$res, detalhe:$det, arquivos:$arqs,
      hook:$hook}' \
    >> "$arq" 2>/dev/null || true
}

# --------------------------------------------------------------------------
# Desfecho
# --------------------------------------------------------------------------
# Modo bloqueio: exit 2 + motivo no stderr (o modelo lê o stderr).
# Modo aviso: registra e deixa passar.
# A mensagem é acionável: diz o que fazer, não só o que está errado.
expx_barra() {
  local modo="$1" raiz="$2" hook="$3" motivo="$4" saida="$5"
  if [ "$modo" = "bloqueio" ]; then
    expx_rastro "$raiz" "acao_bloqueada" "bloqueado" "$motivo" "$hook"
    printf '%s\n' "$saida" >&2
    exit 2
  else
    expx_rastro "$raiz" "regra_violada" "aviso" "$motivo" "$hook"
    # Dois canais, porque os dois harnesses leem lugares diferentes:
    #   Claude Code — stderr, que o transcript mostra
    #   OpenCode    — stdout em JSON, que a ponte anexa ao resultado da
    #                 ferramenta (o `before` do OpenCode não tem "permite mas
    #                 avisa"; sem isto o aviso se perderia lá).
    printf '%s\n' "$saida" >&2
    jq -cn --arg ctx "$saida" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$ctx}}' \
      2>/dev/null || true
    exit 0
  fi
}

# Passagem limpa.
#
# O contrato manda "sempre grava no rastro, inclusive quando permite" (regra 7),
# mas o vocabulário de `evento` não tem um termo para "avaliou e deixou passar".
# Inventar um enum aqui poluiria a leitura do painel, que trata `evento` como
# lista fechada. Enquanto o contrato não nomear esse evento, a passagem é
# silenciosa: o painel só precisa de `regra_violada` e `acao_bloqueada` para
# montar a lista que guia a promoção de aviso para bloqueio.
#
# LACUNA REGISTRADA para o dono do contrato — ver hooks/README.md.
expx_permite() {
  exit 0
}
