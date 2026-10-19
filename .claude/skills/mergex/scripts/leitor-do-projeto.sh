#!/usr/bin/env bash
#
# Le a configuracao do projeto (`.expx/fatiamento.json`) pelo nucleo do expx e imprime as
# variaveis efetivas, uma `CHAVE=valor` por linha, no formato que o shell le.
#
# Uso: leitor-do-projeto.sh [--raiz <dir>] [--rev <commit>]
#   --raiz  raiz do projeto (padrao: `git rev-parse --show-toplevel`)
#   --rev   le o arquivo deste commit, nunca o do disco (o E7 passa o SHA publicado; o
#           merge automatico e o E9, o da base)
#
# - Arquivo ausente (no commit, com --rev; no disco, sem): os padroes, sem chamar node.
# - Arquivo presente: o leitor do nucleo,
#   `<raiz>/.expx/marketplace/plugins/expx/nucleo/scripts/expx-fatiamento.mjs`, com o
#   stdout repassado byte a byte. Roda sempre o instalado, nunca codigo do commit.
#
# Saidas: 0 leu; 1 arquivo invalido (stderr do leitor, stdout vazio); 2 a revisao ou a
# raiz nao resolvem; 3 arquivo presente e leitor ou node ausente, ou leitor que nao
# imprime todas as chaves; 64 uso. Fora do 0, nunca os padroes e nada no stdout.
#
# Consumo: `fatia="$(bash leitor-do-projeto.sh ...)" || <falha>; set -a; eval "$fatia"; set +a`.
# Nenhum `eval` aqui dentro.

set -uo pipefail

uso() { printf 'leitor-do-projeto: %s\nuso: leitor-do-projeto.sh [--raiz <dir>] [--rev <commit>]\n' "$1" >&2; exit 64; }
raiz=''; rev=''
while [ $# -gt 0 ]; do
  case "$1" in
    --raiz|--rev) [ $# -ge 2 ] && [ -n "$2" ] || uso "$1 exige valor"
                  if [ "$1" = --raiz ]; then raiz="$2"; else rev="$2"; fi; shift 2 ;;
    *) uso "argumento desconhecido: $1" ;;
  esac
done
if [ -z "$raiz" ]; then
  raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo 'leitor-do-projeto: fora de um repositorio git (use --raiz)' >&2; exit 2; }
fi
[ -d "$raiz" ] || { echo "leitor-do-projeto: raiz inexistente: $raiz" >&2; exit 2; }
if [ -n "$rev" ]; then
  commit="$(git -C "$raiz" rev-parse --verify --quiet "$rev^{commit}")" \
    || { echo "leitor-do-projeto: revisao inexistente: $rev" >&2; exit 2; }
fi

config='.expx/fatiamento.json'
if [ -n "$rev" ]; then
  git -C "$raiz" cat-file -e "$commit:$config" 2>/dev/null && presente=1 || presente=0
else
  # qualquer entrada conta, como o `lstat` do leitor: link quebrado e presente (e invalido)
  { [ -e "$raiz/$config" ] || [ -L "$raiz/$config" ]; } && presente=1 || presente=0
fi

if [ "$presente" = 0 ]; then
  # os padroes do leitor do nucleo; sem FATIA_MAX_*, para o E7 medir como sempre mediu.
  # EXPX_CAMINHOS_PROTEGIDOS vazio: com o merge automatico desligado a lista nao e lida
  cat <<'EOF'
FATIA_CAPACIDADE_EXCLUIDO='^docs/(sprintx|entregas|eventos)/'
EXPX_REVISAO_POR_TASK=se_disponivel
EXPX_ENTREGA=por_trabalho
EXPX_MERGE_AUTOMATICO=nao
EXPX_CAMINHOS_PROTEGIDOS=
EXPX_REVISOR_BOT=
EXPX_FATIAMENTO_ORIGEM=padrao
EOF
  exit 0
fi

desatualizado() { echo "leitor-do-projeto: expx-fatiamento ausente ou incompleto: atualize o expx (expx update)${1:+ ($1)}" >&2; exit 3; }
mjs_rel=".expx/marketplace/plugins/expx/nucleo/scripts/expx-fatiamento.mjs"; mjs="$raiz/$mjs_rel"
[ -f "$mjs" ] || desatualizado "sem $mjs"
# com --rev, se o commit versiona um leitor diferente do instalado, nenhum dos dois decide
if [ -n "$rev" ] && no_commit="$(git -C "$raiz" rev-parse --verify --quiet "$commit:$mjs_rel")" \
   && [ "$no_commit" != "$(git -C "$raiz" hash-object -- "$mjs_rel")" ]; then desatualizado 'o leitor do commit difere do instalado'; fi
command -v node >/dev/null 2>&1 || desatualizado 'node ausente'

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
leia="$raiz"
if [ -n "$rev" ]; then
  # materializa o arquivo do commit; o que nao e blob (pasta, submodulo) vira pasta, que o
  # leitor recusa como ilegivel. Link do commit vira o texto do alvo: JSON invalido
  leia="$tmp/raiz"; mkdir -p "$leia/.expx" || exit 2
  if [ "$(git -C "$raiz" cat-file -t "$commit:$config")" = blob ]; then
    git -C "$raiz" cat-file blob "$commit:$config" > "$leia/$config" || exit 2
  else
    mkdir "$leia/$config" || exit 2
  fi
fi
# node nativo no Windows nao entende o caminho do MSYS
if command -v cygpath >/dev/null 2>&1; then leia="$(cygpath -w "$leia")"; mjs="$(cygpath -w "$mjs")"; fi

node "$mjs" --raiz "$leia" --formato env > "$tmp/env" 2> "$tmp/err"; rc=$?
if [ "$rc" = 1 ]; then cat "$tmp/err" >&2; exit 1; fi
[ "$rc" = 0 ] || { cat "$tmp/err" >&2; desatualizado "o leitor saiu $rc"; }
grep -qx 'EXPX_FATIAMENTO_ORIGEM=projeto' "$tmp/env" || desatualizado 'o leitor nao confirmou a origem projeto'
for k in FATIA_MAX_LINHAS_PR FATIA_MAX_ARQUIVOS FATIA_MAX_LINHAS_COMMIT FATIA_MAX_KB_ARQUIVO \
         FATIA_MAX_LINHAS_ARQUIVO FATIA_IGNORAR_PROJETO FATIA_CAPACIDADE_ARQUIVOS \
         FATIA_CAPACIDADE_EXCLUIDO EXPX_REVISAO_POR_TASK EXPX_ENTREGA EXPX_MERGE_AUTOMATICO \
         EXPX_CAMINHOS_PROTEGIDOS EXPX_REVISOR_BOT; do
  grep -q "^$k=" "$tmp/env" || desatualizado "o leitor nao imprime $k"
done
cat "$tmp/env"
