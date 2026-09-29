#!/usr/bin/env bash
#
# Bancada P0.2-C7-B / M4-A — o git-perigoso da MergeX tem caminho e id próprios.
#
# Prova: caminho único (`.claude/hooks/mergex/git-perigoso.sh`), id único
# (`mergex/git-perigoso`), registros coerentes (settings.json, hooks.json,
# plugin OpenCode), jq ausente falha fechado, e coexistência com o snapshot
# SprintX que publica `sprintx/git-perigoso` — sem overwrite e sem um id
# desligar o outro.
#
# O snapshot SprintX vem de SPRINTX_REPO (padrão: ../sprintx ao lado deste
# repositório) no SHA SPRINTX_SHA. Snapshot indisponível é FALHA; só
# M4A_SEM_SPRINTX=1 pula a coexistência, e o pulo é impresso.
#
# Uso: bash scripts/ci/test-m4a-git-perigoso-namespace.sh
#

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPRINTX_REPO="${SPRINTX_REPO:-$REPO/../sprintx}"
SPRINTX_SHA="${SPRINTX_SHA:-253b59233e6d7a225a05f011cf52668b708e448b}"
HOOK_REL='.claude/hooks/mergex/git-perigoso.sh'
HOOK="$REPO/$HOOK_REL"

OK=0; FALHOU=0; PULADO=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
igual() { if [ "$2" = "$3" ]; then ok "$1"; else falha "$1 — obteve '$3', esperava '$2'"; fi; }

carga() { # <comando> <cwd>
  jq -cn --arg c "$1" --arg w "$2" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}'
}

roda() { # <script> <carga> <cwd> [PATH] — define RC e SAIDA
  local script="$1" entrada="$2" cwd="$3" caminho="${4:-$PATH}"
  SAIDA="$(cd "$cwd" && printf '%s' "$entrada" | PATH="$caminho" "$BASH" "$script" 2>&1)"
  RC=$?
}

repo_git() { # <dir>
  git init -q -b feature/m4a "$1" 2>/dev/null || return 1
  git -C "$1" config user.email teste@expx.local
  git -C "$1" config user.name Teste
  git -C "$1" commit -q --allow-empty -m base
}

modos() { # <dir> <json dos hooks>
  mkdir -p "$1/.expx"
  printf '{"expx_hooks":1,"hooks":%s}\n' "$2" > "$1/.expx/hooks.json"
}

echo '1. Caminho e id únicos'
[ -f "$HOOK" ] && ok 'hook publicado em .claude/hooks/mergex/' || falha 'hook ausente do namespace mergex'
[ ! -e "$REPO/.claude/hooks/comum/git-perigoso.sh" ] && ok 'nenhuma cópia em comum/' \
  || falha 'comum/git-perigoso.sh ainda existe'
grep -Fxq 'HOOK="mergex/git-perigoso"' "$HOOK" && ok 'id lógico namespaced no hook' \
  || falha 'id lógico do hook não é mergex/git-perigoso'
grep -Fq '. "$DIR/../comum/base.sh"' "$HOOK" && ok 'a biblioteca comum é importada, não copiada' \
  || falha 'o hook não importa comum/base.sh'
[ ! -e "$REPO/.claude/hooks/mergex/base.sh" ] && ok 'base.sh não foi duplicada' || falha 'base.sh duplicada'

echo
echo '2. Registros coerentes com o contrato vivo'
igual 'hooks.json: mergex/git-perigoso em bloqueio' bloqueio \
  "$(jq -r '.hooks["mergex/git-perigoso"].modo // empty' "$REPO/.expx/hooks.json")"
igual 'hooks.json: id sem namespace ausente' '' \
  "$(jq -r '.hooks["git-perigoso"] // empty' "$REPO/.expx/hooks.json")"
CMDS="$(jq -r '.. | objects | select(has("command")) | .command' "$REPO/.claude/settings.json")"
igual 'settings.json: exatamente um registro do hook namespaced' 1 \
  "$(printf '%s\n' "$CMDS" | grep -Fc '/.claude/hooks/mergex/git-perigoso.sh')"
igual 'settings.json: nenhum registro do caminho antigo' 0 \
  "$(printf '%s\n' "$CMDS" | grep -Fc 'comum/git-perigoso.sh')"
igual 'settings.json: timeout crítico do git-perigoso' 30 \
  "$(jq -r '.. | objects | select(has("command")) | select(.command | contains("mergex/git-perigoso.sh")) | .timeout' "$REPO/.claude/settings.json")"
grep -Fq '"mergex/git-perigoso.sh",' "$REPO/.opencode/plugin/mergex.ts" \
  && ok 'plugin OpenCode invoca o caminho namespaced' || falha 'plugin OpenCode fora do namespace'
