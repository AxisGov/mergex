# MergeX M2 Lifecycle e Recuperação E1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar executáveis e auditáveis os checkpoints de persistência dos artefatos de método e recuperar com segurança um commit E1 existente cujo SHA não foi registrado em `ENTREGA.commits`.

**Architecture:** Um executor `persistir-metodo.sh` resolve o trabalho por contexto explícito conferido contra `ENTREGA.md`, deriva um catálogo fechado por origem/checkpoint, usa a trava C5 do índice e cria commits de método com gramática própria. O executor E1 ganha `--registrar-existente`, que valida um SHA completo e alcançável, seus trailers e o ownership dos caminhos do commit antes de acrescentá-lo à sequência, sem criar outro commit.

**Tech Stack:** Bash 3.2, Git, awk/sed/grep, jq nos testes dos hooks, fixtures Git temporárias e scripts de mutação shell.

**Spec:** Handoff do usuário “P0.2-C7-B / MERGEX M2 — lifecycle executável dos artefatos de método + recuperação de commit E1 já existente”, complementado pelos sete ajustes aprovados nesta sessão.

## Global Constraints

- Implementar somente M2; não iniciar M3, S1, S2, B1 ou B2.
- Não alterar SprintX nem BuildX.
- Não corrigir a fixture E8/HISTORICO, não adicionar `.gitattributes`, não tratar CRLF/path Git Bash e não escrever runbook de lock órfão.
- A fonte normativa do trabalho é contexto explícito + `ENTREGA.md`; branch serve somente como prova de consistência.
- O mesmo lock C5 por índice/worktree protege E1, recovery e commits de método.
- Stage preexistente sempre para e nunca é limpo ou adotado.
- Caminhos são relativos e exatos; nunca `git add docs/`, `git add -A`, `git add -u` ou busca global por `docs/**`.
- Produto nunca entra em commit de método.
- Commit E1 tem exatamente um `Task:` e um `Trabalho:`, e nenhum `Metodo:`.
- Commit de método tem exatamente um `Trabalho:` e um `Metodo: pre-e2|pre-e6|e8`, e nenhum `Task:`.
- `Task:` + `Metodo:`, trailers duplicados e `Metodo:` fora do enum são inválidos.
- Commit de método não entra em `ENTREGA.commits`, não consome `seq` e não satisfaz V11.
- Checkpoints são retomáveis pela evidência versionada, sem memória ou rastro local, e no-op não cria commit vazio.
- E2 e E6 apenas verificam suas barreiras; não persistem método silenciosamente.
- `--registrar-existente` não cria, altera, move ou reescreve commits.
- Produzir exatamente um commit final: `feat(mergex): persiste metodo e recupera registro e1`.
- Publicar somente `origin/p0.2/mergex-c7b`; nunca upstream e nunca push forçado.

## Review Focus

- Contexto explícito válido mas branch divergente deve parar por inconsistência, sem selecionar outro trabalho pela branch; coberto na Task 3.
- Paths com espaços ou nomes semelhantes a artefatos não podem escapar do catálogo ou contaminar o stage; coberto na Task 3.
- Commit informado por SHA completo mas já registrado por abreviação equivalente deve ser idempotente; coberto na Task 6.
- Commit raiz deve ser lido com `--root`; merge deve ser recusado como não-E1; rename deve submeter origem e destino ao ownership e falhar fechado se qualquer lado não for provado; coberto na Task 6.
- Falha depois do `git add` e antes do commit de método deve preservar o stage e liberar somente a trava da própria execução; coberto na Task 4.

---

### Task 1: Congelar pré-condições e garantir a branch M2

**Files:**
- Read: `.claude/skills/mergex/references/00-abertura.md`
- Read: `.claude/skills/mergex/references/00-schema.md`
- Read: `.claude/skills/mergex/references/10-estado.md`

**Interfaces:**
- Consumes: HEAD M1 `9b64495d14d29d6ccfdbb149ff0632b4dbe01b78` e base C7-A `0cb0eae7079b3e335904e5c8b9eaa57b309ef247`.
- Produces: branch adotada, árvore inicialmente limpa e baseline registrável para o relatório final.

- [ ] **Step 1: Confirmar branch, HEAD, ancestralidade, árvore e decisão final**

Run:

```bash
git branch --show-current
git rev-parse HEAD
git status --porcelain
git merge-base --is-ancestor 0cb0eae7079b3e335904e5c8b9eaa57b309ef247 HEAD
tail -n 3 .claude/skills/mergex/DECISOES-DA-SKILL.md
```

Expected: branch `p0.2/mergex-c7b`, HEAD M1 exato, status vazio, ancestralidade rc 0 e DM-160 por último.

- [ ] **Step 2: Executar E0 por adoção antes da implementação**

Seguir `00-abertura.md` sem trocar ou criar branch; validar a entrega corrente e preservar qualquer registro existente.

- [ ] **Step 3: Rodar a baseline M1**

Run:

```bash
bash .claude/hooks/teste.sh
```

Expected: `89 ok`, `0 falhas`, `0 pulos` com jq disponível.

### Task 2: Formalizar as duas gramáticas de commit

**Files:**
- Create: `.claude/skills/mergex/scripts/contrato-de-commit.sh`
- Modify: `.claude/skills/mergex/scripts/fechamento-do-e1.sh`
- Modify: `.claude/hooks/mergex/commit-por-task.sh`
- Modify: `.claude/hooks/README.md`
- Modify: `.claude/hooks/teste.sh`
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh`

**Interfaces:**
- Consumes: mensagem por arquivo, texto ou `git show -s --format=%B <sha>`.
- Produces: `--validar-e1 <trabalho> <task>` e `--validar-metodo <trabalho> <checkpoint>` com rc 0 válido, rc não zero fail-closed.

- [ ] **Step 1: Escrever testes vermelhos da gramática**

Cobrir: E1 válido; método válido nos três enums; `Task+Metodo`; Task duplicado; Trabalho duplicado; Metodo duplicado; Metodo fora do enum; E1 sem Trabalho; método com Task; E1 com Metodo.

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh grammar
```

Expected: FAIL porque `contrato-de-commit.sh` ainda não existe e o E1 ainda aceita `Metodo:`.

- [ ] **Step 2: Implementar o validador único**

Usar `git interpret-trailers --parse`; contar por chave, comparar valores exatos e recusar classes híbridas. Não inferir classe por assunto.

- [ ] **Step 3: Integrar E1 e hook ao validador**

`fechamento-do-e1.sh` valida mensagem e commit produzido como classe E1. O hook valida mecanicamente commits que declaram `Task:` ou `Metodo:` e não trata método válido como E1.

- [ ] **Step 4: Rodar testes focados**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh grammar
bash .claude/hooks/teste.sh
bash scripts/ci/test-m1-ownership-contextual.sh
```

Expected: todos verdes; baseline histórica preservada e novos casos dos hooks aprovados.

### Task 3: Fixar catálogo fechado e contexto explícito

**Files:**
- Create: `.claude/skills/mergex/scripts/persistir-metodo.sh`
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh`

**Interfaces:**
- Consumes: `--entrega`, `--origem`, `--trabalho`, `--checkpoint` e raiz Git atual.
- Produces: lista relativa, exata, ordenada e sem duplicatas dos caminhos elegíveis e dirty.

- [ ] **Step 1: Escrever testes vermelhos de contexto e catálogo**

Cobrir SprintX canônica e legada, RunX, branch divergente, ENTREGA divergente, outro trabalho, `00-PLANEJAMENTO.md`, catálogo cumulativo, delivery docs, HISTORICO global literal, base indexada, base não indexada, produto com nome parecido e caminho de outro trabalho.

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh catalog
```

Expected: FAIL porque o executor ainda não lista caminhos.

- [ ] **Step 2: Implementar resolução explícita do contexto**

Comparar `--origem` e `--trabalho` com `ENTREGA.expx_tool`, `ENTREGA.trabalho_id`, pasta da entrega e pasta da origem. A branch ativa apenas confere `ENTREGA.branch`; nunca procura ou escolhe trabalho.

- [ ] **Step 3: Implementar catálogo por checkpoint**

SprintX inclui, quando existentes e previstos: `ORQUESTRADOR.md`, `00-BLOQUEIOS.md`, `00-PLANEJAMENTO.md`, `00-AUDITORIA.md`, `00-DECISOES.md`, `00-ESTIMATIVA.md`, `BUILDX-PREMISSAS.md`, `FECHAMENTO.md`, `sprint-NN/tasks.md`, `sprint.md`, `fases.md`, base indexada e `docs/sprintx/estimativas/HISTORICO.md` literal. RunX usa somente seus nomes contratuais. MergeX usa somente `ENTREGA.md`, `ATENCAO.md`, `PR.md` e `QA-PACOTE.md` do trabalho explícito.

- [ ] **Step 4: Filtrar somente caminhos dirty**

Consultar Git com pathspecs exatos derivados do catálogo; preservar produto dirty fora do conjunto e transportar paths em formato NUL-safe, inclusive quando contêm espaços.

- [ ] **Step 5: Rodar testes focados**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh catalog
```

