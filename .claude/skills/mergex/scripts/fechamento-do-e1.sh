#!/usr/bin/env bash
# fechamento-do-e1 — a seção crítica do E1, do primeiro `git add` à lista
# `ENTREGA.commits` validada, sob a trava do índice desta worktree.
#
# Contrato: references/01-commits.md, "A seção crítica do E1";
# references/00-schema.md, "A ordem de registro — a chave `seq`".
#
# A execução das tasks pode ser paralela. O FECHAMENTO delas é serial: o índice
# Git é de dono único. Este é o trecho inteiro que roda sob a trava, e nesta
# ordem:
#
#   A. staging da task           D. `git commit`
#   B. verificação do diff       E. captura do identificador produzido
#      em stage                  F. `sequencia-de-commits.sh --acrescentar`
#   C. verificações do E1        G. validação da lista final
#
# Só depois de G a trava é liberada. A atribuição do `seq` acontece DENTRO da
# seção — é isso que impede duas sessões de calcularem o mesmo próximo número.
#
#   1. A TRAVA VEM ANTES DO PRIMEIRO `git add`. Travar depois de montar o
#      stage é não travar: a mistura de arquivos já teria acontecido.
#   2. STAGE NÃO VAZIO NA ENTRADA PARA. Não importa se o que está lá parece
#      ser da task atual: não existe prova durável de que este E1 o preparou.
#      Nada de `reset`, `restore --staged`, `stash`, limpeza ou commit do que
#      se encontrou — o stage fica exatamente como estava, e os caminhos vão
#      no relatório.
#   3. FALHA É FECHADA. Trava ocupada, stage sujo, verificação reprovada,
#      commit recusado: PARA, sem limpeza destrutiva e sem tocar no que é de
#      outra execução.
#   4. COMMIT FEITO E REGISTRO NÃO CONCLUÍDO NÃO GERA SEGUNDO COMMIT. O
#      desfecho é relatado como o que é — `commit Git existe; registro E1 não
#      foi concluído` —, e a V11 do portão (E2) é quem cobra a prova que falta.
#   5. NADA DE RENUMERAR. Se a lista ficar inválida depois do append, PARA:
#      escolher outro número esconderia o registro perdido (`00-schema.md`).
#
# Uso:
#   fechamento-do-e1.sh --fechar --entrega <ENTREGA.md> --task <id> \
#       --mensagem <arquivo> [--verificacao <comando>] -- <caminho>...
#       a seção crítica inteira, num processo só.
#
#   fechamento-do-e1.sh --preparar --task <id> -- <caminho>...
#       A a C, e a trava FICA ADQUIRIDA. Imprime `token=`. É o modo do agente:
#       a varredura de segredo do E1 é julgamento humano sobre `git diff
#       --cached`, e ela precisa acontecer DENTRO da seção crítica.
#
#   fechamento-do-e1.sh --concluir --entrega <ENTREGA.md> --task <id> \
#       --mensagem <arquivo> --token <token>
#       D a G, sob a mesma trava, e libera.
#
#   fechamento-do-e1.sh --status      # diagnóstico da trava desta worktree
#
# Códigos:
#   0  seção crítica concluída (ou preparada, no `--preparar`)
#   2  E1 OCUPADO — outra execução tem a seção crítica deste índice
#   3  o índice já tinha conteúdo em stage na entrada
#   4  verificação reprovou ANTES do commit — nenhum commit foi criado
#   5  `git commit` falhou — nenhum registro de E1 foi escrito
#   6  o commit existe e o append em `ENTREGA.commits` falhou
#   7  o commit e o item existem e a lista final não valida
#   64 uso inválido
#
# Bash 3.2 (macOS): nada de mapfile, arrays associativos ou ${v,,}.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAVA_SH="$AQUI/trava-do-e1.sh"
SEQ_SH="$AQUI/sequencia-de-commits.sh"

for f in "$TRAVA_SH" "$SEQ_SH"; do
  [ -f "$f" ] || { printf 'fechamento-do-e1: falta %s\n' "$f" >&2; exit 1; }
