# Hooks da mergex

Implementação dos hooks descritos no contrato `expx-eventos` v1. O contrato
mora no repositório do painel, em `docs/contrato/CONTRATO-expx-eventos.md`, e
governa formato de rastro, modos e regras comuns.

## Por que hooks

Toda regra inviolável da mergex é hoje uma instrução que o modelo pode esquecer
numa execução longa. Hook é script determinístico: roda sempre, porque quem
executa é o harness, não o modelo.

A mergex é a skill que mais toca o versionador — é onde os hooks de segurança
importam mais, e onde um hook mal escrito faz mais estrago.

## Os seis hooks

| Hook | Evento | Modo inicial | O que faz |
|---|---|---|---|
| `sem-segredo` | `PreToolUse` | **bloqueio** | Barra commit e escrita com segredo, credencial ou dado real de cliente |
| `mergex/git-perigoso` | `PreToolUse` | **bloqueio** | Barra push forçado, commit/push na principal, reescrita de histórico enviado, descarte de alteração local, limpeza destrutiva |
| `branch-limpa` | `PreToolUse` | **bloqueio** | Barra criação ou troca de branch com alteração não commitada pendente |
| `commit-por-task` | `PreToolUse` | aviso¹ | Verifica que o commit corresponde a **uma** task, `concluida` e com registro de suíte válido (`parcial` ou `verde`); e que nenhum arquivo em preparação pertence **só a outra task** da feature |
| `arquivo-fora-do-plano` | `PreToolUse` | aviso | Compara o que está em preparação com a lista declarada na task. Artefato de método do **próprio** trabalho é isento; o de outro trabalho, não |
| `pr-so-com-portao` | `PreToolUse` | aviso² | Barra push e abertura de PR sem `PRONTO` registrado; com algum `PRONTO` que não vale no repositório, barra todo comando de publicação |

Os três de segurança nascem em bloqueio: segredo commitado não tem volta, e o
falso positivo ali é raro. Os três de método nascem em aviso, e só sobem a
bloqueio depois de rodarem semanas sem falso positivo — a lista de violações
que o painel acumula é o que guia a promoção.

### ¹ A exceção do `commit-por-task`: arquivo de task irmã

O hook continua em **aviso**, e todas as verificações dele obedecem ao modo
configurado — menos **uma**: um arquivo em preparação que mudou, que a task
sendo fechada **não** declara e que **outra task da feature** declara. Essa
condição **falha fechada mesmo em aviso** (`exit 2`).

Não é uma promoção do hook, e sim uma condição que não sobrevive a falhar
aberta: deixá-la passar cria o **commit parcial enganoso** da task — o
histórico afirmando que a task fechou com o trabalho que ela tem —, e commit
no histórico não tem volta. As demais verificações continuam avisando, e
`desligado` continua desligando o hook inteiro.

Quem classifica é `.claude/skills/mergex/scripts/ownership-da-task.sh`: uma
implementação só, provada pela bancada `scripts/ci/test-ownership-task.sh`.
Quando a branch identifica exatamente uma entrega SprintX/RunX, script ausente
é instalação MergeX incompleta e o hook para; não degrada para `n/a`.
Plano corrente ausente, ilegível ou inconsistente também para o commit manual:
o hook preserva o código de saída do classificador, em vez de confundir erro
sem linhas classificadas com autorização para seguir.

O plano também sai desse contexto: branch ativa + `branch:` de exatamente uma
`docs/entregas/<trabalho_id>/ENTREGA.md`, então `expx_tool` resolve somente a
pasta canônica daquele trabalho. Nenhum plano histórico com task id repetido
participa, e recência/rastro nunca selecionam ownership.

A mensagem (`-m` ou arquivo de `-F`) declara uma de duas classes mecânicas:

- **E1:** exatamente um `Task:` e um `Trabalho:`, sem `Metodo:`;
- **método:** exatamente um `Trabalho:` e um `Metodo:` (`pre-e2`, `pre-e6`
  ou `e8`), sem `Task:`.