Expected: todos os casos passam sem busca global por `docs/**`.

### Task 4: Implementar os commits idempotentes de método

**Files:**
- Modify: `.claude/skills/mergex/scripts/persistir-metodo.sh`
- Modify: `.claude/skills/mergex/scripts/trava-do-e1.sh` apenas se necessário para nomear dono genérico sem mudar o lock
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh`

**Interfaces:**
- Consumes: catálogo da Task 3, `contrato-de-commit.sh`, lock C5 e gate de segredo existente.
- Produces: `--persistir` e `--verificar`, com saída `commit=<sha>` ou `noop=true`.

- [ ] **Step 1: Escrever testes vermelhos do lifecycle 1–18**

Implementar literalmente os 18 cenários obrigatórios do handoff, incluindo crash/retomada, produto dirty, stage preenchido, segredo, trailers, seq e isolamento entre trabalhos.

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh lifecycle
```

Expected: FAIL antes da implementação do modo persistente.

- [ ] **Step 2: Implementar a seção crítica**

Ordem fixa: lock C5 → stage vazio → contexto → catálogo dirty → no-op ou `git add -- <paths exatos>` → conferir stage exatamente igual → segredo → mensagem canônica → commit → validar HEAD e trailers → conferir que `ENTREGA.commits` e próximo seq não mudaram → liberar lock.

- [ ] **Step 3: Implementar idempotência por estado versionado**

Sem paths elegíveis dirty, retornar no-op. Uma chamada após queda vê a árvore/HEAD atuais; não lê rastro ou memória. `--verificar` exige ausência de método elegível dirty e stage vazio, sem criar commit.

- [ ] **Step 4: Provar preservação em falhas**

Injetar falha de gate e falha de commit; confirmar nenhum commit vazio, produto intocado, stage preservado quando necessário e lock liberado apenas pelo token dono.

- [ ] **Step 5: Rodar testes focados**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh lifecycle
bash scripts/ci/test-trava-e1.sh
```

Expected: lifecycle 1–18 verde e C5 sem regressão.

### Task 5: Tornar pre-e2, pre-e6 e e8 barreiras do fluxo

**Files:**
- Modify: `.claude/skills/mergex/SKILL.md`
- Modify: `.claude/skills/mergex/references/01-commits.md`
- Modify: `.claude/skills/mergex/references/02-prontidao.md`
- Modify: `.claude/skills/mergex/references/06-push.md`
- Modify: `.claude/skills/mergex/references/08-registro.md`
- Modify: `.claude/skills/mergex/references/integracao/sprintx.md`
- Modify: `.claude/skills/mergex/references/integracao/runx.md`
- Modify: `.claude/commands/mergex.md`
- Modify: `.claude/commands/mergex-check.md`
- Modify: `.claude/commands/mergex-pr.md`
- Modify: `scripts/ci/validate-mergex-contract.sh`
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh`

**Interfaces:**
- Consumes: `persistir-metodo.sh --persistir|--verificar`.
- Produces: fluxo explícito `pre-e2 → E2`, `pre-e6 → E6`, e E8 terminal pelo checkpoint `e8`.

- [ ] **Step 1: Escrever testes vermelhos de integração do fluxo**

Conferir que documentos e comandos mandam executar checkpoints; E2/E6 chamam somente a barreira; E8 usa o executor; não resta texto de “pré-E6” manual nem sugestão de E1 tardio incorreta.

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh integration
bash scripts/ci/validate-mergex-contract.sh
```

Expected: FAIL até os references e comandos serem atualizados.

- [ ] **Step 2: Atualizar o fluxo normativo**

Documentar ações explícitas, barreiras fail-closed e retorno bloqueado pelo E8. Não permitir que E2/E6 persistam silenciosamente.

- [ ] **Step 3: Substituir persistência manual do E8**

E8 grava o terminal e chama `persistir-metodo.sh --persistir ... --checkpoint e8`; no caminho entregue mantém a publicação conservadora posterior, e no bloqueado nunca publica.

- [ ] **Step 4: Rodar integração focada**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh integration
bash scripts/ci/validate-mergex-contract.sh
```

