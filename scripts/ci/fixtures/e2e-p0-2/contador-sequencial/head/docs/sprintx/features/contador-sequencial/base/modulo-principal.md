# Módulo principal — `src/index.js`

> Base montada pelo agente `investigador` (F1), lendo apenas `src/index.js`, `test/smoke.test.js`, `package.json` e `docs/stack/CONVENCOES.md`.

## Contrato de entrada

- Carregado por `require`; o smoke usa `require('../src/index.js')` (`test/smoke.test.js:7`).
- Arquivo começa com `'use strict';` (`src/index.js:1`).
- Hoje não expõe função nenhuma e não recebe entrada. `proximoNumero` não existe no código; o que ela aceita não está escrito em fonte de código: NÃO DOCUMENTADO (só no briefing buildx: `docs/projeto/MAPA.md` FT-01 e `docs/projeto/PREMISSAS.md` PR-02..PR-05).

## Contrato de saída

- Exporta um objeto vazio: `module.exports = {};` (`src/index.js:3`).
- CommonJS confirmado por `"type": "commonjs"` (`package.json:5`) e pela convenção `require`/`module.exports` (`docs/stack/CONVENCOES.md:19`).
- Ponto natural de exposição de função nova: propriedade do objeto exportado por `src/index.js` — o export atual é objeto (`src/index.js:3`) e a camada é "funções puras exportadas por `src/`" (`docs/stack/CONVENCOES.md:37`).
- Export nomeado no objeto vs. função direto em `module.exports`: NÃO DOCUMENTADO. Trocar o objeto por função quebra o smoke, que exige `typeof lib === 'object'` (`test/smoke.test.js:8`).
- `package.json` sem `main` e sem `exports` (`package.json:1-9`): ponto de entrada do pacote NÃO DOCUMENTADO.

## Limites e cotas

- Biblioteca local, sem configuração nem variável de ambiente (`docs/stack/CONVENCOES.md:48`).
- Tratamento de valores acima de `Number.MAX_SAFE_INTEGER`: NÃO DOCUMENTADO no código.

## Erros conhecidos e tratamento

- `src/index.js` não lança nem trata erro hoje (`src/index.js:1-3`).
- Convenção: entrada inválida lança `TypeError` síncrono; erro de função reutilizada é propagado sem captura nem reembrulho (`docs/stack/CONVENCOES.md:42-44`).

## Riscos para a nossa implementação

- Exportar a função direto como `module.exports` deixa o smoke vermelho (`test/smoke.test.js:8`).
- Casos de borda de "inteiro >= 0" (`NaN`, `Infinity`, `-0`, fracionário, acima de `MAX_SAFE_INTEGER`, `Number` embrulhado) não estão definidos no código — precisam virar decisão explícita.
- Mensagem do `TypeError`: NÃO DOCUMENTADO.

## Fonte

`src/index.js:1`, `src/index.js:3`, `package.json:5`, `test/smoke.test.js:7-8`, `docs/stack/CONVENCOES.md:19`, `:37`, `:42-44`, `:48` — acessado em 2026-09-16
