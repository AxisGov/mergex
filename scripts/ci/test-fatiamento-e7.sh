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
# identidade: o corpo (de `set -uo pipefail` ao fim) e o do verificador do expxdev, e o
# cabecalho guarda o sha256 dele; com EXPXDEV_RAIZ, compara com o arquivo de la (pega deriva)
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -d' ' -f1; }
corpo() { sed -n '/^set -uo pipefail$/,$p' "$1"; }
[ "$(corpo "$script" | sha256)" = "$(sed -n 's/^# Corpo-sha256: //p' "$script")" ] \
  && passa 'o corpo bate com o Corpo-sha256 do cabecalho' \
  || quebra 'o corpo do script nao bate com o Corpo-sha256 do cabecalho'
if [ -z "${EXPXDEV_RAIZ:-}" ]; then
  passa 'corpo igual ao verificar-fatiamento.sh do expxdev: pulado (sem EXPXDEV_RAIZ)'
elif [ -n "$(corpo "$script")" ] && [ "$(corpo "$script")" = "$(corpo "$EXPXDEV_RAIZ/scripts/verificar-fatiamento.sh")" ]; then
  passa 'com EXPXDEV_RAIZ definido, o corpo e igual ao verificar-fatiamento.sh do expxdev'
else
  quebra "o corpo difere de $EXPXDEV_RAIZ/scripts/verificar-fatiamento.sh"
fi

l15="$(grep -n '^## Passo 1.5' "$e7" | head -1 | cut -d: -f1)"
l2="$(grep -n '^## Passo 2 ' "$e7" | head -1 | cut -d: -f1)"
if [ -n "$l15" ] && [ -n "$l2" ] && [ "$l15" -lt "$l2" ]; then
  passa 'o Passo 1.5 (fatiamento) vem antes do Passo 2 (abrir o PR)'
else
  quebra 'o Passo 1.5 nao existe ou nao vem antes da abertura'
fi
# o bloco do passo 1.5 nao exporta nem passa FATIA_: nenhum limite nem exclusao vem do
# ambiente (limites do CodeAnt, fixos). O texto pode citar FATIA_* ao explicar a saida 2
bloco15="$(awk '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                         dentro = 1; buf = ""; achou = 0; next }
                dentro { buf = buf $0 "\n"; if (index($0, "fatiamento-da-pr.sh")) achou = 1 }' "$e7")"
[ -n "$bloco15" ] && ! printf '%s\n' "$bloco15" | grep -q 'FATIA_' \
  && passa 'o bloco do passo 1.5 nao exporta nem passa FATIA_' \
  || quebra "o bloco do passo 1.5 ainda tem FATIA_: $(printf '%s\n' "$bloco15" | grep 'FATIA_')"
# a exclusao do projeto (EXPX_EXCLUIR_DA_REVISAO, pastas separadas por |) vira um par
# --excluir-da-revisao <pasta> por parte, inteira mesmo com espaco, sem glob; vazio nao gera
# argumento, e parametro posicional herdado nao chega ao script. O trecho real, rodado
args_trecho="$(printf '%s\n' "$bloco15" | sed -n '/^set --; set -f/,/^IFS="\$ifs_antes"; set +f$/p')"
args_dir="$(mktemp -d)" && mkdir -p "$args_dir/^gl-1" # uma pasta que o glob ^gl-*/ casaria
args_de() { # <EXPX_EXCLUIR_DA_REVISAO> — imprime os argumentos montados, um [arg] por linha
  local excluir="$1"
  (cd "$args_dir" && set -- herdado1 herdado2 && EXPX_EXCLUIR_DA_REVISAO="$excluir" \
    && eval "$args_trecho" && { [ "$#" = 0 ] || printf '[%s]' "$@"; })
}
dois="$(args_de '^a/|^dados de teste/')"; vazio="$(args_de '')"; glob="$(args_de '^gl-*/')"
rm -rf "$args_dir"
[ -n "$args_trecho" ] && [ "$dois" = '[--excluir-da-revisao][^a/][--excluir-da-revisao][^dados de teste/]' ] \
  && [ -z "$vazio" ] && [ "$glob" = '[--excluir-da-revisao][^gl-*/]' ] \
  && passa 'dois padroes, um com espaco, e EXPX_EXCLUIR_DA_REVISAO vazio: um par por padrao, nenhum herdado, sem glob' \
  || quebra "argumentos do E7: dois '$dois', vazio '$vazio', glob '$glob' (trecho: $args_trecho)"
grep -Fq 'fatiamento-da-pr.sh "$@" "$base" "$publicado"' "$e7" \
  && passa 'o E7 mede o SHA publicado contra a base' \
  || quebra 'o E7 nao chama o script sobre o SHA publicado'
