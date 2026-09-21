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

## A seção crítica do E1

O E1 escreve em quatro recursos: o **índice** Git, o **HEAD**, a lista `ENTREGA.commits` e o **próximo `seq`**. Nenhum deles é da task — todos são da **worktree**. Duas execuções do E1 na mesma worktree compartilham os quatro, e sem exclusão mútua esta sequência é possível, silenciosa e destrutiva:

```
E1-A faz git add dos arquivos dele
E1-B enxerga o stage de A e acrescenta os arquivos dele
E1-A commita a mistura
E1-B lê o HEAD que A produziu
A e B calculam o mesmo próximo seq
```

A C4 fez o **resultado** disso — lista com `seq` duplicado — parar como contrato inválido (`00-schema.md`, "A ordem de registro"). O que segue impede que o estado seja **criado**.

**O índice Git é recurso de DONO ÚNICO durante o E1.** Na mesma worktree, dois E1 nunca executam ao mesmo tempo. A execução das tasks pode ser paralela; o **fechamento** delas é serial.

### O recurso travado é o índice, nunca o repositório

Worktrees diferentes têm **índices independentes** e fecham tasks em paralelo, sem se bloquear. A trava é do índice daquela worktree, e fica em área **não versionada**, colada nele:

```
<git-path do index>.mergex-e1.lock
```

`.git` **pode ser um ARQUIVO** — é o que a sprintx produz ao abrir a feature em `git worktree` próprio. **Nunca use `[ -d .git ]`.** Quem responde onde está o índice é o versionador:

```
git rev-parse --git-path index
```

Trava no **diretório Git comum** é proibida: ela serializaria o repositório inteiro, e duas worktrees nunca podem bloquear uma à outra.

O mecanismo é o `mkdir` atômico de um diretório. Ele existe igual em Linux, macOS, Windows e Git Bash; `flock` não. O conteúdo da trava — task, pid, instante, raiz, índice — é **diagnóstico**: quem exclui é o diretório, e quem autoriza a liberação é o **token** que a aquisição imprimiu. A correção nunca depende da prosa lá dentro.

### A ordem de aquisição

1. Resolver a worktree e o índice.
2. **Adquirir a trava do E1** — antes do primeiro `git add`.
3. Conferir o stage de entrada.
4. Resolver origem/trabalho pela `ENTREGA.md` corrente e validar os footers.
5. **Verificar o ownership unitário da task** (abaixo) — ainda antes do primeiro `git add`.
6. Só então: staging, verificações, commit, validação do commit produzido e registro.

**Travar depois de montar o stage é não travar**: a mistura já teria acontecido.

### Trava já existente: PARE

Outro E1 tem a seção crítica, ou sobrou uma trava órfã. Nos dois casos, o comportamento é o mesmo:

- **Pare e falhe fechado.** Não espere indefinidamente.
- **Não remova a trava automaticamente.** PID pode ter sido reutilizado, o ambiente pode ser outro, o stage pode estar preparado pela metade. "A trava parece velha" não é prova de nada.
- **Não mate outro processo** e **não toque no índice**.

Recuperação automática de queda não é requisito: o diagnóstico é `trava-do-e1.sh --status`, que **nunca remove nada**, e a decisão sobre uma trava órfã é humana.

### O stage na entrada

**Stage já não vazio antes de o E1 preparar qualquer coisa: PARE.** Não importa se o que está lá parece ser da task atual — não existe prova durável de que este E1 o preparou.

Nada de `git reset`, `git restore --staged`, `git stash`, limpeza ou commit do que se encontrou. **Deixe exatamente como estava**, e mostre os caminhos staged no relatório.

Working tree suja **não** é este caso: artefato e desvio são assunto do E1 (lista declarada) e do E2. Aqui o assunto é o **índice**.

### O que a seção cobre

A trava permanece adquirida durante o trecho inteiro:

| | Passo |
|---|---|
| *(antes de A)* | contexto + footers; depois ownership unitário — `desvio` ou `arquivo_de_task_irma` param aqui, sem que A rode |
| A | staging da task |
| B | verificação do diff em stage |
| C | verificações do E1 aplicáveis (a varredura de segredo do passo 2) |
| D | `git commit` |
| E | validação dos footers no commit produzido |
| F | captura do identificador produzido |
| G | `sequencia-de-commits.sh --acrescentar` |
| H | validação da lista final |

