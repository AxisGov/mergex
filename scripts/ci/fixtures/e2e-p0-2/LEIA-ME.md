# Reprodução do E3 do segundo E2E real (buildx → sprintx → mergex)

Cópia dos insumos que a E3 classificou em `p0-integration-test-2`, extraída por `git show`.
A fixture original não foi alterada.

Por feature:

- `arquivos.txt` — os 18 arquivos que o `ATENCAO.md` real classificou. `ATENCAO.md`, `PR.md` e
  `QA-PACOTE.md` ficam de fora: no momento da E3 eles ainda não existiam.
- `head/` — cada arquivo no commit de artefatos pré-E6 (`96d16e9` e `de2fbf3`), o estado mais
  próximo do que a E3 leu.
- `base/` — o que já existia na base da feature (`base-sha.txt`).
- `sujo-no-e3.txt` — arquivos que ainda não estavam no último commit de task. A bancada os deixa
  fora do commit, como estavam na hora da E3.
- `evidencia.tsv` — os critérios que o agente confirmou antes de chamar o classificador:
  - arquivos de produto: os mesmos do `ATENCAO.md` real (O2, O5 e D1);
  - `00-DECISOES.md` e `BUILDX-PREMISSAS.md`: a avaliação de critério O que o contrato manda
    fazer na **origem** da decisão.
- `esperado.tsv` — faixa, critério e trecho do motivo que a política precisa produzir.

No `ATENCAO.md` real, 17 dos 18 arquivos de cada feature ficaram em OLHO OBRIGATÓRIO, e 15 deles
estavam lá só pelo padrão: nenhum critério descrevia artefato de método.
