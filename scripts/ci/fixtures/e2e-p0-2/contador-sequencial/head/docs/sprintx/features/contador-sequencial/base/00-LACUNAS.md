# Lacunas

Uma linha por lacuna, com onde se procurou. Levantadas pelo agente `investigador` na F1.

## modulo-principal

- Campo `main` / `exports` do pacote: NÃO DOCUMENTADO (procurado em `package.json`)
- Formato do export da nova função (propriedade do objeto ou export direto): NÃO DOCUMENTADO (procurado em `src/index.js` e `docs/stack/CONVENCOES.md`); só a restrição `typeof lib === 'object'` em `test/smoke.test.js:8`
- Assinatura e semântica de `proximoNumero`: NÃO DOCUMENTADO no código (procurado em `src/index.js` e `docs/stack/CONVENCOES.md`); só no briefing
- Casos de borda de "inteiro >= 0" (`NaN`, `Infinity`, `-0`, fracionário, acima de `Number.MAX_SAFE_INTEGER`, `Number` embrulhado): NÃO DOCUMENTADO no código (procurado em `docs/stack/CONVENCOES.md:42-44` e `src/index.js`)
- Mensagem do `TypeError`: NÃO DOCUMENTADO (procurado em `docs/stack/CONVENCOES.md:42-44`)
- Documentação pública da API (JSDoc, README): NÃO DOCUMENTADO (procurado nos 4 arquivos lidos)

## harness-de-teste

- Versão mínima do Node (`engines`): NÃO DOCUMENTADO (procurado em `package.json` e `docs/stack/CONVENCOES.md:18`)
- Cobertura de testes: NÃO DOCUMENTADO (procurado em `package.json` e `docs/stack/CONVENCOES.md`)
- Nome do arquivo de teste da feature: NÃO DOCUMENTADO; só o padrão `test/*.test.js` (`docs/stack/CONVENCOES.md:25`)
- Timeout e concorrência do `node --test`: NÃO DOCUMENTADO (procurado em `package.json:7` e `docs/stack/CONVENCOES.md:31`)

## convencoes

- Lint e formatação: inexistentes por declaração (`docs/stack/CONVENCOES.md:33`); `package.json` sem script de lint
- Estilo de código como regra escrita: NÃO DOCUMENTADO (procurado em `docs/stack/CONVENCOES.md`); só se deduz de `src/index.js:1` e `test/smoke.test.js:1`
- Escopo/idioma da mensagem de commit além do prefixo: NÃO DOCUMENTADO (procurado em `docs/stack/CONVENCOES.md:14`)
- Origem das regras de "Fora do projeto": NÃO DOCUMENTADO; seção sem marcação `decidido_pelo_buildx` (`docs/stack/CONVENCOES.md:50-55`)
