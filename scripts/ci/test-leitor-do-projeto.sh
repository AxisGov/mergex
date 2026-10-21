#!/usr/bin/env bash
#
# O leitor do projeto (.claude/skills/mergex/scripts/leitor-do-projeto.sh) e o unico ponto
# da mergex que le `.expx/fatiamento.json`, e sempre pelo nucleo do expx. Sem o arquivo:
# os padroes, sem node. Com o arquivo: o leitor do nucleo, ou erro, nunca os padroes.
# `FATIA_*` no ambiente e erro (limites do CodeAnt, fixos: emenda de 2026-10-19).
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

# nenhuma FATIA_* herdada do shell de quem roda os testes muda o que se mede aqui
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done

# monta_nucleo <destino>: a copia inteira do nucleo (menos o ORIGEM), com as subpastas, sem CR
# (num checkout com core.autocrlf=true a copia chega com CRLF)
monta_nucleo() {
  local f
  while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")" && tr -d '\r' < "$copia/$f" > "$1/$f"
  done < <(cd "$copia" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
}
tmp="$(mktemp -d)"; aux="$(mktemp -d)"; trap 'rm -rf "$tmp" "$aux"' EXIT
g() { git -C "$tmp" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
monta_nucleo "$tmp/$nucleo_rel"
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base

# 0. a montagem traz a copia inteira do nucleo (menos o ORIGEM), com as subpastas
lista() { (cd "$1" && find . -type f ! -path ./ORIGEM | LC_ALL=C sort); }
[ "$(lista "$copia")" = "$(lista "$tmp/$nucleo_rel")" ] \
  && passa 'a montagem traz a copia inteira do nucleo' \
  || quebra "a montagem nao traz a copia inteira: $(lista "$tmp/$nucleo_rel" | tr '\n' ' ')"

# PATH sem node: um diretorio so com os comandos que o helper usa, cada um um
# embrulho para o binario real (link simbolico nao e confiavel no Git Bash)
mkdir -p "$aux/sem-node"
for c in git mktemp rm mkdir cat grep cygpath find sort sed; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$p" > "$aux/sem-node/$c"; chmod +x "$aux/sem-node/$c"
done
sem_node() { (cd "$tmp" && PATH="$aux/sem-node" "$BASH" "$leitor" "$@"); }
tem_node=0; command -v node >/dev/null 2>&1 && tem_node=1

# o exemplo da emenda de 2026-10-19 (secao 5)
conselho='{
  "expx_fatiamento": 2,
  "revisao_por_task": { "modo": "obrigatoria" },
  "entrega": "por_sprint",
  "merge_automatico": { "ativo": true, "caminhos_protegidos": ["^src/pagamentos/"] },
  "revisor_bot": ["codeant-ai[bot]"],
  "excluir_da_revisao": [
    { "padrao": "^fixtures/candidatos/", "classe": "copia", "origem": "scripts/atualizar-candidatos.sh", "motivo": "copia das skills candidatas, revisada no repositorio de origem" }
  ]
}'
# a configuracao de antes da emenda (versao 1, com legibilidade)
conselho_v1='{
  "expx_fatiamento": 1,
  "justificativa": "sprint de ~8 tasks revisadas uma a uma",
  "legibilidade": { "pr_linhas": 2500, "pr_arquivos": 80, "commit_linhas": 300 },
  "revisao_por_task": { "modo": "obrigatoria" },
  "entrega": "por_sprint"
}'
msg_fatia() { printf 'leitor-do-projeto: `%s` não é mais lida (limites do CodeAnt, fixos: emenda de 2026-10-19); remova-a do ambiente' "$1"; }

# 1. sem arquivo: os padroes, sem node no PATH, sem FATIA_ e com os numeros do perfil
saida="$(sem_node)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'EXPX_ENTREGA=por_trabalho'*'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
  && printf '%s\n' "$saida" | grep -qxF 'EXPX_L2_BYTES=204800' \
  && ! printf '%s\n' "$saida" | grep -q 'FATIA_' \
  && passa 'sem arquivo: padroes sem node, sem FATIA_ e com EXPX_L2_BYTES=204800' \
  || quebra "sem arquivo, sem node (rc $rc): $saida"

