#!/usr/bin/env bash
#
# Bancada da seção crítica do E1 — o índice é do E1, e o E1 não é reentrante.
#
# Duas execuções do E1 na MESMA worktree compartilham índice, HEAD,
# `ENTREGA.commits` e o próximo `seq`. A C4 fez o resultado de uma corrida
# (lista com `seq` duplicado) PARAR; a C5 impede que esse estado seja criado.
#
# A bancada não testa a função de trava isolada: ela roda E1 de verdade, com
# `git add`, `git commit` e append em `ENTREGA.commits`, em repositórios
# temporários — inclusive DOIS AO MESMO TEMPO, na mesma worktree e em
# worktrees distintas.
#
# Sem rede e sem jq. Nada fora dos diretórios temporários é tocado.
#
# Uso: bash scripts/ci/test-trava-e1.sh               # tudo
#      bash scripts/ci/test-trava-e1.sh B C           # só esses grupos
#
# Grupos: A (E1 normal, saída limpa, retomada, E1 tardio, task repetida),
# B (dois E1 na mesma worktree), C (duas worktrees), D (stage preexistente),
# E (trava preexistente), G (verificação reprova), H (commit falha),
# I (commit sem registro), J (lista inválida no fim), ESPIAO (a seção cobre o
# append e a validação), EXTRA (leitura sem trava, staging em bloco, modo do
# agente).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/.claude/skills/mergex/scripts"
FECHA="$SCRIPTS/fechamento-do-e1.sh"
TRAVA="$SCRIPTS/trava-do-e1.sh"
SEQ="$SCRIPTS/sequencia-de-commits.sh"
PROVA="$SCRIPTS/prova-de-commit.sh"

OK=0; FALHOU=0
D="$(mktemp -d)"
trap 'cd "$REPO"; rm -rf "$D" 2>/dev/null' EXIT

ok()    { OK=$((OK+1)); printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }

igual() { # <descrição> <obtido> <esperado>
  if [ "$2" = "$3" ]; then ok "$1"
  else falha "$1 — obteve '$2', esperava '$3'"; fi
}

# Grupos. Sem argumento, a bancada roda tudo; com argumentos, só os grupos
# pedidos — é assim que cada mutação dirigida roda apenas a prova que a pega,
# em vez de repetir concorrência real dezessete vezes.
GRUPOS=" $* "
grupo() { # <nome>
  [ "$GRUPOS" = "  " ] && return 0
  case "$GRUPOS" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Fixture: um repositório com produto, ENTREGA aberta e uma base commitada.
# ---------------------------------------------------------------------------
entrega_vazia() { # <arquivo>
  cat > "$1" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: ft-teste
entregue_por: mergex
estado: aberto
versionado: true
branch: feature/ft-teste
branch_base: main
commits: []
desvios: []
criado_em: 2026-09-20
atualizado_em: 2026-09-20
---

# Entrega

Prosa da entrega.
EOF
}

tasks_concluidas() { # <arquivo> <id>...
  local arq="$1" id; shift
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: plano\ntrabalho_id: ft-teste\n'
    printf 'tasks:\n'
    for id in "$@"; do
      printf -- '  - id: %s\n    status: concluida\n    suite: verde\n' "$id"
      printf '    teste_integracao: integra\n    teste_funcional: funciona\n'
    done
    printf -- '---\n\n# Plano\n'
  } > "$arq"
}

mensagem() { # <arquivo> <task>
  printf 'feat(src): fecha %s\n\nObjetivo da task.\n\nTask: %s\nTrabalho: ft-teste\nTestes: integracao e funcional.\n' \
    "$2" "$2" > "$1"
}

repo() { # <dir>
  git init -q -b main "$1" 2>/dev/null
  (
    cd "$1" || exit 1
    git config user.email teste@expx.local
    git config user.name Teste
    git config commit.gpgsign false
    git config core.autocrlf false
    mkdir -p src docs/entregas/ft-teste
    printf 'base\n' > src/a.js
    printf 'base\n' > src/b.js
    entrega_vazia docs/entregas/ft-teste/ENTREGA.md
    git add -A >/dev/null 2>&1
    git commit -qm 'chore: base' >/dev/null 2>&1
  )
}

