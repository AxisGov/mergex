#!/usr/bin/env bash
#
# O E7 mede o PR contra o `expx-fatiamento` antes de abrir (07-abertura-pr.md,
# Passo 1.5). Confere que o passo existe, vem antes da abertura, e que o script
# da skill reprova PR grande e deixa passar PR pequeno.
#
# Uso: bash scripts/ci/test-fatiamento-e7.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$raiz/.claude/skills/mergex/scripts/fatiamento-da-pr.sh"
e7="$raiz/.claude/skills/mergex/references/07-abertura-pr.md"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }

[ -f "$script" ] && passa 'o script de fatiamento existe na skill' || quebra 'fatiamento-da-pr.sh ausente'
grep -Fq 'COPIA, nao dependencia' "$script" \
  && passa 'o script declara que e copia do verificador do ExpxDev' \
  || quebra 'o script nao declara de onde vem'

l15="$(grep -n '^## Passo 1.5' "$e7" | head -1 | cut -d: -f1)"
l2="$(grep -n '^## Passo 2 ' "$e7" | head -1 | cut -d: -f1)"
if [ -n "$l15" ] && [ -n "$l2" ] && [ "$l15" -lt "$l2" ]; then
  passa 'o Passo 1.5 (fatiamento) vem antes do Passo 2 (abrir o PR)'
else
  quebra 'o Passo 1.5 nao existe ou nao vem antes da abertura'
fi
# o FATIA_IGNORAR que o E7 monta, avaliando o trecho real: sem padrao do projeto, e com um
# (que soma ao do E7, nunca o substitui — os artefatos de metodo saem da medida sempre)
ign_trecho="$(sed -n '/^e7_ignorar=/p; /^FATIA_IGNORAR=/{s/ \\$//;p;}' "$e7")"
ign_e7="$(unset FATIA_IGNORAR; eval "$ign_trecho"; printf '%s' "${FATIA_IGNORAR:-}")"
ign_proj="$(FATIA_IGNORAR='^extra/'; eval "$ign_trecho"; printf '%s' "$FATIA_IGNORAR")"
case "$ign_proj" in
  '^extra/|'*'docs/(sprintx|entregas|eventos)/'*) passa 'o FATIA_IGNORAR do projeto soma ao do E7, sem tirar os artefatos de metodo' ;;
  *) quebra "o FATIA_IGNORAR do projeto substitui o do E7: '$ign_proj'" ;;
esac
[ -n "$ign_e7" ] && passa 'o E7 declara o FATIA_IGNORAR do projeto' \
  || quebra 'o E7 herda o FATIA_IGNORAR do ExpxDev (fixtures/candidatos fora da conta)'
grep -Fq 'fatiamento-da-pr.sh "$base" "$publicado"' "$e7" \
  && passa 'o E7 mede o SHA publicado contra a base' \
  || quebra 'o E7 nao chama o script sobre o SHA publicado'
grep -Fq 'o E7 **não abre o PR**' "$e7" \
  && passa 'violacao impede a abertura' \
  || quebra 'o E7 nao diz que a violacao impede a abertura'
grep -Fq 'Saída `2` (ou qualquer outra que não `0` nem `1`): o E7 **não abre o PR**' "$e7" \
  && grep -Fq '| `fatiamento-da-pr.sh` saiu `2`' "$e7" \
  && passa 'medicao impossivel (saida 2) tambem impede a abertura' \
  || quebra 'o E7 so trata as saidas 0 e 1 do fatiamento; a 2 (nao mediu) abriria sem medir'
grep -Fq 'rb="$remoto"; bb="<branch_base>"' "$e7" && grep -Fq 'git fetch "$rb" "$bb"' "$e7" \
  && grep -Fq 'git rev-parse --verify "FETCH_HEAD^{commit}"' "$e7" \
  && passa 'a base vem do remoto do upstream, buscada agora' \
  || quebra 'a base nao e buscada no remoto do upstream (ref antiga ou fork mediria errado)'
grep -Fq 'gh pr create --base "$bb"' "$e7" && ! grep -Fq 'gh pr create --base <branch-base>' "$e7" \
  && passa 'o gh pr create recebe a base sem o remoto ($bb do passo 1.5)' \
  || quebra 'o gh pr create recebe a branch_base crua (upstream/main nao e branch no GitHub)'
