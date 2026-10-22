# Patch de integração — legadox × mergex

Prompt pronto para colar no repositório da skill `legadox`. Ele altera a `legadox` para **expor** os artefatos que a `mergex` consome, em formato estável e localizável.

Trabalhe de forma autônoma até o fim: não faça perguntas, não peça autorização para editar arquivos, não pare no meio.

---

## PARTE 1 — O CONTRATO

A `mergex` cuida do versionamento e da entrega: cria a branch, commita cada task, verifica a prontidão, **classifica o diff por atenção humana**, monta a descrição do pull request e o pacote do QA.

A `legadox` é uma **camada modificadora**: não tem fluxo próprio nem estágios, e é acionada pela presença de `docs/legado/PERFIL.md`. Ela calcula raio de impacto, exige testes de caracterização, orçamento de mudança e plano de reversão.

### A diferença deste patch para os das outras irmãs

**A `legadox` não aciona a `mergex`, e a `mergex` não aciona a `legadox`.** Não há ponto de acionamento a inserir. O que existe é **consumo de artefato**: a `mergex` lê o que a `legadox` já produziu.

Por isso este patch não acrescenta chamada nenhuma. Ele faz uma coisa só: **garantir que o que a `legadox` produz seja localizável e legível por outra skill**, em vez de estar disperso em prosa.

### O que a mergex consome, e para quê

| Artefato da legadox | Usado pela mergex em |
|---|---|
| **Zonas de risco** do `PERFIL.md` | Classificação: arquivo em zona de risco é **sempre** OLHO OBRIGATÓRIO, mesmo com uma linha alterada |
| **Faixa de raio** (BAIXO, MÉDIO, ALTO), sinais e zonas tocadas | Portão (barra sem raio); classificação (raio ALTO é OLHO OBRIGATÓRIO); seção de raio do PR; registro da entrega; ordenação da revisão manual |
| **Testes de caracterização** e o que congelaram | Portão (barra em raio MÉDIO/ALTO sem caracterização); classificação (rebaixa para LEITURA RÁPIDA); seção "o que foi congelado" do PR |
| **Plano de reversão** | Portão (barra sem reversão); classificação (efeito irreversível é OLHO OBRIGATÓRIO); seção "como reverter" do PR |
| **Orçamento de mudança** | Portão (barra se estourado) |
| **Aprovação humana de raio ALTO** | Portão (barra sem aprovação) |
| **`DIVIDA.md`** | Seção "fora de escopo" do PR e do pacote de QA |

### As duas regras deste contrato

**1. Ausência da `mergex` nunca muda a `legadox`.** Nada do que este patch acrescenta depende da `mergex` estar instalada: são artefatos que a `legadox` produz de qualquer forma, apenas em formato estável.

**2. O comando de revisão NUNCA é encadeado.** A `legadox` não menciona, não sugere e não aciona `/mergex-revisar` em lugar nenhum.

---

## PARTE 2 — O QUE ALTERAR

### 2.1 Tornar as zonas de risco localizáveis no `PERFIL.md`

A `mergex` precisa **casar o caminho de um arquivo do diff com uma zona de risco**. Isso exige que as zonas estejam declaradas como caminhos ou padrões de caminho, não só descritas em prosa.

No template e no roteiro do `PERFIL.md`, garanta uma seção com esta forma:

> ## Zonas de risco
>
> | Zona | Caminhos | Por que é zona de risco |
> |---|---|---|
> | fiscal | `src/fiscal/`, `src/nota/calculo*` | cálculo de imposto; erro gera autuação |
> | folha | `src/folha/` | cálculo de salário; erro atinge todos os funcionários |
>
> A coluna **Caminhos** é lida por outras skills: use caminhos relativos à raiz do repositório, uma pasta ou um padrão simples por linha. A prosa da terceira coluna é para humano.

Se o `PERFIL.md` já descreve zonas em prosa, acrescente a tabela **sem remover a prosa**: as duas convivem.

### 2.2 Registrar a faixa de raio de forma legível

O raio precisa ser encontrável por trabalho, não só narrado.

Onde a `legadox` registra o cálculo de raio, garanta que constem, explicitamente:

- a **faixa**, em uma linha própria e literal: `FAIXA: BAIXO`, `FAIXA: MEDIO` ou `FAIXA: ALTO`;
- os **sinais** que determinaram a faixa, um por linha;
- as **zonas tocadas** pelo trabalho, pelos nomes usados na tabela de zonas do `PERFIL.md`;
- os **arquivos** atribuídos a cada faixa, quando o cálculo os discrimina.

