# Convenções do projeto — `docs/stack/CONVENCOES.md`

> Base montada pelo agente `investigador` (F1).

## Contrato de entrada

- Runtime Node.js (`docs/stack/CONVENCOES.md:19`, `decidido_pelo_buildx`).
- CommonJS, `require`/`module.exports`, `"type": "commonjs"` (`docs/stack/CONVENCOES.md:20`; `package.json:5`).
- Sem dependência externa de runtime ou teste (`docs/stack/CONVENCOES.md:21`; `package.json:1-9`).
- Produto em `src/`; testes em `test/*.test.js` com `node:test` e `node:assert/strict` (`docs/stack/CONVENCOES.md:25-26`).
- Conventional Commits (`docs/stack/CONVENCOES.md:15`).

## Contrato de saída

- Biblioteca de uma camada: funções puras exportadas por `src/` (`docs/stack/CONVENCOES.md:38-40`).

## Limites e cotas

- Sem configuração nem variável de ambiente (`docs/stack/CONVENCOES.md:53`).
- Sem banco, interface, serviço externo ou segredo (`docs/stack/CONVENCOES.md:57-60`).
- Regra sobre números, largura ou formatação: NÃO DOCUMENTADO.

## Erros conhecidos e tratamento

- Entrada inválida lança `TypeError` síncrono, confirmado em `src/proximo-numero.js:4-9` (`docs/stack/CONVENCOES.md:44-45`).
- Erro de função reutilizada é propagado sem captura e sem reembrulho — origem ainda `decidido_pelo_buildx`, nenhum código reutiliza função (`docs/stack/CONVENCOES.md:47-49`). A FT-02 é a primeira a exercitá-la.

## Riscos para a nossa implementação

- `try/catch` ou `new TypeError(...)` próprio em volta da chamada a `proximoNumero` viola a regra de propagação (`docs/stack/CONVENCOES.md:47-49`).
- Regras não exercitadas ficam `decidido_pelo_buildx` até a revisão contra o código (`docs/stack/CONVENCOES.md:3-6`); quem atualiza a origem da regra de propagação depois da FT-02 e quando: NÃO DOCUMENTADO.

## Fonte

`docs/stack/CONVENCOES.md:3-6`, `:15`, `:19-21`, `:25-26`, `:32-34`, `:38-40`, `:44-49`, `:53`, `:57-60`; `package.json:5`, `:7` — acessado em 2026-09-16