# o passo 1 reconhece `glab`: o passo 2 tem de ter o comando dele, ou o GitLab cai no manual
grep -Fq 'glab mr create --target-branch "$bb"' "$e7" && grep -Fq -- '--draft --yes' "$e7" \
  && passa 'o GitLab (glab) tem o comando de abertura, com a base do passo 1.5 e sem confirmacao interativa' \
  || quebra 'o passo 1 reconhece glab, mas o passo 2 so tem o comando do gh'
grep -Fq 'o passo 1.5 roda do mesmo jeito, e só depois dele vá para o passo 3' "$e7" \
  && passa 'servico sem ferramenta tambem passa pela medicao' \
  || quebra 'o caminho manual (passo 3) contorna a medicao'

tmp="$(mktemp -d)"; aux="$(mktemp -d)"; trap 'rm -rf "$tmp" "$aux"' EXIT
g() { git -C "$tmp" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base
g switch -q -c pequeno
printf 'linha\n%.0s' $(seq 1 30) > "$tmp/a.md"; g add -A; g commit -q -m pequeno
if (cd "$tmp" && bash "$script" main pequeno >/dev/null 2>&1); then passa 'PR pequeno passa'; else quebra 'PR pequeno reprovou'; fi
g switch -q -c grande main
for i in 1 2 3; do printf 'linha\n%.0s' $(seq 1 200) > "$tmp/g$i.md"; g add -A; g commit -q -m "parte $i"; done
if (cd "$tmp" && bash "$script" main grande >/dev/null 2>&1); then quebra 'PR de 600 linhas passou'; else passa 'PR de 600 linhas reprova (F2)'; fi
# a excecao declarada pelo desenvolvedor chega ao script mesmo sem `export`: o
# trecho real do E7, rodado com FATIA_EXCECAO so como variavel de shell
exc_trecho="$(sed -n '/^e7_ignorar=/,/fatiamento-da-pr\.sh "\$base"/p' "$e7" \
  | sed 's#bash \.claude/skills/mergex/scripts/fatiamento-da-pr\.sh#bash "$script"#')"
saida="$(cd "$tmp" && unset FATIA_EXCECAO FATIA_IGNORAR && FATIA_EXCECAO='movimento mecanico' \
  && base=main && publicado=grande && eval "$exc_trecho" 2>&1)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *"excecao declarada: movimento mecanico"*) true ;; *) false ;; esac \
  && passa 'FATIA_EXCECAO nao exportada chega ao script pelo trecho do E7 (F2 vira aviso)' \
  || quebra "FATIA_EXCECAO nao exportada nao chegou ao script (rc $rc): $saida"
# F3: um commit so de 350 linhas, num PR que cabe em F2
g switch -q -c commit-grande main
printf 'linha\n%.0s' $(seq 1 350) > "$tmp/c.md"; g add -A; g commit -q -m "commit grande"
saida="$(cd "$tmp" && bash "$script" main commit-grande 2>&1)" && quebra 'commit de 350 linhas passou' \
  || { case "$saida" in *"F3:"*) passa 'commit de 350 linhas reprova (F3)' ;; *) quebra "reprovou, mas nao por F3: $saida" ;; esac; }
# F4: arquivo novo acima de 4.000 linhas, com F2 e F3 folgados
g switch -q -c arquivo-grande main
printf 'a\n%.0s' $(seq 1 4100) > "$tmp/longo.txt"; g add -A; g commit -q -m "arquivo longo"
saida="$(cd "$tmp" && FATIA_MAX_LINHAS_PR=9000 FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main arquivo-grande 2>&1)" && quebra 'arquivo de 4.100 linhas passou' \
  || { case "$saida" in *"F4:"*) passa 'arquivo de 4.100 linhas reprova (F4)' ;; *) quebra "reprovou, mas nao por F4: $saida" ;; esac; }