`Task:` + `Metodo:`, qualquer chave de controle duplicada e `Metodo:` fora do
enum param mesmo quando o hook está em aviso. A gramática vem de uma única
implementação, `scripts/contrato-de-commit.sh`: commit de método válido não é
interpretado como E1 e segue para o hook de escopo, sem cobrar status/suíte de
task. Sem nenhuma das duas declarações, o hook não inventa a classe.

A task que está fechando sai do `Task:` validado e **nunca é adivinhada**. O
contrato inteiro está em
`references/01-commits.md`, "O dono do arquivo é a task que está sendo
fechada", e nas decisões da skill.

`scripts/fechamento-do-e1.sh` — a seção crítica do E1 — classifica com o
**mesmo** script, **antes** do primeiro `git add`: pelo caminho normal, o
arquivo de task irmã nunca chega a este hook, porque nunca chega a ser
staged. Este hook continua existindo como **defesa em profundidade** para
quem roda `git add`/`git commit` por fora da seção crítica — as duas chamadas
classificam pela mesma implementação, nunca por regras divergentes.

A mergex só **detecta e nomeia** a condição (`arquivo_de_task_irma`). Abrir
`B-NN` e replanejar é da sprintx.

### ² A exceção do `pr-so-com-portao`: portão `pronto` que não vale

O hook **decide pelo estado do repositório, não pela leitura do comando**. Ler
o shell por texto nunca cobre tudo: `xargs`, função, `-c remote.*.push=`,
subshell, plumbing. Tudo sai do Git, nunca do disco.

**1. Gatilho largo.** O hook dispara quando o comando contém, como palavra, um
termo de publicação:

- `push`, `send-pack` ou `subtree`, também na forma do executável do
  subcomando: `git-push`, `git-send-pack` e `git-subtree`
  (`/usr/lib/git-core/git-push`, `"$(git --exec-path)"/git-push`);
- `pr` ou `mr` seguido, em qualquer posição, de `create` ou `new`.

A fronteira antes do termo (ou do `git-`) é o início do comando ou qualquer
caractere fora de letra, dígito, `_` e `-`: espaço, `/`, aspas. Depois, a
mesma. Por isso `npm run git-push-notifications` não dispara.

Não importa se o termo está dentro de aspas, função, `xargs` ou subshell. O
hook não tenta entender o comando para decidir se dispara. Sem termo de
publicação (`git status`, `npm run push-notifications`), sai na hora.

**2. Varredura do estado.** O hook varre o repositório do `cwd` e todo
diretório literal citado no comando que seja outro repositório Git:

- `cd X` e `pushd X`, com ou sem opções: o diretório é o primeiro argumento
  que não começa com `-` (`cd -P X`, `cd -L X`, `pushd -n X`), ou o que vem
  depois de `--` (`cd -- X`);
- `-C X`, inclusive `env -C X`, e `--chdir X`;
- `--git-dir=X` e `--work-tree=X`;
- `GIT_DIR=X`, `GIT_WORK_TREE=X` e `GIT_COMMON_DIR=X`.

**Diretório corrente encadeado.** Um `X` relativo se resolve como o shell e o
git o resolvem: contra o diretório em vigor naquele ponto do comando, não
contra o `cwd` inicial.

- O diretório corrente começa no `cwd` do hook e muda com `cd`/`pushd` em
  posição de comando (inclusive `builtin cd` e `command cd`), para os
  segmentos seguintes.
- O `cd` de dentro de um subshell `( … )` não vaza para fora. Um `)` sem `(`
  deixa o diretório corrente desconhecido.
- Dentro de um segmento, `-C` e `env -C` se compõem (`git -C .. -C wt`).
  `--git-dir`, `--work-tree` e `GIT_*=` relativos se resolvem contra o
  diretório depois dos `-C` e também contra o diretório corrente do shell;
  as duas leituras são varridas.
- `~` e `~/…` viram `$HOME`, e `cd` sem argumento vai para `$HOME`.
- `cd -`, `pushd +N`/`-N`, `pushd` sem argumento, `popd` e caminho com
  expansão deixam o diretório corrente desconhecido: dali em diante, um
  relativo não se resolve (risco residual).

