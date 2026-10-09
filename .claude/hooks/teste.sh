#!/usr/bin/env bash
# Testes dos hooks da mergex.
#
# Cada caso declara o que TEM que barrar e o que TEM que passar. Os casos de
# "tem que passar" são os mais importantes: hook que dá falso positivo é
# desinstalado, e junto com ele vão os que funcionavam.
#
# Uso: ./hooks/teste.sh

set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$H/../.." && pwd)"
# shellcheck source=scripts/ci/lib/fixture-git.sh
. "$REPO_ROOT/scripts/ci/lib/fixture-git.sh" || exit 1
OK=0; FALHOU=0; PULADOS=0; NAOEXEC=0
# Caso que depende de um ambiente ausente (Git for Windows sobre
# \\wsl.localhost): NAO_EXECUTADO, listado a parte, nunca conta como ok.
nao_executado() { NAOEXEC=$((NAOEXEC+1)); printf '  NAO_EXECUTADO: %s\n' "$1"; }

# Os hooks leem o evento do harness com jq. Sem jq, todo hook sai cedo e por
# 0 — o que faria a suite reportar "passou" onde nao verificou nada. Entao os
# casos que dependem de jq sao PULADOS, e ficam visiveis como tal.
# Em CI isso nunca vale: la a ausencia de jq e falha de ambiente, e a suite
# inteira precisa rodar (o workflow instala jq antes).
SEM_JQ=0
if ! command -v jq >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    printf 'jq ausente no ambiente de CI: os hooks dependem dele. Abortando.\n' >&2
    exit 1
  fi
  SEM_JQ=1
  printf 'AVISO: jq ausente nesta maquina. Casos que dependem de jq serao PULADOS.\n'
  printf '       Rode em Linux/CI (ou em container) para cobri-los.\n\n'
fi

RAIZ_T="$(mktemp -d)"
WT_T="${RAIZ_T}--wt"        # worktree derivado: .git e ARQUIVO, nao diretorio
SEMGIT_T="$(mktemp -d)"
HIST_T="$(mktemp -d)"
WTH_T="${HIST_T}--wt"       # worktree vinculada do repositorio historico
WTM_T="${HIST_T}--main"     # worktree da main do repositorio historico
WTB_T="${HIST_T}--base"     # worktree sem docs/entregas no HEAD
WTX_T="${HIST_T}--outra"    # worktree com o HEAD noutra branch
SEMX_T="$(mktemp -d)"       # repositorio sem MergeX
trap 'rm -rf "$RAIZ_T" "$WT_T" "$SEMGIT_T" "$HIST_T" "$WTH_T" "$WTM_T" "$WTB_T" "$WTX_T" "$SEMX_T"' EXIT
HOOK_CWD="$RAIZ_T"

cd "$RAIZ_T" || exit 1
git init -q -b main . 2>/dev/null
git config user.email teste@expx.local
git config user.name Teste
mkdir -p docs/sprintx/features/trab/sprint-01 docs/entregas/trab
echo conteudo > arquivo.txt
git add arquivo.txt && git commit -qm inicial

cat > docs/sprintx/features/trab/sprint-01/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: trab
tasks:
  - id: T-01.01
    titulo: Primeira task
    status: concluida
    arquivos:
      cria: [src/a.ts]
      altera: []
    suite: verde
  - id: T-01.02
    titulo: Segunda task
    status: em_andamento
    arquivos:
      cria: [src/b.ts]
      altera: []
    suite: vermelha
---
YAML
cat > docs/entregas/trab/ENTREGA.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: trab
entregue_por: mergex
branch: main
branch_base: main
---
YAML
mkdir -p src && touch src/a.ts src/b.ts

# A árvore precisa nascer limpa: o branch-limpa conta arquivo apenas não
# rastreado como pendência (DM-26), e com razão — pode ser trabalho de alguém.
git add -A && git commit -qm "plano e fontes"

# caso <descricao> <script> <ferramenta-json> <exit esperado>
caso() {
  local desc="$1" script="$2" json="$3" esperado="$4"
  local obtido
  if [ "$SEM_JQ" = "1" ]; then
    PULADOS=$((PULADOS+1)); printf '  pulado %s (sem jq)\n' "$desc"; return 0
  fi
  printf '%s' "$json" | bash "$H/$script" >/dev/null 2>&1
  obtido=$?
  if [ "$obtido" = "$esperado" ]; then
    OK=$((OK+1)); printf '  ok    %s\n' "$desc"
  else
    FALHOU=$((FALHOU+1)); printf '  FALHA %s (esperava %s, obteve %s)\n' "$desc" "$esperado" "$obtido"
  fi
}

# fm_chave <arquivo> <chave> <valor> — grava a chave no frontmatter do arquivo
# no disco (troca a linha existente ou acrescenta antes do `---` que fecha).
# fm_sem_chave <arquivo> <chave> — tira a chave do frontmatter.
fm_chave() {
  awk -v k="$2" -v v="$3" '
    NR == 1 { print; fm = 1; next }
    fm && /^---/ { if (!feito) print k ": " v; fm = 0; print; next }
    fm && index($0, k ":") == 1 { print k ": " v; feito = 1; next }
    { print }' "$1" > "$1.fm" && cat "$1.fm" > "$1" && rm -f "$1.fm"
}
fm_sem_chave() {
  awk -v k="$2" '
    NR == 1 { print; fm = 1; next }
    fm && /^---/ { fm = 0; print; next }
    fm && index($0, k ":") == 1 { next }
    { print }' "$1" > "$1.fm" && cat "$1.fm" > "$1" && rm -f "$1.fm"
}

bash_json() { jq -cn --arg c "$1" --arg w "$HOOK_CWD" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}'; }
write_json() { jq -cn --arg c "$1" --arg w "$HOOK_CWD" '{tool_name:"Write",cwd:$w,tool_input:{content:$c}}'; }

echo
echo "sem-segredo — tem que BARRAR"
# As amostras abaixo são montadas em pedaços, de propósito: escritas inteiras
# no arquivo, elas fariam o próprio sem-segredo barrar o commit deste teste —
# o que é o hook funcionando, mas deixaria a suíte impossível de versionar.
# Nenhum valor aqui é real; todos são sintéticos e montados em tempo de teste.
SK="sk-$(printf 'abcdef1234567890QRS')"
PK="$(printf -- '-----BEGIN RSA %s KEY-----' 'PRIVATE')"
SENHA="$(printf 'password = %sTr0ub4dorZ3x%s' "'" "'")"
CPF="$(printf 'cliente 123.%s-01' '456.789')"
URL="$(printf 'postgres://u:%s@db/x' 's3nh4sintetica')"

caso "chave sk-"          comum/sem-segredo.sh "$(write_json "const k=\"$SK\"")" 2
caso "chave privada"      comum/sem-segredo.sh "$(write_json "$PK")" 2
caso "senha atribuida"    comum/sem-segredo.sh "$(write_json "$SENHA")" 2
caso "CPF sintetico"      comum/sem-segredo.sh "$(write_json "$CPF")" 2
caso "URL com credencial" comum/sem-segredo.sh "$(write_json "$URL")" 2
echo "sem-segredo — tem que PASSAR"
caso "variavel de ambiente" comum/sem-segredo.sh "$(write_json 'const k = process.env.API_KEY')" 0
caso "placeholder <>"       comum/sem-segredo.sh "$(write_json 'password: <coloque-a-senha>')" 0
caso "marcador de template" comum/sem-segredo.sh "$(write_json 'token: {{seu_token}}')" 0
caso "variavel de shell"    comum/sem-segredo.sh "$(write_json 'SECRET=${MINHA_VAR}')" 0
caso "prosa sobre senha"    comum/sem-segredo.sh "$(write_json 'O campo senha e validado no login')" 0
caso "comando comum"        comum/sem-segredo.sh "$(bash_json 'npm test')" 0

echo
echo "git-perigoso — tem que BARRAR"
caso "push --force"           mergex/git-perigoso.sh "$(bash_json 'git push --force origin main')" 2
caso "push -f"                mergex/git-perigoso.sh "$(bash_json 'git push -f')" 2
caso "push --force-with-lease" mergex/git-perigoso.sh "$(bash_json 'git push --force-with-lease')" 2
caso "push +refspec"          mergex/git-perigoso.sh "$(bash_json 'git push origin +feat:main')" 2
caso "commit na principal"    mergex/git-perigoso.sh "$(bash_json "git commit -m x")" 2
caso "clean -fd"              mergex/git-perigoso.sh "$(bash_json 'git clean -fd')" 2
echo "git-perigoso — tem que PASSAR (falsos positivos)"
caso "git status"             mergex/git-perigoso.sh "$(bash_json 'git status')" 0
caso "git log"                mergex/git-perigoso.sh "$(bash_json 'git log --oneline')" 0
caso "npm run push-notifications" mergex/git-perigoso.sh "$(bash_json 'npm run push-notifications')" 0
caso "echo sobre push --force"    mergex/git-perigoso.sh "$(bash_json "echo 'nao faca push --force'")" 0
caso "grep por push"          mergex/git-perigoso.sh "$(bash_json 'grep -r push src/')" 0
caso "git clean -n (seco)"    mergex/git-perigoso.sh "$(bash_json 'git clean -n')" 0
caso "git fetch"              mergex/git-perigoso.sh "$(bash_json 'git fetch origin')" 0
# O valor de -o (e de aglomerado terminado em o) nao e o remoto.
caso "push -o main origin feature"  mergex/git-perigoso.sh "$(bash_json 'git push -o main origin feature')" 0
caso "push -uo main origin feature" mergex/git-perigoso.sh "$(bash_json 'git push -uo main origin feature')" 0
# Prefixo de ambiente qualquer (nao so GIT_*) continua sendo push.
caso "FOO=1 git push origin main"   mergex/git-perigoso.sh "$(bash_json 'FOO=1 git push origin main')" 2
# Desfazer o stage NAO toca a arvore e nao destroi nada: barrar isso seria o
# falso positivo que atrapalha o dia inteiro. Regressao de um caso real.
caso "restore --staged (so o stage)" mergex/git-perigoso.sh "$(bash_json 'git restore --staged f.txt')" 0
caso "checkout de branch"            mergex/git-perigoso.sh "$(bash_json 'git checkout outra-branch')" 0

echo
echo "branch-limpa"
caso "troca com arvore limpa"  comum/branch-limpa.sh "$(bash_json 'git switch outra')" 0
echo modificado >> arquivo.txt
caso "troca com arvore suja"   comum/branch-limpa.sh "$(bash_json 'git switch outra')" 2
# Descarte so e perigoso quando ha o que perder: aqui a arvore esta suja.
caso "restore sem flag"   mergex/git-perigoso.sh "$(bash_json 'git restore arquivo.txt')" 2
caso "restore --worktree" mergex/git-perigoso.sh "$(bash_json 'git restore --worktree arquivo.txt')" 2
caso "switch -c com suja"      comum/branch-limpa.sh "$(bash_json 'git switch -c nova')" 2
caso "checkout -- nao e troca" comum/branch-limpa.sh "$(bash_json 'git checkout -- arquivo.txt')" 0
caso "npm run switch"          comum/branch-limpa.sh "$(bash_json 'npm run switch')" 0
git checkout -q -- arquivo.txt

