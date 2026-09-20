# E1 — COMMIT POR TASK

Você está no E1. Esta etapa roda **durante a execução do trabalho**, uma vez por task, no momento em que a task fecha. Nada é montado no fim.

A mensagem de commit é o **principal ativo de quem for resolver um conflito depois**. Ela precisa dizer a **intenção**, não só o que mudou. Meses depois, num merge difícil, ela é o único contexto que sobrevive.

## Pré-requisitos verificáveis

- O repositório é versionado (`versionado: true` no `ENTREGA.md`). Se não for, o E1 não tem o que fazer: siga sem erro.
- A branch ativa é a branch do trabalho registrada no `ENTREGA.md`. Confira com `git branch --show-current`. Se estiver em outra branch, **não commite**: relate a divergência e pare.
- A branch ativa **não** é a principal. Commit direto na principal é proibido (regra 11).

## O gatilho — quando commitar

Commite **exatamente quando** as três condições forem verdade ao mesmo tempo:

1. Os **dois testes da task** estão escritos (`teste_integracao` e `teste_funcional`) — mais o `teste_regressao`, quando é a primeira task de um `bug` da runx.
2. **Suíte da task: `parcial` ou `verde`.** São os dois registros que sustentam um commit. `parcial` é o subconjunto afetado pela task passando — é assim que a sprintx fecha task, e a suíte inteira é cobrada uma vez, ao fechar a sprint. `verde` é a suíte inteira passando.
3. A task foi marcada `status: concluida` em `tasks.md`, no frontmatter e na prosa.

**Antes disso, não commita.** `suite: vermelha`, `suite: nao_executada`, task `em_andamento`, task `bloqueada`, teste faltando: nenhum commit. Essa é a mesma disciplina que o portão de prontidão (E2) vai cobrar depois — só que aqui ela impede o problema de entrar no histórico.

**O que não muda:** os **dois testes da task continuam obrigatórios**, e `parcial` significa "o que era desta task passou", nunca "passou mais ou menos". A mergex não afrouxa TDD: ela apenas para de exigir, a cada task, uma execução de suíte inteira que a skill de origem cobra no fechamento da sprint — e que o portão (E2, V2) continua verificando.

Um commit por task. **Nunca amontoar tasks distintas** no mesmo commit (regra 3), nem dividir uma task em vários commits temáticos.

## Passo 1 — Selecionar o que entra

Leia em `sprint-NN/tasks.md` o campo `arquivos` da task: `cria` e `altera`. Essa é a **lista declarada**.

**Os dois formatos de sprint da sprintx valem aqui.** As tasks vêm sempre da chave `tasks` — no `kind: plano` (sprint condensada) e no `kind: tasks` (três arquivos) —, com os mesmos campos obrigatórios e o mesmo rigor. O E1 **não exige `sprint.md` nem `fases.md`**: a regra única de leitura está em `references/integracao/sprintx.md`, "Como ler uma sprint da sprintx".

Compare com o que mudou de verdade:

```
git status --porcelain
```

**Regra dura: nunca commitar arquivo fora da lista declarada na task** (regra 4).

### O dono do arquivo é a task que está sendo fechada

No E1 o ownership é **unitário**: dono é a task que fecha agora, e só ela. Um arquivo que mudou cai em **exatamente uma** de quatro situações — e são quatro, não três: a quarta é "mudou, não é da task atual, mas **outra task da feature a declara**", que este contrato não tinha e que apareceu no piloto.

A classificação é **por conjuntos**, nunca por prosa. Título, objetivo, status da task e a ordem em que as tasks aparecem no plano **não entram na conta**:

```
mudou ∩ atual                     → na_task_atual         entra
atual − mudou                     → declarado_nao_mudou   não entra, não é erro
mudou − união(todas as tasks)     → desvio                não entra, é desvio
mudou ∩ (união(outras) − atual)   → arquivo_de_task_irma  não entra, NÃO é desvio
```

