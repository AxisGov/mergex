# E9 — REVISÃO E MERGE (MANUAL)

Você está no E9. Esta etapa é diferente de todas as outras da mergex.

**O E9 NUNCA executa automaticamente.** Não é encadeado por nenhum fluxo, não é sugerido ao fim de um trabalho, não aparece como "próximo passo" em relatório nenhum, e não é oferecido depois do E8. Ele só roda quando o desenvolvedor chama `/mergex-revisar` explicitamente (regra 16).

Se você chegou aqui por qualquer outro caminho que não uma chamada explícita, **volte**: você está encadeando o que não pode ser encadeado.

O E9 tem uma função: **dar ao desenvolvedor o estado real de cada PR aberto, na ordem que faz o dia render, e conduzir um merge por vez com confirmação.** Ele não decide, não resolve conflito, não aprova.

## Pré-requisitos verificáveis

- Chamada explícita do desenvolvedor.
- Repositório versionado com remoto configurado.
- Ferramenta de linha de comando do serviço presente e autenticada (`gh auth status` / `glab auth status`).

Sem a ferramenta, o E9 não tem como listar nem integrar PRs. Diga isso e encerre — **nunca peça credencial** (regra 12):

```
mergex E9 — não é possível listar os pull requests

Motivo: <ferramenta não instalada | não autenticada>
A revisão e o merge precisam ser feitos pela interface do serviço de hospedagem.
```

## Passo 1 — Listar os pull requests abertos

```
gh pr list --state open --json number,title,author,headRefName,baseRefName,isDraft,mergeable,url,files,statusCheckRollup
```

Inclui rascunhos: eles aparecem na lista, marcados, mas **nunca são oferecidos para merge**.

Nenhum PR aberto: diga isso e encerre.

## Passo 2 — Reunir o estado de cada PR

Para cada PR, junte **o que estiver disponível**. Fonte ausente vira "não disponível" na apresentação — nunca suposição.

| Dado | Onde buscar | Quando ausente |
|---|---|---|
| Registro de entrega da mergex | `docs/entregas/<trabalho_id>/ENTREGA.md` na branch do PR | "sem registro da mergex" — PR aberto por fora do método |
| Faixa de raio da legadox | `raio` do `ENTREGA.md` | "raio não calculado" |
| Classificação de atenção | `atencao` do `ENTREGA.md`, ou `ATENCAO.md` na branch | "não classificado" |
| Resultado da integração contínua | `statusCheckRollup` | "sem integração contínua configurada" |
| Conflito com a base | `mergeable` do PR | Verifique localmente (passo 5) |
| Arquivos tocados | `files` do PR | `git diff --name-only <base>...<head>` |
| Aberto pela mergex nesta máquina | `pr_url` do `ENTREGA.md` local casa com a URL do PR | Assuma que não |
| Reviews, requested changes, comentários e threads | API do serviço — `gh pr view <n> --json reviews,latestReviews,comments`, mais GraphQL de `reviewThreads` (`isResolved`, `isOutdated`) quando o serviço suportar; `glab api projects/:id/merge_requests/:iid/discussions` no GitLab | Trate como fonte ausente para o REVIEW EVIDENCE GATE — ver "Quando falha" |
| SHA do HEAD atual | `headRefOid` do PR, ou `git rev-parse origin/<head>` | — |

### A marcação de trabalho próprio

Se o PR foi aberto pela mergex **na mesma máquina** — a `pr_url` de algum `ENTREGA.md` local casa com a URL do PR —, marque-o na lista:

```
[aberto por esta instalação da mergex — a skill não aprova o próprio trabalho]
```

Não é impedimento: é divulgação. Quem aprova é a pessoa, e ela precisa saber que a máquina que está apresentando o PR é a mesma que o produziu.

## O REVIEW EVIDENCE GATE

Antes de oferecer merge de qualquer PR, o E9 avalia automaticamente o estado do review
daquele PR. Isto **não** fura a regra 16: o gate só roda *dentro* de uma execução do E9 já
iniciada por chamada explícita de `/mergex-revisar` — ele não dispara o comando sozinho, e
continua impossível chamá-lo fora dele.