grep -Fq 'o E7 **não abre o PR**' "$e7" \
  && passa 'violacao impede a abertura' \
  || quebra 'o E7 nao diz que a violacao impede a abertura'
grep -Fq 'Saída `2` (ou qualquer outra que não `0` nem `1`): o E7 **não abre o PR**' "$e7" \
  && grep -Fq '| `fatiamento-da-pr.sh` saiu `2`' "$e7" \
  && passa 'medicao impossivel (saida 2) tambem impede a abertura' \
  || quebra 'o E7 so trata as saidas 0 e 1 do fatiamento; a 2 (nao mediu) abriria sem medir'
grep -Fxq 'rb="$remoto"' "$e7" && grep -Fq "IFS= read -r bb <<'BRANCH_BASE__INVALIDA~'" "$e7" && grep -Fq 'git fetch "$rb" "$bb"' "$e7" \
  && grep -Fq 'git rev-parse --verify "FETCH_HEAD^{commit}"' "$e7" \
  && passa 'a base vem do remoto do upstream, buscada agora' \
  || quebra 'a base nao e buscada no remoto do upstream (ref antiga ou fork mediria errado)'
grep -Fq 'gh pr create --repo "$destino" --base "$bb"' "$e7" && ! grep -Fq 'gh pr create --base <branch-base>' "$e7" \
  && passa 'o gh pr create recebe a base sem o remoto ($bb do passo 1.5)' \
  || quebra 'o gh pr create recebe a branch_base crua (upstream/main nao e branch no GitHub)'
# o passo 1 reconhece `glab`: o passo 2 tem de ter o comando dele, ou o GitLab cai no manual
grep -Fq -- '--target-branch "$bb" --source-branch "$branch_fonte"' "$e7" && grep -Fq 'glab mr create --repo' "$e7" \
  && grep -Fq -- '"${opcao_rascunho[@]}" --yes' "$e7" \
  && passa 'o GitLab (glab) tem o comando de abertura, com a base do passo 1.5 e sem confirmacao interativa' \
  || quebra 'o passo 1 reconhece glab, mas o passo 2 so tem o comando do gh'
grep -Fq 'o passo 1.5 roda do mesmo jeito, e só depois dele vá para o passo 3' "$e7" \
  && passa 'servico sem ferramenta tambem passa pela medicao' \
  || quebra 'o caminho manual (passo 3) contorna a medicao'

tmp="$(mktemp -d)"; aux="$(mktemp -d)"; trap 'rm -rf "$tmp" "$aux"' EXIT
g() { git -C "$tmp" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g init -q -b main
printf 'base\n' > "$tmp/base.txt"; g add -A; g commit -q -m base
leitor="$raiz/.claude/skills/mergex/scripts/leitor-do-projeto.sh"
# nenhuma FATIA_* herdada do shell de quem roda os testes muda o que se mede aqui
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done
mede() { (cd "$tmp" && bash "$script" "$@" 2>&1); }
linhas() { # <n> <arquivo> — n linhas, cada uma com quebra (wc -l = n)
  mkdir -p "$(dirname "$2")"; awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "linha " i }' > "$2"
}
muitos() { # <n> <pasta> — n arquivos de uma linha
  local i; mkdir -p "$2"; for i in $(seq 1 "$1"); do printf 'x %s\n' "$i" > "$2/f$i.txt"; done
}

# L3: todos os arquivos contam, como o changed_files do GitHub: lock, artefatos de metodo e
# fixtures/candidatos/ inclusive. 97 + 3 = 100 passam; 98 + 3 = 101 reprovam
g switch -q -c l3-100 main
muitos 97 "$tmp/src"
mkdir -p "$tmp/docs/entregas/x" "$tmp/fixtures/candidatos"
printf '{}\n' > "$tmp/package-lock.json"; printf 'entrega\n' > "$tmp/docs/entregas/x/ENTREGA.md"
printf 'copia\n' > "$tmp/fixtures/candidatos/c.txt"; g add -A; g commit -q -m l3-100
saida="$(mede main l3-100)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'PR com 100 arquivo(s)'*) true ;; *) false ;; esac \
  && passa 'L3: 100 arquivos passam' || quebra "L3: 100 arquivos (rc $rc): $saida"
g switch -q -c l3-101 l3-100; printf 'x\n' > "$tmp/src/mais.txt"; g add -A; g commit -q -m l3-101
saida="$(mede main l3-101)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'VIOLACAO L3'*'101 arquivos'*) true ;; *) false ;; esac \
  && passa 'L3: 101 reprovam contando package-lock.json, docs/entregas/ e fixtures/candidatos/' \
  || quebra "L3: 101 arquivos (rc $rc): $saida"
