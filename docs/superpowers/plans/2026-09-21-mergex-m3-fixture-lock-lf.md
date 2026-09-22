# MergeX M3 Fixture, Lock and LF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Endurecer a fixture E8/HISTORICO, formalizar a recuperação humana de lock órfão e garantir LF em scripts shell em checkout Windows e worktree vinculada.

**Architecture:** Um helper exclusivamente de teste torna troca de branch e restauração de tracked fail-closed; o bloco histórico roda em repositório temporário isolado. Uma suíte M3 observa comportamento real de hooks, locks, clones e worktrees, enquanto uma matriz de dez mutantes prova que cada guarda é necessária.

**Tech Stack:** Bash 3.2+, Git, Git Bash, jq, Docker/Linux quando disponível.

**Spec:** `docs/superpowers/specs/2026-09-21-mergex-m3-fixture-lock-lf-design.md`

## Global Constraints

- Criar exatamente um commit final: `fix(mergex): endurece fixture e portabilidade`.
- Não alterar SprintX, BuildX, schema de desvios ou lifecycle M2 por conveniência.
- Não criar PR, não tocar upstream e nunca usar push forçado.
- `.gitattributes` deve conter somente `*.sh text eol=lf`.
- `git add --renormalize -- '*.sh'` precisa produzir diff vazio; caso contrário, parar.
- Recuperação de lock permanece humana, sem `--force-unlock` e sem heurística automática.

## Review Focus

- Um `git switch` que retorna erro enquanto a branch aparente já tem o nome esperado deve falhar pelo retorno.
- Um switch que retorna zero sem efetivamente trocar deve falhar pela conferência da branch.
- Arquivo tracked sujo de um caso não pode atravessar para o próximo caso de branch.
- A exceção do HISTORICO deve valer somente para SprintX e continuar persistível pelo M2.
- Checkout principal e worktree vinculada com `core.autocrlf=true` devem materializar todos os `.sh` em LF real.

---

### Task 1: Helper fail-closed e fixture histórica isolada

**Files:**
- Create: `scripts/ci/lib/fixture-git.sh`
- Modify: `.claude/hooks/teste.sh`
- Create: `scripts/ci/test-m3-fixture-lock-lf.sh`

**Interfaces:**
- Produces: `fixture_switch_exato <branch-esperada> <argumentos de git switch...>` e `fixture_restaurar_tracked <path...>`.
- Consumes: Git CLI e a raiz temporária selecionada por `HOOK_CWD` no gerador JSON da bancada.

- [ ] **Step 1: Escrever RED para retorno, branch e sujeira tracked**

Adicionar à suíte M3 três casos comportamentais: função `git` controlada que devolve `7` no switch mas relata a branch esperada; função que devolve `0` mas relata branch errada; e repositório real em que `fixture_restaurar_tracked` precisa limpar um tracked modificado antes do switch.

- [ ] **Step 2: Executar RED**

Run: `bash scripts/ci/test-m3-fixture-lock-lf.sh fixture`

Expected: FAIL porque `scripts/ci/lib/fixture-git.sh` ainda não existe.

- [ ] **Step 3: Implementar helper mínimo**

```bash
fixture_switch_exato() {
  esperado="$1"; shift
  git switch -q "$@" || return 1
  atual="$(git branch --show-current)" || return 1
  [ "$atual" = "$esperado" ] || return 1
}

fixture_restaurar_tracked() {
  git reset -q || return 1
  [ "$#" -eq 0 ] || git restore --worktree -- "$@"
}
```

- [ ] **Step 4: Isolar o bloco E8/HISTORICO**

Criar uma segunda raiz temporária na bancada de hooks, inicializar somente os artefatos SprintX/RunX necessários, apontar `HOOK_CWD` para ela e substituir todos os `git switch` da fixture por `fixture_switch_exato`. Restaurar explicitamente os tracked do cenário antes de cada troca e conferir que o caso HISTORICO roda em `feature/ft-02`.

- [ ] **Step 5: Executar GREEN**

Run: `bash scripts/ci/test-m3-fixture-lock-lf.sh fixture`

Expected: todos os casos do grupo passam; falha de switch encerra imediatamente.

### Task 2: Política LF, clone autocrlf e worktree vinculada

**Files:**
- Create: `.gitattributes`
- Modify: `scripts/ci/test-m3-fixture-lock-lf.sh`

**Interfaces:**
- Produces: política Git `*.sh text eol=lf` e grupo `lf` da suíte M3.
- Consumes: lista literal de scripts rastreados obtida por `git ls-files -z -- '*.sh'`.

- [ ] **Step 1: Escrever RED do clone e worktree**

Montar repositório-fonte temporário com os arquivos correntes, commitá-lo como fixture, clonar com `-c core.autocrlf=true`, criar worktree vinculada e exigir em ambos:

```text
i/lf w/lf attr/text eol=lf
```

Para cada `.sh`, procurar byte `\r` e comparar a primeira linha literalmente com `#!/usr/bin/env bash`.

- [ ] **Step 2: Executar RED sem `.gitattributes`**

Run: `bash scripts/ci/test-m3-fixture-lock-lf.sh lf`

Expected: FAIL por `w/crlf` ou atributo ausente.

