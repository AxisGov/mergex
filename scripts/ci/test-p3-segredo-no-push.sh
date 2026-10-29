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

repo referencia; printf 'const u = { pass%s: hashedPassword, nome }\n' word > "$R/a.ts"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && passa 'referencia de codigo seguida de virgula: passa (DM-283)' || quebra "referencia: $(mostra)"

repo referencia-fim; printf 'pass%s: SuperSecret\n' word > "$R/a.yml"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && diz 'credencial' && passa 'mesmo valor no fim da linha: barra' || quebra "referencia no fim: $(mostra)"

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
# Com o SHA remoto conhecido aqui, buscar nao muda a conta: o diagnostico nao manda rodar fetch.
! diz 'git fetch' && passa 'acima do limite com o remoto conhecido: sem sugerir git fetch' || quebra "limite com remoto conhecido: $(mostra)"
modo aviso; empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && diz 'grande demais' && passa 'acima de 300 commits em aviso: diagnostica e segue' || quebra "limite aviso: $(mostra)"
# Branch nova: o intervalo e delimitado pelo que o servidor anuncia E existe aqui. So quando o
# servidor anuncia algo que falta aqui (clone defasado) buscar muda a conta, e so ai o diagnostico
# manda rodar git fetch (katosmv/login#34; nitpick do CodeAnt no mergex#56).
repo limite-nova; g checkout -q -b nova; for i in $(seq 1 301); do g commit -q --allow-empty -m "n$i"; done
empurra refs/heads/nova refs/heads/nova
[ "$rc" = 1 ] && diz 'grande demais' && ! diz 'git fetch' \
  && passa 'acima do limite, tudo o que o servidor anuncia ja esta aqui: sem sugerir git fetch' || quebra "limite sem defasagem: $(mostra)"
# o servidor tem um commit que este clone nao tem: buscar delimita o intervalo
outro="$aux/limite-nova-outro"; git clone -q "$aux/limite-nova.git" "$outro"
git -C "$outro" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m remoto
git -C "$outro" push -q origin HEAD:refs/heads/so-no-servidor 2>/dev/null
empurra refs/heads/nova refs/heads/nova
[ "$rc" = 1 ] && diz 'grande demais' && diz 'git fetch origin' \
  && passa 'acima do limite com clone defasado: manda rodar git fetch' || quebra "limite com clone defasado: $(mostra)"
# Push direto para uma URL: o Git passa a URL como nome do remoto, e ela pode trazer credencial.
# O diagnostico manda buscar sem repetir a URL (revisao do Codex).
sl="$(g rev-parse refs/heads/nova)"
printf 'refs/heads/nova %s refs/heads/nova %s\n' "$sl" "$ZERO" \
  | (cd "$R" && bash "$PUSH" --pre-push "https://u:$(printf 's3nh4%s' Xpto)@exemplo.invalid/r.git" "$(g remote get-url origin)") > "$aux/out" 2> "$aux/err"; rc=$?
[ "$rc" = 1 ] && diz 'git fetch' && ! diz 's3nh4Xpto' \
  && passa 'push para URL com credencial: o diagnostico nao repete a URL' || quebra "push para URL: $(mostra)"

echo '== o arquivo do framework que o lock do commit confere nao e varrido (DM-286) =='
# Com o lock v2 DO PROPRIO COMMIT: um lock posterior nao perdoa um commit anterior.
sha_de() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
lock_em() { mkdir -p "$R/.expx"; jq -n --arg p "$1" --arg h "$2" \
  '{lock_version:2,cli_version:"0.12.9",harness:["claude"],skills:{},instalacao:{arquivos:{($p):$h}}}' > "$R/.expx/expx-lock.json"; }
FWP=".claude/hooks/fw.sh"
repo lockok; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 0 ] && passa 'lock: arquivo do framework com o hash do lock do commit: passa' || quebra "lock ok: $(mostra)"
repo lockmsg; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita "chave $SK"
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'lock: segredo na mensagem continua barrando' || quebra "lock msg: $(mostra)"
repo lockdiv; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(printf '%064d' 0)"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'lock: hash que nao bate: barra' || quebra "lock divergente: $(mostra)"
repo lockdepois; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; commita a
lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita b
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'lock: lock posterior nao perdoa o commit anterior: barra' || quebra "lock posterior: $(mostra)"
repo locktag; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita
g tag -a v1 -m "chave $SK"
empurra refs/tags/v1 refs/tags/v1
[ "$rc" = 1 ] && passa 'lock: tag anotada com segredo sobre commit dispensado: barra' || quebra "lock tag: $(mostra)"
repo lockruim; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"
jq --arg k "$(printf '.claude/hooks/a\nb')" --arg h "$(printf '%064d' 0)" '.instalacao.arquivos[$k] = $h' "$R/.expx/expx-lock.json" > "$aux/l.tmp" \
  && mv "$aux/l.tmp" "$R/.expx/expx-lock.json"; commita
empurra refs/heads/main refs/heads/main
[ "$rc" = 1 ] && passa 'lock: chave malformada invalida o lock do commit: barra' || quebra "lock chave ruim: $(mostra)"
repo locksemsha; mkdir -p "$R/.claude/hooks"; printf 'K=%s\n' "$SK" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita
mkdir -p "$aux/semsha"; printf '#!/bin/sh\nexit 1\n' > "$aux/semsha/sha256sum"; cp "$aux/semsha/sha256sum" "$aux/semsha/shasum"
chmod +x "$aux/semsha/sha256sum" "$aux/semsha/shasum"
empurra refs/heads/main refs/heads/main PATH="$aux/semsha:$PATH"
[ "$rc" = 1 ] && passa 'lock: sem sha256 que funcione: barra' || quebra "lock sem sha: $(mostra)"