# renomeacao conta 1: 99 novos e um movido sao 100
g switch -q -c ren-base main; linhas 20 "$tmp/ren.txt"; g add -A; g commit -q -m ren-base
g switch -q -c ren-pr ren-base; mkdir -p "$tmp/movido"; g mv ren.txt movido/ren.txt
muitos 99 "$tmp/novos"; g add -A; g commit -q -m ren-pr
saida="$(mede ren-base ren-pr)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'PR com 100 arquivo(s)'*) true ;; *) false ;; esac \
  && passa 'L3: renomeacao conta 1' || quebra "L3: renomeacao (rc $rc): $saida"

# sem limite de linhas por PR nem por commit: 3.000 linhas em 5 arquivos, num commit so
g switch -q -c sem-linhas main
for i in 1 2 3 4 5; do linhas 600 "$tmp/longo/l$i.ts"; done; g add -A; g commit -q -m sem-linhas
saida="$(mede main sem-linhas)"; rc=$?
[ "$rc" = 0 ] && passa 'sem limite de linhas: 3.000 linhas em 5 arquivos passam' \
  || quebra "3.000 linhas em 5 arquivos (rc $rc): $saida"

# L2: linhas pela conta da CLI (quebras + 1): wc -l 5.000 com quebra final conta 5.001
g switch -q -c l2-5000 main; linhas 5000 "$tmp/grande.ts"; g add -A; g commit -q -m l2-5000
saida="$(mede main l2-5000)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'VIOLACAO L2: grande.ts tem 5001 linhas'*) true ;; *) false ;; esac \
  && passa 'L2: 5.000 linhas com quebra final reprova (5.001 pela conta da CLI)' \
  || quebra "L2: 5.000 linhas com quebra final (rc $rc): $saida"
g switch -q -c l2-4999 main; linhas 4999 "$tmp/grande.ts"; g add -A; g commit -q -m l2-4999
saida="$(mede main l2-4999)"; rc=$?
[ "$rc" = 0 ] && passa 'L2: 4.999 linhas com quebra final passa' \
  || quebra "L2: 4.999 linhas com quebra final (rc $rc): $saida"
# nome que comeca com hifen: o checkout e medido como arquivo, nunca lido como opcao
g switch -q -c l2-hifen main; linhas 5000 "$tmp/-n.md"; g add -A; g commit -q -m l2-hifen
saida="$(mede main l2-hifen)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'VIOLACAO L2: -n.md tem 5001 linhas'*) true ;; *) false ;; esac \
  && passa 'L2: arquivo -n.md medido pelo espelho (blob e checkout)' \
  || quebra "L2: arquivo -n.md (rc $rc): $saida"
# a exclusao chega por argumento, inteira, mesmo com espaco no nome da pasta; so tira de L2
g switch -q -c l2-espaco main; linhas 5000 "$tmp/dados de teste/g.txt"; g add -A; g commit -q -m l2-espaco
saida="$(mede --excluir-da-revisao '^dados de teste/' main l2-espaco)"; rc=$?
sem="$(mede main l2-espaco)"; rc_sem=$?
[ "$rc" = 0 ] && [ "$rc_sem" = 1 ] && case "$saida" in *'PR com 1 arquivo(s)'*) true ;; *) false ;; esac \
  && passa "L2 fora com --excluir-da-revisao '^dados de teste/' (e dentro sem ele)" \
  || quebra "--excluir-da-revisao com espaco (rc $rc, sem o argumento rc $rc_sem): $saida"
for padrao in 'dados/' '^src/*' '^a|b/' '^dados'; do
  (cd "$tmp" && bash "$script" --excluir-da-revisao "$padrao" main l2-4999 >/dev/null 2>&1); rc=$?
  [ "$rc" = 2 ] && passa "--excluir-da-revisao fora da gramatica ($padrao) sai 2" \
    || quebra "--excluir-da-revisao '$padrao' saiu $rc, esperado 2"
done

# FATIA_* no ambiente, mesmo vazia: sai 2 com a mensagem exata, nunca mede ignorando
saida="$(cd "$tmp" && FATIA_EXCECAO= bash "$script" main l2-4999 2>&1)"; rc=$?
[ "$rc" = 2 ] && [ "$saida" = '`FATIA_EXCECAO` não é mais lida (limites do CodeAnt, fixos: emenda de 2026-10-19); remova-a do ambiente' ] \
  && passa 'FATIA_EXCECAO= vazia no ambiente: sai 2 com a mensagem exata' \
  || quebra "FATIA_EXCECAO vazia no ambiente (rc $rc): $saida"

