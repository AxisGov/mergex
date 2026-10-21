#!/usr/bin/env bash
#
# A feature empilhada redirecionada (09-revisao.md, "Feature redirecionada"; desenho de
# 2026-10-18, 4.4; DM-245). Depois do merge da predecessora, o PR so e elegivel no E9
# sincronizado com a base nova, com CI do headRefOid concluido depois do redirecionamento e,
# com `revisor_bot` declarado na arvore da base, uma revisao de um desses logins no
# headRefOid feita depois dele. Roda o bloco real do reference, depois do bloco do HEAD
# autoritativo (R4), com um `gh` de mentira; o leitor do projeto e o real, com o nucleo da
# copia (scripts/ci/fixtures/candidatos/expx-nucleo/) versionado na base.
#
# Uso: bash scripts/ci/test-e9-redirecionamento.sh

set -uo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
e9="$raiz/.claude/skills/mergex/references/09-revisao.md"
r11="$raiz/.claude/skills/mergex/references/11-reconciliacao-base.md"
copia="$raiz/scripts/ci/fixtures/candidatos/expx-nucleo"
nucleo_rel='.expx/marketplace/plugins/expx/nucleo/scripts'

ok=0; falhou=0
passa()  { ok=$((ok+1)); printf '  ok    %s\n' "$1"; }
quebra() { falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; }
for v in $(compgen -e); do case "$v" in FATIA_*) unset "$v" ;; esac; done

aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
# bloco cercado do reference que contem <marca>
bloco() {
  awk -v marca="$1" '/^```/ { if (dentro) { if (achou) { printf "%s", buf; exit } dentro = 0; next }
                              dentro = 1; buf = ""; achou = 0; next }
       dentro { buf = buf $0 "\n"; if (index($0, marca)) achou = 1 }' "$e9" | sed 's|<n>|7|g'
}
bloco 'pull/<n>/head' > "$aux/r4.sh"
bloco '# E9: feature redirecionada (DM-245)' > "$aux/d3.sh"
[ -s "$aux/d3.sh" ] && passa 'o 09-revisao.md tem o bloco da feature redirecionada' \
  || quebra 'o 09-revisao.md nao tem o bloco executavel da feature redirecionada'
cat "$aux/r4.sh" "$aux/d3.sh" > "$aux/e9.sh"