ENTREGA=docs/entregas/ft-teste/ENTREGA.md
SUFIXO='.mergex-e1.lock'

fechar() { # <dir> <task> <arquivo de produto> [--verificacao <cmd>]
  local dir="$1" task="$2" alvo="$3"; shift 3
  mensagem "$D/msg-$task.txt" "$task"
  ( cd "$dir" && bash "$FECHA" --fechar --entrega "$ENTREGA" --task "$task" \
      --mensagem "$D/msg-$task.txt" "$@" -- "$alvo" )
}

trava_de() { ( cd "$1" && bash "$TRAVA" --caminho ); }
commits_de() { ( cd "$1" && git rev-list --count HEAD ); }
itens_de()   { ( cd "$1" && bash "$SEQ" --ler "$ENTREGA" ); }
stage_de()   { ( cd "$1" && git diff --cached --name-only ); }

espera_trava() { # <dir> — bloqueia até a trava daquela worktree existir
  local t i=0
  t="$(trava_de "$1")"
  while [ ! -d "$t" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i+1)); done
  [ -d "$t" ]
}

if grupo A; then
  # ---------------------------------------------------------------------------
  echo 'A. E1 único normal — commit, append, seq correto, trava liberada'
  # ---------------------------------------------------------------------------
  A="$D/a"; repo "$A"
  printf 'muda\n' >> "$A/src/a.js"
  saida="$(fechar "$A" T-01.01 src/a.js 2>&1)"; rc=$?
  igual 'A — a seção crítica conclui com 0' "$rc" 0
  case "$saida" in *seq=1*) ok 'A — o item novo recebeu seq 1' ;;
    *) falha "A — saída sem seq=1: $saida" ;; esac
  igual 'A — exatamente um commit novo' "$(commits_de "$A")" 2
  igual 'A — exatamente um item em ENTREGA.commits' "$(itens_de "$A" | wc -l | tr -d '[:space:]')" 1
  igual 'A — o item registra a task e o SHA' "$(itens_de "$A" | cut -f3)" T-01.01
  sha="$( cd "$A" && git rev-parse --short HEAD )"
  igual 'A — o SHA registrado é o do commit produzido' "$(itens_de "$A" | cut -f4)" "$sha"
  # O registro em ENTREGA.commits acontece DEPOIS do commit, e o ENTREGA.md é
  # artefato de método: ele entra no commit pré-E6, nunca no commit da task.
  igual 'A — só o arquivo declarado entrou no commit' \
    "$( cd "$A" && git show --name-only --format= HEAD | tr -d '\r' | tr '\n' ' ' | sed 's/ *$//')" \
    'src/a.js'
  igual 'A — o índice ficou limpo' "$(stage_de "$A")" ''

  # ---------------------------------------------------------------------------
  echo
  echo 'F. Saída normal não deixa trava residual'
  # ---------------------------------------------------------------------------
  [ -d "$(trava_de "$A")" ] && falha 'F — a saída normal deixou trava residual' \
    || ok 'F — nenhuma trava residual depois da saída normal'
  igual 'F — o --status confirma o índice livre' \
    "$( cd "$A" && bash "$TRAVA" --status | sed -n 's/^estado=//p' )" livre

  # ---------------------------------------------------------------------------
  echo
  echo 'K, L, M. Sessão posterior, E1 tardio e a mesma task de novo'
  # ---------------------------------------------------------------------------
  printf 'muda\n' >> "$A/src/b.js"
  saida="$(fechar "$A" T-01.03 src/b.js 2>&1)"
  case "$saida" in *seq=2*) ok 'K — sessão posterior sem trava usa o próximo seq' ;;
    *) falha "K — esperava seq=2: $saida" ;; esac

  printf 'tardia\n' >> "$A/src/a.js"
  saida="$(fechar "$A" T-01.02 src/a.js 2>&1)"
  case "$saida" in *seq=3*) ok 'L — o E1 tardio passa pela mesma seção e recebe seq 3' ;;
    *) falha "L — esperava seq=3: $saida" ;; esac
  igual 'L — o tardio entrou no FIM, sem reordenar' \
    "$(itens_de "$A" | cut -f3 | tr '\n' ' ' | sed 's/ *$//')" 'T-01.01 T-01.03 T-01.02'

  printf 'denovo\n' >> "$A/src/a.js"
  saida="$(fechar "$A" T-01.01 src/a.js 2>&1)"
  case "$saida" in *seq=4*) ok 'M — a mesma task reaparece com seq global novo' ;;
    *) falha "M — esperava seq=4: $saida" ;; esac
  ( cd "$A" && bash "$SEQ" --validar "$ENTREGA" >/dev/null 2>&1 ) \
    && ok 'K/L/M — a lista continua válida: seq único e contínuo' \
    || falha 'K/L/M — a lista ficou inválida'