echo
echo "commit-por-task (modo aviso: nunca barra, so avisa)"
echo "mudanca a" >> src/a.ts; echo "mudanca b" >> src/b.ts
git add src/a.ts
caso "uma task concluida/verde" mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
git add src/b.ts
caso "duas tasks misturadas"    mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
echo "commit-por-task (modo bloqueio)"
mkdir -p .expx
# Formato do ecossistema: hooks.<nome>.modo
echo '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"bloqueio"}}}' > .expx/hooks.json
caso "duas tasks, em bloqueio"  mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 2
echo '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"desligado"}}}' > .expx/hooks.json
caso "desligado nao age"        mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
# Forma antiga, aceita para não quebrar arquivo já escrito à mão
echo '{"expx_hooks":1,"modos":{"commit-por-task":"bloqueio"}}' > .expx/hooks.json
caso "forma antiga (.modos)"    mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 2
# Arquivo ausente: valem os padrões; segurança nunca é rebaixada
rm -f .expx/hooks.json
caso "sem arquivo: metodo em aviso" mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
rm -f .expx/hooks.json

echo
echo "commit-por-task — arquivo de task irma (a quarta situacao do E1)"
# Duas tasks CONCLUIDAS, para que o que esta em jogo seja so o ownership: nem
# status, nem suite, nem mistura acidental de trabalho inacabado.
git reset -q
mkdir -p docs/sprintx/features/trab/sprint-07
cat > docs/sprintx/features/trab/sprint-07/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: trab
tasks:
  - id: T-07.01
    titulo: A task que esta fechando agora
    status: concluida
    arquivos:
      cria: [src/atual.ts]
      altera: []
    suite: verde
  - id: T-07.02
    titulo: A task irma, ja fechada antes
    status: concluida
    arquivos:
      cria: [src/irma.ts]
      altera: []
    suite: verde
---
YAML
echo "atual" > src/atual.ts; echo "irma" > src/irma.ts
git add -A && git commit -qm "plano com duas tasks concluidas"
echo "mudanca" >> src/atual.ts; echo "mudanca" >> src/irma.ts

# O rodape `Task:` e o que declara qual task esta fechando. O contrato do E1
# ja o exige em toda mensagem de commit de task.
MSG_ATUAL='git commit -m "feat(ui): a task atual

Task: T-07.01
Trabalho: trab"'

git add src/atual.ts
caso "so o arquivo da task atual"        mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 0
git add src/irma.ts
caso "atual + irma: falha fechada"       mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 2
git reset -q && git add src/irma.ts
caso "so o arquivo da irma: falha fechada" mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 2

# O ponto do C1: esta condicao falha FECHADA mesmo com o hook em aviso, que e
# o modo padrao. Deixa-la passar produziria o commit parcial enganoso da task.
mkdir -p .expx
echo '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"aviso"}}}' > .expx/hooks.json
caso "em aviso, ainda barra"             mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 2
# `desligado` continua desligando o hook inteiro: e a valvula de escape do time.
echo '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"desligado"}}}' > .expx/hooks.json
caso "desligado desliga tambem esta"     mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 0
rm -f .expx/hooks.json

# A mensagem tambem chega por arquivo (`git commit -F`), que e como o E1 a
# escreve para preservar as quebras de linha do corpo.
printf 'feat(ui): a task atual\n\nTask: T-07.01\nTrabalho: trab\n' > .git/MENSAGEM
caso "mensagem por -F"                   mergex/commit-por-task.sh "$(bash_json 'git commit -F .git/MENSAGEM')" 2
rm -f .git/MENSAGEM

# Commit de método é uma classe própria: Trabalho + Metodo, sem Task. A
# gramática das três chaves de controle falha fechada mesmo com o hook em aviso.
git reset -q
mkdir -p docs/entregas/trab
printf 'metodo\n' > docs/entregas/trab/PR.md
git add docs/entregas/trab/PR.md
MSG_METODO='git commit -m "chore(mergex): persiste metodo pre-e2

Trabalho: trab
Metodo: pre-e2"'
caso "metodo valido nao e E1 invalido" mergex/commit-por-task.sh "$(bash_json "$MSG_METODO")" 0
caso "Task + Metodo e classe hibrida" mergex/commit-por-task.sh \
  "$(bash_json 'git commit -m "x

Task: T-07.01
Trabalho: trab
Metodo: pre-e2"')" 2
caso "Metodo duplicado e invalido" mergex/commit-por-task.sh \
  "$(bash_json 'git commit -m "x

Trabalho: trab
Metodo: pre-e2
Metodo: pre-e2"')" 2
caso "Trabalho duplicado em metodo e invalido" mergex/commit-por-task.sh \
  "$(bash_json 'git commit -m "x

Trabalho: trab
Trabalho: trab
Metodo: pre-e2"')" 2
caso "Metodo fora do enum e invalido" mergex/commit-por-task.sh \
  "$(bash_json 'git commit -m "x

Trabalho: trab
Metodo: outro"')" 2
git reset -q
rm -f docs/entregas/trab/PR.md
git add src/irma.ts

# Sem dono declarado, nada e inferido: vale o comportamento de sempre (aviso).
caso "sem rodape Task: nao infere dono"  mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
caso "dois rodapes Task: e invalido"      mergex/commit-por-task.sh \
  "$(bash_json 'git commit -m "x

Task: T-07.01
Task: T-07.02
Trabalho: trab"')" 2

# V9 nao muda: ela pergunta se o arquivo foi planejado NA FEATURE, pela uniao.
caso "V9 (uniao) aceita o arquivo da irma" mergex/arquivo-fora-do-plano.sh "$(bash_json "$MSG_ATUAL")" 0

# Replanejado: a task atual passa a declarar o arquivo, e o fechamento segue.
sed -i.bak 's#cria: \[src/atual.ts\]#cria: [src/atual.ts, src/irma.ts]#' docs/sprintx/features/trab/sprint-07/tasks.md
rm -f docs/sprintx/features/trab/sprint-07/tasks.md.bak
caso "replanejado: a atual declara, e passa" mergex/commit-por-task.sh "$(bash_json "$MSG_ATUAL")" 0

git reset -q
git checkout -q -- src/atual.ts src/irma.ts docs/sprintx/features/trab/sprint-07/tasks.md 2>/dev/null
rm -rf docs/sprintx/features/trab/sprint-07 src/atual.ts src/irma.ts
git add -A && git commit -qm "limpa o cenario da task irma"

echo
echo "arquivo-fora-do-plano"
git reset -q && git add src/a.ts
caso "arquivo declarado"        mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
mkdir -p src/fora && echo x > src/fora/surpresa.ts && git add -f src/fora/surpresa.ts
caso "arquivo nao declarado (aviso)" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
git reset -q

echo
echo "pr-so-com-portao"
# Os casos de portão `pronto` moram no repositório histórico (mais abaixo, em
# "pr-so-com-portao — validade"): lá o portão é montado com portao_sha e
# commits de método de verdade. Aqui a branch `main` casa com a entrega
# `trab`, que não registrou portão. O trabalho sai da branch EMPURRADA e o
# portão do ENTREGA.md commitado na revisão empurrada — nunca do disco.
fm_chave docs/entregas/trab/ENTREGA.md portao null
git add docs/entregas/trab/ENTREGA.md && git commit -qm "registra portao null"
caso "portao null, modo aviso: nao barra" mergex/pr-so-com-portao.sh "$(bash_json 'git push -u origin main')" 0
# Uma ENTREGA sem frontmatter (sem `branch:`), não rastreada, não é o trabalho.
mkdir -p docs/entregas/t1
printf 'portao: pronto\n' > docs/entregas/t1/ENTREGA.md
caso "ENTREGA sem branch: nao decide"   mergex/pr-so-com-portao.sh "$(bash_json 'git push -u origin main')" 0
rm -rf docs/entregas/t1
fm_chave docs/entregas/trab/ENTREGA.md portao bloqueado
git add docs/entregas/trab/ENTREGA.md && git commit -qm "registra portao bloqueado"
echo '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"bloqueio"}}}' > .expx/hooks.json
caso "portao bloqueado barra"   mergex/pr-so-com-portao.sh "$(bash_json 'git push -u origin main')" 2
caso "build nao e push"         mergex/pr-so-com-portao.sh "$(bash_json 'npm run build')" 0
rm -f .expx/hooks.json

echo
echo "expx_raiz — raiz do repositorio, inclusive em worktree"
# A raiz ancora docs/entregas/ e docs/eventos/. Num `git worktree`, `.git` e
# ARQUIVO ("gitdir: ..."), nao diretorio: uma busca por [ -d ] sobe demais e
# devolve a raiz errada — o mesmo achado que a sprintx registrou na DS-106.
# shellcheck source=comum/base.sh
. "$H/comum/base.sh"
git -C "$RAIZ_T" worktree add -q -b wt-teste "$WT_T" main >/dev/null 2>&1
mkdir -p "$WT_T/sub" "$RAIZ_T/src/sub"

# Normaliza os dois lados: em Git Bash, `git rev-parse --show-toplevel` devolve
# caminho no estilo do sistema, e a comparacao crua daria falso negativo.
norm() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }
valor() {
  local desc="$1" obtido="$2" esperado="$3"
  if [ "$obtido" = "$esperado" ]; then
    OK=$((OK+1)); printf '  ok    %s\n' "$desc"
  else
    FALHOU=$((FALHOU+1)); printf '  FALHA %s (esperava %s, obteve %s)\n' "$desc" "$esperado" "$obtido"
  fi
}

valor "checkout normal"            "$(norm "$(expx_raiz "$RAIZ_T")")"         "$(norm "$RAIZ_T")"
valor "subdiretorio do checkout"   "$(norm "$(expx_raiz "$RAIZ_T/src/sub")")" "$(norm "$RAIZ_T")"
valor "worktree (.git arquivo)"    "$(norm "$(expx_raiz "$WT_T")")"           "$(norm "$WT_T")"
valor "subdiretorio do worktree"   "$(norm "$(expx_raiz "$WT_T/sub")")"       "$(norm "$WT_T")"
valor "fora de repositorio"        "$(norm "$(expx_raiz "$SEMGIT_T")")"       "$(norm "$SEMGIT_T")"

echo
echo "semantica de suite por task (sprintx: parcial na task, inteira ao fechar a sprint)"
mkdir -p docs/sprintx/features/exportacao-csv/sprint-01 docs/entregas/exportacao-csv
cat > docs/sprintx/features/exportacao-csv/sprint-01/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: exportacao-csv
tasks:
  - id: T-02.01
    titulo: Task fechada com o subconjunto afetado
    status: concluida
    arquivos:
      cria: [src/p.ts]
      altera: []
    suite: parcial
  - id: T-02.02
    titulo: Task fechada com suite vermelha
    status: concluida
    arquivos:
      cria: [src/v.ts]
      altera: []
    suite: vermelha
  - id: T-02.03
    titulo: Task fechada sem rodar teste
    status: concluida
    arquivos:
      cria: [src/n.ts]
      altera: []
    suite: nao_executada
---
YAML
# A branch ativa casa com exatamente uma ENTREGA: recência não escolhe trabalho.
rm -f docs/entregas/trab/ENTREGA.md
cat > docs/entregas/exportacao-csv/ENTREGA.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: exportacao-csv
entregue_por: mergex
branch: main
branch_base: main
portao: null
---
YAML
touch src/p.ts src/v.ts src/n.ts
git add -A >/dev/null 2>&1 && git commit -qm "plano da segunda feature"

mkdir -p .expx
echo '{"expx_hooks":1,"hooks":{"commit-por-task":{"modo":"bloqueio"},"arquivo-fora-do-plano":{"modo":"bloqueio"}}}' > .expx/hooks.json