**MUDANÇA DE CÓDIGO NÃO ENCERRA REVIEW. EVIDÊNCIA ENCERRA REVIEW.**

Um finding de review pode ter gerado uma correção no código; isso sozinho não prova que o
reviewer aceitou a correção, que há evidência publicada, que o CI passou de novo, ou que a
thread foi resolvida. O gate existe para que "o código mudou" nunca seja confundido com "o
review encerrou" — foi exatamente essa confusão que apareceu na prática na PR #5 do
AxisGov/expxdev.

### Contrato genérico de reviewer

Bot e humano são **reviewers equivalentes** para o gate. Nada aqui hardcoda o nome de uma
ferramenta de review — nem CodeRabbit, nem CodeAnt, nem nenhuma outra. O gate consome três
formas de sinal, pela plataforma que existir:

- reviews submetidos, inclusive equivalentes a `CHANGES_REQUESTED` e aprovações;
- comentários inline e review threads, com o estado resolved/unresolved e outdated/current
  quando a plataforma expuser;
- comentários gerais relevantes ao PR.

Plataforma que não expõe uma dessas formas: trate como fonte ausente, do mesmo jeito que o
passo 2 trata qualquer dado que a ferramenta não devolve — nunca suposição.

**R2 usa o estado atual de cada reviewer, nunca o histórico completo.** `latestReviews` (ou o
equivalente do serviço) é a fonte de R2 — o review mais recente de cada pessoa ou bot, não a
lista de todos os reviews que ela já deu. Um `CHANGES_REQUESTED` que o próprio reviewer
substituiu depois por `APPROVED`, ou por um novo review, deixa de contar: é o estado atual
dele que decide, não o que ele disse antes. A lista completa (`reviews`) serve só para
reconstruir contexto — nunca para contar um `CHANGES_REQUESTED` antigo como ativo depois que o
mesmo reviewer já se manifestou de novo.

**PR sem nenhum review, comentário ou thread** satisfaz R2 e R3 por ausência de matéria — o
gate não exige que exista review, só que o review que existir não fique pendente.

### As seis situações de um finding ou thread

Cada finding ou thread de review cai em exatamente uma:

| Situação | Definição |
|---|---|
| `ACTIONABLE_UNRESOLVED` | Finding válido e ainda não tratado. |
| `FIXED_AWAITING_EVIDENCE` | Houve alteração, mas falta commit, teste, resposta ao review, ou CI. |
| `AWAITING_REREVIEW` | Correção e evidência já publicadas; aguardando confirmação ou re-review. |
| `REJECTED_WITH_EVIDENCE` | Finding considerado falso positivo ou não aplicável, com justificativa verificável publicada. |
| `RESOLVED` | O reviewer ou o bot confirmou, ou a thread foi corretamente encerrada. |
| `OUTDATED_NON_BLOCKING` | O comentário ficou obsoleto e não existe finding atual equivalente. |

**Na dúvida entre duas situações, classifique como `ACTIONABLE_UNRESOLVED`.** É a mesma
disciplina da classificação de atenção humana (E3, regra 8): ausência de prova não é prova de
segurança, e a situação mais rigorosa é a que bloqueia.

### R1–R6 — os seis critérios do gate

Esta é a definição normativa dos seis critérios. Ela existe **uma única vez**, aqui; qualquer
outro ponto da skill que cite R1–R6 está referenciando esta tabela, não redefinindo.

| # | Critério | Satisfeito quando |
|---|---|---|
| R1 | CI | O HEAD atual do PR está com CI verde, quando existir integração contínua configurada. |
| R2 | Blocking reviews | Nenhum review ativo em estado equivalente a `CHANGES_REQUESTED` ficou sem tratamento posterior. |
| R3 | Actionable threads | Zero findings válidos em `ACTIONABLE_UNRESOLVED`. |
| R4 | Fix evidence | Todo finding corrigido tem evidência mínima: commit/SHA, resumo preciso da correção, cobertura de regressão relevante, e a validação executada. |
| R5 | Review reply | A evidência foi publicada no próprio thread **antes** de ele ser resolvido. |
| R6 | Closure | O finding foi confirmado/resolvido pelo reviewer ou pelo bot, ou — pela política conservadora da mergex — encerrado com evidência verificável depois de novo CI/re-review. |

