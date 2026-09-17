---
expx_schema: 1
expx_tool: sprintx
kind: orquestrador
trabalho_id: codigo-sequencial
origem_buildx: p0-e2e-v2
feature_id: FT-02
titulo: Codigo sequencial formatado proximoCodigo
tipo_trabalho: feature
tipo_ocorrencia: null
estagio: f6
status: concluido
criado_em: 2026-09-16
atualizado_em: 2026-09-16
concluido_em: 2026-09-16
sprints: [sprint-01, sprint-02]
caminho_critico: [T-01.01, T-02.01, T-02.02, T-02.03]
modulo_afetado: [raiz, test]
arquivos_alterados: [src/index.js, src/proximo-codigo.js, test/proximo-codigo.test.js]
palavras_chave: [codigo, sequencial, proximocodigo, prefixo, zeros, reuso, typeerror]
worktree: ../p0-integration-test-2--codigo-sequencial
---

# Orquestrador — codigo-sequencial

> Porta de entrada da execução. Escrito para quem abriu o repositório agora e não sabe nada. Só caminhos relativos; nunca o valor de um segredo.

Branch do trabalho: feature/codigo-sequencial (base: buildx/p0-e2e-v2) — adotada em 2026-09-16 pela mergex

## 1. Objetivo

Entregar a função pública `proximoCodigo(valor)` (FT-02 do BuildX `p0-e2e-v2`), que depende da FT-01 já integrada.
Ela obtém o próximo número chamando `proximoNumero(valor)` — sem incremento próprio — e devolve `SEQ-` + pelo menos 6 dígitos com zeros à esquerda, sem truncar.
Entrada inválida propaga o `TypeError` de `proximoNumero`. Vive em `src/proximo-codigo.js`, reexportada por `src/index.js`.

## 2. Mapa e ordem de leitura

1. Este arquivo (`ORQUESTRADOR.md`)
2. `00-DECISOES.md` — decisões que governam o plano (D-00 a D-15; D-15 refina D-10)
3. `BUILDX-PREMISSAS.md` — premissa PR-15 assumida pelo BuildX
4. `base/00-INDICE.md` — e os arquivos da base que ele lista (`proximo-numero.md`, `modulo-principal-e-harness.md`, `convencoes.md`) e `base/00-LACUNAS.md`
5. `sprint-01/tasks.md` — sprint condensada (`kind: plano`)
6. `sprint-02/tasks.md` — sprint condensada (`kind: plano`)
7. `00-BLOQUEIOS.md` — bloqueios registrados durante a execução
8. `00-AUDITORIA.md` — achados MÉDIA/BAIXA que permanecem válidos (só existe depois da F5)

## 3. Rota de execução

- Sprint 01: F-01.1 (T-01.01)
- Sprint 02: F-02.1 (T-02.01 → T-02.02 → T-02.03)

Nenhuma fase nem task é paralelizável: todas escrevem em `src/proximo-codigo.js` e `test/proximo-codigo.test.js` e declaram `paralelizavel: false`. Sem task paralelizável, um bloqueio em qualquer task encerra a execução até ser resolvido.

**Caminho crítico:** T-01.01 → T-02.01 → T-02.02 → T-02.03

A integração em `buildx/p0-e2e-v2` por fast-forward (D-02) é do fluxo BuildX, depois da entrega; não é task deste plano.

## 4. Ferramentas

- **MCPs / SDKs:** nenhum além do Node.js (`node:test`, `node:assert/strict`)
- **Testes:** `npm test`
- **Lint:** NÃO EXISTE NO PROJETO
- **Typecheck:** NÃO EXISTE NO PROJETO
- **Segredos:** nenhum — o projeto não tem configuração nem variável de ambiente (`docs/stack/CONVENCOES.md`, D-12).

## 5. Agentes

- **Implementador** — escreve primeiro os dois testes da task, vê ambos falharem, implementa até passarem.
- **Revisor de testes** — antes de aceitar o verde, responde: este teste falharia com uma implementação errada? Se não, o teste volta. Quando o agente `revisor-testes` existir no harness, é ele quem responde.
- **Auditor de aceite** — verifica de fato o `criterio_aceite` da task antes de permitir `status: concluida`.

**Agente único:** assume os três papéis em sequência dentro de cada task, nesta ordem, tratando cada papel como um portão — não avança ao papel seguinte sem fechar o anterior.

## 6. Regras de autonomia

1. Não pergunte nada; não peça autorização para nada.
2. O teste vem antes do código, sempre.
3. Task só é `concluida` com teste de integração E funcional passando e `criterio_aceite` verificado. Não existe "concluído com ressalva".
4. Dúvida nova ou pré-requisito faltando: registrar em `00-BLOQUEIOS.md` (`B-NN | task | bloqueio | o que destravaria`), marcar a task `bloqueada`, pular para a próxima paralelizável. Nunca parar e esperar.
5. Só rode em paralelo o que o plano declarou paralelizável; a execução nunca decide paralelismo.
6. Atualize `status` em `tasks.md` a cada transição; ao concluir, acrescente data e resultado da suíte.
7. Critério de saída de fase/sprint não atendido = não avança.

## 7. Definição de pronto global

- `proximoCodigo(1)` devolve `SEQ-000002`; `0`, `41`, `999999` e `1234567` devolvem `SEQ-000001`, `SEQ-000042`, `SEQ-1000000` e `SEQ-1234568` (D-06, D-07).
- Com duble de `proximoNumero` devolvendo `1234567`, `proximoCodigo(5)` devolve `SEQ-1234567` e o duble recebe `5` — reuso provado, sem incremento próprio (D-03, D-11).
- Com duble de `proximoNumero` lançando um erro sentinela, `proximoCodigo('1')` lança exatamente o mesmo objeto; com o módulo real, `'1'` e `-1` lançam `TypeError` com a mesma mensagem de `proximoNumero` (D-08, D-15).
- Depois de cada teste com duble, o `require.cache` de `src/proximo-numero.js` e `src/proximo-codigo.js` volta ao módulo real, verificado por chamada.
- `src/index.js` continua objeto e expõe `proximoNumero` e `proximoCodigo` (D-04).
- As 4 tasks `concluida`, critérios de `sprint-01` e `sprint-02` atendidos, `npm test` (suíte inteira) com 0 falhas (D-14).

## 8. Como retomar uma sessão interrompida

1. Leia este arquivo inteiro.
2. Leia o `status` de cada task em cada `sprint-NN/tasks.md`.
3. Leia `00-BLOQUEIOS.md`.
4. Continue da primeira task `pendente` ou `em_andamento` cujas dependências (`depende_de`) estão todas `concluida`. Ignore as `bloqueada` até que o bloqueio registrado seja resolvido.
5. Trabalhe de dentro do worktree `../p0-integration-test-2--codigo-sequencial`, branch `feature/codigo-sequencial`.
