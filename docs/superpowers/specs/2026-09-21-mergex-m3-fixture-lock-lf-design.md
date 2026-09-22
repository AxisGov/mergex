# MergeX M3 — Fixture, lock órfão e portabilidade LF

## Objetivo

Fechar as três pendências deliberadamente deixadas para M3: tornar determinística a fixture histórica de E8/HISTORICO, documentar a recuperação humana de uma trava C5 órfã e garantir que scripts shell sejam materializados em LF no Windows e em worktrees vinculadas.

## Estado de partida

- Branch: `p0.2/mergex-c7b`.
- HEAD: `9fdee99ea06c749a0e0756d409945b6a4336f32f`.
- `0cb0eae` é ancestral.
- Árvore limpa.
- `DM-168` é a última decisão.
- Os blobs `.sh` no índice já são LF; parte da worktree Windows aparece como CRLF porque não há política de checkout.

## Escopo

### Fixture histórica

O bloco de hooks que exercita seleção de trabalho, E8 e o HISTORICO será executado em repositório temporário próprio. Um helper de teste será responsável por:

- executar `git switch` e rejeitar imediatamente qualquer retorno não zero;
- conferir a branch resultante contra um valor literal esperado;
- restaurar somente paths tracked explicitamente informados entre cenários;
- nunca mascarar falha com `|| true`.

O JSON entregue aos hooks usará a raiz da fixture ativa, não uma raiz global fixa. Assim, o cenário do HISTORICO provará que está na branch SprintX esperada e que sujeira tracked anterior não atravessa a fronteira do caso.

### Semântica do HISTORICO

`docs/sprintx/estimativas/HISTORICO.md` permanece exceção exata da SprintX:

- não é desvio no hook de escopo;
- não concede isenção à RunX;
- é elegível no catálogo M2 apenas quando o diff é atribuível ao trabalho corrente;
- é persistido por `pre-e2`/lifecycle quando aplicável.

Nenhum schema de desvio ou código do lifecycle M2 será alterado por conveniência.

### Lock órfão

O contrato E1 ganhará um runbook humano canônico. A produção continuará sem `--force-unlock` e sem heurística de idade/PID. O procedimento parte de `trava-do-e1.sh --status`, confere o caminho exato, worktree, índice, task, pid e instante, prova a ausência de E1 vivo, inspeciona status e stage e só então permite remover exatamente aquela trava.

Stage não vazio interrompe a recuperação. Globs, remoção do diretório Git comum e automação da decisão são proibidos. O `--status` final e o stage vazio do próximo E1 continuam obrigatórios.

### Política LF

A raiz terá somente:

```gitattributes
*.sh text eol=lf
```

Não haverá regra nova para Markdown, YAML ou JSON, nem renormalização massiva. Antes do commit, `git add --renormalize -- '*.sh'` deve produzir diff vazio; qualquer diff real interrompe a entrega.

### Prova Windows e worktree

Uma suíte M3 criará um repositório-fonte temporário a partir do conteúdo corrente, fará clone limpo com `core.autocrlf=true` e criará worktree vinculada. Em ambos verificará:

- `git ls-files --eol -- '*.sh'` com `i/lf`, `w/lf` e `attr/text eol=lf`;
- ausência byte a byte de CRLF;
- shebang literal `#!/usr/bin/env bash`;
- `.git` diretório no checkout principal e arquivo na worktree vinculada.

## Testes e mutações

A suíte focada provará retorno do switch, branch resultante, isolamento de sujeira tracked, semântica do HISTORICO, persistência M2, lock conservador, clone autocrlf e worktree vinculada.

A matriz M3 terá controle verde e dez mutantes obrigatórios: retorno do switch ignorado; branch não conferida; sujeira tracked não restaurada; HISTORICO convertido em desvio; `.gitattributes` removido; política sem `eol=lf`; auto-remoção de lock velho; remoção com stage não vazio; glob no runbook; e teste sem inspeção de bytes CRLF.

## Compatibilidade e não escopo

- Não alterar SprintX ou BuildX.
- Não iniciar S1/S2.
- Não criar PR.
- Não mudar upstream, badges ou lifecycle M2 sem regressão real reproduzida.
- Validar Git Bash, container Linux com Bash+jq e WSL apenas se já disponível.
- Produzir um único commit final: `fix(mergex): endurece fixture e portabilidade`.
- Publicar somente em `origin/p0.2/mergex-c7b`, sem force.

## Decisões

- `DM-169`: scripts shell versionados são sempre LF; checkout Windows não altera o EOL executável.
- `DM-170`: trava órfã requer recuperação humana comprovada; a máquina nunca remove por idade ou heurística de PID.