O gate devolve **só** um destes dois vereditos, sempre com R1–R6 individuais. Critério que não
se aplica ao estado atual do PR (por exemplo R4–R6 quando não há nenhum finding corrigido
ainda) vai como `n/a`, nunca omitido — mesma disciplina do `n/a` do portão de prontidão
(`references/02-prontidao.md`).

**O commit de R4 precisa pertencer ao HEAD atual.** `Fixed in <commit>` só é evidência válida
quando esse commit existe no repositório e é ancestral do HEAD atual do PR — não precisa ser o
próprio HEAD, mas um commit de um push que foi descartado (force-push, branch errada, PR
fechado) não serve como prova de nada no PR aberto. Sem ancestralidade confirmável, o finding
fica em `FIXED_AWAITING_EVIDENCE`.

### NÃO VERIFICÁVEL não é SATISFEITO

Ausência de capacidade da plataforma (API que o `gh`/`glab` não expõe, serviço que não é
GitHub nem GitLab, plano que não inclui reviews) não é a mesma coisa que ausência de review.
R2, R3, R5 e R6 dependem de dados que a plataforma pode simplesmente não devolver — e isso tem
que aparecer como um terceiro valor, nunca como `OK` nem como `FALHOU` por omissão:

```
R2 blocking reviews: NÃO VERIFICÁVEL
```

Um critério `NÃO VERIFICÁVEL` bloqueia o merge, do mesmo jeito que `FALHOU` — mas pede, no
passo 7, confirmação humana **específica daquele critério**, distinta da pergunta sobre o
merge em si: "a API não expõe {{o que falta}}; você confirma que não há {{review
pendente/thread aberta/etc.}} para este PR?". Sem essa confirmação, o merge não é oferecido.
Com ela, a condução segue — mas a confirmação vale só para esta execução: a próxima chamada de
`/mergex-revisar` tenta de novo pela API e não herda a confirmação anterior.

R1 nunca vira `NÃO VERIFICÁVEL`: ausência de integração contínua configurada é `n/a` (o
critério simplesmente não se aplica), o que é diferente de "existe CI mas não consigo ler o
resultado" — este último caso é, de fato, `NÃO VERIFICÁVEL`.

```
REVIEW EVIDENCE: SATISFEITO

R1 CI: OK
R2 blocking reviews: OK
R3 actionable threads: OK
R4 fix evidence: OK
R5 review reply: OK
R6 closure: OK
```

```
REVIEW EVIDENCE — BLOQUEADO

R1 CI: OK
R2 blocking reviews: OK
R3 actionable threads: FALHOU — 2 findings
R4 fix evidence: n/a
R5 review reply: n/a
R6 closure: n/a

Findings pendentes:
  src/foo.ts:84 — possível perda de configuração
  src/bar.ts:120 — cleanup não garantido
```

### A resposta ao review — o padrão que prova a correção

Nunca responda a um finding só com "fixed", "done" ou "resolved". Toda resposta segue um dos
dois formatos:

Finding corrigido:

```
Fixed in <commit>.

<resumo preciso da correção>

Regression coverage:
- <teste/caso>
- <teste/caso>

Validation:
- <check relevante>
```

Finding rejeitado (falso positivo ou não aplicável):

```
Not applicable.

<explicação objetiva sustentada pelo código, contrato, teste ou documentação>

Evidence:
- <fonte verificável>
```

Sem essa estrutura, o finding não sai de `FIXED_AWAITING_EVIDENCE` — a resposta sozinha não é
R4 nem R5.

### A ordem de resolução de thread — nunca resolver logo depois de editar código