**Independente da worktree.** Cada candidato vira o diretório Git **comum**
do repositório (`git rev-parse --path-format=absolute --git-common-dir`, com
o fallback de ler o `.git`/`gitdir:` e o `commondir`). Isso vale para árvore,
subdiretório, `.git` e o gitdir de uma worktree vinculada
(`<repo>/.git/worktrees/<wt>`). O `for-each-ref`, o `git grep` e a validade
rodam com `--git-dir=<comum>` (a validade, com `GIT_DIR`/`GIT_WORK_TREE` no
comum): um `core.worktree` inválido não tira o repositório da varredura. Um
candidato que existe e parece Git (tem `.git` nele ou acima), mas cujo
diretório comum não se resolve de jeito nenhum, barra com `exit 2`.

Em cada repositório, para **cada branch local**, ele procura o
`docs/entregas/<id>/ENTREGA.md` da **ponta** dessa branch que declara
`branch: <essa branch>`. São um `for-each-ref` e um `git grep` sobre as
pontas. Quando esse ENTREGA registra `portao: pronto`, o portão tem de valer:

`scripts/validade-do-portao.sh --verificar --entrega <ENTREGA> --rev <ponta>`

Só `ok=true` **com** código 0 conta como prova. Qualquer outra resposta barra
com `exit 2` em **qualquer** modo, `desligado` inclusive (spec de
reconciliação pós-E8, §4.5 e §13.5):

- `ok=false`;
- validade ausente ao lado dos hooks;
- `erro_ambiente`;
- código fora de 0/1.

A mensagem nomeia a branch, o trabalho, o `motivo` e o `primeiro_commit`, e
manda rodar o E2 de novo (`/mergex-check`). Se a branch estiver abandonada, a
outra saída é apagá-la: o portão dela deixa de contar.

A varredura **para na primeira falha**: o hook barra na hora e não valida o
resto. Uma mesma ponta com o mesmo ENTREGA é validada uma vez só por chamada.

**Tempo e timeout.** Um hook que estoura o `timeout` **não bloqueia**: o
comando segue. Por isso este hook tem `timeout: 60` no `.claude/settings.json`
e 60 s no plugin do OpenCode (`TEMPO_POR_HOOK`). No Claude Code, os outros
hooks ficam com 10 s e o `git-perigoso` com 30 s; no OpenCode, todos os outros,
`git-perigoso` inclusive, ficam no limite único de 10 s (`TEMPO_LIMITE`).

**Prazo próprio, que falha fechado.** Como o timeout do harness libera o
comando, o hook tem um prazo interno de **45 s**, contado desde o início da
execução. Ele é verificado antes de cada validade e passado a ela como limite
(`timeout` do coreutils, quando existe). Estourou: `exit 2` em qualquer modo,
com a mensagem `varredura do portão excedeu o prazo; rode /mergex-check ou
apague branches abandonadas`. Só a bancada (`EXPX_HOOKS_BANCADA=1`) pode
reduzir o prazo, por `EXPX_PORTAO_PRAZO_TESTE`; nunca aumentá-lo. O relógio
(`SECONDS`) é zerado no início do hook: um valor herdado do ambiente não
antecipa nem desliga o prazo.

**Sem `timeout` no PATH** (macOS sem coreutils, por exemplo), o prazo só é
conferido entre as validades: antes de cada uma e depois dela. Uma validade
isolada que passe de 60 s pode cair no timeout do harness, e o comando segue.
Com `timeout`/`gtimeout`, a validade é cortada no prazo.

O custo de cada validade cresce com os commits de método depois do portão.
Medido no WSL (média de 3 chamadas, `git push origin main` com todos os
portões válidos):

| Situação | Tempo |
|---|---|
| 50 portões `pronto` válidos, 2 commits de método cada | ~12 s (~0,24 s por validade) |
| 20 portões `pronto` válidos, 12 commits de método cada | ~23,6 s (~1,2 s por validade) |
| 40 portões `pronto` válidos, 12 commits de método cada | barra pelo prazo em ~45 s |
| 50 portões `pronto` válidos, 12 commits de método cada | barra pelo prazo em ~45 s |
| nenhum portão `pronto`, 50 branches (medição anterior) | ~0,5 s |
| 50 vencidos, para na primeira (medição anterior) | ~0,5 s |
| comando sem termo de publicação | ~20–35 ms |

