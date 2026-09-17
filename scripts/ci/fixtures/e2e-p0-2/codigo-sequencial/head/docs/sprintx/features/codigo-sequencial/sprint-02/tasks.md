---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
sprint_id: sprint-02
atualizado_em: 2026-09-16
sprint:
  titulo: Contrato de proximoCodigo
  status: concluido
  criterio_saida: npm test termina com 0 falhas com erro sentinela de proximoNumero chegando identico, reuso do numero devolvido por proximoNumero provado por duble, proximoCodigo(1) devolvendo SEQ-000002 e 999999 devolvendo SEQ-1000000
  riscos: [Duble via require.cache contamina outros testes se as entradas de src/proximo-numero.js e src/proximo-codigo.js nao forem apagadas ao fim, Formato de digitos so garantido ate Number.MAX_SAFE_INTEGER (PR-15, D-09)]
  fora_de_escopo: [Numeros acima de Number.MAX_SAFE_INTEGER (D-09), prefixo configuravel, mensagem propria de erro (D-08)]
fases:
  - id: F-02.1
    titulo: Propagacao, reuso e formato do codigo
    status: concluido
    criterio_saida: T-02.01, T-02.02 e T-02.03 concluidas com seus tres pares de testes passando em npm test
    paralelizavel: false
    paralela_com: []
    tasks: [T-02.01, T-02.02, T-02.03]
tasks:
  - id: T-02.01
    titulo: Propagacao do erro de proximoNumero sem reembrulho
    fase: F-02.1
    status: concluida
    objetivo: proximoCodigo chama proximoNumero(valor) sem validar a entrada nem capturar erro, de modo que o erro lancado por proximoNumero chega ao chamador como o mesmo objeto
    arquivos:
      cria: []
      altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
    teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com '1' e com -1, a chamada lanca TypeError com a mesma mensagem que proximoNumero lanca para a mesma entrada
    teste_funcional: Com o cache de src/proximo-codigo.js apagado e um duble de proximoNumero que lanca um objeto de erro sentinela instalado na entrada de src/proximo-numero.js do require.cache, proximoCodigo('1') lanca exatamente o sentinela e o duble recebe '1'
    criterio_aceite: Os dois testes da T-02.01 passam; ao fim do teste funcional as entradas de require.cache de src/proximo-numero.js e src/proximo-codigo.js sao apagadas e um novo require de src/proximo-codigo.js lanca TypeError para '1' com o proximoNumero real; os testes anteriores continuam passando em npm test
    depende_de: [T-01.01]
    paralelizavel: false
    concluida_em: 2026-09-16
    suite: verde
  - id: T-02.02
    titulo: Codigo SEQ- a partir do numero devolvido por proximoNumero
    fase: F-02.1
    status: concluida
    objetivo: proximoCodigo devolve SEQ- seguido do numero devolvido por proximoNumero(valor), sem incremento proprio
    arquivos:
      cria: []
      altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
    teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com 999999, o retorno e SEQ-1000000
    teste_funcional: Com o cache de src/proximo-codigo.js apagado e um duble de proximoNumero que devolve 1234567 instalado na entrada de src/proximo-numero.js do require.cache, proximoCodigo(5) devolve SEQ-1234567 e o duble e chamado uma vez com 5
    criterio_aceite: Os dois testes da T-02.02 passam; ao fim do teste funcional as entradas de require.cache de src/proximo-numero.js e src/proximo-codigo.js sao apagadas e um novo require de src/proximo-codigo.js devolve SEQ-1000000 para 999999 com o proximoNumero real; os testes anteriores continuam passando em npm test
    depende_de: [T-02.01]
    paralelizavel: false
    concluida_em: 2026-09-16
    suite: verde
  - id: T-02.03
    titulo: Zeros a esquerda ate 6 digitos sem truncar
    fase: F-02.1
    status: concluida
    objetivo: A parte numerica do codigo tem pelo menos 6 digitos com zeros a esquerda e numeros maiores entram inteiros
    arquivos:
      cria: []
      altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
    teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com 1, o retorno e SEQ-000002
    teste_funcional: Dadas as entradas 0, 41, 999999 e 1234567, os retornos sao SEQ-000001, SEQ-000042, SEQ-1000000 e SEQ-1234568
    criterio_aceite: Os dois testes da T-02.03 passam e os testes da T-02.01, T-02.02 e anteriores continuam passando em npm test
    depende_de: [T-02.02]
    paralelizavel: false
    concluida_em: 2026-09-16
    suite: verde