fi
if grupo B; then
  # ---------------------------------------------------------------------------
  echo
  echo 'B. Dois E1 simultâneos na MESMA worktree — um ganha, o outro PARA'
  # ---------------------------------------------------------------------------
  B="$D/b"; repo "$B"
  printf 'primeira\n' >> "$B/src/a.js"
  printf 'segunda\n'  >> "$B/src/b.js"
  ( fechar "$B" T-02.01 src/a.js --verificacao 'sleep 4' >"$D/b1.out" 2>&1; printf '%s\n' "$?" >"$D/b1.rc" ) &
  if espera_trava "$B"; then
    ok 'B — a primeira execução adquiriu a trava do índice'
  else
    falha 'B — a trava não apareceu; a corrida não foi observada'
  fi
  fechar "$B" T-02.02 src/b.js >"$D/b2.out" 2>&1; printf '%s\n' "$?" >"$D/b2.rc"
  wait

  igual 'B — a primeira concluiu com 0' "$(cat "$D/b1.rc")" 0
  igual 'B — a segunda PARA com o código de E1 ocupado' "$(cat "$D/b2.rc")" 2
  grep -q 'OCUPADO' "$D/b2.out" \
    && ok 'B — a segunda devolve condição determinística de E1 ocupado' \
    || falha "B — a segunda não relatou OCUPADO: $(cat "$D/b2.out")"
  igual 'B — exatamente um commit E1 no fim' "$(commits_de "$B")" 2
  igual 'B — exatamente um item novo em ENTREGA.commits' \
    "$(itens_de "$B" | wc -l | tr -d '[:space:]')" 1
  igual 'B — o item é o da execução que ganhou' "$(itens_de "$B" | cut -f3)" T-02.01
  igual 'B — seq único' "$(itens_de "$B" | cut -f2)" 1
  case "$( cd "$B" && git show --name-only --format= HEAD )" in
    *src/b.js*) falha 'B — a segunda conseguiu commitar o arquivo dela' ;;
    *) ok 'B — a segunda não commitou nada' ;;
  esac
  igual 'B — a segunda não deixou nada no índice' "$(stage_de "$B")" ''
  [ -d "$(trava_de "$B")" ] && falha 'B — sobrou trava no fim' || ok 'B — nenhuma trava sobrou'