git reset -q; echo p >> src/p.ts; git add src/p.ts
caso "suite parcial e registro valido" mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 0
git reset -q; echo v >> src/v.ts; git add src/v.ts
caso "suite vermelha barra"            mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 2
git reset -q; echo n >> src/n.ts; git add src/n.ts
caso "suite nao_executada barra"       mergex/commit-por-task.sh "$(bash_json 'git commit -m x')" 2

echo
echo "artefato de metodo: o trabalho corrente sai da BRANCH, nunca da recencia"
# Este bloco historico usa repositorio proprio: nenhuma sujeira produzida pelos
# casos anteriores pode influenciar selecao de trabalho, E8 ou HISTORICO.
cd "$HIST_T" || exit 1
HOOK_CWD="$HIST_T"
git init -q -b main . 2>/dev/null || exit 1
git config user.email teste@expx.local
git config user.name Teste
mkdir -p docs/sprintx/features/ft-01 docs/sprintx/features/ft-02/sprint-01 docs/ft-legado src/fora
printf 'b\n' > docs/sprintx/features/ft-01/00-BLOQUEIOS.md
printf 'b\n' > docs/sprintx/features/ft-02/00-BLOQUEIOS.md
printf 'b\n' > docs/ft-legado/00-BLOQUEIOS.md
printf 'base\n' > src/base.ts
cat > docs/sprintx/features/ft-02/sprint-01/tasks.md <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: ft-02
tasks:
  - id: T-01.01
    status: concluida
    arquivos:
      cria: [src/base.ts]
      altera: []
    suite: verde
---
YAML
git add -A >/dev/null 2>&1 && git commit -qm "base da fixture historica" || exit 1
# Numa arvore integrada (varias features ja entregues no mesmo checkout),
# docs/entregas/ tem uma pasta por trabalho. Qual delas e o trabalho de AGORA
# nao se decide por mtime: decide-se pela branch ativa casada com o `branch:`
# do frontmatter de EXATAMENTE UM ENTREGA.md. Zero, dois ou mais, ou HEAD
# destacado: nenhuma isencao (conservador).
entrega() { # entrega <trabalho_id> <branch>
  mkdir -p "docs/entregas/$1"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: %s\nentregue_por: mergex\nbranch: %s\nbranch_base: main\n---\n\n# Entrega\n' \
    "$1" "$2" > "docs/entregas/$1/ENTREGA.md"
}

# Validade do portão: o push só segue com `portao: pronto` se o portão VALE
# para a revisão empurrada (validade-do-portao.sh). Os helpers montam o portão
# como o E2 e o checkpoint pre-e6 montam: `portao_sha` no ENTREGA.md commitado
# por um commit de método. O trabalho é o último segmento da branch
# (`feature/ft-02` => `ft-02`). Rodam no cwd (o repositório da fixture).
MSG_PORTAO="$SEMGIT_T/mensagem-portao"
metodo_commit() { # <trabalho> <assunto> — commita o índice como pre-e6
  printf '%s\n\nTrabalho: %s\nMetodo: pre-e6\n' "$2" "$1" > "$MSG_PORTAO" || return 1
  git commit -q -F "$MSG_PORTAO"
}
_portao_registra() { # <trabalho> <sha|-> — portao: pronto (+ portao_sha), commitado
  local e="docs/entregas/$1/ENTREGA.md"
  fm_chave "$e" portao pronto || return 1
  if [ "$2" = - ]; then fm_sem_chave "$e" portao_sha; else fm_chave "$e" portao_sha "$2"; fi || return 1
  git add -- "$e" && metodo_commit "$1" "docs(mergex): registra o portao"
}
portao_valido_com_metodo() { # <branch> — portão em HEAD, depois um commit só de método
  local t="${1##*/}"
  fixture_switch_exato "$1" "$1" || return 1
  _portao_registra "$t" "$(git rev-parse HEAD)" || return 1
  printf 'pacote do pr\n' >> "docs/entregas/$t/PR.md"
  git add -- "docs/entregas/$t/PR.md" && metodo_commit "$t" "docs(mergex): pacote do pr"
}
portao_vencido_por_merge() { # <branch> — portão válido, depois um merge da base
  portao_valido_com_metodo "$1" || return 1
  fixture_switch_exato main main || return 1
  printf 'a base avancou\n' >> src/base-avanca.ts
  git add src/base-avanca.ts && git commit -qm "a base avanca" || return 1
  fixture_switch_exato "$1" "$1" || return 1
  git merge -q --no-ff -m "integra a base" main
}
portao_sem_sha() { # <branch> — `portao: pronto` sem portao_sha (entrega legada)
  fixture_switch_exato "$1" "$1" || return 1
  _portao_registra "${1##*/}" -
}
portao_commita() { # <branch> <valor> — commita `portao: <valor>` (null, bloqueado)
  local t="${1##*/}" e
  e="docs/entregas/${1##*/}/ENTREGA.md"
  fixture_switch_exato "$1" "$1" || return 1
  fm_chave "$e" portao "$2" || return 1
  git add -- "$e" && metodo_commit "$t" "docs(mergex): registra portao $2"
}

# Os artefatos usados depois de varias trocas ja nascem tracked em todas as
# branches da fixture. Assim, switch nenhum depende de sujeira residual.
entrega ft-01 feature/ft-01
entrega ft-02 feature/ft-02
entrega ft-legado feature/ft-legado
git add docs/entregas >/dev/null 2>&1 && git commit -qm "entregas da fixture historica" || exit 1

fixture_switch_exato feature/ft-02 -c feature/ft-02 || exit 1
mkdir -p .expx
echo '{"expx_hooks":1,"hooks":{"arquivo-fora-do-plano":{"modo":"bloqueio"}}}' > .expx/hooks.json

# A — uma ENTREGA, declarando a branch atual
entrega ft-02 feature/ft-02
git reset -q; printf 'novo\n' >> docs/sprintx/features/ft-02/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-02/00-BLOQUEIOS.md
caso "A: ENTREGA da branch atual isenta a pasta dela" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0

# B — FT-01 passa a ser a ENTREGA mais recente; a branch atual continua sendo FT-02
entrega ft-01 feature/ft-01
caso "B: ENTREGA mais recente nao rouba o trabalho atual" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0

# C — a pasta da ENTREGA mais recente NAO e isenta: recencia nao decide nada
git reset -q; printf 'novo\n' >> docs/sprintx/features/ft-01/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-01/00-BLOQUEIOS.md
caso "C: pasta da ENTREGA mais recente nao e isenta" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2

# D — duas ENTREGA declarando a MESMA branch atual: ambiguo
entrega ft-03 feature/ft-02
git reset -q; printf 'novo\n' >> docs/sprintx/features/ft-02/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-02/00-BLOQUEIOS.md
caso "D: duas ENTREGA na mesma branch => sem isencao" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
rm -rf docs/entregas/ft-03

# E — nenhuma ENTREGA declara a branch atual
fixture_restaurar_tracked docs/sprintx/features/ft-01/00-BLOQUEIOS.md docs/sprintx/features/ft-02/00-BLOQUEIOS.md || exit 1
fixture_switch_exato feature/sem-entrega -c feature/sem-entrega || exit 1
printf 'novo\n' >> docs/sprintx/features/ft-02/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-02/00-BLOQUEIOS.md
caso "E: nenhuma ENTREGA para a branch => sem isencao" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2

# F — HEAD destacado: nao ha branch para casar
fixture_restaurar_tracked docs/sprintx/features/ft-02/00-BLOQUEIOS.md || exit 1
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
git checkout -q --detach || exit 1
printf 'novo\n' >> docs/sprintx/features/ft-02/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-02/00-BLOQUEIOS.md
caso "F: detached HEAD => sem isencao" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
fixture_restaurar_tracked docs/sprintx/features/ft-02/00-BLOQUEIOS.md || exit 1
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1

# I — pasta legada do trabalho certo, quando nao existe a canonica
entrega ft-legado feature/ft-legado
fixture_switch_exato feature/ft-legado -c feature/ft-legado || exit 1
git reset -q; printf 'novo\n' >> docs/ft-legado/00-BLOQUEIOS.md
git add -f docs/ft-legado/00-BLOQUEIOS.md
caso "I: pasta legada do trabalho certo e isenta" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0

# G — pasta de OUTRO trabalho continua sendo desvio
git reset -q; printf 'novo\n' >> docs/sprintx/features/ft-01/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-01/00-BLOQUEIOS.md
caso "G: pasta de outro trabalho e desvio" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2

# H — arquivo de produto fora do plano continua sendo desvio
fixture_restaurar_tracked docs/ft-legado/00-BLOQUEIOS.md docs/sprintx/features/ft-01/00-BLOQUEIOS.md || exit 1
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
printf 'produto nao planejado\n' > src/fora/surpresa2.ts
git add -f src/fora/surpresa2.ts
caso "H: produto fora do plano e desvio" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2

git reset -q; rm -f src/fora/surpresa2.ts .expx/hooks.json
fixture_switch_exato main main || exit 1

echo
echo "runx — a estrutura da runx nao regride"
# Mesma regra de trabalho corrente, outro formato de caminho: a pasta da
# ocorrencia em curso e isenta; a de outro trabalho continua sendo desvio.
mkdir -p docs/manutencao/OC-2026-0001-erro
printf 'b\n' > docs/manutencao/OC-2026-0001-erro/BLOQUEIOS.md
git add -A >/dev/null 2>&1 && git commit -qm "ocorrencia da runx"
fixture_switch_exato fix/OC-2026-0001-erro -c fix/OC-2026-0001-erro || exit 1
mkdir -p .expx
echo '{"expx_hooks":1,"hooks":{"arquivo-fora-do-plano":{"modo":"bloqueio"}}}' > .expx/hooks.json
entrega OC-2026-0001-erro fix/OC-2026-0001-erro
git reset -q; printf 'novo\n' >> docs/manutencao/OC-2026-0001-erro/BLOQUEIOS.md
git add -f docs/manutencao/OC-2026-0001-erro/BLOQUEIOS.md
caso "runx: pasta da ocorrencia corrente e isenta" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
git reset -q; printf 'novo\n' >> docs/sprintx/features/ft-01/00-BLOQUEIOS.md
git add -f docs/sprintx/features/ft-01/00-BLOQUEIOS.md
caso "runx: pasta de outro trabalho e desvio"     mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
# A isencao do HISTORICO e da sprintx: a runx nao a herda.
git reset -q; mkdir -p docs/sprintx/estimativas; printf 'h\n' >> docs/sprintx/estimativas/HISTORICO.md
git add -f docs/sprintx/estimativas/HISTORICO.md
caso "runx NAO ganha a isencao do HISTORICO"      mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
fixture_restaurar_tracked docs/manutencao/OC-2026-0001-erro/BLOQUEIOS.md docs/sprintx/features/ft-01/00-BLOQUEIOS.md || exit 1
rm -f .expx/hooks.json
fixture_switch_exato main main || exit 1

echo
echo "E8 — fechamento final (o registro da entrega vai para o historico)"
# O E8 fecha commitando o ENTREGA.md final: sem isso, a branch integrada leva um
# registro defasado e o estado final morre com o worktree. Os hooks precisam
# deixar esse commit passar, SEM afrouxar nada do resto.
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
mkdir -p .expx
echo '{"expx_hooks":1,"hooks":{"arquivo-fora-do-plano":{"modo":"bloqueio"}}}' > .expx/hooks.json