# PR de planejamento: so artefatos de metodo, sem L3; a origem de renomeacao conta
g switch -q -c plan-150 main; muitos 150 "$tmp/docs/sprintx/features/x"; g add -A; g commit -q -m plan-150
saida="$(mede --planejamento main plan-150)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'PR de planejamento com 150 arquivo(s)'*) true ;; *) false ;; esac \
  && passa '--planejamento: 150 arquivos em docs/sprintx/ passam (L3 nao se aplica)' \
  || quebra "--planejamento com 150 arquivos (rc $rc): $saida"
g switch -q -c plan-codigo plan-150; mkdir -p "$tmp/src"; printf 'x\n' > "$tmp/src/a.ts"; g add -A; g commit -q -m plan-codigo
saida="$(mede --planejamento main plan-codigo)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'VIOLACAO planejamento: src/a.ts'*) true ;; *) false ;; esac \
  && passa '--planejamento: src/a.ts reprova (VIOLACAO planejamento)' \
  || quebra "--planejamento com src/a.ts (rc $rc): $saida"
g switch -q -c plan-ren-base main; linhas 30 "$tmp/src/a.ts"; g add -A; g commit -q -m plan-ren-base
g switch -q -c plan-ren plan-ren-base; mkdir -p "$tmp/docs/sprintx"; g mv src/a.ts docs/sprintx/a.ts; g commit -q -m plan-ren
saida="$(mede --planejamento plan-ren-base plan-ren)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'VIOLACAO planejamento: src/a.ts'*) true ;; *) false ;; esac \
  && passa '--planejamento: renomeacao de src/a.ts para docs/sprintx/a.ts reprova pela origem' \
  || quebra "--planejamento com renomeacao para docs/sprintx (rc $rc): $saida"

# medicao que falha nao e PR limpo: o blob de um arquivo revisavel some do head depois de as
# refs resolverem, e o script sai 2 (nao mediu), nunca 0
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
g switch -q main
sem_objeto sem-blob-pr perdido.md
falha_ao_medir 'objeto ausente no head (arquivo revisavel)' sem-blob-pr

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
entrega_comum() { # <raiz> — o ENTREGA.md de docs/entregas/x/ de uma entrega comum (sem planejamento)
  mkdir -p "$1/docs/entregas/x"
  printf '%s\n' '---' 'kind: entrega' 'trabalho_id: x' 'sprint_atual: null' 'prs: []' '---' > "$1/docs/entregas/x/ENTREGA.md"
}
printf 'base\n' > "$aux/m2-dev/base.txt"; entrega_comum "$aux/m2-dev"
d add -A; d commit -q -m base; d push -q origin main 2>/dev/null
d switch -q -c feature/x; printf 'linha\n' > "$aux/m2-dev/a.md"; d add -A; d commit -q -m a
d push -q -u origin feature/x 2>/dev/null
bloco_do_e7 'fatiamento-da-pr.sh "$@" "$base" "$publicado"' | sed "s|<branch_base>|main|; s|<trabalho_id>|x|g" \
  | sed "s#bash \.claude/skills/mergex/scripts/entrega-de-planejamento\.sh#bash '$raiz/.claude/skills/mergex/scripts/entrega-de-planejamento.sh'#" \
  | sed 's#bash \.claude/skills/mergex/scripts/fatiamento-da-pr\.sh#bash "$script"#' \
  | sed "s#bash \.claude/skills/mergex/scripts/leitor-do-projeto\.sh#bash '$leitor'#" > "$aux/passo15.sh"
saida="$(cd "$aux/m2-dev" && env -u remoto -u publicado -u bb script="$script" bash "$aux/passo15.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && passa 'o bloco do passo 1.5 roda sozinho, sem $remoto e $publicado de outra chamada' \
  || quebra "o bloco do passo 1.5 depende de variavel de outra chamada (rc $rc): $saida"
mkdir -p "$aux/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$ARGS_GH"\n' > "$aux/bin/gh"; chmod +x "$aux/bin/gh"
# o passo 2 confere a ponta remota com `git ls-remote`, e o remoto dele e uma URL do GitHub: so o
# ls-remote e falso, sem rede, e responde o HEAD (o medido continua publicado)
git_real="$(command -v git)"
printf '#!/usr/bin/env bash\nif [ "${1:-}" = ls-remote ]; then printf "%%s\\t%%s\\n" "$("%s" rev-parse HEAD)" "${3:-}"; exit 0; fi\nexec "%s" "$@"\n' \
  "$git_real" "$git_real" > "$aux/bin/git"; chmod +x "$aux/bin/git"