| Situação | O que fazer |
|---|---|
| `na_task_atual` — mudou e a task atual declara | **Entra no commit.** Vale **mesmo que outra task também o declare**: a interseção com a atual vence |
| `declarado_nao_mudou` — a task atual declara, mas não mudou | Não entra; não é erro (pode ter sido feito em task anterior) |
| `desvio` — mudou e **nenhuma** task declara | **Não entra.** Registre o desvio e siga — o comportamento de sempre |
| `arquivo_de_task_irma` — mudou e **só outra task** declara | **Não entra, e não é desvio.** Pare o fechamento (ver abaixo) |

Quem classifica é o script da skill, que é o único a conceder as quatro situações:

```
git diff --cached --name-only | \
  bash .claude/skills/mergex/scripts/ownership-da-task.sh --classificar . <T-NN.MM>
```

Ele devolve `<situacao>\t<arquivo>\t<tasks que o declaram>` e sai `0` quando o fechamento pode seguir, `2` quando existe arquivo de task irmã e `1` quando **não deu para determinar o dono**. A task atual é **declarada por quem chama**, nunca adivinhada: sem ela, ou com uma que o plano não conhece, o script recusa responder. Escolher "a primeira task encontrada" inventaria o dono.

Arquivo de **produto** alterado fora da lista declarada de **qualquer** task **continua sendo desvio** de escopo. Não o commite e não o apague: deixe-o na árvore, registre a ocorrência em `docs/entregas/<trabalho_id>/ENTREGA.md` na lista `desvios`, e siga para a próxima task. O E2 vai barrar a entrega por isso, com o arquivo nomeado — e é assim que tem que ser: quem decide o que fazer com aquele arquivo é a pessoa.

### `arquivo_de_task_irma` — o arquivo foi planejado, só que em outra task

Esta é a quarta situação, e ela **não é desvio**: o arquivo está no plano da feature. O que ela diz é outra coisa — que **a execução e o plano não batem**. Para cumprir a task atual foi preciso mudar um arquivo que pertence a uma task irmã, normalmente já fechada e congelada.

O exemplo do piloto: `T-03.01` fechou declarando `tests/ui/cabecalho-topo.test.tsx`; a `T-04.03`, em andamento, não declara esse arquivo — mas, para cumpri-la, o arquivo mudou.

**No caso `arquivo_de_task_irma`, pare o fechamento da task.** E, exatamente:

- **não** dê `git add` no arquivo;
- **não** crie o commit da task como se ela estivesse válida — um commit só com o resto seria um **commit parcial enganoso**, que afirma no histórico que a task fechou com o trabalho que ela tem;
- **não** apague, **não** restaure o conteúdo, **não** faça `stash` e **não** limpe a árvore: a alteração é real e precisa continuar onde está;
- **não** o mova para outra task e **não** o atribua em silêncio à task atual;
- **não** o transforme em desvio.

Se ele **já estiver no índice** quando você chegar aqui, tire-o de lá sem tocar na alteração — `git restore --staged <arquivo>` — e **falhe fechado**: não commite. O `commit-por-task` faz o mesmo mecanicamente, e é a única condição desse hook que barra **mesmo em modo `aviso`** (`.claude/hooks/README.md`).

Depois de o planejamento passar a declarar o arquivo na task atual, o E1 **aceita normalmente** — e a task antiga permanece congelada, ainda declarando o arquivo.

### O que a mergex faz com a condição, e o que ela não faz

A mergex **detecta e nomeia** a condição pelo que ela observa: `arquivo_de_task_irma`. É evidência mecânica, produzida por conjuntos, sem interpretação textual.

Ela **não** grava `00-BLOQUEIOS.md`, **não** cria `B-NN`, **não** replaneja e **não** altera estado nenhum da sprintx. Traduzir esta condição para uma classe de pendência — `defeito_de_plano` — é da **sprintx**, que é dona de bloqueio e de replanejamento. É o mesmo corte de dono que a `causa` do portão já usa: a mergex é dona da observação, a skill de origem é dona da classe (DM-111, DM-117).

