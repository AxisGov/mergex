---
expx_schema: 1
expx_tool: sprintx
kind: entrega
trabalho_id: contador-sequencial
entregue_por: mergex
titulo: Contador sequencial proximoNumero
tipo_trabalho: feature
tipo_ocorrencia: null
estado: entregue
versionado: true
branch: feature/contador-sequencial
branch_base: buildx/p0-e2e-v2
commits:
  - task: T-01.01
    commit: 593ab77
  - task: T-02.01
    commit: 09d7ebd
  - task: T-02.02
    commit: 5be75d3
  - task: T-02.03
    commit: 97cdfd4
modulo_afetado: [raiz, test]
arquivos_alterados: [docs/entregas/contador-sequencial/ATENCAO.md, docs/entregas/contador-sequencial/ENTREGA.md, docs/entregas/contador-sequencial/PR.md, docs/entregas/contador-sequencial/QA-PACOTE.md, docs/sprintx/estimativas/HISTORICO.md, docs/sprintx/features/contador-sequencial/00-AUDITORIA.md, docs/sprintx/features/contador-sequencial/00-BLOQUEIOS.md, docs/sprintx/features/contador-sequencial/00-DECISOES.md, docs/sprintx/features/contador-sequencial/BUILDX-PREMISSAS.md, docs/sprintx/features/contador-sequencial/FECHAMENTO.md, docs/sprintx/features/contador-sequencial/ORQUESTRADOR.md, docs/sprintx/features/contador-sequencial/base/00-INDICE.md, docs/sprintx/features/contador-sequencial/base/00-LACUNAS.md, docs/sprintx/features/contador-sequencial/base/convencoes.md, docs/sprintx/features/contador-sequencial/base/harness-de-teste.md, docs/sprintx/features/contador-sequencial/base/modulo-principal.md, docs/sprintx/features/contador-sequencial/sprint-01/tasks.md, docs/sprintx/features/contador-sequencial/sprint-02/tasks.md, src/index.js, src/proximo-numero.js, test/proximo-numero.test.js]
faixa_atencao:
  - arquivo: docs/entregas/contador-sequencial/ENTREGA.md
    faixa: alta
  - arquivo: docs/sprintx/estimativas/HISTORICO.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/00-AUDITORIA.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/00-BLOQUEIOS.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/00-DECISOES.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/BUILDX-PREMISSAS.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/FECHAMENTO.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/ORQUESTRADOR.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/base/00-INDICE.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/base/00-LACUNAS.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/base/convencoes.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/base/harness-de-teste.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/base/modulo-principal.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/sprint-01/tasks.md
    faixa: alta
  - arquivo: docs/sprintx/features/contador-sequencial/sprint-02/tasks.md
    faixa: alta
  - arquivo: src/index.js
    faixa: alta
  - arquivo: src/proximo-numero.js
    faixa: alta
  - arquivo: test/proximo-numero.test.js
    faixa: baixa
raio: null
atencao:
  olho_obrigatorio: 17
  leitura_rapida: 0
  dispensavel: 1
portao: pronto
desvios: []
push_feito: true
pr_url: null
pr_estado: null
criado_em: 2026-09-16
atualizado_em: 2026-09-16
entregue_em: 2026-09-16
---

# Entrega — Contador sequencial proximoNumero

Entregue: `proximoNumero(valor)` em `src/proximo-numero.js`, reexportado por `src/index.js`, na branch `feature/contador-sequencial` publicada em `origin`.

## Onde está o quê

| O quê | Onde |
|---|---|
| Descrição do pull request | [PR.md](PR.md) |
| Pacote de QA | [QA-PACOTE.md](QA-PACOTE.md) |
| Classificação da atenção | [ATENCAO.md](ATENCAO.md) |
| Trabalho de origem | [docs/sprintx/features/contador-sequencial/](../../sprintx/features/contador-sequencial/) |
| Pull request | não aberto — descrição em [PR.md](PR.md) |

## Estado da entrega

- Branch: feature/contador-sequencial — adotada da skill de origem (aberta pela F1 da sprintx em worktree próprio)
- Base: buildx/p0-e2e-v2 — CONVENCOES.md (seção de versionamento, `Branch base`)
- Pasta do trabalho: canônica, `docs/sprintx/features/contador-sequencial/`
- Portão de prontidão: PRONTO (V1–V3, V6, V7, V9, V10 OK; V4, V5, V8 n/a)
- Commits: 4, um por task (T-01.01 593ab77, T-02.01 09d7ebd, T-02.02 5be75d3, T-02.03 97cdfd4)
- Commit de artefatos de método (pré-E6): 96d16e9 — FECHAMENTO.md, HISTORICO.md, ATENCAO.md, PR.md, QA-PACOTE.md e artefatos da feature
- Commit de fechamento final (E8): registrado na mensagem `chore(entrega): finalizar registro do trabalho contador-sequencial`
- Atenção humana: 17 olho obrigatório, 0 leitura rápida, 1 dispensável (revisor-diff)
- Push: feito — origin/feature/contador-sequencial
- Pull request: não aberto — remoto `origin` é repositório local, sem ferramenta de linha de comando de serviço de hospedagem
- Falta para o merge: abrir o PR de feature/contador-sequencial para buildx/p0-e2e-v2 com o conteúdo de PR.md, QA e revisão humana

## Avisos

- E4: seções omitidas por falta de insumo — causa raiz (trabalho da sprintx, sem 01-CAUSA-RAIZ.md), raio de impacto, congelado e reversão (sem modo legado, sem docs/legado/PERFIL.md), fora de escopo (sem DIVIDA.md).
- E5: sem roteiro de teste manual (QA.md da runx); casos derivados dos criterio_aceite das tasks. Entrega sem interface: casos observáveis só pela verificação automática no terminal.
- E3: 13 artefatos de método + FECHAMENTO.md e HISTORICO.md em OLHO OBRIGATÓRIO pela regra do padrão (nenhum critério de faixa cobre Markdown de método). PR.md, QA-PACOTE.md e ATENCAO.md gerados depois do E3, sem faixa.
- E3: revisor-testes indisponível no harness (frontmatter YAML inválido em .claude/agents/revisor-testes.md); revisão de testes da sprintx feita em fallback.
- E7: ferramenta de abertura de PR ausente para o remoto; PR não aberto, não é falha.

## Desvios

Nenhum.