Expected: ambas verdes.

### Task 6: Implementar `--registrar-existente`

**Files:**
- Modify: `.claude/skills/mergex/scripts/fechamento-do-e1.sh`
- Modify: `.claude/skills/mergex/references/01-commits.md`
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh`

**Interfaces:**
- Consumes: `--entrega`, `--origem`, `--trabalho`, `--task`, `--sha <40-hex>`.
- Produces: append validado em `ENTREGA.commits`, `seq=<n>`, ou `noop=true`, sem novo commit Git.

- [ ] **Step 1: Escrever testes vermelhos de recovery 19–35**

Implementar literalmente os 17 cenários obrigatórios, mais SHA equivalente abreviado já registrado, commit raiz/rename/merge indeterminável e branch apenas como consistência.

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh recovery
```

Expected: FAIL porque a ação ainda não existe.

- [ ] **Step 2: Adicionar parsing explícito da ação**

Exigir todos os argumentos; recusar SHA fora de `[0-9A-Fa-f]{40}` antes de consultar Git.

- [ ] **Step 3: Implementar provas sob a trava C5**

Ordem: lock → stage vazio → contexto explícito/ENTREGA → branch consistente → `git cat-file -e <sha>^{commit}` → `git merge-base --is-ancestor <sha> HEAD` → exatamente zero ou um pai (merge recusado; raiz lida com `--root`) → gramática E1 no commit sem `Metodo:` → caminhos do commit, incluindo origem e destino de rename → ownership sobre esses caminhos → estado de `ENTREGA.commits`.

- [ ] **Step 4: Implementar conflito e idempotência**

Mesmo objeto Git + mesma task: no-op. Mesmo objeto + outra task: conflito. Outra SHA da mesma task: permitido. Resolver abreviações já registradas contra o objeto informado para não duplicar o mesmo commit.

- [ ] **Step 5: Acrescentar e validar sem persistir método**

Chamar `sequencia-de-commits.sh --acrescentar` e `--validar`; não executar `git add`, `git commit`, amend, reset, rebase ou cherry-pick. Deixar `ENTREGA.md` dirty.