**Só depois de H a trava é liberada.** A atribuição do `seq` acontece **dentro** da seção — é isso, e só isso, que impede duas sessões de calcularem o mesmo próximo número.

### O executável

A seção crítica não é procedimento de prosa: é o `scripts/fechamento-do-e1.sh`, e o E1 passa por ele.

```
bash .claude/skills/mergex/scripts/fechamento-do-e1.sh --fechar \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md \
  --task <id da task> \
  --mensagem <arquivo com a mensagem do passo 3> \
  -- <caminho-1> <caminho-2> ...
```

Ele recusa `.`, `-A` e `-u`: o staging continua sendo por caminho explícito.

**A varredura de segredo (passo 2) é julgamento, e roda DENTRO da seção** — ela lê `git diff --cached`, que só existe depois do staging. Para isso a seção abre em dois tempos, com a mesma trava atravessando os dois:

```
bash .../fechamento-do-e1.sh --preparar --entrega <ENTREGA.md> \
  --task <id> --mensagem <arquivo> -- <caminho-1> ...
# imprime token=<...>; a trava CONTINUA adquirida
# → varredura de segredo sobre `git diff --cached`
bash .../fechamento-do-e1.sh --concluir --entrega <ENTREGA.md> \
  --task <id> --mensagem <arquivo> --token <token>
```

O `--preparar` vincula `origem`, `trabalho_id` e `task` ao dono da seção. O
`--concluir` exige o mesmo trio e reclassifica o stage já preparado contra o
plano corrente antes do commit. O token sozinho não autoriza trocar de trabalho
nem aproveitar um id de task repetido em outra feature.

Achou segredo entre os dois tempos: **não conclua**. Aborte como manda o passo 2, e libere a seção (`trava-do-e1.sh --liberar <token>`) — a task fica sem commit e a V11 do E2 a nomeia.

| Código | Desfecho |
|---|---|
| 0 | seção concluída: commit criado, item registrado, lista válida, trava liberada |
| 2 | **E1 OCUPADO** — outro E1 tem a seção crítica deste índice; o índice não foi tocado |
| 3 | o índice já tinha conteúdo em stage na entrada; nada foi limpo |
| 4 | verificação reprovou **antes** do commit; nenhum commit foi criado |
| 5 | `git commit` falhou; **nenhum** registro de E1 foi escrito |
| 6 | **commit Git existe; registro E1 não foi concluído** |
| 7 | o commit e o item existem e a lista final não valida |
| 8 | `arquivo_de_task_irma` — arquivo planejado em outra task da feature; nenhum `git add` ocorreu; trava liberada |
| 9 | ownership não determinável (plano legado, task fora do formato); nenhum `git add` ocorreu |
| 10 | `desvio` — arquivo fora de todas as tasks do trabalho corrente; nenhum `git add` ocorreu |

### Liberação

Saída normal libera. Falha antes de qualquer staging libera. Falha depois de staging ou commit parcial **não faz limpeza destrutiva**: o stage e o commit ficam onde estão, para diagnóstico, e a trava sai porque quem protege o estado dali em diante é a regra do stage de entrada — o próximo E1 vai encontrá-lo e parar.

**A trava nunca fica presa por uma saída normal conhecida**, e nenhuma execução remove a trava de outra: `--liberar` exige o token do dono.

### Commit feito e registro não concluído

Se o `git commit` aconteceu e o append em `ENTREGA.commits` falhou:

**NÃO crie um segundo commit.** Não faça retry destrutivo, não reverta, não reescreva o histórico. Pare e relate exatamente isto:

```
commit Git existe; registro E1 não foi concluído
```

O commit é real e fica. A **V11** do portão (E2) existe justamente para detectar task concluída sem prova de E1 registrada, e vai nomear a task. O conserto é o **E1 tardio**, depois que a causa do append estiver resolvida.

### Detecção no ato

Ainda sob a trava, depois do `--acrescentar`, a lista é validada de novo. `seq` duplicado, buraco, regressão ou mistura legado/moderna inválida: **PARE**. Não renumere e não escolha outro número para caber — é a mesma regra do `00-schema.md`. Sob a seção crítica isso não deve acontecer; é guarda de integridade.