# o passo 2 exige um remoto normalizavel (HOST/OWNER/REPO): o caminho local do remoto de teste
# falharia fechado. O passo 1.5 volta a usar o remoto local depois.
git -C "$aux/m2-dev" remote set-url origin https://github.com/acme/x.git
bloco_do_e7 'gh pr create' | sed 's|<título>|titulo simples|; s|<trabalho_id>|x|' > "$aux/passo2.sh"
rm -f "$aux/args-gh"
saida="$(cd "$aux/m2-dev" && env -u bb PATH="$aux/bin:$PATH" ARGS_GH="$aux/args-gh" bash "$aux/passo2.sh" 2>&1)"; rc=$?
args="$(tr '\n' ' ' 2>/dev/null < "$aux/args-gh")"
[ "$rc" = 0 ] && case "$args" in *'--base main --head feature/x '*) true ;; *) false ;; esac \
  && passa 'o bloco do gh pr create recebe a base do passo 1.5 e a branch, noutra chamada' \
  || quebra "o bloco do gh pr create nao tem a base do passo 1.5 (rc $rc, args '$args'): $saida"
# o titulo vem do ORQUESTRADOR.md e e texto, nao comando: com $(...) e crases, nada roda
# (nenhum arquivo-sentinela nasce) e o gh/glab recebe o titulo literal
# o glab do passo 2 consulta o projeto da origem e lista as MRs abertas antes de criar
cat > "$aux/bin/glab" <<'GLAB'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "api projects/"*) printf '{"id":42}\n' ;;
  "mr list") printf '[]\n' ;;
  *) printf '%s\n' "$@" > "$ARGS_GH" ;;
esac
GLAB
chmod +x "$aux/bin/glab"
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
git -C "$aux/m2-dev" remote set-url origin "$aux/m2-remoto.git"
estado="$(git -C "$aux/m2-dev" rev-parse --path-format=absolute --git-path mergex-e7-base)"
[ -s "$estado" ] || quebra 'fixture: o passo 1.5 aprovado nao gravou o estado'
# a branch remota anda entre a chamada dos pre-requisitos e a do passo 1.5: a ref de
# rastreio local continua igual ao HEAD, e so uma busca nesta chamada mostra a ponta nova
git clone -q -b feature/x "$aux/m2-remoto.git" "$aux/m2-outro" 2>/dev/null
printf 'outro\n' > "$aux/m2-outro/b.md"
git -C "$aux/m2-outro" add -A; git -C "$aux/m2-outro" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m b
git -C "$aux/m2-outro" push -q origin feature/x 2>/dev/null
saida="$(cd "$aux/m2-dev" && env -u remoto -u publicado -u bb script="$script" bash "$aux/passo15.sh" 2>&1)"; rc=$?
[ "$rc" = 2 ] && case "$saida" in *'não é o HEAD'*) true ;; *) false ;; esac \
  && passa 'passo 1.5 busca o upstream de novo: ponta remota que andou para o E7, sem medir (2)' \
  || quebra "passo 1.5 mediu a ref de rastreio velha (rc $rc): $saida"
# estado de uma execucao anterior bem-sucedida + fetch do upstream que falha agora: o
# passo 1.5 para, e o passo 2 nao acha base nenhuma, entao nao abre o PR
printf 'main\n' > "$estado"
git -C "$aux/m2-dev" remote set-url origin "$aux/nao-existe.git"
(cd "$aux/m2-dev" && env -u remoto -u publicado -u bb script="$script" bash "$aux/passo15.sh" >/dev/null 2>&1); rc15=$?
rm -f "$aux/args-gh"
(cd "$aux/m2-dev" && env -u bb PATH="$aux/bin:$PATH" ARGS_GH="$aux/args-gh" bash "$aux/passo2.sh" >/dev/null 2>&1); rc2=$?
[ "$rc15" != 0 ] && [ ! -e "$estado" ] && [ "$rc2" != 0 ] && [ ! -e "$aux/args-gh" ] \
  && passa 'fetch do upstream que falha apaga o estado antigo: o passo 2 nao abre o PR' \
  || quebra "estado antigo sobreviveu a falha do passo 1.5 (rc $rc15, estado $( [ -e "$estado" ] && echo presente || echo ausente), passo 2 rc $rc2, gh $( [ -e "$aux/args-gh" ] && echo chamado || echo nao chamado))"

# o passo 1.5 mede com os limites de .expx/fatiamento.json do SHA publicado, lidos pelo
# leitor do projeto (que chama o nucleo do expx). Configuracao que nao se le e "nao mediu"
grep -Fq 'fatia="$(bash .claude/skills/mergex/scripts/leitor-do-projeto.sh --rev "$publicado")" || {' "$e7" \
  && grep -Fxq 'set -a; eval "$fatia"; set +a' "$e7" \
  && passa 'o E7 consome o leitor com set -a' \
  || quebra 'o E7 nao le .expx/fatiamento.json pelo leitor do projeto, exportando com set -a'