# no projeto do desenvolvedor, fixtures/candidatos/ e codigo como outro qualquer
g switch -q -c candidatos main
mkdir -p "$tmp/fixtures/candidatos"
printf 'linha\n%.0s' $(seq 1 450) > "$tmp/fixtures/candidatos/x.md"; g add -A; g commit -q -m candidatos
saida="$(cd "$tmp" && FATIA_IGNORAR="$ign_e7" FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main candidatos 2>&1)" \
  && quebra 'com o FATIA_IGNORAR do E7, 450 linhas em fixtures/candidatos passaram' \
  || { case "$saida" in *"F2:"*) passa 'com o FATIA_IGNORAR do E7, fixtures/candidatos conta (F2)' ;; *) quebra "reprovou, mas nao por F2: $saida" ;; esac; }
# artefatos de metodo (docs/sprintx, docs/entregas, docs/eventos) ficam fora da medida;
# o codigo ao lado deles continua contando
g switch -q -c metodo main
mkdir -p "$tmp/docs/sprintx/features/x/sprint-01" "$tmp/docs/entregas/x" "$tmp/docs/eventos"
for i in $(seq 1 25); do printf 'linha\n%.0s' $(seq 1 40) > "$tmp/docs/sprintx/features/x/sprint-01/a$i.md"; done
printf 'linha\n%.0s' $(seq 1 300) > "$tmp/docs/entregas/x/ENTREGA.md"
printf '{}\n%.0s' $(seq 1 300) > "$tmp/docs/eventos/x.jsonl"
printf 'codigo\n%.0s' $(seq 1 50) > "$tmp/app.ts"; g add -A; g commit -q -m metodo
if (cd "$tmp" && FATIA_IGNORAR="$ign_e7" FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main metodo >/dev/null 2>&1); then
  passa 'artefatos de metodo (27 arquivos, 1600 linhas) ficam fora do F2 do E7'
else
  quebra 'os artefatos de metodo contaram no F2 do E7'
fi
g switch -q -c metodo-e-codigo metodo
printf 'codigo\n%.0s' $(seq 1 400) > "$tmp/app2.ts"; g add -A; g commit -q -m codigo
saida="$(cd "$tmp" && FATIA_IGNORAR="$ign_e7" FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main metodo-e-codigo 2>&1)" \
  && quebra 'o codigo ao lado dos artefatos de metodo saiu da conta' \
  || { case "$saida" in *"F2:"*) passa 'o codigo ao lado dos artefatos de metodo continua contando (F2)' ;; *) quebra "reprovou, mas nao por F2: $saida" ;; esac; }

# medicao que falha nao e PR limpo: um objeto ausente faz o `git diff` falhar
# depois de as refs resolverem, e o script sai 2 (nao mediu), nunca 0
falha_ao_medir() { # <desc> <branch> — espera saida 2
  local rc
  (cd "$tmp" && bash "$script" main "$2" >/dev/null 2>&1); rc=$?
  [ "$rc" = 2 ] && passa "$1: sai 2" || quebra "$1: saiu $rc, esperado 2 (nao mediu)"
}
sem_objeto() { # <branch> <caminho> — apaga o blob solto do caminho na ponta
  local o; o="$(git -C "$tmp" rev-parse "$1:$2")"
  rm -f "$tmp/.git/objects/${o:0:2}/${o:2}"
}
g switch -q -c sem-blob-pr main
printf 'linha\n%.0s' $(seq 1 30) > "$tmp/perdido.md"; g add -A; g commit -q -m "blob que some"
sem_objeto sem-blob-pr perdido.md
falha_ao_medir 'git diff falha na PR inteira (F2)' sem-blob-pr
# F3: o blob some num commit do meio; a PR inteira mede, o commit nao
g switch -q -c sem-blob-commit main
printf 'linha\n%.0s' $(seq 1 350) > "$tmp/meio.md"; g add -A; g commit -q -m "commit de 350 linhas"
o_meio="$(git -C "$tmp" rev-parse HEAD:meio.md)"
printf 'curto\n' > "$tmp/meio.md"; g add -A; g commit -q -m "encurta"
rm -f "$tmp/.git/objects/${o_meio:0:2}/${o_meio:2}"
falha_ao_medir 'git diff falha num commit (F3)' sem-blob-commit
# renomeacao de fixtures/candidatos/ para caminho normal: o destino conta
g switch -q -c renomeia main
mkdir -p "$tmp/fixtures/candidatos" "$tmp/src"
printf 'linha %s\n' $(seq 1 450) > "$tmp/fixtures/candidatos/r.md"; g add -A; g commit -q -m "fixture"
g switch -q -c renomeia-pr renomeia
g mv fixtures/candidatos/r.md src/q.md
printf 'nova %s\n' $(seq 1 300) >> "$tmp/src/q.md"; g add -A; g commit -q -m "promove a fixture"
saida="$(cd "$tmp" && FATIA_MAX_LINHAS_PR=250 FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" renomeia renomeia-pr 2>&1)" \
  && quebra 'renomeacao de fixtures/candidatos para src/ ficou fora da conta' \
  || { case "$saida" in *"F2:"*) passa 'renomeacao de fixtures/candidatos para src/ conta pelo destino (F2)' ;; *) quebra "reprovou, mas nao por F2: $saida" ;; esac; }
