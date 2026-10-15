# Módulo principal e harness de teste

> Base montada pelo agente `investigador` (F1).

## Contrato de entrada

- `src/index.js` importa `{ proximoNumero }` de `./proximo-numero.js` (`src/index.js:3`).
- O smoke faz `require('../src/index.js')` (`test/smoke.test.js:7`).
- Testes usam `require('node:test')` e `require('node:assert/strict')` (`test/proximo-numero.test.js:3-4`, `test/smoke.test.js:3-4`).
- `require` de produto nos testes é relativo (`'../src/...'`) e fica dentro de cada `test` (`test/proximo-numero.test.js:7-8`, `:14`, `:20`).

## Contrato de saída

- `src/index.js` exporta objeto literal com propriedades nomeadas: `module.exports = { proximoNumero }` (`src/index.js:5`).
- O smoke exige só `typeof lib === 'object'` (`test/smoke.test.js:8`); o mesmo em `test/proximo-numero.test.js:16`.
- Todo arquivo começa com `'use strict'` (`src/index.js:1`, `src/proximo-numero.js:1`, `test/*.test.js:1`).
- Nomes de teste em pares por task: `'T-XX.YY integracao: ...'` (via `src/index.js`) e `'T-XX.YY funcional: ...'` (módulo direto), sem acento (`test/proximo-numero.test.js:6`, `:13`, `:19`, `:24`, `:33`, `:38`, `:46`, `:51`).
- Um arquivo de teste por módulo (`test/proximo-numero.test.js` ↔ `src/proximo-numero.js`).

## Limites e cotas

- `npm test` → `node --test` (`package.json:7`).
- Suíte atual: 9 testes, 8 em `test/proximo-numero.test.js` e 1 em `test/smoke.test.js` (`docs/stack/CONVENCOES.md:32`; `FECHAMENTO.md:17`, `:42`).
- Versão mínima do Node: NÃO DOCUMENTADO.
- Sem lint nem build (`docs/stack/CONVENCOES.md:34`).

## Erros conhecidos e tratamento

- Verificação de erro por `assert.throws(() => fn(entrada), TypeError)` (`test/proximo-numero.test.js:35`, `:42`, `:48`, `:54`).
- Erros do harness: NÃO DOCUMENTADO.

## Riscos para a nossa implementação

- `src/index.js` deixando de exportar objeto quebra `test/smoke.test.js:8` e `test/proximo-numero.test.js:16`.
- Acrescentar `proximoCodigo` ao index sem manter `proximoNumero` quebra `test/proximo-numero.test.js:10`, `:20`, `:34`, `:47`.
- Regra de descoberta do `node --test` não está nos arquivos lidos; a convenção `test/*.test.js` vem de `docs/stack/CONVENCOES.md:26`.

## Fonte

`src/index.js:1-5`; `test/smoke.test.js:1-9`; `test/proximo-numero.test.js:1-56`; `package.json:5`, `:7`; `docs/stack/CONVENCOES.md:26`, `:32`, `:34` — acessado em 2026-09-16