# 1 — so o artefato final da entrega deste trabalho
git reset -q
printf 'estado: entregue\n' >> docs/entregas/ft-02/ENTREGA.md
git add -f docs/entregas/ft-02/ENTREGA.md
caso "fechamento final: ENTREGA.md deste trabalho entra" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0

# 2 — produto fora do plano NAO pega carona no fechamento
printf 'produto nao planejado\n' > src/fora/surpresa3.ts
git add -f src/fora/surpresa3.ts
caso "fechamento final nao carrega produto fora do plano" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
git reset -q; rm -f src/fora/surpresa3.ts

# 2b — fechamento BLOQUEADO: o registro do bloqueio tambem precisa ser persistido
git reset -q
printf 'portao: bloqueado\nestado: bloqueado\n' >> docs/entregas/ft-02/ENTREGA.md
git add -f docs/entregas/ft-02/ENTREGA.md
caso "fechamento bloqueado: registro do bloqueio entra" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
git reset -q; git checkout -q -- docs/entregas/ft-02/ENTREGA.md 2>/dev/null

# 2c — HISTORICO global da sprintx: excecao EXATA, so na origem sprintx
git reset -q
mkdir -p docs/sprintx/estimativas
printf 'historico\n' >> docs/sprintx/estimativas/HISTORICO.md
git add -f docs/sprintx/estimativas/HISTORICO.md
caso "HISTORICO global da sprintx nao e desvio" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
git reset -q
printf 'outro\n' > docs/sprintx/estimativas/CALIBRAGEM.md
git add -f docs/sprintx/estimativas/CALIBRAGEM.md
caso "outro arquivo em estimativas/ NAO e isento" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 2
git reset -q; rm -f docs/sprintx/estimativas/CALIBRAGEM.md

# 3 — a varredura de segredo vale igual no artefato de metodo
caso "fechamento final: segredo no artefato barra" comum/sem-segredo.sh "$(write_json "token: \"$SK\"")" 2

# 4 — publicar o fechamento e push: o portao continua mandando, e o `pronto`
# precisa valer para a revisao empurrada (portao_sha + so commits de metodo)
git reset -q
portao_valido_com_metodo feature/ft-02 || exit 1
caso "publicacao do fechamento com portao pronto" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 0
portao_commita feature/ft-02 bloqueado || exit 1
echo '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"bloqueio"}}}' > .expx/hooks.json
caso "publicacao do fechamento com portao bloqueado barra" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 2

# 5 — forcar a publicacao do fechamento continua proibido
caso "fechamento final: push --force barra"            mergex/git-perigoso.sh "$(bash_json 'git push --force origin feature/ft-02')" 2
caso "fechamento final: push --force-with-lease barra" mergex/git-perigoso.sh "$(bash_json 'git push --force-with-lease origin feature/ft-02')" 2

git reset -q; rm -f .expx/hooks.json
git restore --worktree -- docs/entregas/ft-02/ENTREGA.md 2>/dev/null || true
fixture_switch_exato main main || exit 1

echo
echo "pr-so-com-portao — aviso antecipado (bloqueia so com prova)"
# DM-184 (spec 13.8): o hook do Claude e so aviso antecipado, nunca fronteira
# de seguranca. Bloqueia (exit 2) so o `git push` simples, lido sem ambiguidade
# no repositorio do cwd, cuja ref pr_decide_ref barra (a mesma regra do
# pre-push), e o `--no-verify` num push reconhecido. Comando composto, cwd que
# o Git nao le, refspec que nao resolve, validade que nao termina no orcamento:
# aviso e exit 0 — quem decide e o pre-push. Nenhuma varredura de branches.
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
mkdir -p .expx
modo_portao() { printf '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"%s"}}}\n' "$1" > .expx/hooks.json; }
PUSH_FT='git push origin feature/ft-02'
# saida_hook <json> [env...] — roda o hook; SAIDA_H (stderr) e RC_H
SAIDA_H=""; RC_H=""
saida_hook() {
  local json="$1"; shift
  SAIDA_H="$(printf '%s' "$json" | env "$@" bash "$H/mergex/pr-so-com-portao.sh" 2>&1 >/dev/null)"; RC_H=$?
}
# mensagem_cita <desc> <json> <trecho>... — o stderr do hook cita cada trecho
mensagem_cita() {
  local desc="$1" json="$2" t
  shift 2
  if [ "$SEM_JQ" = "1" ]; then PULADOS=$((PULADOS+1)); printf '  pulado %s (sem jq)\n' "$desc"; return 0; fi
  saida_hook "$json"
  for t in "$@"; do
    case "$SAIDA_H" in
      *"$t"*) ;;
      *) FALHOU=$((FALHOU+1)); printf '  FALHA %s (a mensagem nao cita: %s)\n' "$desc" "$t"; return 0 ;;
    esac
  done
  OK=$((OK+1)); printf '  ok    %s\n' "$desc"
}
# caso_aviso <desc> <json> [env...] — exit 0 COM o aviso do hook no stderr
AVISO_H='mergex/pr-so-com-portao — aviso'
caso_aviso() {
  local desc="$1" json="$2"
  shift 2
  if [ "$SEM_JQ" = "1" ]; then PULADOS=$((PULADOS+1)); printf '  pulado %s (sem jq)\n' "$desc"; return 0; fi
  saida_hook "$json" "$@"
  case "$RC_H:$SAIDA_H" in
    0:*"$AVISO_H"*) OK=$((OK+1)); printf '  ok    %s\n' "$desc" ;;
    *) FALHOU=$((FALHOU+1)); printf '  FALHA %s (esperava exit 0 com aviso, obteve %s: %s)\n' "$desc" "$RC_H" "$(printf '%s' "$SAIDA_H" | head -1)" ;;
  esac
}
# caso_calado <desc> <json> — exit 0 sem nada no stderr (passa sem aviso)
caso_calado() {
  local desc="$1" json="$2"
  if [ "$SEM_JQ" = "1" ]; then PULADOS=$((PULADOS+1)); printf '  pulado %s (sem jq)\n' "$desc"; return 0; fi
  saida_hook "$json"
  if [ "$RC_H" = 0 ] && [ -z "$SAIDA_H" ]; then OK=$((OK+1)); printf '  ok    %s\n' "$desc"
  else FALHOU=$((FALHOU+1)); printf '  FALHA %s (esperava exit 0 calado, obteve %s: %s)\n' "$desc" "$RC_H" "$(printf '%s' "$SAIDA_H" | head -1)"; fi
}
# em_todos_os_modos <desc> <json> <exit> — aviso, bloqueio e desligado
em_todos_os_modos() {
  local m
  for m in aviso bloqueio desligado; do
    modo_portao "$m"
    caso "$1 [$m]" mergex/pr-so-com-portao.sh "$2" "$3"
  done
  modo_portao aviso
}
# em_todos_os_modos_avisa <desc> <json> — avisa e sai 0 em aviso e bloqueio
# (o hook nunca bloqueia o que nao prova); em desligado, calado
em_todos_os_modos_avisa() {
  modo_portao aviso;     caso_aviso "$1 [aviso]" "$2"
  modo_portao bloqueio;  caso_aviso "$1 [bloqueio]" "$2"
  modo_portao desligado; caso_calado "$1 [desligado]" "$2"
  modo_portao aviso
}

# Repositorio sem MergeX (branch dev), para os comandos que o citam
git -C "$SEMX_T" init -q -b dev . 2>/dev/null
git -C "$SEMX_T" config user.email teste@expx.local
git -C "$SEMX_T" config user.name Teste
printf 'x\n' > "$SEMX_T/x.txt"
git -C "$SEMX_T" add x.txt && git -C "$SEMX_T" commit -qm inicial

# ENTREGA de outro trabalho, mais recente e `pronto`, nao decide pela branch
# (ft-02, aqui com portao null commitado).
portao_commita feature/ft-02 null || exit 1
entrega outro feature/outro
fm_chave docs/entregas/outro/ENTREGA.md portao pronto
touch -t 203001010000 docs/entregas/outro/ENTREGA.md
modo_portao bloqueio
caso "entrega de outro trabalho mais recente nao libera" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
modo_portao aviso
caso_aviso "entrega de outro trabalho mais recente nao barra (null em aviso)" "$(bash_json "$PUSH_FT")"
rm -rf docs/entregas/outro

# ---------------------------------------------------------------------------
# Portao vencido por merge da base
# ---------------------------------------------------------------------------
portao_vencido_por_merge feature/ft-02 || exit 1
MERGE_T="$(git rev-parse HEAD)"
caso "portao vencido barra mesmo em aviso" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
em_todos_os_modos "push simples com portao vencido bloqueia" "$(bash_json "$PUSH_FT")" 2
mensagem_cita "portao vencido: a mensagem nomeia branch, motivo, primeiro commit e o E2" "$(bash_json "$PUSH_FT")" \
  feature/ft-02 commit_merge "$MERGE_T" /mergex-check
# Comando composto: o hook nao le o shell como fronteira; avisa e o pre-push decide
caso_aviso "comando composto avisa e sai 0: cd <repo> && git push" "$(bash_json "cd $HIST_T && $PUSH_FT")"
caso_aviso "comando composto avisa e sai 0: bash -c 'git push'"    "$(bash_json "bash -c '$PUSH_FT'")"
caso_aviso "comando composto avisa e sai 0: xargs git push"        "$(bash_json 'echo feature/ft-02 | xargs git push origin')"
mensagem_cita "comando composto: o aviso manda ao pre-push" "$(bash_json "cd $HIST_T && $PUSH_FT")" \
  "pre-push" "/mergex-check"
# Abertura de PR nao e push: o hook so le `git push`
caso_calado "nao e push: gh pr create"           "$(bash_json 'gh pr create --fill')"
caso_calado "nao e push: gh -R o/r pr create"    "$(bash_json 'gh -R o/r pr create --fill')"
caso_calado "nao e push: gh --repo o/r pr create" "$(bash_json 'gh --repo o/r pr create')"
caso_calado "nao e push: gh pr new"              "$(bash_json 'gh pr new --fill')"
caso_calado "nao e push: glab mr new"            "$(bash_json 'glab mr new --fill')"
# Outras formas de publicar: avisam
caso_aviso "send-pack avisa"                     "$(bash_json 'git send-pack origin refs/heads/feature/ft-02')"
caso_aviso "subtree push avisa"                  "$(bash_json 'git subtree push --prefix src origin feature/ft-02')"
caso_aviso "/usr/lib/git-core/git-push avisa"    "$(bash_json '/usr/lib/git-core/git-push origin feature/ft-02')"
caso_aviso "\"\$(git --exec-path)\"/git-push avisa" "$(bash_json '"$(git --exec-path)"/git-push origin feature/ft-02')"
caso_aviso "git-send-pack avisa"                 "$(bash_json 'git-send-pack origin refs/heads/feature/ft-02')"
caso_calado "git-subtree --help nao publica"     "$(bash_json "'/usr/lib/git-core/git-subtree' --help")"
caso_calado "sem push: npm run git-push-notifications" "$(bash_json 'npm run git-push-notifications')"
# Tag com o mesmo nome da branch: a origem HEAD e a branch atual, sem ambiguidade
git tag feature/ft-02 main >/dev/null 2>&1
caso "tag homonima da branch: push -u origin HEAD barra" mergex/pr-so-com-portao.sh "$(bash_json 'git push -u origin HEAD')" 2
caso_aviso "tag homonima da branch: refspec ambiguo avisa" "$(bash_json 'git push origin feature/ft-02')"
git tag -d feature/ft-02 >/dev/null 2>&1
# Um .git que nao se resolve: o hook avisa (antes, barrava)
mkdir -p "$SEMGIT_T/quebrado"
printf 'gitdir: %s/nao-existe\n' "$SEMGIT_T" > "$SEMGIT_T/quebrado/.git"
HOOK_CWD="$SEMGIT_T"
caso_aviso "repositorio com .git que nao se resolve avisa" "$(bash_json "cd $SEMGIT_T/quebrado && git push origin feature/ft-02")"
HOOK_CWD="$SEMGIT_T/quebrado"
caso_aviso "cwd com .git que nao se resolve avisa"         "$(bash_json 'git push origin feature/ft-02')"
HOOK_CWD="$SEMGIT_T"
caso_aviso "fora de repositorio: git push avisa"           "$(bash_json 'git push')"
HOOK_CWD="$HIST_T"
rm -rf "$SEMGIT_T/quebrado"
entrega outro feature/outro
touch -t 203001010000 docs/entregas/outro/ENTREGA.md
caso "vencido: entrega de outro trabalho mais recente nao libera" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
rm -rf docs/entregas/outro