g() { git -c core.autocrlf=false -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
sem="$aux/semente"; g init -q -b main "$sem"
while IFS= read -r f; do
  mkdir -p "$sem/$nucleo_rel/$(dirname "$f")" && tr -d '\r' < "$copia/$f" > "$sem/$nucleo_rel/$f"
done < <(cd "$copia" && find . -type f ! -path ./ORIGEM | sed 's|^\./||')
commit() { # <arquivo> <conteudo|-apagar> -> imprime o sha; commita sobre o HEAD atual
  if [ "$2" = -apagar ]; then g -C "$sem" rm -q -- "$1"; else printf '%s\n' "$2" > "$sem/$1"; g -C "$sem" add -A; fi
  g -C "$sem" commit -q -m "$1"; g -C "$sem" rev-parse HEAD
}
em() { g -C "$sem" checkout -q --detach "$1"; }
config_bot() { printf '{ "expx_fatiamento": 2, "revisor_bot": [%s] }' "$1"; }
A="$(commit a.txt a)"
P="$(commit p.txt predecessora)"         # a predecessora, mergeada: a base nova
H="$(commit h.txt feature)"              # a feature sobre a predecessora: sincronizada
em "$A"; M="$(commit m.txt outra)"        # a base andou por outro caminho: H nao a contem
em "$A"; mkdir -p "$sem/.expx"
B="$(commit .expx/fatiamento.json "$(config_bot '"codeant-ai[bot]"')")"
HB="$(commit h.txt feature)"
em "$B"; HBr="$(commit .expx/fatiamento.json -apagar)"   # a cabeca tira o revisor_bot
em "$A"; Bp="$(commit .expx/fatiamento.json "$(config_bot '"codeant"')")"
HBp="$(commit h.txt feature)"
em "$P"; mkdir -p "$sem/.expx"; HA="$(commit .expx/fatiamento.json "$(config_bot '"codeant-ai[bot]"')")"
em "$A"; g -C "$sem" rm -r -q -- "$nucleo_rel"; g -C "$sem" commit -q -m sem-nucleo
mkdir -p "$sem/.expx"; Bn="$(commit .expx/fatiamento.json "$(config_bot '"codeant-ai[bot]"')")"
HBn="$(commit h.txt feature)"

g init -q --bare -b main "$aux/dono/repo.git"
g -C "$sem" push -q "$aux/dono/repo.git" "$A:refs/heads/main" 2>/dev/null
url='https://github.com/dono/repo'
g clone -q "$aux/dono/repo.git" "$aux/clone" 2>/dev/null
git -C "$aux/clone" remote set-url origin "$url.git"
git -C "$aux/clone" config "url.$aux/dono/repo.git.insteadOf" "$url.git"
# sem nucleo instalado no disco: o leitor que conta e o da arvore da base (--nucleo-da-rev)
rm -rf "$aux/clone/.expx"
mkdir -p "$aux/clone/.claude/skills/mergex/scripts"
cp "$raiz/.claude/skills/mergex/scripts/leitor-do-projeto.sh" "$aux/clone/.claude/skills/mergex/scripts/"

mkdir -p "$aux/bin" "$aux/f"
# o gh falso confere os argumentos que importam: o PR, o dono/repo e, nos checks, o headRefOid
cat > "$aux/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$*" in
  'pr view 7 --json url --jq .url') printf '%s/pull/7\n' "$URL_REPO" ;;
  'pr view 7 --json baseRefName,baseRefOid,headRefOid') cat "$FALSO/view.json" ;;
  'api graphql '*)
    case " $* " in *'-f o=dono -f r=repo '*) ;; *) echo "gh falso: dono/repo errado: $*" >&2; exit 9 ;; esac
    case "$*" in
      *BASE_REF_CHANGED_EVENT*) case " $* " in *' -F n=7 '*) cat "$FALSO/linha.json" ;; *) echo "gh falso: PR errado" >&2; exit 9 ;; esac ;;
      *statusCheckRollup*) case " $* " in *" -f h=$HEAD_ESPERADO "*) cat "$FALSO/checks.json" ;; *) echo "gh falso: HEAD errado" >&2; exit 9 ;; esac ;;
      *) echo "gh falso: consulta inesperada" >&2; exit 9 ;;
    esac ;;
  'api --paginate repos/dono/repo/pulls/7/reviews?per_page=100') cat "$FALSO/reviews.json" ;;
  *) echo "gh falso: chamada inesperada: $*" >&2; exit 9 ;;
esac
GH
chmod +x "$aux/bin/gh"

redir='2026-10-20T10:00:00Z'; antes='2026-10-20T09:00:00Z'; depois='2026-10-20T11:00:00Z'; fim='2026-10-20T12:00:00Z'
# check <nome> <nasceu> [<concluido em>] [<status>] [<id do workflow>]: check run de uma execucao
# do Actions (todo workflow se chama CI: o que os distingue e o id)
check() { printf '{"__typename":"CheckRun","name":"%s","status":"%s","completedAt":"%s","checkSuite":{"createdAt":"%s","app":{"slug":"github-actions"},"workflowRun":{"createdAt":"%s","workflow":{"id":"%s","name":"CI"}}}}' \
            "$1" "${4:-COMPLETED}" "${3:-$fim}" "$2" "$2" "${5:-W_ci}"; }
# check_app <app> <nome> <nasceu>: check run de um app, fora do Actions
check_app() { printf '{"__typename":"CheckRun","name":"%s","status":"COMPLETED","completedAt":"%s","checkSuite":{"createdAt":"%s","app":{"slug":"%s"},"workflowRun":null}}' \
                "$2" "$fim" "$3" "$1"; }
