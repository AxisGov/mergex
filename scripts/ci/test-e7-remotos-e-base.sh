#!/usr/bin/env bash
# Correções P1 do Login no E7 (references/07-abertura-pr.md), contra os blocos reais do
# reference, extraídos e executados como em test-fatiamento-e7.sh:
#   - o provedor sai do remoto de upstream da branch, não de `origin`;
#   - a branch_base entra por heredoc com delimitador entre aspas: nada nela é avaliado;
#   - falha de medição sai 2, nunca 1 (1 é "reprovado pelo fatiamento");
#   - o PR abre no projeto do remoto-base, com a origem explícita (fork: `dono:branch`);
#   - a retomada da MR filtra projeto de origem e base, paginando;
#   - sem `--draft` quando o QA já aprovou.
set -uo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
e7="$raiz/.claude/skills/mergex/references/07-abertura-pr.md"
OK=0; FALHOU=0
passa()  { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT

bloco_do_e7() { # <trecho> — o bloco cercado do E7 que contém o trecho (o primeiro)
  awk -v t="$1" '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                          dentro = 1; buf = ""; achou = 0; next }
                 dentro { buf = buf $0 "\n"; if (index($0, t)) achou = 1 }' "$e7"
}
funcao_do_e7() { # <nome> — a primeira definição `<nome>() {` até a linha que é só `}`
  awk -v n="$1() {" 'index($0, n) == 1 { p = 1 } p { print } p && /^}$/ { exit }' "$e7"
}
g() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}"; }

echo '== E7: provedor pelo remoto de upstream =='
f="$(funcao_do_e7 resolver_remoto_upstream)"
if [ -z "$f" ]; then
  quebra 'o E7 nao define resolver_remoto_upstream: presume origin'
else
  falso_git='git() { case "$1:$2:$3" in
    symbolic-ref:--quiet:--short) printf "%s\n" feature/x ;;
    config:--get:branch.feature/x.remote) [ -n "${REMOTO:-}" ] && printf "%s\n" "$REMOTO" ;;
    config:--get:branch.feature/x.merge) [ -n "${REMOTO:-}" ] && printf "%s\n" refs/heads/feature/x ;;
    *) return 1 ;; esac; }'
  saida="$(REMOTO=publish bash -c "$falso_git
$f
resolver_remoto_upstream" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$saida" = publish ] && passa 'upstream em remoto que nao e origin: publish' \
    || quebra "upstream publish: (rc $rc) $saida"
  saida="$(bash -c "$falso_git
$f
resolver_remoto_upstream" 2>&1)"; rc=$?
  [ "$rc" != 0 ] && case "$saida" in *'branch sem remote de upstream'*) true ;; *) false ;; esac \
    && passa 'sem upstream: falha, nunca cai para origin' || quebra "sem upstream: (rc $rc) $saida"
  case "$f" in *origin*) quebra 'resolver_remoto_upstream ainda cita origin' ;; *) passa 'resolver_remoto_upstream nao cita origin' ;; esac
fi

echo '== E7: identidade do remoto =='
f="$(funcao_do_e7 identidade_remota)"
if [ -z "$f" ]; then
  quebra 'o E7 nao define identidade_remota: destino e origem nao sao normalizados'
