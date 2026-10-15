# Patch de integração — sprintx × mergex

Prompt pronto para colar no repositório da skill `sprintx`. Ele altera a `sprintx` para acionar a `mergex` nos pontos corretos e para expor os artefatos que ela consome.

Trabalhe de forma autônoma até o fim: não faça perguntas, não peça autorização para editar arquivos, não pare no meio.

---

## PARTE 1 — O CONTRATO

A `mergex` é a skill do ecossistema Expx que cuida do versionamento e da entrega: garante a branch quando o trabalho começa, commita cada task concluída, verifica a prontidão, classifica o diff por atenção humana, monta a descrição do pull request e o pacote do QA, sobe a branch e abre o PR.

A `sprintx` planeja e executa features novas em seis fases (F1–F6). O código é escrito na **F6 EXECUÇÃO**. É lá, e só lá, que a `mergex` entra.

### As quatro regras deste contrato

**1. A `sprintx` aciona, a `mergex` executa.** A `sprintx` não versiona nada por conta própria na F6: ela chama a `mergex` no ponto certo e devolve o controle. Nenhum comando de versionamento novo entra na `sprintx`.

**2. A branch e o worktree continuam da `sprintx`.** A regra 21 da `sprintx` abre a feature em `feature/<slug>` e em `git worktree` próprio, **na F1**. A `mergex` **adota** o que encontra: ela não cria uma segunda branch, não renomeia a da F1 e não remove worktree. Nada da F1 muda por causa deste patch.

**3. Ausência da `mergex` nunca quebra a `sprintx`.** Toda a integração é condicional à presença de `.claude/skills/mergex/SKILL.md`. Sem ela, a F6 roda exatamente como hoje: executa as tasks, marca os status, roda a suíte, entrega o relatório final. Nenhum commit, nenhum erro, nenhum aviso ruidoso. O worktree e a branch continuam existindo, porque são da `sprintx`.

**4. O comando de revisão NUNCA é encadeado.** A `sprintx` **NÃO mencione `/mergex-revisar`** em lugar nenhum — nem no relatório final da F6, nem como próximo passo, nem como dica. Integrar código é decisão humana.

### Os pontos de acionamento

| Momento na sprintx | Etapa da mergex |
|---|---|
| Início da F6, depois de ler o `ORQUESTRADOR.md` e **antes da primeira task** | **E0** — adota `feature/<slug>` e o worktree da F1; cria a branch só se não existir nenhuma |
| Ao fechar **cada** task (status `concluida`, `suite: parcial` ou `verde`) | **E1** — um commit para aquela task |
| Fim da F6 (todas as tasks executadas, ou nada mais executável) | **E2 → E8** — portão, classificação, PR, pacote de QA, push, abertura, registro |

---

## PARTE 2 — O QUE ALTERAR

### 2.1 `references/06-execucao.md` — três inserções

**(a) Nos pré-requisitos, antes do Passo 1.** Acrescente:

> ### Abertura do trabalho no repositório
>
> Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E0 da `mergex`** antes da primeira task, depois de ler o `ORQUESTRADOR.md`.
>
> A F1 já abriu `feature/<slug>` e o worktree da feature (regra 21). O E0 **adota** o que existe: ele não troca de branch, não cria outra e **não exige árvore limpa** para isso — os artefatos de F1 a F5 estão na árvore, ainda não commitados, que é exatamente onde deveriam estar. Ele registra a branch no `ORQUESTRADOR.md` e cria `docs/entregas/<slug>/ENTREGA.md`.
>
> Se **não** houver branch para este trabalho (execução sem git, "sem worktree" explícito, ou fluxo que não passou pela F1), o E0 cria `feature/<slug>` a partir da base — e aí a árvore precisa estar limpa. Se a `mergex` avisar que há alteração não commitada pendente nesse caso, **pare a F6** e repasse o aviso: não se começa a executar por cima de trabalho não salvo de alguém.
>
> Se a `mergex` avisar que a branch do trabalho está em **outro worktree**, pare e repasse o caminho: o trabalho continua de dentro daquele diretório.
>
> Sem a `mergex` instalada, siga direto para o Passo 1.

**(b) No Passo 2, imediatamente depois do passo do TDD que marca `status: concluida`.** Acrescente como passo seguinte:

> Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E1 da `mergex`** para esta task. Ela commita os arquivos de produto declarados em `arquivos`, mais os artefatos de método deste trabalho que estiverem sujos (a pasta `docs/sprintx/features/<slug>/`, a começar pelo `tasks.md` que você acabou de atualizar), com a mensagem que traz o objetivo e os testes da task, depois de varrer o diff em busca de segredo, credencial e dado real de cliente.
>
> A ordem importa: o commit registra a task **já marcada** como concluída, e é o `tasks.md` atualizado que dá à mensagem o objetivo e os testes.
>
> **`suite: parcial` fecha task e sustenta commit** — é o registro normal da F6, e a suíte inteira continua sendo cobrada no fechamento da sprint. O E1 barra apenas `suite: vermelha` e `suite: nao_executada`.
>
> Se a `mergex` abortar o commit por suspeita de segredo, **não contorne**: a task fica sem commit, o aviso vai para o relatório final, e o portão de prontidão vai barrá-la depois.
>
> Task marcada `bloqueada` não gera commit.