1. Corrigir ou rejeitar o finding.
2. Testar.
3. Commit e push.
4. Publicar a evidência no review, no formato acima.
5. Esperar o CI.
6. Esperar re-review ou confirmação, quando a plataforma expuser.
7. Resolver a thread.

Se o bot ou o reviewer resolver a thread automaticamente depois da evidência publicada, aceite
esse estado — é `RESOLVED` por confirmação externa. Se a thread continuar aberta, ela continua
`AWAITING_REREVIEW` ou `FIXED_AWAITING_EVIDENCE`: **nunca esconda, nunca contorne, nunca
resolva por conta própria fora desta ordem.**

### Falso positivo não é autoaprovação

A mergex faz parte da mesma fábrica que produziu o código sendo revisado — ela não pode ser a
única a decidir que a própria rejeição de um finding encerra o review.

- **Reviewer ou bot concordou** com a rejeição (reagiu, respondeu, resolveu a thread): o
  finding vai para `RESOLVED` normalmente, R6 satisfeito.
- **Reviewer não respondeu** à rejeição publicada: o finding fica em `AWAITING_REREVIEW` e R6
  **não** é satisfeito por conta própria. O passo 7 do E9 pergunta, especificamente para aquele
  finding, se o desenvolvedor concorda com a rejeição antes de contar como fechado — a mesma
  disciplina da confirmação de OLHO OBRIGATÓRIO, aplicada aqui ao próprio veredito da mergex,
  não ao merge.

Isto mantém a intervenção humana baixa: a pessoa só entra quando existe desacordo — ou
silêncio — entre o reviewer e a fábrica, nunca em todo finding rejeitado.

### A fronteira: o que a mergex pode e o que ela não pode

A mergex **pode**: ler reviews, validar findings contra o código atual, reunir evidência,
responder thread, verificar CI, verificar re-review, classificar a situação de cada finding,
resolver thread quando R4–R6 estiverem satisfeitos, e conduzir o merge depois da confirmação
humana do passo 7.

A mergex **não pode**: editar código de produto para satisfazer um review; inventar
justificativa para um finding; marcar finding válido como resolvido sem evidência publicada.

### O pacote de remediação — quando o finding é válido

Finding válido que exige mudança **não é corrigido pela mergex**. Ela valida o finding contra
o código atual, monta este pacote, e devolve à skill de origem do trabalho (sprintx, runx ou
buildx):

```
REVIEW REMEDIATION

Finding:
<texto normalizado>

Arquivo:
<caminho/linha>

Validação:
<por que é válido>

Correção esperada:
<comportamento, não implementação inventada>

Regressão necessária:
<teste que deve provar a correção>

Review reply esperada:
<template de evidência>
```

**A entrega do pacote precisa sobreviver à sessão atual.** A mergex publica o pacote `REVIEW
REMEDIATION` como resposta na própria thread do finding — a mesma capacidade que já usa para
publicar `Fixed in <commit>`/`Not applicable` (ver "A resposta ao review", acima) — e não só
como texto de saída desta execução do E9. É o que garante que qualquer sessão futura, do
executor ou de uma pessoa, encontre o pacote completo no lugar onde o finding apareceu, sem
precisar reconstruir contexto.

Isto reaproveita um mecanismo que a mergex já tem (responder thread) em vez de criar um
artefato novo. A mergex **não** grava o pacote em `BLOQUEIOS.md`/`00-BLOQUEIOS.md` da
sprintx/runx: a única escrita dela em artefato de outra skill continua sendo a linha do
`ORQUESTRADOR.md` no E0 (ver `references/integracao/runx.md` e
`references/integracao/sprintx.md`) — inventar uma segunda escrita ali romperia essa fronteira
só para resolver um problema que a thread do próprio PR já resolve.

Depois de entregar o pacote, o PR é marcado **REVIEW PENDENTE** e **não é oferecido para
merge** nesta passagem do E9 — nem na fila principal, nem com confirmação (vai para os
inelegíveis do passo 4). Quando o executor corrigir e houver novo commit e push, a próxima
chamada de `/mergex-revisar` reavalia o PR do zero.

