# Premissas pendentes do BuildX

### PR-13 — Densidade padrao nas features do contador

- origem: f2_autonoma
- decisao: As features da biblioteca sequencial sao planejadas com densidade padrao da sprintx
- justificativa: PREMISSAS.md PR-02 a PR-06 ja enumeram os casos de borda da entrada; PROJETO.md#fora-de-escopo exclui UI, persistencia, rede e segredo; nenhum dos tres arquivos pede investigacao de segunda ordem
- o_que_invalida: surgir exigencia de investigar casos de borda nao listados em PREMISSAS.md (ex.: perda de precisao acima de Number.MAX_SAFE_INTEGER) ou efeito em outro sistema consumidor
- status: pendente_promocao

### PR-14 — Um modulo por funcao publica, reexportado por src/index.js

- origem: f2_autonoma
- decisao: Cada funcao publica vive em modulo proprio em src/ (proximoNumero em src/proximo-numero.js, teste em test/proximo-numero.test.js) e e reexportada como propriedade nomeada do objeto de src/index.js
- justificativa: CONVENCOES.md#estrutura poe produto em src/ e testes em test/*.test.js; CONVENCOES.md#camadas pede funcoes puras exportadas por src/; o smoke exige que src/index.js exporte objeto (test/smoke.test.js:8); modulo proprio deixa a FT-02 importar proximoNumero por require sem ciclo com src/index.js
- o_que_invalida: o projeto adotar modulo unico em src/index.js, ou a API publica passar a ser um pacote com campo exports proprio
- status: pendente_promocao
