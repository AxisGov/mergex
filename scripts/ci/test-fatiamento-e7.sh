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
ign_e7="$(sed -n 's/^FATIA_IGNORAR="\${FATIA_IGNORAR:-\(.*\)}" \\$/\1/p' "$e7")"
[ -n "$ign_e7" ] && passa 'o E7 declara o FATIA_IGNORAR do projeto' \
  || quebra 'o E7 herda o FATIA_IGNORAR do ExpxDev (fixtures/candidatos fora da conta)'
grep -Fq 'fatiamento-da-pr.sh "$base" "$publicado"' "$e7" \
  && passa 'o E7 mede o SHA publicado contra a base' \
  || quebra 'o E7 nao chama o script sobre o SHA publicado'
grep -Fq 'o E7 **não abre o PR**' "$e7" \
  && passa 'violacao impede a abertura' \
  || quebra 'o E7 nao diz que a violacao impede a abertura'
grep -Fq 'rb="$remoto"; bb="<branch_base>"' "$e7" && grep -Fq 'git fetch "$rb" "$bb"' "$e7" \
  && grep -Fq 'git rev-parse --verify "FETCH_HEAD^{commit}"' "$e7" \
  && passa 'a base vem do remoto do upstream, buscada agora' \
  || quebra 'a base nao e buscada no remoto do upstream (ref antiga ou fork mediria errado)'
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
# e a raiz de historia sem pai (merge de historia sem relacao) mede contra a arvore vazia
g switch -q --orphan raiz-solta; printf 'linha\n%.0s' $(seq 1 350) > "$tmp/solta.md"; g add solta.md; g commit -q -m "raiz solta"
g switch -q -c com-raiz main; g merge -q --allow-unrelated-histories -m "junta raiz" raiz-solta
saida="$(cd "$tmp" && FATIA_MAX_LINHAS_PR=9000 bash "$script" main com-raiz 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$saida" in *"F3:"*) true ;; *) false ;; esac \
  && passa 'commit raiz no intervalo e medido contra a arvore vazia (F3)' \
  || quebra "commit raiz no intervalo: saiu $rc: $saida"

# o trecho do E7 que resolve a base, rodado de verdade: branch_base com e sem o
# remoto no nome (a base informada pelo chamador no E0 pode vir `upstream/main`)
mkdir -p "$aux/clone"; git -C "$aux/clone" init -q
git -C "$aux/clone" remote add origin https://exemplo.invalid/fork.git
git -C "$aux/clone" remote add upstream https://exemplo.invalid/principal.git
resolve_base() { # <branch_base> — imprime "<remoto> <branch>" como o E7 resolve
  sed -n '/^rb="\$remoto"/,/^if \[/p' "$e7" | sed "s|<branch_base>|$1|" > "$aux/resolve.sh"
  (cd "$aux/clone" && remoto=origin && . "$aux/resolve.sh" && printf '%s %s' "$rb" "$bb")
}
for par in 'main|origin main' 'upstream/main|upstream main' \
           'refs/remotes/upstream/main|upstream main' 'feature/x|origin feature/x'; do
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
g switch -q -c avanca main; printf 'novo\n' > "$tmp/novo.txt"; g add -A; g commit -q -m avanca
git -C "$tmp" push -q "$aux/principal.git" avanca:main 2>/dev/null
atual="$(git -C "$aux/principal.git" rev-parse main)"
[ "$atual" != "$(git -C "$aux/dev" rev-parse refs/remotes/origin/HEAD)" ] \
  || quebra 'fixture: o remoto nao avancou depois do clone (o caso da ref velha nao seria testado)'
base_do_e7() { # <branch_base> — roda o trecho do E7 ate o calculo da base, imprime $base
  sed -n '/^rb="\$remoto"/,/^base=/p' "$e7" | sed "s|<branch_base>|$1|" > "$aux/base.sh"
  (cd "$aux/dev" && remoto=origin && . "$aux/base.sh" >/dev/null 2>&1 && printf '%s' "$base")
}
for bb in main origin/HEAD upstream/main refs/remotes/upstream/main estreito/main; do
  [ "$(base_do_e7 "$bb")" = "$atual" ] && passa "branch_base $bb mede contra a ponta atual do remoto" \
    || quebra "branch_base $bb mediu contra outra base (ref velha?)"
done

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
