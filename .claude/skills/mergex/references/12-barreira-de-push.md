# BARREIRA DE PUSH — ATIVAÇÃO E PROVA DO `pre-push`

Contrato: `docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md`, seção 13,
itens 5 a 7 (DM-184).

O `pre-push` do Git é a barreira **local autoritativa contra erro normal**: ele decide cada push
pelo que o Git entrega (refs e SHAs), chamando o validador de push da skill
(`scripts/portao-push.sh --pre-push`), que aplica a mesma validade do portão
(`validade-do-portao.sh --rev`) ao SHA enviado. Este reference cobre como o E0 o ativa, como o E2
prova que ele está ativo, como compô-lo com um hook que já existe e como revertê-lo.

O executável é um só: `scripts/ativacao-pre-push.sh <--instalar|--provar|--reverter> --entrega
docs/entregas/<trabalho_id>/ENTREGA.md`. Códigos: `0` ok; `1` prova reprovada; `3` pré-requisito
ausente (hook de terceiro que não passa na prova); `64` uso. Não existe opção de força.

## Ativação

O E0 roda, **depois de criar ou retomar o `ENTREGA.md`**:

```bash
bash .claude/skills/mergex/scripts/ativacao-pre-push.sh --instalar \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md
```

- **Diretório efetivo:** o script resolve o diretório de hooks pelo próprio Git
  (`git rev-parse --git-path hooks`), o que já respeita um `core.hooksPath` existente, relativo ou
  absoluto, e o diretório comum de uma worktree vinculada. **O E0 nunca altera `core.hooksPath`.**
- **Sem `pre-push` nesse diretório:** instala o chamador gerenciado (`assets/pre-push-gerenciado.sh`,
  com o marcador `# mergex: pre-push gerenciado`), que só chama o validador de push e propaga o
  código de saída dele. O modelo é versionado sem o bit de execução; a cópia instalada recebe o bit.
- **Já é o chamador gerenciado:** nada muda (idempotente).
- **Existe um `pre-push` de terceiro:** o E0 nunca o sobrescreve, renomeia ou edita. Quem decide é
  a prova funcional: aprovada, é **integração externa válida** e o E0 segue; reprovada, o script sai
  `3` com a instrução de composição.
- Em todos os casos o E0 termina com a prova funcional. Código diferente de zero:
  **`mergex E0 BLOQUEADO — pre-push`**, o E0 encerra e mostra a instrução que o script imprimiu.

O marcador serve só para a idempotência e para a reversão. A aceitação de qualquer `pre-push`,
gerenciado ou de terceiro, sempre passa pela prova funcional.

## Composição com hook de terceiro

Quando o repositório já tem um `pre-push`, a composição é **deliberada e feita à mão** por quem
mantém aquele hook. A instrução é uma só, a mesma que o E0 imprime: o `pre-push` existente chama `portao-push.sh --pre-push "$@"`, repassa a entrada padrão e propaga exatamente o código de saída dele.

Exemplo (o hook guarda a entrada padrão, faz o que já fazia e entrega a mesma entrada ao validador):

```bash
#!/usr/bin/env bash
entrada="$(cat)"
# ... o que o hook já fazia, lendo "$entrada" ...
printf '%s\n' "$entrada" \
  | bash "$(git rev-parse --show-toplevel)/.claude/skills/mergex/scripts/portao-push.sh" --pre-push "$@" \
  || exit $?
```

Sequência normativa de recuperação:

1. Na primeira execução, o hook de terceiro ainda não invoca a MergeX: a prova falha, o E0 não
   altera o arquivo, falha fechado (`3`) e mostra a instrução de composição.
2. O responsável compõe o hook à mão, como acima.
3. Na execução seguinte, o E0 não reprova por falta do marcador: executa a prova controlada.
4. O hook composto barra a ref inválida da prova e propaga o código: integração externa válida, o
   E0 prossegue.
