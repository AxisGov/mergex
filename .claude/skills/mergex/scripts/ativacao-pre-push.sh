#!/usr/bin/env bash
# ativacao-pre-push — ativa (E0) e prova (E0 e E2) o pre-push da MergeX.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seção 13, item 6 (DM-184), e references/12-barreira-de-push.md.
#
# Uso:
#   ativacao-pre-push.sh --instalar|--provar|--reverter --entrega <ENTREGA.md>
#
# <ENTREGA.md> é relativo à raiz da árvore de trabalho
# (docs/entregas/<id>/ENTREGA.md); --reverter não o lê.
#
# Diretório efetivo: sempre o que o próprio Git resolve com
# `git rev-parse --git-path hooks` na raiz, o que já respeita um core.hooksPath
# existente (relativo ou absoluto) e o diretório comum de worktrees
# vinculadas. Este script NUNCA escreve core.hooksPath.
#
# --instalar (E0)
#   Sem pre-push no diretório efetivo: instala o chamador gerenciado (o modelo
#   assets/pre-push-gerenciado.sh, marcador `# mergex: pre-push gerenciado`),
#   com o bit de execução, e roda a prova. Já é o chamador gerenciado: nada
#   muda, e roda a prova. Existe um pre-push de terceiro: nunca o escreve,
#   renomeia ou edita; roda a prova — aprovada, é integração externa válida
#   (rc 0); reprovada, rc 3 com `mergex E0 BLOQUEADO — pre-push` e a instrução
#   de composição. O marcador serve só para a idempotência e a reversão: a
#   aceitação de qualquer pre-push é sempre a prova funcional.
#
# --provar (E0 e E2)
#   Prova por comportamento, nunca por busca textual no hook. Monta, sem tocar
#   remoto nem ref, um commit solto (`git commit-tree`, índice temporário)
#   sobre HEAD com um arquivo de produto e o ENTREGA.md do disco em
#   `portao: pronto` com `portao_sha` = HEAD: um portão sabidamente vencido.
#   Executa o pre-push efetivo como o Git o executaria (na raiz, argumentos
#   `prova-mergex file:///dev/null`, uma linha de protocolo para
#   `refs/heads/<branch da entrega>` com o SHA remoto nulo), com
#   MERGEX_PRE_PUSH_SINAL num temporário. A prova tem DOIS lados, cada um uma
#   execução do hook:
#   (a) a ref aplicável com o commit solto vencido: exige código diferente de
#       zero E a linha `mergex-pre-push <SHA desse commit> barra`, que o
#       portao-push.sh só escreve depois de decidir aquela ref;
#   (b) controle positivo: outro commit solto, com a ÁRVORE VAZIA (`git
#       mktree </dev/null`, no formato de hash do repositório: nenhum
#       ENTREGA.md, para que nenhuma parcela da seleção do pre-push o alcance
#       — DM-185), numa ref NÃO aplicável
#       (`refs/heads/mergex-prova-livre-<pid>[-n]`, conferida como inexistente
#       localmente): exige código 0 E a linha
#       `mergex-pre-push <SHA desse commit> passa`. Pega o hook que ignora o
#       código do validador e decide por regra própria, e o ambiente em que o
#       validador barra tudo por erro.
#   Reprovam: pre-push ausente ou não executável, término por sinal (código
#   128 ou mais), estouro do orçamento de tempo, e qualquer resultado
#   diferente do exigido em (a) ou (b) — código zero em (a), não zero em (b),
#   ou a falta da linha (o validador não rodou, não recebeu a entrada, ou a
#   linha é forjada com outro SHA). Um hook escrito de propósito para forjar a linha lendo o SHA
#   da entrada é contorno deliberado, fora do alcance de qualquer prova local:
#   a barreira contra ele é o CI. Orçamento: PRAZO segundos, por um `timeout`
#   que comprove matar um processo no prazo (detecção pelo comportamento) ou,
#   sem ele, por um vigia em Bash; o hook roda em grupo de processos próprio,
#   morto inteiro no estouro e ao fim (nenhum órfão); estouro reprova (com o
#   `timeout`: código 124, ou 137 depois do prazo inteiro, quando o hook
#   ignorou o TERM e levou o KILL). Os
#   objetos do commit solto ficam soltos no repositório
#   (inalcançáveis, nenhuma ref aponta para eles); o índice e a árvore de
#   trabalho não mudam.
#
# --reverter
#   Remove o pre-push só se ele tem o marcador do chamador gerenciado. Diante
#   de um hook de terceiro (composto ou não) só informa que a integração
#   externa é removida pelo responsável dela, e sai 0 sem tocar o arquivo.
#
# Códigos: 0 ok; 1 prova reprovada; 3 pré-requisito ausente (hook de terceiro
# que não passa na prova, modelo ausente, diretório de hooks sem escrita,
# fora de um repositório Git); 64 uso. Nenhuma opção de força.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAO_PUSH="$AQUI/portao-push.sh"
MODELO="$AQUI/../assets/pre-push-gerenciado.sh"
CATALOGO_SH="$AQUI/catalogo-de-metodo.sh"
RB_SH="$AQUI/reconciliacao-base.sh"
MARCADOR='# mergex: pre-push gerenciado'
PRAZO=120
NL='
'
# A instrução de composição: a mesma de references/12-barreira-de-push.md.
COMPOSICAO='o `pre-push` existente chama `portao-push.sh --pre-push "$@"`, repassa a entrada padrão e propaga exatamente o código de saída dele'

