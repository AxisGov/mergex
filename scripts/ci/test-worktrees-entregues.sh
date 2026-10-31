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
git init -q -b main "$T/r"; printf 'node_modules/\ndist/\ndocs/eventos/\n' > "$T/r/.gitignore"; printf 'a\n' > "$T/r/a"
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
wt comrastro; integra comrastro; mkdir -p "$T/comrastro/docs/eventos"; printf 'r\n' > "$T/comrastro/docs/eventos/r.jsonl"
wt comdist; integra comdist; mkdir -p "$T/comdist/dist"; printf 'b\n' > "$T/comdist/dist/b"
wt suja; integra suja; printf 'b\n' >> "$T/suja/a"
wt nova; integra nova; printf 'n\n' > "$T/nova/novo.txt"
wt localonly
wt travada; integra travada; g worktree lock "$T/travada"
g worktree add -q --detach "$T/solta" main
wt "com espaco"; integra "com espaco"
wt avancou; g fetch -q origin; g update-ref refs/remotes/origin/main "$(git -C "$T/avancou" rev-parse HEAD)"
# Por ultimo: integrado, o .gitmodules iria para todas as worktrees criadas depois.
wt comlink; git -C "$T/comlink" update-index --add --cacheinfo "160000,$(git -C "$T/comlink" rev-parse HEAD),modulo"; git -C "$T/comlink" -c user.name=t -c user.email=t@t commit -q -m link; integra comlink; g rm -q --cached modulo; g -c user.name=t commit -q -m "tira o gitlink"; g push -q origin main
wt comsub; printf '[submodule "x"]\n' > "$T/comsub/.gitmodules"; git -C "$T/comsub" add .; git -C "$T/comsub" -c user.name=t -c user.email=t@t commit -q -m sub; integra comsub
(cd "$T/r" && bash "$SCRIPT" --listar) > "$T/saida" 2>&1; rc=$?

[ "$rc" = 0 ];                          afirma "listar sai 0" $?
[ "$(estado entregue)" = removivel ];   afirma "entregue e limpa: removivel" $?
[ "$(estado comcache)" = removivel ];   afirma "so dependencia ignorada: removivel" $?
[ "$(estado comrastro)" = bloqueada ] && [ "$(motivo comrastro)" = ignorado ]; afirma "rastro ignorado bloqueia" $?
[ "$(estado comdist)" = bloqueada ] && [ "$(motivo comdist)" = ignorado ];    afirma "dist ignorado bloqueia" $?
[ "$(estado suja)" = bloqueada ] && [ "$(motivo suja)" = alterada ];            afirma "alteracao rastreada bloqueia" $?
[ "$(estado nova)" = bloqueada ] && [ "$(motivo nova)" = alterada ];            afirma "arquivo novo bloqueia" $?
[ "$(estado localonly)" = bloqueada ] && [ "$(motivo localonly)" = nao_entregue ]; afirma "commit fora da base bloqueia" $?
[ "$(estado travada)" = bloqueada ] && [ "$(motivo travada)" = travada ];       afirma "worktree travada bloqueia" $?
[ "$(estado solta)" = bloqueada ] && [ "$(motivo solta)" = sem_branch ];        afirma "sem branch bloqueia" $?
[ "$(linha r)" = ausente ];                                                     afirma "o checkout principal nao entra" $?
[ "$(estado comsub)" = bloqueada ] && [ "$(motivo comsub)" = submodulo ];       afirma "submodulo bloqueia" $?
[ "$(estado comlink)" = bloqueada ] && [ "$(motivo comlink)" = submodulo ];     afirma "gitlink sem .gitmodules bloqueia" $?
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
g rev-parse -q --verify b-entregue >/dev/null; afirma "a branch fica" $?
(cd "$T/comcache" && bash "$SCRIPT" --remover "$T/comcache") > "$T/saida2" 2>&1; rc=$?
[ "$rc" = 1 ] && [ -d "$T/comcache" ]; afirma "nao remove a worktree em que esta rodando" $?

printf '\n  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