### Artefatos de método do próprio trabalho

Nem tudo que muda durante o trabalho é produto. A skill de origem grava o plano, as decisões, os bloqueios e o fechamento; a mergex grava a entrega. Esses **artefatos de método do próprio trabalho** não estão na lista de nenhuma task porque não são trabalho planejado — são o registro dele:

| Caminho | De quem | Alcance |
|---|---|---|
| `docs/sprintx/features/<trabalho_id>/` | sprintx (canônico) | feature-local |
| `docs/<trabalho_id>/` | sprintx (formato antigo) | feature-local |
| `docs/manutencao/<trabalho_id>/` | runx | trabalho |
| `docs/entregas/<trabalho_id>/` | mergex | entrega |
| `docs/sprintx/estimativas/HISTORICO.md` | sprintx | **global** — só quando a origem é a sprintx |

### O artefato global de método da sprintx

`docs/sprintx/estimativas/HISTORICO.md` é a memória de calibração da sprintx: atravessa
trabalhos, é lida por features futuras e **é deliberadamente versionada**. A sprintx **escreve**;
a mergex **versiona** (contrato de origem em `references/06-execucao.md` da sprintx; resumo em
`references/integracao/sprintx.md`).

Ele **não é produto, não pertence a task e não é desvio** — e não deixa de ser método só por
ficar fora da pasta da feature.

**A exceção é exata.** Vale para esse caminho literal, e **somente quando o trabalho é da
sprintx**. Não existe isenção para `docs/sprintx/estimativas/**`, nem para `docs/sprintx/**`, nem
equivalente na runx: qualquer outro arquivo fora da pasta do trabalho continua podendo ser
invasão real de escopo.

**Qual é o trabalho deste commit.** O da **branch ativa**: vale a pasta do trabalho cujo `docs/entregas/<trabalho_id>/ENTREGA.md` declara `branch:` igual à branch corrente, e **exatamente um** `ENTREGA.md` pode declará-la. Zero, dois ou mais, ou HEAD destacado: **nenhuma isenção** — o que não estiver declarado em task volta a ser desvio, que é o comportamento conservador.

A identificação é pela branch e **nunca por recência**. Numa árvore que acumula entregas — `docs/entregas/ft-01/`, `ft-02/`, `ft-03/` no mesmo checkout —, o `ENTREGA.md` tocado por último pode ser de uma feature encerrada semanas atrás; isentar a pasta dele deixaria passar exatamente a invasão de escopo que esta verificação existe para pegar.

Entre a pasta canônica e a legada do mesmo trabalho, **a canônica vence**: quando `docs/sprintx/features/<trabalho_id>/` existe, é ela a pasta do trabalho, e a legada não é isenta. É o mesmo desempate que o E0 usa para localizar o trabalho.

Eles **entram no commit** e **nunca contam como desvio**. Três limites, e nenhum é flexível:

- **Só a pasta deste trabalho.** `docs/` inteiro não é isento: a pasta de **outro** trabalho continua sendo desvio — é assim que se percebe uma feature que invadiu o território de outra.
- **A varredura de segredo (passo 2) roda sobre eles igual.** Plano e decisão também carregam credencial por acidente.
- **Continuam entrando por caminho explícito**, nunca com `git add .`.

### Quando os artefatos de método entram

Três momentos, e só esses três:

**O `HISTORICO.md` não entra no commit de uma task.** A sprintx só o atualiza ao fim do trabalho, e o lugar dele é o commit de artefatos que antecede o push. Se, por uma retomada anormal, ele já estiver sujo durante o E1 de uma task: **não registre como desvio** e **não o inclua no commit da task** — deixe-o para o commit pré-E6. Um commit de task contém a task e o método **daquele** trabalho, não a memória global acumulada.