status() { printf '{"__typename":"StatusContext","context":"%s","state":"%s","createdAt":"%s"}' "$1" "${3:-SUCCESS}" "$2"; }
review() { printf '{"user":{"login":"%s"},"commit_id":"%s","submitted_at":"%s","state":"COMMENTED"}' "$1" "$2" "$3"; }
# cenario <base> <head> <checks> <reviews> ; opcionais no ambiente: REDIR (vazio: sem troca de
# base), CABECA (a ref do PR no repositorio), MAIN (a ponta real da base), PAGINA_A_MAIS=1 (os
# checks nao cabem numa pagina), REVS2 (uma segunda pagina de revisoes)
cenario() {
  g -C "$sem" push -q -f "$aux/dono/repo.git" "${MAIN:-$1}:refs/heads/main" "${CABECA:-$2}:refs/pull/7/head" 2>/dev/null
  printf '{"baseRefName":"main","baseRefOid":"%s","headRefOid":"%s"}' "$1" "$2" > "$aux/f/view.json"
  printf '{"data":{"repository":{"object":{"statusCheckRollup":{"contexts":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]}}}}}}' \
    "$([ -n "${PAGINA_A_MAIS:-}" ] && echo true || echo false)" "$3" > "$aux/f/checks.json"
  printf '[%s]' "$4" > "$aux/f/reviews.json"; [ -z "${REVS2:-}" ] || printf '[%s]' "$REVS2" >> "$aux/f/reviews.json"
  if [ "${REDIR-$redir}" = '' ]; then nos=''; else nos="{\"createdAt\":\"${REDIR-$redir}\"}"; fi
  printf '{"data":{"repository":{"pullRequest":{"timelineItems":{"nodes":[%s]}}}}}' "$nos" > "$aux/f/linha.json"
  saida="$(cd "$aux/clone" && PATH="$aux/bin:$PATH" URL_REPO="$url" FALSO="$aux/f" HEAD_ESPERADO="$2" bash "$aux/e9.sh" 2>"$aux/err")"; rc=$?
}
# espera <nome> <rc> <linha esperada> [<linha que nao pode aparecer>]
espera() {
  if [ "$rc" = "$2" ] && printf '%s\n' "$saida" | grep -qxF -- "$3" \
     && { [ -z "${4:-}" ] || ! printf '%s\n' "$saida" | grep -qxF -- "$4"; }; then passa "$1"
  else quebra "$1: rc $rc, saida '$saida', stderr '$(head -c 400 "$aux/err")'"; fi
}
ci_ok="$(check hooks "$depois")"
eleg='redirecionado=sim elegivel'
m_sinc='motivo: não sincronizado com a base nova'
m_ci='motivo: CI anterior ao redirecionamento'
m_bot='motivo: revisão do revisor_bot ausente no HEAD atual'

