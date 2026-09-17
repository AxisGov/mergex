# Harness de teste — `test/smoke.test.js` + `package.json`

> Base montada pelo agente `investigador` (F1).

## Contrato de entrada

- Comando: `npm test` → `node --test` (`package.json:7`; `docs/stack/CONVENCOES.md:31`).
- Framework `node:test` (`test/smoke.test.js:3`) com `node:assert/strict` (`test/smoke.test.js:4`).
- Testes em `test/`, arquivos `*.test.js` (`docs/stack/CONVENCOES.md:25`); o smoke segue o padrão.
- Declaração `test('<descrição pt-BR>', () => {...})` (`test/smoke.test.js:6`).
- Módulo carregado dentro do teste por caminho relativo `require('../src/index.js')` (`test/smoke.test.js:7`).
- Arquivo começa com `'use strict';` (`test/smoke.test.js:1`).

## Contrato de saída

- O smoke verifica apenas `assert.equal(typeof lib, 'object')` (`test/smoke.test.js:8`).
- `docs/stack/CONVENCOES.md:31` declara o smoke "rodado verde".
- Código de saída do `node --test` em falha: NÃO DOCUMENTADO nas fontes lidas.

## Limites e cotas

- Versão mínima do Node: NÃO DOCUMENTADO — sem `engines` (`package.json:1-9`); `CONVENCOES.md:18` diz só "Runtime: Node.js".
- Timeout e cobertura: NÃO DOCUMENTADO.
- O script não passa glob (`package.json:7`): vale a descoberta padrão do `node --test`, não descrita nas fontes.

## Erros conhecidos e tratamento

- Nenhum erro documentado.
- Dependência externa de teste proibida (`docs/stack/CONVENCOES.md:20`); `package.json` sem `dependencies`/`devDependencies` (`package.json:1-9`).

## Riscos para a nossa implementação

- Sem versão mínima declarada, Node antigo pode falhar sem aviso.
- Uso de `assert.throws` não aparece nos arquivos: NÃO DOCUMENTADO como padrão existente.
- Nome do arquivo de teste da feature: NÃO DOCUMENTADO; só o padrão `test/*.test.js` é obrigatório.

## Fonte

`test/smoke.test.js:1`, `:3`, `:4`, `:6`, `:7`, `:8`; `package.json:1-9`, `:5`, `:7`; `docs/stack/CONVENCOES.md:18`, `:20`, `:25`, `:31` — acessado em 2026-09-16
