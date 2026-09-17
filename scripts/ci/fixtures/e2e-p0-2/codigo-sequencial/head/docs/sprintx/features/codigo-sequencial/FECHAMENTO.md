---
expx_schema: 1
expx_tool: sprintx
kind: fechamento
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
titulo: Codigo sequencial formatado proximoCodigo
tipo_trabalho: feature
fechado_em: 2026-09-16
modulo_afetado: [raiz, test]
arquivos_alterados: [src/index.js, src/proximo-codigo.js, test/proximo-codigo.test.js]
palavras_chave: [codigo, sequencial, proximocodigo, prefixo, zeros, reuso, typeerror]
resumo: A biblioteca expoe proximoCodigo(valor), que devolve SEQ- mais o numero de proximoNumero com pelo menos 6 digitos, sem truncar, propagando o TypeError de proximoNumero
decisao_principal: proximoCodigo obtem o proximo numero chamando proximoNumero(valor) importado por require de ./proximo-numero.js; nenhum valor + 1 nem algoritmo equivalente em src/proximo-codigo.js
risco_residual: Formato de digitos so garantido ate Number.MAX_SAFE_INTEGER (PR-15, D-09); acima disso String pode perder precisao ou gerar notacao exponencial; testes de duble dependem de apagar o require.cache
testes_adicionados: 8
---

# Fechamento — codigo-sequencial

> Registro do que este trabalho entregou, em que módulo e em que arquivos. É o que torna a
> feature encontrável depois: por arquivo, por módulo e por palavra-chave.
> Os três campos de indexação são cópia fiel do `ORQUESTRADOR.md` no momento do fechamento.

## O que foi entregue

A biblioteca expõe `proximoCodigo(valor)`, que devolve `SEQ-` mais o número calculado por `proximoNumero` com pelo menos 6 dígitos (`proximoCodigo(1)` → `SEQ-000002`), sem truncar números maiores, e propaga o `TypeError` de `proximoNumero` como o mesmo objeto.

## Decisão principal

D-03 — `proximoCodigo` obtém o próximo número chamando `proximoNumero(valor)` importado por `require('./proximo-numero.js')`; nenhum `valor + 1` nem algoritmo equivalente em `src/proximo-codigo.js`. O reuso é provado por teste com duble de `proximoNumero` (D-11), e a propagação por erro sentinela idêntico (D-15).

## Risco residual

Formato de dígitos só garantido até `Number.MAX_SAFE_INTEGER` (PR-15, D-09); acima disso `String` pode perder precisão ou gerar notação exponencial. Os testes com duble dependem de apagar o `require.cache` das duas entradas ao fim.

## Onde isto mexeu

- **Módulos:** raiz, test
- **Arquivos:** `src/index.js`, `src/proximo-codigo.js`, `test/proximo-codigo.test.js`
- **Testes adicionados:** 8