---

# Plano — Sprint 02 — Contrato de proximoCodigo

> Rodada 2 do plano (F3 depois da auditoria NÃO da rodada 1). Achado ALTA: propagação agora provada por erro sentinela idêntico (D-15), em task própria que nasce vermelha antes de `proximoCodigo` chamar `proximoNumero`. Achado MÉDIA: restauração do `require.cache` nomeia as duas entradas e é verificada por chamada real. BAIXA: procedimento do duble explícito (apagar o cache de `src/proximo-codigo.js` antes); testes prefixados `FT-02`.

## Objetivo da sprint

Implementar sob TDD `proximoCodigo(valor)` reutilizando `proximoNumero` (D-03, PR-11): erro de `proximoNumero` propagado como o mesmo objeto (D-08, D-15), prefixo `SEQ-` com o número devolvido por `proximoNumero` (D-05, D-11), zeros à esquerda até 6 dígitos (D-06) e sem truncar (D-07).

## Critério de saída da sprint

`npm test` termina com 0 falhas (suíte inteira), com o erro sentinela de `proximoNumero` chegando idêntico ao chamador, o reuso do número devolvido por `proximoNumero` provado por duble, `proximoCodigo(1)` devolvendo `SEQ-000002` e `proximoCodigo(999999)` devolvendo `SEQ-1000000`.

## Riscos conhecidos

- O duble via `require.cache` contamina outros testes se as entradas de `src/proximo-numero.js` e `src/proximo-codigo.js` não forem apagadas ao fim — os critérios de aceite da T-02.01 e da T-02.02 verificam a restauração por chamada real.
- Formato de dígitos só garantido até `Number.MAX_SAFE_INTEGER` (PR-15, D-09).

## Fora de escopo

- Números acima de `Number.MAX_SAFE_INTEGER` (D-09).
- Prefixo configurável (D-05).
- Mensagem própria de erro (D-08).

## Fase F-02.1 — Propagação, reuso e formato do código

**Objetivo:** cada task acrescenta um comportamento com teste vermelho antes: primeiro chamar `proximoNumero` sem capturar erro, depois usar o número devolvido, depois o padding.

**Tasks:** T-02.01, T-02.02, T-02.03

**Critério de saída:** T-02.01, T-02.02 e T-02.03 concluídas com seus três pares de testes passando em `npm test`.

**Roda em paralelo com:** nenhuma.

Procedimento do duble (T-02.01 e T-02.02): apagar `require.cache` de `src/proximo-codigo.js`; instalar o duble na entrada de `src/proximo-numero.js`; só então `require('../src/proximo-codigo.js')`; ao fim, em `finally`, apagar as duas entradas. Nomes dos testes prefixados com `FT-02` (D-15).

**Status da fase:** concluído em 2026-09-16.

## Portão da sprint — suíte inteira

Sprint concluída em 2026-09-16. Saída de `npm test`:

```
✔ FT-02 T-01.01 integracao: src/index.js reexporta proximoCodigo e mantem proximoNumero
✔ FT-02 T-01.01 funcional: proximoCodigo e funcao e o index continua objeto
✔ FT-02 T-02.01 integracao: '1' e -1 pelo index lancam TypeError com a mesma mensagem de proximoNumero
✔ FT-02 T-02.01 funcional: erro sentinela do duble de proximoNumero chega identico e o duble recebe '1'
✔ FT-02 T-02.02 integracao: proximoCodigo(999999) pelo index devolve SEQ-1000000
✔ FT-02 T-02.02 funcional: com duble de proximoNumero devolvendo 1234567, proximoCodigo(5) devolve SEQ-1234567 e o duble recebe 5 uma vez
✔ FT-02 T-02.03 integracao: proximoCodigo(1) pelo index devolve SEQ-000002
✔ FT-02 T-02.03 funcional: 0, 41, 999999 e 1234567 devolvem SEQ-000001, SEQ-000042, SEQ-1000000 e SEQ-1234568
✔ (9 testes anteriores da FT-01 e smoke)
ℹ tests 17
ℹ pass 17
ℹ fail 0
```