### O rastro não é o mutex

`docs/eventos/<trabalho_id>.jsonl` pode registrar `e1_iniciado`, `e1_concluido` e `e1_recusado_por_lock`, mas ele é local da máquina, append-only e não versionado. **A verdade da exclusão mútua é a trava do índice**, nunca o JSONL.

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
| `desvio` — mudou e **nenhuma** task declara | **Não entra. Pare o fechamento inteiro**, sem commit parcial; preserve a alteração na árvore |
| `arquivo_de_task_irma` — mudou e **só outra task** declara | **Não entra, e não é desvio.** Pare o fechamento (ver abaixo) |

Quem classifica é o script da skill, que é o único a conceder as quatro situações:

```
git status --porcelain | sed 's/^...//' | \
  bash .claude/skills/mergex/scripts/ownership-da-task.sh --classificar \
    . <sprintx|runx|n/a> <trabalho_id> <T-NN.MM>
```

Ele devolve `<situacao>\t<arquivo>\t<tasks que o declaram>` e sai `0` quando a classificação terminou, `2` quando existe arquivo de task irmã e `1` quando **não deu para determinar o dono**. `ownership=n/a` só existe quando o chamador declara explicitamente a aplicabilidade `n/a`; falta de plano nunca significa n/a. Esse valor é um sinal da interface do classificador, **não** um novo valor persistido de `ENTREGA.expx_tool`: o schema vivo continua aceitando apenas `sprintx|runx`, e ambos são task-based no E1.

Origem, `trabalho_id` e task são declarados por quem chama. No E1, `--task` é a fonte normativa da task; `expx_tool` e `trabalho_id` vêm da `ENTREGA.md` corrente. O script resolve **uma pasta apenas**: `docs/sprintx/features/<trabalho_id>/` (com o fallback legado do mesmo trabalho) ou `docs/manutencao/<trabalho_id>/`. Nenhum `find "$RAIZ/docs" ... tasks.md` global participa. Se a origem usa tasks e o plano corrente está ausente ou ilegível, falha fechado. Se o classificador está ausente, é instalação MergeX incompleta e o E1 também para.

IDs de task não são globais. Uma feature histórica e a corrente podem ter ambas `T-01.01`; somente os `tasks.md` dentro da pasta resolvida para o trabalho corrente entram nos conjuntos. Ordem alfabética de pastas e ordem das features nunca selecionam plano.

Arquivo de **produto** alterado fora da lista declarada de **qualquer** task **continua sendo desvio** de escopo. Não o commite e não o apague: deixe-o na árvore. No caminho normativo, o desvio para o fechamento antes do staging; nenhum subconjunto da task vira commit parcial enganoso. O lifecycle posterior decide o registro/encaminhamento — o E1 não apaga, restaura nem guarda a alteração.

### `arquivo_de_task_irma` — o arquivo foi planejado, só que em outra task

Esta é a quarta situação, e ela **não é desvio**: o arquivo está no plano da feature. O que ela diz é outra coisa — que **a execução e o plano não batem**. Para cumprir a task atual foi preciso mudar um arquivo que pertence a uma task irmã, normalmente já fechada e congelada.

O exemplo do piloto: `T-03.01` fechou declarando `tests/ui/cabecalho-topo.test.tsx`; a `T-04.03`, em andamento, não declara esse arquivo — mas, para cumpri-la, o arquivo mudou.

**No caso `arquivo_de_task_irma`, pare o fechamento da task.** E, exatamente:

- **não** dê `git add` no arquivo;
- **não** crie o commit da task como se ela estivesse válida — um commit só com o resto seria um **commit parcial enganoso**, que afirma no histórico que a task fechou com o trabalho que ela tem;
- **não** apague, **não** restaure o conteúdo, **não** faça `stash` e **não** limpe a árvore: a alteração é real e precisa continuar onde está;
- **não** o mova para outra task e **não** o atribua em silêncio à task atual;
- **não** o transforme em desvio.

Pelo caminho normal — `fechamento-do-e1.sh` —, o arquivo **nunca chega a entrar no índice**: o ownership roda antes do primeiro `git add` (passo 4 da seção crítica, acima), e a condição estruturada `arquivo_de_task_irma` para o fechamento ali, com a trava liberada e nada adicionado.