# e no sentido contrario: codigo do produto movido PARA fixtures/candidatos/ com 450
# linhas a menos (55% iguais: ainda e renomeacao) conta as linhas removidas
g switch -q -c produto main
mkdir -p "$tmp/src" "$tmp/fixtures/candidatos"
printf 'linha %s\n' $(seq 1 1000) > "$tmp/src/p.md"; g add -A; g commit -q -m "produto"
g switch -q -c produto-pr produto
tail -n +451 "$tmp/src/p.md" > "$tmp/fixtures/candidatos/p.md"; rm "$tmp/src/p.md"
g add -A; g commit -q -m "tira o produto para a fixture"
saida="$(cd "$tmp" && unset FATIA_IGNORAR && bash "$script" produto produto-pr 2>&1)"
case "$saida" in
  *"PR com 450 linhas em 1 arquivo"*) passa 'renomeacao de src/ para fixtures/candidatos conta as linhas removidas (F2)' ;;
  *) quebra "renomeacao de src/ para fixtures/candidatos escondeu as linhas removidas: $saida" ;;
esac
# controle: renomeacao entre dois caminhos gerados continua fora da conta
g switch -q -c fixture-pr produto-pr
mkdir -p "$tmp/fixtures/candidatos/y"
tail -n +101 "$tmp/fixtures/candidatos/p.md" > "$tmp/fixtures/candidatos/y/p.md"; rm "$tmp/fixtures/candidatos/p.md"
g add -A; g commit -q -m "regenera a fixture"
saida="$(cd "$tmp" && unset FATIA_IGNORAR && bash "$script" produto-pr fixture-pr 2>&1)"
case "$saida" in
  *"PR com 0 linhas em 0 arquivo"*) passa 'renomeacao entre dois caminhos de fixtures/candidatos fica fora da conta' ;;
  *) quebra "renomeacao entre dois caminhos gerados entrou na conta: $saida" ;;
esac
# caminho que so PARECE renomeacao (` => ` no nome) nao e cortado ate o FATIA_IGNORAR
g switch -q -c seta main
mkdir -p "$tmp/docs"
if printf 'linha %s\n' $(seq 1 450) > "$tmp/docs/x => package-lock.json" 2>/dev/null; then
  g add -A; g commit -q -m "nome com seta"
  saida="$(cd "$tmp" && FATIA_MAX_LINHAS_PR=250 FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main seta 2>&1)" \
    && quebra "o arquivo 'docs/x => package-lock.json' saiu da conta como se fosse package-lock.json" \
    || { case "$saida" in *"F2:"*) passa "nome com ' => ' conta pelo caminho inteiro (F2)" ;; *) quebra "reprovou, mas nao por F2: $saida" ;; esac; }
else
  passa "nome com ' => ': pulado, o sistema de arquivos nao aceita '>' (o CI em Linux cobre)"
