---
expx_schema: 1
expx_tool: sprintx
kind: decisoes
trabalho_id: contador-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-01
densidade: padrao
modo_construcao: autonomo
atualizado_em: 2026-09-16
decisoes:
  - id: D-00
    decisao: densidade padrao, construcao autonomo
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-13 para a densidade e PROJETO.md frontmatter modo autonomo para a construcao — F2 respondida pelo BuildX sem pergunta ao humano"
    status: fechada
    bloqueante: false
  - id: D-01
    decisao: Entregar a funcao publica proximoNumero(valor)
    alternativa_descartada: null
    motivo: "Fonte: PROJETO.md#o-que-foi-pedido — declarado pelo usuario no briefing BuildX"
    status: fechada
    bloqueante: false
  - id: D-02
    decisao: A feature termina integrada em buildx/p0-e2e-v2 por fast-forward
    alternativa_descartada: Merge com commit ou integracao direta em main
    motivo: "Fonte: PROJETO.md#descricao-original — declarado pelo usuario no briefing BuildX"
    status: fechada
    bloqueante: false
  - id: D-03
    decisao: proximoCodigo e o prefixo SEQ- ficam fora desta feature
    alternativa_descartada: Entregar proximoNumero e proximoCodigo juntos
    motivo: "(HIPOTESE) fonte: MAPA.md#ft-02 — recorte do B3 do BuildX, FT-02 depende de FT-01"
    status: fechada
    bloqueante: false
  - id: D-04
    decisao: proximoNumero vive em src/proximo-numero.js, teste em test/proximo-numero.test.js, reexportado como propriedade nomeada de src/index.js
    alternativa_descartada: Implementar direto em src/index.js ou exportar a funcao como module.exports
    motivo: "(HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-14 — convencao escolhida pelo BuildX; base/modulo-principal.md registra que o smoke exige objeto"
    status: fechada
    bloqueante: false
  - id: D-05
    decisao: Biblioteca CommonJS com use strict, sem dependencia externa, sem campo main ou exports novo no package.json
    alternativa_descartada: ESM ou pacote com exports declarado
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-01 e CONVENCOES.md#stack — decidido_pelo_buildx no B2"
    status: fechada
    bloqueante: false
  - id: D-06
    decisao: Aceita somente typeof number, Number.isInteger e maior ou igual a zero; retorna valor + 1
    alternativa_descartada: Coercao de string ou BigInt
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-02 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — proximoNumero(0) devolve 1"
    status: fechada
    bloqueante: false
  - id: D-07
    decisao: Negativo, fracionario, NaN, Infinity, -Infinity, BigInt 1n, string 1 e Number embrulhado em objeto lancam TypeError sincrono
    alternativa_descartada: RangeError para negativo ou arredondamento de fracionario
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-03, PR-04, PR-05 e CONVENCOES.md#sinalizacao-de-erro — decidido_pelo_buildx; Number embrulhado tem typeof object"
    status: fechada
    bloqueante: false
  - id: D-08
    decisao: -0 e aceito como inteiro maior ou igual a zero e devolve 1
    alternativa_descartada: Rejeitar -0 com TypeError
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-02 — Number.isInteger(-0) e -0 >= 0 sao verdadeiros, PR-02 nao exclui -0"
    status: fechada
    bloqueante: false
  - id: D-09
    decisao: Sem limite superior; inteiro acima de Number.MAX_SAFE_INTEGER e aceito e devolve valor + 1 em aritmetica de number
    alternativa_descartada: Lancar erro acima de MAX_SAFE_INTEGER
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-06 — sem teto explicito; a perda de precisao e o proprio invalidador registrado em PR-06"
    status: fechada
    bloqueante: false
  - id: D-10
    decisao: A mensagem do TypeError nao faz parte do contrato; testes verificam a classe do erro
    alternativa_descartada: Fixar texto de mensagem nos testes
    motivo: "(HIPOTESE) fonte: CONVENCOES.md#sinalizacao-de-erro — so exige TypeError sincrono, nenhuma mensagem declarada"
    status: fechada
    bloqueante: false
  - id: D-11
    decisao: Sem persistencia, sem estado entre chamadas, sem log, sem metrica
    alternativa_descartada: Guardar o ultimo numero emitido ou registrar log
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-10 — sem efeitos; funcao pura"
    status: fechada
    bloqueante: false
  - id: D-12
    decisao: Sem ambiente, variavel ou segredo
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: CONVENCOES.md#configuracao — decidido_pelo_buildx no B2"
    status: fechada
    bloqueante: false
  - id: D-13
    decisao: Testes com node:test e node:assert/strict via npm test, sem engines, cobertura ou timeout novos; runtime local Node v24.18.0
    alternativa_descartada: Framework externo, meta de cobertura ou campo engines
    motivo: "(HIPOTESE) fonte: CONVENCOES.md#comandos e CONVENCOES.md#estrutura — decidido_pelo_buildx; node --version na F2 respondeu v24.18.0"
    status: fechada
    bloqueante: false
  - id: D-14
    decisao: Estilo dos arquivos novos segue os existentes, use strict e aspas simples; sem README nem JSDoc novos
    alternativa_descartada: Documentacao publica da API
    motivo: "(HIPOTESE) fonte: CONVENCOES.md#comandos sem lint e base/convencoes.md — estilo deduzido de src/index.js:1; documentacao nao consta de PROJETO.md#o-que-foi-pedido"
    status: fechada
    bloqueante: false
  - id: D-15
    decisao: Pronto quando proximoNumero(0) devolve 1, entradas invalidas lancam TypeError, smoke e suite inteira verdes com npm test
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio e CONVENCOES.md#comandos"
    status: fechada
    bloqueante: false
