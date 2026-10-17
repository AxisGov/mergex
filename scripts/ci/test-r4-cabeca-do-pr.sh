#!/usr/bin/env bash
#
# O R4 do E9 busca a cabeca do PR no repositorio base (09-revisao.md, "HEAD
# autoritativo"). O remoto da base pode nao se chamar `origin`: num fork, o
# `origin` e o fork e a base e `upstream`, ou outro nome. Roda o bloco real do
# reference, com um `gh` de mentira que so devolve a URL do PR.
#
# Uso: bash scripts/ci/test-r4-cabeca-do-pr.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
e9="$raiz/.claude/skills/mergex/references/09-revisao.md"

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }

aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
# o bloco cercado do reference que busca pull/<n>/head
awk '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
              dentro = 1; buf = ""; achou = 0; next }
     dentro { buf = buf $0 "\n"; if (index($0, "pull/<n>/head")) achou = 1 }' "$e9" \
  | sed 's|<n>|7|g' > "$aux/r4.sh"
[ -s "$aux/r4.sh" ] && passa 'o 09-revisao.md tem o bloco que busca pull/<n>/head' \
  || quebra 'o 09-revisao.md nao tem bloco executavel que busque a cabeca do PR'

g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
# a base (dono/repo) tem a ref do PR; o fork nao
git init -q --bare -b main "$aux/dono/repo.git"
git init -q --bare -b main "$aux/eu/repo.git"
git init -q -b main "$aux/semente"
printf 'base\n' > "$aux/semente/a.txt"; g -C "$aux/semente" add -A; g -C "$aux/semente" commit -q -m base
g -C "$aux/semente" push -q "$aux/dono/repo.git" main 2>/dev/null
g -C "$aux/semente" push -q "$aux/eu/repo.git" main 2>/dev/null
printf 'pr\n' > "$aux/semente/b.txt"; g -C "$aux/semente" add -A; g -C "$aux/semente" commit -q -m pr
g -C "$aux/semente" push -q "$aux/dono/repo.git" HEAD:refs/pull/7/head 2>/dev/null
cabeca_pr="$(git -C "$aux/semente" rev-parse HEAD)"

mkdir -p "$aux/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$URL_PR"\n' > "$aux/bin/gh"; chmod +x "$aux/bin/gh"

roda_r4() { # <clone> <url do PR> — imprime a $cabeca que o bloco do R4 obteve
  (cd "$1" && PATH="$aux/bin:$PATH" URL_PR="$2" bash -c ". '$aux/r4.sh' >/dev/null 2>&1 && printf '%s' \"\$cabeca\"")
}

# os remotos guardam URLs de servico de verdade; o `insteadOf` so leva o fetch ao
# repositorio local do teste. O R4 escolhe pela URL configurada, e o fetch e do Git
remoto() { # <clone> <nome> <url configurada> <repositorio local>
  git -C "$1" remote add "$2" "$3"
  git -C "$1" config "url.$4.insteadOf" "$3"
}
clone() { git clone -q "$aux/eu/repo.git" "$aux/$1" 2>/dev/null; }

# fork: origin e o fork, a base e `upstream`
clone fork
remoto "$aux/fork" upstream https://github.com/dono/repo.git "$aux/dono/repo.git"
[ "$(roda_r4 "$aux/fork" 'https://github.com/dono/repo/pull/7')" = "$cabeca_pr" ] \
  && passa 'base no remoto upstream: a cabeca do PR vem dela' \
  || quebra 'base no remoto upstream: o R4 nao obteve a cabeca do PR (buscou no origin?)'

# a base com outro nome, em SSH, e com caixa diferente na URL do PR
clone fork2
remoto "$aux/fork2" principal git@github.com:dono/repo.git "$aux/dono/repo.git"
[ "$(roda_r4 "$aux/fork2" 'https://github.com/Dono/Repo/pull/7')" = "$cabeca_pr" ] \
  && passa 'base num remoto SSH de outro nome: achada pela URL, sem diferenca de caixa' \
  || quebra 'base num remoto SSH de outro nome: o R4 nao a achou pela URL'

# o que so termina parecido nao e a base: outro dono (outro-dono/repo) e o mesmo
# dono/repo noutro servico (gitlab.com); os dois vem antes na ordem dos remotos
clone fork3
mkdir -p "$aux/outro-dono"; git clone -q --bare "$aux/eu/repo.git" "$aux/outro-dono/repo.git" 2>/dev/null
remoto "$aux/fork3" a-falso https://github.com/outro-dono/repo.git "$aux/outro-dono/repo.git"
# (o espelho local do gitlab tambem termina em dono/repo, mas nao tem a ref do PR)
mkdir -p "$aux/gitlab/dono"; git clone -q --bare "$aux/eu/repo.git" "$aux/gitlab/dono/repo.git" 2>/dev/null
remoto "$aux/fork3" b-outro-host https://gitlab.com/dono/repo.git "$aux/gitlab/dono/repo.git"
remoto "$aux/fork3" upstream https://github.com/dono/repo.git "$aux/dono/repo.git"
[ "$(roda_r4 "$aux/fork3" 'https://github.com/dono/repo/pull/7')" = "$cabeca_pr" ] \
  && passa 'outro-dono/repo e gitlab.com/dono/repo nao passam por github.com/dono/repo' \
  || quebra 'o R4 tomou outro dono ou outro host pela base github.com/dono/repo'

# nenhum remoto aponta para a base: busca pela propria URL do PR
clone fork4
[ "$(roda_r4 "$aux/fork4" "$aux/dono/repo.git/pull/7")" = "$cabeca_pr" ] \
  && passa 'sem remoto da base: busca pela URL do repositorio do PR' \
  || quebra 'sem remoto da base: o R4 nao buscou pela URL'

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
