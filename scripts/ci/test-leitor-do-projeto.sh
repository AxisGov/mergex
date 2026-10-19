#!/usr/bin/env bash
#
# O leitor do projeto (.claude/skills/mergex/scripts/leitor-do-projeto.sh) e o unico ponto
# da mergex que le `.expx/fatiamento.json`, e sempre pelo nucleo do expx. Sem o arquivo:
# os padroes, sem node. Com o arquivo: o leitor do nucleo, ou erro, nunca os padroes.
# Os casos montam a copia do nucleo (scripts/ci/fixtures/candidatos/expx-nucleo/) num
# repositorio temporario, no caminho em que o `init` do expx a instala.
#
# Uso: bash scripts/ci/test-leitor-do-projeto.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
leitor="$raiz/.claude/skills/mergex/scripts/leitor-do-projeto.sh"
copia="$raiz/scripts/ci/fixtures/candidatos/expx-nucleo"
nucleo_rel='.expx/marketplace/plugins/expx/nucleo/scripts'

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }

tmp="$(mktemp -d)"; aux="$(mktemp -d)"; trap 'rm -rf "$tmp" "$aux"' EXIT
g() { git -C "$tmp" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
mkdir -p "$tmp/$nucleo_rel"
tr -d '\r' < "$copia/expx-fatiamento.mjs" > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base

# PATH sem node: um diretorio so com os comandos que o helper usa, cada um um
# embrulho para o binario real (link simbolico nao e confiavel no Git Bash)
mkdir -p "$aux/sem-node"
for c in git mktemp rm mkdir cat grep cygpath; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$p" > "$aux/sem-node/$c"; chmod +x "$aux/sem-node/$c"
done
sem_node() { (cd "$tmp" && PATH="$aux/sem-node" "$BASH" "$leitor" "$@"); }
tem_node=0; command -v node >/dev/null 2>&1 && tem_node=1

conselho='{
  "expx_fatiamento": 1,
  "justificativa": "sprint de ~8 tasks revisadas uma a uma",
  "legibilidade": { "pr_linhas": 2500, "pr_arquivos": 80, "commit_linhas": 300 },
  "revisao_por_task": { "modo": "obrigatoria" },
  "entrega": "por_sprint"
}'

# 1. sem arquivo: os padroes, sem node no PATH
saida="$(sem_node)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'EXPX_ENTREGA=por_trabalho'*'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
  && passa 'sem arquivo: padroes sem chamar node' \
  || quebra "sem arquivo, sem node (rc $rc): $saida"

# 2. os padroes do helper sao os do leitor do nucleo, nas chaves que o helper imprime
if [ "$tem_node" = 1 ]; then
  mkdir -p "$aux/vazio"
  do_nucleo="$(node "$tmp/$nucleo_rel/expx-fatiamento.mjs" --raiz "$aux/vazio" --formato env)"
  difere=''
  while IFS= read -r linha; do
    k="${linha%%=*}"
    case "$k" in EXPX_CAMINHOS_PROTEGIDOS) continue ;; esac  # vazio de proposito: merge automatico desligado
    printf '%s\n' "$do_nucleo" | grep -qxF -- "$linha" || difere="$difere $k"
  done <<< "$(sem_node)"
  [ -z "$difere" ] && passa 'os padroes do helper sao os do leitor do nucleo' \
    || quebra "padroes do helper diferem do nucleo em:$difere"
else
  passa 'os padroes do helper sao os do leitor do nucleo (sem node)'
fi

# daqui em diante, o arquivo existe no commit
printf '%s\n' "$conselho" > "$tmp/.expx/fatiamento.json"; g add -A; g commit -q -m config

# 3. arquivo valido: repassa o leitor
if [ "$tem_node" = 1 ]; then
  saida="$(cd "$tmp" && bash "$leitor")"; rc=$?
  [ "$rc" = 0 ] && case "$saida" in *'FATIA_MAX_LINHAS_PR=2500'*'EXPX_ENTREGA=por_sprint'*'EXPX_FATIAMENTO_ORIGEM=projeto'*) true ;; *) false ;; esac \
    && passa 'arquivo valido: repassa o leitor' \
    || quebra "arquivo valido (rc $rc): $saida"
