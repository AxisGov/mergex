#!/usr/bin/env bash
# O registro do merge de uma entrega que não é da runx (DM-351): só com o merge
# provado, num commit só com POS-MERGE.md, sem tocar o ENTREGA.md, e o portão
# deixa o PR do registro passar.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$RAIZ/.claude/skills/mergex/scripts/fechamento-pos-merge.sh"
SK="$RAIZ/.claude/skills/mergex/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
ok=0; falhou=0
afirma() { if [ "$2" = "$3" ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s (esperava %s, obteve %s)\n' "$1" "$2" "$3"; fi; }

command -v jq >/dev/null 2>&1 || { echo "sem jq: bancada NAO_EXECUTADA"; exit 1; }

TRAB=onda-4; URL=https://github.com/o/r/pull/379; BR=feature/onda-4; REG="docs/$TRAB-registro-pos-merge"
REL="docs/entregas/$TRAB/POS-MERGE.md"
g() { git -C "$T/r" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git init -q --bare -b main "$T/origem.git"
git init -q -b main "$T/r"
g config "url.$T/origem.git.insteadOf" https://github.com/o/r.git
g remote add origin https://github.com/o/r.git
mkdir -p "$T/r/docs/entregas/$TRAB" "$T/r/src"
printf -- '---\nkind: entrega\ntrabalho_id: %s\nbranch: %s\nbranch_base: main\npr_url: %s\npr_estado: rascunho\nportao: bloqueado\n---\n' "$TRAB" "$BR" "$URL" > "$T/r/docs/entregas/$TRAB/ENTREGA.md"
printf 'a\n' > "$T/r/src/a.js"
mkdir -p "$T/r/.expx"; printf '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"bloqueio"}}}\n' > "$T/r/.expx/hooks.json"
# A base tem história: o merge não é raiz, como em qualquer repositório real.
g commit -q --allow-empty -m anterior
g add .; g commit -q -m base; g push -q origin main; g fetch -q origin
MERGE="$(g rev-parse HEAD)"
g remote set-head origin main >/dev/null 2>&1 || g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

mkdir "$T/bin"
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -z "${GH_FALHA:-}" ] || exit 1
# `gh api repos/<r>/commits/<sha>/pulls`: os PRs pelos quais o commit entrou na base.
# Só a forma que o GitHub aceita: host à parte e `repos/<dono>/<repo>/...` (t-14).
if [ "$1" = api ]; then
  [ -z "${GH_API_FALHA:-}" ] || exit 1
  [ "$2" = --hostname ] && [ "$3" = github.com ] && [[ "$4" =~ ^repos/o/r/commits/[0-9a-f]{40}/pulls$ ]] || exit 1
  printf '%s\n' "${GH_PULLS:-[]}"; exit 0
fi
printf '{"url":"%s","state":"%s","mergeCommit":%s,"headRefName":"%s","baseRefName":"main","isCrossRepository":%s}\n' \
  "${GH_URL:-$3}" "${GH_ESTADO:-MERGED}" "${GH_MERGE:-null}" "${GH_HEAD:-}" "${GH_FORK:-false}"
GH
chmod +x "$T/bin/gh"
IDENT=(GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t)
roda() { ( cd "$T/r" && env PATH="$T/bin:$PATH" "${IDENT[@]}" GH_HEAD="${GH_HEAD:-$BR}" GH_MERGE="${GH_MERGE:-{\"oid\":\"$MERGE\"\}}" "$@" bash "$SCRIPT" --trabalho "${CASO_TRAB:-$TRAB}" ${CASO_PR:+--pr "$CASO_PR"} >"$T/saida" 2>"$T/erro" ); printf '%s' "$?"; }
W="$T/r--$TRAB-registro-pos-merge"
nada_criado() { g show-ref --verify -q "refs/heads/$REG" && return 1; [ ! -e "$W" ] || return 1; [ -z "$(g config --get "branch.$REG.expxRegistroPosMerge")" ]; }
sem_efeito() { nada_criado; afirma "$1: não cria nada" 0 "$?"; }
limpa() { g worktree remove --force "$W" 2>/dev/null; g branch -q -D "$REG" 2>/dev/null; g config --unset "branch.$REG.expxRegistroPosMerge" 2>/dev/null; true; }

echo "id: só o que a validade aceita"
for id in ../x .x entregas 'a b'; do afirma "id '$id': rc 64" 64 "$(CASO_TRAB="$id" roda X=1)"; done
afirma "id com prefixo de ocorrência fora da forma: rc 64" 64 "$(CASO_TRAB=OC-2026-7-rua roda X=1)"
afirma "trabalho sem entrega: rc 3" 3 "$(CASO_TRAB=outra roda X=1)"
mkdir -p "$T/fora/x"; cp "$T/r/docs/entregas/$TRAB/ENTREGA.md" "$T/fora/x/"; ln -s "$T/fora/x" "$T/r/docs/entregas/link"
afirma "pasta da entrega como link: rc 3" 3 "$(CASO_TRAB=link roda X=1)"; rm "$T/r/docs/entregas/link"

echo "sem o merge provado, nada acontece"
afirma "PR aberto: rc 4" 4 "$(roda GH_ESTADO=OPEN)"; sem_efeito "PR aberto"
afirma "serviço falha: rc 5" 5 "$(roda GH_FALHA=1)"; sem_efeito "serviço falha"
afirma "PR de outra branch: rc 6" 6 "$(GH_HEAD=feature/outra roda X=1)"; sem_efeito "outra branch"
afirma "PR de fork com a mesma branch: rc 6" 6 "$(roda GH_FORK=true)"; sem_efeito "fork"
afirma "serviço que não diz se é fork: rc 6" 6 "$(roda GH_FORK=null)"; sem_efeito "fork não dito"
cp "$T/r/docs/entregas/$TRAB/ENTREGA.md" "$T/bak"
sed -i.tmp 's#^pr_url: .*#pr_url: https://github.com/o/r"x/pull/379#' "$T/r/docs/entregas/$TRAB/ENTREGA.md"
afirma "pr_url fora do alfabeto do registro: rc 3" 3 "$(roda X=1)"; sem_efeito "pr_url com aspa"
cp "$T/bak" "$T/r/docs/entregas/$TRAB/ENTREGA.md"; rm -f "$T/r/docs/entregas/$TRAB/ENTREGA.md.tmp"
mkdir -p "$T/r/docs/entregas/solta"; sed "s#^branch: .*#branch: feature/solta#" "$T/bak" > "$T/r/docs/entregas/solta/ENTREGA.md"
afirma "entrega que a base não traz: rc 7" 7 "$(CASO_TRAB=solta GH_HEAD=feature/solta roda X=1)"
g show-ref --verify -q refs/heads/docs/solta-registro-pos-merge || [ -e "$T/r--solta-registro-pos-merge" ] \
  || [ -n "$(g config --get branch.docs/solta-registro-pos-merge.expxRegistroPosMerge)" ]
afirma "entrega que a base não traz: não cria nada" 1 "$?"
rm -rf "$T/r/docs/entregas/solta"
sed 's#^pr_estado: .*#entrega: por_sprint#' "$T/bak" > "$T/r/docs/entregas/$TRAB/ENTREGA.md"
afirma "entrega por_sprint: rc 3" 3 "$(roda X=1)"; sem_efeito "por_sprint"
cp "$T/bak" "$T/r/docs/entregas/$TRAB/ENTREGA.md"
sed 's#^pr_url: .*#pr_url: https://github.com/o/r/pull/380#' "$T/bak" > "$T/r/docs/entregas/$TRAB/ENTREGA.md"
afirma "ENTREGA.md local apontando outro PR mesclado: rc 6" 6 "$(roda GH_URL=https://github.com/o/r/pull/380)"; sem_efeito "ENTREGA.md local editado"
cp "$T/bak" "$T/r/docs/entregas/$TRAB/ENTREGA.md"

echo "sem identidade no Git, o commit falha sem deixar o registro pela metade"
rc=0; ( cd "$T/r" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
  HOME="$T" GIT_CONFIG_GLOBAL="$T/vazio" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
  PATH="$T/bin:$PATH" GH_HEAD="$BR" GH_MERGE="{\"oid\":\"$MERGE\"}" bash "$SCRIPT" --trabalho "$TRAB" >/dev/null 2>"$T/erro" ) || rc=$?
afirma "sem identidade: rc 8" 8 "$rc"
afirma "sem identidade: o worktree fica limpo" "" "$(git -C "$W" status --porcelain 2>/dev/null)"

echo "com o merge provado"
afirma "retoma a branch sem registro: rc 0" 0 "$(roda X=1)"
afirma "a saída traz o worktree" "worktree=$W" "$(sed -n 1p "$T/saida")"
afirma "a saída traz a branch" "branch=$REG" "$(sed -n 2p "$T/saida")"
COMMIT="$(git -C "$W" rev-parse HEAD)"
afirma "a saída traz o commit" "commit=$COMMIT" "$(sed -n 5p "$T/saida")"
afirma "a marca é o merge" "$MERGE" "$(g config --get "branch.$REG.expxRegistroPosMerge")"
afirma "a marca do fechamento da runx não é usada" "" "$(g config --get "branch.$REG.expxFechamento")"
afirma "o commit tem um pai, o merge" "$MERGE" "$(git -C "$W" rev-parse "$COMMIT^")"
afirma "o commit toca só o POS-MERGE.md" "A	$REL" "$(git -C "$W" diff-tree --no-commit-id -r --name-status "$COMMIT")"
afirma "trailer Merge" "$MERGE" "$(git -C "$W" log -1 --format='%(trailers:key=Merge,valueonly)' | sed '/^$/d')"
afirma "trailer Registro-pos-merge-de" "$URL" "$(git -C "$W" log -1 --format='%(trailers:key=Registro-pos-merge-de,valueonly)' | sed '/^$/d')"
afirma "sem trailer Trabalho (não seleciona a entrega no portão)" "" "$(git -C "$W" log -1 --format='%(trailers:key=Trabalho,valueonly)' | sed '/^$/d')"
fm() { sed -n "s/^$1: //p" "$W/$REL" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
afirma "trabalho_id entre aspas no YAML" "trabalho_id: \"$TRAB\"" "$(grep -m1 '^trabalho_id:' "$W/$REL")"
afirma "pr_url_de: entrega" entrega "$(fm pr_url_de)"
afirma "kind" registro_pos_merge "$(fm kind)"
afirma "pr_estado" merged "$(fm pr_estado)"
afirma "merge" "$MERGE" "$(fm merge)"
afirma "pr_url" "$URL" "$(fm pr_url)"
afirma "trabalho_id" "$TRAB" "$(fm trabalho_id)"
afirma "ENTREGA.md intacto" "" "$(git -C "$W" diff "$MERGE" -- "docs/entregas/$TRAB/ENTREGA.md")"
afirma "worktree limpo" "" "$(git -C "$W" status --porcelain)"
afirma "rodar de novo retoma: rc 0" 0 "$(roda X=1)"
afirma "a retomada não cria outro commit" "$COMMIT" "$(git -C "$W" rev-parse HEAD)"
g config "branch.$REG.expxRegistroPosMerge" 0000000000000000000000000000000000000000
afirma "marca de outro merge não retoma: rc 8" 8 "$(roda X=1)"
g config "branch.$REG.expxRegistroPosMerge" "$MERGE"

echo "portão: o PR do registro não reabre a entrega"
( cd "$W" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$REG" "$COMMIT" "$REG" 0000000000000000000000000000000000000000 \
  | bash "$SK/portao-push.sh" --pre-push origin https://github.com/o/r.git >"$T/push" 2>&1 )
afirma "pre-push deixa passar" 0 "$?"
( cd "$W" && bash "$SK/portao-ci.sh" --verificar --base "$MERGE" --sha "$COMMIT" --branch "$REG" >"$T/ci" 2>&1 )
afirma "CI deixa passar" 0 "$?"
afirma "o CI não seleciona entrega" "motivo=ref_nao_aplicavel" "$(grep -m1 '^motivo=' "$T/ci")"

# Controle: editar o ENTREGA.md na mesma branch seleciona a entrega bloqueada, e o portão barra.
printf 'pr_estado: merged\n' >> "$W/docs/entregas/$TRAB/ENTREGA.md"
git -C "$W" -c user.name=t -c user.email=t@t commit -q -am 'docs: edita a entrega'; EDITA="$(git -C "$W" rev-parse HEAD)"
rc=0; ( cd "$W" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$REG" "$EDITA" "$REG" 0000000000000000000000000000000000000000 \
  | bash "$SK/portao-push.sh" --pre-push origin https://github.com/o/r.git >"$T/push2" 2>&1 ) || rc=$?
afirma "controle: editar o ENTREGA.md é barrado no pre-push" 1 "$([ "$rc" = 0 ] && echo 0 || echo 1)"
afirma "branch que andou depois do registro: rc 8" 8 "$(roda X=1)"
git -C "$W" reset -q --hard "$COMMIT"

echo "registro que andou de outro jeito"
git -C "$W" -c user.name=t -c user.email=t@t commit -q --amend -m 'docs: outro'
afirma "commit do registro sem o trailer deste merge: rc 8" 8 "$(roda X=1)"
limpa
mkdir -p "$T/r/src"; g worktree add -q -b "$REG" "$W" "$MERGE"; g config "branch.$REG.expxRegistroPosMerge" "$MERGE"
printf 'x\n' > "$W/src/b.js"; git -C "$W" add src/b.js; git -C "$W" -c user.name=t -c user.email=t@t commit -q -m outro
afirma "branch que andou sem o registro: rc 8" 8 "$(roda X=1)"
limpa
g worktree add -q -b "$REG" "$W" "$MERGE"; g config "branch.$REG.expxRegistroPosMerge" "$MERGE"; printf 'x\n' > "$W/sujo"
afirma "worktree com alteração: rc 8" 8 "$(roda X=1)"
limpa
# O registro já mesclado na base: nada a fazer, e nada se cria.
mkdir -p "$T/r/docs/entregas/$TRAB"; printf 'x\n' > "$T/r/$REL"; g add "$REL"; g commit -q -m registro; g push -q origin main
afirma "base que já traz o registro: rc 8" 8 "$(roda X=1)"; sem_efeito "registro na base"
g reset -q --hard "$MERGE"; g push -q -f origin main 2>/dev/null; g fetch -q origin

echo "a ocorrência da runx segue sem registro"
mkdir -p "$T/r/docs/entregas/OC-2026-0001-a"; sed "s#^branch: .*#branch: fix/OC-2026-0001-a#" "$T/bak" > "$T/r/docs/entregas/OC-2026-0001-a/ENTREGA.md"
afirma "OC: rc 0, sem commit=" "" "$(CASO_TRAB=OC-2026-0001-a GH_HEAD=fix/OC-2026-0001-a roda X=1 >/dev/null; grep '^commit=' "$T/saida")"

echo "--pr: o PR que o E7 não gravou (aberto fora do fluxo)"
P2=https://github.com/o/r/pull/381; ID=1e5
mkdir -p "$T/r/docs/entregas/$ID"
# A história da branch reaproveitada: o planejamento traz uma versão do ENTREGA.md, o
# PR de código traz a final, e um commit depois não o toca.
sed -e "s#^pr_url: .*#pr_url: null#" -e "s#^branch: .*#branch: feature/n#" -e "s#^portao: .*#portao: null#" "$T/bak" > "$T/r/docs/entregas/$ID/ENTREGA.md"
g add "docs/entregas/$ID"; g commit -q -m 'planejamento'; C_PLAN="$(g rev-parse HEAD)"
sed -i 's#^portao: .*#portao: pronto#' "$T/r/docs/entregas/$ID/ENTREGA.md"
g commit -q -am 'entrega sem pr'; C_ENT="$(g rev-parse HEAD)"
printf 'z\n' > "$T/r/src/z.js"; g add src/z.js; g commit -q -m depois; C_DEP="$(g rev-parse HEAD)"
g push -q origin main; g fetch -q origin
oid() { printf '{"oid":"%s"}' "$1"; }
nada_id() { g show-ref --verify -q "refs/heads/docs/$ID-registro-pos-merge" && return 1; [ ! -e "$T/r--$ID-registro-pos-merge" ]; }
afirma "sem pr_url e sem --pr: rc 3" 3 "$(CASO_TRAB=$ID GH_HEAD=feature/n GH_MERGE="$(oid "$C_ENT")" roda X=1)"
grep -qF -- '--pr' "$T/erro"; afirma "a mensagem indica o --pr" 0 "$?"
afirma "--pr de PR de outra branch: rc 6" 6 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/outra GH_MERGE="$(oid "$C_ENT")" roda X=1)"
afirma "--pr com merge anterior à entrega: rc 6" 6 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/n roda X=1)"
afirma "--pr do planejamento (versão antiga do ENTREGA.md): rc 6" 6 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/n GH_MERGE="$(oid "$C_PLAN")" roda X=1)"
afirma "--pr com merge que não traz o ENTREGA.md: rc 6" 6 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/n GH_MERGE="$(oid "$C_DEP")" roda X=1)"
nada_id; afirma "--pr recusado: não cria nada" 0 "$?"
afirma "--pr na ocorrência da runx: rc 64" 64 "$(CASO_TRAB=OC-2026-0001-a CASO_PR=$P2 GH_HEAD=fix/OC-2026-0001-a roda X=1)"
afirma "--pr diferente do pr_url gravado: rc 6" 6 "$(CASO_PR=$P2 roda X=1)"
afirma "--pr igual ao pr_url gravado: rc 0" 0 "$(CASO_PR=$URL roda X=1)"
afirma "--pr do merge que trouxe a entrega: rc 0" 0 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/n GH_MERGE="$(oid "$C_ENT")" roda X=1)"
W2="$T/r--$ID-registro-pos-merge"; R2="$W2/docs/entregas/$ID/POS-MERGE.md"
afirma "pr_url_de: argumento" "pr_url_de: argumento" "$(grep -m1 '^pr_url_de:' "$R2")"
afirma "pr_url é o do argumento" "pr_url: \"$P2\"" "$(grep -m1 '^pr_url:' "$R2")"
afirma "id que o YAML leria como número vai entre aspas" "trabalho_id: \"1e5\"" "$(grep -m1 '^trabalho_id:' "$R2")"
afirma "trailer com o PR do argumento" "$P2" "$(git -C "$W2" log -1 --format='%(trailers:key=Registro-pos-merge-de,valueonly)' | sed '/^$/d')"
afirma "ENTREGA.md sem pr_url continua intacto" "" "$(git -C "$W2" diff HEAD^ -- "docs/entregas/$ID/ENTREGA.md")"
afirma "--pr: rodar de novo retoma: rc 0" 0 "$(CASO_TRAB=$ID CASO_PR=$P2 GH_HEAD=feature/n GH_MERGE="$(oid "$C_ENT")" roda X=1)"
afirma "--pr: retomar sem o --pr não registra outro PR: rc 3" 3 "$(CASO_TRAB=$ID GH_HEAD=feature/n GH_MERGE="$(oid "$C_ENT")" roda X=1)"