grep -Fq 'leitor-do-projeto.sh' "$e7" && ! grep -Fq 'eval "$(' "$e7" \
  && passa 'nenhum eval "$(...)" direto no E7' \
  || quebra 'o E7 nao tem o leitor, ou avalia a saida dele direto (eval "$(...)")'
# contrato: o unico eval do E7 e o do consumo do leitor; outro, solto, executaria o que nao
# passou pelo leitor do nucleo
soltos="$(tr -d '\r' < "$e7" | grep -w 'eval' | grep -vxF 'set -a; eval "$fatia"; set +a')"
[ -z "$soltos" ] && passa 'nenhum eval solto no E7, fora do consumo do leitor' \
  || quebra "eval solto no E7: $soltos"
nucleo_rel='.expx/marketplace/plugins/expx/nucleo/scripts'
copia_nucleo="$raiz/scripts/ci/fixtures/candidatos/expx-nucleo"
# monta_nucleo <destino>: a copia inteira do nucleo (menos o ORIGEM), com as subpastas, sem CR
# (num checkout com core.autocrlf=true a copia chega com CRLF)
monta_nucleo() {
  local f
  while IFS= read -r f; do
    mkdir -p "$1/$(dirname "$f")" && tr -d '\r' < "$copia_nucleo/$f" > "$1/$f"
  done < <(cd "$copia_nucleo" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
}
cenario() { # <nome> [sem-nucleo] [config da base] — remoto e clone novos, base com o nucleo; fica em feature/x
  local dv="$aux/c-$1"
  git init -q --bare -b main "$aux/c-$1.git"; git clone -q "$aux/c-$1.git" "$dv" 2>/dev/null
  mkdir -p "$dv/.expx"; [ -z "${3:-}" ] || printf '%s\n' "$3" > "$dv/.expx/fatiamento.json"
  if [ "${2:-}" != sem-nucleo ]; then
    monta_nucleo "$dv/$nucleo_rel"
  fi
  printf 'base\n' > "$dv/base.txt"; entrega_comum "$dv"
  c "$1" add -A; c "$1" commit -q -m base; c "$1" push -q origin main 2>/dev/null
  c "$1" switch -q -c feature/x
}
c() { local n="$1"; shift; git -C "$aux/c-$n" -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
config() { # [padrao...] — .expx/fatiamento.json v2, com um item de excluir_da_revisao por padrao
  local itens='' p
  for p in "$@"; do
    itens="${itens:+$itens, }{ \"padrao\": \"$p\", \"classe\": \"gerado\", \"origem\": \"scripts/gera.sh\", \"motivo\": \"gerado por script\" }"
  done
  printf '{ "expx_fatiamento": 2, "revisao_por_task": { "modo": "obrigatoria" }, "excluir_da_revisao": [ %s ] }\n' "$itens"
}
publica() { c "$1" add -A; c "$1" commit -q -m "$2"; c "$1" push -q -u origin feature/x 2>/dev/null; }
grande() { # <arquivo> — 5.001 linhas pela conta da CLI (wc -l 5.000, com quebra final)
  mkdir -p "$(dirname "$1")"; awk 'BEGIN { for (i = 1; i <= 5000; i++) print "linha " i }' > "$1"
}
passo15() { # <nome> [VAR=valor...] — roda o bloco real do passo 1.5 no clone
  local n="$1"; shift
  (cd "$aux/c-$n" && env -u remoto -u publicado -u bb script="$script" "$@" bash "$aux/passo15.sh" 2>&1)
}
estado_de() { git -C "$aux/c-$1" rev-parse --path-format=absolute --git-path mergex-e7-base; }
if command -v node >/dev/null 2>&1; then
  # a exclusao do SHA publicado tira a pasta de L2; o disco com outro padrao nao muda a medida
  cenario gerado com-nucleo "$(config '^gerado/')"; grande "$aux/c-gerado/gerado/a.js"; publica gerado gerado
  config '^outro/' > "$aux/c-gerado/.expx/fatiamento.json"
  saida="$(passo15 gerado)"; rc=$?
  [ "$rc" = 0 ] && [ -s "$(estado_de gerado)" ] \
    && passa 'excluir_da_revisao do SHA publicado tira a pasta de L2 (o disco nao muda a medida) e grava o estado' \
    || quebra "excluir_da_revisao do SHA publicado (rc $rc): $saida"
  cenario espaco com-nucleo "$(config '^dados de teste/')"; grande "$aux/c-espaco/dados de teste/a.js"; publica espaco espaco
  saida="$(passo15 espaco)"; rc=$?
  [ "$rc" = 0 ] && passa "padrao com espaco chega inteiro ('^dados de teste/' fora de L2)" \
    || quebra "padrao com espaco (rc $rc): $saida"
  # controle: sem a exclusao, o mesmo arquivo reprova em L2
  cenario sem-exclusao com-nucleo "$(config)"; grande "$aux/c-sem-exclusao/gerado/a.js"; publica sem-exclusao grande
  saida="$(passo15 sem-exclusao)"; rc=$?
  [ "$rc" = 1 ] && [ ! -e "$(estado_de sem-exclusao)" ] && case "$saida" in *'VIOLACAO L2: gerado/a.js'*) true ;; *) false ;; esac \
    && passa 'sem excluir_da_revisao, o arquivo de 5.001 linhas reprova em L2 e nao deixa o estado' \
    || quebra "sem excluir_da_revisao (rc $rc): $saida"
  cenario invalido; printf '{ "expx_fatiamento": 2, "entrega": "por_dia" }\n' > "$aux/c-invalido/.expx/fatiamento.json"
  publica invalido config
  saida="$(passo15 invalido)"; rc=$?
  [ "$rc" = 2 ] && [ ! -e "$(estado_de invalido)" ] && case "$saida" in *entrega*) true ;; *) false ;; esac \
    && passa '.expx/fatiamento.json invalido: o bloco sai 2 e nao deixa o estado da base' \
    || quebra ".expx/fatiamento.json invalido (rc $rc, estado $( [ -e "$(estado_de invalido)" ] && echo presente || echo ausente)): $saida"
  cenario v1; printf '{ "expx_fatiamento": 1, "legibilidade": { "pr_linhas": 2500 } }\n' > "$aux/c-v1/.expx/fatiamento.json"
  publica v1 config
  saida="$(passo15 v1)"; rc=$?
  [ "$rc" = 2 ] && [ ! -e "$(estado_de v1)" ] && case "$saida" in *'migre para 2'*) true ;; *) false ;; esac \
    && passa '.expx/fatiamento.json v1 no SHA publicado: sai 2 e cita migre para 2' \
    || quebra ".expx/fatiamento.json v1 (rc $rc): $saida"