# O disco nunca decide: o ENTREGA da ponta da branch vale
fm_chave docs/entregas/ft-02/ENTREGA.md portao null
caso "disco null com a ponta pronto vencida barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
fm_chave docs/entregas/ft-02/ENTREGA.md portao bloqueado
caso "disco bloqueado com a ponta pronto vencida barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
fixture_restaurar_tracked docs/entregas/ft-02/ENTREGA.md || exit 1
rm -f docs/entregas/ft-02/ENTREGA.md
caso "ENTREGA removido do disco: a ponta vencida barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
fixture_restaurar_tracked docs/entregas/ft-02/ENTREGA.md || exit 1
entrega falso feature/ft-02
caso "ENTREGA falso nao rastreado na mesma branch nao muda nada" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
rm -rf docs/entregas/falso

# Formas que o hook nao le sem ambiguidade: avisam em qualquer modo (o
# desligado silencia), nunca bloqueiam
em_todos_os_modos_avisa "git -C . push"               "$(bash_json 'git -C . push origin feature/ft-02')"
em_todos_os_modos_avisa "git -c k=v push"             "$(bash_json 'git -c core.x=y push origin feature/ft-02')"
em_todos_os_modos_avisa "git --work-tree . push"      "$(bash_json 'git --work-tree . push origin feature/ft-02')"
em_todos_os_modos_avisa "sh -c 'git push'"            "$(bash_json "sh -c 'git push'")"
em_todos_os_modos_avisa "push de tags; \\git push"    "$(bash_json 'git push origin --tags; \git push origin feature/ft-02')"
em_todos_os_modos_avisa "-c remote.origin.push="      "$(bash_json 'git -c remote.origin.push=refs/heads/feature/ft-02:refs/heads/feature/ft-02 push origin')"
git tag v1 >/dev/null 2>&1
caso_aviso "push de tag && /usr/bin/git push"     "$(bash_json 'git push origin v1 && /usr/bin/git push origin feature/ft-02')"
caso_aviso "push benigno && find -exec git push"  "$(bash_json 'git push origin main && find . -maxdepth 0 -exec git push origin feature/ft-02 \;')"
caso_aviso "push benigno; flock git push"         "$(bash_json 'git push origin main; flock /tmp/l git push origin feature/ft-02')"
caso_aviso "(cd outro); git push"                 "$(bash_json "(cd $SEMX_T); git push origin")"
caso_aviso "false && cd outro; git push"          "$(bash_json "false && cd $SEMX_T; git push")"
caso_aviso "funcao que empurra"                   "$(bash_json 'f(){ git push origin feature/ft-02; }; f')"
caso_aviso "prefixo de ambiente qualquer"         "$(bash_json "FOO=1 $PUSH_FT")"
caso_aviso "push com mais de uma linha"           "$(bash_json "git status
$PUSH_FT")"
caso_aviso "refspec entre aspas"                  "$(bash_json 'git push origin "feature/ft-02"')"
caso_aviso "push --all"                           "$(bash_json 'git push --all origin')"
caso_aviso "push --dry-run"                       "$(bash_json 'git push --dry-run origin feature/ft-02')"

# Citacao e outros programas: calados (o gatilho e o git como programa)
caso_calado "echo push nao e push"                "$(bash_json 'echo push')"
caso_calado "git log --grep push nao e push"      "$(bash_json 'git log --grep push')"
caso_calado "push de outra branch (nao aplicavel) passa" "$(bash_json 'git push origin main')"
caso_calado "sem push: git status"                "$(bash_json 'git status')"
caso_calado "sem push: npm run push-notifications" "$(bash_json 'npm run push-notifications')"
caso_calado "sem push: docker push"               "$(bash_json 'docker push img')"

# Outra arvore, outro diretorio, primeiro trabalho MergeX
fixture_switch_exato main main || exit 1
git worktree add -q "$WTM_T" -b fixture-main-wt main >/dev/null 2>&1 || exit 1
git worktree add -q "$WTB_T" -b fixture-sem-entregas "$(git rev-list --max-parents=0 HEAD)" >/dev/null 2>&1 || exit 1
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
HOOK_CWD="$WTM_T"
caso "cwd em outra branch: push da branch vencida barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
caso_aviso "xargs acrescenta o refspec"         "$(bash_json 'echo feature/ft-02 | xargs git push origin')"
caso_aviso "-c remote.origin.push= da main"     "$(bash_json 'git -c remote.origin.push=refs/heads/feature/ft-02:refs/heads/feature/ft-02 push origin')"
caso_aviso "cd com expansao && push"            "$(bash_json "cd \$DIR_X && $PUSH_FT")"
git -C "$WTM_T" config remote.origin.push refs/heads/feature/ft-02:refs/heads/feature/ft-02
caso_aviso "remote.origin.push configurado: push sem refspec avisa" "$(bash_json 'git push origin')"
git -C "$WTM_T" config --unset remote.origin.push
HOOK_CWD="$WTB_T"
[ ! -e "$WTB_T/docs/entregas" ] && caso "controle: o HEAD da arvore nao tem docs/entregas" mergex/pr-so-com-portao.sh "$(bash_json 'git status')" 0
caso "sem entregas no HEAD: push simples da branch vencida barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
caso_aviso "sem entregas no HEAD: funcao"       "$(bash_json 'f(){ git push origin feature/ft-02; }; f')"
caso_aviso "sem entregas no HEAD: ./git push"   "$(bash_json './git push origin feature/ft-02')"
caso_aviso "sem entregas no HEAD: GIT_DIR=x git push" "$(bash_json 'GIT_DIR=x git push origin feature/ft-02')"
caso_aviso "sem entregas no HEAD: xargs -I"     "$(bash_json 'echo feature/ft-02 | xargs -I{} git push origin {}')"
# Diretorio de outro repositorio citado no comando: avisa
HOOK_CWD="$SEMGIT_T"
caso_aviso "fora de repositorio: cd literal && push"   "$(bash_json "cd $HIST_T && $PUSH_FT")"
caso_aviso "fora de repositorio: git -C <dir> push"    "$(bash_json "git -C $HIST_T push origin feature/ft-02")"
caso_aviso "fora de repositorio: env -C <dir> git push" "$(bash_json "env -C $HIST_T git push origin feature/ft-02")"
caso_aviso "fora de repositorio: GIT_DIR=<dir>/.git"   "$(bash_json "GIT_DIR=$HIST_T/.git git push origin feature/ft-02")"
caso_aviso "fora de repositorio: --git-dir=<dir>/.git" "$(bash_json "git --git-dir=$HIST_T/.git push origin feature/ft-02")"
HOOK_CWD="$SEMX_T"
caso_aviso "repo sem MergeX: env -C <dir vencido> git push" "$(bash_json "env -C $HIST_T git push")"
caso_calado "repo sem MergeX: push proprio passa"           "$(bash_json 'git push origin dev')"
caso_aviso "repo sem MergeX: cd -- <wt> && push"           "$(bash_json "cd -- $WTM_T && $PUSH_FT")"
caso_aviso "repo sem MergeX: cd -P <wt> && push"           "$(bash_json "cd -P $WTM_T && $PUSH_FT")"
caso_aviso "repo sem MergeX: cd -L <wt>; push"             "$(bash_json "cd -L $WTM_T; $PUSH_FT")"
caso_aviso "repo sem MergeX: cd -eP -- <wt> && push"       "$(bash_json "cd -eP -- $WTM_T && $PUSH_FT")"
caso_aviso "repo sem MergeX: pushd -n <wt> && push"        "$(bash_json "pushd -n $WTM_T && $PUSH_FT")"
PAI_WTM="$(dirname "$WTM_T")"; BASE_WTM="$(basename "$WTM_T")"; BASE_HIST="$(basename "$HIST_T")"
caso_aviso "git -C <pai> -C <wt> push"            "$(bash_json "git -C $PAI_WTM -C $BASE_WTM push origin feature/ft-02")"
caso_aviso "git -C .. -C <wt> push"               "$(bash_json "git -C .. -C $BASE_WTM push origin feature/ft-02")"
caso_aviso "cd <pai> && GIT_DIR=<repo>/.git push" "$(bash_json "cd $PAI_WTM && GIT_DIR=$BASE_HIST/.git git push origin feature/ft-02")"
caso_aviso "cd .. && cd <wt> && push"             "$(bash_json "cd .. && cd $BASE_WTM && $PUSH_FT")"
caso_aviso "cd <pai> && cd <wt> && push"          "$(bash_json "cd $PAI_WTM && cd $BASE_WTM && $PUSH_FT")"
caso_aviso "cd <pai>; git -C <wt> push"           "$(bash_json "cd $PAI_WTM; git -C $BASE_WTM push origin feature/ft-02")"
caso_aviso "cd <pai> && git --git-dir=<repo>/.git push" "$(bash_json "cd $PAI_WTM && git --git-dir=$BASE_HIST/.git push origin feature/ft-02")"
caso_aviso "cd <pai> && env -C <wt> git push"     "$(bash_json "cd $PAI_WTM && env -C $BASE_WTM git push origin feature/ft-02")"
caso_aviso "cd / && cd <relativo> && push"        "$(bash_json "cd / && cd ${WTM_T#/} && $PUSH_FT")"
caso_aviso "cd / && cd ~/<wt> && push"            "$(bash_json "cd / && cd ~/$BASE_WTM && $PUSH_FT")"
caso_aviso "cd && cd <wt> && push"                "$(bash_json "cd && cd $BASE_WTM && $PUSH_FT")"
caso_aviso "GIT_DIR=~/<repo>/.git push"           "$(bash_json "GIT_DIR=~/$BASE_HIST/.git git push origin feature/ft-02")"
caso_aviso "( cd X ); git push"                   "$(bash_json "( cd $WTM_T ); git push origin feature/ft-02")"
GD_WTM="$(git -C "$WTM_T" rev-parse --absolute-git-dir)"
HOOK_CWD="$SEMGIT_T"
caso_aviso "fora de repositorio: GIT_DIR=<gitdir de worktree vinculada>"     "$(bash_json "GIT_DIR=$GD_WTM git push origin feature/ft-02")"
caso_aviso "fora de repositorio: --git-dir=<gitdir de worktree vinculada>"   "$(bash_json "git --git-dir=$GD_WTM push origin feature/ft-02")"
HOOK_CWD="$HIST_T"
git worktree remove --force "$WTM_T" || exit 1
git worktree remove --force "$WTB_T" || exit 1
git branch -q -D fixture-main-wt fixture-sem-entregas

# cwd que nao e repositorio, em forma UNC: aviso rapido, sem laco de subida de
# diretorio (`dirname //` e `//` em alguns sistemas)
for CWD_UNC in '//' '//wsl.localhost/mergex-nao-existe/x'; do
  HOOK_CWD="$CWD_UNC"
  T0_UNC=$SECONDS
  caso_aviso "cwd UNC sem repositorio nao entra em laco ($CWD_UNC)" "$(bash_json "$PUSH_FT")"
  valor "cwd UNC sem repositorio: termina em menos de 2 s ($CWD_UNC)" "$([ $((SECONDS - T0_UNC)) -lt 2 ] && echo sim || echo nao)" sim
done
HOOK_CWD="$HIST_T"

# dubious ownership: o Git recusa o repositorio do cwd (dono diferente, sem
# safe.directory). Config global VAZIA e temporaria, so no processo do hook.
GLOBAL_VAZIA_T="$SEMGIT_T/global-vazia"
: > "$GLOBAL_VAZIA_T"
caso_aviso "dubious ownership avisa e sai 0" "$(bash_json "$PUSH_FT")" \
  GIT_CONFIG_GLOBAL="$GLOBAL_VAZIA_T" GIT_TEST_ASSUME_DIFFERENT_OWNER=1
case "$SAIDA_H" in
  *safe.directory*) OK=$((OK+1)); printf '  ok    %s\n' "dubious ownership: o aviso cita safe.directory na config global" ;;
  *) FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "dubious ownership: o aviso nao cita safe.directory" ;;