fi
if grupo C; then
  # ---------------------------------------------------------------------------
  echo
  echo 'C, N. Duas worktrees — índices independentes, travas independentes'
  # ---------------------------------------------------------------------------
  C1="$D/c1"; C2="$D/c2"; repo "$C1"
  git -C "$C1" worktree add -q "$C2" -b outra >/dev/null 2>&1
  if [ -d "$C2" ]; then
    [ -f "$C2/.git" ] && ok 'N — na worktree vinculada, .git é ARQUIVO' \
      || falha 'N — .git da worktree vinculada não é arquivo'
    t1="$(trava_de "$C1")"; t2="$(trava_de "$C2")"
    [ "$t1" != "$t2" ] && ok 'C — cada worktree tem a trava do SEU índice' \
      || falha "C — as duas worktrees compartilham a trava: $t1"
    case "$t2" in *//worktrees/*|*/worktrees/*) ok 'N — a trava da vinculada fica no gitdir dela' ;;
      *) falha "N — trava da vinculada fora do gitdir: $t2" ;; esac
    # `--git-common-dir` sai relativo na worktree principal; o caminho da trava é
    # absoluto, então a comparação precisa dos dois na mesma forma.
    # A comparação é pela FORMA do caminho, não contra um caminho remontado à
    # mão: o versionador devolve `C:/...` e o `pwd` do shell devolve
    # `/cygdrive/c/...` para o mesmo diretório, e as duas strings nunca casam.
    # Cada trava é do ÍNDICE da sua worktree, e as duas são outra.
    case "$t1" in *"/index$SUFIXO") ok 'C — a trava da principal é do ÍNDICE dela' ;;
      *) falha "C — a trava da principal não é do índice: $t1" ;; esac
    case "$t2" in *"/index$SUFIXO") ok 'C — a trava da vinculada é do ÍNDICE dela' ;;
      *) falha "C — a trava da vinculada não é do índice: $t2" ;; esac

    printf 'na principal\n' >> "$C1/src/a.js"
    printf 'na vinculada\n' >> "$C2/src/a.js"
    ( fechar "$C1" T-03.01 src/a.js --verificacao 'sleep 3' >"$D/c1.out" 2>&1; printf '%s\n' "$?" >"$D/c1.rc" ) &
    espera_trava "$C1"
    fechar "$C2" T-03.02 src/a.js --verificacao 'sleep 1' >"$D/c2.out" 2>&1; printf '%s\n' "$?" >"$D/c2.rc"
    wait
    igual 'C — a worktree principal fechou' "$(cat "$D/c1.rc")" 0
    igual 'C — a worktree vinculada fechou AO MESMO TEMPO' "$(cat "$D/c2.rc")" 0
    igual 'C — cada uma registrou o seu item' \
      "$(itens_de "$C1" | cut -f3)/$(itens_de "$C2" | cut -f3)" 'T-03.01/T-03.02'
    [ -d "$t1" ] || [ -d "$t2" ] && falha 'C — sobrou trava numa das worktrees' \
      || ok 'C — as duas travas foram liberadas'
  else
    falha 'C — a worktree vinculada não pôde ser criada'
  fi

fi
if grupo D; then
  # ---------------------------------------------------------------------------
  echo
  echo 'D. Stage já preenchido na entrada — PARA e não toca no que encontrou'
  # ---------------------------------------------------------------------------
  Dm="$D/d"; repo "$Dm"
  printf 'de outro\n' >> "$Dm/src/b.js"
  ( cd "$Dm" && git add src/b.js )
  antes_nomes="$(stage_de "$Dm")"
  antes_diff="$( cd "$Dm" && git diff --cached )"
  antes_entrega="$(cat "$Dm/$ENTREGA")"
  printf 'desta task\n' >> "$Dm/src/a.js"
  saida="$(fechar "$Dm" T-04.01 src/a.js 2>&1)"; rc=$?
  igual 'D — o E1 PARA com o código de stage preexistente' "$rc" 3
  grep -q 'já tinha conteúdo em stage' <<<"$saida" \
    && ok 'D — o relatório diz o que aconteceu' || falha "D — relatório: $saida"
  grep -q 'src/b.js' <<<"$saida" \
    && ok 'D — o relatório mostra os caminhos staged' || falha 'D — o relatório não nomeia o staged'
  igual 'D — o stage ficou com exatamente os mesmos caminhos' "$(stage_de "$Dm")" "$antes_nomes"
  igual 'D — o conteúdo em stage ficou byte a byte igual' "$( cd "$Dm" && git diff --cached )" "$antes_diff"
  igual 'D — nenhum commit foi criado' "$(commits_de "$Dm")" 1
  igual 'D — a ENTREGA não foi tocada' "$(cat "$Dm/$ENTREGA")" "$antes_entrega"
  [ -d "$(trava_de "$Dm")" ] && falha 'D — a trava ficou presa' || ok 'D — a trava foi liberada'