else
  for par in 'https://github.com/acme/login.git|github.com/acme/login' \
             'https://github.com/acme/login|github.com/acme/login' \
             'git@github.com:ana/login.git|github.com/ana/login' \
             'ssh://git@gitlab.example.com:2222/grupo/sub/proj.git|gitlab.example.com/grupo/sub/proj' \
             '/caminho/local/repo.git|' 'https://exemplo.com/a b/c.git|'; do
    url="${par%%|*}"; esperado="${par#*|}"
    saida="$(URL="$url" bash -c "git() { [ \"\$1 \$2\" = 'remote get-url' ] && printf '%s\n' \"\$URL\"; }
$f
identidade_remota r" 2>&1)"; rc=$?
    if [ -z "$esperado" ]; then
      [ "$rc" != 0 ] && passa "formato desconhecido falha fechado: $url" || quebra "aceitou $url como '$saida'"
    else
      [ "$rc" = 0 ] && [ "$saida" = "$esperado" ] && passa "$url -> $esperado" || quebra "$url: (rc $rc) '$saida'"
    fi
  done
fi

echo '== E7: passo 1.5 (base e medicao) =='
git init -q --bare -b main "$aux/remoto.git"
git clone -q "$aux/remoto.git" "$aux/dev" 2>/dev/null
mkdir -p "$aux/dev/docs/entregas/x"
printf '%s\n' '---' 'kind: entrega' 'trabalho_id: x' 'sprint_atual: null' 'prs: []' '---' > "$aux/dev/docs/entregas/x/ENTREGA.md"
printf 'base\n' > "$aux/dev/base.txt"; g "$aux/dev" add -A; g "$aux/dev" commit -q -m base; g "$aux/dev" push -q origin main 2>/dev/null
g "$aux/dev" switch -q -c feature/x; printf 'linha\n' > "$aux/dev/a.md"; g "$aux/dev" add -A; g "$aux/dev" commit -q -m a
g "$aux/dev" push -q -u origin feature/x 2>/dev/null
passo15() { # <branch_base> — o bloco do passo 1.5, com a base trocada literalmente
  local b; b="$(bloco_do_e7 'fatiamento-da-pr.sh "$@" "$base" "$publicado"')"
  b="${b//'<branch_base>'/$1}"; b="${b//'<trabalho_id>'/x}"
  b="${b//'bash .claude/skills/mergex/scripts/'/bash $raiz/.claude/skills/mergex/scripts/}"
  printf '%s\n' "$b" > "$aux/passo15.sh"
  (cd "$aux/dev" && bash "$aux/passo15.sh" > "$aux/p15.out" 2>&1)
}
rm -f "$aux/sentinela"
passo15 'main$(touch '"$aux"'/sentinela)`touch '"$aux"'/sentinela`'
[ ! -e "$aux/sentinela" ] && passa 'branch_base com $(...) e crase nao executa nada no shell' \
  || quebra 'a branch_base foi avaliada pelo shell: $(...) ou crase executou'
g "$aux/dev" remote set-url origin "$aux/nao-existe.git"
passo15 main; rc=$?
[ "$rc" = 2 ] && passa 'busca do upstream que falha: sai 2 (nao medido), nunca 1 (reprovado)' \
  || quebra "busca do upstream que falha saiu $rc, esperado 2: $(tr '\n' '|' < "$aux/p15.out")"
g "$aux/dev" remote set-url origin "$aux/remoto.git"

echo '== E7: passo 2 (destino, origem e rascunho) =='
mkdir -p "$aux/bin"
cat > "$aux/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGS_GH"
EOF
cat > "$aux/bin/glab" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "api projects/"*) printf '{"id":42}\n' ;;
  "mr list") p=1; ant=""; for a in "$@"; do [ "$ant" = --page ] && p="$a"; ant="$a"; done
             if [ -f "$GLAB_PAGINAS/$p.json" ]; then cat "$GLAB_PAGINAS/$p.json"; else printf '[]\n'; fi ;;
  "mr create") printf '%s\n' "$@" > "$ARGS_GLAB" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$aux/bin/gh" "$aux/bin/glab"
projeto_pr() { # <dir> <url origin> <url fork> <remoto do upstream> — branch feature/x com upstream
  local d="$1"; git init -q -b main "$d"; printf 'x\n' > "$d/x"; g "$d" add -A; g "$d" commit -q -m x
  g "$d" switch -q -c feature/x
  git -C "$d" remote add origin "$2"; git -C "$d" remote add fork "$3"
  git -C "$d" update-ref "refs/remotes/$4/feature/x" HEAD
  git -C "$d" config branch.feature/x.remote "$4"; git -C "$d" config branch.feature/x.merge refs/heads/feature/x
  mkdir -p "$d/docs/entregas/x"; printf 'corpo\n' > "$d/docs/entregas/x/PR.md"
  printf 'origin\nmain\n' > "$(git -C "$d" rev-parse --path-format=absolute --git-path mergex-e7-base)"
}
passo2() { # <dir> <trecho do bloco> — roda o bloco do passo 2 no projeto
  local b; b="$(bloco_do_e7 "$2")"; b="${b//'<título>'/titulo}"; b="${b//'<trabalho_id>'/x}"
  printf '%s\n' "$b" > "$aux/passo2.sh"
  rm -f "$aux/args-gh" "$aux/args-glab"
  (cd "$1" && PATH="$aux/bin:$PATH" ARGS_GH="$aux/args-gh" ARGS_GLAB="$aux/args-glab" GLAB_PAGINAS="$aux/paginas" \
     bash "$aux/passo2.sh" > "$aux/p2.out" 2>&1)
}
args() { tr '\n' ' ' < "$1" 2>/dev/null; }