fi
# o lock no padrao do script casa o nome inteiro: `package-lock.json.backup` conta.
# Tamanhos diferentes (lock 300, copia 450): so "450 em 1" prova que e a copia que conta
# e o lock que sai; o inverso daria "300 em 1", os dois "750 em 2", nenhum "0 em 0".
g switch -q -c lock-backup main
mkdir -p "$tmp/web"
printf 'linha %s\n' $(seq 1 300) > "$tmp/web/package-lock.json"
printf 'linha %s\n' $(seq 1 450) > "$tmp/package-lock.json.backup"; g add -A; g commit -q -m "lock e copia do lock"
saida="$(cd "$tmp" && unset FATIA_IGNORAR && FATIA_MAX_LINHAS_COMMIT=9000 bash "$script" main lock-backup 2>&1)"
case "$saida" in
  *"PR com 450 linhas em 1 arquivo"*) passa 'o padrao do lock casa o nome inteiro: package-lock.json.backup conta, web/package-lock.json nao' ;;
  *) quebra "package-lock.json.backup saiu da conta (ou o lock entrou): $saida" ;;
esac
# e a raiz de historia sem pai (merge de historia sem relacao) mede contra a arvore vazia
g switch -q --orphan raiz-solta; printf 'linha\n%.0s' $(seq 1 350) > "$tmp/solta.md"; g add solta.md; g commit -q -m "raiz solta"
g switch -q -c com-raiz main; g merge -q --allow-unrelated-histories -m "junta raiz" raiz-solta
saida="$(cd "$tmp" && FATIA_MAX_LINHAS_PR=9000 bash "$script" main com-raiz 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *"F3:"*) true ;; *) false ;; esac \
  && passa 'commit raiz no intervalo e medido contra a arvore vazia (F3)' \
  || quebra "commit raiz no intervalo: saiu $rc: $saida"

# o trecho do E7 que resolve a base, rodado de verdade: branch_base com e sem o
# remoto no nome (a base informada pelo chamador no E0 pode vir `upstream/main`)
# O origin e um repositorio vazio de verdade: o nome curto `upstream/main` so vira
# remoto/branch depois de o ls-remote responder que `upstream/main` nao e branch dele
mkdir -p "$aux/clone"; git -C "$aux/clone" init -q
git init -q --bare "$aux/fork-vazio.git"
git -C "$aux/clone" remote add origin "$aux/fork-vazio.git"
git -C "$aux/clone" remote add upstream https://exemplo.invalid/principal.git
resolve_base() { # <branch_base> [dir] — imprime "<remoto> <branch>" como o E7 resolve
  sed -n '/^rb="\$remoto"/,/^if \[ "\$bb" = HEAD/p' "$e7" | sed '$d' | sed "s|<branch_base>|$1|" > "$aux/resolve.sh"
  (cd "${2:-$aux/clone}" && remoto=origin && . "$aux/resolve.sh" && printf '%s %s' "$rb" "$bb")
}
# ls-remote que falha (rede, credencial) nao prova que a branch nao existe: o E7
# para, em vez de trocar de remoto e medir contra a base errada
mkdir -p "$aux/clone-sem-rede"; git -C "$aux/clone-sem-rede" init -q
git -C "$aux/clone-sem-rede" remote add origin "$aux/nao-existe.git"
git -C "$aux/clone-sem-rede" remote add upstream "$aux/nao-existe.git"
r="$(resolve_base upstream/main "$aux/clone-sem-rede" 2>&1)"
case "$r" in
  *'o E7 não mede nem abre o PR'*) passa 'ls-remote que falha na conferencia do nome curto para o E7' ;;
  *) quebra "ls-remote que falha virou 'nao e branch' e o E7 seguiu: '$r'" ;;
esac
# `refs/heads/...` e ref explicita de branch: nunca e partida em remoto/branch, nem
# quando o primeiro segmento e um remoto configurado
for par in 'main|origin main' 'upstream/main|upstream main' \
           'refs/remotes/upstream/main|upstream main' 'feature/x|origin feature/x' \
           'refs/heads/upstream/main|origin upstream/main'; do
  r="$(resolve_base "${par%%|*}")"
  [ "$r" = "${par#*|}" ] && passa "branch_base ${par%%|*} busca em ${par#*|}" \
    || quebra "branch_base ${par%%|*} resolveu '$r', esperado '${par#*|}'"
done

