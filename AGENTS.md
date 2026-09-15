# AGENTS.md

Instruções para o agente, em qualquer harness (Claude Code, OpenCode, outros).

Este repositório usa a skill **mergex**, em `.claude/skills/mergex/`. Ela cuida do versionamento e da entrega do trabalho: leva o código escrito até o repositório e até o revisor humano.

## Quando acionar a mergex

**Ao começar a implementar um trabalho** — antes da primeira linha de código —, acione a mergex para **abrir a branch** (etapa E0). A branch nasce com o trabalho, não no fim. Sem ela, tudo acontece na branch em que o desenvolvedor estava, normalmente a principal.

**Ao concluir cada task** — com os dois testes escritos, a suíte inteira verde e a task marcada como concluída —, acione a mergex para **commitar aquela task** (etapa E1). Um commit por task, no momento em que ela fecha. Nada é montado no fim.

**Ao terminar a implementação**, acione o **fluxo de entrega** (etapas E2 a E8): portão de prontidão, classificação da atenção humana, descrição do pull request, pacote para o QA, push e abertura do PR.

Nada disso exige que o usuário diga "mergex". Basta ele começar a implementar, terminar uma task, ou pedir para entregar, versionar, subir o trabalho, abrir PR ou passar para o QA.

## A revisão e o merge são MANUAIS

O comando `/mergex-revisar` — revisão e integração de pull requests — **nunca executa automaticamente**.

Não o encadeie a partir de nenhum fluxo, não o sugira ao fim de um trabalho, não o ofereça como próximo passo depois de uma entrega, e não o acione por iniciativa própria. Ele só roda quando o desenvolvedor o chama explicitamente pelo nome.

**Integrar código é decisão humana.** É a única exceção ao automatismo do método.

Uma vez chamado, o E9 avalia automaticamente o **Review Evidence Gate** de cada PR antes de
oferecer merge: mudança de código não encerra review, evidência encerra review. Finding válido
sem evidência publicada vira um pacote de remediação devolvido a quem executou (`sprintx`,
`runx` ou `buildx`) e o PR fica pendente — a mergex nunca corrige código de produto para
satisfazer um review. Isto continua dentro do E9 e continua exigindo a chamada manual; nada
aqui muda o automatismo do resto do método. Detalhe:
`.claude/skills/mergex/references/09-revisao.md`.

## Segurança de versionamento

Valem sempre, em qualquer etapa:

- Nunca push forçado, em nenhuma circunstância.
- Nunca commit ou push direto na branch principal.
- Nunca trocar de branch com alteração não commitada pendente — pare e avise.
- Nunca reescrever histórico já enviado ao remoto.
- Nunca resolver conflito automaticamente. Relate as duas intenções; a resolução é humana.
- Nunca descartar alteração local de ninguém.
- Nunca configurar credencial nem armazenar segredo.
- Nunca commitar arquivo fora da lista declarada na task.
- A varredura de segredo, credencial e dado real de cliente roda a cada commit e no portão de prontidão. Encontrou, aborta.
- Repositório sem versionador: siga sem essas etapas, sem erro e sem bloqueio.

## O que a mergex não faz

Não aprova o próprio trabalho, não faz merge no fluxo automático, não cria release, não publica, não faz deploy, e não altera código para caber na entrega — trabalho incompleto é barrado, nunca maquiado.

**Não previne colisão entre desenvolvedores.** A branch isola o trabalho; ela não impede que duas pessoas alterem o mesmo código. Quem resolve conflito é quem revisa o pull request.

## Hooks e agentes

As regras acima deixaram de depender só de o agente lembrar delas. Elas agora
são **hooks** — scripts determinísticos que o harness executa em toda chamada
de ferramenta.

Três nascem em **bloqueio**, porque o erro não tem volta:

- `sem-segredo` — segredo, credencial ou dado real de cliente em commit ou escrita
- `git-perigoso` — push forçado, commit/push na principal, reescrita de histórico enviado, descarte de alteração local, limpeza destrutiva
- `branch-limpa` — criar ou trocar branch com alteração não commitada pendente

Três nascem em **aviso**, e só sobem a bloqueio depois de rodarem sem falso
positivo: `commit-por-task`, `arquivo-fora-do-plano` e `pr-so-com-portao`.

Se um hook barrar sua ação, **a mensagem diz o que fazer** — leia e corrija, não
contorne. O modo de cada hook vive em `.expx/hooks.json`.

Dois agentes rodam em contexto próprio, com ferramentas de leitura:

- `revisor-diff` classifica o diff nas três faixas (E3), sem ter visto a
  implementação sendo escrita.
- `analista-de-conflito` explica o que cada lado de um conflito pretendia.
  **Só o comando manual `/mergex-revisar` o aciona** — nada no fluxo automático
  pode chamá-lo. Ele não tem ferramenta de escrita nem de execução de comando:
  é impossibilidade técnica, não disciplina, que o impede de resolver conflito.

Detalhe e testes: `.claude/hooks/README.md`.

## A camada de memória (`memox`) — opcional

Quando `.claude/skills/memox/assets/memox.py` existe, a mergex consulta o índice
do `memox` na classificação da atenção (E3) e anexa o histórico de cada arquivo
à descrição do PR (E4); ao fechar a entrega (E8), ela dispara a reindexação.

**Arquivo com histórico de regressão é OLHO OBRIGATÓRIO**, qualquer que seja o
tamanho da mudança — e toda subida cita trabalho, data e artefato.

**Sem o memox instalado, pule em silêncio**: nenhum aviso, nenhuma menção na
saída, e a classificação é exatamente a de sempre. A faixa **nunca desce** por
causa do memox, e coincidência de arquivo não sobe faixa nenhuma.

Detalhe: `.claude/skills/mergex/references/integracao/memox.md`.

## Comandos

| Comando | O que faz |
|---|---|
| `/mergex` | Fluxo automático completo a partir do estado atual |
| `/mergex-abrir` | Abre a branch do trabalho (E0) |
| `/mergex-check` | Portão de prontidão (E2) |
| `/mergex-atencao` | Classifica o diff nas três faixas (E3) |
| `/mergex-pr` | Descrição, push e abertura do PR (E4, E6, E7) |
| `/mergex-qa` | Pacote para o QA (E5) |
| `/mergex-revisar` | Revisão e merge — **manual, só por chamada explícita** |

O detalhe operacional de cada etapa está em `.claude/skills/mergex/references/`. Leia o reference da etapa atual antes de agir, e somente o dela.
