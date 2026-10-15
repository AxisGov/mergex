# proximoNumero — contrato real da FT-01

> Base montada pelo agente `investigador` (F1), lendo `src/proximo-numero.js`, `src/index.js`, `test/proximo-numero.test.js`, `test/smoke.test.js`, `package.json`, `docs/stack/CONVENCOES.md` e `docs/sprintx/features/contador-sequencial/FECHAMENTO.md`.

## Contrato de entrada

- Um parâmetro, `valor` (`src/proximo-numero.js:3`).
- Aceita só `typeof valor === 'number'` (`src/proximo-numero.js:4`), inteiro e `>= 0` (`src/proximo-numero.js:7`).
- Import pelo módulo: `const { proximoNumero } = require('../src/proximo-numero.js')` (`test/proximo-numero.test.js:14`); de dentro de `src/`: `require('./proximo-numero.js')` (`src/index.js:3`). Mesma referência pelo index (`test/proximo-numero.test.js:10`).
- Export: objeto com propriedade nomeada, `module.exports = { proximoNumero }` (`src/proximo-numero.js:13`).
- D-04 da FT-01 existe para a FT-02 importar `proximoNumero` por `require` sem ciclo e sem duplicar a regra de incremento (`docs/sprintx/features/contador-sequencial/FECHAMENTO.md:32`).

## Contrato de saída

- Devolve `valor + 1`, síncrono, `number` (`src/proximo-numero.js:10`).
- Casos testados: `0` → `1` (`test/proximo-numero.test.js:21`); `41` → `42` (`:26`); `-0` → `1` (`:27`); `MAX_SAFE_INTEGER` → `MAX_SAFE_INTEGER + 1` (`:28`); `2 ** 53` → `2 ** 53 + 1` (`:30`, os dois lados arredondados pelo mesmo `+ 1`: não prova resultado exato).

## Limites e cotas

- Mínimo 0 (`src/proximo-numero.js:7`); máximo: nenhum no código (`test/proximo-numero.test.js:29`, validação por `isSafeInteger` descartada de propósito).
- Acima de `Number.MAX_SAFE_INTEGER` é aceito e `valor + 1` perde precisão — risco residual D-09/PR-06 (`docs/sprintx/features/contador-sequencial/FECHAMENTO.md:16`, `:36`).

## Erros conhecidos e tratamento

- Tipo diferente de `number`: `TypeError('proximoNumero espera um valor do tipo number')` (`src/proximo-numero.js:4-5`); testado com `'1'`, `1n`, `new Number(1)`, `undefined`, `null`, `true` (`test/proximo-numero.test.js:35`, `:41-42`).
- Não inteiro ou negativo: `TypeError('proximoNumero espera um inteiro maior ou igual a zero')` (`src/proximo-numero.js:7-8`); testado com `-1`, `1.5`, `NaN`, `Infinity`, `-Infinity` (`test/proximo-numero.test.js:48`, `:53-54`).
- Mensagem não é contrato (D-10, `FECHAMENTO.md:36`); testes checam só a classe (`test/proximo-numero.test.js:35`, `:42`, `:48`, `:54`).
- Lançado de forma síncrona, sem captura interna (`src/proximo-numero.js:3-11`).

## Riscos para a nossa implementação

- Testar a mensagem exata do `TypeError` prende a FT-02 a algo que D-10 diz não ser contrato.
- Acima de `MAX_SAFE_INTEGER` o número que chega à formatação já pode ter perdido precisão; teste de "não truncar" com valores `> 2**53` compara números imprecisos.
- Validar a entrada em `proximoCodigo` antes de chamar `proximoNumero` duplica a regra da FT-01 (`FECHAMENTO.md:32`).
- Importar `proximoNumero` a partir de `src/index.js` pode criar ciclo quando o index reexportar `proximoCodigo`; D-04 aponta `src/proximo-numero.js`.

## Fonte

`src/proximo-numero.js:3-13`; `test/proximo-numero.test.js:6-56`; `docs/sprintx/features/contador-sequencial/FECHAMENTO.md:14-16`, `:28`, `:32`, `:36` — acessado em 2026-09-16