done
# shellcheck source=trava-do-e1.sh
. "$TRAVA_SH"

TOKEN=""
LIBERAR_NA_SAIDA=0

# A trava só é liberada pelo dono, e o código de saída nunca é mascarado: o
# `rc` é capturado antes de qualquer outra coisa acontecer.
encerrar() {
  local rc="$1"
  if [ "$LIBERAR_NA_SAIDA" = 1 ] && [ -n "$TOKEN" ]; then
    liberar "$TOKEN" >/dev/null 2>&1
  fi
  exit "$rc"
}
trap 'encerrar $?' EXIT

uso() { printf 'fechamento-do-e1: %s\n' "$1" >&2; exit 64; }

para() { # <código> <título> [linha]...
  local rc="$1" titulo="$2"; shift 2
  printf 'mergex E1 %s\n' "$titulo" >&2
  while [ "$#" -gt 0 ]; do printf '%s\n' "$1" >&2; shift; done
  exit "$rc"
}

# ---------------------------------------------------------------------------
# A. staging — por caminho explícito, nunca em bloco.
#
# `git add .`, `-A` e `-u` arrastam o que não foi declarado na task (regra 4 do
# E1). Aqui eles nem chegam ao versionador.
# ---------------------------------------------------------------------------
recusa_bloco() {
  local p
  for p in "$@"; do
    case "$p" in
      .|..|-A|-u|--all|--update|-*)
        para 64 'RECUSADO — staging em bloco' \
          "Caminho não declarado: $p" \
          'O E1 adiciona por caminho explícito; `git add .`, `-A` e `-u` arrastam' \
          'o que nenhuma task declarou.' ;;
    esac
  done
}

