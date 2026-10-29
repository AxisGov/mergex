# segredo-dispensa — os arquivos do framework que o lock da instalação confere por hash.
#
# A atualização do framework escreve arquivos que a varredura de segredo acusava
# (referência de código, texto das decisões, a própria tabela), e o hook instalado
# barrava o commit da própria atualização (conselhos, 0.12.5 para 0.12.8; DM-286).
# Um arquivo cujo blob bate com o sha256 que o lock v2 registra em
# `instalacao.arquivos` é o que o ExpxDev instalou: não é varrido.
#
# A dispensa é estreita, e qualquer dúvida a desliga (a varredura segue normal):
# - o lock e o blob vêm do MESMO estado que vai para o histórico: o índice no
#   commit, o próprio commit no push; nunca a árvore de trabalho nem o HEAD;
# - só caminhos em .claude/{hooks,skills,commands,agents}/ e .expx/marketplace/,
#   relativos, sem `.`/`..`, segmento vazio, barra invertida ou controle;
# - só blob regular (100644/100755), no estágio 0;
# - lock v2 legível, até 1 MiB e 4.096 entradas, todo hash com 64 hex; até 256
#   arquivos dispensados e 32 MiB de blobs conferidos por estado.
# Quem falsifica o lock para casar com um segredo passa: o hook existe contra o
# vazamento acidental, e o lock é declaração local, não prova de procedência.
#
# Uso (com o diretório de trabalho na raiz do repositório):
#   segredo_dispensaveis_indice        — caminhos do índice, um por linha
#   segredo_dispensaveis_commit <sha> [pai] — caminhos do commit, contra o primeiro pai
#                                        (sem pai: o commit raiz), um por linha
#   segredo_pathspec_excluir           — lê caminhos e escreve `:(top,literal,exclude)<c>`

_disp_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{ print $1 }'
  else return 1; fi
}

_disp_caminho_ok() {
  case "$1" in
    .claude/hooks/?*|.claude/skills/?*|.claude/commands/?*|.claude/agents/?*|.expx/marketplace/?*) ;;
    *) return 1 ;;
  esac
  case "/$1/" in */./*|*/../*|*//*) return 1 ;; esac
  case "$1" in *\\*) return 1 ;; esac
  printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]' && return 1
  return 0
}

# _disp_lock <objeto do lock> — "caminho<TAB>hash" de cada entrada elegível. Lock
# fora do contrato: nada (e rc 1).
_disp_lock() {
  local obj="$1" tam
  command -v jq >/dev/null 2>&1 || return 1
  tam="$(git cat-file -s "$obj" 2>/dev/null)" || return 1
  [ "$tam" -le 1048576 ] 2>/dev/null || return 1
  git cat-file blob "$obj" 2>/dev/null | jq -r '
    if .lock_version == 2 and (.instalacao.arquivos | type) == "object"
       and (.instalacao.arquivos | length) <= 4096
       and all(.instalacao.arquivos[]; type == "string" and test("^[0-9a-f]{64}$"))
    then .instalacao.arquivos | to_entries[] | "\(.key)\t\(.value)"
    else error("fora do contrato") end' 2>/dev/null
}

# _disp_filtra <lock "caminho\thash"> <prefixo do blob> < alterados (NUL)
# Para cada alterado elegível, o blob (de `<prefixo><caminho>`) com sha256 igual ao do
# lock. `<prefixo>` é `:` (índice, estágio 0) ou `<sha>:` (commit). Acima dos limites,
# nada: a lista só sai inteira, no fim.
_disp_filtra() {
  local lock="$1" pref="$2" c esperado modo obj n=0 soma=0 tam saida=""
  while IFS= read -r -d '' c; do
    _disp_caminho_ok "$c" || continue
    esperado="$(printf '%s\n' "$lock" | awk -F '\t' -v c="$c" '$1 == c { print $2; exit }')"
    [ -n "$esperado" ] || continue
    if [ "$pref" = ":" ]; then
      modo="$(git ls-files -s -z -- ":(top,literal)$c" 2>/dev/null | tr '\0' '\n')"
      [ "$(printf '%s\n' "$modo" | grep -c .)" = 1 ] || continue
      case "$modo" in "100644 "*" 0	$c"|"100755 "*" 0	$c") ;; *) continue ;; esac
      obj="$(printf '%s' "$modo" | awk '{ print $2 }')"
    else
      modo="$(git ls-tree -z --full-tree "${pref%:}" -- "$c" 2>/dev/null | tr '\0' '\n')"
      [ "$(printf '%s\n' "$modo" | grep -c .)" = 1 ] || continue
      case "$modo" in "100644 blob "*"	$c"|"100755 blob "*"	$c") ;; *) continue ;; esac
      obj="$(printf '%s' "$modo" | awk '{ print $3 }')"
    fi
    tam="$(git cat-file -s "$obj" 2>/dev/null)" || continue
    soma=$((soma + tam)); [ "$soma" -le 33554432 ] || return 1
    [ "$(git cat-file blob "$obj" 2>/dev/null | _disp_sha256)" = "$esperado" ] || continue
    n=$((n + 1)); [ "$n" -le 256 ] || return 1
    saida="${saida}${c}
"
  done
  printf '%s' "$saida"
}

segredo_dispensaveis_indice() {
  local lock
  printf 'x' | _disp_sha256 >/dev/null 2>&1 || return 0
  lock="$(_disp_lock ":.expx/expx-lock.json")" || return 0
  [ -n "$lock" ] || return 0
  git diff --cached --name-only -z 2>/dev/null | _disp_filtra "$lock" ":" || return 0
}

segredo_dispensaveis_commit() {
  local c="$1" pai="${2:-}" lock
  printf 'x' | _disp_sha256 >/dev/null 2>&1 || return 0
  lock="$(_disp_lock "$c:.expx/expx-lock.json")" || return 0
  [ -n "$lock" ] || return 0
  if [ -n "$pai" ]; then
    git diff --name-only -z --no-renames "$pai" "$c" -- 2>/dev/null | _disp_filtra "$lock" "$c:" || return 0
  else
    git diff-tree --no-commit-id --root -r --name-only -z "$c" -- 2>/dev/null | _disp_filtra "$lock" "$c:" || return 0
  fi
}

segredo_pathspec_excluir() {
  local c
  while IFS= read -r c; do
    [ -n "$c" ] && printf ':(top,literal,exclude)%s\n' "$c"
  done
}
