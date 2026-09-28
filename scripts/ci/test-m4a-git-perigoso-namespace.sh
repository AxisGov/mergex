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
echo '---------------------------------------------'
printf '%d ok, %d falha(s), %d pulado(s)\n' "$OK" "$FALHOU" "$PULADO"
[ "$FALHOU" = 0 ]