# O conteúdo do índice, um caminho por linha. Sem HEAD não há o que comparar,
# e aí o índice inteiro é o stage.
stage_atual() {
  if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    git diff --cached --name-only 2>/dev/null
  else
    git ls-files --cached 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# 1 e 2 — resolver worktree/índice e adquirir a trava. Nesta ordem, e antes de
# qualquer coisa que toque no índice.
# ---------------------------------------------------------------------------
abre_secao() { # <task>
  local saida rc trava
  saida="$(adquirir "$1")"; rc=$?
  if [ "$rc" = 2 ]; then
    trava="$(caminho_da_trava 2>/dev/null)"
    para 2 'OCUPADO — outra execução do E1 tem a seção crítica deste índice' \
      "trava=$trava" \
      "$(diagnostico "$trava" 2>/dev/null)" \
      'A trava não é removida automaticamente e o índice não foi tocado.' \
      'Espere o outro E1 terminar, ou use --status para diagnosticar.'
  fi
  [ "$rc" = 0 ] || para 1 'PARADO — a trava do índice não pôde ser adquirida' \
    'O índice não foi tocado.'
  TOKEN="$(printf '%s\n' "$saida" | awk -F= '$1 == "token" { print $2 }')"
  [ -n "$TOKEN" ] || para 1 'PARADO — a trava foi criada sem token'
  LIBERAR_NA_SAIDA=1
}

# ---------------------------------------------------------------------------
# 3 — o stage na entrada. Nada é limpo, nada é commitado, nada é desfeito.
# ---------------------------------------------------------------------------
confere_stage_de_entrada() {
  local staged
  staged="$(stage_atual)"
  [ -n "$staged" ] || return 0
  para 3 'PARADO — o índice já tinha conteúdo em stage antes do E1' \
    'Não há prova durável de que este E1 preparou esses caminhos, então eles' \
    'ficaram exatamente como estavam: nada foi resetado, guardado nem commitado.' \
    'Em stage:' \
    "$(printf '%s\n' "$staged" | sed 's/^/  /')" \
    'Decida o que fazer com eles e rode o E1 de novo.'
}

# ---------------------------------------------------------------------------
# A a C — staging, diff em stage e verificações aplicáveis, tudo sob a trava.
# ---------------------------------------------------------------------------
prepara() { # <caminho>...
  git add -- "$@" \
    || para 4 'PARADO — o staging da task falhou' \
      'Nenhum commit foi criado. O índice ficou como o versionador o deixou.'
  [ -n "$(stage_atual)" ] \
    || para 4 'PARADO — nada entrou em stage' \
      'Os caminhos declarados não têm alteração a commitar.'
}

# C — a verificação injetada roda DENTRO da seção, com o diff em stage pronto.
verifica() { # <comando>
  [ -n "$1" ] || return 0
  MERGEX_E1_TOKEN="$TOKEN" bash -c "$1" \
    || para 4 'PARADO — verificação do E1 reprovou antes do commit' \
      "Comando: $1" \
      'Nenhum commit foi criado e nada foi limpo: o stage ficou para diagnóstico.'
}

# ---------------------------------------------------------------------------
# D a G — commit, identificador, append e validação final. Ainda sob a trava.
# ---------------------------------------------------------------------------
conclui() { # <entrega> <task> <mensagem>
  local entrega="$1" task="$2" mensagem="$3" sha saida seq

  # A lista é conferida ANTES do commit, e aqui — não no `prepara` —, para que
  # a conferência aconteça também quando a seção foi aberta pelo `--preparar`.
  # Uma sequência já quebrada faria o `--acrescentar` recusar depois, e o
  # desfecho seria um commit sem registro (código 6) por um defeito que dava
  # para ver antes de commitar.
  bash "$SEQ_SH" --validar "$entrega" >/dev/null 2>&1 \
    || para 4 'PARADO — ENTREGA.commits com sequência inválida' \
      "$(bash "$SEQ_SH" --validar "$entrega" 2>&1)" \
      'Contrato do ENTREGA.md inválido: nenhum commit foi criado e nenhum' \
      'número foi escolhido para caber.'

  git commit -F "$mensagem" >/dev/null \
    || para 5 'PARADO — `git commit` falhou' \
      'Nenhum registro de E1 foi escrito: a lista `commits` da ENTREGA não foi' \
      'tocada. Leia o erro literal do versionador acima; nunca contorne com' \
      '`--no-verify`.'

  sha="$(git rev-parse --short HEAD 2>/dev/null)"
  [ -n "$sha" ] \
    || para 6 'PARADO — commit Git existe; registro E1 não foi concluído' \
      'O identificador do commit não pôde ser lido. Nenhum segundo commit foi' \
      'criado. A V11 do portão (E2) vai cobrar a prova que falta.'

  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \
    || para 6 'PARADO — commit Git existe; registro E1 não foi concluído' \
      "commit=$sha" \
      "$saida" \
      'NENHUM segundo commit foi criado e nada foi desfeito: o commit é real e' \
      'fica no histórico. Conserte o registro e rode o E1 tardio para a task;' \
      'até lá, a V11 do portão (E2) nomeia a task sem prova.'

  seq="$(printf '%s\n' "$saida" | awk -F= '$1 == "seq" { print $2 }')"

  bash "$SEQ_SH" --validar "$entrega" >/dev/null 2>&1 \
    || para 7 'PARADO — a lista ficou inválida depois do registro' \
      "commit=$sha" \
      "seq=$seq" \
      "$(bash "$SEQ_SH" --validar "$entrega" 2>&1)" \
      'Nada foi renumerado e nenhum item foi reescrito. Contrato do ENTREGA.md' \
      'inválido: relate e pare.'

  printf 'commit=%s\n' "$sha"
  printf 'seq=%s\n' "$seq"
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
ACAO=""; ENTREGA=""; TASK=""; MENSAGEM=""; VERIFICACAO=""; TOKEN_DADO=""
CAMINHOS_INICIO=0

case "${1:-}" in
  --fechar|--preparar|--concluir|--status) ACAO="$1"; shift ;;
  *) uso "ação desconhecida: ${1:-<nenhuma>} (--fechar, --preparar, --concluir, --status)" ;;
esac

