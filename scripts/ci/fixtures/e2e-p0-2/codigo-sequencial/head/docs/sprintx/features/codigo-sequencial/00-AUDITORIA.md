# Auditoria — codigo-sequencial

Data: 2026-09-16 · Rodada 2 (reauditoria)

Auditoria emitida pelo agente `auditor-plano`, em contexto separado de quem gerou o plano (somente leitura). Sprints lidas no formato condensado (`kind: plano`); a ausência de `sprint.md` e `fases.md` é o formato, não achado.

**Histórico:** a rodada 1 deu `VEREDITO: NÃO` — achado ALTA na T-02.01 (testes não derrubavam reembrulho do `TypeError` nem validação copiada), MÉDIA na restauração do `require.cache` e quatro BAIXA. A F3 regerou o plano (D-15 refina D-10; T-02.01 com erro sentinela idêntico; restauração verificada por chamada real; procedimento do duble explícito; prefixo `FT-02`; F4 atualizada). A rodada 2 confirmou todos os achados da rodada 1 como resolvidos e auditou o plano novo inteiro.

## Achados

| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| BAIXA | sprint-02/tasks.md | T-02.01: a checagem de restauração no `criterio_aceite` ("um novo require de src/proximo-codigo.js lança TypeError para '1'") não pega falha se o sentinela for um `TypeError`: com a entrada do duble ainda no cache, o novo require lança o próprio sentinela e a checagem passa. | Exigir que o sentinela não seja `TypeError` (ex.: `new Error('sentinela')`), ou exigir na checagem pós-restauração erro `!== sentinela` com a mesma mensagem de `proximoNumero` real. |
| BAIXA | sprint-02/tasks.md | F-02.1, T-02.01 e T-02.02: o procedimento só apaga as entradas do `require.cache`, sem devolver as originais; depois do primeiro teste com duble, `src/index.js` em cache aponta para as instâncias antigas e um novo `require` devolve instâncias novas. O teste de identidade da T-01.01 só passa porque vem antes no arquivo. | Guardar e devolver as entradas originais no `finally`, ou registrar que os testes de identidade da T-01.01 ficam antes dos testes com duble em `test/proximo-codigo.test.js`. |

## Revisão de testes por task

O agente `revisor-testes` **não foi disponibilizado pelo harness** (frontmatter YAML inválido em `.claude/agents/revisor-testes.md`; nova tentativa nesta F5 devolveu "Agent type 'revisor-testes' not found"). Revisão no contexto principal, pela regra da skill:

```
T-01.01 | solido | a identidade de referência de proximoCodigo e de proximoNumero pelo index derruba um index que não reexporte, embrulhe ou perca proximoNumero
T-02.01 | solido | o sentinela idêntico derruba reembrulho por try/catch, validação copiada e import por src/index.js, e a comparação de mensagem com o módulo real derruba erro genérico
T-02.02 | solido | o duble que devolve 1234567 para a entrada 5 derruba valor + 1 local, e 999999 → SEQ-1000000 derruba prefixo ausente
T-02.03 | solido | SEQ-000001/SEQ-000042 derrubam padding ausente ou do lado errado, e 1234567 → SEQ-1234568 derruba truncamento por slice(-6)
```

VEREDITO: SIM — o plano está pronto para execução autônoma.