Se alguém rodar `git add` e `git commit` por fora do script — pulando a seção crítica —, o hook `commit-por-task` classifica o mesmo `git diff --cached` com o mesmo `ownership-da-task.sh` e barra **mesmo em modo `aviso`**, a única condição desse hook que faz isso (`.claude/hooks/README.md`). Nesse caminho manual o arquivo pode ter chegado ao índice antes da barreira: tire-o de lá sem tocar na alteração — `git restore --staged <arquivo>` — e não commite. É defesa em profundidade sobre o caminho normal, nunca uma segunda implementação da regra: as duas chamadas classificam pelo mesmo `ownership-da-task.sh`.

Depois de o planejamento passar a declarar o arquivo na task atual, o E1 **aceita normalmente** — e a task antiga permanece congelada, ainda declarando o arquivo.

### O que a mergex faz com a condição, e o que ela não faz

A mergex **detecta e nomeia** a condição pelo que ela observa: `arquivo_de_task_irma`. É evidência mecânica, produzida por conjuntos, sem interpretação textual.

Ela **não** grava `00-BLOQUEIOS.md`, **não** cria `B-NN`, **não** replaneja e **não** altera estado nenhum da sprintx. Traduzir esta condição para uma classe de pendência — `defeito_de_plano` — é da **sprintx**, que é dona de bloqueio e de replanejamento. É o mesmo corte de dono que a `causa` do portão já usa: a mergex é dona da observação, a skill de origem é dona da classe (DM-111, DM-147).

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

**Este `git add` é o começo da seção crítica**, e não acontece fora dela: quem o executa é o `fechamento-do-e1.sh`, depois de adquirir a trava do índice e de conferir o stage de entrada.

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

Desfaça o staging (`git restore --staged <arquivos>`) e siga para a próxima task. A task fica **sem commit** e o E2 vai barrá-la — na **V11**, que é quem cruza task `concluida` com `ENTREGA.commits` (`references/02-prontidao.md`). Sem a V11 essa promessa não se cumpriria: a task continua `concluida`, com suíte e testes em ordem, e nenhuma outra verificação olha se a prova de E1 existe.

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

No E1 normativo, **`--task` seleciona a task**. O rodapé não seleciona nada: é prova durável e assertiva do contexto explícito. Antes de qualquer staging, a estrutura que será usada precisa conter exatamente um `Task:` e exatamente um `Trabalho:`; os valores precisam ser iguais, respectivamente, a `--task` e ao `trabalho_id` da `ENTREGA.md` corrente. Ausência, duplicata ou divergência para. Não se infere valor pelo título, corpo ou outra prosa.

Depois de `git commit`, e ainda sob a trava, o E1 lê a mensagem do commit produzido e valida os mesmos dois footers novamente antes de escrever `ENTREGA.commits`. A validação prévia impede o commit inválido; a posterior prova que o objeto criado preservou a estrutura validada.

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

Acrescente à lista `commits` do `ENTREGA.md` e reescreva `atualizado_em`. Um item por task, na ordem em que fecharam.

### O item leva `seq` — a chave de ordem

O item novo tem **três** chaves, e `seq` vem primeiro:

```yaml
commits:
  - seq: 15
    task: T-04.03
    commit: 9f3c1aa
```

`seq` é a **ordem de registro do E1**: inteiro positivo, monotônico, **global à ENTREGA**. Não é número de task, de sprint, de rodada da F5, nem timestamp, nem quantidade de commits da branch. O contrato inteiro — progressão, prefixo legado, invariante — está em `references/00-schema.md`, "A ordem de registro".

**Não escreva o item à mão.** O escritor canônico é o `scripts/sequencia-de-commits.sh`: ele lê a lista, valida a sequência, calcula o próximo número e acrescenta o item no fim.

```
bash .claude/skills/mergex/scripts/sequencia-de-commits.sh --acrescentar \
  docs/entregas/<trabalho_id>/ENTREGA.md <id da task> <identificador curto>
```

Ele imprime `seq=<n>` e **só** mexe na lista `commits` — `atualizado_em` continua sendo desta etapa.