echo "--pr: planejamento ainda corrente não fecha a entrega"
ID2=plano-x
mkdir -p "$T/r/docs/entregas/$ID2"
sed -e "s#^pr_url: .*#pr_url: null\nsprint_atual: planejamento#" -e "s#^branch: .*#branch: feature/p#" "$T/bak" > "$T/r/docs/entregas/$ID2/ENTREGA.md"
g add "docs/entregas/$ID2"; g commit -q -m 'planejamento por fora'; C_P2="$(g rev-parse HEAD)"; g push -q origin main; g fetch -q origin
afirma "--pr do planejamento corrente: rc 3" 3 "$(CASO_TRAB=$ID2 CASO_PR=https://github.com/o/r/pull/390 GH_HEAD=feature/p GH_MERGE="$(oid "$C_P2")" roda X=1)"
g show-ref --verify -q "refs/heads/docs/$ID2-registro-pos-merge"; afirma "planejamento corrente: não cria nada" 1 "$?"

echo "--pr: rebase merge em que o último commit não toca o ENTREGA.md"
# O rebase reaplica os commits do PR na linha principal; o serviço diz por qual PR
# cada commit entrou na base (commits/<sha>/pulls).
ID3=rb-x; P3=https://github.com/o/r/pull/391
mkdir -p "$T/r/docs/entregas/$ID3"
sed -e "s#^pr_url: .*#pr_url: null#" -e "s#^branch: .*#branch: feature/rb#" "$T/bak" > "$T/r/docs/entregas/$ID3/ENTREGA.md"
g add "docs/entregas/$ID3"; g commit -q -m 'rb: entrega'; C_RB1="$(g rev-parse HEAD)"
printf 'rb\n' > "$T/r/src/rb.js"; g add src/rb.js; g commit -q -m 'rb: ajuste'; C_RB2="$(g rev-parse HEAD)"
g push -q origin main; g fetch -q origin
rb() { CASO_TRAB=$ID3 CASO_PR="${2:-$P3}" GH_HEAD=feature/rb GH_MERGE="$(oid "$C_RB2")" roda GH_PULLS="$1" ${3:+"$3"}; }
afirma "rebase: o serviço não liga o commit a PR nenhum: rc 6" 6 "$(rb '[]')"
afirma "rebase: o commit entrou por outro PR: rc 6" 6 "$(rb '[{"number":390}]')"
# A branch reaproveitada: o PR 393, mesclado por squash depois do 391 (rebase), leva
# os commits originais do 391 e casa em branch, base, blob, título e data. Só o
# serviço diz que o commit que trouxe a entrega entrou pelo 391.
afirma "rebase: PR seguinte da mesma branch não registra a entrega: rc 6" 6 "$(rb '[{"number":391}]' https://github.com/o/r/pull/393)"
afirma "rebase: o serviço não responde sobre o commit: rc 5" 5 "$(rb '[{"number":391}]' "" GH_API_FALHA=1)"
g show-ref --verify -q "refs/heads/docs/$ID3-registro-pos-merge"; afirma "rebase recusado: não cria nada" 1 "$?"
afirma "rebase: o commit entrou por este PR: rc 0" 0 "$(rb '[{"number":391}]')"
afirma "rebase: o registro aponta o merge do serviço" "$C_RB2" "$(g config --get "branch.docs/$ID3-registro-pos-merge.expxRegistroPosMerge")"

echo "--pr: merge commit, com a base andando ao lado"
ID4=mc-x; P4=https://github.com/o/r/pull/392
g checkout -q -b lado-mc
mkdir -p "$T/r/docs/entregas/$ID4"
sed -e "s#^pr_url: .*#pr_url: null#" -e "s#^branch: .*#branch: feature/mc#" "$T/bak" > "$T/r/docs/entregas/$ID4/ENTREGA.md"
g add "docs/entregas/$ID4"; g commit -q -m 'mc: entrega'; C_MC1="$(g rev-parse HEAD)"
g checkout -q main; printf 'mc\n' > "$T/r/src/mc.js"; g add src/mc.js; g commit -q -m 'mc: base anda'
g merge -q --no-ff -m 'Merge lado-mc' lado-mc; C_MC="$(g rev-parse HEAD)"; g push -q origin main; g fetch -q origin
afirma "merge commit que trouxe o ENTREGA.md: rc 0" 0 "$(CASO_TRAB=$ID4 CASO_PR=$P4 GH_HEAD=feature/mc GH_MERGE="$(oid "$C_MC")" roda X=1)"
printf '\n%s ok, %s falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
