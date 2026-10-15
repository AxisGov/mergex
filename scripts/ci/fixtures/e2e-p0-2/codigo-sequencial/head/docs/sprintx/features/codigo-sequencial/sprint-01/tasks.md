---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
sprint_id: sprint-01
atualizado_em: 2026-09-16
sprint:
  titulo: Capacidade de testar o modulo proximo-codigo
  status: concluido
  criterio_saida: npm test termina com 0 falhas, incluindo o smoke, os 8 testes da FT-01 e os dois testes da T-01.01 (carregamento e reexport)
  riscos: [Reexport no index pode quebrar os testes da FT-01 que usam proximoNumero pelo index (base/modulo-principal-e-harness.md)]
  fora_de_escopo: [Formato SEQ-, zeros a esquerda, reuso de proximoNumero e propagacao de erro]
fases:
  - id: F-01.1
    titulo: Modulo proximo-codigo carregavel e reexportado
    status: concluido
    criterio_saida: test/proximo-codigo.test.js carrega src/proximo-codigo.js e src/index.js e os dois testes da T-01.01 passam junto dos testes da FT-01
    paralelizavel: false
    paralela_com: []
    tasks: [T-01.01]
tasks:
  - id: T-01.01
    titulo: Modulo proximo-codigo carregavel e reexportado pelo index
    fase: F-01.1
    status: concluida
    objetivo: Criar src/proximo-codigo.js com corpo provisorio que lanca Error nao implementado, sem chamar proximoNumero, e expor proximoCodigo como propriedade nomeada de src/index.js mantendo proximoNumero
    arquivos:
      cria: [src/proximo-codigo.js, test/proximo-codigo.test.js]
      altera: [src/index.js]
    teste_integracao: require de src/index.js expoe proximoCodigo com a mesma referencia de src/proximo-codigo.js e proximoNumero com a mesma referencia de src/proximo-numero.js
    teste_funcional: Dado o require de src/proximo-codigo.js, typeof proximoCodigo e function e typeof do objeto de src/index.js continua object
    criterio_aceite: npm test sai com codigo 0 com os dois testes da T-01.01 e os 9 testes anteriores passando
    depende_de: []
    paralelizavel: false
    concluida_em: 2026-09-16
    suite: verde
---

# Plano — Sprint 01 — Capacidade de testar o módulo proximo-codigo

> Rodada 2 do plano (F3 depois da auditoria NÃO da rodada 1): critério de saída reescrito sem a palavra "carga" (achado BAIXA).

## Objetivo da sprint

Deixar `src/proximo-codigo.js` existente, carregável pelo harness e reexportado por `src/index.js` junto de `proximoNumero` (D-04), com corpo provisório sem regra — para que os testes da sprint-02 comecem vermelhos.

## Critério de saída da sprint

`npm test` termina com 0 falhas (suíte inteira), incluindo o smoke, os 8 testes da FT-01 e os dois testes da T-01.01 (carregamento e reexport).

## Riscos conhecidos

- O reexport no `src/index.js` pode quebrar testes da FT-01 que usam `proximoNumero` pelo index (`base/modulo-principal-e-harness.md`).

## Fora de escopo

- Formato `SEQ-`, zeros à esquerda, reuso de `proximoNumero` e propagação de erro — sprint-02.

## Fase F-01.1 — Módulo proximo-codigo carregável e reexportado

**Objetivo:** módulo novo e ponto público de exportação prontos para teste.

**Tasks:** T-01.01

**Critério de saída:** `test/proximo-codigo.test.js` carrega `src/proximo-codigo.js` e `src/index.js` e os dois testes da T-01.01 passam junto dos testes da FT-01.

**Roda em paralelo com:** nenhuma.

Nomes dos testes da FT-02 prefixados com `FT-02` (D-15).

**Status da fase:** concluído em 2026-09-16.

## Portão da sprint — suíte inteira

Sprint concluída em 2026-09-16. Saída de `npm test`:

```
ℹ tests 11
ℹ pass 11
ℹ fail 0
```

## Tasks

---

```yaml
id: T-01.01
titulo: Modulo proximo-codigo carregavel e reexportado pelo index
objetivo: Criar src/proximo-codigo.js com corpo provisorio que lanca Error nao implementado, sem chamar proximoNumero, e expor proximoCodigo como propriedade nomeada de src/index.js mantendo proximoNumero
arquivos:
  cria: [src/proximo-codigo.js, test/proximo-codigo.test.js]
  altera: [src/index.js]
teste_integracao: require de src/index.js expoe proximoCodigo com a mesma referencia de src/proximo-codigo.js e proximoNumero com a mesma referencia de src/proximo-numero.js
teste_funcional: Dado o require de src/proximo-codigo.js, typeof proximoCodigo e function e typeof do objeto de src/index.js continua object
criterio_aceite: npm test sai com codigo 0 com os dois testes da T-01.01 e os 9 testes anteriores passando
depende_de: []
paralelizavel: false
status: concluida
```

2026-09-16 · suíte: 11 passed, 0 failed (npm test, suíte inteira) · real: 0,1 h