5. Se a prova falhar, o hook terminar inesperadamente, liberar a ref inválida ou não propagar o
   código de saída, o E0 continua falhando fechado.
6. A reversão da MergeX não modifica o hook composto (seção "Reversão").

Hook que só **cita** a MergeX (num comentário, numa string) sem executá-la não passa: o
reconhecimento é por comportamento, nunca por busca textual.

## Prova funcional

```bash
bash .claude/skills/mergex/scripts/ativacao-pre-push.sh --provar \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md
```

A mesma prova serve ao E0 e ao E2, e não confia no caminho nem na existência do arquivo:

1. Monta, **sem tocar remoto nem ref**, um commit solto (`git commit-tree`, com índice temporário)
   sobre `HEAD`, com um arquivo de produto e o `ENTREGA.md` do disco em `portao: pronto` e
   `portao_sha` = `HEAD`: um portão sabidamente vencido. O índice, a árvore de trabalho, as refs e o
   remoto não mudam; só ficam objetos soltos, que nenhuma ref alcança.
2. Executa o `pre-push` efetivo como o Git o executaria: na raiz da árvore de trabalho, com os
   argumentos `prova-mergex file:///dev/null`, uma linha de protocolo para
   `refs/heads/<branch da entrega>` com o SHA desse commit solto, e `MERGEX_PRE_PUSH_SINAL`
   apontando para um temporário. O validador de push escreve ali, **depois de decidir** cada ref
   recebida na entrada padrão, a linha `mergex-pre-push <SHA avaliado> <passa|avisa|barra>`, sem
   mudar a decisão.
3. **A prova tem dois lados**, cada um uma execução do hook, e **aprova só com os dois**:
   - **(a) ref aplicável vencida:** o hook sai com código diferente de zero **e** o sinal tem a
     linha `mergex-pre-push <SHA do commit solto desta prova> barra`;
   - **(b) controle positivo:** um segundo commit solto (a árvore de `HEAD`, sem nenhum
     `ENTREGA.md` que declare a branch usada) numa ref **não aplicável**
     (`refs/heads/mergex-prova-livre-<pid>`, conferida como inexistente localmente): o hook sai com
     código **0** **e** o sinal tem `mergex-pre-push <SHA desse commit> passa`.

   O lado (b) pega o que o (a) não distingue: o hook que chama a MergeX mas decide o código por
   regra própria (no push real, ele liberaria um portão vencido) e o ambiente em que o validador
   barra tudo por erro (por exemplo, objetos ou `safe.directory` inacessíveis para ele). Reprovam
   também: `pre-push` ausente ou não executável, término por sinal (código 128 ou mais), a falta de
   qualquer das duas linhas (o validador não rodou, rodou sem receber a entrada, ou a linha foi
   escrita por outro com SHA alheio) e o estouro do orçamento de tempo.
4. **Orçamento de tempo:** 120 s por execução. Vale um `timeout` que comprove, pelo comportamento,
   matar um processo dentro do prazo (GNU, uutils ou outro); sem ele, um vigia em Bash. O hook roda
   em grupo de processos próprio, morto inteiro no estouro e ao fim da prova: nenhum processo fica
   órfão. Estouro reprova — com o `timeout`, o código 124, ou 137 depois do prazo inteiro (o hook
   ignorou o TERM e levou o KILL).

**Limite da prova.** Ela pega erro normal: hook que não chama a MergeX, que só a cita, que a chama
sem a entrada, que não propaga o código, que forja o sinal antigo ou uma linha com outro SHA. Um hook
escrito **de propósito** para forjar a linha certa (lendo o SHA da entrada padrão) é contorno
deliberado, que nenhuma prova local alcança: a barreira contra ele é o CI com proteção de merge,
quando o produto o ativar (spec, seção 13, item 8).