grep -Fq 'comum/git-perigoso.sh' "$REPO/.opencode/plugin/mergex.ts" \
  && falha 'plugin OpenCode ainda invoca o caminho antigo' || ok 'plugin OpenCode sem caminho antigo'

echo
echo '3. O modo é lido somente pelo id namespaced'
R="$D/modo"; repo_git "$R"
roda "$HOOK" "$(carga 'git push --force origin feature/m4a' "$R")" "$R"
igual 'sem hooks.json: bloqueio padrão' 2 "$RC"
modos "$R" '{"git-perigoso":{"modo":"desligado"}}'
roda "$HOOK" "$(carga 'git push --force origin feature/m4a' "$R")" "$R"
igual 'id sem namespace desligado não desliga a MergeX' 2 "$RC"
modos "$R" '{"sprintx/git-perigoso":{"modo":"desligado"}}'
roda "$HOOK" "$(carga 'git push --force origin feature/m4a' "$R")" "$R"
igual 'sprintx/git-perigoso desligado não desliga a MergeX' 2 "$RC"
modos "$R" '{"mergex/git-perigoso":{"modo":"desligado"}}'
roda "$HOOK" "$(carga 'git push --force origin feature/m4a' "$R")" "$R"
igual 'mergex/git-perigoso desligado desliga só a MergeX' 0 "$RC"
rm -f "$R/.expx/hooks.json"

echo
echo '4. jq ausente é bloqueio de contrato, não sucesso silencioso'
BIN="$D/bin-sem-jq"; mkdir -p "$BIN"
for c in cat grep dirname; do
  printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v "$c")" > "$BIN/$c"; chmod +x "$BIN/$c"
done
PATH="$BIN" command -v jq >/dev/null 2>&1 && falha 'o PATH de prova ainda enxerga jq' || ok 'PATH de prova sem jq'
roda "$HOOK" "$(carga 'git push --force origin feature/m4a' "$R")" "$R" "$BIN"
igual 'sem jq: push forçado barra' 2 "$RC"
case "$SAIDA" in *'dependência ausente: jq'*) ok 'sem jq: mensagem nomeia a dependência' ;;
  *) falha "sem jq: mensagem não nomeia jq: $SAIDA" ;; esac
roda "$HOOK" "$(carga 'git status' "$R")" "$R" "$BIN"
igual 'sem jq: qualquer git é barrado (não há como avaliar)' 2 "$RC"
roda "$HOOK" "$(carga 'npm test' "$R")" "$R" "$BIN"
igual 'sem jq: comando sem git não é assunto do hook' 0 "$RC"
roda "$HOOK" "$(carga 'ls /tmp/digital' "$R")" "$R" "$BIN"
igual 'sem jq: "git" dentro de palavra não barra' 0 "$RC"
roda "$HOOK" "$(carga 'git status' "$R")" "$R"
igual 'com jq: git status passa' 0 "$RC"

echo
echo '5. Coexistência com o snapshot SprintX'
if ! git -C "$SPRINTX_REPO" cat-file -e "$SPRINTX_SHA^{commit}" 2>/dev/null; then
  if [ "${M4A_SEM_SPRINTX:-0}" = 1 ]; then
    PULADO=$((PULADO+1)); printf '  PULADO coexistência: snapshot %s indisponível em %s\n' "$SPRINTX_SHA" "$SPRINTX_REPO"
  else
    falha "snapshot SprintX $SPRINTX_SHA indisponível em $SPRINTX_REPO (M4A_SEM_SPRINTX=1 pula)"
  fi