---

# Decisões — contador-sequencial

> Uma linha por decisão tomada no planejamento (F2 e, excepcionalmente, F3). Formato fixo. Não apague decisões: uma decisão revertida ganha nova linha que cita a anterior.

## Densidade e forma de construção

**Densidade:** padrao
**Forma de construção:** autonomo

Sem `BRIEFING.md` do prodx. F2 respondida pelo BuildX (modo autônomo), pelos quatro degraus: `PROJETO.md`, `PREMISSAS.md`, `CONVENCOES.md` e, para o que nenhum dos três responde, premissa nova em `BUILDX-PREMISSAS.md` gravada antes do uso.

## Decisões

```
D-00 | densidade padrao, construcao autonomo | null | (HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-13 para a densidade e PROJETO.md frontmatter modo autonomo para a construcao — F2 respondida pelo BuildX sem pergunta ao humano
D-01 | Entregar a funcao publica proximoNumero(valor) | null | Fonte: PROJETO.md#o-que-foi-pedido — declarado pelo usuario no briefing BuildX
D-02 | A feature termina integrada em buildx/p0-e2e-v2 por fast-forward | Merge com commit ou integracao direta em main | Fonte: PROJETO.md#descricao-original — declarado pelo usuario no briefing BuildX
D-03 | proximoCodigo e o prefixo SEQ- ficam fora desta feature | Entregar proximoNumero e proximoCodigo juntos | (HIPOTESE) fonte: MAPA.md#ft-02 — recorte do B3 do BuildX, FT-02 depende de FT-01
D-04 | proximoNumero vive em src/proximo-numero.js, teste em test/proximo-numero.test.js, reexportado como propriedade nomeada de src/index.js | Implementar direto em src/index.js ou exportar a funcao como module.exports | (HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-14 — convencao escolhida pelo BuildX; base/modulo-principal.md registra que o smoke exige objeto
D-05 | Biblioteca CommonJS com use strict, sem dependencia externa, sem campo main ou exports novo no package.json | ESM ou pacote com exports declarado | (HIPOTESE) fonte: PREMISSAS.md#PR-01 e CONVENCOES.md#stack — decidido_pelo_buildx no B2
D-06 | Aceita somente typeof number, Number.isInteger e maior ou igual a zero; retorna valor + 1 | Coercao de string ou BigInt | (HIPOTESE) fonte: PREMISSAS.md#PR-02 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — proximoNumero(0) devolve 1
D-07 | Negativo, fracionario, NaN, Infinity, -Infinity, BigInt 1n, string 1 e Number embrulhado em objeto lancam TypeError sincrono | RangeError para negativo ou arredondamento de fracionario | (HIPOTESE) fonte: PREMISSAS.md#PR-03, PR-04, PR-05 e CONVENCOES.md#sinalizacao-de-erro — decidido_pelo_buildx; Number embrulhado tem typeof object
D-08 | -0 e aceito como inteiro maior ou igual a zero e devolve 1 | Rejeitar -0 com TypeError | (HIPOTESE) fonte: PREMISSAS.md#PR-02 — Number.isInteger(-0) e -0 >= 0 sao verdadeiros, PR-02 nao exclui -0
D-09 | Sem limite superior; inteiro acima de Number.MAX_SAFE_INTEGER e aceito e devolve valor + 1 em aritmetica de number | Lancar erro acima de MAX_SAFE_INTEGER | (HIPOTESE) fonte: PREMISSAS.md#PR-06 — sem teto explicito; a perda de precisao e o proprio invalidador registrado em PR-06
D-10 | A mensagem do TypeError nao faz parte do contrato; testes verificam a classe do erro | Fixar texto de mensagem nos testes | (HIPOTESE) fonte: CONVENCOES.md#sinalizacao-de-erro — so exige TypeError sincrono, nenhuma mensagem declarada
D-11 | Sem persistencia, sem estado entre chamadas, sem log, sem metrica | Guardar o ultimo numero emitido ou registrar log | (HIPOTESE) fonte: PREMISSAS.md#PR-10 — sem efeitos; funcao pura
D-12 | Sem ambiente, variavel ou segredo | null | (HIPOTESE) fonte: CONVENCOES.md#configuracao — decidido_pelo_buildx no B2
D-13 | Testes com node:test e node:assert/strict via npm test, sem engines, cobertura ou timeout novos; runtime local Node v24.18.0 | Framework externo, meta de cobertura ou campo engines | (HIPOTESE) fonte: CONVENCOES.md#comandos e CONVENCOES.md#estrutura — decidido_pelo_buildx; node --version na F2 respondeu v24.18.0
D-14 | Estilo dos arquivos novos segue os existentes, use strict e aspas simples; sem README nem JSDoc novos | Documentacao publica da API | (HIPOTESE) fonte: CONVENCOES.md#comandos sem lint e base/convencoes.md — estilo deduzido de src/index.js:1; documentacao nao consta de PROJETO.md#o-que-foi-pedido
D-15 | Pronto quando proximoNumero(0) devolve 1, entradas invalidas lancam TypeError, smoke e suite inteira verdes com npm test | null | (HIPOTESE) fonte: PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio e CONVENCOES.md#comandos
```

## Cobertura dos eixos e das lacunas da F1

| Eixo / lacuna | Decisão |
|---|---|
| 1 Escopo de negócio | D-01, D-03 |
| 2 Arquitetura | D-04, D-05 |
| 3 Contrato de dados | D-06, D-08, D-09, D-11 |
| 4 Estado e observabilidade | D-11 |
| 5 Resiliência e erro | D-07, D-10 |
| 6 Ambiente e segredos | D-12 |
| 7 Definição de pronto | D-02, D-15 |
| lacunas `modulo-principal` (main/exports, formato do export, assinatura, bordas, mensagem, doc) | D-05, D-04, D-06, D-07/D-08/D-09, D-10, D-14 |
| lacunas `harness-de-teste` (engines, cobertura, nome do teste, timeout) | D-13, D-04 |
| lacunas `convencoes` (lint, estilo, commit, fora do projeto) | D-14, D-02 (commits pela mergex, Conventional Commits de `CONVENCOES.md#versionamento`), D-12 |

Nenhuma contradição com a base da F1.

## Pendências

Nenhuma pendência.