# e o fetch de verdade: o E7 mede contra o que o remoto TEM agora, nao contra a
# ref de rastreio local (que fica velha num origin/HEAD buscado)
git init -q --bare -b main "$aux/principal.git"
git -C "$tmp" push -q "$aux/principal.git" main:main 2>/dev/null
git clone -q "$aux/principal.git" "$aux/dev" 2>/dev/null
git -C "$aux/dev" remote add upstream "$aux/principal.git"; git -C "$aux/dev" fetch -q upstream
# remoto com refspec estreito (como um clone --single-branch de outra branch): o
# fetch de main nao atualiza refs/remotes/estreito/main, que fica velha
git -C "$aux/dev" remote add estreito "$aux/principal.git"; git -C "$aux/dev" fetch -q estreito
git -C "$aux/dev" config remote.estreito.fetch '+refs/heads/outra:refs/remotes/estreito/outra'
# branch cujo primeiro segmento e um remoto configurado: `feature/x` existe no remoto
# do upstream e `feature` tambem e remoto. A branch existente vence; `feature/main`,
# que nao e branch do upstream, continua indo ao remoto `feature`
git -C "$tmp" push -q "$aux/principal.git" main:refs/heads/feature/x 2>/dev/null
git -C "$aux/dev" remote add feature "$aux/principal.git"
g switch -q -c avanca main; printf 'novo\n' > "$tmp/novo.txt"; g add -A; g commit -q -m avanca
git -C "$tmp" push -q "$aux/principal.git" avanca:main 2>/dev/null
atual="$(git -C "$aux/principal.git" rev-parse main)"
[ "$atual" != "$(git -C "$aux/dev" rev-parse refs/remotes/origin/HEAD)" ] \
  || quebra 'fixture: o remoto nao avancou depois do clone (o caso da ref velha nao seria testado)'
base_do_e7() { # <branch_base> — roda o trecho do E7 ate o calculo da base, imprime $base
  sed -n '/^rb="\$remoto"/,/^base=/p' "$e7" | sed "s|<branch_base>|$1|" > "$aux/base.sh"
  (cd "$aux/dev" && remoto=origin && . "$aux/base.sh" >/dev/null 2>&1 && printf '%s' "$base")
}
for bb in main origin/HEAD upstream/main refs/remotes/upstream/main estreito/main feature/main; do
  [ "$(base_do_e7 "$bb")" = "$atual" ] && passa "branch_base $bb mede contra a ponta atual do remoto" \
    || quebra "branch_base $bb mediu contra outra base (ref velha?)"
done
# origin/HEAD vira o NOME da branch padrao do remoto, nao `HEAD`: o `gh pr create
# --base "$bb"` e a instrucao manual do passo 3 recebem esse $bb, e `HEAD` nao e
# branch no servico. A padrao muda para `padrao` para nao passar por acaso com `main`
git -C "$aux/principal.git" branch padrao main
git -C "$aux/principal.git" symbolic-ref HEAD refs/heads/padrao
bb_do_e7() { # <branch_base> — roda o trecho do E7 ate o calculo da base, imprime $bb
  sed -n '/^rb="\$remoto"/,/^base=/p' "$e7" | sed "s|<branch_base>|$1|" > "$aux/bb.sh"
  (cd "$aux/dev" && remoto=origin && . "$aux/bb.sh" >/dev/null 2>&1 && printf '%s' "$bb")
}
for par in 'origin/HEAD|padrao' 'refs/remotes/upstream/HEAD|padrao' 'main|main' \
           'feature/x|feature/x' 'refs/heads/feature/x|feature/x' 'refs/remotes/feature/main|main'; do
  r="$(bb_do_e7 "${par%%|*}")"
  [ "$r" = "${par#*|}" ] && passa "branch_base ${par%%|*} abre o PR contra '${par#*|}'" \
    || quebra "branch_base ${par%%|*} deu bb='$r', esperado '${par#*|}' (o gh pr create receberia isso)"
done