# 2. os padroes do helper sao os do leitor do nucleo: as mesmas doze chaves, os mesmos valores
# (so EXPX_CAMINHOS_PROTEGIDOS e excecao: vazio de proposito, merge automatico desligado)
if [ "$tem_node" = 1 ]; then
  mkdir -p "$aux/vazio"
  do_nucleo="$(node "$tmp/$nucleo_rel/expx-fatiamento.mjs" --raiz "$aux/vazio" --formato env)"
  do_helper="$(sem_node)"
  difere=''
  while IFS= read -r linha; do
    k="${linha%%=*}"
    case "$k" in EXPX_CAMINHOS_PROTEGIDOS) continue ;; esac
    printf '%s\n' "$do_nucleo" | grep -qxF -- "$linha" || difere="$difere $k"
  done <<< "$do_helper"
  chaves() { printf '%s\n' "$1" | sed 's/=.*//'; }
  [ -z "$difere" ] && [ "$(chaves "$do_helper")" = "$(chaves "$do_nucleo")" ] \
    && [ "$(chaves "$do_helper" | wc -l | tr -d ' ')" = 12 ] \
    && passa 'os padroes do helper sao os do leitor do nucleo (doze chaves)' \
    || quebra "padroes do helper diferem do nucleo em:$difere | helper: $(chaves "$do_helper" | tr '\n' ' ')| nucleo: $(chaves "$do_nucleo" | tr '\n' ' ')"
else
  passa 'os padroes do helper sao os do leitor do nucleo (sem node)'
fi

