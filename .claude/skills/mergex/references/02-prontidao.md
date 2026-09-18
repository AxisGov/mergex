# E2 — PORTÃO DE PRONTIDÃO

Você está no E2. Esta etapa roda **ao fim da execução, antes de qualquer preparação de entrega** — antes do E3, do E4, do E5, do push e do PR.

O portão tem uma função só: **barrar o que não está pronto e explicar o que falta**. Ele nunca maquia, nunca "passa com ressalva", nunca ajusta o trabalho para caber (regra 6). Um portão que deixa passar não é portão.

A saída é binária: `PRONTO` ou `BLOQUEADO`.

## Pré-requisitos verificáveis

- `docs/entregas/<trabalho_id>/ENTREGA.md` existe (o E0 rodou). Se não existir, rode o E0 primeiro (`references/00-abertura.md`) — a branch pode não ter nascido, e o portão precisa saber o que foi commitado.
- O `ORQUESTRADOR.md` e o `tasks.md` do trabalho existem. Sem eles não há o que verificar: relate que o trabalho não está planejado e encerre `BLOQUEADO`.
- A pasta do trabalho é a **mesma** que o E0 encontrou: na sprintx, `docs/sprintx/features/<slug>/` (canônico) e, só quando ele não existe, `docs/<slug>/` (formato antigo); na runx, `docs/manutencao/<OC-ID>-<slug>/`. Nunca misture as duas pastas da sprintx na mesma verificação.

## As dez verificações

Rode **todas**, sempre, mesmo depois de a primeira falhar. O usuário precisa da lista completa do que falta, não do primeiro erro. Verificação que não se aplica ao trabalho é marcada `n/a`, nunca omitida.

### V1 — Task com status diferente de `concluida`

Leia o frontmatter de todo `sprint-NN/tasks.md` do trabalho. Toda task tem que estar `concluida`.

**Os dois formatos de sprint da sprintx valem em V1, V2, V3 e V9.** As tasks vêm sempre da chave `tasks`, no `kind: plano` (condensado) e no `kind: tasks` (três arquivos) — regra única em `references/integracao/sprintx.md`, "Como ler uma sprint da sprintx". O formato nunca muda quais campos existem nem quanto rigor se cobra.

Falha: qualquer task em `pendente`, `em_andamento` ou `bloqueada`. Nomeie cada uma (id e título) e o status atual. Task `bloqueada` aponta o `B-NN` correspondente em `BLOQUEIOS.md`.

### V2 — Task concluída sem registro de suíte que a sustente

Para cada task `concluida`, leia o campo `suite`:

| Valor | Resultado |
|---|---|
| `parcial` | OK — os testes afetados pela task passaram |
| `verde` | OK — a suíte inteira passou |
| `vermelha` | **FALHA** |
| `nao_executada` | **FALHA** — `concluida` sem teste executado é inconsistência do registro |

`parcial` e `verde` são registros válidos, e é assim que a skill de origem trabalha: na task roda o subconjunto afetado, e a suíte inteira é cobrada uma vez, ao fechar a sprint. Reprovar `parcial` aqui obrigaria a skill de origem a escrever `verde` onde ela não rodou a suíte inteira — o portão passaria a premiar registro falso, que é o oposto do que ele existe para fazer.

`vermelha` e `nao_executada` são FALHA. Nomeie a task.

**O trabalho inteiro continua precisando da suíte inteira.** Além do registro por task, procure a **evidência da suíte inteira no fechamento de cada sprint**, onde a skill de origem a registra, com a saída da execução colada. **Onde procurar depende do formato da sprint:**

| Formato | Onde está o fechamento da sprint |
|---|---|
| Três arquivos (`kind: tasks`) | `sprint-NN/sprint.md` e o relatório da F6 |
| Condensado (`kind: plano`) | a chave `sprint` do próprio `sprint-NN/tasks.md` (status e `criterio_saida`) e o relatório da F6 |