else
  S="$D/sprintx"; mkdir -p "$S"
  git -C "$SPRINTX_REPO" archive "$SPRINTX_SHA" .claude .expx | tar -xf - -C "$S"
  M="$D/mergex"; mkdir -p "$M"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard -- .claude/hooks .claude/settings.json .expx \
      | xargs -0 tar -cf - ) | tar -xf - -C "$M"
  SX="$S/.claude/hooks/sprintx/git-perigoso.sh"
  [ -f "$SX" ] && ok 'snapshot SprintX publica sprintx/git-perigoso.sh' || falha 'snapshot SprintX sem o hook'
  igual 'snapshot SprintX registra o id sprintx/git-perigoso' bloqueio \
    "$(jq -r '.hooks["sprintx/git-perigoso"].modo // empty' "$S/.expx/hooks.json")"

  # Os dois conjuntos de hooks não disputam nenhum caminho físico.
  COMUNS="$(comm -12 \
    <(cd "$S" && find .claude/hooks -type f | LC_ALL=C sort) \
    <(cd "$M" && find .claude/hooks -type f | LC_ALL=C sort))"
  igual 'nenhum arquivo de hook em comum entre SprintX e MergeX' '' "$COMUNS"

  for ordem in sprintx-primeiro mergex-primeiro; do
    T="$D/$ordem"; repo_git "$T"
    if [ "$ordem" = sprintx-primeiro ]; then
      cp -R "$S/.claude" "$T/"; cp -R "$M/.claude" "$T/"
    else
      cp -R "$M/.claude" "$T/"; cp -R "$S/.claude" "$T/"
    fi
    cmp -s "$T/.claude/hooks/sprintx/git-perigoso.sh" "$SX" \
      && ok "$ordem: o hook SprintX ficou intacto" || falha "$ordem: o hook SprintX foi sobrescrito"
    cmp -s "$T/$HOOK_REL" "$M/$HOOK_REL" \
      && ok "$ordem: o hook MergeX ficou intacto" || falha "$ordem: o hook MergeX foi sobrescrito"
  done

  # Os dois registros de modo convivem no mesmo .expx/hooks.json (a fusão dos
  # arquivos é do instalador; aqui só a união dos ids é provada).
  T="$D/sprintx-primeiro"; mkdir -p "$T/.expx"
  jq -s '{expx_hooks:1, hooks:(.[0].hooks + .[1].hooks)}' "$S/.expx/hooks.json" "$M/.expx/hooks.json" \
    > "$T/.expx/hooks.json"
  igual 'união: as chaves das duas skills são disjuntas' '' \
    "$(jq -r -n --slurpfile a "$S/.expx/hooks.json" --slurpfile b "$M/.expx/hooks.json" \
      '[$a[0].hooks | keys[]] as $x | [$b[0].hooks | keys[]] | map(select(. as $k | $x | index($k))) | .[]')"
  igual 'união: sprintx/git-perigoso presente' bloqueio "$(jq -r '.hooks["sprintx/git-perigoso"].modo' "$T/.expx/hooks.json")"
  igual 'união: mergex/git-perigoso presente' bloqueio "$(jq -r '.hooks["mergex/git-perigoso"].modo' "$T/.expx/hooks.json")"

  PUSH="$(carga 'git push --force origin feature/m4a' "$T")"
  roda "$T/.claude/hooks/sprintx/git-perigoso.sh" "$PUSH" "$T"; igual 'ambos ligados: SprintX barra' 2 "$RC"
  roda "$T/$HOOK_REL" "$PUSH" "$T"; igual 'ambos ligados: MergeX barra' 2 "$RC"

  cp "$T/.expx/hooks.json" "$D/uniao.json"
  jq '.hooks["mergex/git-perigoso"].modo = "desligado"' "$D/uniao.json" > "$T/.expx/hooks.json"
  roda "$T/$HOOK_REL" "$PUSH" "$T"; igual 'mergex desligado: MergeX passa' 0 "$RC"
  roda "$T/.claude/hooks/sprintx/git-perigoso.sh" "$PUSH" "$T"; igual 'mergex desligado: SprintX continua barrando' 2 "$RC"

  jq '.hooks["sprintx/git-perigoso"].modo = "desligado"' "$D/uniao.json" > "$T/.expx/hooks.json"
  roda "$T/.claude/hooks/sprintx/git-perigoso.sh" "$PUSH" "$T"; igual 'sprintx desligado: SprintX passa' 0 "$RC"
  roda "$T/$HOOK_REL" "$PUSH" "$T"; igual 'sprintx desligado: MergeX continua barrando' 2 "$RC"

  # Cada settings.json registra só o próprio caminho.
  igual 'settings SprintX aponta para sprintx/git-perigoso.sh' 1 \
    "$(jq -r '.. | objects | select(has("command")) | .command' "$S/.claude/settings.json" | grep -c 'hooks/sprintx/git-perigoso.sh')"
  igual 'settings SprintX não aponta para o hook MergeX' 0 \
    "$(jq -r '.. | objects | select(has("command")) | .command' "$S/.claude/settings.json" | grep -c 'mergex/git-perigoso.sh')"
fi

echo
echo '6. Destino do push: decide o destino nomeado, não a branch ativa'
#
# O bloco "push na principal" respondia a uma pergunta só — "a branch ativa é a
# principal?" — e com ela cobria duas situações que não são a mesma:
#
#   - o comando NOMEIA um destino. Aí quem decide é o destino: estando em main,
#     `git push origin feature/x` não toca a principal e é trabalho legítimo;
#   - o comando não nomeia destino nenhum (`git push`, `git push origin`,
#     `--all`). Aí o destino é o upstream da branch ativa, e só nesse caso
#     "estou na principal" é motivo suficiente.
#
# Confundir as duas dava os dois defeitos cobertos aqui: o falso positivo que
# barra destino explícito de feature estando em main, e a falha aberta que
# deixa `git push origin :main` passar estando fora dela.

repo_principal() { # <dir> — repo cuja branch ativa É a principal (main)
  git init -q -b main "$1" 2>/dev/null || return 1
  git -C "$1" config user.email teste@expx.local
  git -C "$1" config user.name Teste
  git -C "$1" commit -q --allow-empty -m base
}