Branches suportadas antes do prazo: cerca de **185** portões `pronto` válidos
simultâneos com 2 commits de método cada, e cerca de **38** com 12 commits de
método cada. Acima disso o hook não libera mais nada: todo comando de
publicação barra pelo prazo até as branches abandonadas serem apagadas.

A validade não tem "caminho curto" para `portao_sha` igual à revisão: esse caso
não ocorre. O `ENTREGA.md` da revisão teria de conter o SHA do próprio commit
que o contém, e o SHA depende do conteúdo. Todo portão válido tem pelo menos o
commit de método que o registrou no intervalo.

Isso independe do HEAD e da branch ativa. Por isso também vale:

- no primeiro trabalho MergeX do projeto, quando a main ainda não tem
  `docs/entregas`;
- com o `ENTREGA.md` do disco apagado, editado ou não rastreado.

A entrega de um trabalho já integrado à main não é o portão da main, porque
declara outra branch.

**Custo aceito.** Enquanto houver portão vencido no repositório, **qualquer**
comando com termo de publicação é barrado, inclusive citações como
`git log --grep push` e `echo push`. A mensagem diz isso e manda corrigir o
portão. Com todos os portões válidos, esses comandos passam. Um repositório
sem MergeX nunca é barrado por este hook.

**3. Refinamento: `null` e `bloqueado`.** A leitura por token do push, a mesma
do `mergex/git-perigoso` (`expx_segmentos`/`expx_push_le`, em `comum/base.sh`),
continua com dois usos:

- identificar as branches que o comando empurra;
- dar contexto à mensagem.

Quando a branch empurrada é de um trabalho cujo ENTREGA, na revisão
empurrada, diz `null` ou `bloqueado`, vale o modo configurado, como sempre:
`aviso` avisa, `bloqueio` barra, `desligado` não age.

A abertura de PR (`gh pr create|new`, `gh -R <repo> pr create`,
`glab mr create|new`) conta para a branch ativa, ou para a de
`--head`/`--source-branch`. Isso só vale quando `gh`/`glab` é o programa:
`grep 'gh pr create'` não abre PR.

**Origem explícita.** Há um caso em que a leitura por token acrescenta uma
checagem ao `pronto`: o destino é a branch de um trabalho com `pronto` e a
origem não é a ponta local dessa branch. Exemplos: `git push origin
<sha>:feature/x`, `HEAD~1:refs/heads/feature/x`, `main:feature/x`.

Nesse caso a validade roda também sobre a **origem**
(`--rev <origem resolvida>`), porque é ela que sobe. Origem que não resolve
num commit barra. As duas regras valem em qualquer modo. Com
`feature/x:feature/x`, ou com o SHA da própria ponta, vale a ponta, que a
varredura já validou.

Fora isso, a leitura por token **não** decide a liberação de um portão
`pronto`: quem decide é a varredura.

**Riscos residuais — é uma barreira de agente, não de segurança contra
adversário.**

- **Diretório não literal.** Um diretório citado com expansão (`cd $D`,
  `GIT_DIR=$X`, `~outro`) não é varrido. O hook só varre o `cwd` e os
  diretórios literais (`~` e `~/…` são expandidos para `$HOME`).
- **Diretório corrente desconhecido.** `cd -` (o `OLDPWD` vem da shell do
  harness), `pushd +N`/`-N`, `pushd` sem argumento e `popd` dependem de estado
  que o texto não mostra: o diretório de destino não é varrido, e um relativo
  citado depois deles não se resolve.
- **Publicação puxada pelo remoto.** Com um remoto no sistema de arquivos,
  `git -C <remoto> fetch <wt> feature/x:feature/x` (ou `--git-dir=<remoto>
  fetch`) grava a branch no remoto sem termo de publicação no comando, e o
  hook não dispara. Num remoto de rede (GitHub, GitLab) não se aplica.
- **Commit fora de ponta de branch.** Um commit que não é a ponta de nenhuma
  branch local (SHA solto, HEAD destacado, branch só no remoto) não é varrido.
  A exceção é quando ele é a origem explícita de um push para a branch local
  de um trabalho com `pronto`. Destino sem branch local não é checado.