**`--acrescentar` é gravação, e gravação nova do E1 só acontece sob a seção crítica** — é o `fechamento-do-e1.sh` que o chama, entre o commit e a validação final, com a trava do índice adquirida. Um segundo escritor real fora dela devolveria a corrida que a seção existe para impedir. **Leitura não trava nada**: `--ler`, `--validar` e `--proximo` continuam funcionando a qualquer momento, inclusive com a seção ocupada.

| Situação | O que o escritor faz |
|---|---|
| `commits: []` (entrega nova) | grava o primeiro item com `seq: 1` |
| Lista com N itens válidos | grava `seq: N+1`, no **fim** |
| Prefixo legado com N itens sem `seq` | grava `seq: N+1`; **não** acrescenta `seq` aos legados |
| Sequência quebrada (duplicata, buraco, regressão, legado depois de `seq`) | **não grava nada** e relata o motivo |
| `commit` que não é identificador válido, ou task vazia | **não grava nada** |

**Gravação nova nunca cria item sem `seq`.** Leitura histórica aceita o prefixo legado; escrita, não. E **nunca faça backfill**: item legado não ganha `seq` retroativo, nem "para deixar a lista uniforme".

**Sequência quebrada PARA.** É violação de contrato do `ENTREGA.md`, não causa de negócio do portão: não vira `indeterminada`, não entra em `falhas_portao` e não se conserta escolhendo outro número. Relate e pare.

### `commits` é histórico de execução, não índice de plano

A regra é **um commit por fechamento de task em cada execução** — não "um `task` id único para sempre". A diferença aparece no replanejamento: o portão barra, a feature volta para o planejamento, o plano é refeito e a F6 roda de novo. Se o plano refeito reaproveitar o mesmo `id` de uma task que já fechou antes, o `ENTREGA.md` que o E0 **retomou** (`00-abertura.md`) ainda tem o item antigo.

- **Nunca apague item antigo** para "corrigir" a lista: ele registra um commit que existe no histórico.
- **Um `task` id pode reaparecer**, desde que o `commit` seja **outro SHA** e a ordem preserve a sequência real dos fechamentos.
- Dois itens com o **mesmo id e o mesmo SHA** são duplicata: não acrescente o segundo.

Isto não muda o schema e não cria campo: `references/00-schema.md` descreve `commits` como "um item por task commitada, na ordem em que fecharam" — uma lista ordenada, sem exigência de id único. **A chave `seq` não muda isso**: ela dá identidade à ordem, e continua não exigindo que cada `task` apareça uma vez só (`00-schema.md`, "A ordem de registro"). Quem lê a lista lê história de execução; quem quer o plano lê `tasks.md`, que é a fonte dele.

### O E1 tardio

Uma task pode ter fechado sem que o commit acontecesse: segredo detectado na varredura, branch errada, hook do versionador, falha operacional. O E2 barra isso na **V11** — task `concluida` sem item em `commits` —, e o conserto é rodar o **E1 tardio**: o mesmo E1, no mesmo formato, no momento em que a lacuna aparece.

- Rode o E1 normalmente para aquela task: selecione o que entra, varra segredo, monte a mensagem, commite.
- **Acrescente** o item `{seq, task, commit}` ao fim de `commits`, pelo mesmo escritor. **Não reordene** os itens antigos e não reescreva SHA nenhum: a lista é a sequência real dos fechamentos, e o commit tardio fechou agora.
- Rode a V11 de novo. Com a prova registrada, ela passa.

**O E1 tardio recebe SEMPRE o próximo `seq` global** — nunca um número "reservado" na posição lógica da task. `seq` registra **quando o E1 aconteceu**, não a ordem numérica das tasks:

```yaml
commits:
  - seq: 1
    task: T-01.01
    commit: aaa1111
  - seq: 2
    task: T-01.03
    commit: bbb2222
  - seq: 3          # E1 tardio: fechou agora, entra agora
    task: T-01.02
    commit: ccc3333
```

Inserir `T-01.02` "entre" os dois primeiros renumeraria itens já gravados e apagaria o fato de que aquele commit só existiu depois — exatamente o que a chave de ordem existe para preservar.

O E1 tardio **continua sendo permitido** e não é exceção ao contrato: é o E1 rodando no momento em que deveria ter rodado. O que nunca é permitido é inventar o item sem o commit — um `commit` que não existe não é prova, e a V11 recusa identificador malformado justamente para isso.

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