**Na sprint condensada, `sprint.md` não existe — e a ausência dele não é aviso nem falha.** Exigir um arquivo que o formato não tem seria barrar plano válido. O que continua sendo cobrado é a evidência da execução, no lugar onde a skill de origem deveria tê-la registrado; ausente, vale a tabela abaixo, sem inventar evidência.

| Estado | Resultado |
|---|---|
| Sprint concluída com a execução registrada e verde | OK |
| Sprint concluída com execução registrada vermelha | **FALHA** — nomeie a sprint |
| Sprint concluída sem nenhum registro de execução | **AVISO**, nomeando a sprint e onde ele deveria estar |

**Nunca reescreva tasks `parcial` para `verde`** para satisfazer esta verificação, e nunca invente a evidência: o que falta nesses casos é a execução, não o registro.

### V3 — Task sem teste de integração ou sem teste funcional

Para cada task, `teste_integracao` e `teste_funcional` têm que existir e não estar vazios.

Falha: campo ausente, vazio, ou preenchido com marcador de template (`{{...}}`, `TODO`, `NÃO DETERMINADO`). Nomeie a task e o campo.

### V4 — Bug da runx cuja primeira task não tem teste de regressão

Aplica-se só quando o trabalho é da runx com `tipo: bug`. A primeira task da primeira fase tem que ter `teste_regressao` preenchido.

Falha: campo ausente ou vazio. Sem teste de regressão não há prova de que o defeito existia — nem de que sumiu.

Nos demais tipos e nos trabalhos da sprintx: `n/a`.

### V5 — QA da runx reprovado, ou ausente quando exigido

Aplica-se só a trabalhos da runx. Leia `docs/manutencao/<OC-ID>-<slug>/QA.md`.

| Estado | Resultado |
|---|---|
| Contém `VEREDITO: APROVADO` | Passa |
| Contém `VEREDITO: REPROVADO` | **Falha.** Liste os achados ALTA: cada um precisa voltar ao E3 da runx |
| Não existe | **Falha**, quando o fluxo da runx já deveria tê-lo produzido (E2–E8 da mergex rodam entre o E4 e o E5 da runx) |

Trabalho da sprintx: `n/a` — a sprintx não tem estágio de QA equivalente; o que ela tem é a auditoria da F5 (V6).

### V6 — Auditoria da sprintx reprovada

Aplica-se só a trabalhos da sprintx. Leia o `00-AUDITORIA.md` na pasta do trabalho, na mesma ordem do E0: `docs/sprintx/features/<slug>/00-AUDITORIA.md` (canônico) e, só se ele não existir, `docs/<slug>/00-AUDITORIA.md` (formato antigo).

Falha: o arquivo existe e **não** contém `VEREDITO: SIM`, ou existe achado de severidade ALTA em aberto. Auditoria reprovada na F5 faz o portão barrar.

Arquivo ausente: aviso, não bloqueio — a execução pode ter vindo de um fluxo que não passou pela F5.

### V7 — Bloqueio aberto que afeta o escopo entregue

Leia os bloqueios na pasta do trabalho: `docs/sprintx/features/<slug>/00-BLOQUEIOS.md` (canônico) ou `docs/<slug>/00-BLOQUEIOS.md` (formato antigo) na sprintx; `BLOQUEIOS.md` na runx.

Falha: bloqueio com `resolvido_em: null` cuja `task` está dentro do escopo entregue. Nomeie o `B-NN`, a task e a descrição.

Bloqueio resolvido, ou aberto sobre task fora do escopo entregue: não barra, mas entra como aviso na saída.

### V8 — Modo legado

Aplica-se só quando `docs/legado/PERFIL.md` existe. Sem ele: `n/a` em todos os itens abaixo.

| Item | Falha quando |
|---|---|
| Raio calculado | Não há raio de impacto registrado para este trabalho |
| Caracterização | Raio MÉDIO ou ALTO sem testes de caracterização registrados |
| Reversão | Não há plano de reversão registrado |
| Orçamento | O orçamento de mudança declarado foi estourado |
| Aprovação humana | Raio ALTO sem aprovação humana registrada |

