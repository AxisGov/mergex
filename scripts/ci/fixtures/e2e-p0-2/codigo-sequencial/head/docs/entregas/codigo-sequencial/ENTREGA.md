---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: codigo-sequencial
entregue_por: mergex
titulo: Codigo sequencial formatado proximoCodigo
tipo_trabalho: feature
tipo_ocorrencia: null
estado: aberto
versionado: true
branch: feature/codigo-sequencial
branch_base: buildx/p0-e2e-v2
commits:
  - task: T-01.01
    commit: 6ac7811
  - task: T-02.01
    commit: 1acae34
  - task: T-02.02
    commit: 3f9258f
  - task: T-02.03
    commit: 3e47565
modulo_afetado: [raiz, test]
arquivos_alterados: []
faixa_atencao:
  - arquivo: docs/entregas/codigo-sequencial/ENTREGA.md
    faixa: alta
  - arquivo: docs/sprintx/estimativas/HISTORICO.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/00-AUDITORIA.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/00-BLOQUEIOS.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/00-DECISOES.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/BUILDX-PREMISSAS.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/FECHAMENTO.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/ORQUESTRADOR.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/base/00-INDICE.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/base/00-LACUNAS.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/base/convencoes.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/base/modulo-principal-e-harness.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/base/proximo-numero.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/sprint-01/tasks.md
    faixa: alta
  - arquivo: docs/sprintx/features/codigo-sequencial/sprint-02/tasks.md
    faixa: alta
  - arquivo: src/index.js
    faixa: alta
  - arquivo: src/proximo-codigo.js
    faixa: alta
  - arquivo: test/proximo-codigo.test.js
    faixa: baixa
raio: null
atencao:
  olho_obrigatorio: 17
  leitura_rapida: 0
  dispensavel: 1
portao: pronto
desvios: []
push_feito: false
pr_url: null
pr_estado: null
criado_em: 2026-09-16
atualizado_em: 2026-09-16
entregue_em: null
---

# Entrega — Codigo sequencial formatado proximoCodigo

Entrega em aberto: execução da F6 da sprintx em andamento na branch `feature/codigo-sequencial`.

## Onde está o quê

| O quê | Onde |
|---|---|
| Descrição do pull request | [PR.md](PR.md) |
| Pacote de QA | [QA-PACOTE.md](QA-PACOTE.md) |
| Classificação da atenção | [ATENCAO.md](ATENCAO.md) |
| Trabalho de origem | [docs/sprintx/features/codigo-sequencial/](../../sprintx/features/codigo-sequencial/) |
| Pull request | não aberto |

## Estado da entrega

- Branch: feature/codigo-sequencial — adotada da skill de origem (aberta pela F1 da sprintx em worktree próprio)
- Base: buildx/p0-e2e-v2 — CONVENCOES.md (seção de versionamento, `Branch base`)
- Pasta do trabalho: canônica, `docs/sprintx/features/codigo-sequencial/`
- Portão de prontidão: PRONTO (V1–V3, V6, V7, V9, V10 OK; V4, V5, V8 n/a)
- Commits: 4, um por task (T-01.01 6ac7811, T-02.01 1acae34, T-02.02 3f9258f, T-02.03 3e47565)
- Commit de artefatos de método: não feito
- Atenção humana: 17 olho obrigatório, 0 leitura rápida, 1 dispensável (revisor-diff)
- Push: não feito
- Pull request: não aberto
- Falta para o merge: execução das tasks, portão, entrega e revisão humana

## Avisos

- E4: seções omitidas por falta de insumo — causa raiz (sem 01-CAUSA-RAIZ.md), raio, congelado e reversão (sem docs/legado/PERFIL.md), fora de escopo (sem DIVIDA.md).
- E5: sem roteiro manual (QA.md da runx); casos derivados dos criterio_aceite; entrega sem interface.
- E3: 15 artefatos de método em OLHO OBRIGATÓRIO pela regra do padrão.
- F5/F6: revisor-testes indisponível no harness (frontmatter YAML inválido); revisão de testes em fallback.
- F5: auditoria rodada 1 VEREDITO NÃO (ALTA em T-02.01), replanejamento F3→F4→F5, rodada 2 VEREDITO SIM.

## Desvios

Nenhum.