- [ ] **Step 3: Adicionar política mínima**

```gitattributes
*.sh text eol=lf
```

- [ ] **Step 4: Provar ausência de renormalização de blobs**

Run: `git add --renormalize -- '*.sh'`

Expected: `git diff --cached --name-only -- '*.sh'` vazio. Se não estiver vazio, parar sem prosseguir.

- [ ] **Step 5: Executar GREEN**

Run: `bash scripts/ci/test-m3-fixture-lock-lf.sh lf`

Expected: clone principal e worktree vinculada passam EOL, bytes e shebang.

### Task 3: Runbook humano e invariantes do lock

**Files:**
- Modify: `.claude/skills/mergex/references/01-commits.md`
- Modify: `scripts/ci/test-trava-e1.sh`
- Modify: `scripts/ci/validate-mergex-contract.sh`
- Modify: `scripts/ci/test-m3-fixture-lock-lf.sh`

**Interfaces:**
- Consumes: `trava-do-e1.sh --status`, `--liberar <token>` e lock localizado por `--caminho`.
- Produces: runbook humano canônico sem nova opção de produção.

- [ ] **Step 1: Escrever RED das invariantes**

Na fixture real, adquirir/criar lock, preservar o arquivo `dono`, rodar `--status`, tentar token errado, preparar stage e tentar novo E1. Exigir lock e stage byte a byte inalterados. O validador deve recusar qualquer `--force-unlock`, remoção por idade/PID ou glob no procedimento.

- [ ] **Step 2: Executar RED do contrato**

Run: `bash scripts/ci/test-m3-fixture-lock-lf.sh lock && bash scripts/ci/validate-mergex-contract.sh`

Expected: FAIL porque o runbook completo ainda não existe.

- [ ] **Step 3: Documentar procedimento humano**

Adicionar em `references/01-commits.md` uma seção numerada que exige `--status`, caminho exato, conferência de worktree/índice/task/pid/instante, ausência de E1 vivo, `git status --porcelain`, `git diff --cached --name-status`, parada com stage não vazio, remoção literal somente depois da prova, proibição de glob/diretório Git comum, novo `--status` e stage vazio no E1 seguinte.

- [ ] **Step 4: Executar GREEN**

Run: `bash scripts/ci/test-trava-e1.sh E EXTRA && bash scripts/ci/test-m3-fixture-lock-lf.sh lock && bash scripts/ci/validate-mergex-contract.sh`

Expected: todos passam; nenhuma função de produção remove lock alheio.

### Task 4: Decisões e matriz de dez mutantes

**Files:**
- Modify: `.claude/skills/mergex/DECISOES-DA-SKILL.md`
- Create: `scripts/ci/mutacao-m3-fixture-lock-lf.sh`
- Modify: `scripts/ci/validate-mergex-contract.sh`

**Interfaces:**
- Produces: `DM-169`, `DM-170` e mutantes M1–M10 com controle sem mutação.
- Consumes: grupos `fixture`, `historico`, `lock`, `lf` da suíte M3 e o validador estrutural.

- [ ] **Step 1: Adicionar decisões mínimas**

Registrar `DM-169` para LF obrigatório em `.sh` e `DM-170` para recuperação humana de lock órfão.

- [ ] **Step 2: Implementar mutantes dirigidos**

Criar cópias temporárias e aplicar exatamente: `switch || true`; remoção da conferência de branch; restauração tracked inoperante; HISTORICO como desvio; exclusão de `.gitattributes`; troca por `*.sh text`; auto-remove de lock velho; auto-remove com stage; glob no runbook; remoção do scan de CRLF.

- [ ] **Step 3: Executar controle e mutantes**

Run: `bash scripts/ci/mutacao-m3-fixture-lock-lf.sh`

Expected: controle verde e `10 morta(s), 0 viva(s), 0 erro(s)`.

### Task 5: Regressão multiplataforma e entrega única

**Files:**
- Verify: todos os arquivos M3 acima e todo o contrato MergeX.

**Interfaces:**
- Consumes: Git Bash atual, container Linux já disponível e WSL somente se disponível.
- Produces: um commit e um push fast-forward somente para origin.

- [ ] **Step 1: Reexecutar regressão obrigatória**

Executar M1, M2, C7-A, V11, seq, C5/lock, causa, hooks completos com jq e contrato. Exigir hooks `94/94`, zero falhas e zero pulos.

- [ ] **Step 2: Executar ambientes**

Rodar suíte M3 e regressão essencial em Git Bash e em container Linux com Bash+jq já disponível. Consultar WSL; registrar indisponível sem instalar nada se não responder.

- [ ] **Step 3: Verificações finais**

Executar `bash -n` em todos os `.sh`, `git diff --check`, gate de segredo, `git status`, `git ls-files --eol -- '*.sh'` e o ensaio de renormalização. Confirmar ausência de mudança SprintX/BuildX e árvore pronta para um único commit.

- [ ] **Step 4: Criar o único commit**

```bash
git commit -m "fix(mergex): endurece fixture e portabilidade"
```

- [ ] **Step 5: Publicar somente origin**

Buscar `origin/p0.2/mergex-c7b`, provar fast-forward, executar push normal sem upstream/force e confirmar o SHA remoto igual ao local.
