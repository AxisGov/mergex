# Patch de integração — runx × mergex

Prompt pronto para colar no repositório da skill `runx`. Ele altera a `runx` para acionar a `mergex` nos pontos corretos e para expor os artefatos que ela consome.

Trabalhe de forma autônoma até o fim: não faça perguntas, não peça autorização para editar arquivos, não pare no meio.

---

## PARTE 1 — O CONTRATO

A `mergex` é a skill do ecossistema Expx que cuida do versionamento e da entrega: cria a branch quando o trabalho começa, commita cada task concluída, verifica a prontidão, classifica o diff por atenção humana, monta a descrição do pull request e o pacote do QA, sobe a branch e abre o PR.

A `runx` trata ocorrências de produção em cinco estágios (E1–E5). O código é escrito no **E3 FIX**.

**Atenção à colisão de nomes.** As duas skills numeram estágios com `E`. Neste patch, sempre diga de qual skill é o estágio: **E1–E5 da runx** (investigação, plano, fix, QA, relatório) e **E0–E9 da mergex** (as etapas dela).

### As três regras deste contrato

**1. A `runx` aciona, a `mergex` executa.** A `runx` não versiona nada por conta própria: chama a `mergex` no ponto certo e devolve o controle.

**2. Ausência da `mergex` nunca quebra a `runx`.** Toda a integração é condicional à presença de `.claude/skills/mergex/SKILL.md`. Sem ela, o E3 da runx roda como hoje e segue para o E4 e o E5. Nenhuma branch, nenhum commit, nenhum erro.

**3. O comando de revisão NUNCA é encadeado.** A `runx` não menciona, não sugere e não aciona `/mergex-revisar` em lugar nenhum — nem nos relatórios do E5, nem como próximo passo. Integrar código é decisão humana.

### Os pontos de acionamento

| Momento na runx | Etapa da mergex |
|---|---|
| Início do **E3 da runx**, depois de ler o `ORQUESTRADOR.md` e **antes da primeira task** | **E0** — abre `fix/<OC-ID>-<slug>` (tipo `bug`) ou `chore/<OC-ID>-<slug>` (demais tipos) |
| Ao fechar **cada** task (status `concluida`, suíte verde) | **E1** — um commit para aquela task |
| **Entre o E4 e o E5 da runx** | **E2 → E8** — portão, classificação, PR, pacote de QA, push, abertura, registro |

### Por que a entrega fica entre o E4 e o E5 da runx

O **E4 da runx** é o QA e grava `QA.md` com o veredito. O **E5 da runx** grava os relatórios, atualiza o `INDICE.md` e **fecha a ocorrência**.

A `mergex` entra no meio porque o portão dela precisa do veredito do QA — QA reprovado barra a entrega —, e porque o E5 da runx só deve rodar depois da entrega existir: **a mergex entrega, a runx fecha**. Fechar a ocorrência antes registraria como resolvido algo que ainda não chegou ao repositório.

---

## PARTE 2 — O QUE ALTERAR

### 2.1 `references/03-fix.md` — duas inserções

**(a) Nos pré-requisitos verificáveis, antes do Passo 1.** Acrescente:

> ### Abertura do trabalho no repositório
>
> Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E0 da `mergex`** antes da primeira task, depois de ler o `ORQUESTRADOR.md`. Ela verifica se o repositório é versionado, determina a branch base e cria a branch da ocorrência — `fix/<OC-ID>-<slug>` quando `tipo: bug`, `chore/<OC-ID>-<slug>` nos demais tipos —, retomando a branch se ela já existir.
>
> A exigência de árvore limpa vale quando o E0 precisa **criar ou trocar** de branch, que é o caminho normal da runx. Se a sessão já estiver na branch da ocorrência, ele apenas a adota, sem trocar nada.
>
> Se a `mergex` avisar que há alteração não commitada pendente, **pare o E3** e repasse o aviso: não se começa a corrigir por cima de trabalho não salvo de alguém.
>
> Sem a `mergex` instalada, siga direto para o Passo 1.

**(b) No Passo 2, imediatamente depois do passo 8 do TDD** (o que marca `status: concluida`). Acrescente como passo 9:

> 9. Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E1 da `mergex`** para esta task. Ela commita **apenas os arquivos declarados** em `arquivos`, com a mensagem que traz o objetivo e os testes da task, depois de varrer o diff em busca de segredo, credencial e dado real de cliente.
>
> Na primeira task de uma ocorrência `tipo: bug`, a mensagem cita o **teste de regressão primeiro**: é ele que prova que o defeito existia.
>
> Se a `mergex` abortar o commit por suspeita de segredo, **não contorne**: a task fica sem commit e o portão de prontidão vai barrá-la depois.
>
> Task marcada `bloqueada` não gera commit.

### 2.2 `references/04-qa.md` — uma inserção ao fim

Depois de gravar `QA.md` com o veredito, acrescente:

> ## Entrega, antes do E5
>
> Se `.claude/skills/mergex/SKILL.md` existir, acione as **etapas E2 a E8 da `mergex`** depois de gravar o veredito e **antes de seguir para o E5**: portão de prontidão, classificação da atenção humana, descrição do pull request, pacote de QA, push, abertura do PR e registro da entrega.
>
> A `mergex` lê o `QA.md` no portão dela: **`VEREDITO: REPROVADO` faz o portão barrar**, listando os achados ALTA. Nesse caso a entrega não acontece e o fluxo volta ao E3 — o que já é o comportamento da máquina de estados da `runx`.
>
> Com `VEREDITO: APROVADO`, a `mergex` entrega e o E5 segue normalmente. **A mergex entrega; a runx fecha a ocorrência.**
>
> Sem a `mergex` instalada, siga direto para o E5.

### 2.3 `references/05-relatorio.md` — uma inserção

No relatório técnico, acrescente uma seção:

> ### Entrega
>
> Se existir `docs/entregas/<OC-ID>-<slug>/ENTREGA.md`, traga dele: a branch, a quantidade de commits, o resultado do portão, a contagem das três faixas de atenção humana, e a URL do pull request (ou o caminho de `PR.md`, quando a ferramenta do serviço não estava disponível).
>
> Sem esse arquivo, omita a seção — não escreva que não houve entrega.
>
> **Não sugira o merge e não mencione `/mergex-revisar`** em nenhum dos dois relatórios. A revisão e a integração são manuais.

E no **relatório de uso**, nenhuma alteração: ele é o texto que o suporte devolve ao cliente e não fala de branch, commit nem pull request.

### 2.4 `SKILL.md` — duas alterações

**(a) Na tabela "Estágios → arquivos da skill"**, nas linhas do E3 e do E4, acrescente à coluna de roteiro:

> E3: `references/03-fix.md` — aciona a `mergex` (E0 e E1) quando ela estiver instalada
> E4: `references/04-qa.md` — aciona a `mergex` (E2–E8) antes do E5, quando ela estiver instalada

**(b) Numa seção nova, ao fim, antes das regras invioláveis:**

> ## Entrega no repositório
>
> A `runx` termina com a ocorrência fechada e os relatórios gravados. Levar o código até o repositório e até o revisor é trabalho da [`mergex`](https://github.com/bittencourtthulio/mergex): ela abre a branch no início do E3, commita cada task que fecha, e entre o E4 e o E5 monta a entrega — portão de prontidão, classificação do diff por atenção humana, descrição do pull request e pacote para o QA.
>
> A `mergex` entrega; **quem fecha a ocorrência continua sendo a `runx`**, no E5. A integração é condicional: sem a `mergex` instalada, os estágios rodam exatamente como sempre.

### 2.5 O que NÃO alterar

- **Nenhuma regra inviolável da `runx`.** A regra 10 (quem implementa não aprova) e a 11 (a ocorrência não fecha sem os dois relatórios) continuam valendo integralmente.
- **A máquina de estados.** A `mergex` não é um estágio e não entra na tabela de detecção.
- **O contrato da task.** Nenhum campo novo.
- **`00-OCORRENCIA.md`, `01-CAUSA-RAIZ.md` e `QA.md`.** A `mergex` só lê. A única escrita dela em artefato da `runx` é uma linha no `ORQUESTRADOR.md` registrando a branch.
- **A árvore `docs/relatorios/`.** É da `runx`. A `mergex` grava em `docs/entregas/`.
- **O relatório de uso.** É da `runx`, e a `mergex` apenas o aponta no pacote de QA.

---

## PARTE 3 — VERIFICAÇÃO

1. Grep por `mergex`: as menções aparecem **apenas** em `references/03-fix.md`, `references/04-qa.md`, `references/05-relatorio.md` e no `SKILL.md`, nos pontos descritos.
2. Grep por `mergex-revisar`, `revisar`, `merge` e `integrar`: **nenhuma** menção ao comando de revisão em nenhum arquivo, e nenhuma nos dois relatórios do E5.
3. Toda menção à `mergex` está condicionada à existência de `.claude/skills/mergex/SKILL.md`.
4. Simule o E3 **sem** a `mergex`: roda de ponta a ponta e segue para o E4 e o E5, sem falha e sem aviso ruidoso.
5. Simule o E3 **com** a `mergex`: E0 antes da primeira task, E1 depois de cada `status: concluida`.
6. Simule `VEREDITO: REPROVADO` no E4: o portão da `mergex` barra, a entrega não acontece, e o fluxo volta ao E3 como a máquina de estados já manda.
7. Simule `VEREDITO: APROVADO`: E2–E8 rodam, e só depois o E5 grava os relatórios e fecha a ocorrência.
8. Simule ocorrência `tipo: bug`: a branch nasce com prefixo `fix/`; ocorrência `tipo: melhoria-ui`: prefixo `chore/`.
9. Confirme que nenhuma regra inviolável da `runx` foi alterada e que nenhum campo do contrato da task foi acrescentado.
10. Grep por caminho absoluto nos trechos acrescentados.

---

## ENTREGA

Ao terminar, mostre:

- o diff de cada arquivo alterado;
- o resultado das verificações 1 a 10;
- confirmação explícita de que `/mergex-revisar` não é mencionado em lugar nenhum, incluindo os relatórios do E5.