## Tasks

---

```yaml
id: T-02.01
titulo: Propagacao do erro de proximoNumero sem reembrulho
objetivo: proximoCodigo chama proximoNumero(valor) sem validar a entrada nem capturar erro, de modo que o erro lancado por proximoNumero chega ao chamador como o mesmo objeto
arquivos:
  cria: []
  altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com '1' e com -1, a chamada lanca TypeError com a mesma mensagem que proximoNumero lanca para a mesma entrada
teste_funcional: Com o cache de src/proximo-codigo.js apagado e um duble de proximoNumero que lanca um objeto de erro sentinela instalado na entrada de src/proximo-numero.js do require.cache, proximoCodigo('1') lanca exatamente o sentinela e o duble recebe '1'
criterio_aceite: Os dois testes da T-02.01 passam; ao fim do teste funcional as entradas de require.cache de src/proximo-numero.js e src/proximo-codigo.js sao apagadas e um novo require de src/proximo-codigo.js lanca TypeError para '1' com o proximoNumero real; os testes anteriores continuam passando em npm test
depende_de: [T-01.01]
paralelizavel: false
status: concluida
```

2026-09-16 · suíte: 13 passed, 0 failed (npm test, suíte inteira) · real: 0,2 h · sentinela é Error comum (não TypeError), para a checagem de restauração discriminar (achado BAIXA da rodada 2)

---

```yaml
id: T-02.02
titulo: Codigo SEQ- a partir do numero devolvido por proximoNumero
objetivo: proximoCodigo devolve SEQ- seguido do numero devolvido por proximoNumero(valor), sem incremento proprio
arquivos:
  cria: []
  altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com 999999, o retorno e SEQ-1000000
teste_funcional: Com o cache de src/proximo-codigo.js apagado e um duble de proximoNumero que devolve 1234567 instalado na entrada de src/proximo-numero.js do require.cache, proximoCodigo(5) devolve SEQ-1234567 e o duble e chamado uma vez com 5
criterio_aceite: Os dois testes da T-02.02 passam; ao fim do teste funcional as entradas de require.cache de src/proximo-numero.js e src/proximo-codigo.js sao apagadas e um novo require de src/proximo-codigo.js devolve SEQ-1000000 para 999999 com o proximoNumero real; os testes anteriores continuam passando em npm test
depende_de: [T-02.01]
paralelizavel: false
status: concluida
```

2026-09-16 · suíte: 15 passed, 0 failed (npm test, suíte inteira) · real: 0,1 h

---

```yaml
id: T-02.03
titulo: Zeros a esquerda ate 6 digitos sem truncar
objetivo: A parte numerica do codigo tem pelo menos 6 digitos com zeros a esquerda e numeros maiores entram inteiros
arquivos:
  cria: []
  altera: [src/proximo-codigo.js, test/proximo-codigo.test.js]
teste_integracao: Chamando proximoCodigo pelo objeto exportado de src/index.js com 1, o retorno e SEQ-000002
teste_funcional: Dadas as entradas 0, 41, 999999 e 1234567, os retornos sao SEQ-000001, SEQ-000042, SEQ-1000000 e SEQ-1234568
criterio_aceite: Os dois testes da T-02.03 passam e os testes da T-02.01, T-02.02 e anteriores continuam passando em npm test
depende_de: [T-02.02]
paralelizavel: false
status: concluida
```

2026-09-16 · suíte: 17 passed, 0 failed (npm test, suíte inteira) · real: 0,1 h
