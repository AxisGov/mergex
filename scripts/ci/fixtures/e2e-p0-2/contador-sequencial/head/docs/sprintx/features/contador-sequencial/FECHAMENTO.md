---
expx_schema: 1
expx_tool: sprintx
kind: fechamento
trabalho_id: contador-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-01
titulo: Contador sequencial proximoNumero
tipo_trabalho: feature
fechado_em: 2026-09-16
modulo_afetado: [raiz, test]
arquivos_alterados: [src/index.js, src/proximo-numero.js, test/proximo-numero.test.js]
palavras_chave: [contador, sequencial, proximonumero, incremento, validacao, typeerror]
resumo: A biblioteca expoe proximoNumero(valor), que devolve valor + 1 para inteiro number maior ou igual a zero e lanca TypeError para qualquer outra entrada
decisao_principal: proximoNumero vive em src/proximo-numero.js, teste em test/proximo-numero.test.js, reexportado como propriedade nomeada de src/index.js
risco_residual: Inteiro acima de Number.MAX_SAFE_INTEGER e aceito e perde precisao em valor + 1 (D-09, PR-06); mensagem do TypeError nao e contrato (D-10)
testes_adicionados: 8
---

# Fechamento — contador-sequencial

> Registro do que este trabalho entregou, em que módulo e em que arquivos. É o que torna a
> feature encontrável depois: por arquivo, por módulo e por palavra-chave.
> Os três campos de indexação são cópia fiel do `ORQUESTRADOR.md` no momento do fechamento.

## O que foi entregue

A biblioteca expõe `proximoNumero(valor)`, que devolve `valor + 1` para inteiro `number` `>= 0` e lança `TypeError` para qualquer outra entrada.

## Decisão principal

D-04 — `proximoNumero` vive em `src/proximo-numero.js`, teste em `test/proximo-numero.test.js`, reexportado como propriedade nomeada de `src/index.js`. É o que permite à FT-02 importar `proximoNumero` por `require` sem ciclo e sem duplicar a regra de incremento.

## Risco residual

Inteiro acima de `Number.MAX_SAFE_INTEGER` é aceito e perde precisão em `valor + 1` (D-09, PR-06); a mensagem do `TypeError` não é contrato (D-10).

## Onde isto mexeu

- **Módulos:** raiz, test
- **Arquivos:** `src/index.js`, `src/proximo-numero.js`, `test/proximo-numero.test.js`
- **Testes adicionados:** 8
