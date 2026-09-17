---
expx_schema: 1
expx_tool: sprintx
kind: base_indice
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
atualizado_em: 2026-09-16
areas:
  - arquivo: proximo-numero.md
    titulo: proximoNumero contrato real da FT-01
    lacunas: 2
  - arquivo: modulo-principal-e-harness.md
    titulo: Modulo principal e harness de teste
    lacunas: 5
  - arquivo: convencoes.md
    titulo: Convencoes do projeto
    lacunas: 6
---

# Índice da base — codigo-sequencial

| Arquivo | Área | Resumo |
|---|---|---|
| `proximo-numero.md` | proximoNumero (FT-01) | Import por `require('./proximo-numero.js')`, devolve `valor + 1`, `TypeError` síncrono para tipo e domínio, perda de precisão acima de `MAX_SAFE_INTEGER` |
| `modulo-principal-e-harness.md` | Módulo principal e harness | `src/index.js` exporta objeto nomeado; testes `node:test` em pares integração/funcional; `npm test` com 9 testes |
| `convencoes.md` | Convenções do projeto | CommonJS sem dependências; `TypeError` síncrono; propagação de erro de função reutilizada ainda sem evidência |