fi
if grupo E; then
  # ---------------------------------------------------------------------------
  echo
  echo 'E. Trava preexistente — PARA, não espera, não remove'
  # ---------------------------------------------------------------------------
  Em="$D/e"; repo "$Em"
  te="$(trava_de "$Em")"; mkdir "$te"
  printf 'token=de-outra-execucao\ntask=T-99.99\npid=424242\ninstante=2026-09-20T00:00:00Z\n' > "$te/dono"
  dono_antes="$(cat "$te/dono")"
  printf 'muda\n' >> "$Em/src/a.js"
  saida="$(fechar "$Em" T-05.01 src/a.js 2>&1)"; rc=$?
  igual 'E — PARA com o código de E1 ocupado' "$rc" 2
  igual 'E — a trava alheia continua existindo' "$( [ -d "$te" ] && echo sim )" sim
  igual 'E — a trava alheia não foi reescrita' "$(cat "$te/dono")" "$dono_antes"
  grep -q 'T-99.99' <<<"$saida" && ok 'E — o relatório traz o diagnóstico de quem tem a trava' \
    || falha "E — sem diagnóstico do dono: $saida"
  igual 'E — nenhum commit foi criado' "$(commits_de "$Em")" 1
  igual 'E — nada foi para o índice' "$(stage_de "$Em")" ''
  ( cd "$Em" && bash "$TRAVA" --liberar token-errado >/dev/null 2>&1 )
  igual 'E — --liberar com token errado não remove a trava' "$( [ -d "$te" ] && echo sim )" sim
  ( cd "$Em" && bash "$TRAVA" --status >/dev/null 2>&1 )
  igual 'E — --status diagnostica sem remover (código 2)' "$( [ -d "$te" ] && echo sim )" sim
  ( cd "$Em" && bash "$TRAVA" --liberar de-outra-execucao >/dev/null 2>&1 ) \
    && ok 'E — o dono do token libera a própria trava' || falha 'E — o dono não conseguiu liberar'
  [ -d "$te" ] && falha 'E — a trava do próprio dono não saiu' || ok 'E — a trava saiu com o token certo'

fi
if grupo G; then
  # ---------------------------------------------------------------------------
  echo
  echo 'G. Verificação reprova antes do commit — nenhum commit, nada é limpo'
  # ---------------------------------------------------------------------------
  G="$D/g"; repo "$G"
  printf 'muda\n' >> "$G/src/a.js"
  antes_entrega="$(cat "$G/$ENTREGA")"
  saida="$(fechar "$G" T-06.01 src/a.js --verificacao 'exit 7' 2>&1)"; rc=$?
  igual 'G — PARA no código de verificação reprovada' "$rc" 4
  igual 'G — nenhum commit foi criado' "$(commits_de "$G")" 1
  igual 'G — a ENTREGA não foi tocada' "$(cat "$G/$ENTREGA")" "$antes_entrega"
  igual 'G — o stage montado ficou para diagnóstico (sem limpeza destrutiva)' \
    "$(stage_de "$G" | tr '\n' ' ' | sed 's/ *$//')" 'src/a.js'
  [ -d "$(trava_de "$G")" ] && falha 'G — a trava ficou presa' || ok 'G — a trava foi liberada'
  # O produto não foi resetado: a alteração continua na árvore.
  grep -q muda "$G/src/a.js" && ok 'G — o produto não foi revertido' || falha 'G — o produto foi mexido'

fi
if grupo H; then
  # ---------------------------------------------------------------------------
  echo
  echo 'H. git commit falha — nenhum registro E1 falso'
  # ---------------------------------------------------------------------------
  H="$D/h"; repo "$H"
  # A recusa do versionador é provocada pela assinatura, não por um hook: o bit
  # de execução de um `pre-commit` não se comporta igual nos três sistemas
  # suportados, e um hook que não roda faria este caso passar sem provar nada.
  ( cd "$H" \
    && git config commit.gpgsign true \
    && git config user.signingkey chave-que-nao-existe \
    && git config gpg.program "$D/programa-de-assinatura-inexistente" )
  printf 'muda\n' >> "$H/src/a.js"
  antes_entrega="$(cat "$H/$ENTREGA")"
  saida="$(fechar "$H" T-07.01 src/a.js 2>&1)"; rc=$?
  igual 'H — PARA no código de commit recusado' "$rc" 5
  igual 'H — nenhum commit foi criado' "$(commits_de "$H")" 1
  igual 'H — nenhum registro E1 foi escrito' "$(cat "$H/$ENTREGA")" "$antes_entrega"
  grep -q 'no-verify' <<<"$saida" && ok 'H — o relatório proíbe contornar o hook' \
    || falha 'H — o relatório não diz que --no-verify é proibido'
  [ -d "$(trava_de "$H")" ] && falha 'H — a trava ficou presa' || ok 'H — a trava foi liberada'