- **Origem explícita só quando literal.** A checagem da origem explícita lê o
  refspec no texto do comando. Um refspec que chega por fora do texto
  (`echo <sha>:feature/x | xargs git push origin`) não é lido; vale só a
  varredura da ponta local.
- **Alias de git.** Com `git config alias.p push`, o comando `git p origin
  <branch>` não tem termo de publicação e não dispara o hook.
- **Ofuscação por aspas.** `git pu""sh origin <branch>` é um push para o shell,
  mas o texto não tem o termo `push` como palavra e o hook não dispara. É a
  mesma classe do alias.
- **PR pela API.** `gh api repos/<o>/<r>/pulls -f head=<branch> …` abre um PR
  sem termo de publicação no comando, e o hook não dispara. Ele só expõe o que
  já está no remoto: o código chegou lá por um push, que passou pelo hook.
- **Tempo.** O prazo interno de 45 s falha fechado: acima dele, o hook barra
  em vez de deixar passar. O custo de cada validade cresce com os commits de
  método depois do portão (E4, E5, E8 acumulam em branches entregues que
  ficam locais). Ver a tabela acima: com muitos portões `pronto` válidos ao
  mesmo tempo, todo comando de publicação passa a ser barrado pelo prazo até
  as branches abandonadas serem apagadas.

**Recomendação.** A garantia forte é rodar `validade-do-portao.sh` fora do
agente:

- num job de CI, sobre o SHA do PR;
- ou num hook `pre-push` do Git, que recebe as refs realmente enviadas.

O hook de agente evita o erro comum. O CI ou o `pre-push` fecham o que o texto
do comando não mostra.

## Onde cada coisa mora

Segue a convenção do ecossistema — a mesma da `stackx` e da `sprintx`:

```
.claude/hooks/comum/     biblioteca e hooks compartilhados (base, segredo, branch)
.claude/hooks/mergex/    hooks próprios da mergex
.claude/hooks/teste.sh   a suíte
.claude/settings.json    o registro dos hooks no Claude Code
.claude/agents/          os dois agentes
.opencode/plugin/        a ponte para o OpenCode
.opencode/agent/         os mesmos agentes, no formato do OpenCode
.expx/hooks.json         o modo de cada hook
```

**Hook com nome que outra skill também usa mora no namespace da skill.** O
`git-perigoso` da mergex é `.claude/hooks/mergex/git-perigoso.sh`, com id
`mergex/git-perigoso` em `.expx/hooks.json`; a sprintx publica o dela em
`.claude/hooks/sprintx/git-perigoso.sh`, com id `sprintx/git-perigoso`. Os
dois coexistem sem sobrescrita, e desligar um id não desliga o outro. O id sem
namespace (`git-perigoso`) não é lido por nenhum dos dois (DM-171).

**A lógica não é duplicada entre os dois harnesses.** O plugin do OpenCode
(`.opencode/plugin/mergex.ts`) invoca os **mesmos scripts** de
`.claude/hooks/`. Só o registro difere, porque os mecanismos diferem:

| | Claude Code | OpenCode |
|---|---|---|
| Registro | `settings.json`, evento → matcher → handler | plugin JS/TS, `tool.execute.before` |
| Bloqueio | `exit 2`, motivo no stderr | lançar exceção |
| Aviso | stderr, lido pelo transcript | não existe no `before`: o aviso é represado e anexado ao resultado no `after` |

Por causa da última linha, os hooks emitem o aviso **nos dois canais**: stderr
(Claude Code) e JSON no stdout (OpenCode). Um harness ignora o canal do outro.

## Modo, por hook

O modo vive em `.expx/hooks.json`, na raiz do projeto:

```json
{
  "expx_hooks": 1,
  "hooks": {
    "sem-segredo": { "modo": "bloqueio" },
    "mergex/git-perigoso": { "modo": "bloqueio" },
    "branch-limpa": { "modo": "bloqueio" },
    "commit-por-task": { "modo": "aviso" },
    "arquivo-fora-do-plano": { "modo": "aviso" },
    "pr-so-com-portao": { "modo": "aviso" }
  }
}
```

