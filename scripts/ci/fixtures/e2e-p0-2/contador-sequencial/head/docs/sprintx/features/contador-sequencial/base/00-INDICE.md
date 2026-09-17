---
expx_schema: 1
expx_tool: sprintx
kind: base_indice
trabalho_id: contador-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-01
atualizado_em: 2026-09-16
areas:
  - arquivo: modulo-principal.md
    titulo: Modulo principal src/index.js
    lacunas: 6
  - arquivo: harness-de-teste.md
    titulo: Harness de teste node:test
    lacunas: 4
  - arquivo: convencoes.md
    titulo: Convencoes do projeto
    lacunas: 4
---

# Índice da base — contador-sequencial

| Arquivo | Área | Resumo |
|---|---|---|
| `modulo-principal.md` | Módulo principal `src/index.js` | Exporta objeto CommonJS vazio; função nova entra como propriedade para manter o smoke verde |
| `harness-de-teste.md` | Harness de teste | `npm test` → `node --test`, `node:test` + `node:assert/strict`, testes em `test/*.test.js` |
| `convencoes.md` | Convenções do projeto | Branch base `buildx/p0-e2e-v2`, CommonJS sem dependências, `TypeError` síncrono e propagação sem reembrulho |
