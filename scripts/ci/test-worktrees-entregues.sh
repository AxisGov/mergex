#!/usr/bin/env bash
# A varredura de worktrees so remove o que esta entregue e sem nada que se perca.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$RAIZ/.claude/skills/mergex/scripts/worktrees-entregues.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
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
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida" 2>&1; rc=$?

[ "$rc" = 0 ];                          afirma "listar sai 0" $?
[ "$(estado entregue)" = removivel ];   afirma "entregue e limpa: removivel" $?
[ "$(estado comcache)" = removivel ];   afirma "so dependencia ignorada: removivel" $?
[ "$(estado comrastro)" = bloqueada ] && [ "$(motivo comrastro)" = ignorado ]; afirma "rastro ignorado bloqueia" $?
[ "$(estado comdist)" = removivel ];    afirma "saida de build e cobertura ignoradas: removivel (DM-331)" $?
[ "$(estado distrastro)" = bloqueada ] && [ "$(motivo distrastro)" = ignorado ]; afirma "build junto com rastro: o rastro bloqueia" $?
[ "$(estado distsolta)" = bloqueada ] && [ "$(motivo distsolta)" = ignorado ]; afirma "dist/ sem manifesto de build ao lado bloqueia (DM-333)" $?
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
(cd "$T/comcache" && bash "$SCRIPT" --remover "$T/comcache") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/comcache" ]; afirma "nao remove a worktree em que esta rodando" $?

printf '\n  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