# 3. FATIA_* no ambiente: sai 1, com a mensagem exata por variavel, sem arquivo e sem node;
# definida e vazia tambem
(cd "$tmp" && FATIA_MAX_LINHAS_PR=400 PATH="$aux/sem-node" "$BASH" "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -qxF "$(msg_fatia FATIA_MAX_LINHAS_PR)" "$aux/err" \
  && passa 'FATIA_MAX_LINHAS_PR no ambiente: sai 1 com a mensagem exata, sem arquivo e sem node' \
  || quebra "FATIA_MAX_LINHAS_PR no ambiente: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
(cd "$tmp" && FATIA_IGNORAR= PATH="$aux/sem-node" "$BASH" "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -qxF "$(msg_fatia FATIA_IGNORAR)" "$aux/err" \
  && passa 'FATIA_IGNORAR vazia tambem: sai 1 com a mensagem exata' \
  || quebra "FATIA_IGNORAR vazia: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"

# 4. --rev de um commit sem o arquivo, com o arquivo so no disco: os padroes, sem node
printf '%s\n' "$conselho" > "$tmp/.expx/fatiamento.json"
saida="$(sem_node --rev HEAD)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
  && passa '--rev sem o arquivo no commit, com arquivo so no disco: padroes' \
  || quebra "--rev sem o arquivo no commit (rc $rc): $saida"

# daqui em diante, o arquivo existe no commit
g add -A; g commit -q -m config

# 5. arquivo v2 valido: repassa o leitor
if [ "$tem_node" = 1 ]; then
  saida="$(cd "$tmp" && bash "$leitor")"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -qxF 'EXPX_EXCLUIR_DA_REVISAO=^fixtures/candidatos/' \
    && printf '%s\n' "$saida" | grep -qxF 'EXPX_ENTREGA=por_sprint' \
    && printf '%s\n' "$saida" | grep -qxF 'EXPX_FATIAMENTO_ORIGEM=projeto' \
    && passa 'arquivo v2 valido: repassa o leitor' \
    || quebra "arquivo v2 valido (rc $rc): $saida"
else
  passa 'arquivo v2 valido: repassa o leitor (sem node)'
fi

# 6. FATIA_* no ambiente com arquivo valido tambem: sai 1, nunca le
(cd "$tmp" && FATIA_EXCECAO='movimento mecanico' bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -qxF "$(msg_fatia FATIA_EXCECAO)" "$aux/err" \
  && passa 'FATIA_EXCECAO com arquivo valido: sai 1 com a mensagem exata' \
  || quebra "FATIA_EXCECAO com arquivo valido: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"

# 7. arquivo invalido: sai 1, stdout vazio, stderr do leitor com a chave
if [ "$tem_node" = 1 ]; then
  printf '{ "expx_fatiamento": 2, "entrega": "por_dia" }\n' > "$tmp/.expx/fatiamento.json"
  (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
  [ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -q 'entrega' "$aux/err" \
    && passa 'arquivo invalido: sai 1, stdout vazio, stderr cita a chave' \
    || quebra "arquivo invalido: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
  # a versao 1 (de antes da emenda) e recusada com a migracao e a chave removida
  printf '%s\n' "$conselho_v1" > "$tmp/.expx/fatiamento.json"
  (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
  [ "$rc" = 1 ] && [ ! -s "$aux/out" ] && grep -q 'migre para 2' "$aux/err" && grep -q 'legibilidade' "$aux/err" \
    && passa 'versao 1: sai 1, stdout vazio, stderr com "migre para 2" e a chave legibilidade' \
    || quebra "versao 1: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
  g checkout -q -- .expx/fatiamento.json
else
  passa 'arquivo invalido e versao 1: sai 1 (sem node)'
fi

# 8. arquivo presente e leitor ausente, ou nucleo antigo (sem expx-limites.mjs, sem perfis/):
# sai 3 e manda atualizar o expx, antes de chamar node (o node espiao marca se foi chamado)
mkdir -p "$aux/node-espia"
printf '#!/usr/bin/env bash\n: > "%s/node-chamado"\nexit 1\n' "$aux" > "$aux/node-espia/node"; chmod +x "$aux/node-espia/node"
for falta in expx-fatiamento.mjs expx-limites.mjs perfis; do
  mv "$tmp/$nucleo_rel/$falta" "$aux/guardado"; rm -f "$aux/node-chamado"
  saida="$(cd "$tmp" && PATH="$aux/node-espia:$PATH" bash "$leitor" 2>&1)"; rc=$?
  mv "$aux/guardado" "$tmp/$nucleo_rel/$falta"
  [ "$rc" = 3 ] && [ ! -e "$aux/node-chamado" ] && case "$saida" in *'expx update'*) true ;; *) false ;; esac \
    && passa "nucleo sem $falta: sai 3 e cita expx update" \
    || quebra "nucleo sem $falta (rc $rc): $saida"
done

# 9. arquivo presente e node ausente: sai 3, nunca os padroes
saida="$(sem_node 2>&1)"; rc=$?
[ "$rc" = 3 ] && case "$saida" in *'expx update'*) true ;; *) false ;; esac \
  && passa 'arquivo presente e node ausente: sai 3' \
  || quebra "arquivo presente e node ausente (rc $rc): $saida"

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

# 10. --rev le o arquivo do commit, nao o do disco (o E7 mede o SHA publicado)
if [ "$tem_node" = 1 ]; then
  printf '%s\n' "${conselho//fixtures\/candidatos/gerado}" > "$tmp/.expx/fatiamento.json"
  saida="$(cd "$tmp" && bash "$leitor" --rev HEAD)"; rc=$?
  g checkout -q -- .expx/fatiamento.json
  [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -qxF 'EXPX_EXCLUIR_DA_REVISAO=^fixtures/candidatos/' \
    && passa '--rev le o arquivo do commit, nao o do disco' \
    || quebra "--rev leu o disco (rc $rc): $saida"
else
  passa '--rev le o arquivo do commit (sem node)'
fi

# 11. --rev confere a pasta inteira do nucleo do commit contra a instalada: igual, le; leitor,
# perfil ou arquivo a mais em perfis/ diferentes: nenhum dos dois decide, sai 3
if [ "$tem_node" = 1 ]; then
  (cd "$tmp" && bash "$leitor" --rev HEAD > "$aux/out" 2>&1); rc=$?
  [ "$rc" = 0 ] && passa '--rev com a pasta do nucleo igual a instalada: le' \
    || quebra "--rev com a pasta igual a instalada: rc $rc: $(cat "$aux/out")"
else
  passa '--rev com a pasta do nucleo igual a instalada (sem node)'
fi
cp "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
printf 'process.stdout.write("EXPX_FATIAMENTO_ORIGEM=padrao\\n")\n' > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
saida="$(cd "$tmp" && bash "$leitor" --rev HEAD 2>&1)"; rc=$?
cp "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
[ "$rc" = 3 ] && case "$saida" in *'difere do instalado'*) true ;; *) false ;; esac \
  && passa '--rev com leitor do commit diferente do instalado: sai 3' || quebra "--rev com leitores diferentes (rc $rc): $saida"
perfil_outro="$(commit_com 100644 "$(blob '{ "outro": true }')" "$nucleo_rel/perfis/codeant-app.json")"
(cd "$tmp" && bash "$leitor" --rev "$perfil_outro" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'difere do instalado' "$aux/err" \
  && passa '--rev com perfil do commit diferente do instalado: sai 3' \
  || quebra "--rev com perfil diferente: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
perfil_a_mais="$(commit_com 100644 "$(blob '{}')" "$nucleo_rel/perfis/codeant-cli-9.9.9.json")"
(cd "$tmp" && bash "$leitor" --rev "$perfil_a_mais" > "$aux/out" 2> "$aux/err"); rc=$?
[ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'difere do instalado' "$aux/err" \
  && passa '--rev com um arquivo a mais em perfis/ no commit: sai 3' \
  || quebra "--rev com arquivo a mais em perfis/: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
# blob versionado com CRLF (commitado com autocrlf=false) e o mesmo arquivo instalado, num
# clone com core.autocrlf=true: o git o ve igual (status limpo), e o helper tambem, nunca 3
if [ "$tem_node" = 1 ]; then
  perfil="$nucleo_rel/perfis/codeant-app.json"; cp "$tmp/$perfil" "$aux/perfil.json"
  sed 's/$/\r/' "$aux/perfil.json" > "$tmp/$perfil"
  perfil_crlf="$(commit_com 100644 "$(g hash-object -w --no-filters -- "$perfil")" "$perfil")"
  g config core.autocrlf true
  (cd "$tmp" && bash "$leitor" --rev "$perfil_crlf" > "$aux/out" 2> "$aux/err"); rc=$?
  g config --unset core.autocrlf; cp "$aux/perfil.json" "$tmp/$perfil"
  [ "$rc" = 0 ] && passa '--rev com blob CRLF no commit e o mesmo arquivo instalado (autocrlf=true): le' \
    || quebra "--rev com blob CRLF igual ao instalado: rc $rc, stderr '$(cat "$aux/err")'"
else
  passa '--rev com blob CRLF igual ao instalado (sem node)'
fi
# e o inverso: arquivo instalado que o commit nao tem
printf '{}\n' > "$tmp/$nucleo_rel/perfis/codeant-cli-9.9.9.json"
(cd "$tmp" && bash "$leitor" --rev HEAD > "$aux/out" 2> "$aux/err"); rc=$?
rm -f "$tmp/$nucleo_rel/perfis/codeant-cli-9.9.9.json"
[ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'difere do instalado' "$aux/err" \
  && passa '--rev com um arquivo instalado a mais que o commit: sai 3' \
  || quebra "--rev com arquivo instalado a mais: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"

# 12. link quebrado no lugar do arquivo: presente e invalido, nunca os padroes
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

# 13. o consumo seguro exporta para processo filho
if [ "$tem_node" = 1 ]; then
  filho="$(cd "$tmp" && fatia="$(bash "$leitor" --rev HEAD)" || exit 9; set -a; eval "$fatia"; set +a
           bash -c 'printf %s "$EXPX_EXCLUIR_DA_REVISAO"')"
  [ "$filho" = '^fixtures/candidatos/' ] && passa 'consumo seguro exporta para processo filho' \
    || quebra "o processo filho viu EXPX_EXCLUIR_DA_REVISAO='$filho'"
else
  passa 'consumo seguro exporta para processo filho (sem node)'
fi

# 14. uso errado: 64, antes de tudo (tambem antes da FATIA_)
(cd "$tmp" && bash "$leitor" --nada >/dev/null 2>&1); rc=$?
[ "$rc" = 64 ] && passa 'argumento desconhecido sai 64' || quebra "argumento desconhecido saiu $rc"
(cd "$tmp" && FATIA_IGNORAR=x bash "$leitor" --nada >/dev/null 2>&1); rc=$?
[ "$rc" = 64 ] && passa 'argumento desconhecido com FATIA_ no ambiente: 64 primeiro' \
  || quebra "argumento desconhecido com FATIA_ no ambiente saiu $rc"

# 15. revisao ou raiz que nao resolvem: sai 2, stdout vazio, nunca os padroes
for opc in --rev --raiz; do # o valor vai como um argumento so: o TMPDIR pode ter espaco
  [ "$opc" = --rev ] && val=nao-existe || val="$aux/nao-existe"
  (cd "$tmp" && bash "$leitor" "$opc" "$val" > "$aux/out" 2>/dev/null); rc=$?
  [ "$rc" = 2 ] && [ ! -s "$aux/out" ] && passa "$opc que nao resolve: sai 2" \
    || quebra "$opc que nao resolve: rc $rc, stdout '$(cat "$aux/out")'"
done

# 16. leitor que imprime FATIA_ (leitor antigo), ou que nao imprime todas as chaves: sai 3
# (expx update), nunca o que ele imprimiu
if [ "$tem_node" = 1 ]; then
  cp "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
  completo="$(cd "$tmp" && bash "$leitor")"
  for caso in antigo incompleto; do
    if [ "$caso" = antigo ]; then texto="FATIA_MAX_LINHAS_PR=1"$'\n'"$completo"; else texto='EXPX_FATIAMENTO_ORIGEM=projeto'; fi
    node -e 'process.stdout.write("process.stdout.write(" + JSON.stringify(process.argv[1] + "\n") + ")\n")' "$texto" \
      > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
    (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
    [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'expx update' "$aux/err" \
      && passa "leitor $caso (FATIA_ ou chave faltando): sai 3" \
      || quebra "leitor $caso: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
  done
  cp "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
else
  passa 'leitor antigo ou incompleto: sai 3 (sem node)'
fi

# 17. --rev com .expx/fatiamento.json que nao e arquivo no commit: presente e invalido (sai 1)
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

# 18. o que o leitor do nucleo ve como presente (o lstat nao da ENOENT) nunca vira os
# padroes: gitlink sem objeto no lugar do arquivo e `.expx` que nao e pasta (ENOTDIR)
if [ "$tem_node" = 1 ]; then
  gitlink="$(commit_com 160000 1111111111111111111111111111111111111111 .expx/fatiamento.json)"
  expx_blob="$(commit_com 100644 "$(blob '{}')" .expx .expx)"
  for caso in "gitlink $gitlink" ".expx-arquivo $expx_blob"; do
    (cd "$tmp" && bash "$leitor" --rev "${caso#* }" > "$aux/out" 2>/dev/null); rc=$?
    [ "$rc" = 1 ] && [ ! -s "$aux/out" ] && passa "--rev com ${caso%% *}: presente e invalido (sai 1)" \
      || quebra "--rev com ${caso%% *}: rc $rc, stdout '$(cat "$aux/out")'"
  done
else
  passa '--rev com gitlink ou .expx arquivo (sem node)'
fi
mkdir -p "$aux/expx-arquivo"; printf '{}\n' > "$aux/expx-arquivo/.expx"
(bash "$leitor" --raiz "$aux/expx-arquivo" > "$aux/out" 2>/dev/null); rc=$?
[ "$rc" = 3 ] && [ ! -s "$aux/out" ] && passa '.expx arquivo no disco: presente, sem leitor possivel (sai 3)' \
  || quebra ".expx arquivo no disco: rc $rc, stdout '$(cat "$aux/out")'"

# 19. leitor que o node nao carrega (sintaxe, modulo que falta) sai 1 como o arquivo
# invalido, mas sem a linha `expx-fatiamento: ` do contrato do leitor: sai 3, nunca 1
if [ "$tem_node" = 1 ]; then
  cp "$tmp/$nucleo_rel/expx-fatiamento.mjs" "$aux/leitor.mjs"
  for caso in 'sintaxe:syntax error(' 'modulo:import "node:nao-existe";'; do
    printf '%s\n' "${caso#*:}" > "$tmp/$nucleo_rel/expx-fatiamento.mjs"
    (cd "$tmp" && bash "$leitor" > "$aux/out" 2> "$aux/err"); rc=$?
    [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && grep -q 'expx update' "$aux/err" \
      && passa "leitor que nao carrega (${caso%%:*}): sai 3" \
      || quebra "leitor que nao carrega (${caso%%:*}): rc $rc, stderr '$(cat "$aux/err")'"
  done
  cp "$aux/leitor.mjs" "$tmp/$nucleo_rel/expx-fatiamento.mjs"
else
  passa 'leitor que nao carrega: sai 3 (sem node)'
fi

# 20. `.expx` que nao se atravessa (sem permissao): o lstat do nucleo da EACCES, nao
# ENOENT, e o arquivo e presente; nunca os padroes
mkdir -p "$aux/fechada/.expx"; chmod 000 "$aux/fechada/.expx" 2>/dev/null
if [ ! -x "$aux/fechada/.expx" ]; then
  (bash "$leitor" --raiz "$aux/fechada" > "$aux/out" 2>/dev/null); rc=$?
  [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && passa '.expx sem permissao de travessia: presente (sai 3)' \
    || quebra ".expx sem permissao de travessia: rc $rc, stdout '$(cat "$aux/out")'"
else
  passa '.expx sem permissao: pulado, o sistema ou o root ignoram o chmod (o CI em Linux cobre)'
fi
chmod 755 "$aux/fechada/.expx" 2>/dev/null

# 21. --nucleo-da-rev (D3 e merge automatico): o leitor executado e o da arvore de <rev>,
# materializado do commit num temporario, nunca o instalado nem o do disco
(cd "$tmp" && bash "$leitor" --nucleo-da-rev > "$aux/out" 2>/dev/null); rc=$?
[ "$rc" = 64 ] && [ ! -s "$aux/out" ] && passa '--nucleo-da-rev sem --rev: sai 64' \
  || quebra "--nucleo-da-rev sem --rev: rc $rc, stdout '$(cat "$aux/out")'"
# commit sobre o HEAD sem um caminho (arquivo ou pasta): commit_sem <caminho>
commit_sem() {
  local idx="$aux/indice"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" g read-tree HEAD
  GIT_INDEX_FILE="$idx" g rm -r -q --cached -- "$1"
  g commit-tree "$(GIT_INDEX_FILE="$idx" g write-tree)" -p HEAD -m "sem $1"
}
if [ "$tem_node" = 1 ]; then
  completo="$(cd "$tmp" && bash "$leitor" --rev HEAD)"
  texto="$completo"$'\n''EXPX_MARCA_DA_BASE=1'
  js="$(node -e 'process.stdout.write("process.stdout.write(" + JSON.stringify(process.argv[1] + "\n") + ")\n")' "$texto")"
  marcado="$(commit_com 100644 "$(blob "$js")" "$nucleo_rel/expx-fatiamento.mjs")"
  # o instalado fica fora do disco: o leitor da base vem do commit, nao da pasta instalada
  mv "$tmp/.expx/marketplace" "$aux/marketplace"
  (cd "$tmp" && bash "$leitor" --rev "$marcado" --nucleo-da-rev > "$aux/out" 2> "$aux/err"); rc=$?
  mv "$aux/marketplace" "$tmp/.expx/marketplace"
  [ "$rc" = 0 ] && grep -qxF 'EXPX_MARCA_DA_BASE=1' "$aux/out" && grep -qxF 'EXPX_ENTREGA=por_sprint' "$aux/out" \
    && passa 'nucleo da base diferente do instalado: vale o da base, sem o instalado no disco' \
    || quebra "nucleo da base diferente do instalado: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
  (cd "$tmp" && bash "$leitor" --rev "$marcado" > "$aux/out" 2>/dev/null); rc=$?
  [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && passa 'o mesmo commit sem --nucleo-da-rev: sai 3 (difere do instalado)' \
    || quebra "o mesmo commit sem --nucleo-da-rev: rc $rc, stdout '$(cat "$aux/out")'"
else
  passa 'nucleo da base diferente do instalado: vale o da base (sem node)'
fi
# base com o arquivo e sem a pasta do nucleo, nucleo antigo na base, ou entrada que nao e
# arquivo comum (link, gitlink) na pasta: sai 3, sem chamar node
sem_pasta="$(commit_sem "$nucleo_rel")"
sem_limites="$(commit_sem "$nucleo_rel/expx-limites.mjs")"
link_nucleo="$(commit_com 120000 "$(blob ../../../../../../../../fora.mjs)" "$nucleo_rel/expx-limites.mjs" "$nucleo_rel/expx-limites.mjs")"
gitlink_nucleo="$(commit_com 160000 1111111111111111111111111111111111111111 "$nucleo_rel/perfis/sub")"
for caso in "sem-pasta|$sem_pasta|não versiona o núcleo" "nucleo-antigo|$sem_limites|expx update" \
            "link|$link_nucleo|não é arquivo comum" "gitlink|$gitlink_nucleo|não é arquivo comum"; do
  nome="${caso%%|*}"; resto="${caso#*|}"; c="${resto%%|*}"; msg="${resto#*|}"
  rm -f "$aux/node-chamado"
  (cd "$tmp" && PATH="$aux/node-espia:$PATH" bash "$leitor" --rev "$c" --nucleo-da-rev > "$aux/out" 2> "$aux/err"); rc=$?
  [ "$rc" = 3 ] && [ ! -s "$aux/out" ] && [ ! -e "$aux/node-chamado" ] && grep -qF "$msg" "$aux/err" \
    && passa "--nucleo-da-rev com base $nome: sai 3 sem node ($msg)" \
    || quebra "--nucleo-da-rev com base $nome: rc $rc, stdout '$(cat "$aux/out")', stderr '$(cat "$aux/err")'"
done
# base sem o arquivo (e sem a pasta do nucleo): os padroes, sem node
idx="$aux/indice"; rm -f "$idx"; GIT_INDEX_FILE="$idx" g read-tree --empty
sem_nada="$(g commit-tree "$(GIT_INDEX_FILE="$idx" g write-tree)" -m vazio)"
saida="$(sem_node --rev "$sem_nada" --nucleo-da-rev)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'EXPX_FATIAMENTO_ORIGEM=padrao'*) true ;; *) false ;; esac \
  && passa '--nucleo-da-rev com base sem o arquivo nem o nucleo: padroes, sem node' \
  || quebra "--nucleo-da-rev com base sem o arquivo: rc $rc: $saida"

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