REDIR='' cenario "$P" "$H" "$ci_ok" ''
espera 'PR sem redirecionamento: as condicoes nao se aplicam' 0 'redirecionado=nao'
cenario "$M" "$H" "$ci_ok" ''
espera 'base nova nao ancestral do head: inelegivel nao sincronizado' 1 "$m_sinc" "$m_ci"
cenario "$P" "$H" '' ''
espera 'sincronizado e check verde so de head anterior: inelegivel CI anterior ao redirecionamento' 1 "$m_ci"
cenario "$P" "$H" "$(check hooks "$antes" "$antes")" ''
espera 'head inalterado pelo redirecionamento e check verde so de antes dele: inelegivel CI anterior ao redirecionamento' 1 "$m_ci"
cenario "$P" "$H" "$(check hooks "$antes" "$depois")" ''
espera 're-execucao de uma execucao de antes do redirecionamento, concluida depois: inelegivel CI anterior' 1 "$m_ci"
cenario "$P" "$H" "$(check hooks "$depois"),$(check contract "$antes")" ''
espera 'um check do head de antes do redirecionamento, outro depois: inelegivel CI anterior' 1 "$m_ci"
cenario "$P" "$H" "$(check hooks "$redir")" ''
espera 'check nascido no mesmo segundo do redirecionamento nao e depois dele' 1 "$m_ci"
cenario "$P" "$H" "$ci_ok,$(status CodeAnt "$antes")" ''
espera 'status de antes do redirecionamento: inelegivel CI anterior' 1 "$m_ci"
cenario "$P" "$H" "$(check hooks "$antes" "$antes"),$(check hooks "$depois"),$(status CodeAnt "$antes"),$(status CodeAnt "$depois")" ''
espera 'o mesmo check numa execucao de antes e numa nova (reabrir o PR): vale a nova, elegivel' 0 "$eleg"
cenario "$P" "$H" "$(check hooks "$antes" "$antes" '' W_outro),$(check hooks "$depois")" ''
espera 'dois workflows com o mesmo nome e o mesmo check: o de antes nao some, inelegivel CI anterior' 1 "$m_ci"
cenario "$P" "$H" "$(check_app app-a lint "$antes"),$(check_app app-b lint "$depois")" ''
espera 'dois apps com um check de mesmo nome: o de antes nao some, inelegivel CI anterior' 1 "$m_ci"
cenario "$P" "$H" "$(check_app app-a lint "$antes"),$(check_app app-a lint "$depois")" ''
espera 'o mesmo app com o check numa suite nova: vale a nova, elegivel' 0 "$eleg"
cenario "$P" "$H" "$ci_ok,$(status bot "$depois"),$(check lento "$depois" '' IN_PROGRESS),$(status externo "$depois" PENDING)" ''
espera 'sincronizado, CI verde no head, sem revisor_bot: elegivel (check em andamento fica para o R1)' 0 "$eleg"
cenario "$P" "$H" "$(check hooks "$antes" "$antes"),$(check hooks "$depois" '' IN_PROGRESS)" ''
espera 'execucao de antes concluida e a nova so em andamento: fica para o R1, nao e CI anterior' 0 "$eleg"
cenario "$P" "$H" "$ci_ok,$(status externo "$antes" PENDING)" ''
espera 'status pendente desde antes do redirecionamento: inelegivel CI anterior' 1 "$m_ci"
PAGINA_A_MAIS=1 cenario "$P" "$H" "$ci_ok" ''
espera 'checks em mais de uma pagina: nao verificavel' 1 'redirecionado=nao_verificavel: os checks não foram lidos'
CABECA="$M" cenario "$P" "$H" "$ci_ok" ''
espera 'cabeca buscada diferente do headRefOid: nao verificavel' 1 'redirecionado=nao_verificavel: a cabeça buscada não é o headRefOid'
MAIN="$A" cenario "$P" "$H" "$ci_ok" ''
espera 'ponta da base diferente do baseRefOid: nao verificavel' 1 'redirecionado=nao_verificavel: a ponta da base não é o baseRefOid'
if command -v node >/dev/null 2>&1; then
  cenario "$B" "$HB" "$ci_ok" "$(review 'codeant-ai[bot]' "$B" "$depois")"
  espera 'revisor_bot declarado e revisao so de head anterior: inelegivel' 1 "$m_bot"
  cenario "$B" "$HB" "$ci_ok" "$(review 'codeant-ai[bot]' "$HB" "$antes")"
  espera 'revisor_bot declarado e revisao no head de antes do redirecionamento: inelegivel' 1 "$m_bot"
  cenario "$B" "$HB" "$ci_ok" "$(review 'codeant-ai[bot]' "$HB" "$depois")"
  espera 'revisor_bot declarado e revisao no head depois do redirecionamento: elegivel' 0 "$eleg"
  cenario "$B" "$HB" "$ci_ok" "$(review 'codeant-ai' "$HB" "$depois"),$(review 'Codeant-AI[bot]' "$HB" "$depois")"
  espera 'login parecido (sem [bot], outra caixa) nao conta' 1 "$m_bot"
  cenario "$Bp" "$HBp" "$ci_ok" "$(review 'codeant-ai[bot]' "$HBp" "$depois")"
  espera 'login parecido (prefixo) nao conta' 1 "$m_bot"
  cenario "$P" "$HA" "$ci_ok" ''
  espera 'revisor_bot acrescentado so na cabeca do PR nao vale' 0 "$eleg"
  cenario "$B" "$HBr" "$ci_ok" ''
  espera 'revisor_bot tirado so na cabeca do PR tambem nao vale' 1 "$m_bot"
  cenario "$Bn" "$HBn" "$ci_ok" "$(review 'codeant-ai[bot]' "$HBn" "$depois")"
  espera 'base com .expx/fatiamento.json e sem a pasta do nucleo: inelegivel, leitor sai 3' 1 \
    'motivo: configuração da base não lida (leitor-do-projeto saiu 3)'
else
  passa 'casos do revisor_bot: pulados sem node (o CI cobre)'
fi

# contrato: a orientacao e a reconciliacao de base, nunca um commit vazio
sec="$(awk '/^### Feature redirecionada/ { d = 1; next } d && /^##/ { exit } d' "$e9")"
for t in 'nunca com commit vazio' '11-reconciliacao-base.md' 'DM-245' 'CI anterior ao redirecionamento' \
         'R1–R6 inteiro' '--nucleo-da-rev'; do
  printf '%s\n' "$sec" | grep -qF -- "$t" && passa "09-revisao.md, Feature redirecionada, cita: $t" \
    || quebra "09-revisao.md, Feature redirecionada, nao cita: $t"
done
grep -qF 'feature redirecionada' "$r11" && grep -qF 'commit vazio' "$r11" \
  && passa '11-reconciliacao-base.md encaminha a feature redirecionada, sem commit vazio' \
  || quebra '11-reconciliacao-base.md nao trata a feature redirecionada'

printf '%d ok, %d falha(s)\n' "$ok" "$falhou"
[ "$falhou" = 0 ]