**A mergex nunca escreve a correção de código dentro dela mesma** — isso seria alterar código
de produto para caber na entrega, o que as regras 6 e 18 já proíbem.

## Passo 3 — Detectar sobreposição entre PRs

Cruze as listas de arquivos de **todos** os PRs abertos, dois a dois.

Dois ou mais PRs tocando o mesmo arquivo vão **destacados no topo da lista**, com os dois identificados e os arquivos em comum nomeados:

```
SOBREPOSIÇÃO — dois PRs abertos tocam os mesmos arquivos

  #482 "Corrigir base de cálculo do ICMS-ST" (fix/OC-2026-0184-...)
  #479 "Extrair formatador de nota fiscal" (feature/formatador-nota)
  Em comum:
    src/fiscal/base_calculo.py

Isto não é um bloqueio e não há conflito ainda. É informação para decidir a
ordem: o segundo a entrar vai precisar rebasear ou resolver conflito.
```

**Isto não é prevenção de colisão.** A mergex não previne colisão entre desenvolvedores, não reserva arquivo e não resolve conflito. É informação para quem decide a ordem.

## Passo 4 — Ordenar do MENOR para o MAIOR impacto

**Menor primeiro**, por duas razões que devem ser declaradas na saída:

1. Cada merge fácil que entra **reduz a superfície do próximo** — menos PRs abertos, menos sobreposição possível.
2. **Adiar o difícil não o piora; adiar o fácil sim** — o fácil vai acumulando divergência com a base enquanto espera.

### O critério, na ordem de desempate

Some, em ordem lexicográfica de prioridade (o primeiro critério que difere decide):

| # | Critério | Menor impacto ← → Maior impacto |
|---|---|---|
| 1 | Faixa de raio | sem raio / baixo → médio → alto |
| 2 | Arquivos em OLHO OBRIGATÓRIO | zero → poucos → muitos |
| 3 | Sobreposição com outro PR aberto | nenhuma → com um → com vários |
| 4 | Conflito com a base | sem conflito → com conflito |
| 5 | Quantidade de arquivos tocados | poucos → muitos |
| 6 | Número do PR | menor → maior (desempate final, estável) |

**Declare o critério na saída**, sempre. A ordem sem o critério é opinião; com o critério, é auditável.

PRs **inelegíveis para merge** — rascunho, integração contínua vermelha, ou `REVIEW EVIDENCE: BLOQUEADO` (ver "O REVIEW EVIDENCE GATE", acima) — aparecem na lista, **no fim**, marcados com o motivo, e **não entram na condução do passo 7**.

## Passo 5 — Analisar conflitos (relatar, nunca resolver)

Para cada PR marcado com conflito, esta análise é **o que o E9 tem de mais útil**. É trabalho que ninguém mais faz e que economiza a parte mais cara do dia do revisor.

Levante o conflito sem alterar nada da árvore de trabalho:

```
git fetch origin <base> <head>
git merge-tree $(git merge-base origin/<base> origin/<head>) origin/<base> origin/<head>
```

`merge-tree` calcula o merge **sem tocar na árvore de trabalho e sem criar commit**. Nunca faça um merge de verdade para "ver o conflito".

### Delegue a análise ao agente `analista-de-conflito`

**Passe o conflito ao agente `analista-de-conflito`.** Ele recebe o conflito e
explica o que cada lado pretendia, segundo a mensagem de commit e o plano de
cada trabalho.

Ele é a peça mais útil deste comando, e a que mais se beneficia de contexto
próprio: **ele lê os dois trabalhos sem estar comprometido com nenhum.** Quem
escreveu um dos lados tende a achar que a intenção dele é a óbvia, e a do outro
é o desvio.

**As ferramentas dele são somente de leitura — `Read`, `Grep` e `Glob`, sem
execução de comando.** Não é uma promessa de que ele não vai resolver o
conflito: é impossibilidade técnica. Ele não tem como fazer checkout, merge, nem
escrever no arquivo.