uso() {
  [ -z "${1:-}" ] || printf 'ativacao-pre-push: %s\n' "$1" >&2
  printf '%s\n' 'uso: ativacao-pre-push.sh --instalar|--provar|--reverter --entrega <ENTREGA.md>' >&2
  exit 64
}

MODO=""
ENTREGA=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --instalar|--provar|--reverter) [ -z "$MODO" ] || uso 'um modo só'; MODO="${1#--}"; shift ;;
    --entrega) [ "$#" -ge 2 ] || uso '--entrega sem valor'; ENTREGA="$2"; shift 2 ;;
    *) uso "opção desconhecida: $1" ;;
  esac
done
[ -n "$MODO" ] || uso 'falta o modo'
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
case "$ENTREGA" in
  docs/entregas/*/ENTREGA.md) ;;
  *) uso '--entrega deve ser docs/entregas/<id>/ENTREGA.md, relativo à raiz' ;;
esac
case "/$ENTREGA/" in */../*|*/./*|*//*) uso '--entrega com componente . ou .. ou vazio' ;; esac

diz() { printf 'ativacao-pre-push: %s\n' "$1"; }
erro() { printf 'ativacao-pre-push: %s\n' "$1" >&2; }
pre_requisito() { erro "$1"; exit 3; }

TMP_DIR=""
encerrar() {
  local rc="$1"
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  exit "$rc"
}
trap 'encerrar $?' EXIT
trap 'exit 1' HUP INT TERM

[ -r "$CATALOGO_SH" ] || pre_requisito "dependência indisponível: $CATALOGO_SH"
# shellcheck source=catalogo-de-metodo.sh
. "$CATALOGO_SH" || pre_requisito "dependência ilegível: $CATALOGO_SH"
set +e

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || pre_requisito 'fora de um repositório Git com árvore de trabalho'
# O diretório efetivo vem do próprio Git, na raiz: core.hooksPath (relativo à
# raiz ou absoluto) e o diretório comum de worktree vinculada já resolvidos.
# A primeira linha é só o ponto de partida ingênuo (<git comum>/hooks, que
# ignoraria core.hooksPath); a guarda o substitui pelo efetivo.
HOOKS="$(git -C "$RAIZ" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hooks"
HOOKS="$(git -C "$RAIZ" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" # guarda:ATVHP
[ -n "$HOOKS" ] || pre_requisito 'o Git não resolveu o diretório de hooks efetivo'
HOOK="$HOOKS/pre-push"

# gerenciado — o pre-push é o chamador gerenciado (arquivo regular com o
# marcador). Só para a idempotência e a reversão; nunca aceita nada sozinho.
gerenciado() {
  [ -f "$HOOK" ] && [ ! -L "$HOOK" ] && grep -Fxq -- "$MARCADOR" "$HOOK" 2>/dev/null
}
existe() { [ -e "$HOOK" ] || [ -L "$HOOK" ]; }

instrucao() {
  printf '%s\n' \
    "mergex E0 BLOQUEADO — pre-push: o pre-push de terceiro em $HOOK não passou na prova funcional ($PROVA_ERRO); o arquivo não foi alterado." \
    "Composição deliberada, feita à mão por quem mantém o hook: $COMPOSICAO." \
    "Validador desta instalação: $PORTAO_PUSH" \
    'Exemplo e detalhes: .claude/skills/mergex/references/12-barreira-de-push.md, "Composição com hook de terceiro". Depois de compor, rode o E0 de novo.' >&2
}

# ---------------------------------------------------------------------------
# Prova funcional
# ---------------------------------------------------------------------------

# O editor de frontmatter do registro (Task 6), reutilizado literalmente de
# reconciliacao-base.sh: as mesmas funções, sem um parser novo.
carrega_editor() {
  [ -r "$RB_SH" ] || return 1
  eval "$(awk '/^(_entrega_fecha|_entrega_troca|entrega_define)\(\) \{/,/^}$/' "$RB_SH")" || return 1
  declare -F _entrega_fecha >/dev/null && declare -F _entrega_troca >/dev/null && declare -F entrega_define >/dev/null
}

# orcamento — LIMITE com um `timeout` que comprovadamente mata um processo
# dentro do prazo (pelo comportamento: `timeout 1 sleep 5` tem de sair 124 em
# menos de 5 s; vale GNU, uutils ou outro); senão vazio, e executa_hook usa o
# vigia em Bash.
LIMITE=""
orcamento() {
  local ini fim rc
  LIMITE=""
  command -v timeout >/dev/null 2>&1 || return 0
  ini="$(date +%s)"; timeout 1 sleep 5 >/dev/null 2>&1; rc=$?; fim="$(date +%s)"
  [ "$rc" = 124 ] && [ $((fim - ini)) -lt 5 ] && LIMITE="timeout -k 5 $PRAZO"
  return 0
}

# executa_hook <lado> — roda o pre-push efetivo como o Git (na raiz,
# argumentos da prova, a linha de protocolo linha-<lado> na entrada,
# MERGEX_PRE_PUSH_SINAL=sinal-<lado>, saída em saida-<lado>) em grupo de
# processos próprio (`set -m`), com o orçamento: o `timeout` comprovado, ou um
# vigia em Bash que, estourado o PRAZO, marca estouro-<lado> e mata o grupo
# (TERM e, 5 s depois, KILL). No fim, o que sobrar do grupo do hook é morto:
# nenhum processo órfão. Devolve o código do hook; DURACAO em segundos.
DURACAO=0
executa_hook() {
  local l="$1" pid vigia="" rc ini
  rm -f "$TMP_DIR/estouro-$l"; : > "$TMP_DIR/sinal-$l"
  ini="$(date +%s)"
  set -m
  # shellcheck disable=SC2086
  ( cd "$RAIZ" && export MERGEX_PRE_PUSH_SINAL="$TMP_DIR/sinal-$l" && exec $LIMITE "$HOOK" prova-mergex file:///dev/null       < "$TMP_DIR/linha-$l" > "$TMP_DIR/saida-$l" 2>&1 ) &
  pid=$!
  if [ -z "$LIMITE" ]; then
    ( sleep "$PRAZO"; : > "$TMP_DIR/estouro-$l"; kill -TERM -- "-$pid" 2>/dev/null
      sleep 5; kill -KILL -- "-$pid" 2>/dev/null ) >/dev/null 2>&1 &
    vigia=$!
  fi
  wait "$pid"; rc=$?
  if [ -n "$vigia" ]; then kill -KILL -- "-$vigia" 2>/dev/null; wait "$vigia" 2>/dev/null; fi
  kill -KILL -- "-$pid" 2>/dev/null
  set +m
  DURACAO=$(( $(date +%s) - ini ))
  PROVA_SAIDA="$TMP_DIR/saida-$l"
  return "$rc"
}

# tempo_ok <lado> <rc> — o hook terminou sozinho, dentro do orçamento. Com o
# `timeout`, 124 é estouro, e 137 também quando o prazo inteiro passou (o hook
# ignorou o TERM e levou o KILL do `-k`); antes do prazo, 137 é término por
# sinal do próprio hook.
tempo_ok() {
  local est="o pre-push estourou o orçamento de ${PRAZO}s ($1)"
  [ ! -e "$TMP_DIR/estouro-$1" ] || { PROVA_ERRO="$est"; return 1; }
  if [ -n "$LIMITE" ]; then
    [ "$2" != 124 ] || { PROVA_ERRO="$est"; return 1; }
    [ "$2" != 137 ] || [ "$DURACAO" -lt "$PRAZO" ] || { PROVA_ERRO="$est"; return 1; }
  fi
  [ "$2" -lt 128 ] || { PROVA_ERRO="o pre-push terminou por sinal (código $2, $1)"; return 1; }
  return 0
}

# para_git <caminho> — o temporário como o git o lê: no Git Bash do Windows,
# a forma mista do cygpath (não depende da conversão automática do MSYS, que
# MSYS_NO_PATHCONV desliga); nos demais, o próprio caminho
para_git() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

PROVA_ERRO=""
PROVA_RC=""
provar() {
  local head b c c2 livre n arvore vazia blob_e blob_p nulo produto rc tg
  PROVA_ERRO=""; PROVA_RC=""; PROVA_SAIDA=""
  [ -f "$HOOK" ] && [ -x "$HOOK" ] || { PROVA_ERRO="nenhum pre-push executável no diretório efetivo $HOOKS"; return 1; }
  [ -f "$RAIZ/$ENTREGA" ] && [ ! -L "$RAIZ/$ENTREGA" ] || { PROVA_ERRO="$ENTREGA não é arquivo regular"; return 1; }
  carrega_editor || { PROVA_ERRO="editor de frontmatter indisponível ($RB_SH)"; return 1; }
  head="$(git -C "$RAIZ" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || { PROVA_ERRO='HEAD não resolve para um commit'; return 1; }
  if [ -z "$TMP_DIR" ]; then
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mergex-ativacao.XXXXXX")" || { TMP_DIR=""; PROVA_ERRO='não foi possível criar diretório temporário'; return 1; }
  fi
  # o ENTREGA.md do disco com o portão sabidamente vencido: pronto em HEAD,
  # seguido de um commit de produto
  cp "$RAIZ/$ENTREGA" "$TMP_DIR/entrega.md" || { PROVA_ERRO="$ENTREGA ilegível"; return 1; }
  ENTREGA_ERRO=""
  entrega_define "$TMP_DIR/entrega.md" portao pronto && entrega_define "$TMP_DIR/entrega.md" portao_sha "$head" \
    || { PROVA_ERRO="$ENTREGA: $ENTREGA_ERRO"; return 1; }
  b="$(catalogo_fm "$TMP_DIR/entrega.md" branch)"
  case "$b" in ''|*[[:space:]]*|*[[:cntrl:]]*) PROVA_ERRO="$ENTREGA sem branch: válida"; return 1 ;; esac
  produto=".mergex-prova-pre-push/produto-$$.txt"
  printf 'prova funcional do pre-push da MergeX (%s)\n' "$$" > "$TMP_DIR/produto" || { PROVA_ERRO='temporário sem escrita'; return 1; }
  tg="$(para_git "$TMP_DIR")" || { PROVA_ERRO='temporário sem caminho para o git'; return 1; }
  blob_e="$(git -C "$RAIZ" hash-object -w --no-filters -- "$tg/entrega.md" 2>/dev/null)" \
    && blob_p="$(git -C "$RAIZ" hash-object -w --no-filters -- "$tg/produto" 2>/dev/null)" \
    && GIT_INDEX_FILE="$tg/indice" git -C "$RAIZ" read-tree "$head" 2>/dev/null \
    && GIT_INDEX_FILE="$tg/indice" git -C "$RAIZ" update-index --add --cacheinfo "100644,$blob_e,$ENTREGA" 2>/dev/null \
    && GIT_INDEX_FILE="$tg/indice" git -C "$RAIZ" update-index --add --cacheinfo "100644,$blob_p,$produto" 2>/dev/null \
    && arvore="$(GIT_INDEX_FILE="$tg/indice" git -C "$RAIZ" write-tree 2>/dev/null)" \
    && c="$(GIT_AUTHOR_NAME='MergeX prova' GIT_AUTHOR_EMAIL='prova@mergex.invalid' \
      GIT_COMMITTER_NAME='MergeX prova' GIT_COMMITTER_EMAIL='prova@mergex.invalid' \
      git -C "$RAIZ" commit-tree --no-gpg-sign "$arvore" -p "$head" -m 'chore: prova funcional do pre-push da mergex' 2>/dev/null)" \
    || { PROVA_ERRO='não foi possível montar o commit solto da prova'; return 1; }
  nulo="$(printf '%s' "$c" | sed 's/./0/g')"
  orcamento

  # (a) a ref aplicável com o portão sabidamente vencido: o hook tem de barrar
  # (código diferente de zero), e o validador tem de ter decidido `barra` para
  # o SHA do commit solto DESTA prova (a linha vem do portao-push.sh depois da
  # decisão; linha antiga, SHA alheio ou decisão diferente não contam)
  printf 'refs/heads/%s %s refs/heads/%s %s
' "$b" "$c" "$b" "$nulo" > "$TMP_DIR/linha-a"
  executa_hook a 2>/dev/null; rc=$?
  PROVA_RC="$rc"
  tempo_ok a "$rc" || return 1
  [ "$rc" != 0 ] || { PROVA_ERRO='o pre-push saiu com código 0: liberou a ref sabidamente inválida da prova, ou não propagou o código do validador'; return 1; }
  grep -Fxq "mergex-pre-push $c barra" "$TMP_DIR/sinal-a" || { PROVA_ERRO="o pre-push saiu com código $rc sem que o validador da MergeX barrasse a ref da prova ($c): nenhuma decisão dele no sinal"; return 1; } # guarda:ATVTXT

  # (b) controle positivo: outro commit solto, com a árvore VAZIA (nenhum
  # ENTREGA.md: nem o nome, nem o conteúdo, nem o trailer selecionam nada —
  # DM-185), numa ref NÃO aplicável — um nome que não existe localmente. O
  # validador decide `passa` e o hook tem de sair 0: prova que o código do
  # hook é o do validador (não uma regra própria) e que o validador de fato
  # avalia neste ambiente (não barra tudo por erro)
  n=0; livre="mergex-prova-livre-$$"
  while git -C "$RAIZ" show-ref -q --verify "refs/heads/$livre"; do n=$((n + 1)); livre="mergex-prova-livre-$$-$n"; done
  vazia="$(git -C "$RAIZ" mktree </dev/null 2>/dev/null)" || { PROVA_ERRO='não foi possível gravar a árvore vazia do controle positivo'; return 1; }
  c2="$(GIT_AUTHOR_NAME='MergeX prova' GIT_AUTHOR_EMAIL='prova@mergex.invalid'       GIT_COMMITTER_NAME='MergeX prova' GIT_COMMITTER_EMAIL='prova@mergex.invalid'       git -C "$RAIZ" commit-tree --no-gpg-sign "$vazia" -p "$head" -m 'chore: controle positivo da prova do pre-push da mergex' 2>/dev/null)"     || { PROVA_ERRO='não foi possível montar o commit solto do controle positivo'; return 1; }
  printf 'refs/heads/%s %s refs/heads/%s %s
' "$livre" "$c2" "$livre" "$nulo" > "$TMP_DIR/linha-b"
  executa_hook b 2>/dev/null; rc=$?
  tempo_ok b "$rc" || return 1
  [ "$rc" = 0 ] || { PROVA_ERRO="controle positivo: o pre-push barrou (código $rc) uma ref não aplicável (refs/heads/$livre): não propaga o código do validador (regra própria) ou o validador barra tudo neste ambiente"; return 1; } # guarda:ATVTXT
  grep -Fxq "mergex-pre-push $c2 passa" "$TMP_DIR/sinal-b" || { PROVA_ERRO="controle positivo: o validador da MergeX não decidiu \`passa\` para a ref não aplicável ($c2)"; return 1; } # guarda:ATVTXT
  return 0
}

aprovada() {
  diz "prova funcional aprovada: o pre-push efetivo ($HOOK) executou o validador da MergeX, barrou a ref inválida da prova (código $PROVA_RC) e liberou o controle positivo (código 0)"
}
reprovada() {
  erro "prova funcional reprovada: $PROVA_ERRO"
  if [ -n "${PROVA_SAIDA:-}" ] && [ -s "$PROVA_SAIDA" ]; then
    sed -n '1,20s/^/  pre-push: /p' "$PROVA_SAIDA" >&2
  fi
}

# ---------------------------------------------------------------------------
# Instalação do chamador gerenciado (só quando não existe pre-push)
# ---------------------------------------------------------------------------
instala() {
  local rel linha
  [ -r "$MODELO" ] && grep -Fxq -- "$MARCADOR" "$MODELO" || pre_requisito "modelo do chamador gerenciado ausente ou sem o marcador: $MODELO"
  # validador da skill dentro da árvore: relativo à raiz, resolvido quando o
  # Git roda o hook (vale em worktree vinculada e pelo Git for Windows);
  # fora dela, o caminho absoluto
  case "$PORTAO_PUSH" in
    "$RAIZ"/*) rel="${PORTAO_PUSH#"$RAIZ"/}"; linha="MERGEX_PORTAO_PUSH=\"\$MERGEX_RAIZ\"/$(printf '%q' "$rel")" ;;
    *) linha="MERGEX_PORTAO_PUSH=$(printf '%q' "$PORTAO_PUSH")" ;;
  esac
  # só cria quando falta (o `mkdir -p` do Git Bash falha sobre //servidor/...)
  [ -d "$HOOKS" ] || mkdir -p "$HOOKS" 2>/dev/null || pre_requisito "não foi possível criar o diretório de hooks efetivo $HOOKS"
  # noclobber: a criação falha se um pre-push surgiu depois da verificação;
  # nunca sobrescreve
  if ! ( set -C; LINHA="$linha" awk '$0 == "MERGEX_PORTAO_PUSH=__MERGEX_PORTAO_PUSH__" { print ENVIRON["LINHA"]; next } { print }' "$MODELO" > "$HOOK" ) 2>/dev/null; then
    pre_requisito "não foi possível criar $HOOK (já existe ou sem escrita); nada foi sobrescrito"
  fi
  chmod 755 "$HOOK" 2>/dev/null || pre_requisito "não foi possível dar o bit de execução a $HOOK"
  diz "chamador gerenciado instalado em $HOOK"
}

# terceiro — o pre-push existente não é o gerenciado: nunca é escrito,
# renomeado nem editado. Aprovado na prova, é integração externa válida (sai
# 0); reprovado, é pré-requisito ausente (sai 3) com a instrução de composição.
terceiro() {
  if provar; then
    aprovada
    diz "o pre-push de terceiro em $HOOK passou na prova funcional: integração externa válida; o arquivo não foi alterado"
    exit 0
  fi
  reprovada
  instrucao
  exit 3
}

# ---------------------------------------------------------------------------
# Modos
# ---------------------------------------------------------------------------
case "$MODO" in
  provar)
    if provar; then aprovada; exit 0; fi
    reprovada
    erro 'sem a prova o E2 não emite PRONTO; rode o E0 (ativacao-pre-push.sh --instalar) e siga a instrução dele'
    exit 1 ;;

  reverter)
    if ! existe; then diz "nenhum pre-push em $HOOKS; nada a reverter"; exit 0; fi
    if gerenciado; then
      rm -f "$HOOK" || pre_requisito "não foi possível remover $HOOK"
      diz "chamador gerenciado removido de $HOOK"; exit 0
    fi
    diz "o pre-push em $HOOK não é o chamador gerenciado pela MergeX: não foi tocado. Se ele compõe a MergeX (integração externa), a composição é removida pelo responsável dele."
    exit 0 ;;

  instalar)
    # pre-push de terceiro: só a prova decide, e o arquivo nunca é tocado
    ! existe || gerenciado || terceiro # guarda:ATVSOB
    if gerenciado; then diz "chamador gerenciado já ativo em $HOOK; nada mudou"; else instala; fi
    if provar; then aprovada; exit 0; fi
    reprovada
    erro "mergex E0 BLOQUEADO — pre-push: o chamador gerenciado em $HOOK não passou na prova funcional; confira o validador ($PORTAO_PUSH) e rode --reverter e --instalar de novo"
    exit 1 ;;
esac
uso