repo_trabalho() { # <dir> — main existe (é a principal), mas a ativa é feature/x
  repo_principal "$1" || return 1
  git -C "$1" switch -q -c feature/x
}

EM_MAIN="$D/em-main"; repo_principal "$EM_MAIN" || falha 'fixture em-main não pôde ser criada'
FORA="$D/fora-main";  repo_trabalho  "$FORA"    || falha 'fixture fora-main não pôde ser criada'

# Cada caso executa o hook de verdade, por payload, como o harness faz.
em_main() { # <rc esperado> <comando>
  roda "$HOOK" "$(carga "$2" "$EM_MAIN")" "$EM_MAIN"; igual "em main: $2" "$1" "$RC"
}
fora() { # <rc esperado> <comando>
  roda "$HOOK" "$(carga "$2" "$FORA")" "$FORA"; igual "fora de main: $2" "$1" "$RC"
}

igual 'fixture em-main: a branch ativa é main' main "$(git -C "$EM_MAIN" branch --show-current)"
igual 'fixture fora-main: a branch ativa é feature/x' feature/x "$(git -C "$FORA" branch --show-current)"
git -C "$FORA" show-ref --verify --quiet refs/heads/main \
  && ok 'fixture fora-main: main existe, logo é a principal do repo' \
  || falha 'fixture fora-main: sem refs/heads/main o hook não enxerga a principal'

echo
echo '6.1 Em main, destino explícito de branch de trabalho passa'
em_main 0 'git push origin --delete feature/x'
em_main 0 'git push origin :refs/heads/feature/x'
em_main 0 'git push -u origin feature/x'
em_main 0 'git push origin feature/x'

echo
echo '6.2 Em main, o que tem de continuar barrado continua'
em_main 2 'git push'
em_main 2 'git push origin'
em_main 2 'git push origin HEAD'
em_main 2 'git push --all origin'
em_main 2 'git push origin main'
em_main 2 'git push origin refs/heads/main'
em_main 2 'git push origin HEAD:main'
em_main 2 'git push origin :main'
em_main 2 'git push origin --delete main'
em_main 2 'git push origin -d main'
em_main 2 'git push --force origin feature/x'
em_main 2 'git push -f origin feature/x'
em_main 2 'git push --force-with-lease origin feature/x'
em_main 2 'git push origin +feature/x:feature/x'
em_main 2 'git commit -m trabalho'

echo
echo '6.3 Fora de main, qualquer destino main barra — inclusive depois de `:`'
fora 2 'git push origin :main'
fora 2 'git push origin :refs/heads/main'
fora 2 'git push origin feature/x:main'
fora 2 'git push origin refs/heads/feature/x:refs/heads/main'
fora 2 'git push origin main'
fora 2 'git push origin HEAD:main'
fora 2 'git push origin --delete main'
fora 2 'git push origin -d main'
fora 2 'git push --force origin feature/x'
fora 2 'git push origin +feature/x:feature/x'
# Sem refspec, a única palavra solta é o REMOTO. Um remoto que se chama como a
# principal continua barrado, como já era antes desta correção.
fora 2 'git push main'

echo
echo '6.4 Fora de main, o trabalho normal não é incomodado'
fora 0 'git push'
fora 0 'git push origin'
fora 0 'git push origin HEAD'
fora 0 'git push -u origin feature/x'
fora 0 'git push origin --delete feature/x'
fora 0 'git push origin :refs/heads/feature/x'
fora 0 'git commit -m trabalho'

echo
echo '6.5 Precisão: nome que só contém "main" não é a principal'
em_main 0 'git push origin domain'
em_main 0 'git push origin feature/main-menu'
em_main 0 'git push origin :domain'
fora 0 'git push origin domain'
fora 0 'git push origin feature/main-menu'
fora 0 'git push origin :feature/main-menu'

echo
echo '6.6 Em main, push implícito segue implícito com redirecionamento e opções'
#
# "Sem destino" não pode ser uma FORMA de linha reconhecida por enumeração: o
# que decide é a ausência de refspec, não o que vem depois dela. Redirecionar a
# saída, encanar num tee ou escrever uma opção DEPOIS do remoto não transforma
# um push implícito em push com destino — e enquanto transformava, `git push`
# em main saía por qualquer um desses acessórios.
em_main 2 'git push > /tmp/m4a-push.log'
em_main 2 'git push 2>/tmp/m4a-push.log'
em_main 2 'git push origin > /tmp/m4a-push.log'
em_main 2 'git push origin --all'
em_main 2 'git push origin --mirror'
em_main 2 'git push origin -v'
em_main 2 'git push -v origin -v'
em_main 2 'git push --receive-pack /usr/bin/git-receive-pack origin'
em_main 2 'git push --repo=origin'
em_main 2 'git push --mirror'
em_main 2 'git push | tee /tmp/m4a-push.log'