esac
GIT_CONFIG_GLOBAL="$GLOBAL_VAZIA_T" GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git -C "$HIST_T" rev-parse --show-toplevel >/dev/null 2>&1 \
  && { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "controle: o Git aceitou o repositorio com dono diferente"; } \
  || { OK=$((OK+1)); printf '  ok    %s\n' "controle: o Git recusa o repositorio (dubious ownership)"; }

# Entrega legada: pronto sem portao_sha nunca libera
portao_sem_sha feature/ft-02 || exit 1
caso "pronto legado sem portao_sha barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
mensagem_cita "pronto legado: a mensagem nomeia portao_sha_ausente" "$(bash_json "$PUSH_FT")" portao_sha_ausente /mergex-check

# ---------------------------------------------------------------------------
# Portao valido seguido so de commit de metodo: o uso comum passa
# ---------------------------------------------------------------------------
portao_valido_com_metodo feature/ft-02 || exit 1
caso "portao valido com commit so de metodo libera" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 0
caso_calado "push simples com portao valido passa" "$(bash_json "$PUSH_FT")"
for C in 'git push' 'git push -u origin feature/ft-02' 'git push origin HEAD:feature/ft-02' \
         'git push origin HEAD:refs/heads/feature/ft-02' 'git push origin feature/ft-02:feature/ft-02' \
         'git push origin refs/heads/feature/ft-02' 'git push -o main origin feature/ft-02' \
         'git push -uo main origin feature/ft-02' 'git push origin main' 'git push origin v1' \
         'git push origin :feature/velha' 'git push --follow-tags origin feature/ft-02' \
         'git commit -m "antes do git push"' 'echo "git push origin feature/ft-02"' \
         'grep -rn "git push origin feature/ft-02" .' 'gh pr create --body "rode git push origin feature/ft-02"' \
         'find . -maxdepth 0 -exec echo git push \;'; do
  caso_calado "portao valido: $C" "$(bash_json "$C")"
done
for C in 'git -C . push origin feature/ft-02' "sh -c 'git push'" 'gh pr create --fill' 'gh -R o/r pr create --fill' \
         'gh pr new --fill' 'glab mr new --fill' 'git push --tags' 'git push --all origin' \
         'GIT_DIR=.git git push origin feature/ft-02' 'cd $DIR_X && git push origin feature/ft-02' \
         "cd $HIST_T && git push origin feature/ft-02" 'echo push' 'git log --grep push' 'docker push img' \
         '/usr/lib/git-core/git-push origin feature/ft-02' '"$(git --exec-path)"/git-push origin feature/ft-02' \
         "cd -P $HIST_T && git push origin feature/ft-02" "cd -- $HIST_T && git push origin feature/ft-02"; do
  caso "portao valido: $C" mergex/pr-so-com-portao.sh "$(bash_json "$C")" 0
done

# --no-verify num push reconhecido: bloqueia em qualquer modo (o pre-push
# seria pulado; o CI e a barreira contra esse contorno)
caso "--no-verify reconhecido bloqueia"                    mergex/pr-so-com-portao.sh "$(bash_json 'git push --no-verify origin feature/ft-02')" 2
em_todos_os_modos "--no-verify no fim do push bloqueia"    "$(bash_json 'git push origin feature/ft-02 --no-verify')" 2
caso "--no-verify em comando composto bloqueia"            mergex/pr-so-com-portao.sh "$(bash_json "cd $HIST_T && git push --no-verify origin feature/ft-02")" 2
caso "--no-verify dentro de sh -c bloqueia"                mergex/pr-so-com-portao.sh "$(bash_json "sh -c 'git push --no-verify'")" 2
caso "--no-verify com /usr/bin/git bloqueia"               mergex/pr-so-com-portao.sh "$(bash_json '/usr/bin/git push --no-verify origin feature/ft-02')" 2
caso "--no-verify com opcao global bloqueia"               mergex/pr-so-com-portao.sh "$(bash_json 'git -c core.x=y push --no-verify')" 2
caso "--no-verify com git-push bloqueia"                   mergex/pr-so-com-portao.sh "$(bash_json '/usr/lib/git-core/git-push --no-verify origin feature/ft-02')" 2
caso "--no-verify fora de repositorio bloqueia"            mergex/pr-so-com-portao.sh "$(jq -cn --arg c 'git push --no-verify' --arg w "$SEMGIT_T" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}')" 2
mensagem_cita "--no-verify: a mensagem explica o pre-push pulado e o CI" "$(bash_json 'git push --no-verify origin feature/ft-02')" \
  "--no-verify" "pula" "pre-push" "CI" "/mergex-check"
caso_calado "--no-verify em git commit nao e push"         "$(bash_json 'git commit --no-verify -m x')"
caso_calado "git log --grep=--no-verify nao bloqueia"      "$(bash_json 'git log --grep=--no-verify')"
# Prefixos unicos que o Git aceita para --no-verify (--no-ver colide com
# --no-verbose e o proprio Git recusa)
caso "prefixo --no-verif bloqueia"                         mergex/pr-so-com-portao.sh "$(bash_json 'git push --no-verif origin feature/ft-02')" 2
caso "prefixo --no-veri bloqueia"                          mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02 --no-veri')" 2
mensagem_cita "prefixo --no-verif: a mesma mensagem do --no-verify" "$(bash_json 'git push --no-verif origin feature/ft-02')" \
  "push com --no-verify barrado" "pre-push" "CI"
caso_aviso "--no-ver (ambiguo para o Git) nao bloqueia: avisa" "$(bash_json 'git push --no-ver origin feature/ft-02')"
# Formas reais de push com --no-verify: bloqueiam
for C in 'git push --no-verify' 'git push origin x --no-verify&' '(git push --no-verify)' 'git push --no-verify|cat' \
         '{ git push --no-verify; }' 'time git push --no-verify' 'command git push --no-verify' 'nice -n 5 git push --no-verify' \
         'git push "--no-verify"' 'git push --no-""verify' 'bash -c "git push --no-verify"' 'git push origin x --no-verify 2>&1' \
         'git --no-pager push --no-verify' 'GIT_TRACE=1 git push --no-verify' 'git push -n --no-verify'; do
  caso "forma real de push com --no-verify bloqueia: $C" mergex/pr-so-com-portao.sh "$(bash_json "$C")" 2
done
# Citacao do --no-verify em comando que nao publica: calado, nunca bloqueia
for C in 'git commit -m "docs: o hook barra git push --no-verify"' 'git log --grep "git push --no-verify"' \
         'git tag -a v9 -m "nunca git push --no-verify"' 'gh pr create --body "nao use git push --no-verify"' \
         'echo "git push --no-verify"' 'grep -rn "git push --no-verify" .'; do
  caso_calado "nao publica, so cita --no-verify: $C" "$(bash_json "$C")"
done

# Origem explicita: a validade roda sobre o SHA enviado
fixture_switch_exato fixture-produto -c fixture-produto || exit 1
printf 'produto solto\n' > src/solto.ts
git add src/solto.ts && git commit -qm "feat: produto solto" || exit 1
SHA_PROD="$(git rev-parse HEAD)"
fixture_switch_exato feature/ft-02 feature/ft-02 || exit 1
git branch -q -D fixture-produto
caso "origem explicita: <sha de produto>:feature/ft-02 barra" mergex/pr-so-com-portao.sh "$(bash_json "git push origin $SHA_PROD:feature/ft-02")" 2
mensagem_cita "origem explicita: a mensagem nomeia a origem, o motivo e o E2" "$(bash_json "git push origin $SHA_PROD:feature/ft-02")" \
  "$SHA_PROD" commit_de_produto /mergex-check
modo_portao desligado
caso "origem explicita: barra tambem em desligado" mergex/pr-so-com-portao.sh "$(bash_json "git push origin $SHA_PROD:refs/heads/feature/ft-02")" 2
modo_portao aviso
caso "origem explicita: HEAD~1:refs/heads/feature/ft-02 validada pela origem" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin HEAD~1:refs/heads/feature/ft-02')" 0
caso "origem explicita: feature/ft-02:feature/ft-02 ok" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02:feature/ft-02')" 0
caso "origem explicita: SHA da propria ponta ok" mergex/pr-so-com-portao.sh "$(bash_json "git push origin $(git rev-parse HEAD):feature/ft-02")" 0
caso "origem explicita: outra branch (main) barra" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin main:feature/ft-02')" 2
caso_aviso "origem explicita que nao se resolve avisa (o git recusa sozinho)" "$(bash_json 'git push origin nao-existe:feature/ft-02')"
# A ponta da branch decide, nao o HEAD de outra arvore
git branch -q fixture-vencida HEAD
git worktree add -q "$WTX_T" fixture-vencida >/dev/null 2>&1 || exit 1
printf 'produto na outra arvore\n' > "$WTX_T/src/outra-arvore.ts"
git -C "$WTX_T" add src/outra-arvore.ts && git -C "$WTX_T" commit -qm "feat: produto na outra arvore" || exit 1
HOOK_CWD="$WTX_T"
caso "outra arvore com HEAD vencido nao decide pela ponta valida" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 0
HOOK_CWD="$HIST_T"
git worktree remove --force "$WTX_T" || exit 1
git branch -q -D fixture-vencida

# Commit de produto depois do portao: vencido
printf 'produto depois do portao\n' > src/depois.ts
git add src/depois.ts && git commit -qm "feat: produto depois do portao" || exit 1
caso "produto depois do portao barra o push da branch" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
mensagem_cita "produto depois do portao: commit_de_produto no proprio commit" "$(bash_json "$PUSH_FT")" \
  commit_de_produto "$(git rev-parse HEAD)"
modo_portao bloqueio
caso "portao vencido em bloqueio tambem barra"     mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
# o modo nunca afrouxa o portao vencido (a mesma regra do pre-push)
modo_portao desligado
caso "desligado nao pula a validade do portao"     mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2

