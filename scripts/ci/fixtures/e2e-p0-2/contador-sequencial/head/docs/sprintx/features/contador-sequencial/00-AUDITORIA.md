# Auditoria — contador-sequencial

Data: 2026-09-16

Auditoria emitida pelo agente `auditor-plano`, em contexto separado de quem gerou o plano (somente leitura). Sprints lidas no formato condensado (`kind: plano`) — `sprint-01/tasks.md` e `sprint-02/tasks.md`; a ausência de `sprint.md` e `fases.md` é o formato, não achado.

## Achados

| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| MÉDIA | sprint-02/tasks.md | O `teste_funcional` da T-02.01 para no `Number.MAX_SAFE_INTEGER`, que ainda é um inteiro seguro. Uma implementação que valide com `Number.isSafeInteger` (e passe a lançar erro acima do limite) passa em todos os testes do plano e contraria a D-09 sem que ninguém perceba. A definição de pronto do ORQUESTRADOR.md tem a mesma lacuna. | Incluir na T-02.01 uma entrada acima do limite, por exemplo `2 ** 53`: a chamada não lança erro e devolve `2 ** 53 + 1` (em aritmética de number). Acrescentar o mesmo caso à definição de pronto do ORQUESTRADOR.md. |
| BAIXA | sprint-02/tasks.md | O `teste_funcional` da T-02.02 cobre só `1n`, `'1'` e `new Number(1)`. `1n` não discrimina, porque `1n + 1` já lança `TypeError` nativo. Faltam `undefined`, `null` e `true`; uma validação por lista de tipos proibidos sem `Number.isInteger` deixaria `true` devolver `2`. | Acrescentar `undefined`, `null` e `true` às entradas do `teste_funcional` da T-02.02, cada uma lançando `TypeError`. |
| BAIXA | sprint-01/tasks.md | A T-01.01 não diz o que a função provisória faz. Nada impede o implementador de já escrever a regra completa, e os testes da sprint-02 nunca ficariam vermelhos. | Fixar no `objetivo` da T-01.01 o corpo provisório (por exemplo, `throw new Error('nao implementado')`) e proibir validação e incremento nessa task. |
| BAIXA | sprint-01/tasks.md | A T-01.01 e a D-04 não definem o formato do export de `src/proximo-numero.js` (função direto em `module.exports` ou objeto `{ proximoNumero }`); a FT-02 (PR-11) vai depender dessa escolha. | Fixar o formato na D-04 ou no `objetivo` da T-01.01, e fazer o `teste_integracao` comparar com a forma escolhida. |
| BAIXA | ORQUESTRADOR.md | A regra 4 manda pular para a próxima task paralelizável quando houver bloqueio, mas o plano não tem nenhuma; um bloqueio trava tudo o que vem depois, e isso não está escrito. | Dizer na seção 3 que, sem tasks paralelizáveis, um bloqueio encerra a execução até ser resolvido. |

## Revisão de testes por task

O agente `revisor-testes` **não foi disponibilizado pelo harness**: `.claude/agents/revisor-testes.md` existe, mas seu frontmatter é YAML inválido (`description` sem aspas contendo `: `), e o harness não o registra. Pela regra da skill ("quando o agente não existe no harness em uso, a fase roda como sempre rodou"), a revisão foi feita no contexto principal:

```
T-01.01 | solido | a identidade de referência entre src/index.js e src/proximo-numero.js falha se o index não reexportar ou embrulhar a função, e o objetivo da task é só a exposição
T-02.01 | solido | 41→42 derruba um retorno constante 1, -0→1 derruba rejeição via Object.is e MAX_SAFE_INTEGER+1 derruba um teto inventado
T-02.02 | solido | '1', 1n e new Number(1) derrubam coerção e checagem por instanceof, e a exigência de T-02.01 seguir verde derruba "lançar sempre"
T-02.03 | solido | -1 derruba checar só Number.isInteger, 1.5 derruba checar só >= 0, e NaN/±Infinity derrubam comparação ingênua
```

Divergência registrada: o `auditor-plano`, independente, apontou que T-02.01 não discrimina uma validação por `Number.isSafeInteger` (achado MÉDIA acima) — ponto que a revisão em contexto principal não pegou.

VEREDITO: SIM — o plano está pronto para execução autônoma.
