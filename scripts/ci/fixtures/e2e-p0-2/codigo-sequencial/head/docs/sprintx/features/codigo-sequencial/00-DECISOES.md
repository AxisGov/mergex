---
expx_schema: 1
expx_tool: sprintx
kind: decisoes
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
densidade: padrao
modo_construcao: autonomo
atualizado_em: 2026-09-16
decisoes:
  - id: D-00
    decisao: densidade padrao, construcao autonomo
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-13 para a densidade e PROJETO.md frontmatter modo autonomo para a construcao — F2 respondida pelo BuildX sem pergunta ao humano"
    status: fechada
    bloqueante: false
  - id: D-01
    decisao: Entregar a funcao publica proximoCodigo(valor) que reutiliza proximoNumero
    alternativa_descartada: null
    motivo: "Fonte: PROJETO.md#o-que-foi-pedido — declarado pelo usuario no briefing BuildX"
    status: fechada
    bloqueante: false
  - id: D-02
    decisao: A feature termina integrada em buildx/p0-e2e-v2 por fast-forward, depois da FT-01
    alternativa_descartada: Merge com commit ou integracao direta em main
    motivo: "Fonte: PROJETO.md#descricao-original — declarado pelo usuario no briefing BuildX"
    status: fechada
    bloqueante: false
  - id: D-03
    decisao: proximoCodigo obtem o proximo numero chamando proximoNumero(valor) importado por require de ./proximo-numero.js; nenhum valor + 1 nem algoritmo equivalente em src/proximo-codigo.js
    alternativa_descartada: Calcular valor + 1 localmente ou importar via src/index.js
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-11 e PREMISSAS.md#PR-14 — regra unica de incremento; import pelo modulo evita ciclo com src/index.js (base/proximo-numero.md)"
    status: fechada
    bloqueante: false
  - id: D-04
    decisao: proximoCodigo vive em src/proximo-codigo.js, teste em test/proximo-codigo.test.js, reexportado como propriedade nomeada de src/index.js junto de proximoNumero
    alternativa_descartada: Implementar em src/proximo-numero.js ou direto em src/index.js
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-14 — convencao escolhida pelo BuildX na FT-01; smoke exige index objeto (base/modulo-principal-e-harness.md)"
    status: fechada
    bloqueante: false
  - id: D-05
    decisao: O codigo comeca com o literal SEQ- em maiusculas, sem prefixo configuravel
    alternativa_descartada: Prefixo parametrizavel
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-07 — catalogo de lacunas do BuildX"
    status: fechada
    bloqueante: false
  - id: D-06
    decisao: A parte numerica tem pelo menos 6 digitos com zeros a esquerda; proximoCodigo(1) devolve SEQ-000002 e proximoCodigo(0) devolve SEQ-000001
    alternativa_descartada: Largura livre ou outro preenchimento
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-08 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — proximoCodigo(1) devolve SEQ-000002"
    status: fechada
    bloqueante: false
  - id: D-07
    decisao: Numero com mais de 6 digitos entra inteiro no codigo; proximoCodigo(999999) devolve SEQ-1000000 e proximoCodigo(1234567) devolve SEQ-1234568
    alternativa_descartada: Truncar para 6 digitos
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-09 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — sem truncar"
    status: fechada
    bloqueante: false
  - id: D-08
    decisao: proximoCodigo nao valida a entrada por conta propria e nao captura erro; o TypeError lancado por proximoNumero chega ao chamador como o mesmo objeto de erro, sem reembrulho
    alternativa_descartada: Validacao propria ou try/catch com TypeError novo
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-12 e CONVENCOES.md#sinalizacao-de-erro — decidido_pelo_buildx, primeira reutilizacao do projeto"
    status: fechada
    bloqueante: false
  - id: D-09
    decisao: Formato de digitos garantido so ate Number.MAX_SAFE_INTEGER; parte numerica vem de String(numero); testes de largura e nao truncamento usam inteiros seguros
    alternativa_descartada: Tratar notacao exponencial ou teto acima da faixa segura
    motivo: "(HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-15 — convencao escolhida pelo BuildX; String(1e21) devolve 1e+21 (verificado na F2)"
    status: fechada
    bloqueante: false
  - id: D-10
    decisao: Testes de erro de proximoCodigo verificam que o erro e TypeError e identico ao lancado por proximoNumero para a mesma entrada (mesma classe e mesma mensagem), sem fixar o texto
    alternativa_descartada: Fixar o texto da mensagem
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-12 e base/proximo-numero.md — mensagem nao e contrato (D-10 da FT-01), propagacao sim"
    status: fechada
    bloqueante: false
  - id: D-11
    decisao: O reuso de proximoNumero e provado por teste que injeta um duble de proximoNumero via require.cache antes de carregar src/proximo-codigo.js e verifica a chamada e o uso do valor devolvido
    alternativa_descartada: Provar reuso so por comportamento igual ou por leitura textual do fonte
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-11 e CONVENCOES.md#stack — reuso e requisito de codigo; sem dependencia externa, sem biblioteca de mock"
    status: fechada
    bloqueante: false
  - id: D-12
    decisao: Sem persistencia, estado, log, metrica, ambiente ou segredo
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-10 e CONVENCOES.md#configuracao — decidido_pelo_buildx"
    status: fechada
    bloqueante: false
  - id: D-13
    decisao: Testes com node:test e node:assert/strict via npm test, pares integracao pelo index e funcional pelo modulo, estilo use strict e aspas simples; runtime local Node v24.18.0, sem engines
    alternativa_descartada: Framework externo ou campo engines
    motivo: "(HIPOTESE) fonte: CONVENCOES.md#estrutura e CONVENCOES.md#comandos e base/modulo-principal-e-harness.md — padrao da FT-01"
    status: fechada
    bloqueante: false
  - id: D-14
    decisao: Pronto quando proximoCodigo(1) devolve SEQ-000002, numero de mais de 6 digitos nao trunca, entrada invalida propaga o TypeError de proximoNumero, reuso provado por teste e npm test inteiro verde
    alternativa_descartada: null
    motivo: "(HIPOTESE) fonte: PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio e MAPA.md#ft-02"
    status: fechada
    bloqueante: false
  - id: D-15
    decisao: Refina D-10 - a propagacao e provada por duble de proximoNumero que lanca um objeto de erro sentinela, que deve chegar ao chamador como o mesmo objeto; com o modulo real, classe e mensagem iguais as de proximoNumero; testes da FT-02 prefixados com FT-02 no nome
    alternativa_descartada: Provar propagacao so por classe e mensagem (D-10), que nao derruba reembrulho nem validacao copiada
    motivo: "(HIPOTESE) fonte: PREMISSAS.md#PR-12 e 00-AUDITORIA.md rodada 1 achado ALTA — refina D-10 sem apaga-la"
    status: fechada
    bloqueante: false