**(c) No Passo 3 (relatório de encerramento), antes de montar o relatório** — e **depois** de gravar o `FECHAMENTO.md`. Acrescente:

> ### Entrega
>
> Se `.claude/skills/mergex/SKILL.md` existir, acione as **etapas E2 a E8 da `mergex`**, nesta ordem: portão de prontidão, classificação da atenção humana, descrição do pull request, pacote de QA, push, abertura do PR e registro da entrega. O `FECHAMENTO.md` precisa já estar gravado: ele entra no commit de artefatos de método que a `mergex` faz antes do push.
>
> Se o portão devolver `BLOQUEADO`, **inclua no relatório final o que ele apontou** e não tente contornar: a `mergex` barra e explica, nunca maquia. Achado de auditoria ALTA em aberto na F5 faz o portão barrar, e sprint fechada sem a suíte inteira registrada aparece como aviso do portão.
>
> Acrescente ao relatório final uma seção **Entrega** com: a branch, a quantidade de commits, o resultado do portão, a contagem das três faixas de atenção, e a URL do pull request (ou o caminho de `PR.md`, quando a ferramenta do serviço não estiver disponível).
>
> **Não sugira o merge e NÃO mencione `/mergex-revisar`.** A revisão e a integração são manuais e só rodam quando o desenvolvedor as chama pelo nome.

### 2.2 `SKILL.md` — duas alterações

**(a) Na tabela "Fases → arquivos da skill"**, na linha da F6, acrescente à coluna de roteiro:

> `references/06-execucao.md` — aciona a `mergex` (E0, E1, E2–E8) quando ela estiver instalada

**(b) Numa seção nova, ao fim, antes das regras invioláveis:**

> ## Entrega no repositório
>
> A `sprintx` termina com o código escrito e os testes verdes. Levar isso até o repositório e até o revisor é trabalho da [`mergex`](https://github.com/bittencourtthulio/mergex): ela adota a branch e o worktree que a F1 abriu, commita cada task que fecha, e ao fim monta a entrega — portão de prontidão, classificação do diff por atenção humana, descrição do pull request e pacote para o QA.
>
> A integração é condicional: sem a `mergex` instalada, a F6 roda exatamente como sempre.

### 2.3 O que NÃO alterar

- **Nenhuma regra inviolável da `sprintx`.** Nenhuma delas muda — inclusive a 21, que continua dando à F1 a posse da branch e do worktree.
- **A F1.** Ela continua criando ou retomando `feature/<slug>` e o worktree, com a base que ela já determina. Nenhum passo da F1 entra neste patch.
- **A máquina de estados.** A `mergex` não é uma fase e não entra na tabela de detecção de fase.
- **O contrato da task.** Nenhum campo novo. A `mergex` lê o que já existe, e aceita `suite: parcial` como o contrato já define.
- **As fases F1 a F5.** Antes da F6 não há código escrito.
- **O `expx-schema v1`.** A `mergex` grava seu próprio `kind: entrega` em `docs/entregas/`, fora das pastas da `sprintx`.
- **A única escrita da `mergex` em artefato da `sprintx`** é uma linha no `ORQUESTRADOR.md` registrando a branch. Nada mais.

---

## PARTE 3 — VERIFICAÇÃO

1. Grep por `mergex` em toda a skill: as menções aparecem **apenas** em `references/06-execucao.md` e no `SKILL.md`, nos pontos descritos.
2. Grep por `mergex-revisar`, `revisar`, `merge` e `integrar`: **nenhuma** menção ao comando de revisão em nenhum arquivo. Ele não pode ser encadeado nem sugerido.
3. Toda menção à `mergex` está condicionada à existência de `.claude/skills/mergex/SKILL.md`.
4. Simule a F6 **sem** a `mergex` instalada: a fase roda de ponta a ponta, executa as tasks, entrega o relatório final, e nenhum passo falha nem gera aviso ruidoso.
5. Simule a F6 **com** a `mergex`, dentro do worktree que a F1 criou: o E0 **adota** a branch, sem trocar de branch e sem reclamar dos artefatos de F1 a F5 não commitados; E1 depois de cada `status: concluida`; E2–E8 antes do relatório final.
6. Simule a F6 **com** a `mergex` num repositório onde a F1 não criou branch (sem git na F1, ou "sem worktree"): o E0 cria `feature/<slug>`, e com árvore suja ele para e avisa — e a F6 para junto.
7. Simule uma task fechada com `suite: parcial`: o E1 commita normalmente.
8. Simule o portão devolvendo `BLOQUEADO`: o relatório final traz o que falta e nada é contornado.
9. Confirme que nenhuma regra inviolável da `sprintx` foi alterada, que a regra 21 continua intacta, e que nenhum campo do contrato da task foi acrescentado.
10. Grep por caminho absoluto nos trechos acrescentados.

---

## ENTREGA

Ao terminar, mostre:

- o diff de cada arquivo alterado;
- o resultado das verificações 1 a 10;
- confirmação explícita de que `/mergex-revisar` não é mencionado em lugar nenhum.