Passe a ele: o conflito calculado com `merge-tree`, a mensagem de commit de cada
lado, e o `tasks.md` (mais o `01-CAUSA-RAIZ.md`, quando é da runx) de cada
trabalho.

**Restrição herdada:** este agente só é acionado por este comando manual. Nada
no fluxo automático da mergex pode chamá-lo.

Para cada arquivo em conflito, relate quatro coisas:

1. **Onde**: arquivo e trechos (as linhas ou a função).
2. **O que este PR pretendia ali**, segundo a mensagem de commit da task e o plano do trabalho.
3. **O que o outro lado pretendia ali** — a base, ou o outro PR — pela mesma fonte.
4. **Por que os dois se cruzaram**: mesma função, mesma linha, ou mudanças adjacentes que o versionador não consegue juntar.

```
CONFLITO — #482 contra main

  src/fiscal/base_calculo.py, função calcular_base_st(), linhas 40–58

  O que #482 pretendia:
    "Excluir o desconto incondicional da base de ST, conforme a regra vigente."
    (T-01.02, fix/OC-2026-0184-icms-st-base-desconto)

  O que entrou na base depois:
    "Extrair o rateio por item para um método próprio."
    (#479, mesclado em 2026-08-28)

  Por que se cruzaram:
    Os dois reescreveram o corpo de calcular_base_st(). Um mudou a fórmula, o
    outro mudou a estrutura. As duas intenções são compatíveis; a junção não é
    automática porque tocam as mesmas linhas.

  A mergex não resolve conflito. Resolver isto é decisão humana: as duas
  intenções precisam coexistir no código final.
```

**Nunca resolva.** Não escolha um lado, não sugira o texto final do arquivo, não faça checkout de versão, não rode `git checkout --ours/--theirs`, não peça ao versionador que decida. Relatar as duas intenções é o limite — e é o ponto (regra 17).

Acrescente, por trecho, **o que perguntar a quem decidir**: a pergunta que
destrava a decisão, não a resposta. É o que o `analista-de-conflito` devolve, e
é o que faz a análise valer o tempo de quem lê — ela nomeia a decisão que só
uma pessoa com contexto de negócio pode tomar.

## Passo 6 — Apresentar a lista

Use `assets/TEMPLATE-revisao.md`. Nesta ordem:

1. **Sobreposições** entre PRs abertos, destacadas no topo (passo 3).
2. **O critério de ordenação**, declarado.
3. **Os PRs elegíveis**, do menor para o maior impacto.
4. **Os inelegíveis**, no fim, com o motivo.

Por PR, exatamente estes campos:

```
#482 — Corrigir base de cálculo do ICMS-ST com desconto incondicional
  Autor: <autor>
  Trabalho: OC-2026-0184-icms-st-base-desconto (runx, regra-de-calculo)
  Impacto: raio ALTO — 3 arquivos em olho obrigatório
  Arquivos: 9 (src/fiscal/ 3, src/relatorios/ 1, tests/ 5)
  Integração contínua: verde
  Conflito: não
  Review Evidence: SATISFEITO
  Reviews: 0 actionable, 0 aguardando evidência, 0 aguardando re-review, 1 rejeitado com evidência, 4 resolvidos
  [aberto por esta instalação da mergex — a skill não aprova o próprio trabalho]
  Recomendação: revisar os 3 arquivos de olho obrigatório antes de integrar;
                é o de maior impacto da fila.
```

A **recomendação é uma linha** e é derivada do estado, não de opinião. Ela nunca diz "pode integrar sem olhar".

PR com `REVIEW EVIDENCE: BLOQUEADO` não recebe recomendação de merge: mostra, no lugar, o
bloco de bloqueio inteiro do REVIEW EVIDENCE GATE (R1–R6 e os findings pendentes) e entra nos
inelegíveis do passo 4, com o motivo `REVIEW EVIDENCE: BLOQUEADO`.

## Passo 7 — Conduzir, um PR por vez