---

# Decisões — codigo-sequencial

> Uma linha por decisão tomada no planejamento (F2 e, excepcionalmente, F3). Formato fixo. Não apague decisões: uma decisão revertida ganha nova linha que cita a anterior.

## Densidade e forma de construção

**Densidade:** padrao
**Forma de construção:** autonomo

Sem `BRIEFING.md` do prodx. F2 respondida pelo BuildX (modo autônomo), pelos quatro degraus. Único ponto sem fonte nos três arquivos — formatação fora da faixa segura — virou premissa nova PR-15 em `BUILDX-PREMISSAS.md`, gravada antes do uso.

## Decisões

```
D-00 | densidade padrao, construcao autonomo | null | (HIPOTESE) fonte: PREMISSAS.md#PR-13 para a densidade e PROJETO.md frontmatter modo autonomo para a construcao — F2 respondida pelo BuildX sem pergunta ao humano
D-01 | Entregar a funcao publica proximoCodigo(valor) que reutiliza proximoNumero | null | Fonte: PROJETO.md#o-que-foi-pedido — declarado pelo usuario no briefing BuildX
D-02 | A feature termina integrada em buildx/p0-e2e-v2 por fast-forward, depois da FT-01 | Merge com commit ou integracao direta em main | Fonte: PROJETO.md#descricao-original — declarado pelo usuario no briefing BuildX
D-03 | proximoCodigo obtem o proximo numero chamando proximoNumero(valor) importado por require de ./proximo-numero.js; nenhum valor + 1 nem algoritmo equivalente em src/proximo-codigo.js | Calcular valor + 1 localmente ou importar via src/index.js | (HIPOTESE) fonte: PREMISSAS.md#PR-11 e PREMISSAS.md#PR-14 — regra unica de incremento; import pelo modulo evita ciclo com src/index.js (base/proximo-numero.md)
D-04 | proximoCodigo vive em src/proximo-codigo.js, teste em test/proximo-codigo.test.js, reexportado como propriedade nomeada de src/index.js junto de proximoNumero | Implementar em src/proximo-numero.js ou direto em src/index.js | (HIPOTESE) fonte: PREMISSAS.md#PR-14 — convencao escolhida pelo BuildX na FT-01; smoke exige index objeto (base/modulo-principal-e-harness.md)
D-05 | O codigo comeca com o literal SEQ- em maiusculas, sem prefixo configuravel | Prefixo parametrizavel | (HIPOTESE) fonte: PREMISSAS.md#PR-07 — catalogo de lacunas do BuildX
D-06 | A parte numerica tem pelo menos 6 digitos com zeros a esquerda; proximoCodigo(1) devolve SEQ-000002 e proximoCodigo(0) devolve SEQ-000001 | Largura livre ou outro preenchimento | (HIPOTESE) fonte: PREMISSAS.md#PR-08 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — proximoCodigo(1) devolve SEQ-000002
D-07 | Numero com mais de 6 digitos entra inteiro no codigo; proximoCodigo(999999) devolve SEQ-1000000 e proximoCodigo(1234567) devolve SEQ-1234568 | Truncar para 6 digitos | (HIPOTESE) fonte: PREMISSAS.md#PR-09 e PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio — sem truncar
D-08 | proximoCodigo nao valida a entrada por conta propria e nao captura erro; o TypeError lancado por proximoNumero chega ao chamador como o mesmo objeto de erro, sem reembrulho | Validacao propria ou try/catch com TypeError novo | (HIPOTESE) fonte: PREMISSAS.md#PR-12 e CONVENCOES.md#sinalizacao-de-erro — decidido_pelo_buildx, primeira reutilizacao do projeto
D-09 | Formato de digitos garantido so ate Number.MAX_SAFE_INTEGER; parte numerica vem de String(numero); testes de largura e nao truncamento usam inteiros seguros | Tratar notacao exponencial ou teto acima da faixa segura | (HIPOTESE) fonte: BUILDX-PREMISSAS.md#PR-15 — convencao escolhida pelo BuildX; String(1e21) devolve 1e+21 (verificado na F2)
D-10 | Testes de erro de proximoCodigo verificam que o erro e TypeError e identico ao lancado por proximoNumero para a mesma entrada (mesma classe e mesma mensagem), sem fixar o texto | Fixar o texto da mensagem | (HIPOTESE) fonte: PREMISSAS.md#PR-12 e base/proximo-numero.md — mensagem nao e contrato (D-10 da FT-01), propagacao sim
D-11 | O reuso de proximoNumero e provado por teste que injeta um duble de proximoNumero via require.cache antes de carregar src/proximo-codigo.js e verifica a chamada e o uso do valor devolvido | Provar reuso so por comportamento igual ou por leitura textual do fonte | (HIPOTESE) fonte: PREMISSAS.md#PR-11 e CONVENCOES.md#stack — reuso e requisito de codigo; sem dependencia externa, sem biblioteca de mock
D-12 | Sem persistencia, estado, log, metrica, ambiente ou segredo | null | (HIPOTESE) fonte: PREMISSAS.md#PR-10 e CONVENCOES.md#configuracao — decidido_pelo_buildx
D-13 | Testes com node:test e node:assert/strict via npm test, pares integracao pelo index e funcional pelo modulo, estilo use strict e aspas simples; runtime local Node v24.18.0, sem engines | Framework externo ou campo engines | (HIPOTESE) fonte: CONVENCOES.md#estrutura e CONVENCOES.md#comandos e base/modulo-principal-e-harness.md — padrao da FT-01
D-14 | Pronto quando proximoCodigo(1) devolve SEQ-000002, numero de mais de 6 digitos nao trunca, entrada invalida propaga o TypeError de proximoNumero, reuso provado por teste e npm test inteiro verde | null | (HIPOTESE) fonte: PROJETO.md#criterios-de-aceite-do-ponto-de-vista-do-negocio e MAPA.md#ft-02
D-15 | Refina D-10 - a propagacao e provada por duble de proximoNumero que lanca um objeto de erro sentinela, que deve chegar ao chamador como o mesmo objeto; com o modulo real, classe e mensagem iguais as de proximoNumero; testes da FT-02 prefixados com FT-02 no nome | Provar propagacao so por classe e mensagem (D-10), que nao derruba reembrulho nem validacao copiada | (HIPOTESE) fonte: PREMISSAS.md#PR-12 e 00-AUDITORIA.md rodada 1 achado ALTA — refina D-10 sem apaga-la
```

## Cobertura dos eixos e das lacunas da F1

| Eixo / lacuna | Decisão |
|---|---|
| 1 Escopo de negócio | D-01, D-05, D-06, D-07 |
| 2 Arquitetura | D-03, D-04, D-11 |
| 3 Contrato de dados | D-06, D-07, D-09, D-12 |
| 4 Estado e observabilidade | D-12 |
| 5 Resiliência e erro | D-08, D-10, D-15 |
| 6 Ambiente e segredos | D-12 |
| 7 Definição de pronto | D-02, D-14 |
| lacunas `proximo-numero` (formatação fora da faixa, D-09/D-10/PR-06) | D-09, D-10 |
| lacunas `modulo-principal-e-harness` (nome do arquivo, reexport, numeração, Node, descoberta) | D-04, D-13 (numeração das tasks fica para a F3) |
| lacunas `convencoes` (proximoCodigo, SEQ-, zeros, largura, truncamento, mensagem) | D-01, D-05, D-06, D-07, D-08, D-10 |

Nenhuma contradição com a base da F1.

## Pendências

Nenhuma pendência.
