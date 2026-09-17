---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: contador-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-01
sprint_id: sprint-01
atualizado_em: 2026-09-16
sprint:
  titulo: Capacidade de testar o modulo proximo-numero
  status: concluido
  criterio_saida: npm test termina com 0 falhas, incluindo o smoke e os testes de carga do modulo proximo-numero
  riscos: [Sem versao minima de Node declarada no package.json (base/harness-de-teste.md)]
  fora_de_escopo: [Regra de incremento e validacao de entrada de proximoNumero, proximoCodigo da FT-02]
fases:
  - id: F-01.1
    titulo: Modulo carregavel e reexportado
    status: concluido
    criterio_saida: test/proximo-numero.test.js carrega src/proximo-numero.js e src/index.js e os dois testes da T-01.01 passam
    paralelizavel: false
    paralela_com: []
    tasks: [T-01.01]
tasks:
  - id: T-01.01
    titulo: Modulo proximo-numero carregavel e reexportado pelo index
    fase: F-01.1
    status: concluida
    objetivo: Criar o modulo src/proximo-numero.js e seu arquivo de teste, expondo proximoNumero como propriedade nomeada de src/index.js
    arquivos:
      cria: [src/proximo-numero.js, test/proximo-numero.test.js]
      altera: [src/index.js]
    teste_integracao: require de src/index.js expoe proximoNumero como a mesma referencia exportada por src/proximo-numero.js
    teste_funcional: Dado o require de src/proximo-numero.js, typeof proximoNumero e function e typeof do objeto de src/index.js continua object
    criterio_aceite: npm test sai com codigo 0 e o arquivo test/proximo-numero.test.js tem os dois testes da T-01.01 passando
    depende_de: []
    paralelizavel: false
    concluida_em: 2026-09-16
    suite: verde
---

# Plano — Sprint 01 — Capacidade de testar o módulo proximo-numero

## Objetivo da sprint

Deixar o módulo `src/proximo-numero.js` existente, carregável pelo harness `node:test` e reexportado por `src/index.js` (D-04), sem regra de negócio — para que o TDD da sprint-02 tenha onde escrever o teste vermelho.

## Critério de saída da sprint

`npm test` termina com 0 falhas, incluindo `test/smoke.test.js` e os testes de carga de `test/proximo-numero.test.js`.

## Riscos conhecidos

- Sem versão mínima de Node declarada no `package.json` (`base/harness-de-teste.md`); D-13 registra o runtime local v24.18.0.

## Fora de escopo

- Regra de incremento e validação de entrada de `proximoNumero` — é a sprint-02.
- `proximoCodigo` — FT-02 (D-03).

## Fase F-01.1 — Módulo carregável e reexportado

**Objetivo:** módulo novo e ponto público de exportação prontos para teste.

**Tasks:** T-01.01

**Critério de saída:** `test/proximo-numero.test.js` carrega `src/proximo-numero.js` e `src/index.js` e os dois testes da T-01.01 passam.

**Roda em paralelo com:** nenhuma.

**Status da fase:** concluído em 2026-09-16.

## Portão da sprint — suíte inteira

Sprint concluída em 2026-09-16. Saída de `npm test`:

```
✔ T-01.01 integracao: src/index.js reexporta proximoNumero de src/proximo-numero.js (1.949ms)
✔ T-01.01 funcional: proximoNumero e funcao e o index continua objeto (0.1552ms)
✔ o modulo principal carrega (2.0234ms)
ℹ tests 3
ℹ pass 3
ℹ fail 0
```

### Grafo de tasks

```mermaid
%% Grafo de tasks — sprint-01 — gerado pela sprintx a partir deste arquivo
flowchart LR
  subgraph fase_01_1["F-01.1 Modulo carregavel"]
    T_01_01["T-01.01<br/>Modulo reexportado"]
  end
  classDef pendente fill:#F3F0EA,stroke:#8A7F70,color:#1A1815
  classDef em_andamento fill:#FDF0D5,stroke:#B4541E,color:#1A1815
  classDef concluida fill:#DFF0D8,stroke:#4A6B3A,color:#1A1815
  classDef bloqueada fill:#F8D7DA,stroke:#8C2F24,color:#1A1815
  classDef critico stroke-width:3px
  class T_01_01 concluida
```

## Tasks

---

```yaml
id: T-01.01
titulo: Modulo proximo-numero carregavel e reexportado pelo index
objetivo: Criar o modulo src/proximo-numero.js e seu arquivo de teste, expondo proximoNumero como propriedade nomeada de src/index.js
arquivos:
  cria: [src/proximo-numero.js, test/proximo-numero.test.js]
  altera: [src/index.js]
teste_integracao: require de src/index.js expoe proximoNumero como a mesma referencia exportada por src/proximo-numero.js
teste_funcional: Dado o require de src/proximo-numero.js, typeof proximoNumero e function e typeof do objeto de src/index.js continua object
criterio_aceite: npm test sai com codigo 0 e o arquivo test/proximo-numero.test.js tem os dois testes da T-01.01 passando
depende_de: []
paralelizavel: false
status: concluida
```

2026-09-16 · suíte: 3 passed, 0 failed (npm test, suíte inteira) · real: 0,1 h
