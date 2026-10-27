#!/usr/bin/env bash
# Varredura de segredo no pre-push (katosmv/conselhos-municipais#210, P3; DM-279).
#
# O portao-push.sh, chamado pelo pre-push do Git, varre o que o push publica — as
# mensagens e as linhas adicionadas de cada commit que o remoto ainda não tem, e a
# mensagem das tags anotadas — com a mesma tabela do sem-segredo
# (skills/mergex/scripts/segredo-tabela.sh). É a segunda camada: pega o que o
# PreToolUse não vê (segredo gerado pelo próprio comando, commit feito por fora).
#
# Os segredos são montados em pedaços AQUI, mas gravados já unidos nos commits da
# fixture: o arquivo de teste não carrega nenhum, e a detecção é real.
set -uo pipefail
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUSH="$raiz/.claude/skills/mergex/scripts/portao-push.sh"
OK=0; FALHOU=0
passa()  { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
quebra() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT

SK="sk-$(printf 'abcdef1234567890QRS')"
ZERO=0000000000000000000000000000000000000000
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
# repo <nome> — repositório com remoto bare `origin` e a main já publicada
repo() {
  R="$aux/$1"; git init -q -b main "$R"; git init -q --bare "$aux/$1.git"
  printf 'base\n' > "$R/base.txt"; g add -A; g commit -q -m base
  g remote add origin "$aux/$1.git"; g push -q origin main 2>/dev/null
}
commita() { g add -A && g commit -q -m "${1:-x}"; }
# empurra <ref local> <ref remota> [VAR=valor...] — o protocolo do pre-push, como o Git o entrega
empurra() {
  local rl="$1" rr="$2" sl sr; shift 2
  # O SHA remoto é o que o servidor anuncia, como o Git o entrega ao hook — não a ref
  # de rastreio, que é cache local (CodeAnt no mergex#54).
  sl="$(g rev-parse "$rl")"; sr="$(g ls-remote origin "$rr" | awk 'NR == 1 { print $1 }')"; sr="${sr:-$ZERO}"
  printf '%s %s %s %s\n' "$rl" "$sl" "$rr" "$sr" \
    | (cd "$R" && env "$@" bash "$PUSH" --pre-push origin "${URL_PUSH:-$(g remote get-url origin)}") > "$aux/out" 2> "$aux/err"; rc=$?
}
modo() { mkdir -p "$R/.expx"; printf '{"expx_hooks":1,"hooks":{"sem-segredo":{"modo":"%s"}}}\n' "$1" > "$R/.expx/hooks.json"; }
diz() { grep -q -- "$1" "$aux/err"; }
mostra() { printf 'rc %s | %s' "$rc" "$(tr '\n' '|' < "$aux/err")"; }

echo '== o que o push publica e varrido =='
repo limpo; printf 'ok\n' > "$R/a.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && passa 'commit limpo: passa' || quebra "limpo: $(mostra)"

repo linha; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && diz 'chave de API' && ! grep -q "$SK" "$aux/err" \
  && passa 'segredo em linha adicionada: barra, mascarado' || quebra "linha: $(mostra)"

repo mensagem; printf 'ok\n' > "$R/a.txt"; commita "deploy com $SK"
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && diz 'chave de API' && passa 'segredo so na mensagem do commit: barra' || quebra "mensagem: $(mostra)"

repo some; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita; printf 'ok\n' > "$R/a.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'adicionado e removido dentro do intervalo: barra (a historia o guarda)' || quebra "some: $(mostra)"

repo publicado; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita; g push -q origin main 2>/dev/null
printf 'ok\n' > "$R/b.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && passa 'segredo so em commit que o remoto ja tem: passa' || quebra "publicado: $(mostra)"

repo placeholder; printf 'token: "placeholder"\nK=sk-your-key-here-xxxxxxxxxx\n' > "$R/a.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && passa 'placeholder: passa' || quebra "placeholder: $(mostra)"

repo nova; g checkout -q -b feature/x; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
empurra refs/heads/feature/x refs/heads/feature/x
[ "$rc" = 1 ] && passa 'branch nova (remoto sem a ref): barra' || quebra "branch nova: $(mostra)"

echo '== merge, tag e exclusao =='
repo evil; g checkout -q -b lado; printf 'lado\n' > "$R/l.txt"; commita lado
g checkout -q main; printf 'main\n' > "$R/m.txt"; commita main
g merge -q --no-ff --no-commit lado 2>/dev/null; printf 'K=%s\n' "$SK" > "$R/so-no-merge.txt"; g add -A; g commit -q -m merge
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'segredo so na resolucao do merge ("evil merge"): barra' || quebra "evil merge: $(mostra)"

repo tagleve; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita; g tag v1
printf 'refs/tags/v1 %s refs/tags/v1 %s\n' "$(g rev-parse v1)" $ZERO \
  | (cd "$R" && bash "$PUSH" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 1 ] && passa 'tag leve sobre commit nao publicado com segredo: barra' || quebra "tag leve: $(mostra)"

repo taganotada; g tag -a v2 -m "release $SK"
printf 'refs/tags/v2 %s refs/tags/v2 %s\n' "$(g rev-parse v2)" $ZERO \
  | (cd "$R" && bash "$PUSH" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 1 ] && diz 'tag' && passa 'segredo so na mensagem da tag anotada: barra' || quebra "tag anotada: $(mostra)"

repo tagcadeia; g tag -a interna -m "interna $SK"; g tag -a externa -m "externa limpa" interna
printf 'refs/tags/externa %s refs/tags/externa %s\n' "$(g rev-parse externa)" $ZERO \
  | (cd "$R" && bash "$PUSH" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 1 ] && passa 'segredo na tag anotada interna de uma cadeia de tags: barra' || quebra "cadeia de tags: $(mostra)"

repo exclusao
printf 'refs/heads/velha %s refs/heads/velha %s\n' $ZERO "$(g rev-parse main)" \
  | (cd "$R" && bash "$PUSH" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 0 ] && passa 'exclusao de ref: nada a varrer, passa' || quebra "exclusao: $(mostra)"

echo '== o que o servidor ja tem (nao a ref de rastreio) =='
# A ref de rastreio e cache local: adiantada sobre o servidor (ou de outra URL), ela
# esconderia um commit que o servidor nao tem (CodeAnt no mergex#54).
repo adiantada; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita; g update-ref refs/remotes/origin/main HEAD
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && diz 'chave de API' && passa 'ref de rastreio adiantada sobre o servidor: barra' || quebra "adiantada: $(mostra)"
repo adiantada-nova; g checkout -q -b feature/y; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
g update-ref refs/remotes/origin/feature/y HEAD
empurra refs/heads/feature/y refs/heads/feature/y
[ "$rc" = 1 ] && passa 'branch nova com rastreio falso apontando para ela: barra' || quebra "adiantada nova: $(mostra)"
# Branch nova num repositorio maduro: o que o servidor anuncia delimita o intervalo,
# sem ref de rastreio nenhuma, e o limite de 300 nao e atingido pelo que ja e dele.
repo maduro; for i in $(seq 1 305); do g commit -q --allow-empty -m "c$i"; done; g push -q origin main 2>/dev/null
for r in $(g for-each-ref --format='%(refname)' refs/remotes); do g update-ref -d "$r"; done
g checkout -q -b feature/z; printf 'ok\n' > "$R/z.txt"; commita
empurra refs/heads/feature/z refs/heads/feature/z
[ "$rc" = 0 ] && passa 'branch nova limpa sobre 305 commits ja publicados, sem rastreio: passa' || quebra "maduro: $(mostra)"
URL_PUSH="$aux/nao-existe.git" empurra refs/heads/feature/z refs/heads/feature/z
[ "$rc" = 1 ] && diz 'ls-remote' && passa 'consulta ao servidor que falha: barra (falha fechada)' || quebra "ls-remote: $(mostra)"

# A prova funcional do E0 empurra commits soltos sobre o HEAD para `file:///dev/null`,
# que nao publica nada: o controle positivo tem de passar mesmo num repositorio maduro.
c_prova="$(g commit-tree "$(g mktree </dev/null)" -p HEAD -m prova)"
printf 'refs/heads/mergex-prova-livre-1 %s refs/heads/mergex-prova-livre-1 %s\n' "$c_prova" $ZERO \
  | (cd "$R" && bash "$PUSH" --pre-push prova-mergex file:///dev/null) > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 0 ] && passa 'prova do E0 (file:///dev/null) sobre 306 commits: passa' || quebra "prova E0: $(mostra)"

echo '== modo, limite e sinal =='
repo aviso; modo aviso; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
: > "$aux/sinal"; empurra refs/heads/main refs/heads/main MERGEX_PRE_PUSH_SINAL="$aux/sinal"
[ "$rc" = 0 ] && diz 'chave de API' && grep -q ' avisa$' "$aux/sinal" \
  && passa 'modo aviso: diagnostica, segue e o sinal diz avisa' || quebra "aviso: $(mostra) sinal $(cat "$aux/sinal")"

repo bloqueio; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
: > "$aux/sinal"; empurra refs/heads/main refs/heads/main MERGEX_PRE_PUSH_SINAL="$aux/sinal"
[ "$rc" = 1 ] && grep -q ' barra$' "$aux/sinal" && passa 'bloqueio: o sinal diz barra' || quebra "sinal barra: $(mostra)"

repo desligado; modo desligado; printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && ! diz 'segredo' && passa 'desligado: nao varre' || quebra "desligado: $(mostra)"

repo limite; for i in $(seq 1 301); do g commit -q --allow-empty -m "c$i"; done
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && diz 'grande demais' && passa 'acima de 300 commits em bloqueio: barra' || quebra "limite bloqueio: $(mostra)"
modo aviso; empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && diz 'grande demais' && passa 'acima de 300 commits em aviso: diagnostica e segue' || quebra "limite aviso: $(mostra)"

echo '== falha fechada =='
copia="$aux/instalacao"; mkdir -p "$copia/.claude/skills/mergex" "$copia/.claude/hooks"
cp -R "$raiz/.claude/skills/mergex/scripts" "$copia/.claude/skills/mergex/"
cp -R "$raiz/.claude/hooks/comum" "$copia/.claude/hooks/"
rm -f "$copia/.claude/skills/mergex/scripts/segredo-tabela.sh"
repo semtabela; printf 'ok\n' > "$R/a.txt"; commita
printf 'refs/heads/main %s refs/heads/main %s\n' "$(g rev-parse main)" "$(g rev-parse origin/main)" \
  | (cd "$R" && bash "$copia/.claude/skills/mergex/scripts/portao-push.sh" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 1 ] && diz 'tabela' && passa 'sem a tabela de segredo: barra, mesmo com push limpo' || quebra "sem tabela: $(mostra)"
modo desligado
printf 'refs/heads/main %s refs/heads/main %s\n' "$(g rev-parse main)" "$(g rev-parse origin/main)" \
  | (cd "$R" && bash "$copia/.claude/skills/mergex/scripts/portao-push.sh" --pre-push origin "$aux/x.git") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 0 ] && passa 'sem a tabela, mas desligado: nao exige a tabela' || quebra "sem tabela desligado: $(mostra)"

printf -- '---------------------------------------------\n%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