**1. No commit da task que fechou.** Junto dos arquivos de produto declarados entram os artefatos de método deste trabalho que estiverem sujos naquele momento — a começar pelo `tasks.md` que acabou de marcar a task como `concluida`. No **primeiro** commit do trabalho, é isso que leva ao histórico o que a F1 a F5 produziram (base, decisões, plano, orquestrador, auditoria) e que até ali existia só na árvore — inclusive quando a árvore é um `git worktree` que será removido depois.

**2. Num commit de artefatos de método, imediatamente antes do push (E6).** O fim do trabalho produz o que nenhuma task fecha. Entram, por **caminho explícito**, os que estiverem sujos:

- `FECHAMENTO.md` e os demais artefatos feature-local ainda sujos deste trabalho;
- `docs/entregas/<trabalho_id>/` — `ENTREGA.md`, `PR.md`, `QA-PACOTE.md`, `ATENCAO.md`;
- `docs/sprintx/estimativas/HISTORICO.md`, **quando a origem é a sprintx** e ele está sujo. É o ponto normal de versionamento dele.

Um commit só, no formato do passo 3:

```
chore(entrega): registrar artefatos do trabalho <trabalho_id>

Artefatos de metodo do trabalho; nenhuma alteracao de produto.

Trabalho: <trabalho_id>
```

**3. No fechamento final do E8, depois do push e do PR.** O E6 e o E7 produzem estado que só existe depois deles — `push_feito`, `pr_url`, `pr_estado` —, e o E8 fecha o registro com `estado: entregue`, `entregue_em` e a prosa correspondente. Esse último registro **não pode ficar só na árvore**: quem integra a branch integra commits, nunca arquivo sujo de worktree. O E8 tem um commit próprio para ele, no mesmo formato; o procedimento completo — o que entra, o que nunca entra, a publicação e o que fazer quando ela falha — está em `references/08-registro.md`:

```
chore(entrega): finalizar registro do trabalho <trabalho_id>

Artefatos finais da entrega; nenhuma alteracao de produto.

Trabalho: <trabalho_id>
```

**Commit de artefatos de método não é task**: ele **não entra na lista `commits`** do `ENTREGA.md` — ela é de task, uma por task —, e é registrado na prosa do `ENTREGA.md`.

Isto **não é uma etapa nova**: é o E1, no formato que ele já usa, chamado em outro momento.

**Por que dois commits de método, e não um.** Não é duplicação: eles carregam estados diferentes do mesmo trabalho.

1. **Pré-E6** — leva ao histórico o que precisa existir **antes** da publicação: o `FECHAMENTO.md` da skill de origem e os artefatos da entrega (`ENTREGA.md` como está até ali, `PR.md`, `QA-PACOTE.md`, `ATENCAO.md`). Sem ele, a branch subiria sem a descrição do PR e sem o pacote de QA.
2. **Fechamento final do E8** — leva o estado que só é conhecido **depois** do push e do PR. Adiá-lo para "o próximo commit de artefatos" deixaria a branch publicada apontando para uma versão anterior do registro, e o estado final morreria junto com o worktree que a skill de origem remove.

Nenhum dos dois é task e nenhum dos dois entra na lista `commits`. **Ao retornar do E8, nenhuma atualização final da entrega fica dependendo de um trabalho futuro**: o que a entrega afirma está no commit para o qual a branch aponta.

Adicione **por caminho explícito**, nunca em bloco:

```
git add <caminho-1> <caminho-2> ...
```

Não use `git add .`, `git add -A` nem `git add -u`. Eles arrastam o que não foi declarado.

### Nunca commite

- Amostra de dado real vinda da comparação da legadox (as amostras de caracterização podem conter dado de cliente).
- Arquivo de ambiente, credencial, chave, dump de banco, log de produção.
- Artefato de build ou dependência instalada, salvo quando o repositório versiona isso deliberadamente.

## Passo 2 — Varredura de segredo (obrigatória, a cada commit)

Rode **antes** de cada commit, sobre o que está prestes a ser commitado (regra 5):

```
git diff --cached
```

Procure no conteúdo adicionado:

| Categoria | Sinais |
|---|---|
| Chave de API / token | `api_key`, `apikey`, `secret`, `token`, `bearer `, `authorization:`, sequências longas de base64 ou hex em atribuição literal, prefixos de provedor (`sk-`, `ghp_`, `xox`, `AKIA`, `AIza`) |
| Credencial | `password`, `passwd`, `senha`, `pwd` com valor literal; string de conexão com usuário e senha embutidos (`://usuario:senha@`) |
| Chave privada | `BEGIN RSA PRIVATE KEY`, `BEGIN OPENSSH PRIVATE KEY`, `BEGIN PRIVATE KEY`, `.pem`, `.p12` |
| Dado real de cliente | CPF, CNPJ, e-mail, telefone, cartão, endereço ou nome de pessoa real em fixture, teste, seed ou comentário |

Placeholder óbvio não é segredo: `senha`, `xxx`, `changeme`, `<sua-chave>`, `example.com`, valor de variável de ambiente lido em runtime (`process.env.X`, `os.getenv("X")`). Na dúvida entre placeholder e segredo real, **trate como segredo**.

**Encontrou: aborte o commit.** Não commite parcialmente, não remova o trecho por conta própria.

```
mergex E1 ABORTADO — possível segredo em <arquivo>:<linha>

Trecho: <o padrão encontrado, com o valor MASCARADO — nunca ecoe o segredo>
Categoria: <chave de API | credencial | chave privada | dado real de cliente>

O commit da task <id> não foi feito. Remova o segredo do arquivo (use variável
de ambiente), confirme que ele nunca entrou no histórico, e conclua a task de novo.
```

Desfaça o staging (`git restore --staged <arquivos>`) e siga para a próxima task. A task fica **sem commit** e o E2 vai barrá-la.

**Nunca ecoe o valor do segredo** na saída, no log ou no arquivo de registro: mascare (`sk-...4f2a`).

## Passo 3 — Montar a mensagem

Formato exato:

```
<tipo>(<escopo>): <título da task>

<objetivo da task, uma frase>

Task: <id>
Trabalho: <trabalho_id>
Testes: <o que os dois testes cobrem, resumido>
```

### O tipo

Siga a convenção detectada no repositório (`git log --format=%s -30` mostra se ele usa Conventional Commits ou outra coisa) ou a declarada no `CONVENCOES.md` da stackx. **Convenção do repositório vence** (regra 14).

Na ausência de convenção detectável:

| Origem do trabalho | Tipo |
|---|---|
| sprintx (feature) | `feat` |
| runx `tipo: bug` | `fix` |
| runx demais tipos | `chore` |

### O escopo

O módulo ou área tocada pela task, derivado dos arquivos declarados (a pasta ou o domínio comum a eles). Sem escopo evidente, omita os parênteses: `fix: <título>`.

### O corpo

O `objetivo` da task, literal, uma frase. **Não parafraseie e não invente** — está escrito em `tasks.md` (regra 7).

### O rodapé

- `Task:` o `id` da task (`T-NN.MM`).
- `Trabalho:` o `trabalho_id` (o slug da feature ou o `<OC-ID>-<slug>`).
- `Testes:` uma linha resumindo o que `teste_integracao` e `teste_funcional` cobrem. Quando houver `teste_regressao`, cite-o primeiro: é ele que reproduzia o problema.

### Exemplo

```
fix(fiscal): Corrigir base de cálculo do ICMS-ST com desconto incondicional

Excluir o desconto incondicional da base de ST, conforme a regra vigente.

Task: T-01.02
Trabalho: OC-2026-0184-icms-st-base-desconto
Testes: regressão reproduz a base inflada com desconto; integração valida a nota
fim a fim; funcional confere a base para desconto de 10% sobre item de R$ 100.
```

## Passo 4 — Commitar e registrar

```
git commit -F <arquivo-de-mensagem>
```