fi
if grupo I; then
  # ---------------------------------------------------------------------------
  echo
  echo 'I. O commit aconteceu e o append falhou — PARA, sem segundo commit'
  # ---------------------------------------------------------------------------
  # O escritor da lista é substituído por um duble que RECUSA gravar. A cópia dos
  # scripts é o que permite provar o desfecho sem depender de permissão de
  # arquivo, que não se comporta igual nos três sistemas suportados.
  duble() { # <dir do duble> <corpo>
    mkdir -p "$1"
    cp "$SCRIPTS/trava-do-e1.sh" "$SCRIPTS/fechamento-do-e1.sh" "$1/"
    printf '%s\n' "$2" > "$1/sequencia-de-commits.sh"
  }
  I="$D/i"; repo "$I"
  SI="$D/scripts-i"
  duble "$SI" '#!/usr/bin/env bash
  case "$1" in
    --validar) printf "commits=0\n"; exit 0 ;;
    --acrescentar) printf "sequencia-de-commits: disco cheio\n" >&2; exit 1 ;;
  esac
  exit 64'
  printf 'muda\n' >> "$I/src/a.js"
  mensagem "$D/msg-i.txt" T-08.01
  antes_entrega="$(cat "$I/$ENTREGA")"
  saida="$( cd "$I" && bash "$SI/fechamento-do-e1.sh" --fechar --entrega "$ENTREGA" \
    --task T-08.01 --mensagem "$D/msg-i.txt" -- src/a.js 2>&1 )"; rc=$?
  igual 'I — PARA no código de commit sem registro' "$rc" 6
  grep -q 'commit Git existe; registro E1 não foi concluído' <<<"$saida" \
    && ok 'I — o relatório diz exatamente o que aconteceu' || falha "I — relatório: $saida"
  igual 'I — o commit foi preservado' "$(commits_de "$I")" 2
  igual 'I — NENHUM segundo commit automático' \
    "$( cd "$I" && git log --format=%s -2 | tr '\n' ' ' | sed 's/ *$//')" \
    'feat(src): fecha T-08.01 chore: base'
  igual 'I — a ENTREGA continua sem o item' "$(cat "$I/$ENTREGA")" "$antes_entrega"
  tasks_concluidas "$D/tasks-i.md" T-08.01
  igual 'I — a V11 detecta a task concluída sem prova de E1' \
    "$(bash "$PROVA" --verificar "$I/$ENTREGA" "$D/tasks-i.md" 2>&1 | head -1)" 'V11=FALHA'
  [ -d "$(trava_de "$I")" ] && falha 'I — a trava ficou presa' || ok 'I — a trava foi liberada'