echo
echo '6.7 --all e --mirror alcançam a principal de qualquer branch'
#
# Os dois empurram refs que o comando não nomeia — entre elas a principal.
# Ficar fora de main não torna nenhum deles seguro.
em_main 2 'git push --all'
em_main 2 'git push --mirror origin'
fora 2 'git push --all'
fora 2 'git push --all origin'
fora 2 'git push --mirror origin'
fora 2 'git push origin --all'
fora 2 'git push origin --mirror'

echo
echo '6.8 Destino entre aspas continua sendo destino'
#
# O hook recebe a string do comando como ela foi escrita: as aspas chegam
# dentro do token. Reconhecer a principal só quando ela vem crua deixava
# `origin "main"` passar.
em_main 2 'git push origin "main"'
fora 2 'git push origin "main"'
fora 2 "git push origin 'refs/heads/main'"
fora 2 'git push origin "HEAD:main"'
fora 2 'git push origin ":main"'
em_main 0 'git push origin "feature/x"'
fora 0 "git push origin 'feature/x'"

echo
echo '6.9 Opção global do git antes do push não esconde o push'
#
# `git -C <path> push` e `git -c <k>=<v> push` têm o VALOR numa palavra
# separada. Toda a seção de push era casada por uma regex que só admitia
# opções sem valor entre `git` e `push`: com o valor solto no meio, o comando
# deixava de ser reconhecido como push e saía inteiro — inclusive forçado.
em_main 2 'git -C /tmp/m4a-outro push'
em_main 2 'git -c push.default=simple push'
em_main 2 'git --git-dir /tmp/m4a-outro/.git push origin main'
fora 2 'git -C /tmp/m4a-outro push origin main'
fora 2 'git -c user.name=x push --force origin feature/x'
fora 2 'git -C /tmp/m4a-outro push --mirror origin'
fora 2 'git --work-tree /tmp/m4a-outro push origin :main'
em_main 0 'git -C /tmp/m4a-outro push origin feature/x'
fora 0 'git -c core.pager=cat push origin feature/x'

echo
echo '6.10 Destino explícito de trabalho tolera opção e cano seguros ao redor'
em_main 0 'git push origin feature/x --quiet'
em_main 0 'git push --quiet origin feature/x'
em_main 0 'git push -u origin feature/x 2>/dev/null'
em_main 0 'git push origin feature/x | tee /tmp/m4a-push.log'
em_main 0 'git push -o ci.skip origin feature/x'
em_main 0 'git push origin HEAD:feature/x'
fora 0 'git push origin feature/x --quiet'
fora 0 'git push origin feature/x:feature/x'
fora 0 'git push origin feature/x | tee /tmp/m4a-push.log'

echo
echo '6.11 Destino que o hook não consegue classificar falha fechado'
#
# Variável, substituição de comando e curinga só têm valor na hora em que o
# shell roda; o hook vê o texto. Não dá para provar que o destino não é a
# principal, e um hook de segurança não passa o que não provou.
em_main 2 'git push origin "$RAMO"'
em_main 2 'git push origin ${RAMO}'
fora 2 'git push origin "$RAMO"'
fora 2 'git push origin $(cat /tmp/m4a-ramo)'
fora 2 "git push origin 'refs/heads/*:refs/heads/*'"

echo
echo '6.12 Num encadeamento, o push perigoso continua sendo visto'
em_main 2 'git push origin feature/x && git push origin main'
fora 2 'git push origin feature/x; git push --force origin feature/y'
fora 2 'git push -fu origin feature/x'
fora 2 'git push --force-if-includes origin feature/x'
em_main 0 'echo inicio && git push origin feature/x'

echo
echo '6.13 O push embrulhado por outro programa continua sendo um push'
#
# `bash -c`, `sh -c` e `eval` colocam o comando dentro de um argumento. O `git`
# deixa de ser a primeira palavra do segmento, mas continua sendo o programa
# que vai rodar — e a regra antiga, que varria a linha inteira, já enxergava
# esse push. Procurar o `git` dentro do segmento é o que impede a correção de
# devolver essa cobertura para trás.
em_main 2 'bash -c "git push"'
em_main 2 'bash -c "git push origin main"'
fora 2 'bash -c "git push origin main"'
fora 2 'sh -c "git push origin :main"'
fora 2 'eval "git push --mirror origin"'
fora 2 'bash -c "git push --force origin feature/x"'
em_main 0 'bash -c "git push origin feature/x"'
# A aspa simples embrulha igual à dupla.
fora 2 "sh -c 'git push origin main'"
em_main 2 "bash -c 'git push'"
# Embrulhar um comando inofensivo não inventa perigo.
em_main 0 'bash -c "git status"'
fora 0 'bash -c "git log --oneline"'

