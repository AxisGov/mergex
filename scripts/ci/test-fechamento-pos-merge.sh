#!/usr/bin/env bash
# O fechamento da runx depois do merge só abre com o merge da entrega provado, e o
# hook só isenta os quatro documentos na branch aberta pelo script (DM-306).
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$RAIZ/.claude/skills/mergex/scripts/fechamento-pos-merge.sh"
HOOK="$RAIZ/.claude/hooks/mergex/arquivo-fora-do-plano.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
ok=0; falhou=0
afirma() { if [ "$2" = "$3" ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s (esperava %s, obteve %s)\n' "$1" "$2" "$3"; fi; }

command -v jq >/dev/null 2>&1 || { echo "sem jq: bancada NAO_EXECUTADA"; exit 1; }

OC=OC-2026-0007; TRAB="$OC-rua"; URL=https://github.com/o/r/pull/9; BR="fix/$TRAB"; FEC="docs/$OC-fechamento"
g() { git -C "$T/r" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git init -q --bare -b main "$T/origem.git"
git init -q -b main "$T/r"
for u in https://github.com/o/r.git ssh://git@github.com:443/o/r.git git@github.com:o/r.git; do g config --add "url.$T/origem.git.insteadOf" "$u"; done
g remote add origin https://github.com/o/r.git
mkdir -p "$T/r/docs/entregas/$TRAB" "$T/r/docs/entregas/OC-2026-0008-rua" "$T/r/docs/manutencao/$TRAB" "$T/r/docs/manutencao/OC-2026-0008-rua" \
  "$T/r/docs/relatorios" "$T/r/docs/sprintx/features/x" "$T/r/src" "$T/r/.expx"
printf -- '---\nkind: entrega\ntrabalho_id: %s\nbranch: %s\nbranch_base: main\npr_url: %s\npr_estado: aberto\n---\n' "$OC" "$BR" "$URL" > "$T/r/docs/entregas/$TRAB/ENTREGA.md"
printf -- '---\nkind: entrega\nbranch: fix/sem\nbranch_base: main\npr_url: null\n---\n' > "$T/r/docs/entregas/OC-2026-0008-rua/ENTREGA.md"
printf 'orq\n' > "$T/r/docs/manutencao/$TRAB/ORQUESTRADOR.md"
printf 'orq\n' > "$T/r/docs/manutencao/OC-2026-0008-rua/ORQUESTRADOR.md"
printf 'idx\n' > "$T/r/docs/relatorios/INDICE.md"
printf 'a\n' > "$T/r/src/a.js"
printf 'arquivos:\n  cria: [src/planejado.js]\n' > "$T/r/docs/sprintx/features/x/tasks.md"
printf '{"expx_hooks":1,"hooks":{"arquivo-fora-do-plano":{"modo":"bloqueio"}}}\n' > "$T/r/.expx/hooks.json"
g add .; g commit -q -m base; g push -q origin main; g fetch -q origin
MERGE="$(g rev-parse HEAD)"
g commit -q --allow-empty -m 'fora da base' ; FORA_BASE="$(g rev-parse HEAD)"; g reset -q --hard "$MERGE"

# `gh` falso: devolve o que o caso pede, e registra que foi chamado.
mkdir "$T/bin"
cat > "$T/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -z "${GH_FALHA:-}" ] || exit 1
printf '{"url":"%s","state":"%s","mergeCommit":%s,"headRefName":"%s","baseRefName":"%s"}\n' \
  "${GH_URL:-$3}" "${GH_ESTADO:-MERGED}" "${GH_MERGE:-null}" "${GH_HEAD:-}" "${GH_BASE:-main}"
GH
chmod +x "$T/bin/gh"
roda() { ( cd "$T/r" && env PATH="$T/bin:$PATH" GH_HEAD="${GH_HEAD:-$BR}" GH_MERGE="${GH_MERGE:-{\"oid\":\"$MERGE\"\}}" "$@" bash "$SCRIPT" --trabalho "${CASO_TRAB:-$TRAB}" >"$T/saida" 2>"$T/erro" ); printf '%s' "$?"; }
nada_criado() { g show-ref --verify -q "refs/heads/$FEC" && return 1; [ ! -e "$T/r--$OC-fechamento" ] || return 1; [ -z "$(g config --get "branch.$FEC.expxFechamento")" ]; }
sem_efeito() { nada_criado; afirma "$1: não cria nada" 0 "$?"; }

echo "script: sem o merge provado, nada acontece"
afirma "PR aberto: rc 4" 4 "$(roda GH_ESTADO=OPEN)"; sem_efeito "PR aberto"
afirma "PR fechado sem merge: rc 4" 4 "$(roda GH_ESTADO=CLOSED)"; sem_efeito "PR fechado"
afirma "serviço falha: rc 5" 5 "$(roda GH_FALHA=1)"; sem_efeito "serviço falha"
afirma "sem merge informado: rc 5" 5 "$(GH_MERGE=null roda X=1)"; sem_efeito "sem merge informado"
afirma "outra branch no PR: rc 6" 6 "$(roda GH_HEAD=fix/outra)"; sem_efeito "outra branch"
afirma "outra base no PR: rc 6" 6 "$(roda GH_BASE=develop)"; sem_efeito "outra base"
afirma "outra url na resposta: rc 6" 6 "$(roda GH_URL=https://github.com/o/r/pull/10)"; sem_efeito "outra url"
afirma "merge fora da base: rc 7" 7 "$(GH_MERGE="{\"oid\":\"$FORA_BASE\"}" roda X=1)"; sem_efeito "merge fora da base"
afirma "entrega sem pr_url: rc 3" 3 "$(CASO_TRAB=OC-2026-0008-rua roda X=1)"
afirma "entrega ausente: rc 3" 3 "$(CASO_TRAB=OC-2026-0009-nao roda X=1)"
afirma "id que não é de ocorrência: rc 64" 64 "$(CASO_TRAB=feature-x roda X=1)"
afirma "id de ocorrência sem os quatro dígitos: rc 64" 64 "$(CASO_TRAB=OC-2026-7-rua roda X=1)"
SEM_GH="$T/semgh"; mkdir "$SEM_GH"; for c in bash git jq sed awk tr cat dirname mktemp; do ln -s "$(command -v "$c")" "$SEM_GH/$c"; done
rc=0; ( cd "$T/r" && PATH="$SEM_GH" bash "$SCRIPT" --trabalho "$TRAB" >/dev/null 2>&1 ) || rc=$?
afirma "sem a ferramenta gh: rc 5" 5 "$rc"; sem_efeito "sem gh"
cp "$T/r/docs/entregas/$TRAB/ENTREGA.md" "$T/entrega.bak"
sed -i.tmp 's#^pr_url: .*#pr_url: https://github.com/outro/repo/pull/9#' "$T/r/docs/entregas/$TRAB/ENTREGA.md"
afirma "pr_url de outro repositório: rc 6" 6 "$(roda GH_URL=https://github.com/outro/repo/pull/9)"; sem_efeito "outro repositório"
cp "$T/entrega.bak" "$T/r/docs/entregas/$TRAB/ENTREGA.md"; rm -f "$T/r/docs/entregas/$TRAB/ENTREGA.md.tmp"

g remote set-url origin ssh://git@github.com:443/o/r.git
afirma "remoto ssh com porta é o mesmo repositório" 4 "$(roda GH_ESTADO=OPEN)"
g remote set-url origin git@github.com:o/r.git
afirma "remoto scp é o mesmo repositório" 4 "$(roda GH_ESTADO=OPEN)"
g remote set-url origin https://github.com/o/r.git

echo "script: com o merge provado"
g worktree add -q -b tomada "$T/r--$OC-fechamento" HEAD
afirma "pasta de destino já existe: rc 8" 8 "$(roda X=1)"
g worktree remove "$T/r--$OC-fechamento"; g branch -q -D tomada
g branch -q "$FEC"
afirma "branch já existe sem a marca: rc 8" 8 "$(roda X=1)"
g branch -q -D "$FEC"
# Clone de uma branch só: o fetch sem refspec não atualizaria o ramo remoto da base.
g config remote.origin.fetch +refs/heads/nada:refs/remotes/origin/nada
g update-ref -d refs/remotes/origin/main
afirma "PR mesclado, em clone de uma branch só: rc 0" 0 "$(roda X=1)"
g config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
W="$T/r--$OC-fechamento"
afirma "a saída traz o caminho absoluto" "worktree=$W" "$(sed -n 1p "$T/saida")"
afirma "a saída traz o merge" "merge=$MERGE" "$(sed -n 3p "$T/saida")"
afirma "a marca é o merge" "$MERGE" "$(g config --get "branch.$FEC.expxFechamento")"
afirma "a branch nasce da base" "$MERGE" "$(git -C "$W" rev-parse HEAD)"
git -C "$W" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; afirma "a branch nasce sem rastrear" 128 "$?"
afirma "ENTREGA.md intacto" "" "$(git -C "$W" status --short)"
afirma "rodar de novo retoma: rc 0" 0 "$(roda X=1)"
afirma "a retomada aponta o mesmo worktree" "worktree=$W" "$(sed -n 1p "$T/saida")"
g config "branch.$FEC.expxFechamento" 0000000000000000000000000000000000000000
afirma "marca de outro merge não retoma: rc 8" 8 "$(roda X=1)"
g config "branch.$FEC.expxFechamento" "$MERGE"

SOLTA="$(git -C "$W" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit-tree -m solta "$(git -C "$W" rev-parse HEAD^{tree})")"
git -C "$W" update-ref "refs/heads/$FEC" "$SOLTA"
afirma "branch que perdeu o merge não retoma: rc 8" 8 "$(roda X=1)"
git -C "$W" update-ref "refs/heads/$FEC" "$MERGE"; git -C "$W" reset -q --hard "$MERGE"
git clone -q --depth 1 "file://$T/origem.git" "$T/raso" 2>/dev/null
git -C "$T/raso" remote set-url origin https://github.com/o/r.git; git -C "$T/raso" config "url.$T/origem.git.insteadOf" https://github.com/o/r.git
rc=0; ( cd "$T/raso" && env PATH="$T/bin:$PATH" GH_HEAD="$BR" GH_MERGE="{\"oid\":\"$MERGE\"}" bash "$SCRIPT" --trabalho "$TRAB" >/dev/null 2>"$T/erro" ) || rc=$?
afirma "clone raso: rc 5, com o motivo" "5 1" "$rc $(grep -c 'clone raso' "$T/erro")"

echo "hook: os quatro documentos só com a marca e os trailers"
w() { git -C "$W" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
limpa() { w reset -q --hard "$MERGE"; w clean -fdq; }
RDIR="docs/relatorios/2026-11-01-$TRAB"
prepara() { mkdir -p "$W/$RDIR"; printf 'novo\n' >> "$W/docs/manutencao/$TRAB/ORQUESTRADOR.md"; printf 't\n' > "$W/$RDIR/tecnico.md"; printf 'u\n' > "$W/$RDIR/uso.md"; printf 'novo\n' >> "$W/docs/relatorios/INDICE.md"; w add -A -- docs/manutencao docs/relatorios; }
MSG="$T/msg"
msg() { printf 'docs: fecha a ocorrencia\n\nFechamento-de: %s\nMerge: %s\n' "$URL" "${1:-$MERGE}" > "$MSG"; }
julga() { jq -cn --arg c "git commit -F $MSG" --arg w "$W" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}' | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?"; }

msg; prepara
afirma "com marca e trailers: os quatro passam" 0 "$(julga)"
g config --unset "branch.$FEC.expxFechamento"
afirma "sem a marca do script: barra" 2 "$(julga)"
g config "branch.$FEC.expxFechamento" "$FORA_BASE"; msg "$FORA_BASE"
afirma "marca fora do HEAD: barra" 2 "$(julga)"
g config "branch.$FEC.expxFechamento" "$MERGE"; msg "$FORA_BASE"
afirma "trailer com outro merge: barra" 2 "$(julga)"
printf 'docs: fecha\n' > "$MSG"
afirma "sem trailers: barra" 2 "$(julga)"
printf 'docs: fecha\n\nFechamento-de: https://github.com/o/r/pull/10\nMerge: %s\n' "$MERGE" > "$MSG"
afirma "trailer com outro PR: barra" 2 "$(julga)"
msg; printf 'x\n' > "$W/src/novo.js"; w add src/novo.js
afirma "um quinto arquivo de produto: barra" 2 "$(julga)"
limpa; prepara; printf 'x\n' > "$W/src/planejado.js"; w add src/planejado.js
afirma "um quinto arquivo, mesmo declarado numa task: barra" 2 "$(julga)"
limpa; prepara; printf 'x\n' >> "$W/docs/entregas/$TRAB/ENTREGA.md"; w add "docs/entregas/$TRAB/ENTREGA.md"
afirma "tocar a ENTREGA: barra" 2 "$(julga)"
limpa; mkdir -p "$W/$RDIR"; cp "$W/src/a.js" "$W/$RDIR/tecnico.md"; w add "$RDIR/tecnico.md"
afirma "cópia de produto para relatório: barra" 2 "$(julga)"
limpa; mkdir -p "$W/$RDIR"; cp "$W/docs/relatorios/INDICE.md" "$W/$RDIR/uso.md"; w add "$RDIR/uso.md"
afirma "documento parecido com outro documento: passa" 0 "$(julga)"
limpa; prepara; git -C "$W" mv "docs/entregas/$TRAB" "docs/entregas/$OC""0-rua"; git -C "$W" reset -q -- docs/entregas
afirma "entrega de outro id com o mesmo prefixo: barra" 2 "$(julga)"
rm -rf "$W/docs/entregas/$OC""0-rua"; git -C "$W" checkout -q -- "docs/entregas/$TRAB"
limpa; prepara; printf 'x\n' >> "$W/docs/manutencao/OC-2026-0008-rua/ORQUESTRADOR.md"; w add -A docs/manutencao
afirma "documento de outra ocorrência: barra" 2 "$(julga)"
limpa; mkdir -p "$W/$RDIR"; printf 't\n' > "$W/$RDIR/tecnico.md"; chmod +x "$W/$RDIR/tecnico.md"; w add "$RDIR/tecnico.md"
afirma "executável com nome de relatório: barra" 2 "$(julga)"
limpa; mkdir -p "$W/$RDIR"; ln -s ../../../src/a.js "$W/$RDIR/uso.md"; w add "$RDIR/uso.md"
afirma "link com nome de relatório: barra" 2 "$(julga)"
limpa; mkdir -p "$W/$RDIR"; w mv src/a.js "$RDIR/tecnico.md"
afirma "renomeação de produto para relatório: barra" 2 "$(julga)"
limpa; w rm -q docs/relatorios/INDICE.md
afirma "remoção do índice: barra" 2 "$(julga)"
limpa; prepara; mkdir -p "$W/docs/relatorios/2026-11-01-$TRAB/sub"; printf 'x\n' > "$W/docs/relatorios/2026-11-01-$TRAB/sub/tecnico.md"; w add -A docs/relatorios
afirma "subpasta do relatório: barra" 2 "$(julga)"
limpa; prepara; git -C "$W" switch -q -c docs/nao-e-fechamento; g config "branch.docs/nao-e-fechamento.expxFechamento" "$MERGE"
afirma "outra branch com a marca: barra" 2 "$(julga)"
git -C "$W" switch -q "$FEC"; limpa

echo "portão: o PR de fechamento não seleciona entrega, e commit-por-task não o barra"
SK="$RAIZ/.claude/skills/mergex/scripts"
msg; prepara
jq -cn --arg c "git commit -F $MSG" --arg w "$W" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}' \
  | bash "$RAIZ/.claude/hooks/mergex/commit-por-task.sh" >/dev/null 2>&1
afirma "commit-por-task deixa passar" 0 "$?"
w commit -q -F "$MSG"; FECHA="$(w rev-parse HEAD)"
g remote set-head origin main >/dev/null 2>&1 || git -C "$T/r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
( cd "$W" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$FEC" "$FECHA" "$FEC" 0000000000000000000000000000000000000000 \
  | bash "$SK/portao-push.sh" --pre-push origin https://github.com/o/r.git >"$T/push" 2>&1 )
afirma "pre-push deixa passar" 0 "$?"
( cd "$W" && bash "$SK/portao-ci.sh" --verificar --base "$MERGE" --sha "$FECHA" --branch "$FEC" >"$T/ci" 2>&1 )
afirma "CI deixa passar" 0 "$?"
afirma "o CI não seleciona entrega" "motivo=ref_nao_aplicavel" "$(grep -m1 '^motivo=' "$T/ci")"

printf '\n%s ok, %s falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
