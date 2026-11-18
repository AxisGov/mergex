#!/usr/bin/env bash
# A varredura de worktrees so remove o que esta entregue e sem nada que se perca.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$RAIZ/.claude/skills/mergex/scripts/worktrees-entregues.sh"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
ok=0; falhou=0
afirma() { if [ "$2" = 0 ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; fi; }

g() { git -C "$T/r" -c user.name=t -c user.email=t@t "$@"; }
git init -q --bare "$T/origem.git"
git init -q -b main "$T/r"; printf 'node_modules/\ndist/\ncoverage/\n.mypy_cache/\ndocs/eventos/\n' > "$T/r/.gitignore"; printf 'a\n' > "$T/r/a"
# manifestos de build: so com eles ao lado `dist/` e `coverage/` sao saida de build (DM-333)
mkdir -p "$T/r/packages/p"; printf '{}\n' > "$T/r/package.json"; printf '{}\n' > "$T/r/packages/p/package.json"
g add .; g commit -q -m base; g remote add origin "$T/origem.git"; g push -q origin main

wt() { # wt <nome> — branch e worktree novos, com um commit
  g worktree add -q -b "b-${1// /-}" "$T/$1" main
  printf '%s\n' "$1" > "$T/$1/f-${1// /-}"
  git -C "$T/$1" add .; git -C "$T/$1" -c user.name=t -c user.email=t@t commit -q -m "$1"
}
integra() { g merge -q --no-ff --no-edit "b-${1// /-}"; g push -q origin main; }
linha() { grep -F "$T/$1	" "$T/saida" || printf 'ausente\n'; }
estado() { linha "$1" | cut -f1; }
motivo() { linha "$1" | cut -f2; }

wt entregue; integra entregue
wt comcache; integra comcache; mkdir -p "$T/comcache/node_modules/x"; printf 'y\n' > "$T/comcache/node_modules/x/y"
mkdir -p "$T/comcache/.mypy_cache/3.12"; printf 'm\n' > "$T/comcache/.mypy_cache/3.12/m.json"
# `dist/` numa pasta sem manifesto de build pode ser dado que nao se refaz (CodeAnt no conselhos#350)
wt distsolta; integra distsolta; mkdir -p "$T/distsolta/dados/dist"; printf 'd\n' > "$T/distsolta/dados/dist/base.csv"
wt comrastro; integra comrastro; mkdir -p "$T/comrastro/docs/eventos"; printf 'r\n' > "$T/comrastro/docs/eventos/r.jsonl"
wt comdist; integra comdist; mkdir -p "$T/comdist/dist" "$T/comdist/packages/p/dist" "$T/comdist/coverage"
printf 'b\n' > "$T/comdist/dist/b"; printf 'b\n' > "$T/comdist/packages/p/dist/b"; printf 'c\n' > "$T/comdist/coverage/c"
wt distrastro; integra distrastro; mkdir -p "$T/distrastro/dist" "$T/distrastro/docs/eventos"
printf 'b\n' > "$T/distrastro/dist/b"; printf 'r\n' > "$T/distrastro/docs/eventos/r.jsonl"
# docs/eventos/ so com o `.gitignore` que o hook grava, sem rastro nenhum (login, depois do DM-331).
# O conteudo e o que o hook grava de verdade (.claude/hooks/comum/base.sh), nao so `*`: o teste com
# `*` passava enquanto o docs/eventos/ real bloqueava (CodeAnt no conselhos-municipais#356, DM-336)
HOOK_GI='# Rastro de eventos expx: local da maquina, nao versionado.\n*\n'
grep -qF "printf '$HOOK_GI'" "$RAIZ/.claude/hooks/comum/base.sh"; afirma "o teste usa o mesmo .gitignore que o hook grava" $?
wt rastrovazio; integra rastrovazio; mkdir -p "$T/rastrovazio/docs/eventos"; printf "$HOOK_GI" > "$T/rastrovazio/docs/eventos/.gitignore"
mkdir -p "$T/rastrovazio/outra/eventos"; printf "$HOOK_GI" | sed 's/$/\r/' > "$T/rastrovazio/outra/eventos/.gitignore"
# um CR dentro do padrao nao e fim de linha: o .gitignore deixa de ser o do hook (CodeAnt no
# conselhos-municipais#365)
wt crdentro; integra crdentro; mkdir -p "$T/crdentro/docs/eventos"
printf '# Rastro de eventos expx: local da maquina, nao versionado.\n\r*\n' > "$T/crdentro/docs/eventos/.gitignore"
# so `*`, sem o comentario do hook, foi escrito por alguem: bloqueia (DM-336)
# um nome com quebra de linha nao vira varios caminhos: os pedacos aqui sao `.gitignore` do hook
# que existem (o segundo relativo ao diretorio de onde o script roda), e o `.gitignore` escrito a
# mao dentro da pasta sairia junto (CodeAnt no login#101)
wt nlnome; integra nlnome; mkdir -p "$T/nlnome/docs/eventos/.gitignore
sub" "$T/r/sub"; printf "$HOOK_GI" > "$T/nlnome/docs/eventos/.gitignore"; printf "$HOOK_GI" > "$T/r/sub/.gitignore"
printf 'regras do time\n' > "$T/nlnome/docs/eventos/.gitignore
sub/.gitignore"
wt soestrela; integra soestrela; mkdir -p "$T/soestrela/outra/eventos"; printf '*\n' > "$T/soestrela/outra/eventos/.gitignore"
# .gitignore escrito por alguem (outro conteudo) bloqueia; o find que nao le a pasta tambem (conselhos#354)
wt gitignoreproprio; integra gitignoreproprio; mkdir -p "$T/gitignoreproprio/outra/notas"
printf '*\n# regras do time: manter\n' > "$T/gitignoreproprio/outra/notas/.gitignore"
wt donapush; integra donapush # antes do comsub: o .gitmodules integrado iria para ela
# a worktree que guarda o diretorio de hooks (core.hooksPath dentro dela, DM-338)
g worktree add -q -b b-hookdentro "$T/hookdentro" main; mkdir -p "$T/hookdentro/.githooks"
printf '#!/usr/bin/env bash\nMERGEX_PORTAO_PUSH="$MERGEX_RAIZ"/.claude/skills/mergex/scripts/portao-push.sh\n' > "$T/hookdentro/.githooks/pre-push"
git -C "$T/hookdentro" add .; git -C "$T/hookdentro" -c user.name=t -c user.email=t@t commit -q -m hookdentro; integra hookdentro
# a worktree com um link para o diretorio de hooks de fora (CodeAnt no mergex#107)
mkdir -p "$T/hooks-fora"; printf '#!/usr/bin/env bash\nMERGEX_PORTAO_PUSH="$MERGEX_RAIZ"/.claude/skills/mergex/scripts/portao-push.sh\n' > "$T/hooks-fora/pre-push"
g worktree add -q -b b-hooklink "$T/hooklink" main; ln -s "$T/hooks-fora" "$T/hooklink/.hooks-link"
git -C "$T/hooklink" add .; git -C "$T/hooklink" -c user.name=t -c user.email=t@t commit -q -m hooklink; integra hooklink
# a dona com `\` literal no nome (o validador dela e gravado com `printf '%q'`, login#101)
g worktree add -q -b b-donabarra "$T/dona\\barra" main
printf 'x\n' > "$T/dona\\barra/f-donabarra"; git -C "$T/dona\\barra" add .
git -C "$T/dona\\barra" -c user.name=t -c user.email=t@t commit -q -m donabarra; integra donabarra
wt pastafechada; integra pastafechada; mkdir -p "$T/pastafechada/docs/eventos/sub"; printf "$HOOK_GI" > "$T/pastafechada/docs/eventos/.gitignore"
printf 'r\n' > "$T/pastafechada/docs/eventos/sub/r.jsonl"; chmod 000 "$T/pastafechada/docs/eventos/sub"
wt suja; integra suja; printf 'b\n' >> "$T/suja/a"
wt nova; integra nova; printf 'n\n' > "$T/nova/novo.txt"
wt localonly
wt travada; integra travada; g worktree lock "$T/travada"
g worktree add -q --detach "$T/solta" main
wt "com espaco"; integra "com espaco"
wt avancou; g fetch -q origin; g update-ref refs/remotes/origin/main "$(git -C "$T/avancou" rev-parse HEAD)"
# Por ultimo: integrado, o .gitmodules iria para todas as worktrees criadas depois.
wt comlink; git -C "$T/comlink" update-index --add --cacheinfo "160000,$(git -C "$T/comlink" rev-parse HEAD),modulo"; git -C "$T/comlink" -c user.name=t -c user.email=t@t commit -q -m link; integra comlink; g rm -q --cached modulo; g -c user.name=t commit -q -m "tira o gitlink"; g push -q origin main
wt oculta; integra oculta; printf 'o\n' >> "$T/oculta/a"; git -C "$T/oculta" update-index --assume-unchanged a
wt pulada; integra pulada; printf 'p\n' >> "$T/pulada/a"; git -C "$T/pulada" update-index --skip-worktree a
# Merge com resolucao que nao esta na base: nenhum commit proprio, e o `git cherry` nao o veria.
wt mesclada; integra mesclada; g worktree add -q -b b-mergeada "$T/mergeada" main~1
git -C "$T/mergeada" -c user.name=t -c user.email=t@t merge -q --no-ff --no-edit b-mesclada
wt comsub; printf '[submodule "x"]\n' > "$T/comsub/.gitmodules"; git -C "$T/comsub" add .; git -C "$T/comsub" -c user.name=t -c user.email=t@t commit -q -m sub; integra comsub
# o pre-push instalado (compartilhado por todas as worktrees) que chama o validador de UMA delas
# pelo caminho absoluto: ela nao sai (login, depois do #96). Sem bit de execucao, o Git nao o roda.
# o diretorio de hooks e o do teste (config local vence a global): um core.hooksPath global da
# maquina nunca e gravado nem apagado aqui (CodeAnt no mergex#103)
mkdir -p "$T/hooks-teste"; g config core.hooksPath "$T/hooks-teste"
HK="$(git -C "$T/r" rev-parse --path-format=absolute --git-path hooks/pre-push)"
case "$HK" in "$T"/*) ;; *) echo "FALHA diretorio de hooks fora do teste: $HK" >&2; exit 1 ;; esac
printf '#!/usr/bin/env bash\n# mergex: chamador gerenciado\nMERGEX_PORTAO_PUSH=%s\n' "$T/donapush/.claude/skills/mergex/scripts/portao-push.sh" > "$HK"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida" 2>&1; rc=$?
cp "$T/saida" "$T/saida-com-hook"
# o caminho vem do `printf '%q'` do --instalar: o `\` literal se desfaz certo, e a forma `$'...'`
# (quebra de linha) bloqueia na duvida (CodeAnt no login#101)
printf '#!/usr/bin/env bash\n# mergex: chamador gerenciado\nMERGEX_PORTAO_PUSH=%s\n' "$(printf '%q' "$T/dona\\barra/.claude/skills/mergex/scripts/portao-push.sh")" > "$HK"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-barra" 2>&1
grep -qF "bloqueada	validador_do_pre_push	$T/dona\\barra	" "$T/saida-barra"; afirma "validador com \\ literal no caminho: a worktree dona bloqueia" $?
printf '#!/usr/bin/env bash\n# mergex: chamador gerenciado\nMERGEX_PORTAO_PUSH=%s\n' "$(printf '%q' "$T/dona
nl/portao-push.sh")" > "$HK"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-nl" 2>&1
grep -qF "bloqueada	validador_do_pre_push	$T/dona\\barra	" "$T/saida-nl"; afirma "validador com quebra de linha no caminho: na duvida bloqueia" $?
g worktree remove --force "$T/dona\\barra"
printf '#!/usr/bin/env bash\n# mergex: chamador gerenciado\nMERGEX_PORTAO_PUSH=%s\n' "$T/donapush/.claude/skills/mergex/scripts/portao-push.sh" > "$HK"
printf '#!/usr/bin/env bash\nMERGEX_PORTAO_PUSH="$MERGEX_RAIZ"/.claude/skills/mergex/scripts/portao-push.sh\n' > "$HK"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-relativo" 2>&1; rm -f "$HK"; g config --unset core.hooksPath
grep -qF "removivel	-	$T/donapush	" "$T/saida-relativo"; afirma "chamador relativo a raiz nao prende worktree" $?
# core.hooksPath dentro de uma worktree: o hook mora nela, e remove-la apagaria o pre-push de
# todos os checkouts, mesmo com o chamador relativo a raiz (CodeAnt no conselhos#361, DM-338).
# O hook vem commitado e integrado (a worktree nasce antes do comsub): sem a guarda, seria removivel.
# Relativo, o hooksPath e de cada checkout: o hook da worktree e so dela, e ela sai (CodeAnt no
# conselhos-municipais#365)
g config core.hooksPath .githooks
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-hookrel" 2>&1
grep -qF "removivel	-	$T/hookdentro	" "$T/saida-hookrel"; afirma "hooksPath relativo: o hook da worktree e so dela e nao a prende" $?
# relativo com `..`: todos os checkouts caem na mesma pasta dentro da worktree (CodeAnt no mergex#109)
g config core.hooksPath ../hookdentro/.githooks
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-hookrel" 2>&1
grep -qF "bloqueada	validador_do_pre_push	$T/hookdentro	" "$T/saida-hookrel"; afirma "hooksPath relativo com ..: a pasta comum na worktree a prende" $?
# o pre-push de fora que e link para dentro da worktree: o --git-path do Git resolve o link (CodeAnt no conselhos-municipais#365)
mkdir -p "$T/hooks-ext"; ln -s "$T/hookdentro/.githooks/pre-push" "$T/hooks-ext/pre-push"; g config core.hooksPath "$T/hooks-ext"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-hookext" 2>&1
grep -qF "bloqueada	validador_do_pre_push	$T/hookdentro	" "$T/saida-hookext"; afirma "pre-push de fora que e link para dentro da worktree: ela e dona e bloqueia" $?
rm -f "$T/hooks-ext/pre-push"
g config core.hooksPath "$T/hookdentro/.githooks"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida-hookdentro" 2>&1
grep -qF "bloqueada	validador_do_pre_push	$T/hookdentro	" "$T/saida-hookdentro"; afirma "hooksPath dentro da worktree: ela e dona do pre-push e bloqueia" $?
(cd "$T/r" && bash "$SCRIPT" --remover "$T/hookdentro") > "$T/saida2" 2>&1; rc_hd=$?
[ "$rc_hd" = 1 ] && [ -f "$T/hookdentro/.githooks/pre-push" ]; afirma "--remover nao apaga o pre-push que mora na worktree" $?
g config core.hooksPath "$T/hooklink/.hooks-link"
(cd "$T/r" && bash "$SCRIPT" --remover "$T/hooklink") > "$T/saida2" 2>&1; rc_hd=$?
[ "$rc_hd" = 1 ] && [ -L "$T/hooklink/.hooks-link" ] && grep -qF validador_do_pre_push "$T/saida2"
afirma "hooksPath por link dentro da worktree para fora: ela e dona e o --remover para" $?
g config --unset core.hooksPath; g worktree remove --force "$T/hookdentro"; g worktree remove --force "$T/hooklink"

[ "$rc" = 0 ];                          afirma "listar sai 0" $?
[ "$(estado entregue)" = removivel ];   afirma "entregue e limpa: removivel" $?
[ "$(estado comcache)" = removivel ];   afirma "so dependencia ignorada: removivel" $?
[ "$(estado comrastro)" = bloqueada ] && [ "$(motivo comrastro)" = ignorado ]; afirma "rastro ignorado bloqueia" $?
[ "$(estado comdist)" = removivel ];    afirma "saida de build e cobertura ignoradas: removivel (DM-331)" $?
[ "$(estado distrastro)" = bloqueada ] && [ "$(motivo distrastro)" = ignorado ]; afirma "build junto com rastro: o rastro bloqueia" $?
[ "$(estado distsolta)" = bloqueada ] && [ "$(motivo distsolta)" = ignorado ]; afirma "dist/ sem manifesto de build ao lado bloqueia (DM-333)" $?
[ "$(estado rastrovazio)" = removivel ]; afirma "docs/eventos/ so com o .gitignore do hook: removivel" $?
[ "$(estado crdentro)" = bloqueada ] && [ "$(motivo crdentro)" = ignorado ]; afirma ".gitignore com CR dentro do padrao nao e o do hook: bloqueia" $?
[ "$(estado gitignoreproprio)" = bloqueada ] && [ "$(motivo gitignoreproprio)" = ignorado ]; afirma ".gitignore com outro conteudo que o do hook bloqueia" $?
[ "$(estado nlnome)" = bloqueada ] && [ "$(motivo nlnome)" = ignorado ]; afirma "nome com quebra de linha na pasta ignorada bloqueia" $?
[ "$(estado soestrela)" = bloqueada ] && [ "$(motivo soestrela)" = ignorado ]; afirma ".gitignore so com '*', sem o comentario do hook, bloqueia (DM-336)" $?
[ "$(estado donapush)" = bloqueada ] && [ "$(motivo donapush)" = validador_do_pre_push ]; afirma "worktree dona do validador do pre-push instalado bloqueia" $?
[ "$(estado entregue)" = removivel ]; afirma "com o mesmo pre-push, as outras worktrees continuam removiveis" $?
if [ "$(id -u)" != 0 ] && ! ls "$T/pastafechada/docs/eventos/sub" >/dev/null 2>&1; then
  [ "$(estado pastafechada)" = bloqueada ] && [ "$(motivo pastafechada)" = ignorado ]; afirma "pasta ignorada que o find nao consegue ler bloqueia" $?
else
  echo "  (sem pasta ilegivel neste ambiente: caso pulado)"
fi
[ "$(estado suja)" = bloqueada ] && [ "$(motivo suja)" = alterada ];            afirma "alteracao rastreada bloqueia" $?
[ "$(estado nova)" = bloqueada ] && [ "$(motivo nova)" = alterada ];            afirma "arquivo novo bloqueia" $?
[ "$(estado localonly)" = bloqueada ] && [ "$(motivo localonly)" = nao_entregue ]; afirma "commit fora da base bloqueia" $?
[ "$(estado travada)" = bloqueada ] && [ "$(motivo travada)" = travada ];       afirma "worktree travada bloqueia" $?
[ "$(estado solta)" = bloqueada ] && [ "$(motivo solta)" = sem_branch ];        afirma "sem branch bloqueia" $?
[ "$(linha r)" = ausente ];                                                     afirma "o checkout principal nao entra" $?
[ "$(estado comsub)" = bloqueada ] && [ "$(motivo comsub)" = submodulo ];       afirma "submodulo bloqueia" $?
[ "$(estado comlink)" = bloqueada ] && [ "$(motivo comlink)" = submodulo ];     afirma "gitlink sem .gitmodules bloqueia" $?
[ "$(estado oculta)" = bloqueada ] && [ "$(motivo oculta)" = oculta ];         afirma "assume-unchanged bloqueia" $?
[ "$(estado pulada)" = bloqueada ] && [ "$(motivo pulada)" = oculta ];          afirma "skip-worktree bloqueia" $?
[ "$(estado mergeada)" = bloqueada ] && [ "$(motivo mergeada)" = nao_entregue ]; afirma "commit de merge fora da base bloqueia" $?
[ "$(estado "com espaco")" = removivel ];                                       afirma "caminho com espaco" $?
[ "$(estado avancou)" = bloqueada ] && [ "$(motivo avancou)" = nao_entregue ];  afirma "a base vem do remoto, nao da ref local" $?

# Rede fora: nada e removivel.
g remote set-url origin "$T/nao-existe.git"
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida" 2>&1
[ "$(motivo entregue)" = nao_verificado ];                                      afirma "sem o remoto: nao verificado" $?
g remote set-url origin "$T/origem.git"

# Falha de comando e "nao verificado", nunca removivel.
mkdir -p "$T/shim"; printf '#!/bin/sh\ncase "$*" in *"status --porcelain"*) exit 1;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$T/shim/git"; chmod +x "$T/shim/git"
(cd "$T/r" && PATH="$T/shim:$PATH" bash "$SCRIPT" --listar) > "$T/saida" 2>&1
[ "$(estado entregue)" = bloqueada ] && [ "$(motivo entregue)" = nao_verificado ]; afirma "falha de comando: nao verificado" $?

printf '#!/bin/sh\ncase "$*" in *"worktree list"*) "%s" "$@"; exit 1;; esac\nexec "%s" "$@"\n' "$(command -v git)" "$(command -v git)" > "$T/shim/git"
(cd "$T/r" && PATH="$T/shim:$PATH" bash "$SCRIPT" --remover "$T/entregue") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/entregue" ]; afirma "worktree list que falha no fim nao remove" $?

(cd "$T/r" && bash "$SCRIPT" --remover "$T/suja") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/suja" ]; afirma "--remover recusa a bloqueada" $?
(cd "$T/r" && bash "$SCRIPT" --remover "$T/entregue") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$T/entregue" ]; afirma "--remover remove a entregue" $?
(cd "$T/r" && bash "$SCRIPT" --remover "$T/distrastro") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/distrastro" ] && grep -qx '  ignorado que nao se refaz: docs/eventos/' "$T/saida2" \
  && ! grep -q 'nao se refaz: dist/' "$T/saida2"; afirma "--remover parado lista so o ignorado que nao se refaz" $?
(cd "$T/r" && bash "$SCRIPT" --remover "$T/comdist") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -d "$T/comdist" ]; afirma "--remover remove a worktree com dist/ e coverage/" $?
g rev-parse -q --verify b-entregue >/dev/null; afirma "a branch fica" $?
# O Git for Windows tira a worktree do registro e deixa a pasta com as junctions do node_modules
# dos workspaces, pendentes (login, depois da 0.14.13). O shim refaz essa casca depois do remove
# real: um link pendente e um vivo, para um destino fora que nao pode ser seguido
mkdir -p "$T/fora"; printf 'dado\n' > "$T/fora/importante"
printf '%s\n' '#!/bin/sh' "\"$(command -v git)\" \"\$@\" || exit \$?" \
  'case "$*" in *"worktree remove"*) eval "c=\${$#}"' \
  '  mkdir -p "$c/node_modules/@a" && ln -s "$c/packages/p" "$c/node_modules/@a/pend" && ln -s "$FORA" "$c/node_modules/viva"' \
  '  [ -z "${SOBRA:-}" ] || printf "x\n" > "$c/node_modules/$SOBRA" ;; esac' > "$T/shim/git"
chmod +x "$T/shim/git"
(cd "$T/r" && FORA="$T/fora" PATH="$T/shim:$PATH" bash "$SCRIPT" --remover "$T/rastrovazio") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$T/rastrovazio" ] && [ "$(cat "$T/fora/importante")" = dado ] && grep -qx "removida: $T/rastrovazio" "$T/saida2"
afirma "--remover tira a casca de links pendentes que o Git deixa, sem seguir o link vivo" $?
(cd "$T/r" && FORA="$T/fora" SOBRA=anotacao.txt PATH="$T/shim:$PATH" bash "$SCRIPT" --remover "$T/com espaco") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -f "$T/com espaco/node_modules/anotacao.txt" ] && [ -L "$T/com espaco/node_modules/viva" ] \
  && grep -qF "  $T/com espaco/node_modules/anotacao.txt" "$T/saida2" && ! grep -q '^removida' "$T/saida2"
afirma "--remover com arquivo comum na sobra para e mostra o caminho, sem apagar nada" $?
(cd "$T/comcache" && bash "$SCRIPT" --remover "$T/comcache") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/comcache" ]; afirma "nao remove a worktree em que esta rodando" $?

printf '\n  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
