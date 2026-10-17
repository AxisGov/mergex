# Exemplo — revisão e merge de pull requests

Saída do comando `/mergex-revisar`, chamado explicitamente pelo desenvolvedor. Quatro PRs abertos: um trivial, um de raio ALTO, um com conflito e um com integração contínua vermelha.

---

# Pull requests abertos — 4

## Sobreposição entre PRs abertos

```
#482 "Corrigir base de cálculo do ICMS-ST com desconto" (fix/OC-2026-0184-icms-st-base-desconto)
#479 "Extrair rateio por item para método próprio"      (feature/extrair-rateio-item)
Em comum:
  src/fiscal/base_calculo.py
```

Isto não é bloqueio e não há conflito ainda: os dois PRs estão abertos e nenhum foi integrado. É informação para decidir a ordem — o segundo a entrar vai precisar rebasear ou resolver conflito.

A mergex não previne colisão entre desenvolvedores. A branch isola o trabalho; ela não impede que duas pessoas alterem o mesmo código.

## Critério de ordenação

Do **MENOR para o MAIOR impacto**, porque cada merge fácil que entra reduz a superfície do próximo, e porque adiar o difícil não o piora — adiar o fácil sim.

Desempate, nesta ordem: faixa de raio → arquivos em olho obrigatório → sobreposição com outro PR → conflito com a base → quantidade de arquivos → número do PR.

## Fila

### 1. #485 — Corrigir rótulo da coluna de vencimento no relatório de cobrança

- Autor: `@ana.souza`
- Trabalho: OC-2026-0191-rotulo-coluna-vencimento (runx, `melhoria-ui`)
- Impacto: **raio BAIXO** — 0 arquivos em olho obrigatório
- Arquivos: 2 (`src/relatorios/` 1, `tests/relatorios/` 1)
- Integração contínua: **verde**
- Conflito: não
- Recomendação: entra primeiro. Troca de texto de rótulo, coberta por teste; nada em olho obrigatório.

---

### 2. #479 — Extrair rateio por item para método próprio

- Autor: `@carlos.lima`
- Trabalho: exportacao-rateio-item (sprintx, feature)
- Impacto: **raio MÉDIO** — 1 arquivo em olho obrigatório
- Arquivos: 6 (`src/fiscal/` 2, `tests/fiscal/` 3, `tests/caracterizacao/` 1)
- Integração contínua: **verde**
- Conflito: não
- Sobreposição: toca `src/fiscal/base_calculo.py`, também tocado por #482
- Recomendação: refatoração coberta por caracterização; o arquivo em olho obrigatório está em zona fiscal. Integrar antes do #482 deixa o conflito do lado do #482, que é o mais novo e tem quem o acompanhe.

---

### 3. #482 — Corrigir base de cálculo do ICMS-ST com desconto incondicional

- Autor: `@thulio` (via mergex)
- Trabalho: OC-2026-0184-icms-st-base-desconto (runx, `regra-de-calculo`)
- Impacto: **raio ALTO** — 4 arquivos em olho obrigatório
- Arquivos: 9 (`src/fiscal/` 3, `src/relatorios/` 1, `migrations/` 1, `tests/` 4)
- Integração contínua: **verde**
- Conflito: **sim, com `main`** — ver análise abaixo
- Sobreposição: toca `src/fiscal/base_calculo.py`, também tocado por #479
- **[aberto por esta instalação da mergex — a skill não aprova o próprio trabalho]**
- Recomendação: o de maior impacto da fila. Tem migração de banco e mudança de valor em documento fiscal. Revisar os 4 arquivos de olho obrigatório antes de integrar, e resolver o conflito com a base — que continua sendo trabalho humano.

---

## Conflitos

```
CONFLITO — #482 contra main

  src/fiscal/base_calculo.py, função calcular_base_st(), linhas 40–58

  O que #482 pretendia:
    "Excluir o desconto incondicional da base de ST, conforme a regra vigente."
    (T-01.02, fix/OC-2026-0184-icms-st-base-desconto)

  O que entrou na base depois:
    "Extrair a montagem do rateio para um helper, sem mudar o resultado."
    (#476, mesclado em 2026-08-28 por @carlos.lima)

  Por que se cruzaram:
    Os dois reescreveram o corpo de calcular_base_st(). O #482 mudou a fórmula —
    passou a subtrair o desconto antes de aplicar o MVA. O #476 mudou a estrutura —
    moveu a montagem do rateio para outra função, sem alterar o resultado.

    As duas intenções são compatíveis: a fórmula corrigida precisa existir dentro
    da estrutura nova. A junção não é automática porque os dois tocaram as mesmas
    linhas, não porque as mudanças se contradizem.

  O que perguntar a quem decidir:
    No helper novo do rateio, a subtração do desconto entra antes da aplicação
    do MVA em cada item, ou uma vez só, sobre a base já rateada?

  A mergex não resolve conflito. Resolver isto é decisão humana: as duas intenções
  precisam coexistir no código final, e quem conhece a regra fiscal é quem deve
  decidir onde a subtração do desconto entra na estrutura nova.
```

## Não oferecidos para merge

| PR | Motivo |
|---|---|
| #487 — "Adicionar cache no exportador de NF-e" (`@bruno.reis`) | **integração contínua vermelha** — 3 testes falhando em `tests/fiscal/`. Não é oferecido para merge |

Detalhe do #487, para contexto: raio MÉDIO, 4 arquivos, 1 em olho obrigatório, sem conflito com a base. Assim que a suíte ficar verde, ele entraria entre o #485 e o #479 pelo critério de ordenação.

---

## Condução

Um PR por vez, na ordem acima, com confirmação explícita daquele PR específico.

```
1/3 — #485 "Corrigir rótulo da coluna de vencimento no relatório de cobrança"
      raio BAIXO, 0 em olho obrigatório, integração verde, sem conflito.

      Confirma o merge do #485?
```

```
2/3 — #479 "Extrair rateio por item para método próprio"
      raio MÉDIO, integração verde, sem conflito.

      Este PR tem 1 arquivo em OLHO OBRIGATÓRIO:
        src/fiscal/base_calculo.py — zona de risco fiscal, raio MÉDIO

      Você revisou esse arquivo? (o merge não segue sem esta confirmação)
```

```
3/3 — #482 "Corrigir base de cálculo do ICMS-ST com desconto incondicional"
      raio ALTO, integração verde, COM CONFLITO contra main.

      O conflito precisa ser resolvido por você antes de qualquer merge — a
      mergex não resolve conflito. A análise dos dois lados está acima.

      Este PR tem 4 arquivos em OLHO OBRIGATÓRIO:
        src/fiscal/calculo_icms_st.py — zona de risco fiscal, altera base de cálculo
        src/fiscal/base_calculo.py — zona de risco fiscal, raio ALTO
        migrations/0042_ajusta_precisao_base_st.sql — migração de banco
        src/relatorios/exportador_nfe.py — contrato público (XML da NF-e)

      Você revisou esses quatro arquivos? (o merge não segue sem esta confirmação)
```

## Resumo final

- **Integrados:** #485, #479
- **Pendentes:**
  - **#482** — conflito com `main` a resolver, e é raio ALTO com 4 arquivos em olho obrigatório. A resolução é humana.
  - **#487** — integração contínua vermelha, 3 testes falhando. Não foi oferecido para merge.