No E2 a prova é barreira inicial, ao lado da `pre-e2`: reprovada, o E2 não começa e nada é
gravado. O resultado do portão é gravado só por `scripts/registrar-portao.sh`, que roda a mesma
prova antes de gravar `portao: pronto` (reprovada: `RESULTADO: BLOQUEADO — pre-push sem prova
funcional`, nada gravado, código `3`). E os checkpoints `pre-e6` e `e8` de `persistir-metodo.sh`
recusam persistir um `ENTREGA.md` com `portao: pronto` sem a prova: sem essa persistência, o
`pronto` nunca chega ao SHA que o `pre-push` avalia.

## Reversão

```bash
bash .claude/skills/mergex/scripts/ativacao-pre-push.sh --reverter \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md
```

- Remove o `pre-push` **só** se ele é o chamador gerenciado, reconhecido pelo marcador.
- Diante de um hook de terceiro, composto ou não, não toca o arquivo: só informa que a integração
  externa precisa ser removida pelo responsável dela, e sai `0`.
- Nunca altera `core.hooksPath`.

Reverter a MergeX (voltar o pin) não desfaz uma composição feita à mão: quem compôs um hook próprio
desfaz a composição por conta própria, e o PR de reversão explica o passo.

## CI

O CI é a barreira **contra contorno deliberado** (`git push --no-verify` ignora o `pre-push`) e a
defesa adicional ao `pre-push`, nunca o substituto dele. Ele repete a decisão do `pre-push` sobre o
SHA real da cabeça do PR, pelo mesmo executável de regra:

```bash
bash .claude/skills/mergex/scripts/portao-ci.sh --verificar --sha <sha40> --branch <nome>
```

- **Mesma regra, mesmo modo.** `portao-ci.sh` não tem regra própria: decide como a ref
  `refs/heads/<nome>` empurrada com o SHA `<sha>` e SHA remoto nulo, chamando a mesma função do
  `pre-push` (`pr_decide_ref`, em `portao-regras.sh`). Imprime `decisao=`, `motivo=` e `entrega=`.
  Portão `pronto` vencido, ausente, inconsistente ou ilegível, `historia_incompleta` e
  `erro_ambiente` reprovam em qualquer modo; `portao: null` segue o modo de `pr-so-com-portao` em
  `.expx/hooks.json`, igual ao `pre-push`.
- **O SHA do PR, não o `HEAD` local.** A decisão é sobre o `--sha` recebido; o commit em que o
  checkout está não entra.
- **Códigos:** `0` passa ou avisa; `1` barra (o diagnóstico vai a stderr, com textos distintos para
  `historia_incompleta`, que manda completar a história, e para `erro_ambiente`); `64` uso. Não existe
  opção de força.
- **História completa.** O clone do CI precisa de `fetch-depth: 0`; clone raso é
  `historia_incompleta` e reprova.
- **Template.** `assets/ci/mergex-portao.yml` roda em `pull_request`, faz o checkout do SHA da
  cabeça do PR com `fetch-depth: 0` e chama `portao-ci.sh` com esse SHA e a branch de origem do PR.
  Os valores do evento entram pelo `env:` do step, nunca interpolados no texto do shell.

### Handoff: esta branch não ativa o CI

Esta branch não ativa CI em nenhum produto: ela entrega o executável, o template e os testes, e nenhum
arquivo vive em `.github/workflows/`. Ativar é handoff posterior e separado, feito no repositório do
produto: copiar o template para `.github/workflows/` e configurar a proteção de merge da branch
principal exigindo o check `mergex-portao`. Sem a proteção de merge exigindo o check, ele não barra
nada. O empacotamento do `pre-push` e do template pelo ExpxDev é outro handoff.

### Condição do PR #192

O PR #192 fica em rascunho até o QA aprovar e até estarem comprovados no produto os três itens:

1. a instalação da MergeX nova com o `pre-push` ativo;
2. o check de CI correspondente com a proteção de merge;
3. os gates.

Enquanto isso não estiver comprovado, nenhum texto deste repositório afirma proteção em vigor.