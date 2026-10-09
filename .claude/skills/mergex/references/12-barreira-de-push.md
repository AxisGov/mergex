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
3. **Aprova só se** o hook sair com código diferente de zero **e** o sinal tiver a linha
   `mergex-pre-push <SHA do commit solto desta prova> barra`. Reprovam: `pre-push` ausente ou não
   executável, término por sinal (código 128 ou mais), código zero (liberou a ref inválida ou não
   propagou o código), a falta dessa linha (o validador não rodou, rodou sem receber a entrada, ou a
   linha foi escrita por outro com SHA alheio) e o estouro do orçamento de tempo.
4. **Orçamento de tempo:** 120 s. Vale um `timeout` que comprove, pelo comportamento, matar um
   processo dentro do prazo (GNU, uutils ou outro); sem ele, um vigia em Bash. O hook roda em grupo
   de processos próprio, morto inteiro no estouro e ao fim da prova: nenhum processo fica órfão.
   Estouro reprova.

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