fi
if grupo J; then
  # ---------------------------------------------------------------------------
  echo
  echo 'J. O append produz lista inválida — a validação barra, nada é renumerado'
  # ---------------------------------------------------------------------------
  J="$D/j"; repo "$J"
  SJ="$D/scripts-j"
  duble "$SJ" '#!/usr/bin/env bash
  estado="$(dirname "$0")/chamadas"
  n="$(cat "$estado" 2>/dev/null || printf 0)"
  case "$1" in
    --validar)
      n=$((n + 1)); printf "%s\n" "$n" > "$estado"
      if [ "$n" -ge 2 ]; then printf "sequencia-de-commits: seq duplicado: 1\n" >&2; exit 1; fi
      printf "commits=0\n"; exit 0 ;;
    --acrescentar)
      printf "DUBLE-ITEM task=%s commit=%s\n" "$3" "$4" >> "$2"
      printf "seq=1\n"; exit 0 ;;
  esac
  exit 64'
  printf 'muda\n' >> "$J/src/a.js"
  mensagem "$D/msg-j.txt" T-09.01
  saida="$( cd "$J" && bash "$SJ/fechamento-do-e1.sh" --fechar --entrega "$ENTREGA" \
    --task T-09.01 --mensagem "$D/msg-j.txt" -- src/a.js 2>&1 )"; rc=$?
  igual 'J — PARA no código de lista inválida depois do registro' "$rc" 7
  grep -q 'Nada foi renumerado' <<<"$saida" \
    && ok 'J — o relatório afirma que nada foi renumerado' || falha "J — relatório: $saida"
  igual 'J — o item escrito pelo duble ficou exatamente como saiu dele' \
    "$(grep -c 'DUBLE-ITEM task=T-09.01' "$J/$ENTREGA")" 1
  igual 'J — nenhum segundo item foi acrescentado' "$(grep -c 'DUBLE-ITEM' "$J/$ENTREGA")" 1
  igual 'J — nenhum segundo commit' "$(commits_de "$J")" 2
  [ -d "$(trava_de "$J")" ] && falha 'J — a trava ficou presa' || ok 'J — a trava foi liberada'

fi
if grupo ESPIAO; then
  # ---------------------------------------------------------------------------
  echo
  echo 'A seção crítica cobre o append e a validação final (espião)'
  # ---------------------------------------------------------------------------
  # Um espião no lugar do escritor da lista: ele anota se a trava estava ADQUIRIDA
  # no instante de cada chamada e delega para o escritor de verdade. É assim que
  # se prova que `seq` é atribuído DENTRO da seção — sem isso, "a trava cobre o
  # append" seria afirmação de prosa.
  Sp="$D/s"; repo "$Sp"
  SSp="$D/scripts-s"; REGISTRO="$D/espiao.txt"; : > "$REGISTRO"
  mkdir -p "$SSp"
  cp "$SCRIPTS/trava-do-e1.sh" "$SCRIPTS/fechamento-do-e1.sh" "$SSp/"
  {
    printf '#!/usr/bin/env bash\n'
    printf 't="$(git rev-parse --git-path index)%s"\n' "$SUFIXO"
    printf 'if [ -d "$t" ]; then e=COM_TRAVA; else e=SEM_TRAVA; fi\n'
    printf 'printf "%%s %%s\\n" "$e" "$1" >> %s\n' "'$REGISTRO'"
    printf 'exec bash %s "$@"\n' "'$SEQ'"
  } > "$SSp/sequencia-de-commits.sh"
  printf 'muda\n' >> "$Sp/src/a.js"
  mensagem "$D/msg-s.txt" T-12.01
  ( cd "$Sp" && bash "$SSp/fechamento-do-e1.sh" --fechar --entrega "$ENTREGA" \
      --task T-12.01 --mensagem "$D/msg-s.txt" -- src/a.js >/dev/null 2>&1 )
  igual 'o espião foi acionado' "$( [ -s "$REGISTRO" ] && echo sim || echo nao )" sim
  igual 'o append em ENTREGA.commits roda sob a trava' \
    "$(grep -c '^COM_TRAVA --acrescentar' "$REGISTRO")" 1
  igual 'a validação da lista roda sob a trava, antes e depois do append' \
    "$(grep -c '^COM_TRAVA --validar' "$REGISTRO")" 2
  igual 'nenhuma chamada do escritor caiu fora da seção crítica' \
    "$(grep -c '^SEM_TRAVA' "$REGISTRO")" 0