A linha `FAIXA:` literal existe pelo mesmo motivo que `VEREDITO: SIM` na `sprintx` e `VEREDITO: APROVADO` na `runx`: torna o portão binário e a leitura por outra skill inequívoca.

### 2.3 Registrar o plano de reversão com os efeitos irreversíveis separados

O plano de reversão precisa distinguir o que o versionador desfaz do que ele não desfaz. A `mergex` usa a segunda lista em dois lugares: classifica como OLHO OBRIGATÓRIO todo arquivo com efeito irreversível declarado, e traz a lista para a seção "como reverter" do pull request.

Garanta no plano uma seção com esta forma:

> ## Efeitos que o versionador NÃO desfaz
>
> | Efeito | Arquivo/origem | Como desfazer, se der |
> |---|---|---|
> | migração aplicada em produção | `migrations/0042_*.sql` | migração reversa manual |
> | mensagem publicada na fila | `src/eventos/publicador.py` | não há desfazer; consumidor precisa ser idempotente |
>
> Sem efeito irreversível, escreva a seção com a tabela vazia e uma linha dizendo isso. **Seção ausente é diferente de seção vazia**: a `mergex` trata ausência como "não avaliado".

### 2.4 Registrar o que a caracterização congelou

Onde a `legadox` registra os testes de caracterização, garanta que conste, por teste: **qual comportamento foi congelado** e **se ele é o comportamento correto ou um comportamento errado preservado de propósito**.

Essa distinção vai literalmente para a seção "o que foi congelado" do pull request. É a informação que mais surpreende o revisor: um teste que congela um bug conhecido é uma decisão, não um descuido — e o PR precisa dizer isso.

### 2.5 `SKILL.md` — uma seção nova ao fim

> ## Entrega no repositório
>
> Quando a [`mergex`](https://github.com/AxisGov/mergex) estiver instalada, os artefatos da `legadox` alimentam a entrega automaticamente, sem acionamento nenhum:
>
> - as **zonas de risco** do `PERFIL.md` fazem um arquivo ser classificado como OLHO OBRIGATÓRIO no diff, **mesmo com uma linha alterada**;
> - a **faixa de raio** entra no portão de prontidão, na descrição do pull request e na ordenação da revisão manual;
> - a **caracterização** e o **plano de reversão** viram seções próprias do pull request;
> - o **`DIVIDA.md`** vira a seção "fora de escopo".
>
> A `legadox` não chama a `mergex` e a `mergex` não chama a `legadox`: o que existe é leitura de artefato. Sem a `mergex` instalada, nada muda aqui.

### 2.6 O que NÃO alterar

- **Nenhuma regra da `legadox`.** Nenhum limiar de raio, nenhuma exigência de caracterização, nenhum critério de orçamento.
- **O gatilho.** Continua sendo a presença de `docs/legado/PERFIL.md`.
- **A prosa existente.** As tabelas e linhas literais deste patch **acrescentam** estrutura legível por máquina; não substituem a prosa para humano.
- **Nada sobre versionamento.** A `legadox` não cria branch, não commita e não abre PR. Isso é da `mergex`.

---

## PARTE 3 — VERIFICAÇÃO

1. Grep por `mergex`: as menções aparecem **apenas** no `SKILL.md`, na seção nova, e são descritivas — nenhuma é um acionamento.
2. Grep por `mergex-revisar`, `revisar`, `merge` e `integrar`: **nenhuma** menção ao comando de revisão.
3. O `PERFIL.md` gerado tem a tabela de zonas com a coluna de **caminhos relativos**, e a prosa existente foi preservada.
4. O registro de raio tem a linha literal `FAIXA: <BAIXO|MEDIO|ALTO>`, os sinais e as zonas tocadas.
5. O plano de reversão tem a seção "Efeitos que o versionador NÃO desfaz", presente mesmo quando vazia.
6. O registro de caracterização diz, por teste, o que foi congelado e se é comportamento correto ou errado preservado de propósito.
7. Simule um projeto **sem** `PERFIL.md`: a `legadox` continua inerte e nada do que este patch acrescentou é exigido.
8. Simule a `legadox` **sem** a `mergex` instalada: todos os artefatos continuam sendo produzidos como sempre, e nenhum passo falha.
9. Confirme que nenhum limiar, critério ou regra da `legadox` foi alterado.
10. Grep por caminho absoluto nos trechos acrescentados.

---

## ENTREGA

Ao terminar, mostre:

- o diff de cada arquivo alterado;
- um exemplo do `PERFIL.md` com a tabela de zonas preenchida;
- o resultado das verificações 1 a 10;
- confirmação explícita de que nenhum acionamento da `mergex` foi inserido e de que `/mergex-revisar` não é mencionado.