else
  passa 'excluir_da_revisao e configuracao no passo 1.5: pulado (sem node; o CI tem node)'
fi
cenario sem-leitor sem-nucleo "$(config)"; c sem-leitor push -q -u origin feature/x 2>/dev/null
saida="$(passo15 sem-leitor)"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$(estado_de sem-leitor)" ] && case "$saida" in *'expx update'*) true ;; *) false ;; esac \
  && passa 'arquivo presente sem leitor: sai 2 e cita expx update' \
  || quebra "arquivo presente sem leitor (rc $rc): $saida"
# sem o arquivo, nada chama node: 101 arquivos, contando fixtures/candidatos/ e docs/entregas/,
# reprovam em L3, e o reprovado (saida 1) nao deixa o estado da base para o passo 2
cenario sem-config; mkdir -p "$aux/c-sem-config/fixtures/candidatos" "$aux/c-sem-config/docs/entregas/x"
for i in $(seq 1 100); do printf 'x\n' > "$aux/c-sem-config/fixtures/candidatos/f$i.txt"; done
printf 'pr\n' > "$aux/c-sem-config/docs/entregas/x/PR.md"; publica sem-config muitos
mkdir -p "$aux/node-espia"; printf '#!/usr/bin/env bash\n: > "%s/node-chamado"\nexit 1\n' "$aux" > "$aux/node-espia/node"; chmod +x "$aux/node-espia/node"
saida="$(passo15 sem-config PATH="$aux/node-espia:$PATH")"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$aux/node-chamado" ] && case "$saida" in *'VIOLACAO L3'*'101 arquivos'*) true ;; *) false ;; esac \
  && passa 'sem arquivo: 101 arquivos (fixtures/candidatos/ e docs/entregas/ inclusive) reprovam (L3) e nada chama node' \
  || quebra "sem arquivo (rc $rc, node $( [ -e "$aux/node-chamado" ] && echo chamado || echo nao chamado)): $saida"
[ "$rc" = 1 ] && [ ! -e "$(estado_de sem-config)" ] \
  && passa 'passo 1.5 reprovado (saida 1) nao deixa o estado da base para o passo 2' \
  || quebra "passo 1.5 reprovado: rc $rc, estado $( [ -e "$(estado_de sem-config)" ] && echo presente || echo ausente)"