fi
if grupo EXTRA; then
  # ---------------------------------------------------------------------------
  echo
  echo 'A leitura da lista nunca exige a trava'
  # ---------------------------------------------------------------------------
  L="$D/l"; repo "$L"
  tl="$(trava_de "$L")"; mkdir "$tl"; printf 'token=x\ntask=T-00\n' > "$tl/dono"
  n=0
  ( cd "$L" && bash "$SEQ" --ler "$ENTREGA" >/dev/null 2>&1 )     || n=1
  ( cd "$L" && bash "$SEQ" --validar "$ENTREGA" >/dev/null 2>&1 ) || n=1
  ( cd "$L" && bash "$SEQ" --proximo "$ENTREGA" >/dev/null 2>&1 ) || n=1
  igual '--ler, --validar e --proximo funcionam com a trava ocupada' "$n" 0
  rm -rf "$tl"

  # ---------------------------------------------------------------------------
  echo
  echo 'O staging é por caminho explícito: em bloco nem chega ao versionador'
  # ---------------------------------------------------------------------------
  Bl="$D/bloco"; repo "$Bl"
  printf 'muda\n' >> "$Bl/src/a.js"
  for arg in . -A -u; do
    mensagem "$D/msg-bloco.txt" T-10.01
    ( cd "$Bl" && bash "$FECHA" --fechar --entrega "$ENTREGA" --task T-10.01 \
        --mensagem "$D/msg-bloco.txt" -- "$arg" >/dev/null 2>&1 )
    rc=$?
    igual "staging em bloco com '$arg' é recusado" "$rc" 64
  done
  igual 'nenhum commit saiu do staging em bloco' "$(commits_de "$Bl")" 1
  [ -d "$(trava_de "$Bl")" ] && falha 'a recusa de bloco deixou trava' || ok 'a recusa de bloco não trava nada'

  # ---------------------------------------------------------------------------
  echo
  echo 'Modo do agente: a trava atravessa --preparar e --concluir'
  # ---------------------------------------------------------------------------
  P="$D/p"; repo "$P"
  printf 'muda\n' >> "$P/src/a.js"
  mensagem "$D/msg-p.txt" T-11.01
  saida="$( cd "$P" && bash "$FECHA" --preparar --task T-11.01 -- src/a.js 2>&1 )"
  rc=$?
  token="$(printf '%s\n' "$saida" | sed -n 's/^token=//p')"
  igual '--preparar conclui com 0' "$rc" 0
  [ -n "$token" ] && ok '--preparar imprime o token da seção' || falha '--preparar não imprimiu token'
  [ -d "$(trava_de "$P")" ] && ok 'a trava CONTINUA adquirida depois do --preparar' \
    || falha 'o --preparar liberou a trava'
  igual '--preparar deixou o diff em stage para a varredura de segredo' \
    "$(stage_de "$P" | tr '\n' ' ' | sed 's/ *$//')" 'src/a.js'
  # Enquanto a seção está aberta, outro E1 não entra.
  printf 'outra\n' >> "$P/src/b.js"
  fechar "$P" T-11.02 src/b.js >/dev/null 2>&1
  igual 'outro E1 não entra enquanto a seção preparada está aberta' "$?" 2
  # Token errado não conclui a seção de ninguém.
  ( cd "$P" && bash "$FECHA" --concluir --entrega "$ENTREGA" --task T-11.01 \
      --mensagem "$D/msg-p.txt" --token nao-e-o-token >/dev/null 2>&1 )
  igual '--concluir com token errado PARA' "$?" 2
  igual '--concluir com token errado não commitou' "$(commits_de "$P")" 1
  [ -d "$(trava_de "$P")" ] && ok '--concluir com token errado não removeu a trava alheia' \
    || falha 'a trava foi removida por quem não é dono'
  saida="$( cd "$P" && bash "$FECHA" --concluir --entrega "$ENTREGA" --task T-11.01 \
      --mensagem "$D/msg-p.txt" --token "$token" 2>&1 )"
  igual '--concluir com o token certo fecha a seção' "$?" 0
  case "$saida" in *seq=1*) ok '--concluir atribui o seq dentro da seção' ;;
    *) falha "--concluir não imprimiu seq: $saida" ;; esac
  igual '--concluir liberou a trava' "$( [ -d "$(trava_de "$P")" ] && echo sim || echo nao )" nao
fi

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), 0 pulado(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = "0" ]