- [ ] A trava do índice foi adquirida **antes** do primeiro `git add` e liberada só depois da validação da lista.
- [ ] O stage estava vazio na entrada (e, se não estava, o E1 parou sem tocá-lo).
- [ ] Origem/trabalho vieram da `ENTREGA.md` corrente; a task veio de `--task`.
- [ ] A mensagem tinha exatamente um `Task:` e um `Trabalho:`, ambos correspondentes, antes do staging; o commit produzido foi validado de novo.
- [ ] O ownership da task rodou **antes** do primeiro `git add`, dentro da seção crítica.
- [ ] Só arquivos declarados **na task que fechou** entraram no commit.
- [ ] Nenhum `desvio` produziu commit parcial; a alteração ficou preservada na árvore.
- [ ] Nenhum arquivo `arquivo_de_task_irma` foi commitado, apagado ou restaurado.
- [ ] A varredura de segredo rodou sobre o diff em stage e não achou nada.
- [ ] A mensagem tem tipo, escopo, título, objetivo e o rodapé com `Task`, `Trabalho` e `Testes`.
- [ ] O commit existe e seu identificador está no `ENTREGA.md`, num item com `seq` (`sequencia-de-commits.sh --validar` passa).
- [ ] A árvore ficou limpa dos arquivos daquela task.

## Quando falha

| Situação | O que fazer |
|---|---|
| `suite: vermelha` ou `nao_executada` | Não commita. A task não fechou de verdade — o E2 vai barrá-la nomeando-a |
| Task sem os dois testes | Não commita. O E2 vai barrá-la |
| Arquivo fora da lista declarada de toda task | **Para o fechamento inteiro antes do staging.** Não entra, não gera commit parcial e fica preservado na árvore |
| Arquivo declarado só em task irmã (`arquivo_de_task_irma`) | Não entra e **não é desvio**. Para o fechamento da task, sem commit parcial, sem apagar e sem restaurar. Levar ao replanejamento é da sprintx |
| Dono da task não determinável | Não commita. O script sai `1` e nada é classificado — nunca se infere o dono pela prosa |
| Origem task-based com plano corrente ausente/ilegível | Não commita. É erro de contrato; nunca vira `n/a` e nunca procura plano histórico |
| Origem task-based sem `ownership-da-task.sh` | Não commita. A instalação MergeX está incompleta; nunca degrada silenciosamente |
| Footer `Task:`/`Trabalho:` ausente, duplicado ou divergente | Não commita. A estrutura é validada antes do staging e o commit produzido é conferido novamente |
| Segredo detectado | Aborta o commit, desfaz o staging, avisa com o valor mascarado. A task fica `concluida` sem prova: a **V11** do E2 a nomeia |
| Task já `concluida` que ficou sem commit | Roda o **E1 tardio** (acima): commita agora e acrescenta o item ao fim de `commits`, com o próximo `seq`, sem reordenar o histórico |
| `commits` com sequência quebrada | **Não grave.** Contrato inválido: relate o motivo do `sequencia-de-commits.sh --validar` e pare. Nunca escolha outro número para caber |
| Branch errada ou principal | Não commita; relata a divergência e para |
| `git commit` falha (hook, assinatura) | Relata o erro literal do versionador e para; nunca contorna com `--no-verify` |
| Outro E1 tem a seção crítica deste índice | **PARA** (código 2). Não espera, não remove a trava, não toca no índice |
| Trava existe e nenhum E1 conhecido está em curso | **PARA.** `trava-do-e1.sh --status` diagnostica; remover é decisão humana, nunca automática |
| Stage já não vazio na entrada | **PARA** (código 3). Nada de reset, restore, stash ou commit do que se encontrou; o relatório nomeia os caminhos |
| Commit criado e append em `ENTREGA.commits` falhou | **PARA** (código 6) e relata "commit Git existe; registro E1 não foi concluído". Nenhum segundo commit, nenhum rollback. A V11 do E2 nomeia a task |
| Lista inválida depois do append | **PARA** (código 7). Não renumera e não reescreve item nenhum |
| Repositório sem versionador | Nada a fazer; segue sem erro |