else
  passa 'arquivo valido: repassa o leitor (sem node)'
fi

# 4. arquivo invalido: sai 1, stdout vazio, stderr do leitor com a chave
if [ "$tem_node" = 1 ]; then
  printf '{ "expx_fatiamento": 1, "entrega": "por_dia" }\n' > "$tmp/.expx/fatiamento.json"
  (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
  [ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -q 'entrega' "$aux/err" \
    && passa 'arquivo invalido: sai 1, stdout vazio, stderr cita a chave' \
    || quebra "arquivo invalido: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
  g checkout -q -- .expx/fatiamento.json
else
  passa 'arquivo invalido: sai 1 (sem node)'
fi

# 5. arquivo presente e leitor ausente: sai 3 e manda atualizar o expx
mv "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
saida="$(cd "$tmp" && bash "$leitor" 2>&1)"; rc=$?
mv "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
[ "$rc" = 3 ] && case "$saida" in *'expx update'*) true ;; *) false ;; esac \
  && passa 'arquivo presente e leitor ausente: sai 3 e cita expx update' \
  || quebra "arquivo presente e leitor ausente (rc $rc): $saida"

# 6. arquivo presente e node ausente: sai 3, nunca os padroes
saida="$(sem_node 2>&1)"; rc=$?
[ "$rc" = 3 ] && case "$saida" in *'expx update'*) true ;; *) false ;; esac \
  && passa 'arquivo presente e node ausente: sai 3' \
  || quebra "arquivo presente e node ausente (rc $rc): $saida"

# 7. --rev le o arquivo do commit, nao o do disco (o E7 mede o SHA publicado)
if [ "$tem_node" = 1 ]; then
  printf '%s\n' "${conselho/2500/9999}" > "$tmp/.expx/fatiamento.json"
  saida="$(cd "$tmp" && bash "$leitor" --rev HEAD)"; rc=$?
  g checkout -q -- .expx/fatiamento.json
  [ "$rc" = 0 ] && case "$saida" in *'FATIA_MAX_LINHAS_PR=2500'*) true ;; *) false ;; esac \
    && passa '--rev le o arquivo do commit, nao o do disco' \
    || quebra "--rev leu o disco (rc $rc): $saida"
  # leitor do disco diferente do versionado no commit: nenhum dos dois roda, sai 3
  cp "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
  printf 'process.stdout.write("EXPX_FATIAMENTO_ORIGEM=padrao\\n")\n' > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
  saida="$(cd "$tmp" && bash "$leitor" --rev HEAD 2>&1)"; rc=$?
  cp "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
  [ "$rc" = 3 ] && case "$saida" in *'difere do instalado'*) true ;; *) false ;; esac \
    && passa '--rev com leitor do commit diferente do instalado: sai 3' || quebra "--rev com leitores diferentes (rc $rc): $saida"
else
  passa '--rev le o arquivo do commit (sem node)'
fi

# 8. --rev de um commit sem o arquivo, com o arquivo so no disco: os padroes, sem node
saida="$(sem_node --rev HEAD~1)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
  && passa '--rev sem o arquivo no commit, com arquivo so no disco: padroes' \
  || quebra "--rev sem o arquivo no commit (rc $rc): $saida"

# 9. link quebrado no lugar do arquivo: presente e invalido, nunca os padroes
if [ "$tem_node" = 1 ]; then
  mkdir -p "$aux/link/.expx"
  if ln -s "$aux/nao-existe.json" "$aux/link/.expx/fatiamento.json" 2>/dev/null && [ -L "$aux/link/.expx/fatiamento.json" ]; then
    cp -R "$tmp/.expx/marketplace" "$aux/link/.expx/"
    (bash "$leitor" --raiz "$aux/link" > "$aux/out" 2>/dev/null); rc=$?
    [ "$rc" = 1 ] && [ ! -s "$aux/out" ] \
      && passa 'link quebrado como .expx/fatiamento.json: presente e invalido (sai 1)' \
      || quebra "link quebrado: rc $rc, stdout '$(cat "$aux/out")'"
  else
    passa 'link quebrado: pulado, o sistema nao cria link simbolico (o CI em Linux cobre)'
  fi
