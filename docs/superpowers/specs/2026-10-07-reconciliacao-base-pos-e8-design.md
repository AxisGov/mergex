# MergeX — Reconciliação de base pós-E8

## Objetivo

Dar à MergeX um caminho contratual, verificável e fechado para integrar uma base que avançou
**depois** do E8, quando a resolução semântica dessa integração exige ajustar arquivos que nasceram
ou mudaram na base nova e que nenhuma task do plano declara. Hoje esse caso não tem saída: a V9
reprova os arquivos, a SprintX (corretamente) não deixa acrescentá-los a tasks concluídas e não
existe etapa depois do E8.

A correção é da MergeX. O plano continua sendo a fonte do que a feature fez; o que a integração da
base exigiu passa a ter registro próprio, com prova mecânica de origem, revisão humana obrigatória,
gate completo e novo portão.

## Estado de partida

- Branch: `p0.2/mergex-historico-yaml-escalar`.
- HEAD: `bd4c1c58c2ec36635aa365a3e79b3acbc7b7357d` (merge do PR #5 sobre o merge do PR #4).
- `e06a6eecf6d95a5645df7ba95737f5ec15cd622c` é ancestral; é o commit instalado no produto onde o
  defeito apareceu.
- `DM-177` é a última decisão.
- Os checkpoints de método são o enum fechado `pre-e2 | pre-e6 | e8` (DM-162/163).
- A V9 não tem implementação executável: é aplicada pela prosa de
  `.claude/skills/mergex/references/02-prontidao.md` ("V9"), e nenhum teste calcula o diff
  `<branch-base>...HEAD`.

## 1. O defeito real (PR #192 de Conselhos Municipais)

Trabalho da SprintX `mp2-7a-travas-de-acao`, 25 tasks concluídas (`seq` 1..25), E2 `PRONTO`, E3–E8
concluídos, PR aberto em rascunho. Depois do E8, a `main` do produto avançou de `0f030f9` para
`5610b10` (migração de componentes para a biblioteca de UI do projeto, PRs #183–#191 do produto). O
PR passou a `CONFLICTING`.

A integração por merge normal resolveu três conflitos de produção (todos declarados nas tasks) e
exigiu ajustar testes que divergiam semanticamente da interface fundida. Dois deles **nasceram na
base nova** e não pertencem a task nenhuma:

- `tests/ui/compliance-ksmv-primitives.test.tsx` — esperava um botão que a feature dividiu em duas
  etapas;
- `tests/ui/attendance-ksmv-primitives.test.tsx` — montava o modal com um perfil que a feature
  deixou sem as ações do bloco testado.

A resolução passou em testes focados, em duas revisões independentes e no gate completo do
repositório. Mesmo assim a V9, aplicada ao resultado do merge contra a base nova, reprova os dois
arquivos: estão no diff e fora da união dos `arquivos` das tasks. A SprintX recusa acrescentá-los a
T-02.02 e T-02.11 (tasks congeladas) e não abre replanejamento sem task bloqueada e sem fronteira
limpa. O merge ficou preservado, sem commit, à espera desta correção.

Defeitos da mesma família encontrados na investigação, tratados aqui porque a correção depende
deles:

1. **Portão sem vínculo com commit.** O hook `pr-so-com-portao` lê `portao` do `ENTREGA.md` mais
   recente por data de modificação, não do trabalho da branch, e nenhum commit posterior invalida um
   `portao: pronto`. Um merge da base depois do E8 seria publicado sem novo E2.
2. **Base por nome de ref.** `branch_base` grava um nome (`origin/main`, `main`). A V9, o E3 e o E4
   usam `<ref>...HEAD`; o resultado depende de a ref local ter avançado ou não. Com a ref parada e
   o merge feito de outra, o diff passa a conter tudo o que a base trouxe.

## 2. Propriedade

| Componente | Papel nesta correção |
|---|---|
| **MergeX** | Dona. V9, ciclo de vida da entrega, validade do portão, artefato de reconciliação, checkpoint de método, hooks de commit e de push. |
| **SprintX** | Sem mudança. O congelamento de tasks concluídas (DS-143) e o retorno da F6 só sobre escopo não concluído (`03-plano.md`, "Retorno da F6") estão corretos: a base que avança não é defeito de plano. |
| **ExpxDev** | Sem mudança de código. Atualiza o pin/lock da MergeX e os candidatos de certificação. |
| **BuildX** | Sem mudança de código. Integra só por fast-forward e não deixa a base avançar durante uma feature; a falha de V9 continua com a mesma causa (`arquivo_fora_do_plano`), então o mapeamento de recursão não muda. |

Por que a SprintX fica intacta: o plano registra o que a feature **decidiu** fazer. Um ajuste
exigido pela base que andou não é decisão da feature, é consequência de um evento posterior ao
plano. Gravá-lo no plano reescreveria a história de tasks já entregues; gravá-lo na entrega, com
proveniência, registra o evento onde ele aconteceu.

## 3. Alternativas

### A — Reconciliação de base na MergeX (escolhida)

Um registro próprio da entrega, criado depois de integrar a base nova, que declara os arquivos
ajustados pela integração e prova mecanicamente que cada um vem da base. A V9 aceita esses
arquivos somente quando o registro verifica; o E3 os põe em olho obrigatório; o portão volta a
`null` e o E2 roda de novo.

Preserva congelamento, um-commit-por-task, `seq` e V11; o custo é uma etapa nova depois do E8 e a
regra de validade do portão, que de qualquer modo era necessária (defeito 1).

### B — Task especial de integração na SprintX (rejeitada)

Criar, depois do planejamento, uma task só de compatibilidade.

Rejeitada porque:

1. O ajuste mora no próprio merge commit: o merge tem de estar verde, e só fica verde com os testes
   ajustados. A task ficaria sem commit próprio, e o E1 não aceita merge commit
   (`fechamento-do-e1.sh --registrar-existente` recusa, coberto em `test-m2-lifecycle-recuperacao.sh`).
   A alternativa seria um merge commit vermelho seguido do commit da task, o que quebra o gate.
2. Consumiria `seq` novo e exigiria F3, F4 e F5 completos para um ajuste mecânico, reabrindo uma
   entrega já certificada.
3. Exigiria um tipo de task inexistente (o contrato da task tem campos fixos) e a regra de
   "trabalho novo depois do fechamento", que a SprintX não tem e não deve ganhar por causa da base.
4. A proteção contra expansão de escopo seria só a auditoria F5: uma task declara o que quiser.

### C — Extensão append-only de tasks concluídas (rejeitada)

Permitir acrescentar só `arquivos` a uma task concluída.

Rejeitada porque:

1. Quebra a DS-143: a assinatura das congeladas cobre o item inteiro; dividi-la em núcleo e
   extensões cria exatamente a porta que o congelamento existe para fechar.
2. Faz o histórico mentir: declararia que a T-02.02 alterou um arquivo que o commit dela nunca
   tocou; a relação task ↔ commit, que a V11 e o ownership do E1 pressupõem, deixa de ser verdade.
3. É o pior risco de escopo escondido: qualquer arquivo poderia ser pendurado em qualquer task
   concluída, sem prova de origem.

## 4. Invariantes

1. **Tasks concluídas permanecem congeladas.** Nada nesta correção grava ou propõe gravar
   `tasks.md`, `sprint.md`, `fases.md` ou `00-PLANEJAMENTO.md`; o plano só é lido, para compor a
   união da V9 e para a prova 3. A reconciliação nunca altera `arquivos` de task nenhuma.
2. **Um commit por task continua verdadeiro.** O merge commit não é E1, não tem `Task:` e não
   entra em `ENTREGA.commits`; o commit de método da reconciliação também não.
3. **Nenhum `seq` novo.** `sequencia-de-commits.sh` não é chamado pela reconciliação; a lista
   `commits` e a V11 ficam idênticas.
4. **Reconciliação não esconde expansão de escopo.** Só é elegível o arquivo que a base nova criou
   ou alterou, que a feature não tocou antes do merge, que nenhuma task declara e que o merge de
   fato mudou em relação à base nova; todo arquivo reconciliado é olho obrigatório no E3; qualquer
   commit de produto posterior invalida o portão.
5. **Falha fechada.** Toda prova que não pode ser calculada reprova. Não existe flag, variável de
   ambiente nem modo de hook que pule a reconciliação, a V9 executável ou a validade do portão.

## 5. Modelo Git

| Símbolo | O que é | Como é obtido |
|---|---|---|
| `B0` | Última base validada da entrega | `base_validada_sha` do `ENTREGA.md` (E0, ou a `B1` da reconciliação anterior) |
| `P1` | A feature imediatamente antes do merge | primeiro pai de `M` |
| `B1` | A base nova integrada | segundo pai de `M` |
| `M` | O merge reconciliado | o commit de integração, com exatamente dois pais |

Condições estruturais, todas obrigatórias:

- `M` tem exatamente dois pais; `P1 = M^1`, `B1 = M^2`.
- `B0` é ancestral de `B1` (`git merge-base --is-ancestor B0 B1`).
- `B0` é ancestral de `P1`.
- `M` está na linha de primeiro pai de `HEAD` (o merge pertence à branch do trabalho, não a um
  ramo lateral).
- `B1` é ancestral da ponta atual da ref de base (`branch_base`) no momento do registro.
- A mensagem de `M` tem exatamente um `Trabalho: <trabalho_id>` igual ao da `ENTREGA.md`, um
  `Integra-base:` seguido do SHA completo de `B1`, e nenhum `Task:` nem `Metodo:`.

`M` não é criado pela MergeX: é o merge que a pessoa (ou o agente, sob autorização) concluiu. A
MergeX valida e registra.

## 6. As quatro provas de elegibilidade

Para cada caminho `f` declarado na reconciliação, com renomeação desligada (`--no-renames`):

| # | Prova | Comando de referência | Reprova quando |
|---|---|---|---|
| 1 | `f` nasceu ou mudou na base entre `B0` e `B1` | `git diff --no-renames --name-status B0 B1 -- f` | vazio; ou status `D` (a base removeu `f`); ou mudança de tipo (`T`), que também reprova |
| 2 | A feature não tocou `f` antes do merge | `git rev-list --first-parent P1 ^<início> -- f` | não vazio, salvo merges de reconciliações anteriores que já listam `f` |
| 3 | `f` não consta das tasks | união de `arquivos.cria` + `arquivos.altera` do plano corrente, e catálogo de método | `f` está na união ou é artefato de método |
| 4 | Existe diferença real entre `B1` e `M` | `git diff --quiet --no-renames B1 M -- f` | sem diferença; ou `f` ausente em `M` (a integração removeu `f`) |

`<início>` da prova 2 é `B0` na primeira reconciliação e o `M` da reconciliação anterior nas
seguintes.

Consequências deliberadas:

- Renomeação na base vale como remoção mais criação: só o caminho novo pode ser elegível.
- Arquivo removido pela base e mantido pela integração é ressurreição, não ajuste: reprova.
- Arquivo da base removido pela integração é perda de cobertura: reprova.
- Arquivo que já está nas tasks não precisa de reconciliação: o registro o recusa, para que nada
  seja coberto por dois caminhos.

## 7. Artefato

`docs/entregas/<trabalho_id>/RECONCILIACAO-BASE-NNN.md`, com `NNN` de três dígitos, a partir de
`001`, contínuo e sem lacunas. Um arquivo por merge de base integrado. É artefato de método da
MergeX: entra no catálogo, nunca no commit de uma task.

### 7.1 Frontmatter

| Chave | Tipo | Regra |
|---|---|---|
| `expx_schema` | inteiro | `1` |
| `expx_tool` | enum | origem do trabalho, igual ao `ENTREGA.md`: `sprintx` \| `runx` |
| `kind` | enum | `reconciliacao_base` |
| `trabalho_id` | texto | igual ao `ENTREGA.md` |
| `numero` | inteiro | `1`, `2`, ... igual ao `NNN` do nome do arquivo |
| `anterior` | texto ou nulo | nome do artefato anterior; `null` só no `001` |
| `branch` | texto | igual a `ENTREGA.branch` |
| `branch_base` | texto | nome da ref de base, só informativo; as provas usam os SHAs |
| `origem_base` | enum | `registrada_e0` \| `inferida_legado` \| `reconciliacao_anterior` |
| `b0_sha` | SHA-1, 40 hex | `B0` |
| `p1_sha` | SHA-1, 40 hex | `P1` |
| `b1_sha` | SHA-1, 40 hex | `B1` |
| `m_sha` | SHA-1, 40 hex | `M` |
| `estado` | enum | `ativa` \| `superada` |
| `arquivos` | lista | um item por caminho reconciliado; `[]` quando a integração não exigiu ajuste |
| `arquivos[].caminho` | texto | caminho relativo à raiz, exatamente como no Git |
| `arquivos[].status_base` | enum | `A` (nasceu entre `B0` e `B1`) \| `M` (mudou entre `B0` e `B1`) |
| `arquivos[].blob_b1` | SHA-1, 40 hex | `git rev-parse B1:<caminho>` |
| `arquivos[].blob_m` | SHA-1, 40 hex | `git rev-parse M:<caminho>` |
| `arquivos[].diff_b1_m_sha256` | sha256, 64 hex | ver abaixo |
| `arquivos[].motivo` | texto | uma linha: o que da feature tornou o ajuste necessário |
| `registrado_em` | data ISO | data do sistema no registro |
| `assinatura` | sha256, 64 hex | ver abaixo |

Regras:

- Todas as chaves sempre presentes; lista vazia é `[]`. Um merge de base sem arquivo a reconciliar
  gera o artefato com `arquivos: []`: é ele que avança a base validada.
- SHAs sempre completos (40 hex), nunca nome de ref.
- `motivo` é texto de uma linha, não vazio, sem marcador de template; é para o revisor, não entra
  em prova.
- `diff_b1_m_sha256` é o sha256 da saída de
  `git -c core.quotepath=false -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.suppressBlankEmpty=false -c diff.relative=false diff --no-ext-diff --no-textconv --no-color --binary --full-index --no-renames --no-relative --src-prefix=a/ --dst-prefix=b/ -U3 --inter-hunk-context=0 --diff-algorithm=myers --indent-heuristic B1 M -- <caminho>`,
  rodado da raiz do repositório, com pathspec literal. As flags explícitas tornam o valor
  independente da configuração local e do clone (a linha `index` sai com SHA completo).
- `assinatura` é o sha256 das linhas canônicas, em ordem de byte:
  `numero`, `anterior`, `trabalho_id`, `b0_sha`, `p1_sha`, `b1_sha`, `m_sha`, e uma linha por
  arquivo `caminho\tstatus_base\tblob_b1\tblob_m\tdiff_b1_m_sha256`. Editar o artefato à mão quebra
  a assinatura.

### 7.2 Estados

| Estado | Significado | Quem grava |
|---|---|---|
| `ativa` | Última reconciliação da cadeia, ou anterior ainda necessária | `--registrar` |
| `superada` | Uma reconciliação seguinte da mesma entrega já a encadeou | `--registrar` da seguinte |

Não existe estado editável à mão nem estado "aceita com ressalva". `superada` não remove cobertura:
os arquivos de uma reconciliação superada continuam cobertos enquanto o conteúdo em `HEAD` for o
`blob_m` registrado (seção 9).

### 7.3 Prosa

Abaixo do frontmatter: um parágrafo com a base integrada e o PR, e uma tabela por arquivo
(caminho, status na base, motivo). Sem frontmatter extra, sem cópia de diff.

## 8. Comandos

Novo executável `scripts/reconciliacao-base.sh`.

### `--registrar`

```bash
bash .claude/skills/mergex/scripts/reconciliacao-base.sh --registrar \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md \
  --origem <sprintx|runx> --trabalho <trabalho_id> \
  [--merge <sha>] -- <caminho-1> <caminho-2> ...
```

- Sem `--merge`, `M` é `HEAD`. Com `--merge <sha>`, registra um merge anterior ainda não publicado
  (`M` na linha de primeiro pai de `HEAD`, entre a base validada e `HEAD`), para encadear merges
  concluídos antes de a MergeX nova estar instalada.
- Exige: stage vazio; nenhum merge em andamento (`MERGE_HEAD` ausente); branch ativa igual a
  `ENTREGA.branch`; contexto explícito igual a `ENTREGA.trabalho_id`/`expx_tool`; a trava C5 do
  índice adquirida.
- Calcula as condições estruturais (seção 5) e as quatro provas (seção 6) para cada caminho dado.
- **Inventário completo**: calcula também o conjunto `git diff --name-only --no-renames B1 M` e
  exige que todo caminho desse conjunto esteja na união das tasks, no catálogo de método ou na
  lista dada. Um caminho alterado pelo merge e não declarado reprova o registro inteiro: não existe
  registro parcial.
- Grava o artefato `NNN` seguinte, marca o anterior como `superada` e atualiza o `ENTREGA.md`
  (seção 11). Não faz commit: quem persiste é o checkpoint `reconciliacao-base`.
- Sem `--force`, sem `--sem-prova`, sem variável de ambiente que relaxe prova.

### `--verificar`

```bash
bash .claude/skills/mergex/scripts/reconciliacao-base.sh --verificar \
  --entrega docs/entregas/<trabalho_id>/ENTREGA.md \
  --origem <sprintx|runx> --trabalho <trabalho_id>
```

Só leitura. Para toda a cadeia `001..NNN`:

- numeração contínua, `anterior` encadeado, `b0_sha` de cada uma igual ao `b1_sha` da anterior, e o
  `b0_sha` do `001` igual ao `base_validada_sha` original da entrega;
- assinatura recalculada igual à gravada;
- condições estruturais e as quatro provas recalculadas sobre o histórico atual;
- para cada caminho coberto: o conteúdo em `HEAD` é o `blob_m` da reconciliação mais recente que o
  lista. Arquivo reconciliado alterado depois de `M` deixa de estar coberto, e a verificação
  reprova.

Saída: `ok=true` e uma linha `coberto\t<caminho>\t<NNN>` por arquivo; ou `ok=false` e uma linha
`motivo\t<código>\t<detalhe>` por falha.

### Códigos de saída (os dois modos)

| Código | Significado |
|---|---|
| 0 | registrado / verificado |
| 2 | trava C5 ocupada |
| 3 | stage não vazio ou merge em andamento |
| 4 | prova reprovada (estrutura, uma das quatro provas, inventário incompleto) |
| 5 | contrato do artefato ou do `ENTREGA.md` inválido (numeração, encadeamento, assinatura) |
| 6 | base validada indeterminável (legado ambíguo) |
| 64 | uso incorreto |

## 9. Checkpoint de método `reconciliacao-base`

O enum de `persistir-metodo.sh`, `contrato-de-commit.sh` e `catalogo-de-metodo.sh` passa a
`pre-e2 | reconciliacao-base | pre-e6 | e8`.

- Catálogo do checkpoint: `docs/entregas/<trabalho_id>/ENTREGA.md` e os
  `RECONCILIACAO-BASE-NNN.md` sujos. Nada de produto, de teste ou de plano.
- Mensagem:

  ```
  chore(mergex): persiste metodo reconciliacao-base

  Trabalho: <trabalho_id>
  Metodo: reconciliacao-base
  ```

- Mesma trava, mesma varredura de segredo, mesmo stage vazio na entrada, sem commit vazio.
- Não entra em `ENTREGA.commits`, não consome `seq`, não satisfaz V11.
- `--verificar --checkpoint reconciliacao-base` é a barreira que o E2 exige quando a entrega tem
  reconciliação: artefatos e `ENTREGA.md` persistidos e `reconciliacao-base.sh --verificar` com
  `ok=true`.

## 10. V9 executável

Novo executável `scripts/portao-v9.sh --verificar --entrega <ENTREGA.md> --origem <...> --trabalho <...>`.
A prosa de `02-prontidao.md` passa a mandar rodá-lo; o resultado dele é a V9.

1. **Base do diff por SHA, não por nome.** `B` é o `b1_sha` da última reconciliação ativa, ou o
   `base_validada_sha` da entrega quando não há reconciliação. O conjunto é
   `git diff --name-only --no-renames B...HEAD`. Isso fecha o defeito 2: mover a ref local não muda
   o resultado.
2. **Conjunto aceito**, composto nesta ordem:
   - união de `arquivos.cria` + `arquivos.altera` de todas as tasks do plano corrente (a V9
     continua usando a união; DM-152 vale);
   - artefatos de método do trabalho (pasta do trabalho, `docs/entregas/<trabalho_id>/`,
     `docs/sprintx/estimativas/HISTORICO.md` só na SprintX) — isenções existentes, inalteradas;
   - caminhos com `coberto` na saída de `reconciliacao-base.sh --verificar`, e só se ela devolver
     `ok=true`.
3. **Resultado:** cada caminho do diff fora do conjunto aceito é uma linha
   `fora_do_plano\t<caminho>`; qualquer linha é `FALHA` em V9. `--verificar` da reconciliação com
   `ok=false` é `FALHA` registrada como `v9_sem_prova`.
4. A V9 do hook `arquivo-fora-do-plano` (sobre `git diff --cached`) não muda de semântica; ganha
   apenas o reconhecimento do commit de integração da base (seção 12).

## 11. ENTREGA.md

Chaves novas, sempre presentes:

| Chave | Valor |
|---|---|
| `base_validada_sha` | SHA de 40 hex da base em que o trabalho foi validado; gravado no E0; atualizado pelo `--registrar` para o `b1_sha` registrado |
| `origem_base` | `registrada_e0` \| `inferida_legado` |
| `reconciliacoes` | lista `{numero, arquivo, b1_sha, m_sha}`, na ordem; `[]` sem reconciliação |
| `portao_sha` | SHA de 40 hex do `HEAD` que o E2 avaliou; `null` antes do E2 e depois de um `--registrar` |

`--registrar` também reabre a entrega como a retomada do E0 já faz: `estado: aberto`,
`portao: null`, `portao_sha: null`, `falhas_portao: []`, `causa: null`, `push_feito: false`,
`entregue_em: null`; preserva `commits`, `criado_em`, `pr_url`, `pr_estado`, `desvios`.
`causa-do-portao.sh --validar` não muda: a combinação `aberto`/`null` já é válida.

## 12. E3 e commits

- **E3:** novo critério `O10 — arquivo reconciliado da base`, avaliado antes de L e D. Todo caminho
  `coberto` é olho obrigatório, e a justificativa cita `RECONCILIACAO-BASE-NNN.md` e o `motivo`. O
  `classificar-atencao.sh` recebe a lista coberta e não aceita rebaixar um reconciliado. O E3 roda
  só sobre o delta desde o último `ATENCAO.md` e regrava o arquivo inteiro.
- **Commit de integração da base:** `contrato-de-commit.sh` ganha a classe "integração de base"
  (dois pais, `Trabalho:` e `Integra-base:`, sem `Task:` e sem `Metodo:`). O hook `commit-por-task`
  a reconhece e não a trata como mistura de tasks; o hook `arquivo-fora-do-plano`, num commit dessa
  classe, avalia só os caminhos que diferem do segundo pai (o que a integração mudou), não tudo o
  que veio da base.

## 13. Validade do portão

1. O E2 grava `portao_sha` = `HEAD` avaliado, junto com `portao`.
2. O portão vale para um `HEAD` posterior somente se **todo** commit em `portao_sha..HEAD`:
   - é commit de método válido de `pre-e6` ou `e8`, pela gramática de `contrato-de-commit.sh`
     (`reconciliacao-base` não entra: o registro já devolve o portão a `null`); e
   - toca apenas caminhos do catálogo daquele checkpoint; e
   - tem um único pai.
3. Qualquer commit de produto, de teste, de plano, ou merge (inclusive de base nova) em
   `portao_sha..HEAD` invalida o portão. `portao_sha` ausente, não ancestral de `HEAD` ou `null`
   com `portao: pronto` também invalida.
4. Novo `scripts/validade-do-portao.sh --verificar --entrega <ENTREGA.md>` implementa 1–3, só
   leitura, `ok=true|false` e o primeiro commit que invalidou.
5. **Hook de push** (`pr-so-com-portao`): resolve o `ENTREGA.md` pelo trabalho da branch ativa (o
   mesmo resolvedor dos outros hooks; nunca por data de modificação) e exige
   `validade-do-portao.sh --verificar` com `ok=true`. Essa condição barra mesmo com o hook em modo
   `aviso`, como a regra de task irmã do `commit-por-task`: é a condição que, deixada passar,
   publicaria código não avaliado.
6. **E6 e E7** exigem a mesma validade como pré-requisito, além do `pre-e6`.

## 14. Compatibilidade e base legada

- **Execução nova:** o E0 grava `base_validada_sha = git merge-base HEAD <branch_base>` e
  `origem_base: registrada_e0`.
- **Entrega anterior a esta versão** (sem `base_validada_sha`): na primeira reconciliação, e só
  nela, o `--registrar` infere `B0 = git merge-base P1 B1` e grava `origem_base: inferida_legado`
  no `ENTREGA.md` e no artefato `001`. A inferência falha fechada (código 6) quando:
  - há mais de um merge-base (`git merge-base --all` com mais de um resultado);
  - a linha de primeiro pai de `P1` desde o merge-base já contém algum merge commit;
  - o merge-base não é ancestral de `B1`.
- Depois de gravada, a base nunca é inferida de novo: as seguintes vêm da cadeia.
- **Múltiplas reconciliações:** cada merge de base gera o `NNN` seguinte; `b0_sha` do novo é o
  `b1_sha` do anterior; o anterior vira `superada`. Merges concluídos antes da instalação podem ser
  registrados em ordem com `--merge <sha>`, um por vez, do mais antigo para o mais novo.
- **Entrega sem reconciliação:** comportamento idêntico ao atual, com a base fixada por SHA.

## 15. Falhas fechadas

| Situação | Resultado |
|---|---|
| Merge em andamento ao registrar ou persistir | Código 3; nada gravado |
| `M` com número de pais diferente de 2, pais trocados, ou fora da linha de primeiro pai | Código 4 |
| Qualquer uma das quatro provas reprovada | Código 4; nenhum artefato |
| Caminho alterado pelo merge e não declarado (inventário) | Código 4; nenhum artefato |
| Artefato editado à mão (assinatura) ou cadeia quebrada | `--verificar` código 5; V9 `v9_sem_prova` |
| Arquivo reconciliado alterado depois de `M` | Deixa de estar coberto; V9 `FALHA` |
| Base legada ambígua | Código 6; nada gravado |
| Portão vencido no push | Hook barra, em qualquer modo |
| Ferramenta ausente (`git`, `jq`) | Reprova; nunca degrada para aprovado |

Não existe flag de bypass em nenhum dos executáveis. O validador de contrato procura e reprova
qualquer opção de força nesses scripts.

## 16. Fluxo completo depois de uma reconciliação

1. Merge normal da base nova, resolução semântica, testes focados e revisão da resolução.
2. Commit de integração `M` (seção 12).
3. Gate completo do repositório (o do `ORQUESTRADOR.md`; no PR #192, o D-44) sobre `HEAD`.
4. `reconciliacao-base.sh --registrar` com os caminhos ajustados.
5. Checkpoint `reconciliacao-base`.
6. E2 completo: barreira `reconciliacao-base` + V1–V11 com a V9 executável; grava `portao` e
   `portao_sha`. `BLOQUEADO` encerra como hoje (E8 bloqueado, sem push).
7. E3 sobre o delta, com O10 para os reconciliados.
8. E4 e E5 regravados (lista de arquivos, testes, colaterais).
9. Checkpoint `pre-e6`.
10. E6: push, exigindo portão válido (seção 13).
11. E7: retomada do PR existente (nunca um segundo PR).
12. E8 e checkpoint `e8`; push final do registro.

## 17. Retomada do PR #192

Estado preservado: merge em andamento sobre `e16410e9626efea7e3b0764f90ee735f3b5e4918`, com
`MERGE_HEAD = 5610b10afb5b27dacf1dee02aa1418a9ce69e6f0`, resolução completa no índice (três
arquivos de produção e dez arquivos de teste ajustados), gate completo verde sobre essa árvore
(117 arquivos, 1378 testes), duas revisões independentes sem defeito aberto.

1. **Não abortar e não refazer a resolução.** Ela é o insumo do primeiro `M`.
2. Com autorização explícita do responsável, concluir o merge **localmente**, sem publicar, com a
   resolução exatamente como está no índice: `M1`, mensagem com `Trabalho: mp2-7a-travas-de-acao`
   e `Integra-base: 5610b10afb5b27dacf1dee02aa1418a9ce69e6f0`. Nenhum push até o passo 7.
3. A MergeX nova chega à `main` de Conselhos por um PR de instalação separado, com base `B2`.
   Instalar na própria feature tornaria `.claude/**` e `.expx/**` arquivos fora do plano.
4. Integrar `B2` na feature: `M2`. Os arquivos de framework vêm da base e não entram no diff contra
   `B2`. Se `B2` trouxer novos conflitos de produto, eles seguem o passo 1 do fluxo.
5. Gate completo sobre o `HEAD` resultante.
6. Registrar em ordem: `--registrar --merge M1 -- tests/ui/compliance-ksmv-primitives.test.tsx
   tests/ui/attendance-ksmv-primitives.test.tsx` (legado: `origem_base: inferida_legado`,
   `B0 = 0f030f9d83101cdaa8c52f457be6163b81eb2072`); depois `--registrar` para `M2` (com
   `arquivos: []` se nada mais for ajustado). Checkpoint `reconciliacao-base`.
7. Fluxo da seção 16 a partir do E2; push só com portão válido; PR #192 continua em rascunho até o
   QA aprovar.

Dos dez arquivos de teste ajustados no merge, oito estão declarados em tasks (os `mp2-7a-*`,
`conferencias-mp2-7a` e os dois `checklists-*`) e passam pela V9 normalmente; só os dois nascidos
na base precisam de reconciliação.

## 18. Implantação

1. **PR da MergeX** sobre `p0.2/mergex-historico-yaml-escalar`, a partir desta branch: executáveis
   novos, prosa de E0/E2/E3/E6/E7/E8, schema, hooks, testes e decisões.
2. **Recertificação** da MergeX: todas as suítes `scripts/ci/test-*.sh`, todos os mutantes,
   `validate-mergex-contract.sh` e `.claude/hooks/teste.sh`.
3. **ExpxDev:** atualizar o pin da MergeX e os candidatos de certificação
   (`src/teste/candidatos.ts` e `fixtures/candidatos/`) e rodar a certificação P0.2. Sem mudança
   de código: o checkpoint e o artefato novos são da skill; o enum de modos de hook e as chaves de
   `.expx/hooks.json` não mudam.
4. **Conselhos Municipais:** PR separado de instalação na `main` (`.claude/**`, `.expx/**`), com
   o lock novo e `doctor` limpo. Nada da feature entra nesse PR.
5. **Retomada do PR #192** pela seção 17.

## 19. Reversão

- Reverter a MergeX é voltar o pin para o commit anterior e reinstalar. Não há migração de dados:
  as chaves novas do `ENTREGA.md` e os artefatos ficam como documentação.
- Uma entrega que dependia de reconciliação volta a reprovar na V9 da versão antiga — falha
  fechada, nunca aprovação indevida.
- O hook de push antigo volta a ler o portão por data; a reversão reabre o defeito 1, e isso deve
  constar do PR de reversão.

## 20. Fora de escopo

- Qualquer mudança na SprintX, inclusive a brecha observada de `defeito_de_plano` com `task: null`
  abrir rodada sem task bloqueada (`planejamento.sh`), que fica registrada para a SprintX tratar.
- Qualquer mudança de código no BuildX ou no ExpxDev.
- Suporte do painel ao `kind: reconciliacao_base`.
- Rebase, cherry-pick ou squash da base; reconciliação de renomeação como tal; ressurreição ou
  remoção de arquivos da base.
- Merge automático da base pela MergeX: a integração continua humana.
- Publicação automática: nada desta correção faz push fora do E6/E8.

## 21. Plano de testes

Fixtures em repositórios Git reais e temporários, montadas pelos helpers de `scripts/ci/lib/` e por
`scripts/ci/fixtures/e2e-p0-2/` (base, head, `base-sha.txt`).

### Suíte nova `scripts/ci/test-r1-reconciliacao-base.sh`

Fixture-base: plano com tasks concluídas, `ENTREGA.md` entregue com portão `pronto` e
`portao_sha`; a base avança criando dois arquivos de teste e alterando um arquivo de produção que a
feature também altera; merge com conflito resolvido e os dois testes ajustados.

Positivos:

1. Reprodução exata do PR #192: os caminhos `tests/ui/compliance-ksmv-primitives.test.tsx` e
   `tests/ui/attendance-ksmv-primitives.test.tsx` nascem na base (status `A`), são ajustados no
   merge; V9 reprova antes do registro e aprova depois.
2. `--merge <sha>` registra `M1` com `HEAD` já em `M2`; a cadeia `001 → 002` verifica.
3. Merge de base sem ajuste gera `arquivos: []` e avança a base validada.
4. Legado sem `base_validada_sha`: inferência única, `origem_base: inferida_legado`.
5. Arquivo com `status_base: M` (mudou na base) e ajustado: elegível.
6. Commit só de método depois do portão: portão continua válido; push aceito.

Negativos (um caso por regra):

7. Arquivo que a base não tocou.
8. Arquivo tocado pela feature antes do merge.
9. Arquivo declarado em task.
10. Arquivo sem diferença entre `B1` e `M`.
11. Arquivo removido pela base e mantido.
12. Arquivo da base removido pela integração.
13. Renomeação na base: caminho antigo recusado.
14. Caminho alterado pelo merge e não declarado (inventário).
15. `M` com um pai, com pais trocados, ou fora da linha de primeiro pai.
16. Mensagem de `M` sem `Integra-base:`, com `Task:` ou com `Metodo:`.
17. Merge em andamento e stage preenchido.
18. Artefato editado (assinatura), numeração com lacuna, `anterior` errado.
19. Arquivo reconciliado alterado depois de `M`.
20. Legado ambíguo: dois merge-bases; merge prévio na linha de primeiro pai.
21. Portão vencido: commit de produto depois de `portao_sha`; merge de base depois de
    `portao_sha`; commit `Metodo:` que toca caminho fora do catálogo; `portao_sha` não ancestral.
22. Hook de push resolve o `ENTREGA.md` pela branch, mesmo com outro `ENTREGA.md` mais recente.
23. Nenhuma opção de força aceita em nenhum dos executáveis novos.
24. Nenhum `tasks.md`, `sprint.md`, `fases.md` ou `00-PLANEJAMENTO.md` alterado por qualquer
    comando da suíte (hash antes e depois).
25. `ENTREGA.commits` e o próximo `seq` idênticos antes e depois.

### Suítes existentes ampliadas

- `test-portao-v11.sh`: portão completo com V9 executável e base por SHA.
- `test-m2-lifecycle-recuperacao.sh`: checkpoint `reconciliacao-base` (enum, catálogo, stage, noop,
  não entra em `commits`); `--registrar-existente` continua recusando merge commit.
- `.claude/hooks/teste.sh`: `commit-por-task` e `arquivo-fora-do-plano` no commit de integração;
  `pr-so-com-portao` com portão válido, vencido e `ENTREGA.md` de outro trabalho mais recente.
- `test-causa-portao.sh`: reabertura `entregue → aberto` pelo registro.
- `test-atencao-metodo.sh`: O10 e recusa de rebaixar reconciliado.
- `test-integracao-c7a.sh`, `test-m1-ownership-contextual.sh`, `test-m4b-arvore-inteira.sh`,
  `test-ownership-task.sh`: a união continua a mesma; arquivo nascido na base sem reconciliação
  continua `desvio` no E1.
- `validate-mergex-contract.sh`: prosa de E0, E2, E3, E6, E7, E8, schema e checkpoint; ausência de
  flag de força.

### Mutantes (`scripts/ci/mutacao-r1-reconciliacao-base.sh`)

Cada um tem de reprovar ao menos um caso:

1. Prova 1 desligada.
2. Prova 1 aceitando status `D`.
3. Prova 2 sem `--first-parent`.
4. Prova 3 desligada.
5. Prova 4 desligada.
6. Inventário do merge desligado.
7. Assinatura não conferida.
8. Encadeamento `b0 = b1 anterior` não conferido.
9. Cobertura sem conferir `blob_m` em `HEAD`.
10. V9 com base por nome de ref em vez de SHA.
11. Portão aceitando commit de produto depois de `portao_sha`.
12. Portão aceitando merge depois de `portao_sha`.
13. Hook de push lendo o `ENTREGA.md` mais recente.
14. Hook de push respeitando modo `aviso` para portão vencido.
15. Inferência legada aceitando dois merge-bases.
16. Registro gravando `seq` ou tocando `tasks.md`.
17. O10 permitindo faixa média para reconciliado.

## 22. Critérios de sucesso

1. Todas as suítes `scripts/ci/test-*.sh` e `.claude/hooks/teste.sh` verdes; os 17 mutantes novos
   e todos os existentes mortos; `validate-mergex-contract.sh` verde.
2. A reprodução do PR #192 (caso 1) reprova na V9 antes do registro e aprova depois, sem nenhuma
   alteração em arquivo de plano.
3. Nenhum arquivo da SprintX, do BuildX ou do código do ExpxDev muda; no ExpxDev mudam só pin e
   candidatos, e a certificação P0.2 passa.
4. Em Conselhos, depois da seção 17: `persistir-metodo --verificar` limpo em todos os checkpoints;
   E2 `PRONTO` com V9 OK; sequência `1..25` e V11 OK; `portao_sha` igual ao `HEAD` avaliado; push
   aceito pelo hook; PR #192 sem conflito e com os checks do repositório verdes; nada integrado em
   `main` pela MergeX.

## Decisões propostas

- `DM-178`: base que avança depois do E8 é evento da entrega, não defeito de plano; o registro é da
  MergeX (reconciliação de base) e nunca altera task.
- `DM-179`: arquivo reconciliado só com as quatro provas e inventário completo do merge; sem
  registro parcial e sem bypass.
- `DM-180`: a V9 é executável e usa a base validada por SHA; a união das tasks continua sendo o
  conjunto do plano (DM-152 mantida).
- `DM-181`: o portão vale para um SHA; só commits de método de um pai e dentro do catálogo mantêm a
  validade; o hook de push resolve o trabalho pela branch e barra portão vencido em qualquer modo.
- `DM-182`: arquivo reconciliado é olho obrigatório (O10).
- `DM-183`: base legada é inferida uma única vez, com `origem_base: inferida_legado`, e a
  inferência ambígua falha fechada.
