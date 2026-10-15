# Convenções do projeto — `docs/stack/CONVENCOES.md`

> Base montada pelo agente `investigador` (F1). Todas as regras são prescritivas, marcadas `decidido_pelo_buildx`; só o comando de teste traz evidência real (`docs/stack/CONVENCOES.md:3-5`).

## Contrato de entrada

- Versionamento: Branch principal `main` (`:11`); Branch base `buildx/p0-e2e-v2` (`:12`); Conventional Commits `feat:`/`fix:`/`test:`/`docs:`/`chore:` (`:14`).
- Stack: Node.js (`:18`); CommonJS com `require`/`module.exports` e `"type": "commonjs"` (`:19`); sem dependência externa de runtime ou teste (`:20`).
- Estrutura: produto em `src/` (`:24`); testes em `test/*.test.js` com `node:test` e `node:assert/strict` (`:25`).
- Comandos: só `npm test` (`node --test`), evidência `package.json` e smoke verde (`:31`); sem lint nem build (`:33`).
- Camadas: biblioteca de uma camada, funções puras exportadas por `src/` (`:37-38`).
- Configuração: nenhuma (`:48`).
- Fora do projeto: banco, interface, serviço externo, segredo (`:52-55`, sem marcação de origem).

## Contrato de saída

- Saída esperada de feature: função pura exportada por `src/` (`:37`).
- Valor de retorno de `proximoNumero`: NÃO DOCUMENTADO neste arquivo (só no briefing).

## Limites e cotas

NÃO DOCUMENTADO — o arquivo não traz limite numérico.

## Erros conhecidos e tratamento

- Entrada inválida lança `TypeError` síncrono (`:42`).
- Erro de função reutilizada é propagado sem captura nem reembrulho (`:42-44`).

## Riscos para a nossa implementação

- O PR da feature deve mirar a Branch base `buildx/p0-e2e-v2`, não `main` (`:11-12`).
- Nenhuma regra validada na prática além do comando de teste (`:3-5`).
- Sem lint: estilo (`'use strict'`, aspas simples) só se deduz dos arquivos existentes (`src/index.js:1`, `test/smoke.test.js:1`).
- Proibição de dependências (`:20`) impede biblioteca de validação.

## Fonte

`docs/stack/CONVENCOES.md:3-5`, `:11`, `:12`, `:14`, `:18`, `:19`, `:20`, `:24`, `:25`, `:31`, `:33`, `:37-38`, `:42-44`, `:48`, `:52-55` — acessado em 2026-09-16
