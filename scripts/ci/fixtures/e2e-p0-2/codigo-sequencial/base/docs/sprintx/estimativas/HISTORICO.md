---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: 2026-09-16
unidade: h
entradas:
  - trabalho_id: contador-sequencial
    task_id: T-01.01
    tipo_task: config
    area: modulo proximo-numero e reexport em src/index.js
    sinais: [arquivo_novo_isolado]
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.1
    duracao_observada: 0.02
    desvio: null
    registrado_em: 2026-09-16
  - trabalho_id: contador-sequencial
    task_id: T-02.01
    tipo_task: dominio
    area: incremento de proximoNumero
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.1
    duracao_observada: 0.02
    desvio: null
    registrado_em: 2026-09-16
  - trabalho_id: contador-sequencial
    task_id: T-02.02
    tipo_task: dominio
    area: validacao de tipo de proximoNumero
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.1
    duracao_observada: 0.01
    desvio: null
    registrado_em: 2026-09-16
  - trabalho_id: contador-sequencial
    task_id: T-02.03
    tipo_task: dominio
    area: validacao de dominio de proximoNumero
    sinais: []
    estimado_min: null
    estimado_max: null
    estimado_media: null
    real: 0.1
    duracao_observada: 0.01
    desvio: null
    registrado_em: 2026-09-16
calibracao: []
---

# Histórico de esforço — calibração das estimativas

Uma linha por task concluída, com o esforço real medido. É a única base de calibração real do projeto: sem ele, toda estimativa fica com confiança no máximo MÉDIA.

Unidade: hora de trabalho focado. O real é o esforço efetivamente gasto na task — escrever os dois testes, implementar, rodar a suíte e verificar o critério de aceite. Não inclui reunião, revisão, deploy nem ida e volta com o cliente.

`duracao_observada` vem do rastro (`task_iniciada` → `task_concluida`) e é tempo de parede, não esforço: nunca substitui o `real`.

## Entradas

| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Duração observada | Desvio |
|---|---|---|---|---|---|---|---|---|---|
| contador-sequencial | T-01.01 | config | módulo proximo-numero e reexport em src/index.js | arquivo_novo_isolado | null | null | 0,1 h | 0,02 h | null |
| contador-sequencial | T-02.01 | dominio | incremento de proximoNumero | — | null | null | 0,1 h | 0,02 h | null |
| contador-sequencial | T-02.02 | dominio | validação de tipo de proximoNumero | — | null | null | 0,1 h | 0,01 h | null |
| contador-sequencial | T-02.03 | dominio | validação de domínio de proximoNumero | — | null | null | 0,1 h | 0,01 h | null |

O trabalho `contador-sequencial` rodou sem a F3.5: estimado e desvio em `null`, real preenchido.

## Calibração por tipo de task

Nenhuma entrada com desvio calculável ainda (nenhum trabalho com estimativa): tabela vazia.

**Regra do fator.** O desvio de um tipo só vira fator de correção nas estimativas seguintes a partir de **3 entradas encerradas** daquele tipo. Quando aplicado, o fator é **sempre declarado na saída da estimativa**, nunca embutido em silêncio.

## Como se calcula o desvio

```
desvio_task = real / media_task_estimada          # media_task = (o + 4m + p) / 6
desvio_medio_do_tipo = media dos desvio_task daquele tipo
```