# null e bloqueado (commitados): pr_decide_ref decide, como no pre-push
portao_commita feature/ft-02 null || exit 1
modo_portao aviso
caso_aviso "null em aviso: avisa e passa"                "$(bash_json "$PUSH_FT")"
caso_aviso "null em aviso: push --all avisa"             "$(bash_json 'git push --all origin')"
modo_portao bloqueio
caso "null em bloqueio: barra"                          mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
caso "null em bloqueio: push de outra branch nao e do trabalho" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin main')" 0
caso "null em bloqueio: citacao nao e push da branch"   mergex/pr-so-com-portao.sh "$(bash_json 'echo push')" 0
caso "null em bloqueio: grep 'gh pr create' nao e PR"   mergex/pr-so-com-portao.sh "$(bash_json "grep -n 'gh pr create' README.md")" 0
caso "null em bloqueio: gh pr create nao e push"        mergex/pr-so-com-portao.sh "$(bash_json 'gh pr create --fill')" 0
modo_portao desligado
caso_calado "null com o hook desligado: nao age"        "$(bash_json "$PUSH_FT")"
portao_commita feature/ft-02 bloqueado || exit 1
modo_portao bloqueio
caso "bloqueado em bloqueio: barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
modo_portao aviso
caso "bloqueado em aviso: barra (o modo so vale para null)" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
# o disco pronto nao promove nada: vale o bloqueado da ponta
fm_chave docs/entregas/ft-02/ENTREGA.md portao pronto
modo_portao bloqueio
caso "disco pronto com a ponta bloqueada: barra" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
fixture_restaurar_tracked docs/entregas/ft-02/ENTREGA.md || exit 1
modo_portao aviso

# ---------------------------------------------------------------------------
# Instalacao: as regras ao lado dos hooks, e a validade substituida
# ---------------------------------------------------------------------------
portao_valido_com_metodo feature/ft-02 || exit 1
caso "controle: portao valido de novo libera"      mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 0
INST_R="$SEMGIT_T/instalacao/.claude"
INST_T="$INST_R/hooks"
mkdir -p "$INST_T/comum" "$INST_T/mergex"
cp "$H/comum/base.sh" "$INST_T/comum/base.sh"
cp "$H/mergex/pr-so-com-portao.sh" "$INST_T/mergex/pr-so-com-portao.sh"
H_REAL="$H"; H="$INST_T"
caso_aviso "regras ausentes ao lado dos hooks: avisa" "$(bash_json "$PUSH_FT")"
mensagem_cita "regras ausentes: o aviso nomeia portao-regras.sh" "$(bash_json "$PUSH_FT")" portao-regras.sh
caso "regras ausentes: --no-verify continua barrado" mergex/pr-so-com-portao.sh "$(bash_json 'git push --no-verify origin feature/ft-02')" 2

# Com os scripts da skill copiados, a validade vira um substituto
mkdir -p "$INST_R/skills/mergex"
cp -R "$REPO_ROOT/.claude/skills/mergex/scripts" "$INST_R/skills/mergex/scripts"
STUB_T="$INST_R/skills/mergex/scripts/validade-do-portao.sh"
CHAMADAS_T="$SEMGIT_T/chamadas-validade"
# O hook passa --rev com o SHA enviado (a ponta da branch empurrada)
cat > "$STUB_T" <<'STUB'
#!/usr/bin/env bash
esperado="$(git rev-parse HEAD)"; rev=""
while [ "$#" -gt 0 ]; do case "$1" in --rev) rev="${2:-}"; shift 2 ;; *) shift ;; esac; done
[ "$rev" = "$esperado" ] && { printf 'ok=true\nprimeiro_commit=-\n'; exit 0; }
printf 'ok=false\nmotivo=commit_de_produto\nprimeiro_commit=-\n'; exit 1
STUB
caso_calado "o hook passa --rev com a ponta (push)"       "$(bash_json "$PUSH_FT")"
caso "o hook passa --rev com a origem explicita: HEAD~1 barra pelo substituto" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin HEAD~1:refs/heads/feature/ft-02')" 2
printf '#!/usr/bin/env bash\nprintf "ok=false\\nmotivo=erro_ambiente\\nprimeiro_commit=-\\naviso=sem git\\n"; exit 1\n' > "$STUB_T"
caso_aviso "validade com erro_ambiente avisa (nao prova nada)" "$(bash_json "$PUSH_FT")"
printf '#!/usr/bin/env bash\nexit 64\n' > "$STUB_T"
caso_aviso "validade com uso invalido avisa"          "$(bash_json "$PUSH_FT")"
printf '#!/usr/bin/env bash\nprintf "ok=true\\nprimeiro_commit=-\\n"; exit 1\n' > "$STUB_T"
caso_aviso "validade ok=true com rc 1 avisa"          "$(bash_json "$PUSH_FT")"
printf '#!/usr/bin/env bash\nprintf "ok=false\\nmotivo=commit_de_produto\\nprimeiro_commit=-\\n"; exit 1\n' > "$STUB_T"
caso "validade ok=false barra (prova)"                mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2

# Sem `timeout` funcional: avisa sem chamar a validade
: > "$CHAMADAS_T"
printf '#!/usr/bin/env bash\necho x >> %s\nprintf "ok=true\\nprimeiro_commit=-\\n"; exit 0\n' "$CHAMADAS_T" > "$STUB_T"
SEM_TIMEOUT_T="$SEMGIT_T/sem-timeout"
mkdir -p "$SEM_TIMEOUT_T"
IFS=: read -r -a DIRS_PATH_T <<<"$PATH"
for D_T in "${DIRS_PATH_T[@]}"; do
  case "$D_T" in /mnt/*|'') continue ;; esac   # WSL: pastas do Windows (lentas)
  for F_T in "$D_T"/*; do
    N_T="${F_T##*/}"
    case "$N_T" in timeout|gtimeout) continue ;; esac
    [ -x "$F_T" ] && [ ! -e "$SEM_TIMEOUT_T/$N_T" ] && ln -s "$F_T" "$SEM_TIMEOUT_T/$N_T"
  done
done
valor "controle: o PATH da bancada nao tem timeout" "$(PATH="$SEM_TIMEOUT_T" command -v timeout || echo ausente)" ausente
caso_aviso "sem timeout no PATH: avisa e sai 0" "$(bash_json "$PUSH_FT")" PATH="$SEM_TIMEOUT_T"
valor "sem timeout no PATH: a validade nao e chamada" "$(wc -l < "$CHAMADAS_T" | tr -d ' ')" 0
# um `timeout` que nao mata (so executa o comando) nao e funcional
printf '#!/usr/bin/env bash\n[ "$1" = -k ] && shift 2\nshift\nexec "$@"\n' > "$SEM_TIMEOUT_T/timeout"
chmod +x "$SEM_TIMEOUT_T/timeout"
caso_aviso "timeout que nao mata: avisa e sai 0" "$(bash_json "$PUSH_FT")" PATH="$SEM_TIMEOUT_T"
valor "timeout que nao mata: a validade nao e chamada" "$(wc -l < "$CHAMADAS_T" | tr -d ' ')" 0
rm -rf "$SEM_TIMEOUT_T"

# hook nao varre branches: 50 branches entregues com `pronto`, uma validade so
BASE_50="$(git rev-parse main)"
I_T=1
while [ "$I_T" -le 50 ]; do
  B_T="$(printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: b%s\nentregue_por: mergex\nbranch: feature/b%s\nbranch_base: main\nportao: pronto\nportao_sha: %s\n---\n' "$I_T" "$I_T" "$BASE_50" | git hash-object -w --stdin)" || exit 1
  rm -f "$SEMGIT_T/idx-50"
  GIT_INDEX_FILE="$SEMGIT_T/idx-50" git read-tree "$BASE_50" || exit 1
  GIT_INDEX_FILE="$SEMGIT_T/idx-50" git update-index --add --cacheinfo "100644,$B_T,docs/entregas/b$I_T/ENTREGA.md" || exit 1
  C_T="$(git commit-tree "$(GIT_INDEX_FILE="$SEMGIT_T/idx-50" git write-tree)" -p "$BASE_50" -m "entrega b$I_T")" || exit 1
  git update-ref "refs/heads/feature/b$I_T" "$C_T" || exit 1
  I_T=$((I_T + 1))
done
rm -f "$SEMGIT_T/idx-50"
valor "controle: 50 branches entregues com portao pronto" "$(git for-each-ref --format=x 'refs/heads/feature/b*' | wc -l | tr -d ' ')" 50
: > "$CHAMADAS_T"
caso_calado "hook nao varre branches: push da branch valida passa" "$(bash_json "$PUSH_FT")"
valor "hook nao varre branches: no maximo uma chamada da validade" "$([ "$(wc -l < "$CHAMADAS_T" | tr -d ' ')" -le 1 ] && echo sim || echo "nao: $(wc -l < "$CHAMADAS_T" | tr -d ' ')")" sim
: > "$CHAMADAS_T"
caso_calado "hook nao varre branches: push de outra branch calado" "$(bash_json 'git push origin main')"
valor "hook nao varre branches: ref nao aplicavel, nenhuma chamada" "$(wc -l < "$CHAMADAS_T" | tr -d ' ')" 0
for I_T in $(git for-each-ref --format='%(refname)' 'refs/heads/feature/b*'); do git update-ref -d "$I_T"; done

# validade lenta nao segura o comando: a substituta dorme 120 s; o hook sai 0
# com aviso dentro do orcamento, sem processo orfao; e o push real seguinte e
# barrado pelo pre-push (que usa a validade de verdade)
printf 'produto vencido para o push real\n' > src/lento.ts
git add src/lento.ts && git commit -qm "feat: produto para o push real" || exit 1
printf '#!/usr/bin/env bash\nsleep 3119\nprintf "ok=true\\nprimeiro_commit=-\\n"; exit 0\n' > "$STUB_T"
T0_LENTO=$SECONDS
caso_aviso "validade lenta nao segura o comando: avisa e sai 0" "$(bash_json "$PUSH_FT")"
DUR_LENTO=$((SECONDS - T0_LENTO))
valor "validade lenta nao segura o comando: menos de 9 s (${DUR_LENTO} s)" "$([ "$DUR_LENTO" -lt 9 ] && echo sim || echo nao)" sim
case "$SAIDA_H" in
  *"orçamento de 8 s"*) OK=$((OK+1)); printf '  ok    %s\n' "validade lenta: o aviso nomeia o orcamento de 8 s" ;;
  *) FALHOU=$((FALHOU+1)); printf '  FALHA %s (%s)\n' "validade lenta: o aviso nao nomeia o orcamento" "$(printf '%s' "$SAIDA_H" | head -1)" ;;
esac
N_T=0; while [ "$N_T" -lt 5 ] && pgrep -f '^sleep 3119$' >/dev/null 2>&1; do sleep 1; N_T=$((N_T + 1)); done
if pgrep -f '^sleep 3119$' >/dev/null 2>&1; then
  FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "validade lenta: processo orfao da validade"; pkill -f '^sleep 3119$'