# cada bloco do E7 roda numa chamada propria do shell (conselho #204, rodada 3): o do
# passo 1.5 nao herda $remoto nem $publicado dos pre-requisitos, e o do passo 2 nao herda
# o $bb do passo 1.5. Os blocos reais, extraidos do reference, rodam cada um num bash novo
bloco_do_e7() { # <trecho> — imprime o bloco cercado do E7 que contem o trecho
  awk -v t="$1" '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                          dentro = 1; buf = ""; achou = 0; next }
                 dentro { buf = buf $0 "\n"; if (index($0, t)) achou = 1 }' "$e7"
}
git init -q --bare -b main "$aux/m2-remoto.git"
git clone -q "$aux/m2-remoto.git" "$aux/m2-dev" 2>/dev/null
d() { git -C "$aux/m2-dev" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
printf 'base\n' > "$aux/m2-dev/base.txt"; d add -A; d commit -q -m base; d push -q origin main 2>/dev/null
d switch -q -c feature/x; printf 'linha\n' > "$aux/m2-dev/a.md"; d add -A; d commit -q -m a
d push -q -u origin feature/x 2>/dev/null
bloco_do_e7 'fatiamento-da-pr.sh "$base" "$publicado"' | sed "s|<branch_base>|main|" \
  | sed 's#bash \.claude/skills/mergex/scripts/fatiamento-da-pr\.sh#bash "$script"#' > "$aux/passo15.sh"
saida="$(cd "$aux/m2-dev" && env -u remoto -u publicado -u bb script="$script" bash "$aux/passo15.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && passa 'o bloco do passo 1.5 roda sozinho, sem $remoto e $publicado de outra chamada' \
  || quebra "o bloco do passo 1.5 depende de variavel de outra chamada (rc $rc): $saida"
mkdir -p "$aux/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$ARGS_GH"\n' > "$aux/bin/gh"; chmod +x "$aux/bin/gh"
bloco_do_e7 'gh pr create' | sed 's|<título>|titulo simples|; s|<trabalho_id>|x|' > "$aux/passo2.sh"
rm -f "$aux/args-gh"
saida="$(cd "$aux/m2-dev" && env -u bb PATH="$aux/bin:$PATH" ARGS_GH="$aux/args-gh" bash "$aux/passo2.sh" 2>&1)"; rc=$?
args="$(tr '\n' ' ' 2>/dev/null < "$aux/args-gh")"
[ "$rc" = 0 ] && case "$args" in *'--base main --head feature/x '*) true ;; *) false ;; esac \
  && passa 'o bloco do gh pr create recebe a base do passo 1.5 e a branch, noutra chamada' \
  || quebra "o bloco do gh pr create nao tem a base do passo 1.5 (rc $rc, args '$args'): $saida"
# o titulo vem do ORQUESTRADOR.md e e texto, nao comando: com $(...) e crases, nada roda
# (nenhum arquivo-sentinela nasce) e o gh/glab recebe o titulo literal
cp "$aux/bin/gh" "$aux/bin/glab"
titulo_mau='fix: $(touch sentinela-1) e `touch sentinela-2` com $HOME, "aspas", '"'"'apostrofo'"'"' & \barra'
for cmd in 'gh pr create' 'glab mr create'; do
  bloco="$(bloco_do_e7 "$cmd")"
  bloco="${bloco//'<título>'/"$titulo_mau"}"; printf '%s\n' "${bloco//'<trabalho_id>'/x}" > "$aux/titulo.sh"
  rm -f "$aux/args-gh" "$aux/m2-dev/sentinela-1" "$aux/m2-dev/sentinela-2"
  (cd "$aux/m2-dev" && PATH="$aux/bin:$PATH" ARGS_GH="$aux/args-gh" bash "$aux/titulo.sh" >/dev/null 2>&1)
  recebido="$(awk 'pega { print; exit } $0 == "--title" { pega = 1 }' "$aux/args-gh" 2>/dev/null)"
  if [ -e "$aux/m2-dev/sentinela-1" ] || [ -e "$aux/m2-dev/sentinela-2" ]; then
    quebra "$cmd: o titulo com \$(...) ou crase executou comando na abertura do PR"
  elif [ "$recebido" != "$titulo_mau" ]; then
    quebra "$cmd: o titulo chegou alterado: '$recebido'"
  else
    passa "$cmd: titulo com \$(...) e crases chega literal, sem executar nada"
  fi
done

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