if [ "$ACAO" = --status ]; then
  LIBERAR_NA_SAIDA=0
  [ "$#" -eq 0 ] || uso '--status não recebe argumento'
  status; exit $?
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --entrega)     [ "$#" -ge 2 ] || uso '--entrega precisa de um arquivo'; ENTREGA="$2"; shift 2 ;;
    --task)        [ "$#" -ge 2 ] || uso '--task precisa de um id'; TASK="$2"; shift 2 ;;
    --mensagem)    [ "$#" -ge 2 ] || uso '--mensagem precisa de um arquivo'; MENSAGEM="$2"; shift 2 ;;
    --verificacao) [ "$#" -ge 2 ] || uso '--verificacao precisa de um comando'; VERIFICACAO="$2"; shift 2 ;;
    --token)       [ "$#" -ge 2 ] || uso '--token precisa de um token'; TOKEN_DADO="$2"; shift 2 ;;
    --)            shift; CAMINHOS_INICIO=1; break ;;
    *)             uso "opção desconhecida: $1" ;;
  esac
done

[ -n "$TASK" ] || uso 'falta --task'

RAIZ="$(raiz_da_worktree)" || { printf 'fechamento-do-e1: %s\n' "$ERRO" >&2; exit 1; }

# A ENTREGA é resolvida ANTES do `cd`: o chamador a nomeia a partir de onde
# está, e os caminhos da task são relativos à raiz da worktree.
if [ -n "$ENTREGA" ]; then
  ENTREGA="$(absoluto "$ENTREGA" "$PWD")"
  [ -f "$ENTREGA" ] || uso "ENTREGA.md inexistente: $ENTREGA"
fi
if [ -n "$MENSAGEM" ]; then
  MENSAGEM="$(absoluto "$MENSAGEM" "$PWD")"
  [ -s "$MENSAGEM" ] || uso "arquivo de mensagem vazio ou inexistente: $MENSAGEM"
fi

cd "$RAIZ" || { printf 'fechamento-do-e1: raiz inacessível: %s\n' "$RAIZ" >&2; exit 1; }

case "$ACAO" in
  --fechar)
    [ -n "$ENTREGA" ] || uso 'falta --entrega'
    [ -n "$MENSAGEM" ] || uso 'falta --mensagem'
    [ "$CAMINHOS_INICIO" = 1 ] && [ "$#" -gt 0 ] || uso '--fechar precisa de `-- <caminho>...`'
    recusa_bloco "$@"
    abre_secao "$TASK"                 # 1 e 2
    confere_stage_de_entrada           # 3
    prepara "$@"                       # A e B
    verifica "$VERIFICACAO"            # C
    conclui "$ENTREGA" "$TASK" "$MENSAGEM"   # D a G
    exit 0 ;;

  --preparar)
    [ "$CAMINHOS_INICIO" = 1 ] && [ "$#" -gt 0 ] || uso '--preparar precisa de `-- <caminho>...`'
    recusa_bloco "$@"
    abre_secao "$TASK"
    confere_stage_de_entrada
    prepara "$@"
    # A seção continua aberta: quem preparou tem a trava até `--concluir`.
    LIBERAR_NA_SAIDA=0
    printf 'token=%s\n' "$TOKEN"
    printf 'trava=%s\n' "$(caminho_da_trava)"
    stage_atual | sed 's/^/staged=/'
    exit 0 ;;

  --concluir)
    [ -n "$ENTREGA" ] || uso 'falta --entrega'
    [ -n "$MENSAGEM" ] || uso 'falta --mensagem'
    [ -n "$TOKEN_DADO" ] || uso 'falta --token (o que o --preparar imprimiu)'
    [ "$CAMINHOS_INICIO" = 0 ] || uso '--concluir não recebe caminhos: o stage já está montado'
    conferir "$TOKEN_DADO" \
      || para 2 'OCUPADO — esta execução não é dona da seção crítica' \
        "$ERRO" \
        'Nada foi commitado e nada foi registrado.'
    TOKEN="$TOKEN_DADO"
    LIBERAR_NA_SAIDA=1
    [ -n "$(stage_atual)" ] \
      || para 4 'PARADO — nada em stage para concluir' \
        'O --preparar desta seção não deixou nada no índice.'
    conclui "$ENTREGA" "$TASK" "$MENSAGEM"
    exit 0 ;;
esac
