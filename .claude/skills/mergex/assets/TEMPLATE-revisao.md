# TEMPLATE — revisão e merge de pull requests (E9, MANUAL)

Saída do comando `/mergex-revisar`, que só roda por chamada explícita do
desenvolvedor. Substitua todos os marcadores `{{assim}}`.
Apague este cabeçalho ao usar.

---

# Pull requests abertos — {{n}}

## Sobreposição entre PRs abertos

{{quando dois ou mais PRs tocam o mesmo arquivo — vai no TOPO, sempre}}

```
#{{n}} "{{título}}" ({{branch}})
#{{n}} "{{título}}" ({{branch}})
Em comum:
  {{caminho do arquivo}}
```

Isto não é bloqueio e não há conflito ainda. É informação para decidir a ordem:
o segundo a entrar vai precisar rebasear ou resolver conflito. A mergex não
previne colisão entre desenvolvedores.

## Critério de ordenação

Do MENOR para o MAIOR impacto, porque cada merge fácil que entra reduz a
superfície do próximo, e porque adiar o difícil não o piora — adiar o fácil sim.

Desempate, nesta ordem: faixa de raio → arquivos em olho obrigatório →
sobreposição com outro PR → conflito com a base → quantidade de arquivos →
número do PR.

## Fila

### {{ordem}}. #{{n}} — {{título}}

- Autor: {{autor}}
- Trabalho: {{trabalho_id}} ({{skill de origem}}, {{tipo}})
- Impacto: {{raio}} — {{n}} arquivos em olho obrigatório
- Arquivos: {{n}} ({{agrupamento por pasta}})
- Integração contínua: {{verde | vermelha | sem integração configurada}}
- Conflito: {{não | sim, com a base | sim, com #n}}
- Review Evidence: {{SATISFEITO | BLOQUEADO}}
- Reviews: {{n}} actionable, {{n}} aguardando evidência, {{n}} aguardando re-review, {{n}} rejeitados com evidência, {{n}} resolvidos
- {{[aberto por esta instalação da mergex — a skill não aprova o próprio trabalho]}}
- Recomendação: {{uma linha, derivada do estado, nunca de opinião}}

{{PR com Review Evidence BLOQUEADO não recebe recomendação de merge — mostra o bloco de
bloqueio abaixo e entra em "Não oferecidos para merge"}}

## Conflitos

{{um bloco por PR em conflito — relatar, NUNCA resolver}}

```
CONFLITO — #{{n}} contra {{base | #n}}

  {{arquivo}}, {{função ou trecho}}, linhas {{n}}–{{n}}

  O que #{{n}} pretendia:
    "{{objetivo, da mensagem de commit da task}}"
    ({{task}}, {{branch}})

  O que o outro lado pretendia:
    "{{objetivo do outro lado}}"
    ({{origem}})

  Por que se cruzaram:
    {{mesma função, mesma linha, ou mudanças adjacentes}}

  A mergex não resolve conflito. Resolver isto é decisão humana.
```

## Review Evidence — bloqueados

{{um bloco por PR com Review Evidence BLOQUEADO}}

```
REVIEW EVIDENCE — BLOQUEADO

R1 CI: {{OK | FALHOU}}
R2 blocking reviews: {{OK | FALHOU | NÃO VERIFICÁVEL}}
R3 actionable threads: {{OK | FALHOU — {{n}} findings | NÃO VERIFICÁVEL}}
R4 fix evidence: {{OK | FALHOU | n/a}}
R5 review reply: {{OK | FALHOU | n/a | NÃO VERIFICÁVEL}}
R6 closure: {{OK | FALHOU | n/a | NÃO VERIFICÁVEL}}

Findings pendentes:
  {{arquivo}}:{{linha}} — {{descrição}}
```

## Não oferecidos para merge

| PR | Motivo |
|---|---|
| #{{n}} | {{rascunho | integração contínua vermelha | REVIEW EVIDENCE: BLOQUEADO}} |

---

## Condução

Um PR por vez, na ordem acima, com confirmação explícita daquele PR
específico. Nunca em lote. PR com faixa OLHO OBRIGATÓRIO ou raio ALTO exige,
antes, a confirmação de que o desenvolvedor revisou os arquivos daquela faixa,
nomeados um a um. PR com Review Evidence BLOQUEADO nunca é oferecido — mudança
de código não encerra review, evidência encerra review.

## Resumo final

- Integrados: {{lista}}
- Pendentes: {{lista, com o motivo de cada um}}