Use um arquivo de mensagem (ou `-m` repetido) para preservar as quebras de linha do corpo. Não use `--amend`: reescrever histórico é proibido (regra 11).

Confirme o identificador:

```
git rev-parse --short HEAD
```

Acrescente à lista `commits` do `ENTREGA.md`, com `task` e `commit`, e reescreva `atualizado_em`. Um item por task, na ordem em que fecharam.

### `commits` é histórico de execução, não índice de plano

A regra é **um commit por fechamento de task em cada execução** — não "um `task` id único para sempre". A diferença aparece no replanejamento: o portão barra, a feature volta para o planejamento, o plano é refeito e a F6 roda de novo. Se o plano refeito reaproveitar o mesmo `id` de uma task que já fechou antes, o `ENTREGA.md` que o E0 **retomou** (`00-abertura.md`) ainda tem o item antigo.

- **Nunca apague item antigo** para "corrigir" a lista: ele registra um commit que existe no histórico.
- **Um `task` id pode reaparecer**, desde que o `commit` seja **outro SHA** e a ordem preserve a sequência real dos fechamentos.
- Dois itens com o **mesmo id e o mesmo SHA** são duplicata: não acrescente o segundo.

Isto não muda o schema e não cria campo: `references/00-schema.md` descreve `commits` como "um item por task commitada, na ordem em que fecharam" — uma lista ordenada, sem exigência de id único. Quem lê a lista lê história de execução; quem quer o plano lê `tasks.md`, que é a fonte dele.

Não faça push aqui. Push é E6, e só depois do portão (E2) aprovar.

### Grave o evento no rastro

Acrescente uma linha em `docs/eventos/<trabalho_id>.jsonl`, no formato do
contrato `expx-eventos` v1:

```json
{"ts":"<ISO-8601 UTC>","expx_eventos":1,"trabalho_id":"<id>","ferramenta":"mergex","origem":"skill","evento":"commit_criado","fase":"e1","task":"T-01.02","agente":null,"resultado":"ok","detalhe":"<tipo>(<escopo>): <título>","arquivos":["<caminhos do commit>"]}
```

É com `commit_criado` que o painel mostra, por trabalho, a branch, os commits e
a task de cada um — sem tocar no versionador. **Chave nunca omitida:** valor que
não se aplica é `null`.

O arquivo é append-only e ignorado pelo versionador (é local da máquina de quem
executou). Ninguém o edita à mão.

## Critério de saída

Por task:

- [ ] Só arquivos declarados **na task que fechou** entraram no commit.
- [ ] Nenhum arquivo `arquivo_de_task_irma` foi commitado, apagado ou restaurado.
- [ ] A varredura de segredo rodou sobre o diff em stage e não achou nada.
- [ ] A mensagem tem tipo, escopo, título, objetivo e o rodapé com `Task`, `Trabalho` e `Testes`.
- [ ] O commit existe e seu identificador está no `ENTREGA.md`.
- [ ] A árvore ficou limpa dos arquivos daquela task.

## Quando falha

| Situação | O que fazer |
|---|---|
| `suite: vermelha` ou `nao_executada` | Não commita. A task não fechou de verdade — o E2 vai barrá-la nomeando-a |
| Task sem os dois testes | Não commita. O E2 vai barrá-la |
| Arquivo fora da lista declarada de toda task | Não entra no commit; registra em `desvios`; o E2 barra |
| Arquivo declarado só em task irmã | Não entra e **não é desvio**. Para o fechamento da task, sem commit parcial, sem apagar e sem restaurar. A sprintx decide o replanejamento |
| Dono da task não determinável | Não commita. O script sai `1` e nada é classificado — nunca se infere o dono pela prosa |
| Segredo detectado | Aborta o commit, desfaz o staging, avisa com o valor mascarado |
| Branch errada ou principal | Não commita; relata a divergência e para |
| `git commit` falha (hook, assinatura) | Relata o erro literal do versionador e para; nunca contorna com `--no-verify` |
| Repositório sem versionador | Nada a fazer; segue sem erro |