echo
echo '6.14 A aspa de fechamento anda com o último token, e ele ainda é uma opção'
#
# Embrulhar o comando cola a aspa de fechamento na ÚLTIMA palavra: `bash -c
# "git push --all"` dá o token `--all"`, não `--all`. O reconhecimento das
# opções compara o token inteiro, então `--all"`, `--mirror"` e `--force"`
# deixavam de ser reconhecidos — e o push escapava por fora da principal,
# justamente onde a branch ativa não salva. É o mesmo bypass do embrulho: só
# muda de qual palavra a aspa sobrou.
fora 2 'bash -c "git push --all"'
fora 2 'eval "git push --all"'
fora 2 "eval 'git push --all'"
fora 2 'bash -c "git push origin --all"'
fora 2 'bash -c "git push origin --mirror"'
fora 2 'sh -c "git push --mirror"'
fora 2 'bash -c "git push origin feature/x --force"'
fora 2 'bash -c "git push origin feature/x --force-with-lease"'
em_main 2 'bash -c "git push origin feature/x --force"'
# O lado seguro continua seguro: opção inofensiva na ponta não barra nada.
fora 0 'bash -c "git push origin feature/x --quiet"'
em_main 0 'bash -c "git push origin feature/x --quiet"'

echo
echo '6.15 A continuação de linha não parte o push em dois comandos'
#
# A barra invertida no fim da linha não separa nada: o shell EMENDA as duas
# linhas antes de decidir o que é programa e o que é argumento. `git push \` com
# `origin main` na linha seguinte é UM push com destino nomeado — não um push
# implícito seguido de outra coisa.
#
# A leitura por segmento quebra o comando nos separadores, e a quebra de linha
# está entre eles: a segunda linha ia embora, e o `main` escrito nela deixava de
# ser visto. Fora da principal, onde a branch ativa não segura nada, o push para
# main passava. A regra antiga, que varria a linha inteira, já o barrava — a
# emenda da continuação é o que impede a correção de perder essa cobertura.
#
# Emendar é só do par barra-invertida+quebra. A quebra de linha solta continua
# separando comandos, porque é o que ela faz no shell.
NL='
'
fora    2 "git push \\$NL  origin main"
em_main 2 "git push \\$NL  origin main"
fora    2 "git push origin \\$NL  main"
em_main 2 "git push origin \\$NL  main"
fora    2 "git \\$NL  push origin main"
em_main 2 "git \\$NL  push origin main"
fora    2 "git push origin \\$NL  HEAD:main"
fora    2 "git push origin \\$NL  :main"
fora    2 "git push origin \\$NL  feature/x:main"
fora    2 "git push \\$NL  --all"
em_main 2 "git push \\$NL  --all"
fora    2 "git push \\$NL  --mirror origin"
fora    2 "git push --force \\$NL  origin feature/x"
fora    2 "git push \\$NL  origin \\$NL  main"
# A linha emendada também não inventa perigo: destino de trabalho segue passando.
fora    0 "git push origin \\$NL  feature/x"
em_main 0 "git push origin \\$NL  feature/x"
fora    0 "git push -u \\$NL  origin feature/x"
fora    0 "git push origin \\$NL  :refs/heads/feature/x"
fora    0 "git push origin \\$NL  feature/main-menu"
# Sem a barra invertida, a quebra de linha continua sendo fim de comando: o push
# escrito na segunda linha é lido por si, e é ele que decide.
em_main 2 "echo ini${NL}git push"
em_main 2 "echo ini${NL}git push origin main"
fora    2 "echo ini${NL}git push origin main"
fora    0 "echo ini${NL}git push origin feature/x"

echo
echo '6.16 Citar um push em texto não é executar um push'
#
# O hook procurava a palavra `git` em QUALQUER posição do segmento, para
# enxergar o push embrulhado por `bash -c`. Só que "aparecer no meio da linha"
# não distingue quem RODA de quem CITA: `echo "git push origin main"` imprime
# um texto e não empurra nada, e passou a ser barrado — junto com a mensagem
# que fala de push, o aviso impresso e a busca por push no código. Falso
# positivo que atrapalha o dia inteiro é o que a regra 1 do desenho proíbe.
#
# Quem decide agora é o PROGRAMA do segmento: `git` ele mesmo, ou um programa
# que roda o que vem no argumento (6.17).
em_main 0 'echo "git push origin main"'
fora    0 'echo "git push origin main"'
em_main 0 'echo git push origin main'
em_main 0 'echo "git push --all"'
fora    0 'echo "git push --mirror origin"'
fora    0 'printf "%s\n" "git push --force origin main"'
em_main 0 'echo "nao faca git push origin main" > /tmp/m4a-aviso.txt'
fora    0 'grep -rn "git push --force" docs/'
fora    0 'git log --oneline --grep "git push origin main"'
# A mensagem de commit cita um push; o comando é um commit. Na principal ele
# barra por ser commit na principal, não por parecer push.
fora    0 'git commit -m "git push origin main"'
em_main 2 'git commit -m "git push origin main"'