Na ordem apresentada, **um de cada vez**. Nunca em lote, nunca uma confirmação única para vários (regra 17).

Para cada PR elegível:

1. Apresente o bloco do PR de novo, resumido. Se, entre a apresentação (passo 6) e este
   momento, uma revisão nova mudou o veredito do REVIEW EVIDENCE GATE para `BLOQUEADO` —
   comentário novo, CI que voltou a falhar —, **pare e não ofereça o merge** (recusa dura 6):
   diga o que mudou e passe para o próximo PR.
2. **Peça confirmação explícita daquele PR específico.** "Confirma o merge do #482?" — nunca "posso seguir com os três?".
3. Se algum critério do REVIEW EVIDENCE GATE estiver `NÃO VERIFICÁVEL`, pergunte, para **aquele critério especificamente**, se o desenvolvedor confirma o que a API não conseguiu expor (ver "NÃO VERIFICÁVEL não é SATISFEITO", acima). Sem essa confirmação específica, não ofereça o merge. Se algum finding estiver `REJECTED_WITH_EVIDENCE` sem resposta do reviewer, pergunte, também especificamente para aquele finding, se o desenvolvedor concorda com a rejeição (ver "Falso positivo não é autoaprovação", acima).
4. Se houver arquivo em **OLHO OBRIGATÓRIO** ou o raio for **ALTO**, a confirmação é dupla: antes de perguntar sobre o merge, pergunte se o desenvolvedor **revisou os arquivos daquela faixa**, listando-os por nome:

```
Este PR tem 3 arquivos em OLHO OBRIGATÓRIO:
  src/fiscal/calculo_icms_st.py — zona de risco fiscal, altera base de cálculo
  src/fiscal/base_calculo.py — zona de risco fiscal, raio ALTO
  migrations/0042_ajusta_precisao_st.sql — migração de banco

Você revisou esses três arquivos? (o merge não segue sem esta confirmação)
```

Sem essa confirmação, **não ofereça o merge** deste PR. Passe para o próximo.

5. Confirmado, faça o merge com a estratégia que o repositório usa (detecte em `CONVENCOES.md` da stackx ou nos merges anteriores; na ausência, use o padrão do serviço). Nunca force, nunca reescreva histórico já enviado.
6. Atualize `pr_estado: merged` no `ENTREGA.md` correspondente, quando ele existir localmente.

   **E, somente se o PR mergeado for o do trabalho atual**, grave `pr_estado: merged`
   também em `.expx/estado.json`. O E9 percorre PRs de vários trabalhos e de outras
   pessoas; a barra mostra **um** trabalho, o que está em andamento nesta sessão. Mergear o
   PR de outro trabalho não muda o estado do seu.

   O PR é do trabalho atual quando a `pr_url` do `ENTREGA.md` daquele PR casa com a do
   `ENTREGA.md` do trabalho nomeado em `trabalho` no próprio `estado.json`. Se `trabalho`
   for `null`, se o `estado.json` não existir, ou se a correspondência não for certa,
   **não grave nada** — na dúvida, deixe a barra como está.

   Não toque em `branch`. O procedimento é o de `10-estado.md`, e falha de gravação vai
   para o rastro sem interromper a condução dos PRs seguintes.
7. Recusa ou silêncio: **não faça o merge**, siga para o próximo, e registre que ele ficou pendente.

### As seis recusas duras

Não faça merge, em nenhuma hipótese:

| # | Nunca faça merge | Por quê |
|---|---|---|
| 1 | Com integração contínua vermelha | A máquina já provou que algo quebrou |
| 2 | De PR em rascunho | Rascunho declara que ainda não está pronto |
| 3 | Sem confirmação **daquele** PR específico | Confirmação em lote não é confirmação |
| 4 | Com faixa OLHO OBRIGATÓRIO sem a confirmação de que os arquivos foram revisados | É o propósito inteiro da classificação |
| 5 | Resolvendo conflito | A resolução é humana |
| 6 | Com `REVIEW EVIDENCE` diferente de `SATISFEITO` | Mudança de código não encerra review — evidência encerra review (ver "O REVIEW EVIDENCE GATE") |