else
  passa 'link quebrado: presente e invalido (sem node)'
fi

# 10. o consumo seguro exporta para processo filho
if [ "$tem_node" = 1 ]; then
  filho="$(cd "$tmp" && fatia="$(bash "$leitor" --rev HEAD)" || exit 9; set -a; eval "$fatia"; set +a
           bash -c 'printf %s "$FATIA_MAX_LINHAS_PR"')"
  [ "$filho" = 2500 ] && passa 'consumo seguro exporta para processo filho' \
    || quebra "o processo filho viu FATIA_MAX_LINHAS_PR='$filho'"
else
  passa 'consumo seguro exporta para processo filho (sem node)'
fi

# 11. uso errado: 64
(cd "$tmp" && bash "$leitor" --nada >/dev/null 2>&1); rc=$?
[ "$rc" = 64 ] && passa 'argumento desconhecido sai 64' || quebra "argumento desconhecido saiu $rc"

# 12. revisao ou raiz que nao resolvem: sai 2, stdout vazio, nunca os padroes
for args in '--rev nao-existe' "--raiz $aux/nao-existe"; do
  (cd "$tmp" && bash "$leitor" $args > "$aux/out" 2>/dev/null); rc=$?
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && passa "${args%% *} que nao resolve: sai 2" \
    || quebra "${args%% *} que nao resolve: rc $rc, stdout '$(cat "$aux/out")'"
done

# 13. leitor que nao imprime todas as chaves: sai 3 (expx update), nunca o que ele imprimiu
if [ "$tem_node" = 1 ]; then
  cp "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
  printf 'process.stdout.write("FATIA_MAX_LINHAS_PR=1\\nEXPX_FATIAMENTO_ORIGEM=projeto\\n")\n' > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
  (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
  cp "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
  [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'expx update' "$aux/err" \
    && passa 'leitor que nao imprime todas as chaves: sai 3' \
    || quebra "leitor incompleto: rc $rc, stdout '$(cat "$aux/out")'"
else
  passa 'leitor que nao imprime todas as chaves: sai 3 (sem node)'
fi

# commit sobre o HEAD com uma entrada trocada por plumbing, sem depender do sistema de
# arquivos (link, gitlink): commit_com <modo> <objeto> <caminho> [<removido antes>]
commit_com() {
  local idx="$aux/indice"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" g read-tree HEAD
  [ -z "${4:-}" ] || GIT_INDEX_FILE="$idx" g rm -r -q --cached -- "$4"
  GIT_INDEX_FILE="$idx" g update-index --add --cacheinfo "$1,$2,$3"
  g commit-tree "$(GIT_INDEX_FILE="$idx" g write-tree)" -p HEAD -m "$3"
}
blob() { printf '%s' "$1" | g hash-object -w --stdin; }
# 14. --rev com .expx/fatiamento.json que nao e arquivo no commit: presente e invalido (sai 1)
if [ "$tem_node" = 1 ]; then
  pasta="$(commit_com 100644 "$(blob "$conselho")" .expx/fatiamento.json/x .expx/fatiamento.json)"
  link="$(commit_com 120000 "$(blob ../valido.json)" .expx/fatiamento.json)"
  for caso in "pasta $pasta" "link $link"; do
    (cd "$tmp" && bash "$leitor" --rev "${caso#* }" > "$aux/out" 2>/dev/null); rc=$?
    [ "$rc" = 1 ] && [ ! -s "$aux/out" ] && passa "--rev com ${caso%% *} no lugar do arquivo: presente e invalido (sai 1)" \
      || quebra "--rev com ${caso%% *} no lugar do arquivo: rc $rc, stdout '$(cat "$aux/out")'"
  done
else
  passa '--rev com pasta ou link no lugar do arquivo (sem node)'
fi

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