echo
echo '6.17 O programa que RODA o argumento continua entregando o push'
#
# A contrapartida da 6.16: o embrulho de verdade não pode voltar a ser bypass.
# `bash -c`, `sh -c` e `eval` rodam o que está no argumento, e o `/bin/sh` é o
# mesmo programa que o `sh` — o que decide é o nome do programa, não o caminho
# onde ele mora. O prefixo de ambiente também não esconde nada: `VAR=x git
# push` é um push com uma variável na frente.
fora    2 'bash -c "git push origin main"'
fora    2 'sh -c "git push origin main"'
fora    2 'eval "git push origin main"'
fora    2 '/bin/sh -c "git push origin main"'
fora    2 '/bin/bash -c "git push --mirror origin"'
fora    2 '/usr/bin/env bash -c "git push origin main"'
fora    2 'sudo git push origin main'
fora    2 'xargs git push origin main'
fora    2 'GIT_DIR=/tmp/m4a-outro/.git git push origin main'
em_main 2 'GIT_SSH_COMMAND="ssh -v" git push'
fora    2 'GIT_SSH_COMMAND="ssh -v" git push origin main'
fora    2 'eval "git push --force origin feature/x"'
# E o embrulho não inventa perigo onde não há.
fora    0 'GIT_SSH_COMMAND="ssh -v" git push origin feature/x'
fora    0 '/bin/sh -c "git push origin feature/x"'
fora    0 'bash -c "git status"'

echo
echo '6.18 A quebra em segmentos não depende do sed do GNU'
#
# O contrato do repositório é bash 3.2 e utilitários POSIX — macOS incluído.
# `s/X/\n/` com QUEBRA DE LINHA no lado direito é extensão GNU: no sed do BSD
# esse `\n` é a letra `n`. Os segmentos saíam grudados numa linha só, `git
# status; git push origin main` virava `git statusngit push origin main`, o
# `push` deixava de ser lido — e o hook falhava ABERTO exatamente na cadeia
# que ele existe para barrar.
#
# A prova é dupla, e nenhuma delas depende de rodar num macOS: um sed que se
# comporta como o do BSD, e nenhum sed no PATH. Se o resultado é o mesmo nos
# dois, a quebra não é do sed.
SED_REAL="$(command -v sed)"
SED_BSD="$D/bin-sed-bsd"; mkdir -p "$SED_BSD"
{ printf '#!/usr/bin/env bash\n'
  printf '# sed "BSD": a unica divergencia emulada e a que importa — `\\n` no lado\n'
  printf '# direito do s/// e a LETRA n, nao uma quebra de linha.\n'
  printf 'a=()\n'
  printf 'for x in "$@"; do a+=( "${x//\\\\n/n}" ); done\n'
  printf 'exec %s "${a[@]}"\n' "$SED_REAL"
} > "$SED_BSD/sed"; chmod +x "$SED_BSD/sed"
SED_SEM="$D/bin-sed-ausente"; mkdir -p "$SED_SEM"
{ printf '#!/bin/sh\n'; printf 'printf "sed indisponivel\\n" >&2\n'; printf 'exit 127\n'; } \
  > "$SED_SEM/sed"; chmod +x "$SED_SEM/sed"

igual 'shim: o sed BSD não produz quebra de linha no s///' 'anb' \
  "$(printf 'a;b\n' | PATH="$SED_BSD:$PATH" sed -e 's/;/\n/g')"
if PATH="$SED_SEM:$PATH" sed -e 's/a/b/' </dev/null >/dev/null 2>&1; then
  falha 'shim: o PATH de prova ainda enxerga um sed que funciona'
else
  ok 'shim: PATH de prova sem sed utilizável'
fi
# O hook não chama sed em lugar nenhum: a quebra é do próprio bash. Comentário
# não conta — só linha de código.
igual 'o hook não invoca sed' 0 \
  "$(grep -v '^[[:space:]]*#' "$HOOK" | grep -Ec '(^|[^[:alnum:]_./-])sed([^[:alnum:]_]|$)')"