| Modo | Comportamento |
|---|---|
| `aviso` | Registra `regra_violada` no rastro e deixa passar |
| `bloqueio` | Registra `acao_bloqueada`, sai com 2 e devolve o motivo ao modelo |
| `desligado` | Não faz nada, nem registra — menos o portão `pronto` que não vale para a revisão publicada (²), que nenhum modo pula |

Arquivo ausente: valem os padrões da tabela dos seis hooks. **Um hook de
segurança nunca é rebaixado por arquivo ausente** — a ausência do arquivo não
afrouxa nada, só o `desligado` explícito o faz.

## As três regras de desenho que este diretório obedece

Hook em execução de comando é o mais arriscado do ecossistema: intercepta
**toda** chamada de terminal, inclusive as que não têm nada a ver com a mergex.

1. **Casar o comando com precisão.** Uma regra frouxa que barre qualquer coisa
   contendo `push` atrapalha o dev o dia inteiro. Os casamentos são ancorados
   em `git` como programa e na forma real da opção, não em substring solta.
2. **Ser rápido.** Roda em toda chamada de terminal; acima de 200 ms o atraso é
   perceptível. Tudo é `bash` + `jq`, sem interpretador pesado, sem rede, e
   com saída antecipada assim que o comando não é do versionador.
3. **Falhar aberto no método, fechado na segurança.** Hook de método que quebra
   e trava o terminal faz o time desligar tudo — inclusive os de segurança.

## Como testar

```
./.claude/hooks/teste.sh
```

Roda os casos de cada hook: o que tem que barrar, o que tem que passar, e os
falsos positivos conhecidos que precisam continuar passando.

## Lacuna registrada no contrato

O contrato manda, na regra 7, que o hook **sempre grave no rastro, inclusive
quando permite**. Mas o vocabulário de `evento` não tem um termo para "avaliou
e deixou passar": os disponíveis para hook são `regra_violada` (modo aviso),
`acao_bloqueada` (modo bloqueio), `suite_executada` e `arquivo_alterado`.

Inventar um enum aqui poluiria a leitura do painel, que trata `evento` como
lista fechada. Enquanto o contrato não nomear esse evento, **a passagem limpa é
silenciosa**. Nada se perde para o propósito declarado: o painel precisa de
`regra_violada` e `acao_bloqueada` para montar a lista de violações que guia a
promoção de aviso para bloqueio, e as duas são gravadas.

Quem mantém o contrato decide se acrescenta um `regra_avaliada` ao vocabulário.

## Nota de portabilidade

Os scripts rodam em **bash 3.2**, que é o que o macOS ainda entrega. Isso
exclui `mapfile`/`readarray` e outras construções de bash 4+. Ao editar um
hook, rode `./hooks/teste.sh` — a suíte cobre exatamente os casos onde essas
diferenças aparecem.

Dependências: `bash`, `jq`, `git`, e os utilitários POSIX (`grep`, `sed`,
`awk`, `find`). Nenhuma chamada de rede, em nenhum caminho.

**`jq` precisa estar no PATH do processo que executa o hook**, não só no do
terminal interativo: o harness roda `bash` não interativo, que não lê
`~/.bash_profile`. No `mergex/git-perigoso`, jq ausente é **bloqueio de
contrato** — toda chamada cujo payload menciona `git` é barrada com a mensagem
`dependência ausente: jq` — porque sem jq o comando não pode ser lido e o hook
passaria sem avaliar nada (DM-171). Não existe parser alternativo. Os demais
hooks que leem o payload por jq (`sem-segredo`, `branch-limpa` e os de método)
ainda **falham abertos** sem jq: risco registrado na DM-171, fora do escopo do
M4-A.

**Timeout.** O harness cancela o hook que estoura o timeout e deixa o comando
rodar — timeout é falha aberta. No Claude Code, o `mergex/git-perigoso` usa
30 s, o mesmo timeout crítico do `sprintx/git-perigoso`; no OpenCode, ele fica
no limite único de 10 s do plugin (`TEMPO_LIMITE`). A barreira posterior, fechada, é o
E1 (`fechamento-do-e1.sh`): ele inventaria a árvore inteira antes do
`git add`, então um arquivo de task irmã escrito enquanto o hook de escopo da
skill de origem estourava o timeout ainda barra o fechamento (DM-172).