# FATIA_* esquecida no shell (definida e vazia): o bloco sai 2, mostra a mensagem e nao
# deixa o estado; nunca mede ignorando a variavel
cenario fatia; printf 'x\n' > "$aux/c-fatia/a.ts"; publica fatia a
saida="$(passo15 fatia FATIA_IGNORAR=)"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$(estado_de fatia)" ] && case "$saida" in *'`FATIA_IGNORAR` não é mais lida'*'remova-a do ambiente'*) true ;; *) false ;; esac \
  && passa 'FATIA_IGNORAR= no shell: o bloco sai 2, cita remova-a do ambiente e nao deixa o estado' \
  || quebra "FATIA_IGNORAR= no shell (rc $rc, estado $( [ -e "$(estado_de fatia)" ] && echo presente || echo ausente)): $saida"

# O PR de planejamento (DM-259): o bloco pergunta a entrega-de-planejamento.sh, no SHA
# publicado, e so entao passa --planejamento ao espelho (sem L3, so artefatos de metodo)
grep -Fq 'entrega-de-planejamento.sh --entrega "docs/entregas/<trabalho_id>/ENTREGA.md" --rev "$publicado"' "$e7" \
  && passa 'o bloco do passo 1.5 le a entrega de planejamento do SHA publicado' \
  || quebra 'o bloco do passo 1.5 nao pergunta a entrega-de-planejamento.sh com --rev "$publicado"'
entrega_planejamento() { # <nome> [incoerente] — o ENTREGA.md do planejamento aberto
  mkdir -p "$aux/c-$1/docs/entregas/x"
  if [ "${2:-}" = incoerente ]; then
    printf '%s\n' '---' 'kind: entrega' 'trabalho_id: x' 'sprint_atual: planejamento' '---'
  else
    printf '%s\n' '---' 'kind: entrega' 'trabalho_id: x' 'sprint_atual: planejamento' 'prs:' \
      '  - sprint: planejamento' '    url: null' '    estado: null' '    merge_sha: null' '    merge: null' '---'
  fi > "$aux/c-$1/docs/entregas/x/ENTREGA.md"
}
cenario plan150; entrega_planejamento plan150
mkdir -p "$aux/c-plan150/docs/sprintx/features/x"
for i in $(seq 1 150); do printf 'm %s\n' "$i" > "$aux/c-plan150/docs/sprintx/features/x/m$i.md"; done
publica plan150 planejamento
saida="$(passo15 plan150)"; rc=$?
[ "$rc" = 0 ] && [ -s "$(estado_de plan150)" ] && case "$saida" in *'PR de planejamento com 151 arquivo(s)'*) true ;; *) false ;; esac \
  && passa 'entrega de planejamento com 150 arquivos de metodo: o bloco sai 0 (sem L3) e grava o estado' \
  || quebra "entrega de planejamento com 150 arquivos de metodo (rc $rc): $saida"
cenario plansrc; entrega_planejamento plansrc
mkdir -p "$aux/c-plansrc/docs/sprintx/features/x" "$aux/c-plansrc/src"
printf 'p\n' > "$aux/c-plansrc/docs/sprintx/features/x/00-PLANEJAMENTO.md"; printf 'x\n' > "$aux/c-plansrc/src/a.ts"
publica plansrc codigo
saida="$(passo15 plansrc)"; rc=$?
[ "$rc" = 1 ] && [ ! -e "$(estado_de plansrc)" ] && case "$saida" in *'VIOLACAO planejamento: src/a.ts'*) true ;; *) false ;; esac \
  && passa 'entrega de planejamento com src/a.ts: sai 1, lista o arquivo e nao deixa o estado' \
  || quebra "entrega de planejamento com src/a.ts (rc $rc): $saida"
cenario planinc; entrega_planejamento planinc incoerente; publica planinc incoerente
saida="$(passo15 planinc)"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$(estado_de planinc)" ] \
  && passa 'ENTREGA incoerente no SHA publicado: o bloco sai 2 e nao deixa o estado' \
  || quebra "ENTREGA incoerente no SHA publicado (rc $rc): $saida"
# o disco nao conta: planejamento so no disco, entrega comum publicada
cenario plandisco; mkdir -p "$aux/c-plandisco/src"; printf 'x\n' > "$aux/c-plandisco/src/a.ts"; publica plandisco a
entrega_planejamento plandisco
saida="$(passo15 plandisco)"; rc=$?
[ "$rc" = 0 ] && case "$saida" in *'PR de planejamento'*) false ;; *) true ;; esac \
  && passa 'a marca do planejamento vem do SHA publicado, nao do disco' \
  || quebra "a marca do planejamento veio do disco (rc $rc): $saida"
saida="$(passo15 sem-config)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *'PR de planejamento'*) false ;; *'VIOLACAO L3'*) true ;; *) false ;; esac \
  && passa 'entrega comum: o bloco nao passa --planejamento (101 arquivos ainda reprovam em L3)' \
  || quebra "entrega comum com 101 arquivos (rc $rc): $saida"

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
