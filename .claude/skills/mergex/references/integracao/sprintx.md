# Integração — sprintx

A `sprintx` planeja e executa features novas, em seis fases: F1 INGESTÃO → F2 DESCOBERTA → F3 PLANO → F4 ORQUESTRADOR → F5 AUDITORIA → F6 EXECUÇÃO.

A mergex entra **na F6** e em nenhuma outra fase. Antes da F6 não há código escrito, e a mergex não tem o que versionar.

## Quem é dono do quê

**A F1 da sprintx é a dona da branch `feature/<slug>` e do worktree.** A regra 21 da sprintx abre a feature num `git worktree` próprio, na branch `feature/<slug>`, já na F1 — muito antes de existir código. Quando a F6 chega, branch e worktree normalmente já existem.

A mergex **adota** o que encontra:

| Quem | Faz |
|---|---|
| sprintx F1 | cria ou retoma `feature/<slug>` e o worktree da feature |
| mergex E0 | adota a branch e o worktree existentes, registra e valida a entrega |
| mergex E0, **só** quando a branch não existe | cria a branch, a partir da base determinada |

A mergex **nunca cria uma segunda branch para o mesmo trabalho** e nunca troca de branch quando já está na certa. O detalhe operacional — os casos A, B e C — está em `references/00-abertura.md`.

## Onde ficam os artefatos da sprintx

O caminho canônico é `docs/sprintx/features/<slug>/`. `docs/<slug>/` é o formato anterior, que a sprintx continua suportando nas pastas que já existem.

A mergex procura **o canônico primeiro e o antigo como fallback**, em todas as etapas que leem artefato da sprintx, e **nunca move uma pasta legada**: migrar é decisão do usuário.

## Os pontos de acionamento

| Momento na sprintx | Etapa da mergex | O que acontece |
|---|---|---|
| Início da F6, **antes da primeira task** | **E0 ABERTURA** | Adota `feature/<slug>` e o worktree da F1 (ou cria a branch, se ela não existir), registra no `ORQUESTRADOR.md` e cria `docs/entregas/<slug>/ENTREGA.md` |
| Ao fechar **cada** task (status `concluida`, `suite: parcial` ou `verde`) | **E1 COMMIT** | Um commit por task, com a mensagem no formato da mergex |
| Fim da F6, com todas as tasks executadas | **E2 → E8** | Portão, classificação, descrição do PR, pacote de QA, push, abertura do PR, registro |
| Fim da F6, com o portão **bloqueado** | **E2 → E8 (fechamento bloqueado)** | E3 a E7 **não executam**. O E8 grava `estado: bloqueado`, persiste o registro por commit e **não publica a branch**; o controle volta à sprintx com o que falta |

Depois do E8, a mergex devolve o controle. **Ela não sugere o E9** (regra 16).

**Portão bloqueado não pula o E8.** `F6 → E2 BLOQUEADO` não significa E3 a E7: significa E8 em
fechamento bloqueado — registro persistido por commit, branch **não** publicada — e retorno à
sprintx com o que falta. Se a feature for replanejada e a F6 rodar de novo, o E0 **retoma** o
`ENTREGA.md` que já existe em vez de recriá-lo, preservando `commits` e `criado_em`
(`references/00-abertura.md`).

### E0 — no início da F6

A F6 começa lendo o `ORQUESTRADOR.md` e retomando o estado das tasks. A mergex roda **depois dessa leitura e antes da primeira task**, porque a branch precisa existir antes do primeiro commit.

Dois casos, e os dois são normais:

- **A F1 já abriu a branch e a sessão está dentro do worktree dela.** O E0 adota: não troca de branch, não cria outra e **não exige árvore limpa** — os artefatos de F1 a F5 estão ali, ainda não commitados, que é exatamente onde deveriam estar.
- **Não há branch para este trabalho** (sem git na F1, "sem worktree" explícito, ou fluxo que não passou pela F1). O E0 cria `feature/<slug>` a partir da base, e aí sim a árvore precisa estar limpa.

Sessão interrompida e retomada: o E0 encontra a branch existente e **adota ou retoma nela**, sem criar outra. A F6 continua de onde parou pelo `status` das tasks.

Se a branch do trabalho estiver em uso por **outro** worktree, o E0 informa o caminho e encerra sem mexer em nada: o trabalho continua de dentro daquele diretório.

### E1 — no passo do TDD que fecha a task

O `references/06-execucao.md` da sprintx fecha cada task assim: verifica o critério de aceite, marca `status: concluida` no frontmatter e na prosa, com data e resultado da suíte.

**O E1 roda imediatamente depois disso.** A ordem importa: o commit registra a task já marcada como concluída, e é o `tasks.md` atualizado que dá à mensagem de commit o objetivo e os testes.