Cada item falho é uma linha da saída, com o arquivo onde deveria estar.

### V9 — Arquivo alterado fora da lista declarada no plano

Compare o conjunto de arquivos tocados pelos commits do trabalho com a união dos `arquivos.cria` + `arquivos.altera` de todas as tasks.

```
git diff --name-only <branch-base>...HEAD
```

Falha: arquivo de produto no diff que não está declarado em nenhuma task. Nomeie cada um. Some a isso os `desvios` já registrados pelo E1.

Arquivo declarado que não aparece no diff **não** é falha: pode ter sido criado e revertido dentro do escopo, ou já existir como estava.

A união dos `arquivos` sai da chave `tasks`, **nos dois formatos de sprint** (`kind: plano` e `kind: tasks`): o formato do plano nunca muda o que é produto declarado.

**Os artefatos de método do próprio trabalho não são desvio** e não entram nesta conta: a pasta do trabalho (`docs/sprintx/features/<trabalho_id>/`, `docs/<trabalho_id>/` no formato antigo, `docs/manutencao/<trabalho_id>/` na runx) e `docs/entregas/<trabalho_id>/`.

**E, quando a origem é a sprintx, `docs/sprintx/estimativas/HISTORICO.md` também fica fora da conta.** Ele é o artefato global de método da sprintx (`references/integracao/sprintx.md`): não reprova a V9, não entra em `desvios` e não precisa estar declarado em nenhuma task. A exclusão é **exata e cirúrgica** — só esse caminho literal, só na origem sprintx. Nenhum outro arquivo sob `docs/sprintx/estimativas/` é isento, e a runx não ganha isenção equivalente.

**Vale também quando ele já está no histórico da branch.** Numa retomada depois de bloqueio, o `HISTORICO.md` commitado na tentativa anterior aparece em `git diff <branch-base>...HEAD`: continua sendo método, e continua não barrando a V9. A regra não depende de ele estar sujo agora. Eles são o registro do trabalho, não produto, e é o E1 que os commita (`01-commits.md`). A pasta de **outro** trabalho continua sendo desvio, e nomeá-la aqui é justamente como se percebe escopo invadido.

### V10 — Segredo, credencial ou dado real de cliente no diff

**Roda sempre, mesmo quando todo o resto passou** (regra 5). É a única verificação que não pode ser pulada por nenhum motivo.

```
git diff <branch-base>...HEAD
```

Aplique a mesma tabela de sinais do `01-commits.md` (chave de API, credencial, chave privada, dado real de cliente). Falha: qualquer ocorrência, **com o valor mascarado na saída**.

Esta verificação existe em duas camadas de propósito: o E1 impede o segredo de entrar, o E2 pega o que entrou por fora do E1 (commit manual do dev, merge da base, arquivo trazido de outra branch).

**Repositório sem versionador:** V9 e V10 rodam sobre os arquivos declarados nas tasks e sobre a árvore de trabalho, em vez do diff. Não pule nenhuma das duas.

## Formato exato da saída

Use `assets/TEMPLATE-prontidao.md`. Grave em `docs/entregas/<trabalho_id>/` **não** é obrigatório — a saída do portão é para a tela e para o campo `portao` do `ENTREGA.md`.

Cabeçalho, sempre:

```
mergex E2 — PORTÃO DE PRONTIDÃO
Trabalho: <trabalho_id>   Branch: <branch>   Data: <AAAA-MM-DD>

RESULTADO: PRONTO
```

ou

```
RESULTADO: BLOQUEADO
```

Depois, a tabela das dez verificações, todas as linhas, sempre:

```
| # | Verificação | Resultado |
|---|---|---|
| V1 | Tasks concluídas | OK |
| V2 | Registro de suíte por task | FALHA |
...
```

Resultado por verificação: `OK`, `FALHA`, `AVISO` ou `n/a`.

E, para cada `FALHA`, um bloco com **o que falta e onde corrigir**:

```
V2 — FALHA: task fechada sem teste passando
  T-01.03 "Recalcular o rateio por item" — suite: vermelha
  Onde corrigir: docs/manutencao/<OC-ID>-<slug>/sprint-01/tasks.md
  O que fazer: voltar ao E3 da runx, fazer a suíte passar, remarcar a task
```

Avisos vão numa seção própria no fim, sem alterar o resultado.

## Registro das falhas

O portão grava no `ENTREGA.md`, **junto com `portao`**, a lista das verificações que deram `FALHA` — a chave `falhas_portao` (`references/00-schema.md`, "A causa do bloqueio"). É dela, e só dela, que o E8 deriva a `causa` do bloqueio.

- Um item por linha `FALHA` da tabela, com o número da verificação em minúscula: `v1` … `v10`.
- Verificação que **não pôde rodar** — marcada `FALHA` porque ausência de prova não é prova — entra como `vN_sem_prova`, nunca como `vN`. É o que impede que um "não consegui verificar" seja lido depois como um defeito provado.
- `AVISO` e `n/a` não entram. `PRONTO` grava `falhas_portao: []`.
- Na numeração do portão, uma linha só. Monte a lista com o script, que também recusa item desconhecido ou repetido:

```
bash .claude/skills/mergex/scripts/causa-do-portao.sh --lista v7 v1
[v1, v7]
```

O portão **não grava `causa`**: ela continua `null` até o E8 fechar o bloqueio (`references/08-registro.md`). E ele não classifica o motivo pelo conteúdo — o que diz o `B-NN`, de quem é o arquivo fora do escopo, por que a suíte ficou vermelha fica na saída para a pessoa, não no YAML.

## Critério de saída

**`PRONTO`** quando nenhuma verificação deu `FALHA`. Grave `portao: pronto` e `falhas_portao: []` no `ENTREGA.md`, reescreva `atualizado_em`, e siga para o E3.

**`BLOQUEADO`** quando qualquer verificação deu `FALHA`. Grave `portao: bloqueado` e `falhas_portao` com as verificações que falharam no `ENTREGA.md`.

**`BLOQUEADO` encerra as etapas de entrega e segue apenas ao E8 para registrar e persistir o bloqueio.** Não classifique o diff (E3), não monte a descrição do PR (E4), não gere o pacote de QA (E5), não faça push (E6), não abra PR (E7): **nenhuma dessas etapas executa.**

O E8 roda em **fechamento bloqueado** (`references/08-registro.md`): grava `estado: bloqueado`, preserva `portao: bloqueado`, e commita esse registro para que o bloqueio sobreviva ao worktree. Ele **não publica a branch** — o portão proibiu o E6, e o fechamento não fura essa proibição. Ir ao E8 **não é continuar a entrega**: é finalizar e persistir o bloqueio.

O trabalho fica na branch, commitado até onde estava correto. Nada é desfeito, nada é descartado, nada é maquiado.

## Quando falha

| Situação | O que fazer |
|---|---|
| `tasks.md` sem frontmatter | Leia da prosa e registre o aviso; se não for possível determinar o status, é `FALHA` em V1 |
| `QA.md` ausente em trabalho da runx | `FALHA` em V5 — a entrega ainda não passou pelo E4 da runx |
| `PERFIL.md` ausente | V8 inteira é `n/a`; não invente modo legado |
| Sem versionador | V9 e V10 rodam sobre árvore e tasks; as demais não mudam |
| Branch base indisponível para o diff | Use `git diff --name-only HEAD~<n>..HEAD` sobre os commits do trabalho registrados no `ENTREGA.md`; registre a imprecisão como aviso |
| Verificação impossível de rodar | Marque `FALHA`, nunca `OK`, e registre `vN_sem_prova` em `falhas_portao`. Ausência de prova não é prova |
| `ORQUESTRADOR.md` ou `tasks.md` ausente | `BLOQUEADO`: V1 não tem como determinar status — `v1_sem_prova` —, e as demais que dependem do plano também entram `_sem_prova` |