## Critério de saída

- [ ] Todos os PRs abertos foram listados, inclusive rascunhos e inelegíveis.
- [ ] Sobreposições estão no topo, com os PRs identificados e os arquivos em comum.
- [ ] O critério de ordenação está declarado.
- [ ] A ordem vai do menor para o maior impacto.
- [ ] PRs com integração vermelha, rascunhos e `REVIEW EVIDENCE: BLOQUEADO` não foram oferecidos para merge.
- [ ] Todo PR mostrou `Review Evidence: SATISFEITO | BLOQUEADO` e o bloco `Reviews` com as cinco contagens.
- [ ] PR bloqueado mostrou R1–R6 individuais e os findings pendentes nomeados.
- [ ] Finding válido virou pacote `REVIEW REMEDIATION` devolvido à skill de origem, nunca corrigido pela mergex.
- [ ] Conflitos foram relatados com as duas intenções, sem resolução.
- [ ] Cada merge feito teve confirmação específica; os de OLHO OBRIGATÓRIO tiveram a confirmação dupla.
- [ ] PRs abertos por esta instalação da mergex estão marcados.
- [ ] `pr_estado: merged` foi para o `.expx/estado.json` **apenas** se o PR mergeado era o do trabalho atual; PR de outro trabalho não alterou a barra.

Ao fim, um resumo: o que foi integrado, o que ficou pendente e por quê.

## O rastro do comando manual

Grave em `docs/eventos/<trabalho_id>.jsonl`: **a lista de PRs avaliados, a ordem
apresentada e o que foi mergeado.**

```json
{"ts":"<ISO-8601 UTC>","expx_eventos":1,"trabalho_id":"<id>","ferramenta":"mergex","origem":"skill","evento":"veredito_emitido","fase":"e9","task":null,"agente":"analista-de-conflito","resultado":"ok","detalhe":"PRs avaliados: #479, #482; ordem: #479 < #482; mergeado: #479","arquivos":[]}
```

O registro é do que **uma pessoa decidiu**, não do que a skill decidiu: a
mergex **nunca faz merge por conta própria, em nenhum caminho**. Cada merge da
lista teve confirmação explícita daquele PR específico.

## Quando falha

| Situação | O que fazer |
|---|---|
| Ferramenta ausente ou não autenticada | Encerra dizendo que a revisão precisa ser feita pela interface; nunca pede credencial |
| Nenhum PR aberto | Diz e encerra |
| PR sem registro da mergex | Apresenta com o que houver e marca "sem registro da mergex" |
| Integração contínua não configurada | Marca "sem integração contínua"; não é impedimento, mas entra na recomendação |
| `mergeable` desconhecido | Verifica localmente com `merge-tree`; se não der, marca "conflito não verificado" e trata como conflito |
| Merge falha no serviço | Relata o erro literal e segue para o próximo PR; nunca tenta contornar |
| Usuário pede para resolver o conflito | Recusa: a mergex relata as duas intenções; a resolução é humana (regra 17) |
| Usuário pede merge em lote | Recusa: um por vez, com confirmação de cada (regra 17) |
| Ferramenta lista o PR mas não expõe reviews/threads | Marca os critérios afetados (R2/R3/R5/R6, conforme o dado ausente) como `NÃO VERIFICÁVEL` e pede a confirmação humana específica do passo 7; sem ela, trata como `REVIEW EVIDENCE: BLOQUEADO` — mesmo critério conservador do `mergeable` desconhecido |
| Plataforma não expõe estado resolved/outdated de uma thread | Trata como fonte ausente para aquele campo; o finding correspondente não passa de `FIXED_AWAITING_EVIDENCE` — nunca vira `RESOLVED` sem confirmação verificável |
| Usuário pede para resolver thread ou marcar finding sem evidência publicada | Recusa: sem R4/R5, o finding fica onde está; a mergex não maquia review encerrado |