com_sed() { # <rc esperado> <dir> <rótulo do dir> <comando>
  roda "$HOOK" "$(carga "$4" "$2")" "$2" "$SHIM:$PATH"
  igual "$ROT/$3: $4" "$1" "$RC"
}
for SHIM in "$SED_BSD" "$SED_SEM"; do
  ROT="${SHIM##*/}"
  com_sed 2 "$EM_MAIN" 'em main' 'git status; git push'
  com_sed 2 "$FORA"    'fora'    'git status; git push origin main'
  com_sed 2 "$FORA"    'fora'    'git fetch origin && git push --force origin feature/x'
  com_sed 2 "$FORA"    'fora'    'git fetch origin || git push origin main'
  com_sed 2 "$FORA"    'fora'    'git status | cat; git push origin :main'
  com_sed 2 "$EM_MAIN" 'em main' 'git push origin feature/x && git push origin main'
  com_sed 2 "$FORA"    'fora'    'git push origin feature/x; git push --mirror origin'
  com_sed 2 "$EM_MAIN" 'em main' 'git push > /tmp/m4a-push.log'
  com_sed 2 "$EM_MAIN" 'em main' 'git push 2>/tmp/m4a-push.log'
  com_sed 2 "$EM_MAIN" 'em main' 'git push | tee /tmp/m4a-push.log'
  com_sed 2 "$EM_MAIN" 'em main' 'git push'
  # O lado seguro não muda de lado por causa do sed.
  com_sed 0 "$FORA"    'fora'    'git status; git push origin feature/x'
  com_sed 0 "$EM_MAIN" 'em main' 'git push origin feature/x | tee /tmp/m4a-push.log'
  com_sed 0 "$EM_MAIN" 'em main' 'echo inicio && git push origin feature/x'
done

echo
echo '6.19 A barra invertida escapada não emenda a quebra de linha'
#
# A barra que continua a linha é a que NÃO está escapada. Barras andam em
# pares: `\\` é UMA barra literal, e a quebra depois dela continua sendo fim de
# comando — o push escrito na linha seguinte é um push por si e tem de ser
# lido. Apagar todo par barra+quebra sem contar a corrida de barras fundia dois
# comandos que o shell mantém separados: a palavra da linha de cima colava no
# `git` da linha de baixo e o push da segunda linha sumia do segmento. Falha
# ABERTA do mesmo tamanho da que a emenda veio consertar.
#
# Quem decide é a paridade: ímpar emenda, par separa.
B1='\'      # uma barra: continua a linha
B2='\\'     # duas barras: uma barra literal, a quebra separa
fora    2 "echo a${B2}${NL}git push origin main"
em_main 2 "echo a${B2}${NL}git push"
fora    2 "echo a${B2}${NL}git push --force origin feature/x"
fora    2 "echo a${B2}${NL}git push --mirror origin"
em_main 2 "echo a${B2}${B2}${NL}git push origin main"
fora    2 "echo a${B2}${B2}${NL}git push origin :main"
# Par com push inofensivo na linha de baixo continua passando.
fora    0 "echo a${B2}${NL}git push origin feature/x"
em_main 0 "echo a${B2}${NL}git push origin feature/x"
# Ímpar continua emendando — o outro lado da mesma conta.
fora    2 "git push origin ${B1}${NL}main"
fora    2 "git push origin ${B2}${B1}${NL}main"
em_main 0 "echo ini${B1}${NL}git push"
fora    0 "git push origin ${B1}${NL}feature/x"

echo
echo '6.20 O descritor do redirecionamento é palavra inteira, não fim de nome'
#
# Em `2>/tmp/log` o `2` é descritor porque é uma palavra SÓ de dígitos. Em
# `main2>/tmp/log` o `2` é a última letra do destino `main2` — outra branch,
# que não é a principal. Descartar o dígito colado no nome transformava `main2`
# em `main` e barrava um push legítimo, e o mesmo corte comia o fim de
# qualquer destino terminado em número.
fora    0 'git push origin main2>/tmp/m4a-push.log'
em_main 0 'git push origin main2>/tmp/m4a-push.log'
fora    0 'git push origin release2>>/tmp/m4a-push.log'
em_main 0 'git push origin feature/x2>/tmp/m4a-push.log'
fora    0 'git push origin main2'
# O descritor de verdade continua sendo descritor, e o destino continua sendo
# lido por inteiro. Se ele não for reconhecido, o número sobra como palavra e
# ocupa o lugar de um refspec: o push implícito na principal deixa de parecer
# implícito e sai livre — falha ABERTA por um `2>` escrito depois do remoto.
em_main 2 'git push origin 2>/tmp/m4a-push.log'
em_main 2 'git push origin 1>>/tmp/m4a-push.log'
em_main 2 'git push origin 2>&1'
fora    0 'git push origin 2>/tmp/m4a-push.log'
fora    2 'git push origin main 2>/tmp/m4a-push.log'
em_main 2 'git push origin main 2>/tmp/m4a-push.log'
fora    2 'git push origin :main 2>/tmp/m4a-push.log'
em_main 2 'git push 2>/tmp/m4a-push.log'
em_main 2 'git push 2>&1 | tee /tmp/m4a-push.log'
fora    2 'git push --force origin feature/x2>/tmp/m4a-push.log'
fora    2 'git push origin main2 main'
fora    2 'git push --mirror origin 2>/tmp/m4a-push.log'

echo
echo '---------------------------------------------'
printf '%d ok, %d falha(s), %d pulado(s)\n' "$OK" "$FALHOU" "$PULADO"
[ "$FALHOU" = 0 ]