else OK=$((OK+1)); printf '  ok    %s\n' "validade lenta: nenhum processo orfao"; fi
H="$H_REAL"
REMOTO_LENTO_T="$SEMGIT_T/remoto-lento.git"
git init -q --bare "$REMOTO_LENTO_T"
ATV_T="$REPO_ROOT/.claude/skills/mergex/scripts/ativacao-pre-push.sh"
GIT_CONFIG_GLOBAL="$GLOBAL_VAZIA_T" bash "$ATV_T" --instalar --entrega docs/entregas/ft-02/ENTREGA.md >/dev/null 2>&1
valor "controle: pre-push instalado pelo E0 (ativacao-pre-push --instalar)" "$?" 0
GIT_CONFIG_GLOBAL="$GLOBAL_VAZIA_T" git push -q "$REMOTO_LENTO_T" feature/ft-02 >/dev/null 2>&1
valor "validade lenta: o git push real seguinte e barrado pelo pre-push" "$?" 1
valor "validade lenta: nada chegou ao remoto" "$(git -C "$REMOTO_LENTO_T" for-each-ref | wc -l | tr -d ' ')" 0
GIT_CONFIG_GLOBAL="$GLOBAL_VAZIA_T" bash "$ATV_T" --reverter --entrega docs/entregas/ft-02/ENTREGA.md >/dev/null 2>&1
rm -rf "$REMOTO_LENTO_T"
rm -rf "$SEMGIT_T/instalacao"

# Git for Windows sobre \\wsl.localhost\...: o hook roda pelo Git Bash do
# Windows, com o cwd UNC. Sem o ambiente: NAO_EXECUTADO (nunca conta como ok).
gfw_hook() { # <desc> <com|sem> — exige exit 0; deixa a saida em GFW_SAIDA
  local desc="$1" safe="$2" gb="/mnt/c/Program Files/Git/bin/bash.exe" w hk j r
  GFW_SAIDA=""
  command -v wslpath >/dev/null 2>&1 || { nao_executado "$desc — sem wslpath (fora do WSL)"; return 1; }
  [ -f "$gb" ] || { nao_executado "$desc — Git Bash do Windows ausente ($gb)"; return 1; }
  "$gb" -c 'command -v git >/dev/null && command -v jq >/dev/null' >/dev/null 2>&1 \
    || { nao_executado "$desc — o Git Bash do Windows nao executa pelo interop, ou sem git/jq nele"; return 1; }
  w="$(wslpath -w "$HIST_T")"; hk="$(wslpath -w "$H/mergex/pr-so-com-portao.sh" | tr '\\' '/')"
  case "$w" in '\\'*) ;; *) nao_executado "$desc — o cenario nao tem caminho UNC ($w)"; return 1 ;; esac
  j="$SEMGIT_T/gfw.json"; r="$SEMGIT_T/gfw-roda.sh"
  jq -cn --arg c "$PUSH_FT" --arg w "$w" '{tool_name:"Bash",cwd:$w,tool_input:{command:$c}}' > "$j"
  cat > "$r" <<'EOF'
# Git Bash do Windows: <hook> <json> <com|sem> <repositorio UNC com />
# Config global TEMPORARIA so neste processo (GIT_CONFIG_GLOBAL): a config
# global do usuario nao e lida nem escrita.
g="$(mktemp)" || exit 91
if [ "$3" = com ]; then printf '[safe]\n\tdirectory = %%(prefix)/%s\n' "$4" > "$g"; else : > "$g"; fi
export GIT_CONFIG_GLOBAL="$(cygpath -m "$g")"
e="$(mktemp)" || exit 92
ini=$SECONDS
bash "$1" < "$2" > /dev/null 2> "$e"; rc=$?
printf 'uname=%s\nrc=%s\nt=%s\n' "$(uname -s)" "$rc" "$((SECONDS - ini))"
sed 's/^/err=/' "$e"
rm -f "$g" "$e"
EOF
  GFW_SAIDA="$("$gb" "$(wslpath -w "$r")" "$hk" "$(wslpath -w "$j")" "$safe" "$(printf '%s' "$w" | tr '\\' '/')" 2>&1)"
  rm -f "$j" "$r"
  case "$(printf '%s\n' "$GFW_SAIDA" | sed -n 's/^uname=//p')" in
    MINGW*|MSYS*) ;;
    *) FALHOU=$((FALHOU+1)); printf '  FALHA %s (nao rodou no Git Bash: %s)\n' "$desc" "$(printf '%s' "$GFW_SAIDA" | tr '\n' '|')"; return 1 ;;
  esac
  if [ "$(printf '%s\n' "$GFW_SAIDA" | sed -n 's/^rc=//p')" = 0 ]; then
    OK=$((OK+1)); printf '  ok    %s (%s s)\n' "$desc" "$(printf '%s\n' "$GFW_SAIDA" | sed -n 's/^t=//p')"; return 0
  fi
  FALHOU=$((FALHOU+1)); printf '  FALHA %s (%s)\n' "$desc" "$(printf '%s' "$GFW_SAIDA" | tr '\n' '|')"; return 1
}
portao_valido_com_metodo feature/ft-02 || exit 1
caso "controle: portao valido para o push legitimo do Git for Windows" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 0
if gfw_hook "git for windows sobre UNC: aviso sem bloqueio (sem safe.directory)" sem; then
  case "$GFW_SAIDA" in
    *"err=mergex/pr-so-com-portao — aviso"*safe.directory*) OK=$((OK+1)); printf '  ok    %s\n' "git for windows sobre UNC: dubious ownership avisa e cita safe.directory na config global" ;;
    *) FALHOU=$((FALHOU+1)); printf '  FALHA %s (%s)\n' "git for windows sobre UNC: o aviso nao cita safe.directory" "$(printf '%s' "$GFW_SAIDA" | tr '\n' '|')" ;;
  esac
fi
[ -z "${MERGEX_GFW_SAIDA:-}" ] || printf '%s\n' "$GFW_SAIDA" > "$MERGEX_GFW_SAIDA.sem"
if gfw_hook "regressao do falso bloqueio desta maquina: portao valido sobre UNC passa (com safe.directory)" com; then
  case "$GFW_SAIDA" in
    *"barrado"*) FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "git for windows: mensagem de bloqueio num push legitimo" ;;
    *) OK=$((OK+1)); printf '  ok    %s\n' "git for windows sobre UNC: nenhuma mensagem de bloqueio no push legitimo" ;;
  esac
fi
[ -z "${MERGEX_GFW_SAIDA:-}" ] || printf '%s\n' "$GFW_SAIDA" > "$MERGEX_GFW_SAIDA.com"

# Worktree vinculada (.git e arquivo): mesma regra
rm -f .expx/hooks.json
fixture_switch_exato main main || exit 1
git worktree add -q "$WTH_T" feature/ft-02 >/dev/null 2>&1 || exit 1
HOOK_CWD="$WTH_T"
caso "worktree vinculada: portao valido libera"    mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 0
printf 'produto na worktree\n' > "$WTH_T/src/na-worktree.ts"
git -C "$WTH_T" add src/na-worktree.ts && git -C "$WTH_T" commit -qm "feat: produto na worktree" || exit 1
caso "worktree vinculada: portao vencido barra em aviso" mergex/pr-so-com-portao.sh "$(bash_json "$PUSH_FT")" 2
mkdir -p "$WTH_T/.expx"
for MODO_WT in aviso bloqueio; do
  printf '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"%s"}}}\n' "$MODO_WT" > "$WTH_T/.expx/hooks.json"
  caso_aviso "worktree vinculada: git -C . push vencido avisa [$MODO_WT]" "$(bash_json 'git -C . push origin feature/ft-02')"
done
printf '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"desligado"}}}\n' > "$WTH_T/.expx/hooks.json"
caso_calado "worktree vinculada: git -C . push vencido calado [desligado]" "$(bash_json 'git -C . push origin feature/ft-02')"
rm -rf "$WTH_T/.expx"
HOOK_CWD="$HIST_T"
git worktree remove --force "$WTH_T" || exit 1

# Repositorio sem MergeX nunca bloqueia, nem em modo bloqueio
mkdir -p "$SEMX_T/.expx"
printf '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"bloqueio"}}}\n' > "$SEMX_T/.expx/hooks.json"
HOOK_CWD="$SEMX_T"
for C in 'git push' 'git push origin dev' 'git push -u origin dev' 'gh pr create --fill' 'echo push' \
         "sh -c 'git push'" 'git push origin $(git branch --show-current)' \
         '/usr/lib/git-core/git-push origin dev' '"$(git --exec-path)"/git-push origin dev' 'git-send-pack origin refs/heads/dev' \
         'cd -P . && git push origin dev'; do
  caso "sem MergeX em bloqueio: $C" mergex/pr-so-com-portao.sh "$(bash_json "$C")" 0
done
HOOK_CWD="$HIST_T"

cd "$RAIZ_T" || exit 1
HOOK_CWD="$RAIZ_T"

echo
echo "plano task-based ausente/ilegivel — ownership manual falha fechado"
git add -A && git commit -qm "isola cenario de plano invalido"
fixture_switch_exato hook-plano-invalido -c hook-plano-invalido || exit 1
sed -i.bak 's/^branch: .*/branch: hook-plano-invalido/' docs/entregas/exportacao-csv/ENTREGA.md
rm -f docs/entregas/exportacao-csv/ENTREGA.md.bak
MSG_PLANO_INVALIDO='git commit -m "fix(csv): fecha task

Task: T-02.01
Trabalho: exportacao-csv"'
printf 'lixo \x00 nao-yaml' > docs/sprintx/features/exportacao-csv/sprint-01/tasks.md
printf 'mudanca para ownership\n' >> src/a.ts
git add src/a.ts
caso "tasks.md corrompido barra ownership" mergex/commit-por-task.sh "$(bash_json "$MSG_PLANO_INVALIDO")" 2
caso "tasks.md corrompido (escopo)" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -m x')" 0
rm -f docs/sprintx/features/exportacao-csv/sprint-01/tasks.md
caso "tasks.md ausente barra ownership" mergex/commit-por-task.sh "$(bash_json "$MSG_PLANO_INVALIDO")" 2

echo
echo "registro dos hooks — tempo do pr-so-com-portao"
# O hook e consultivo e cabe no proprio orcamento (8 s): o timeout dele volta a
# 10 s, como os demais, nos dois harnesses (sem limite proprio no OpenCode).
valor "settings.json: timeout do pr-so-com-portao e 10" \
  "$(jq -r '.. | objects | select(has("command")) | select(.command | contains("mergex/pr-so-com-portao.sh")) | .timeout' "$REPO_ROOT/.claude/settings.json")" 10
valor "OpenCode: nenhum limite proprio por hook (o pr-so-com-portao fica nos 10 s)" \
  "$(grep -c 'TEMPO_POR_HOOK\|60_000' "$REPO_ROOT/.opencode/plugin/mergex.ts")" 0
valor "OpenCode: limite unico de 10 s" "$(grep -c '^const TEMPO_LIMITE = 10_000$' "$REPO_ROOT/.opencode/plugin/mergex.ts")" 1
valor "hook: orcamento interno de 8 s" "$(grep -c '^ORCAMENTO=8$' "$H/mergex/pr-so-com-portao.sh")" 1

echo
echo "---------------------------------------------"
printf '%d ok, %d falha(s), %d pulado(s)\n' "$OK" "$FALHOU" "$PULADOS"
[ "$PULADOS" = "0" ] || printf 'ATENCAO: %d caso(s) nao foram verificados nesta maquina.\n' "$PULADOS"
# NAO_EXECUTADO nunca conta como ok: fica listado a parte
[ "$NAOEXEC" = "0" ] || printf '%d caso(s) NAO_EXECUTADO (nao contados como ok)\n' "$NAOEXEC"
[ "$FALHOU" = "0" ]