echo '== cada commit e lido uma vez so =='
# Com achado, a segunda fase dizia onde relendo cada commit no Git: log, rev-list e diff
# de novo, ~1.800 processos em 300 commits (A4 do CodeAnt no conselhos#211). Agora ela le
# o que a primeira fase guardou. Um wrapper no PATH conta as chamadas, so durante o portao.
repo umavez
for i in $(seq 1 12); do printf '%s\n' "$i" > "$R/n.txt"; commita "c$i"; done
printf 'K=%s\n' "$SK" > "$R/a.txt"; commita
mkdir -p "$aux/bin"; GIT_REAL="$(command -v git)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/chamadas"\nexec "%s" "$@"\n' "$aux" "$GIT_REAL" > "$aux/bin/git"
chmod +x "$aux/bin/git"; : > "$aux/chamadas"
empurra refs/heads/main refs/heads/main PATH="$aux/bin:$PATH"
conta() { n_log="$(grep -c '^log -1 --format=%B' "$aux/chamadas")"; n_par="$(grep -c '^rev-list --parents' "$aux/chamadas")"; n_dif="$(grep -c '^diff --text' "$aux/chamadas")"
  n_lck="$(grep -c '^cat-file -s .*:\.expx/expx-lock\.json$' "$aux/chamadas")"; n_nom="$(grep -cE '^diff(-tree)? .*--name-only' "$aux/chamadas")"; n_lst="$(grep -c '^ls-tree' "$aux/chamadas")"; }
conta
[ "$rc" = 1 ] && diz 'chave de API' && [ "$n_log" = 13 ] && [ "$n_par" = 13 ] && [ "$n_dif" = 13 ] \
  && passa 'com achado, 13 commits: uma leitura de cada no Git' || quebra "uma vez: log $n_log, parents $n_par, diff $n_dif (esperava 13) | $(mostra)"
# Sem lock nos commits, a dispensa (DM-286) custa uma consulta ao lock por commit, e so.
[ "$n_lck" = 13 ] && [ "$n_nom" = 0 ] && [ "$n_lst" = 0 ] \
  && passa 'sem lock: uma consulta ao lock por commit, nenhuma lista nem ls-tree' || quebra "sem lock: lock $n_lck, nomes $n_nom, ls-tree $n_lst (esperava 13, 0, 0)"
# Duas refs com os mesmos 13 commits no mesmo push: a segunda le o que a primeira guardou.
g branch outra main; : > "$aux/chamadas"
printf 'refs/heads/main %s refs/heads/main %s\nrefs/heads/outra %s refs/heads/outra %s\n' \
  "$(g rev-parse main)" "$(g ls-remote origin refs/heads/main | awk '{print $1}')" "$(g rev-parse outra)" "$ZERO" \
  | (cd "$R" && PATH="$aux/bin:$PATH" bash "$PUSH" --pre-push origin "$(g remote get-url origin)") > "$aux/out" 2> "$aux/err"; rc=$?
conta
[ "$rc" = 1 ] && [ "$(grep -c 'no commit' "$aux/err")" -ge 2 ] && [ "$n_log" = 13 ] && [ "$n_par" = 13 ] && [ "$n_dif" = 13 ] \
  && passa 'duas refs com os mesmos commits: uma leitura de cada no push' || quebra "duas refs: log $n_log, parents $n_par, diff $n_dif (esperava 13) | $(mostra)"
# Com lock em cada commit: o lock e a lista de alterados uma vez por commit, e um ls-tree por
# arquivo elegivel alterado.
repo comlock; mkdir -p "$R/.claude/hooks"
for i in $(seq 1 5); do printf 'v%s\n' "$i" > "$R/$FWP"; lock_em "$FWP" "$(sha_de "$R/$FWP")"; commita "c$i"; done
printf 'K=%s\n' "$SK" > "$R/a.txt"; commita; : > "$aux/chamadas"
empurra refs/heads/main refs/heads/main PATH="$aux/bin:$PATH"
conta
[ "$rc" = 1 ] && [ "$n_log" = 6 ] && [ "$n_lck" = 6 ] && [ "$n_nom" = 6 ] && [ "$n_lst" = 5 ] \
  && passa 'com lock: uma consulta ao lock e uma lista por commit, um ls-tree por arquivo' || quebra "com lock: log $n_log, lock $n_lck, nomes $n_nom, ls-tree $n_lst (esperava 6, 6, 6, 5) | $(mostra)"

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

echo '== o reference diz o que o modo faz com a falha de leitura =='
# Em `aviso`, falha de leitura avisa e o push segue, como o portao faz; o reference prometia
# bloqueio em todo modo (katosmv/login#34).
ref12="$raiz/.claude/skills/mergex/references/12-barreira-de-push.md"
! grep -q 'Qualquer falha de leitura' "$ref12" && grep -q 'falha de leitura nunca conta como limpo' "$ref12" \
  && passa '12-barreira: falha de leitura barra em bloqueio e avisa em aviso' || quebra '12-barreira: a frase da falha de leitura promete bloqueio em todo modo'

printf -- '---------------------------------------------\n%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