**`suite: parcial` fecha task e sustenta commit.** A sprintx roda, na task, o subconjunto afetado (`suite: parcial`) e cobra a suíte inteira uma vez, ao fechar a sprint. O E1 aceita `parcial` e `verde`; barra `vermelha` e `nao_executada`. Os dois testes da task continuam obrigatórios — TDD não muda aqui —, e o portão (E2, V2) continua cobrando a evidência da suíte inteira no fechamento de cada sprint.

Task marcada `bloqueada` não gera commit. O E2 vai barrá-la depois — o que está correto: uma feature com task bloqueada não está pronta para entregar.

Os **artefatos de método do próprio trabalho** — a pasta `docs/sprintx/features/<slug>/` (ou a legada `docs/<slug>/`) e `docs/entregas/<slug>/` — entram nos commits do E1 e nunca contam como desvio de escopo. É o que leva ao histórico o plano, as decisões e o `FECHAMENTO.md`, inclusive quando o worktree da feature for removido depois. O contrato está em `references/01-commits.md`.

**E o E8 fecha commitando o registro final da entrega**, com o estado que só existe depois do push e do PR. É o que permite remover o worktree da feature — ou integrar a branch por fast-forward — sem perder o estado final: quem integra, integra commits (`references/08-registro.md`).

### E2 a E8 — ao fim da F6

Rodam quando a F6 termina: todas as tasks executadas, ou nada mais executável.

**Auditoria reprovada na F5 faz o E2 barrar** (verificação V6). Se o `00-AUDITORIA.md` do trabalho existe e não contém `VEREDITO: SIM`, ou tem achado ALTA em aberto, o portão devolve `BLOQUEADO` e o fluxo encerra. Achado ALTA manda voltar para a F3 — e um plano que voltou para a F3 não tem entrega a fazer.

## O que a mergex consome da sprintx

A coluna "Onde" vale para as duas formas: `docs/sprintx/features/<slug>/` (canônico) e `docs/<slug>/` (formato antigo).

| Artefato | Onde | Usado em |
|---|---|---|
| `ORQUESTRADOR.md` | pasta do trabalho | E0 (registro da branch e do worktree), E4 (título e objetivo), E2 (comando de teste) |
| `sprint-NN/tasks.md` | pasta do trabalho | E1 (objetivo, arquivos, testes), E2 (status, suíte, testes), E3 (cobertura por task) |
| `sprint-NN/fases.md`, `sprint.md` | pasta do trabalho | E2 (critérios de saída e evidência da suíte inteira) |
| `00-BLOQUEIOS.md` | pasta do trabalho | E2 (V7 — bloqueio aberto no escopo) |
| `00-AUDITORIA.md` | pasta do trabalho | E2 (V6 — auditoria reprovada) |
| `00-DECISOES.md` | pasta do trabalho | E4 (contexto da seção "o que muda e por quê") |
| `FECHAMENTO.md` | pasta do trabalho | E1 (commit de artefatos de método, antes do push) |

O `trabalho_id` da mergex é o **mesmo `<slug>`** da sprintx. Não gere outro.

## O que a mergex NÃO faz com a sprintx

- Não altera o plano, as tasks, as fases nem a auditoria. A única escrita da mergex em artefato da sprintx é **uma linha** no `ORQUESTRADOR.md` registrando a branch (E0).
- **Não disputa a posse da branch nem do worktree.** Não cria uma segunda branch, não renomeia a que a F1 abriu, não remove worktree de ninguém.
- Não executa task, não escreve teste, não implementa nada.
- Não substitui a F5. A auditoria audita o plano; o portão verifica a execução.
- Não move pasta de trabalho em formato antigo.

## Trabalho da sprintx sem modo legado

É o caso normal. Sem `docs/legado/PERFIL.md`:

- **E2:** a verificação V8 inteira é `n/a`.
- **E3:** os critérios O1, O7 e O8 (zona de risco, efeito irreversível, raio ALTO) não podem ser avaliados; registre como fonte ausente. Os demais critérios continuam valendo integralmente — mudança de cálculo, migração, contrato público e código sem cobertura seguem sendo OLHO OBRIGATÓRIO.
- **E4:** as seções 5 (raio), 7 (congelado) e 8 (reverter) são **omitidas**, não preenchidas com texto genérico (regra 10).
- **E8:** `raio: null`.

## Se a mergex não estiver instalada

A F6 da sprintx roda exatamente como antes: executa as tasks, marca os status, roda a suíte e entrega o relatório final. Nenhuma branch é criada pela mergex, nenhum commit é feito por ela, e nada quebra. O worktree e a branch da F1 continuam existindo, porque são da sprintx. **A ausência da mergex nunca quebra o fluxo da sprintx.**