- [ ] **Step 6: Rodar testes focados**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh recovery
bash scripts/ci/test-portao-v11.sh
bash scripts/ci/test-sequencia-commits.sh
bash scripts/ci/test-ownership-task.sh
```

Expected: recovery 19–35 verde; C3/V11, C4 e ownership preservados.

### Task 7: Provar V11 antes, durante e depois do checkpoint

**Files:**
- Modify: `scripts/ci/test-m2-lifecycle-recuperacao.sh`
- Modify: `.claude/skills/mergex/references/02-prontidao.md`

**Interfaces:**
- Consumes: recovery da Task 6 e lifecycle da Task 4.
- Produces: prova do ciclo V11 em worktree e em `git show HEAD`.

- [ ] **Step 1: Construir cenário integrado vermelho**

Criar commit E1 sem registro; provar V11 FALHA; recuperar; provar V11 OK local; executar pre-e2; extrair `ENTREGA.md` do HEAD e provar V11 OK contra evidência commitada.

- [ ] **Step 2: Rodar e corrigir somente integração necessária**

Run:

```bash
bash scripts/ci/test-m2-lifecycle-recuperacao.sh v11
```

Expected: PASS sem segundo commit de produto.

### Task 8: Registrar decisões DM-161+ e fechar o contrato documental

**Files:**
- Modify: `.claude/skills/mergex/DECISOES-DA-SKILL.md`
- Modify: `scripts/ci/validate-mergex-contract.sh`
- Modify: `README.md` somente se a interface pública de instalação/uso exigir

**Interfaces:**
- Consumes: decisões implementadas nas Tasks 2–7.
- Produces: decisões numeradas, contrato validável e ausência de contradições antigas.

- [ ] **Step 1: Escrever validações vermelhas para DM e referências**

Cobrar DM-161 em diante, os três checkpoints, as duas gramáticas, recovery explícito, contexto não selecionado pela branch e `00-PLANEJAMENTO.md` elegível.

- [ ] **Step 2: Documentar decisões sem ampliar escopo**

Registrar cada decisão material e remover somente texto contraditório de M1/M2. Manter M3 explicitamente pendente.

- [ ] **Step 3: Rodar o validador**

Run:

```bash
bash scripts/ci/validate-mergex-contract.sh
```

Expected: PASS.

### Task 9: Construir e matar os 18 mutantes M2

**Files:**
- Create: `scripts/ci/mutacao-m2-lifecycle-recuperacao.sh`
- Modify: `scripts/ci/test-m2-lifecycle-recuperacao.sh` apenas para fortalecer observabilidade quando um mutante sobreviver

**Interfaces:**
- Consumes: executor, recovery, hooks, barriers e V11 implementados.
- Produces: controle verde e 18 mutantes mortos individualmente.

- [ ] **Step 1: Implementar controle obrigatório**

Copiar o repositório para diretório temporário, rodar a bancada M2 sem mutação e exigir sucesso antes de mutar.

- [ ] **Step 2: Implementar mutantes 1–18 do handoff**

Cada mutante deve aplicar uma alteração textual específica, provar que foi aplicada e executar apenas o grupo de teste que observa a propriedade.

- [ ] **Step 3: Rodar a suíte de mutação M2**

Run:

```bash
bash scripts/ci/mutacao-m2-lifecycle-recuperacao.sh
```

Expected: controle PASS; mutantes 1–18 MORTOS; zero sobreviventes e zero erros de aplicação.

### Task 10: Verificação completa e único commit final

**Files:**
- Modify: todos os arquivos M2 declarados nas Tasks 2–9
- Include: `docs/superpowers/plans/2026-09-21-mergex-m2-lifecycle-recuperacao.md`

**Interfaces:**
- Consumes: implementação completa M2.
- Produces: um commit final validado e publicado somente em `origin/p0.2/mergex-c7b`.

- [ ] **Step 1: Rodar suites históricas e M2**

Run:

```bash
bash scripts/ci/test-m1-ownership-contextual.sh
bash scripts/ci/test-integracao-c7a.sh
bash scripts/ci/test-ownership-task.sh
bash scripts/ci/test-portao-v11.sh
bash scripts/ci/test-sequencia-commits.sh
bash scripts/ci/test-trava-e1.sh
bash scripts/ci/test-m2-lifecycle-recuperacao.sh
bash scripts/ci/test-causa-portao.sh
bash scripts/ci/validate-mergex-contract.sh
bash scripts/ci/mutacao-m1-ownership-contextual.sh
bash scripts/ci/mutacao-trava-e1.sh
bash scripts/ci/mutacao-atencao-metodo.sh
bash scripts/ci/mutacao-m2-lifecycle-recuperacao.sh
bash .claude/hooks/teste.sh
```

Expected: todas verdes, hooks com pelo menos a baseline de 89 casos e nenhuma falha/pulo histórico.

- [ ] **Step 2: Rodar verificações estáticas e de segurança**

Run:

```bash
find .claude scripts/ci -name '*.sh' -print0 | xargs -0 -n1 bash -n
git diff --check
git diff --cached --check
git status --short
```

Executar também a varredura de segredo sobre o diff completo, sempre mascarando valores; esperado: nenhum achado.

- [ ] **Step 3: Revisar escopo e índice antes do commit**

Confirmar branch não principal, índice vazio na entrada, nenhum arquivo SprintX/BuildX alterado, nenhuma mudança M3 e todos os arquivos no commit pertencentes ao plano M2.

- [ ] **Step 4: Criar o único commit**

Stage somente os caminhos M2 explícitos e executar:

```bash
git commit -m 'feat(mergex): persiste metodo e recupera registro e1'
```

Expected: exatamente um novo commit desde o HEAD inicial, com o assunto exato.

- [ ] **Step 5: Validar commit e árvore**

Run:

```bash
git log --oneline 9b64495d14d29d6ccfdbb149ff0632b4dbe01b78..HEAD
git status --porcelain
git diff --check 9b64495d14d29d6ccfdbb149ff0632b4dbe01b78..HEAD
```

Expected: um commit M2 e árvore limpa.

- [ ] **Step 6: Publicar somente origin**

Buscar `origin/p0.2/mergex-c7b`, recusar remoto à frente, então executar push normal sem força. Não executar nenhum comando contra upstream.

- [ ] **Step 7: Relatório final e parada**

Responder os 22 itens do handoff, informar qualquer bloqueador remanescente de M3 e parar sem iniciar trabalho adicional.