projeto_pr "$aux/fork" https://github.com/acme/login.git git@github.com:ana/login.git fork
passo2 "$aux/fork" 'gh pr create'
case "$(args "$aux/args-gh")" in
  *'--repo github.com/acme/login --base main --head ana:feature/x '*) passa 'fork no GitHub: abre no destino, com head dono:branch' ;;
  *) quebra "fork no GitHub: args '$(args "$aux/args-gh")' $(tr '\n' '|' < "$aux/p2.out")" ;;
esac
projeto_pr "$aux/mesmo" https://github.com/acme/login.git git@github.com:ana/login.git origin
passo2 "$aux/mesmo" 'gh pr create'
case "$(args "$aux/args-gh")" in
  *'--repo github.com/acme/login --base main --head feature/x '*) passa 'mesmo projeto: head sem dono' ;;
  *) quebra "mesmo projeto: args '$(args "$aux/args-gh")'" ;;
esac
case "$(args "$aux/args-gh")" in *--draft*) passa 'QA nao aprovado: rascunho' ;; *) quebra 'QA nao aprovado e o PR nao saiu rascunho' ;; esac
mkdir -p "$aux/mesmo/docs/manutencao/x"; printf 'VEREDITO: APROVADO\n' > "$aux/mesmo/docs/manutencao/x/QA.md"
passo2 "$aux/mesmo" 'gh pr create'
case "$(args "$aux/args-gh")" in *--draft*) quebra 'QA aprovado e o PR ainda saiu rascunho' ;; '') quebra "QA aprovado: gh nao chamado $(tr '\n' '|' < "$aux/p2.out")" ;; *) passa 'QA aprovado: sem --draft' ;; esac

projeto_pr "$aux/gl" https://gitlab.example.com/acme/login.git git@gitlab.example.com:ana/login.git fork
mkdir -p "$aux/paginas"
mr() { printf '{"source_branch":"%s","source_project_id":%s,"target_branch":"%s","web_url":"%s"}' "$1" "$2" "$3" "$4"; }
irrelevantes="$(for i in $(seq 1 100); do mr feature/x $((1000 + i)) main "https://gl/mr/$i"; [ "$i" = 100 ] || printf ','; done)"
printf '[]\n' > "$aux/paginas/1.json"
passo2 "$aux/gl" 'glab mr create'
case "$(args "$aux/args-glab")" in
  *'--repo https://gitlab.example.com/acme/login --head https://gitlab.example.com/ana/login --target-branch main --source-branch feature/x '*)
    passa 'GitLab sem MR aberta: cria no destino, com a origem pela URL completa' ;;
  *) quebra "GitLab sem MR: args '$(args "$aux/args-glab")' $(tr '\n' '|' < "$aux/p2.out")" ;;
esac
printf '[%s]\n' "$irrelevantes" > "$aux/paginas/1.json"; printf '[%s]\n' "$(mr feature/x 42 main https://gl/mr/alvo)" > "$aux/paginas/2.json"
passo2 "$aux/gl" 'glab mr create'; rc=$?
[ "$rc" = 0 ] && [ ! -e "$aux/args-glab" ] && passa 'GitLab: a MR da origem, na segunda pagina, e retomada sem criar outra' \
  || quebra "GitLab retomada paginada: rc $rc, create $( [ -e "$aux/args-glab" ] && echo chamado || echo nao) $(tr '\n' '|' < "$aux/p2.out")"
printf '[%s]\n' "$(mr feature/x 42 release https://gl/mr/outra-base)" > "$aux/paginas/1.json"; rm -f "$aux/paginas/2.json"
passo2 "$aux/gl" 'glab mr create'
[ -e "$aux/args-glab" ] && passa 'GitLab: MR da origem para outra base nao conta, e a nova e criada' \
  || quebra "GitLab outra base: create nao chamado $(tr '\n' '|' < "$aux/p2.out")"
printf '[%s,%s]\n' "$(mr feature/x 42 main https://gl/mr/a)" "$(mr feature/x 42 main https://gl/mr/b)" > "$aux/paginas/1.json"
passo2 "$aux/gl" 'glab mr create'; rc=$?
[ "$rc" != 0 ] && [ ! -e "$aux/args-glab" ] && passa 'GitLab: duas MRs abertas da origem falham fechado' \
  || quebra "GitLab duas MRs: rc $rc"

printf -- '---------------------------------------------\n%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
