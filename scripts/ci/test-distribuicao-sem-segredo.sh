#!/usr/bin/env bash
# A distribuição da MergeX passa pela própria varredura de segredo (DM-282).
#
# O que a instalação copia para o projeto vai para o commit dele, e o pre-push
# (DM-279) varre o que o push publica. Na 0.12.5, exemplos fictícios do próprio
# texto da MergeX (`usuario:senha@`, a senha iniciada por `!`) barraram o push do
# commit que instalava a versão no katosmv/login.
#
# Aqui a instalação é a de verdade: os dois blocos do README (Claude Code e
# OpenCode) rodam num projeto descartável, com a árvore de trabalho desta MergeX
# no lugar do `git clone`. Cada arquivo que a instalação deixou é varrido INTEIRO
# com a mesma tabela (scripts/segredo-tabela.sh) — mais estrito que o pre-push,
# que olha só as linhas adicionadas — e o primeiro push do projeto passa pelo
# portao-push.sh. A suíte dos hooks (`hooks/teste.sh`, `hooks/testes/`) carrega
# amostras adversariais de propósito e não pode chegar ao projeto.
set -uo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUSH="$raiz/.claude/skills/mergex/scripts/portao-push.sh"
# shellcheck source=../../.claude/skills/mergex/scripts/segredo-tabela.sh
. "$raiz/.claude/skills/mergex/scripts/segredo-tabela.sh"
OK=0; FALHOU=0
passa()  { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
ZERO=0000000000000000000000000000000000000000

# varre <arquivo> — imprime os achados da tabela sobre o arquivo inteiro. Arquivo que
# não se lê não é arquivo limpo: sai como achado, para a lista errada não passar.
varre() {
  [ -f "$1" ] && [ -r "$1" ] || { printf '  - ilegivel: %s\n' "$1"; return; }
  ALVO="$(cat "$1")"; segredo_varrer; printf '%s' "$ACHADOS"
}

# bloco <titulo da secao> — o primeiro bloco ```bash depois do titulo, no README
bloco() {
  awk -v t="$1" '
    $0 == t { achou = 1; next }
    achou && /^```bash$/ { dentro = 1; next }
    dentro && /^```$/ { exit }
    dentro { print }
  ' "$raiz/README.md"
}

# instala <titulo> <projeto> — roda o bloco do README no projeto, com a árvore de
# trabalho desta MergeX no lugar do clone (o que ainda não foi commitado conta)
instala() {
  local script
  script="$aux/instala-$(printf '%s' "$1" | tr -c 'A-Za-z' '_').sh"
  bloco "$1" | awk -v r="$raiz" '
    /^git clone https:\/\/github\.com\/AxisGov\/mergex\.git / {
      print "mkdir -p \"$mergex_tmp/mergex\" && (cd \"" r "\" && git ls-files -z | xargs -0 tar -cf -) | tar -C \"$mergex_tmp/mergex\" -xf -"
      next
    }
    { print }
  ' > "$script"
  grep -q 'tar -C "$mergex_tmp/mergex" -xf -' "$script" || { quebra "$1: bloco do README sem o git clone esperado"; return 1; }
  git init -q -b main "$2" && (cd "$2" && bash -e "$script") > "$aux/inst.out" 2>&1 \
    || { quebra "$1: a instalacao do README falhou: $(tr '\n' '|' < "$aux/inst.out")"; return 1; }
}

echo '== controles da varredura =='
printf 'DB=postgres://app:%s@db/x\n' "s3nh4-real-$(printf 'Qx9')" > "$aux/real.txt"
[ -n "$(varre "$aux/real.txt")" ] && passa 'credencial real em URL: acusada' || quebra 'credencial real passou'
printf 'DB=postgres://app:<senha>@db/x\npassword: "<senha>"\n' > "$aux/ph.txt"
[ -z "$(varre "$aux/ph.txt")" ] && passa 'placeholder inteiro: passa' || quebra "placeholder acusado: $(varre "$aux/ph.txt")"
[ -n "$(varre "$aux/nao-existe.txt")" ] && passa 'arquivo ausente: acusado, nao limpo' || quebra 'arquivo ausente passou como limpo'

for secao in '### Claude Code' '### OpenCode'; do
  echo "== instalacao do README: $secao =="
  P="$aux/projeto-$(printf '%s' "$secao" | tr -c 'A-Za-z' '_')"
  instala "$secao" "$P" || continue

  n="$(git -C "$P" ls-files -o | wc -l | tr -d ' ')"
  [ "$n" -gt 50 ] && passa "$n arquivos instalados" || quebra "so $n arquivos instalados: a instalacao esta errada"
  if [ -e "$P/.claude/hooks/teste.sh" ] || [ -e "$P/.claude/hooks/testes" ]; then
    quebra 'a suite dos hooks chegou ao projeto'
  else
    passa 'a suite dos hooks nao chega ao projeto'
  fi
  faltam=""
  while IFS= read -r h; do
    [ -f "$P/$h" ] || faltam="$faltam $h"
  done < <(git -C "$raiz" ls-files -- .claude/hooks | grep -Ev '^\.claude/hooks/teste\.sh$|^\.claude/hooks/testes/')
  [ -z "$faltam" ] && passa 'todo hook da fonte, menos a suite, chegou ao projeto' || quebra "hooks que nao chegaram:$faltam"

  sujos=""
  while IFS= read -r f; do
    a="$(varre "$P/$f")"
    [ -z "$a" ] || sujos="$sujos$f:"$'\n'"$a"$'\n'
  done < <(git -C "$P" ls-files -o)
  if [ -z "$sujos" ]; then passa 'cada arquivo instalado, inteiro: sem achado'; else quebra 'achados no que a instalacao deixou:'; printf '%s' "$sujos"; fi

  g() { git -C "$P" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
  git init -q --bare "$P.git"
  g add -A && g commit -q -m 'instala a mergex' && g remote add origin "$P.git"
  printf 'refs/heads/main %s refs/heads/main %s\n' "$(g rev-parse HEAD)" "$ZERO" \
    | (cd "$P" && bash "$PUSH" --pre-push origin "$P.git") > "$aux/out" 2> "$aux/err"; rc=$?
  [ "$rc" = 0 ] && passa 'primeiro push do projeto: passa' \
    || quebra "primeiro push barrado (rc $rc): $(tr '\n' '|' < "$aux/err")"
done

printf '\n%s ok, %s falhas\n' "$OK" "$FALHOU"
[ "$FALHOU" -eq 0 ]
