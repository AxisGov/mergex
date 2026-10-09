# MergeX — Reconciliação de base pós-E8 — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar à MergeX um caminho fechado e verificável para integrar uma base que avançou depois do E8: artefato de reconciliação com quatro provas recalculadas do Git, V9 executável por SHA, E3 obrigatório para reconciliados e portão vinculado a commit.

**Architecture:** Um executável novo (`reconciliacao-base.sh`) registra e verifica a reconciliação, apoiado numa biblioteca de artefato (`reconciliacao-artefato.sh`) que emite, lê, valida e assina `RECONCILIACAO-BASE-NNN.md`. A V9 passa a ser o executável `portao-v9.sh`, que compõe a união das tasks (exposta por `ownership-da-task.sh --uniao`) com os caminhos que a verificação da reconciliação declara cobertos. A validade do portão é o executável `validade-do-portao.sh --rev`. A barreira de push segue a DM-184 e tem três consumidores do mesmo validador, através da biblioteca de decisão por ref `portao-regras.sh`:
- o `pre-push` do Git (`portao-push.sh`), ativado pelo E0 e provado funcionalmente pelo E2 (`ativacao-pre-push.sh`): barreira local contra erro normal. O resultado do E2 só é gravado por `registrar-portao.sh`, que roda a prova antes de gravar `pronto`, e os checkpoints `pre-e6` e `e8` recusam persistir `pronto` sem a prova;
- o executável de CI (`portao-ci.sh`), com template de workflow: barreira contra contorno deliberado, nos limites da DM-185 (contra o `--no-verify` e o contorno pelo nome da branch, não contra todo contorno deliberado; spec, seção 15.1, itens 1 e 12), não ativada em produto nesta branch;
- o hook do Claude `pr-so-com-portao`, só consultivo.

O checkpoint `reconciliacao-base` entra no enum fechado de `contrato-de-commit.sh`, `catalogo-de-metodo.sh` e `persistir-metodo.sh`.

**Estado de execução (2026-10-08):** as Tasks 1–13 estão concluídas e aprovadas. A antiga Task 14 (hook `pr-so-com-portao` como fronteira, commits `92d5471`..`78fbb10`) não foi aprovada depois de cinco ciclos e foi superada pela DM-184. Ela fica no histórico, sem reescrita, e não conta como aprovação de nenhuma das Tasks 14–17 abaixo. As antigas Tasks 15–19 não foram iniciadas e passam a 18–22. A execução é subagent-driven, com implementador e revisor novos por task.

**Tech Stack:** Bash 3.2+, Git, awk, `sha256sum` ou `shasum -a 256`; `jq` só nos hooks (como hoje).

**Spec:** `docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md`

## Global Constraints

- Só a MergeX muda. SprintX, BuildX e ExpxDev não recebem nenhuma alteração nesta branch.
- Nenhum comando lê para gravar `tasks.md`, `sprint.md`, `fases.md` ou `00-PLANEJAMENTO.md`; o plano é só lido.
- Nenhum `seq` novo: `sequencia-de-commits.sh` nunca é chamado pelos scripts novos.
- Nenhuma flag de bypass (`--force`, `--sem-prova`, variável de ambiente que relaxe prova) em nenhum executável novo ou alterado.
- Toda prova é recalculada do Git; um caminho nunca é aceito só por estar listado no artefato.
- SHAs sempre completos (40 hex) nos artefatos e no `ENTREGA.md`; nunca nome de ref como prova.
- Códigos de saída de `reconciliacao-base.sh`: `0` ok, `2` trava C5 ocupada, `3` stage não vazio ou merge em andamento, `4` prova reprovada, `5` contrato inválido, `6` base indeterminável, `64` uso.
- Checkpoints de método: enum fechado `pre-e2 | reconciliacao-base | pre-e6 | e8`.
- O portão só continua válido depois de `portao_sha` com commits de um pai, `Metodo:` `pre-e6` ou `e8`, tocando só o catálogo daquele checkpoint. Qualquer commit de produto, teste, plano ou merge invalida.
- Portão `pronto` vencido, ausente, inconsistente ou ilegível, `historia_incompleta` e `erro_ambiente` barram o push no `pre-push` e reprovam no CI, em qualquer modo. `portao: null` segue o modo de `pr-so-com-portao` em `.expx/hooks.json`, interpretado igual pelos três consumidores.
- O `pre-push` e o CI decidem só pelo que o Git entrega (refs, SHAs, árvores). Nenhum executável da barreira trata texto de comando de shell como fronteira de segurança. O hook do Claude é só consultivo: na dúvida, avisa e sai 0.
- O E0 nunca altera `core.hooksPath` e nunca sobrescreve, renomeia ou edita um `pre-push` de terceiro. Aceitação de qualquer `pre-push` só por prova funcional, nunca por busca textual.
- Nenhum arquivo em `.github/workflows/`: esta branch entrega o template de CI e não ativa CI em lugar nenhum.
- Testes que dependem de Git for Windows sobre `\\wsl.localhost\...` imprimem `NAO_EXECUTADO: <motivo>` quando o ambiente não os tem, e esses casos nunca contam como aprovados.
- Toda linha que implementa uma guarda listada nos mutantes termina com o comentário `# guarda:<ID>`; os mutantes trocam essas linhas pelo identificador.
- Commits pequenos, um por task, no formato do repositório (`test(mergex):`, `fix(mergex):`, `docs(mergex):`), sem push.
- Nenhum caminho absoluto nem estado de máquina nos arquivos versionados.

## Review Focus

1. **Caminho com espaço, acento ou aspas** entre os reconciliados — o registro grava, a verificação cobre e a V9 aceita exatamente aquele caminho, sem `core.quotepath` escapar nomes. Teste na Task 5 (`caminho com espaço e acento`).
2. **Entrega legada com `portao: pronto` e sem `portao_sha`** — o push real é barrado pelo `pre-push`, com instrução de rodar o E2 de novo, nunca liberado. Teste na Task 14 (`pronto legado sem portao_sha barra`).
3. **Ref local da base parada enquanto a remota avançou** — a V9 dá o mesmo resultado, porque usa o SHA validado, não o nome. Teste na Task 11 (`ref local desatualizada`).
4. **Conflito resolvido pegando o lado da base inteiro para um arquivo** — sem diferença `B1..M`, o arquivo não pode ser reconciliado (prova 4) e também não aparece na V9. Teste na Task 5 (`resolução igual à base`).
5. **Produto rodando numa worktree vinculada** (`.git` é arquivo) — registro, trava C5, checkpoint e `pre-push` funcionam igual. Teste na Task 20 (`fluxo na worktree vinculada`) e na Task 15 (`ativação em worktree vinculada`).
6. **Push com várias refs** — uma ref aplicável inválida barra o push inteiro, mesmo depois de uma válida. Teste na Task 14 (`duas refs, a segunda inválida, barra o push inteiro`).
7. **SHA enviado diferente do `HEAD`** — o `pre-push` avalia o SHA enviado, não o checkout. Teste na Task 14 (`push de commit anterior ao HEAD valida o SHA enviado`).
8. **Hook de terceiro composto corretamente** — depois de composto à mão, passa na prova funcional e vira integração externa válida. Teste na Task 15 (`hook de terceiro composto passa na prova`).
9. **Hook que só cita a MergeX** — sem executá-la, reprova a prova. Teste na Task 15 (`hook que só cita a MergeX reprova`).
10. **Git for Windows sobre `\\wsl.localhost\...`** — o hook do Claude avisa e não bloqueia push legítimo; o `pre-push` decide. Teste na Task 17 (`git for windows sobre UNC: aviso sem bloqueio`), que imprime `NAO_EXECUTADO` sem o ambiente.
11. **Clone raso ou objeto ausente** — `historia_incompleta` e push barrado, com diagnóstico próprio. Teste na Task 14 (`clone raso barra com historia_incompleta` e `objeto ausente é historia_incompleta`).
12. **`--no-verify`** — o hook do Claude bloqueia o reconhecido com certeza; o CI é a barreira contra o contorno. Teste na Task 17 (`--no-verify reconhecido bloqueia`) e na Task 16 (`ci reprova o SHA que o pre-push barraria`).
13. **`portao: null` nos modos existentes** — `pre-push`, CI e hook dão o mesmo resultado em `bloqueio`, `aviso` e `desligado`. Teste na Task 17 (`null nos três modos: consumidores iguais`).
14. **E2 sem `pre-push` funcional** — nem a saída `PRONTO` nem a sua gravação ou persistência acontecem; o teste invoca os entrypoints executáveis reais (`registrar-portao.sh` e `persistir-metodo.sh --checkpoint pre-e6`/`e8`), e o contrato exige as chamadas nos comandos em prosa. Teste na Task 15 (`E2 sem pre-push funcional não emite nem grava PRONTO` e `pre-e6 recusa persistir pronto sem pre-push funcional`).

---

### Task 1: Fixture Git real e reprodução do cenário

**Files:**
- Create: `scripts/ci/lib/fixture-reconciliacao.sh`
- Create: `scripts/ci/test-r1-reconciliacao-base.sh`

**Interfaces:**
- Consumes: `fixture_switch_exato` de `scripts/ci/lib/fixture-git.sh`.
- Produces:
  - `fx_cenario <dir> [legado]` — monta o cenário inteiro num repositório novo e exporta `FX_B0 FX_P1 FX_B1 FX_M` (SHAs de 40 hex), `FX_TRAB=ft-rec`, `FX_ENTREGA=docs/entregas/ft-rec/ENTREGA.md`, `FX_NOVO1=tests/ui/compliance-ksmv-primitives.test.tsx`, `FX_NOVO2=tests/ui/attendance-ksmv-primitives.test.tsx`. Com `legado`, o `ENTREGA.md` não tem `base_validada_sha`, `origem_base`, `reconciliacoes` nem `portao_sha`.
  - `fx_merge_sem_commit <dir>` — mesmo cenário, parando com o merge resolvido no índice e sem commit (para os casos de merge em andamento).
  - Na suíte: `ok`, `falha`, `afirma <desc> <cmd...>` (exige rc 0), `rc_igual <desc> <rc> <cmd...>`, e o despacho por grupo `bash scripts/ci/test-r1-reconciliacao-base.sh <grupo>...|todos`.
  - Na suíte, os caminhos dos executáveis, sobrescrevíveis por variável de ambiente como em `test-portao-v11.sh`: `S="$REPO/.claude/skills/mergex/scripts"`, `RB="$S/reconciliacao-base.sh"`, `V9="$S/portao-v9.sh"`, `VALIDADE="$S/validade-do-portao.sh"`, `CONTRATO="$S/contrato-de-commit.sh"`, `SEQ="$S/sequencia-de-commits.sh"`, `CAUSA="$S/causa-do-portao.sh"`, `PROVA="$S/prova-de-commit.sh"`, `TRAVA="$S/trava-do-e1.sh"`.

O cenário: `main` com `src/painel.ts`; branch `feature/ft-rec` com o plano (`T-01.01` concluída, `altera: [src/painel.ts]`, `cria: [tests/ui/ft-rec.test.ts]`), o commit E1 da task, o `ENTREGA.md` entregue com `seq: 1`, `portao: pronto` e o commit `pre-e2`/`e8` de método; a `main` avança criando `FX_NOVO1`/`FX_NOVO2` e alterando a mesma linha de `src/painel.ts`; merge com conflito em `src/painel.ts`, resolução combinando os dois lados e os dois testes novos ajustados; commit `M` com `Trabalho: ft-rec` e `Integra-base: <FX_B1>`.

- [ ] **Step 1: Escrever o grupo `reproducao` (RED)**

```bash
grupo_reproducao() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  fx_cenario "$d" || { falha "cenário não montou"; return; }
  cd "$d" || return
  [ "$(git rev-parse "$FX_M^1")" = "$FX_P1" ] && ok "M^1 é P1" || falha "M^1 diferente de P1"
  [ "$(git rev-parse "$FX_M^2")" = "$FX_B1" ] && ok "M^2 é B1" || falha "M^2 diferente de B1"
  for f in "$FX_NOVO1" "$FX_NOVO2"; do
    [ "$(git diff --no-renames --name-status "$FX_B0" "$FX_B1" -- "$f" | cut -f1)" = A ] \
      && ok "$f nasceu na base" || falha "$f não nasceu na base"
    git diff --quiet "$FX_B1" "$FX_M" -- "$f" && falha "$f sem ajuste no merge" || ok "$f ajustado no merge"
    git diff --name-only "$FX_B1...HEAD" | grep -Fxq "$f" \
      && ok "$f aparece no diff da V9 (defeito)" || falha "$f não aparece no diff da V9"
  done
  cd "$REPO" || return
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh reproducao`
Expected: FAIL com `fixture ausente`.

- [ ] **Step 3: Implementar a fixture**

`fixture-reconciliacao.sh` cria o repositório com `git init -q -b main`, `user.email teste@expx.local`, `core.autocrlf false`, `core.quotepath false`, e usa somente comandos Git reais (`merge --no-ff --no-commit`, `commit -F`). Nenhum SHA é fixo: tudo é lido com `git rev-parse` depois de cada commit. A mensagem de `M` é escrita num arquivo temporário com os dois trailers.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh reproducao`
Expected: `N ok, 0 falha(s)` e rc 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "test(mergex): reproduz base que avanca depois do e8"
```

### Task 2: União executável das tasks

**Files:**
- Modify: `.claude/skills/mergex/scripts/ownership-da-task.sh`
- Test: `scripts/ci/test-ownership-task.sh`

**Interfaces:**
- Consumes: as funções internas `contexto` e `plano` do próprio script.
- Produces: `ownership-da-task.sh --uniao <raiz> <origem> <trabalho>` → um caminho por linha, `sort -u`, união de `cria`+`altera` de todas as tasks do plano corrente; rc `0`, ou `1` com `motivo=` no stderr quando o plano está ausente ou ilegível (mesmos motivos de `--classificar`).

- [ ] **Step 1: Escrever o teste (RED)**

O caso monta o próprio plano em `$D`: `T-01.01` com `cria: [src/a.ts]` e `altera: [tests/a.test.ts]`; `T-01.02` com `cria: [src/b.ts]` e `altera: [src/a.ts]` (o repetido prova o `sort -u`).

```bash
saida="$(bash "$SCRIPT" --uniao "$D" sprintx ft-teste)"; rc=$?
[ "$rc" = 0 ] && [ "$saida" = "$(printf 'src/a.ts\nsrc/b.ts\ntests/a.test.ts')" ] \
  && ok "--uniao devolve a união ordenada" || falha "--uniao: rc=$rc saída=$saida"
bash "$SCRIPT" --uniao "$D" sprintx ft-inexistente >/dev/null 2>&1
[ $? = 1 ] && ok "--uniao sem plano falha fechado" || falha "--uniao sem plano não falhou"
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-ownership-task.sh`
Expected: FAIL nos dois casos novos (`ação desconhecida: --uniao`).

- [ ] **Step 3: Implementar**

Acrescentar o ramo `--uniao` ao despacho: chama `contexto` e `plano` exatamente como `--classificar` e imprime `printf '%s\n' "$PLANO" | cut -f2 | sort -u`. A classificação unitária do E1 não muda (DM-152).

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-ownership-task.sh`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/ownership-da-task.sh scripts/ci/test-ownership-task.sh
git commit -m "feat(mergex): expoe a uniao das tasks para a v9"
```

### Task 3: Classe de commit de integração da base

**Files:**
- Modify: `.claude/skills/mergex/scripts/contrato-de-commit.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `contrato`)

**Interfaces:**
- Produces: `contrato-de-commit.sh --validar-integracao --trabalho <id> (--arquivo <msg> | --commit <sha>)` → stdout `classe=integracao_base` e `b1=<sha40>`; rc `0`, `2` contrato inválido, `64` uso. Com `--commit`, exige exatamente dois pais e `<commit>^2` igual ao `Integra-base:`.

- [ ] **Step 1: Escrever o grupo `contrato` (RED)**

```bash
grupo_contrato() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  rc_igual "M válido é integração" 0 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M"
  [ "$(bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_M" | sed -n 's/^b1=//p')" = "$FX_B1" ] \
    && ok "b1 é o segundo pai" || falha "b1 divergente"
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\nTask: T-01.01\n' "$FX_B1" > m1
  rc_igual "Task junto com Integra-base reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m1
  printf 'x\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$(git rev-parse --short "$FX_B1")" > m2
  rc_igual "SHA abreviado reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo m2
  rc_igual "commit de um pai reprova" 2 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --commit "$FX_P1"
  rc_igual "checkpoint reconciliacao-base é método válido" 0 bash "$CONTRATO" --validar-metodo \
    --trabalho ft-rec --checkpoint reconciliacao-base --arquivo "$REPO/scripts/ci/fixtures/r1/metodo-reconciliacao.txt"
  cd "$REPO" || return
}
```

Criar `scripts/ci/fixtures/r1/metodo-reconciliacao.txt` com o corpo de checkpoint da spec (seção 9).

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh contrato`
Expected: FAIL com `ação desconhecida: --validar-integracao` e `checkpoint inválido: reconciliacao-base`.

- [ ] **Step 3: Implementar**

Em `contrato-de-commit.sh`: ramo `--validar-integracao` (zero `Task:`, zero `Metodo:`, um `Trabalho:` igual ao contexto, um `Integra-base:` de 40 hex minúsculo; com `--commit`, `git rev-list --parents -n1` com exatamente três campos e o terceiro igual ao valor); e `reconciliacao-base` no `case` do `--validar-metodo`. As linhas das três checagens de integração terminam com `# guarda:INT`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh contrato && bash scripts/ci/test-m2-lifecycle-recuperacao.sh grammar`
Expected: ambos rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/contrato-de-commit.sh scripts/ci/test-r1-reconciliacao-base.sh scripts/ci/fixtures/r1
git commit -m "feat(mergex): reconhece o commit de integracao da base"
```

### Task 4: Artefato `RECONCILIACAO-BASE-NNN.md`

**Files:**
- Create: `.claude/skills/mergex/scripts/reconciliacao-artefato.sh` (biblioteca, carregada com `.`)
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `artefato`)

**Interfaces:**
- Produces (todas retornam 0/1 e preenchem `RB_ERRO` em falha):
  - `rb_sha256` — sha256 de stdin, por `sha256sum` ou `shasum -a 256`; sem nenhum dos dois, retorna 1.
  - `rb_diff_sha <b1> <m> <caminho>` — sha256 de `git diff --no-ext-diff --no-color --binary --no-renames <b1> <m> -- <caminho>`.
  - `rb_emitir <saida> <tsv-escalares> <tsv-arquivos>` — grava o arquivo com frontmatter na ordem da spec (seção 7.1), caminhos e `motivo` como escalares YAML entre aspas duplas com `\` e `"` escapados, prosa da seção 7.3, e `assinatura` calculada.
  - `rb_ler <arquivo>` — imprime `escalar\t<chave>\t<valor>` e `arquivo\t<caminho>\t<status_base>\t<blob_b1>\t<blob_m>\t<diff_sha>\t<motivo>`.
  - `rb_assinatura <arquivo>` — sha256 das linhas canônicas da spec (seção 7.1).
  - `rb_validar <arquivo> <trabalho> <numero esperado>` — schema: chaves todas presentes, enums, SHAs de 40 hex, `numero` igual ao `NNN` do nome, `anterior` nulo só no 001, `motivo` não vazio e sem `{{`, assinatura recalculada igual (`# guarda:ASS`).

- [ ] **Step 1: Escrever o grupo `artefato` (RED)**

```bash
grupo_artefato() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"
  . "$REPO/.claude/skills/mergex/scripts/reconciliacao-artefato.sh" || { falha "biblioteca ausente"; return; }
  rb_emitir "$d/RECONCILIACAO-BASE-001.md" "$REPO/scripts/ci/fixtures/r1/escalares-001.tsv" \
    "$REPO/scripts/ci/fixtures/r1/arquivos-001.tsv" && ok "emite" || falha "emitir: $RB_ERRO"
  rb_validar "$d/RECONCILIACAO-BASE-001.md" ft-rec 1 && ok "valida o que emitiu" || falha "validar: $RB_ERRO"
  [ "$(rb_ler "$d/RECONCILIACAO-BASE-001.md" | grep -c '^arquivo	')" = 2 ] && ok "lê os dois arquivos" || falha "leitura"
  sed -i 's/numero: 1/numero: 2/' "$d/RECONCILIACAO-BASE-001.md"
  rb_validar "$d/RECONCILIACAO-BASE-001.md" ft-rec 1 && falha "edição manual passou" || ok "edição manual quebra assinatura"
  for chave in b0_sha motivo assinatura estado; do
    rb_emitir "$d/x.md" "$REPO/scripts/ci/fixtures/r1/escalares-001.tsv" "$REPO/scripts/ci/fixtures/r1/arquivos-001.tsv"
    grep -v "^ *$chave:" "$d/x.md" > "$d/y.md"
    rb_validar "$d/y.md" ft-rec 1 && falha "sem $chave passou" || ok "sem $chave reprova"
  done
  ( PATH="$d/vazio"; mkdir -p "$d/vazio"; printf x | rb_sha256 ) >/dev/null 2>&1 \
    && falha "sem ferramenta de hash passou" || ok "sem ferramenta de hash falha fechado"
}
```

`scripts/ci/fixtures/r1/escalares-001.tsv` e `arquivos-001.tsv` usam SHAs sintéticos de 40 hex e incluem o caminho `tests/ui/caso com espaço e ação.test.tsx` (Review Focus 1).

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh artefato`
Expected: FAIL com `biblioteca ausente`.

- [ ] **Step 3: Implementar a biblioteca**

Somente as funções da interface; leitura por awk sobre o frontmatter, no estilo de `catalogo_fm`; sem `jq`, sem arrays associativos. A partir desta task, a suíte carrega a biblioteca no topo (`. "$S/reconciliacao-artefato.sh"`), e as tasks seguintes usam `rb_sha256` nos testes.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh artefato`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-artefato.sh scripts/ci/test-r1-reconciliacao-base.sh scripts/ci/fixtures/r1
git commit -m "feat(mergex): define o artefato de reconciliacao de base"
```

### Task 5: `--registrar` — estrutura, quatro provas e inventário

**Files:**
- Create: `.claude/skills/mergex/scripts/reconciliacao-base.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `provas`)

**Interfaces:**
- Consumes: `rb_*` (Task 4), `ownership-da-task.sh --uniao` (Task 2), `contrato-de-commit.sh --validar-integracao` (Task 3), `catalogo_metodo` e `trava-do-e1.sh` existentes.
- Produces: `reconciliacao-base.sh --registrar --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id> -- <caminho>...` com `M = HEAD`; grava `docs/entregas/<id>/RECONCILIACAO-BASE-NNN.md` e imprime `registrado=<nome>`, `b0=`, `p1=`, `b1=`, `m=`. Nesta task, `B0` vem de `base_validada_sha` (cenário não legado).

Guardas, cada linha com `# guarda:<ID>`: dois pais e `M` na linha de primeiro pai de `HEAD` (`EST`); `B0` ancestral de `B1` e de `P1` (`EST`); prova 1 por `git diff --no-renames --name-status B0 B1 -- f` sem status `D` (`P1`, `P1D`); prova 2 por `git rev-list --first-parent P1 ^<início> -- f` vazio (`P2FP`); prova 3 contra `--uniao` e o catálogo (`P3`); prova 4 por `git diff --quiet --no-renames B1 M -- f` com `f` presente em `M` (`P4`); inventário `git diff --name-only --no-renames B1 M` contido em união ∪ catálogo ∪ lista (`INV`). Pré-condições: stage vazio e `MERGE_HEAD` ausente → rc 3; trava C5 pelo `trava-do-e1.sh`.

- [ ] **Step 1: Escrever o grupo `provas` (RED)**

```bash
grupo_provas() {
  local d r; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  rc_igual "registra os dois testes da base" 0 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  git restore -- docs; git clean -fdq docs
  rc_igual "inventário: falta um caminho alterado pelo merge" 4 "${r[@]}" "$FX_NOVO1"
  rc_igual "prova 3: caminho das tasks" 4 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" src/painel.ts
  rc_igual "prova 1: arquivo que a base não tocou" 4 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" README.md
  rc_igual "prova 2: arquivo tocado pela feature" 4 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2" tests/ui/ft-rec.test.ts
  cd "$REPO" || return
  for variante in base_removeu integracao_removeu renomeado resolucao_igual_base m_um_pai pais_trocados \
    fora_primeiro_pai m_sem_integra_base m_com_metodo; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d"; cd "$d" || return
    rc_igual "variante $variante reprova" 4 "${r[@]}" $FX_LISTA_VARIANTE
    cd "$REPO" || return
  done
  for variante in caminho_especial base_alterou; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d"; cd "$d" || return
    rc_igual "variante $variante registra" 0 "${r[@]}" $FX_LISTA_VARIANTE
    cd "$REPO" || return
  done
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_merge_sem_commit "$d"; cd "$d" || return
  rc_igual "merge em andamento" 3 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return
  d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  bash "$TRAVA" --adquirir teste-r1 >/dev/null
  rc_igual "trava C5 ocupada" 2 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  cd "$REPO" || return
}
```

A fixture ganha a variável `FX_VARIANTE` e exporta `FX_LISTA_VARIANTE` com os caminhos que o caso tenta registrar:

| Variante | O que monta | Registro |
|---|---|---|
| `base_removeu` | a base remove um arquivo e a integração o mantém | 4 |
| `integracao_removeu` | a integração remove um dos testes novos | 4 |
| `renomeado` | a base renomeia um arquivo; a lista traz o caminho antigo | 4 |
| `resolucao_igual_base` | `FX_NOVO2` resolvido com o lado da base inteiro (Review Focus 4) | 4 |
| `m_um_pai` | `M` é um commit comum | 4 |
| `pais_trocados` | merge feito a partir da base (`M^1` é a base) | 4 |
| `fora_primeiro_pai` | `M` está num ramo lateral de `HEAD` | 4 |
| `m_sem_integra_base` | mensagem de `M` sem `Integra-base:` | 4 |
| `m_com_metodo` | mensagem de `M` com `Metodo:` | 4 |
| `caminho_especial` | teste novo da base com espaço e acento no nome (Review Focus 1) | 0 |
| `base_alterou` | arquivo que já existia em `B0`, mudado pela base (`status_base: M`) e ajustado | 0 |

`trava-do-e1.sh --adquirir` é o modo já existente que o E1 usa; o caso não libera a trava, e o diretório temporário é descartado no fim.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh provas`
Expected: FAIL (`reconciliacao-base.sh: No such file`).

- [ ] **Step 3: Implementar o registro**

Despacho de argumentos no estilo de `persistir-metodo.sh` (`uso`, `para`, `encerrar` liberando a trava); recusa qualquer opção desconhecida com rc 64 (nunca aceita `--force`). Lista de caminhos lida NUL-safe a partir dos argumentos; comandos Git com `-c core.quotepath=false`. Grava o artefato com `rb_emitir` e `estado: ativa`. Ainda não toca o `ENTREGA.md`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh provas`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-base.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): registra reconciliacao com quatro provas"
```

### Task 6: `--registrar` — `ENTREGA.md`, base validada e reabertura

**Files:**
- Modify: `.claude/skills/mergex/scripts/reconciliacao-base.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `entrega`)

**Interfaces:**
- Consumes: `causa-do-portao.sh --validar` e `sequencia-de-commits.sh --validar` (só leitura, para conferir o resultado).
- Produces: depois do artefato, o `ENTREGA.md` fica com `base_validada_sha = b1`, `reconciliacoes` acrescida de `{numero, arquivo, b1_sha, m_sha}`, `estado: aberto`, `portao: null`, `portao_sha: null`, `falhas_portao: []`, `causa: null`, `push_feito: false`, `entregue_em: null`, `atualizado_em` do sistema; demais chaves intactas.

- [ ] **Step 1: Escrever o grupo `entrega` (RED)**

```bash
grupo_entrega() {
  local d antes_commits antes_tasks; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  antes_commits="$(bash "$SEQ" --ler "$FX_ENTREGA")"
  antes_tasks="$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)"
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  fm() { awk -v c="$1" 'NR>1&&/^---/{exit} index($0,c": ")==1{sub(/^[^:]*: */,"");print;exit}' "$FX_ENTREGA"; }
  [ "$(fm base_validada_sha)" = "$FX_B1" ] && ok "base validada avança para B1" || falha "base_validada_sha"
  [ "$(fm estado)" = aberto ] && [ "$(fm portao)" = null ] && [ "$(fm portao_sha)" = null ] \
    && ok "entrega reaberta e portão zerado" || falha "reabertura"
  [ "$(bash "$SEQ" --ler "$FX_ENTREGA")" = "$antes_commits" ] && ok "commits e seq intactos" || falha "seq mudou"
  [ "$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)" = "$antes_tasks" ] \
    && ok "tasks.md intactos" || falha "tasks.md mudou"
  rc_igual "causa-do-portao aceita a reabertura" 0 bash "$CAUSA" --validar "$FX_ENTREGA"
  cd "$REPO" || return
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh entrega`
Expected: FAIL em `base validada avança para B1` e `entrega reaberta`.

- [ ] **Step 3: Implementar**

Função `entrega_define <arquivo> <chave> <valor>` (substitui a linha da chave de topo no frontmatter ou a insere antes do `---` de fechamento) e `entrega_reconciliacoes <arquivo> <tsv>` (reescreve o bloco inteiro da lista). Gravação em temporário e `mv`. A chamada a qualquer escritor de `seq` não existe; a linha que monta a lista de chaves gravadas termina com `# guarda:SEQ`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh entrega && bash scripts/ci/test-causa-portao.sh`
Expected: ambos rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-base.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): reabre a entrega e avanca a base validada"
```

### Task 7: `--verificar`

**Files:**
- Modify: `.claude/skills/mergex/scripts/reconciliacao-base.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `verificar`)

**Interfaces:**
- Produces: `reconciliacao-base.sh --verificar --entrega <ENTREGA.md> --origem <...> --trabalho <id>` → só leitura; `ok=true` e `coberto\t<caminho>\t<NNN>` por caminho, ou `ok=false` e `motivo\t<código>\t<detalhe>`; rc 0, 4 (prova), 5 (contrato). Recalcula do Git, para toda a cadeia, estrutura e quatro provas; confere `rb_validar`, numeração, `anterior`, encadeamento `b0 = b1` anterior (`# guarda:CAD`) e, por caminho coberto, `git rev-parse HEAD:<caminho>` igual ao `blob_m` da reconciliação mais recente que o lista (`# guarda:BLOBM`).

- [ ] **Step 1: Escrever o grupo `verificar` (RED)**

```bash
grupo_verificar() {
  local d v; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  v=(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  rc_igual "verifica o registro" 0 "${v[@]}"
  [ "$("${v[@]}" | grep -c '^coberto	')" = 2 ] && ok "dois cobertos" || falha "cobertura"
  cp "$d/docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md" "$d/bak.md"
  fx_forja_artefato "$d" README.md   # reescreve o artefato listando README.md com assinatura recalculada
  rc_igual "artefato forjado com assinatura válida não passa: prova recalculada" 4 "${v[@]}"
  cp "$d/bak.md" "$d/docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md"
  echo "// depois de M" >> "$FX_NOVO1"; git commit -qam "mexe depois de M"
  rc_igual "reconciliado alterado depois de M deixa de estar coberto" 4 "${v[@]}"
  cd "$REPO" || return
}
```

`fx_forja_artefato` (fixture) usa `rb_emitir` para gerar um artefato coerente e assinado que lista um caminho inelegível.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh verificar`
Expected: FAIL (`ação desconhecida: --verificar`).

- [ ] **Step 3: Implementar**

Reaproveitar as mesmas funções de prova da Task 5 (uma implementação, chamada pelos dois modos); `--verificar` nunca grava e nunca adquire trava.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh verificar`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-base.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): verifica a cadeia de reconciliacao recalculando as provas"
```

### Task 8: `--merge <sha>` e cadeia de reconciliações

**Files:**
- Modify: `.claude/skills/mergex/scripts/reconciliacao-base.sh`
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `cadeia`)

**Interfaces:**
- Consumes: `--registrar` e `--verificar`.
- Produces: `--registrar ... --merge <sha>`: `M` informado, na linha de primeiro pai de `HEAD` e posterior à base validada; o `<início>` da prova 2 passa a ser o `M` da reconciliação anterior; o artefato anterior vira `estado: superada`; o novo tem `origem_base: reconciliacao_anterior` e `anterior` preenchido. Fixture produz `fx_segunda_base <dir> [ajusta]` → `FX_B2 FX_M2`.

- [ ] **Step 1: Escrever o grupo `cadeia` (RED)**

```bash
grupo_cadeia() {
  local d r; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; fx_segunda_base "$d"; cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  rc_igual "registra M1 com HEAD em M2" 0 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  rc_igual "registra M2 sem arquivos" 0 "${r[@]}" --merge "$FX_M2" --
  rc_igual "cadeia 001→002 verifica" 0 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  grep -q '^estado: superada' docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md && ok "001 superada" || falha "001 não superada"
  grep -q "^b0_sha: $FX_B1" docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md && ok "002 encadeia em B1" || falha "encadeamento"
  grep -q '^arquivos: \[\]' docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md && ok "002 com arquivos: []" || falha "lista vazia"
  rc_igual "registrar M1 de novo depois de M2 reprova" 5 "${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2"
  mv docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md docs/entregas/ft-rec/RECONCILIACAO-BASE-003.md
  rc_igual "lacuna na numeração reprova" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  mv docs/entregas/ft-rec/RECONCILIACAO-BASE-003.md docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  sed -i 's/^anterior: .*/anterior: null/' docs/entregas/ft-rec/RECONCILIACAO-BASE-002.md
  rc_igual "anterior errado reprova" 5 bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec
  cd "$REPO" || return
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh cadeia`
Expected: FAIL (`opção desconhecida: --merge`).

- [ ] **Step 3: Implementar**

Ordem obrigatória: um `--merge` só é aceito se `M^2` descende do `b1_sha` da última reconciliação (ou da base validada) e se `M` é o merge mais antigo ainda não registrado na linha de primeiro pai; caso contrário rc 5.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh cadeia`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-base.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): encadeia reconciliacoes e registra merge anterior"
```

### Task 9: Base legada inferida

**Files:**
- Modify: `.claude/skills/mergex/scripts/reconciliacao-base.sh`
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `legado`)

**Interfaces:**
- Produces: sem `base_validada_sha` no `ENTREGA.md`, o primeiro `--registrar` infere `B0 = git merge-base P1 B1`, grava `origem_base: inferida_legado` no `ENTREGA.md` e no `001`, e acrescenta as chaves novas ausentes. Rc 6, sem gravar nada, quando `git merge-base --all P1 B1` tem mais de um resultado (`# guarda:LEG2`), quando a linha de primeiro pai de `P1` desde o merge-base contém merge, ou quando o merge-base não é ancestral de `B1`. Com a chave já presente, nunca infere de novo.

- [ ] **Step 1: Escrever o grupo `legado` (RED)**

```bash
grupo_legado() {
  local d r; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d" legado; cd "$d" || return
  r=(bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec --)
  rc_igual "legado infere B0" 0 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
  grep -q '^origem_base: inferida_legado' "$FX_ENTREGA" && ok "origem_base gravada" || falha "origem_base"
  grep -q "^b0_sha: $FX_B0" docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md && ok "B0 inferido certo" || falha "B0"
  cd "$REPO" || return
  for variante in criss_cross merge_previo; do
    d="$(mktemp -d)"; TMPS="$TMPS $d"; FX_VARIANTE="$variante" fx_cenario "$d" legado; cd "$d" || return
    rc_igual "legado ambíguo ($variante) falha fechado" 6 "${r[@]}" "$FX_NOVO1" "$FX_NOVO2"
    git diff --quiet && ok "nada gravado ($variante)" || falha "gravou algo ($variante)"
    cd "$REPO" || return
  done
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh legado`
Expected: FAIL (`legado infere B0` com rc 5 por chave ausente).

- [ ] **Step 3: Implementar**

Função `base_do_registro` que devolve `B0` e a origem: chave presente → valor gravado; ausente → inferência com as três checagens; qualquer falha → rc 6 antes de qualquer escrita.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh legado`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/reconciliacao-base.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): infere uma unica vez a base de entrega legada"
```

### Task 10: Checkpoint `reconciliacao-base` e catálogo

**Files:**
- Modify: `.claude/skills/mergex/scripts/catalogo-de-metodo.sh`
- Modify: `.claude/skills/mergex/scripts/persistir-metodo.sh`
- Test: `scripts/ci/test-m2-lifecycle-recuperacao.sh` (grupos `catalog` e `lifecycle`)

**Interfaces:**
- Consumes: `contrato-de-commit.sh --validar-metodo --checkpoint reconciliacao-base` (Task 3).
- Produces:
  - `catalogo_metodo ... reconciliacao-base` → `docs/entregas/<id>/ENTREGA.md` e os `RECONCILIACAO-BASE-NNN.md` nomeados em `ENTREGA.reconciliacoes` (nomes literais, sem glob); `pre-e6` e `e8` passam a incluir também esses artefatos.
  - `catalogo_pasta_do_trabalho <raiz> <origem> <trabalho>` → a pasta resolvida (canônica, runx ou legada), extraída da lógica hoje inline em `persistir-metodo.sh`, que passa a chamá-la.
  - `persistir-metodo.sh --checkpoint reconciliacao-base` com o mesmo comportamento dos outros checkpoints (trava, stage vazio, segredo, sem commit vazio).

- [ ] **Step 1: Escrever os casos (RED)**

```bash
# grupo catalog
saida="$(catalogo_metodo "$D" sprintx ft-teste docs/sprintx/features/ft-teste reconciliacao-base)"
[ "$saida" = "$(printf 'docs/entregas/ft-teste/ENTREGA.md\ndocs/entregas/ft-teste/RECONCILIACAO-BASE-001.md')" ] \
  && ok "catálogo reconciliacao-base: só ENTREGA e artefatos" || falha "catálogo reconciliacao-base: $saida"
# grupo lifecycle
bash "$PERSISTIR" --persistir --entrega "$E" --origem sprintx --trabalho ft-teste --checkpoint reconciliacao-base
[ $? = 0 ] && [ "$(git log -1 --format=%B | git interpret-trailers --parse | grep -c '^Metodo: reconciliacao-base')" = 1 ] \
  && ok "checkpoint reconciliacao-base cria commit de método" || falha "checkpoint reconciliacao-base"
git show --name-only --format= HEAD | grep -qv '^docs/entregas/ft-teste/' && falha "commit levou produto" || ok "só artefatos de entrega"
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-m2-lifecycle-recuperacao.sh catalog lifecycle`
Expected: FAIL com `checkpoint desconhecido: reconciliacao-base`.

- [ ] **Step 3: Implementar**

Acrescentar o valor aos três `case` de checkpoint (catálogo, persistir, contrato já feito), o ramo do catálogo e a leitura de `reconciliacoes` do `ENTREGA.md`; extrair `catalogo_pasta_do_trabalho` sem mudar a resolução.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-m2-lifecycle-recuperacao.sh && bash scripts/ci/test-m4b-arvore-inteira.sh`
Expected: ambos rc 0 (a extração da pasta não muda nenhum caso existente).

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/catalogo-de-metodo.sh .claude/skills/mergex/scripts/persistir-metodo.sh scripts/ci/test-m2-lifecycle-recuperacao.sh
git commit -m "feat(mergex): checkpoint de metodo reconciliacao-base"
```

### Task 11: V9 executável

**Files:**
- Create: `.claude/skills/mergex/scripts/portao-v9.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `v9`)
- Test: `scripts/ci/test-portao-v11.sh` (caso do portão completo)

**Interfaces:**
- Consumes: `ownership-da-task.sh --uniao`, `catalogo_metodo`, `reconciliacao-base.sh --verificar`.
- Produces: `portao-v9.sh --verificar --entrega <ENTREGA.md> --origem <...> --trabalho <id>` → `base=<sha40>`, `origem_base=<registrada_e0|inferida_legado|reconciliacao|inferida_leitura>`, `resultado=ok|v9|v9_sem_prova`, e `fora_do_plano\t<caminho>` por desvio; rc 0 ok, 1 `v9`, 3 `v9_sem_prova`. Base: `b1_sha` da última reconciliação; senão `base_validada_sha`; senão (entrega legada sem reconciliação) `git merge-base HEAD <branch_base>` único, informado como `inferida_leitura` e nunca gravado (`# guarda:V9SHA`). Diff por `git diff --name-only --no-renames <base>...HEAD`.

- [ ] **Step 1: Escrever o grupo `v9` (RED)**

```bash
grupo_v9() {
  local d v; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  v=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  rc_igual "antes do registro: V9 reprova os dois" 1 "${v[@]}"
  [ "$("${v[@]}" | grep -c '^fora_do_plano	')" = 2 ] && ok "nomeia os dois" || falha "lista de desvios"
  bash "$RB" --registrar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec -- "$FX_NOVO1" "$FX_NOVO2" >/dev/null
  rc_igual "depois do registro: V9 aprova" 0 "${v[@]}"
  git branch -f main "$FX_B0"
  rc_igual "ref local desatualizada não muda o resultado" 0 "${v[@]}"
  echo x > extra.ts; git add extra.ts; git commit -qm "produto fora do plano"
  rc_igual "arquivo de produto fora do plano reprova" 1 "${v[@]}"
  cd "$REPO" || return
}
```

No `test-portao-v11.sh`, o caso do portão completo passa a calcular a V9 com `portao-v9.sh` e exigir `resultado=ok`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh v9`
Expected: FAIL (`portao-v9.sh: No such file`).

- [ ] **Step 3: Implementar**

Composição na ordem da spec (seção 10): união das tasks, isenções de método existentes (pasta do trabalho, `docs/entregas/<id>/`, `HISTORICO.md` só na SprintX), cobertos da verificação — esta só conta com `ok=true`; `ok=false` → `v9_sem_prova`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh v9 && bash scripts/ci/test-portao-v11.sh`
Expected: ambos rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/portao-v9.sh scripts/ci/test-r1-reconciliacao-base.sh scripts/ci/test-portao-v11.sh
git commit -m "feat(mergex): v9 executavel com base validada por sha"
```

### Task 12: E3 — `O10` para reconciliados

**Files:**
- Modify: `.claude/skills/mergex/scripts/classificar-atencao.sh`
- Modify: `.claude/skills/mergex/references/03-atencao-humana.md`
- Modify: `.claude/agents/revisor-diff.md`
- Modify: `.opencode/agent/revisor-diff.md`
- Test: `scripts/ci/test-atencao-metodo.sh`

**Interfaces:**
- Produces: `ORDEM='O1 O2 O3 O4 O5 O6 O7 O8 O9 O10 L1 L2 L3 L4 D1 D2 D3 D4 PADRAO'`; opção `--reconciliados <arquivo>` (um caminho por linha, tipicamente a coluna 2 das linhas `coberto` de `--verificar`); todo caminho da lista recebe `O10: arquivo reconciliado da base` e fica em OLHO OBRIGATÓRIO, sem importar as evidências L/D recebidas (`# guarda:O10`).

- [ ] **Step 1: Escrever os casos (RED)**

```bash
printf 'tests/ui/novo.test.tsx\n' > "$D/reconc.txt"
saida="$(printf 'tests/ui/novo.test.tsx\tD1: teste novo\n' | bash "$CLASSIF" --base main --reconciliados "$D/reconc.txt")"
case "$saida" in *"OLHO OBRIGATÓRIO"*"O10:"*) ok "reconciliado não desce de faixa" ;; *) falha "O10: $saida" ;; esac
[ "$(bash "$CLASSIF" --ordem)" = 'O1 O2 O3 O4 O5 O6 O7 O8 O9 O10 L1 L2 L3 L4 D1 D2 D3 D4 PADRAO' ] \
  && ok "ordem com O10" || falha "ordem"
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-atencao-metodo.sh`
Expected: FAIL (`opção desconhecida: --reconciliados`).

- [ ] **Step 3: Implementar**

Opção e injeção no script; tabela O da referência e dos dois prompts do `revisor-diff` com a linha `O10`, no mesmo texto, para o `validate-mergex-contract.sh` continuar achando a ordem igual nas três fontes.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-atencao-metodo.sh && bash scripts/ci/validate-mergex-contract.sh`
Expected: ambos rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/classificar-atencao.sh .claude/skills/mergex/references/03-atencao-humana.md .claude/agents/revisor-diff.md .opencode/agent/revisor-diff.md scripts/ci/test-atencao-metodo.sh
git commit -m "feat(mergex): reconciliado e olho obrigatorio no e3"
```

### Task 13: Validade do portão

**Files:**
- Create: `.claude/skills/mergex/scripts/validade-do-portao.sh`
- Test: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `portao`)

**Interfaces:**
- Consumes: `contrato-de-commit.sh --validar-metodo`, `catalogo_metodo`, `catalogo_pasta_do_trabalho`.
- Produces: `validade-do-portao.sh --verificar --entrega <ENTREGA.md>` → `ok=true` ou `ok=false`, `motivo=<portao_nao_pronto|portao_sha_ausente|portao_sha_nao_ancestral|commit_de_produto|commit_merge|metodo_fora_do_catalogo>`, `primeiro_commit=<sha40|->`; rc 0 ou 1; só leitura. Cada commit de `portao_sha..HEAD`: um pai (`# guarda:PTMERGE`), `--validar-metodo` com checkpoint `pre-e6` ou `e8`, e `git diff-tree --no-commit-id --name-only -r` contido no catálogo daquele checkpoint (`# guarda:PTPROD`).

- [ ] **Step 1: Escrever o grupo `portao` (RED)**

```bash
grupo_portao() {
  local d p; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  p=(bash "$VALIDADE" --verificar --entrega "$FX_ENTREGA")
  fx_portao_em "$d" "$FX_P1"            # grava portao: pronto e portao_sha = P1 no ENTREGA.md
  rc_igual "merge depois do portão invalida" 1 "${p[@]}"
  "${p[@]}" | grep -q '^motivo=commit_merge' && ok "motivo commit_merge" || falha "motivo"
  fx_portao_em "$d" HEAD; fx_commit_metodo "$d" pre-e6 docs/entregas/ft-rec/PR.md
  rc_igual "commit só de método pre-e6 mantém válido" 0 "${p[@]}"
  fx_commit_metodo "$d" e8 src/painel.ts
  rc_igual "commit Metodo: tocando produto invalida" 1 "${p[@]}"
  fx_portao_em "$d" HEAD; echo y >> "$FX_NOVO2"; git commit -qam "ajuste de teste"
  rc_igual "commit de teste invalida" 1 "${p[@]}"
  fx_portao_sem_sha "$d"
  rc_igual "pronto sem portao_sha invalida" 1 "${p[@]}"
  fx_portao_em "$d" "$(fx_commit_solto "$d")"   # commit em ramo próprio, fora da história de HEAD
  rc_igual "portao_sha não ancestral invalida" 1 "${p[@]}"
  cd "$REPO" || return
}
```

`fx_portao_em`, `fx_commit_metodo`, `fx_portao_sem_sha` e `fx_commit_solto` entram na fixture e commitam via `git commit -F` com os trailers corretos. `fx_commit_solto` cria um commit num ramo novo a partir de `B0`, imprime o SHA e volta para a branch do trabalho com `fixture_switch_exato`. `B1` não serve para esse caso: ele é ancestral de `HEAD` pelo segundo pai de `M`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh portao`
Expected: FAIL (`validade-do-portao.sh: No such file`).

- [ ] **Step 3: Implementar**

Iterar `git rev-list --reverse portao_sha..HEAD`, parando no primeiro commit que invalida; `portao_sha` precisa ser ancestral de `HEAD`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh portao`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex/scripts/validade-do-portao.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): vincula o portao ao sha avaliado"
```

### Task 14: Validador por revisão e protocolo `pre-push`

**Files:**
- Modify: `.claude/skills/mergex/scripts/validade-do-portao.sh` (objeto Git ausente passa a `historia_incompleta`)
- Create: `.claude/skills/mergex/scripts/portao-regras.sh` (biblioteca carregada com `.`, 100644)
- Create: `.claude/skills/mergex/scripts/portao-push.sh` (100644, chamado com `bash`)
- Create: `scripts/ci/test-r2-barreira-push.sh` (100755; grupos `prepush` nesta task, `ativacao` na 15, `ci` na 16, `modo` na 17)
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh` (`fx_remoto_bare`, `fx_push_real`)
- Modify: `scripts/ci/test-r1-reconciliacao-base.sh` (grupo `portao`: classificação de objeto ausente)

**Interfaces:**
- Consumes: `validade-do-portao.sh --verificar --entrega <E> [--rev <sha>]` (já existe, da implementação superada); `reconciliacao-base.sh --verificar --checkpoint reconciliacao-base` (Task 11); `persistir-metodo.sh --checkpoint reconciliacao-base` (Task 10); `reconciliacao-arvore.sh` (`arvore_ambiente_git`, `arvore_recusa_raso`); `fx_cenario`.
- Produces:
  - `validade-do-portao.sh`: contrato da spec, seção 13, item 4. Saída `ok=`, `motivo=`, `primeiro_commit=`, `aviso=`; códigos 0, 1 e 64. Objeto Git necessário ausente é `historia_incompleta` (`# guarda:VALOBJ`). Revisão que não é commit por outro motivo continua `erro_ambiente`.
  - `portao-regras.sh`, funções que retornam 0/1 e preenchem `PR_ERRO` em falha:
    - `pr_modo_null <raiz>`: imprime `bloqueio|aviso|desligado`, o modo de `pr-so-com-portao` em `.expx/hooks.json`; sem a chave, `aviso`, que é o padrão do repositório.
    - `pr_entrega_da_ref <raiz> <ref_remota> <sha_local> <sha_remoto>`: imprime o caminho do `ENTREGA.md` que declara `branch: <b>` para `refs/heads/<b>` na árvore do SHA enviado, do SHA remoto anterior ou da ponta local de `refs/heads/<b>`; nada quando a ref não é aplicável.
    - `pr_decide_ref <raiz> <ref_local> <sha_local> <ref_remota> <sha_remoto>`: imprime `decisao=<passa|avisa|barra>`, `motivo=<texto>` e `entrega=<caminho|->`. Exclusão (SHA local nulo), tag e ref não aplicável dão `passa`. Para ref aplicável, roda `validade-do-portao.sh --rev <sha_local>`: `ok=true` passa; `portao: null` segue `pr_modo_null`; todo o resto barra (`# guarda:PPMODO` na linha que impede o modo de afrouxar `pronto` inválido).
  - `portao-push.sh --pre-push <remoto> <url>`: lê da entrada padrão as linhas do protocolo `pre-push` e decide cada ref com `pr_decide_ref` sobre o SHA local da linha, nunca sobre o `HEAD` (`# guarda:PPSHA`). Barra o push inteiro se qualquer ref barrar (`# guarda:PPMULTI`). Diagnóstico em stderr, com `historia_incompleta` e `erro_ambiente` em textos distintos. Códigos: 0 libera, 1 barra, 64 uso. Com `MERGEX_PRE_PUSH_SINAL=<arquivo>` no ambiente, só acrescenta a linha `mergex-pre-push invocado <pid>` ao arquivo, sem mudar a decisão (é o sinal da prova funcional da Task 15). O custo é uma validade por ref aplicável, nenhuma varredura de branches.
  - Fixture: `fx_remoto_bare <dir>` cria `remoto.git` bare ao lado do cenário e exporta `FX_REMOTO`; `fx_push_real <dir> <args do git push>` roda `git push` real com o `pre-push` apontando para `portao-push.sh` (instalado por chamador mínimo da própria fixture, até a Task 15 trazer o oficial) e imprime `rc=<n>` e a ref remota resultante.

- [ ] **Step 1: Escrever o grupo `prepush` (RED)**

Casos, todos com push **real** contra `FX_REMOTO`, afirmando o rc do `git push` e o SHA da ref remota depois:
- `pronto válido passa`;
- `pronto vencido barra` (commit de produto depois do portão);
- `pronto legado sem portao_sha barra`;
- `ENTREGA ausente no SHA enviado barra` (a ref é aplicável pela ponta remota anterior);
- `ENTREGA ilegível barra` (frontmatter quebrado);
- `push de commit anterior ao HEAD valida o SHA enviado` (`git push origin <sha_valido>:feature/ft-rec`, com HEAD vencido: passa; e o inverso: barra);
- `duas refs, a segunda inválida, barra o push inteiro` (a ref remota da primeira não muda);
- `exclusão de branch passa` (`git push origin :feature/ft-rec`);
- `tag passa`;
- `ref fora da branch do trabalho passa`;
- `null nos três modos` (`bloqueio` barra, `aviso` passa com diagnóstico em stderr, `desligado` passa);
- `clone raso barra com historia_incompleta` (`git clone --depth 1 file://…`);
- `objeto ausente é historia_incompleta` (repositório com o objeto do `portao_sha` removido de `objects/`);
- `validador ausente é erro_ambiente e barra` (a cópia do `portao-push.sh` aponta para um validador inexistente);
- `push com cd, bash -c e link simbólico é decidido pelo pre-push` (os três comandos rodam `git push` real, e o resultado é o da validade, sem leitura de shell);
- `custo independe das branches entregues` (50 branches locais com `ENTREGA.md` próprio e só uma ref no push: no máximo uma chamada da validade, contada por um stub que registra as chamadas);
- `barreira: reconciliação registrada e não persistida dá persistencia` (`reconciliacao-base.sh --verificar --checkpoint reconciliacao-base` sai 5 com `motivo\tpersistencia`; depois do checkpoint, sai 0);
- `ordem: sem portão pronto o push segue o modo` (reconciliação persistida, `portao: null`: o push real segue `pr_modo_null`, porque o E2 ainda não autorizou);
- `ordem: commit reconciliacao-base depois do portão barra o push` (um novo checkpoint `reconciliacao-base` depois de `portao_sha` dá `commit_de_produto` na validade, e o push real é barrado);
- `ordem: o pre-push não reexecuta a reconciliação` (portão válido; um artefato não rastreado adulterado no disco não muda a decisão do push, que depende só da validade sobre o SHA enviado).

No grupo `portao` da suíte r1:
- `objeto ausente é historia_incompleta, não erro_ambiente`;
- `isenção por prefixo: .ts em docs/entregas depois do portão invalida` (commit `Metodo: pre-e6` criando `docs/entregas/ft-rec/x.ts` depois do portão: `metodo_fora_do_catalogo`). Fixa o risco residual 5 da spec.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r2-barreira-push.sh prepush; bash scripts/ci/test-r1-reconciliacao-base.sh portao`
Expected: FAIL. O `prepush` falha com `portao-push.sh: No such file`; o `portao` falha em `objeto ausente é historia_incompleta, não erro_ambiente`, porque hoje sai `erro_ambiente`. O caso de isenção por prefixo já passa, porque fixa um comportamento existente; ele não faz parte do RED e precisa matar o mutante PTPROD.

- [ ] **Step 3: Implementar**

`portao-regras.sh` com as três funções; `portao-push.sh` lendo a entrada padrão linha a linha; `validade-do-portao.sh` distinguindo, antes de concluir `erro_ambiente`, a falha por objeto ausente (`git cat-file -e` do objeto pedido falha num repositório Git legível). Ambiente Git fixado como nos outros executáveis (`arvore_ambiente_git`). Sem opção de força.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r2-barreira-push.sh prepush && bash scripts/ci/test-r1-reconciliacao-base.sh portao && bash scripts/ci/validate-mergex-contract.sh`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Revisão independente**

Revisor novo, com o diff da task e as seções 13 e 15 da spec. Foco: decisão só por refs e SHAs do Git; o modo nunca afrouxa `pronto` inválido; várias refs; objeto ausente contra ambiente; custo por ref.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/mergex/scripts/validade-do-portao.sh .claude/skills/mergex/scripts/portao-regras.sh .claude/skills/mergex/scripts/portao-push.sh scripts/ci/test-r2-barreira-push.sh scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "feat(mergex): pre-push decide pelas refs enviadas"
```

### Task 15: Ativação no E0 e prova funcional no E2

O E0 e o E2 não têm entrypoint executável próprio. São comandos em prosa que o agente segue:
- E0: `.claude/commands/mergex-abrir.md:5` e `.opencode/commands/mergex-abrir.md:5`, que mandam seguir `references/00-abertura.md`, e a linha E0 de `.claude/commands/mergex.md:17` e `.opencode/commands/mergex.md:17`.
- E2: `.claude/commands/mergex-check.md:5` e `.opencode/commands/mergex-check.md:5`, que mandam seguir `references/02-prontidao.md`, e a linha E2 de `.claude/commands/mergex.md:24` e `.opencode/commands/mergex.md:24`.

As verificações V1–V11 são aplicadas pelo agente com apoio de scripts (`persistir-metodo.sh --verificar --checkpoint pre-e2`, `portao-v9.sh`, `prova-de-commit.sh`). A decisão `PRONTO`/`BLOQUEADO` e a gravação de `portao: pronto` estão só em prosa, em `references/02-prontidao.md:271-273`.

Por isso esta task combina três camadas:
1. **Prosa dos entrypoints:** E0 chama `--instalar` e para quando falha; E2 chama `--provar` antes de V1.
2. **Teste de contrato:** exige essas chamadas nos entrypoints reais, na ordem.
3. **Enforcement executável:** não depende da obediência do agente.
   - Um gravador único do resultado do portão (`registrar-portao.sh`) roda a prova antes de gravar `pronto`.
   - Os checkpoints `pre-e6` e `e8` do `persistir-metodo.sh` recusam persistir `portao: pronto` sem a prova. Sem essa persistência, o `pronto` nunca chega ao SHA que o `pre-push` avalia.

**Files:**
- Create: `.claude/skills/mergex/scripts/ativacao-pre-push.sh` (100644)
- Create: `.claude/skills/mergex/scripts/registrar-portao.sh` (100644; único gravador de `portao`, `portao_sha`, `falhas_portao` e `atualizado_em` pelo E2)
- Create: `.claude/skills/mergex/assets/pre-push-gerenciado.sh` (modelo do chamador gerenciado, 100644; instalado com 100755)
- Create: `.claude/skills/mergex/references/12-barreira-de-push.md` (seções "Ativação", "Composição com hook de terceiro", "Prova funcional", "Reversão")
- Modify: `.claude/skills/mergex/scripts/persistir-metodo.sh` (checkpoints `pre-e6` e `e8`: recusa persistir `portao: pronto` sem prova funcional)
- Modify: `.claude/commands/mergex-abrir.md`, `.opencode/commands/mergex-abrir.md` (E0 chama `ativacao-pre-push.sh --instalar` e para quando falha)
- Modify: `.claude/commands/mergex-check.md`, `.opencode/commands/mergex-check.md` (E2 chama `ativacao-pre-push.sh --provar` antes de V1 e grava o resultado só por `registrar-portao.sh`)
- Modify: `.claude/commands/mergex.md`, `.opencode/commands/mergex.md` (linhas E0 e E2 do fluxo completo, com as mesmas chamadas)
- Modify: `.claude/skills/mergex/references/00-abertura.md` (passo novo depois de criar ou retomar o `ENTREGA.md`: `--instalar`; rc diferente de zero dá `mergex E0 BLOQUEADO — pre-push`, encerra o E0 e mostra a instrução de composição; o checklist final ganha o item do `pre-push` ativo)
- Modify: `.claude/skills/mergex/references/02-prontidao.md` (barreira inicial ganha `--provar` ao lado da `pre-e2`: falhou, o E2 não começa e nada é gravado; as linhas 271 e 273 passam a gravar só por `registrar-portao.sh`)
- Modify: `scripts/ci/validate-mergex-contract.sh` (asserções de contrato dos entrypoints)
- Modify: `scripts/ci/test-r2-barreira-push.sh` (grupos `ativacao` e `entrypoints`)
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh` (`fx_hook_terceiro`, `fx_worktree_vinculada`)

**Interfaces:**
- Consumes: `portao-push.sh --pre-push` e o sinal `MERGEX_PRE_PUSH_SINAL` (Task 14); `fx_cenario`.
- Produces (fixture): `fx_worktree_vinculada <dir>` cria uma worktree vinculada do cenário e exporta `FX_WT`; `fx_hook_terceiro <dir> <nao_composto|composto|so_cita|nao_propaga|libera|sinal>` grava um `pre-push` de terceiro na variante pedida. A Task 20 consome `fx_worktree_vinculada`.
- Produces: `ativacao-pre-push.sh <--instalar|--provar|--reverter> --entrega <ENTREGA.md>`:
  - `--instalar` (E0): resolve o diretório efetivo com `git rev-parse --git-path hooks` e nunca escreve `core.hooksPath` (`# guarda:ATVHP`). Sem `pre-push`, copia o modelo, que tem o marcador `# mergex: pre-push gerenciado`. Com o chamador gerenciado, nada muda. Com `pre-push` de terceiro, nunca escreve, renomeia nem edita o arquivo (`# guarda:ATVSOB`) e roda `--provar`: passando, aceita como integração externa válida; reprovando, sai com 3 e a instrução de composição.
  - `--provar` (E0 e E2): cria, sem tocar remoto nem ref, um commit solto (`git commit-tree`) sobre `HEAD` com um arquivo de produto e o `ENTREGA.md` em `portao: pronto` com `portao_sha` = `HEAD`, que é sabidamente vencido. Executa o `pre-push` efetivo como o Git o executaria (argumentos `prova-mergex file:///dev/null`, uma linha de protocolo para `refs/heads/<branch da entrega>`, `MERGEX_PRE_PUSH_SINAL` num temporário). Aprova só se o hook sair com código diferente de zero **e** o sinal registrar a execução do `portao-push.sh` (`# guarda:ATVTXT`). Término por sinal, código zero ou ausência do sinal reprovam.
  - `--reverter`: remove o arquivo só se tiver o marcador de gerenciado; diante de integração externa ou hook de terceiro, só informa e sai 0, sem tocar o arquivo.
  - Códigos: 0 ok; 1 prova reprovada; 3 pré-requisito ausente (hook de terceiro não composto); 64 uso. Sem opção de força.
- Produces: `registrar-portao.sh --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id> --resultado <pronto|bloqueado> [--falhas <vN>...]`:
  - Com `--resultado pronto`: roda `ativacao-pre-push.sh --provar` **antes** de qualquer escrita (`# guarda:E2SEMHOOK`). Reprovou: imprime `RESULTADO: BLOQUEADO — pre-push sem prova funcional`, não grava nada no `ENTREGA.md` e sai 3. Aprovou: grava `portao: pronto`, `portao_sha` = SHA de 40 hex do `HEAD`, `falhas_portao: []` e `atualizado_em`, pelo editor de frontmatter da Task 6, e imprime `RESULTADO: PRONTO`.
  - Com `--resultado bloqueado`: grava `portao: bloqueado` e `falhas_portao` pela forma de `causa-do-portao.sh --lista`; não exige a prova.
  - O resultado gravado passa em `causa-do-portao.sh --validar`. Códigos: 0 gravado; 3 prova ausente ou reprovada; 5 contrato inválido; 64 uso.
- Produces: em `persistir-metodo.sh --persistir` e `--verificar` com `--checkpoint pre-e6` ou `e8`: se o `ENTREGA.md` a persistir tem `portao: pronto`, roda `ativacao-pre-push.sh --provar` antes de commitar (`# guarda:E2SEMHOOK`). Reprovou: sai diferente de zero com `pre-push sem prova funcional`, sem commit e com o stage intacto. Os outros checkpoints não mudam.

- [ ] **Step 1: Escrever o grupo `ativacao` (RED)**

Casos:
- `instala sem pre-push e é idempotente` (segunda execução não muda o arquivo, comparado por hash e mtime);
- `core.hooksPath já configurado é respeitado e não muda` (relativo e absoluto; `git config --get core.hooksPath` igual antes e depois);
- `hook de terceiro não composto: E0 sai 3 e não toca o arquivo` (hash igual; a mensagem traz a instrução de composição);
- `hook de terceiro composto passa na prova` (variante que chama `portao-push.sh` e propaga o código de saída; o E0 sai 0);
- `hook que só cita a MergeX reprova` (variante que tem o caminho do validador num comentário e sai 1 por conta própria: sem o sinal, reprova);
- `hook composto que não propaga o código reprova` (chama a MergeX e sai 0);
- `hook composto que libera a ref inválida reprova`, `hook que termina por sinal reprova`;
- `prova funcional não toca remoto nem refs` (`git for-each-ref` e o remoto bare iguais antes e depois);
- `E2 sem prova aprovada não emite PRONTO` (o `--provar` sai 1 com o hook removido);
- `reversão remove só o chamador gerenciado` e `reversão preserva hook de terceiro e integração externa`;
- `ativação em worktree vinculada` (o diretório efetivo é o comum);
- `diretório com espaço e acento` (raiz do cenário e `core.hooksPath` com espaço, acento e apóstrofo);
- `git for windows: diretório efetivo sobre UNC` (com `git.exe` e `wslpath` disponíveis, resolve o diretório efetivo e roda `--provar` pelo Git Bash; sem eles, imprime `NAO_EXECUTADO: git for windows indisponível` e não conta como ok).

Grupo `entrypoints`. Invoca os entrypoints executáveis reais do E2 e da persistência, nunca só o script de ativação:
- `E2 sem pre-push funcional não emite nem grava PRONTO` (`registrar-portao.sh --resultado pronto` sem `pre-push`, com hook de terceiro não composto e com hook que só cita a MergeX: sai 3, a saída não contém `RESULTADO: PRONTO`, e o `ENTREGA.md` fica byte a byte igual);
- `E2 com chamador gerenciado grava PRONTO` (sai 0, `portao: pronto` e `portao_sha` = `HEAD` gravados, `causa-do-portao.sh --validar` aprova);
- `E2 com hook externo composto grava PRONTO`;
- `pre-e6 recusa persistir pronto sem pre-push funcional` (`portao: pronto` editado à mão no disco, `pre-push` removido: `persistir-metodo.sh --persistir --checkpoint pre-e6` sai diferente de zero, sem commit e com o stage intacto; o mesmo para `e8`);
- `pre-e6 persiste pronto com pre-push funcional` (gerenciado e externo composto);
- `BLOQUEADO não depende da prova` (`--resultado bloqueado` grava sem `pre-push`).

Em `validate-mergex-contract.sh`, asserções de contrato sobre os entrypoints em prosa:
- `mergex-abrir.md` (as duas cópias) e `00-abertura.md` citam `ativacao-pre-push.sh --instalar` e a parada `mergex E0 BLOQUEADO — pre-push`;
- `mergex-check.md` (as duas cópias) e `02-prontidao.md` citam `ativacao-pre-push.sh --provar` antes da primeira menção a `V1`;
- `02-prontidao.md` manda gravar o resultado só por `registrar-portao.sh` e não manda mais editar `portao: pronto` diretamente;
- `mergex.md` (as duas cópias) cita as duas chamadas nas linhas E0 e E2.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r2-barreira-push.sh ativacao entrypoints; bash scripts/ci/validate-mergex-contract.sh`
Expected: FAIL. `ativacao` e `entrypoints` falham com `ativacao-pre-push.sh: No such file` e `registrar-portao.sh: No such file`; o `validate-mergex-contract.sh` falha com `mergex-abrir sem ativacao-pre-push.sh --instalar`.

- [ ] **Step 3: Implementar**

O executável de ativação, o gravador `registrar-portao.sh`, a guarda nos checkpoints `pre-e6` e `e8` do `persistir-metodo.sh`, o modelo, o reference `12-barreira-de-push.md` e a prosa dos entrypoints listados em Files. A instrução de composição da mensagem de erro é a mesma do reference: o hook existente chama `portao-push.sh --pre-push "$@"`, repassa a entrada padrão e propaga exatamente o código de saída.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r2-barreira-push.sh ativacao entrypoints prepush && bash scripts/ci/validate-mergex-contract.sh && bash scripts/ci/test-m2-lifecycle-recuperacao.sh lifecycle && bash scripts/ci/test-causa-portao.sh`
Expected: todos `ok` (os casos `NAO_EXECUTADO`, se houver, listados à parte), rc 0. Os checkpoints sem `portao: pronto` se comportam como antes.

- [ ] **Step 5: Revisão independente**

Revisor novo, com o diff e a seção 13, item 6, da spec. Foco:
- nenhuma escrita em `core.hooksPath` nem em hook de terceiro;
- reconhecimento só por comportamento;
- prova sem efeito colateral em refs e remoto;
- reversão;
- nenhum caminho executável grava ou persiste `portao: pronto` sem a prova;
- os entrypoints em prosa fazem as chamadas na ordem.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/mergex/scripts/ativacao-pre-push.sh .claude/skills/mergex/scripts/registrar-portao.sh .claude/skills/mergex/scripts/persistir-metodo.sh .claude/skills/mergex/assets/pre-push-gerenciado.sh .claude/skills/mergex/references/12-barreira-de-push.md .claude/skills/mergex/references/00-abertura.md .claude/skills/mergex/references/02-prontidao.md .claude/commands/mergex-abrir.md .opencode/commands/mergex-abrir.md .claude/commands/mergex-check.md .opencode/commands/mergex-check.md .claude/commands/mergex.md .opencode/commands/mergex.md scripts/ci/validate-mergex-contract.sh scripts/ci/test-r2-barreira-push.sh scripts/ci/lib/fixture-reconciliacao.sh
git commit -m "feat(mergex): ativa e prova o pre-push nos entrypoints do e0 e do e2"
```

### Task 16: Contrato e template de CI

**Files:**
- Create: `.claude/skills/mergex/scripts/portao-ci.sh` (100644)
- Create: `.claude/skills/mergex/assets/ci/mergex-portao.yml` (template; nunca copiado para `.github/workflows/` nesta branch)
- Modify: `.claude/skills/mergex/references/12-barreira-de-push.md` (seção "CI", com o handoff e a condição do PR #192)
- Modify: `scripts/ci/test-r2-barreira-push.sh` (grupo `ci`)

**Interfaces:**
- Consumes: `pr_decide_ref` e `pr_modo_null` (Task 14).
- Produces: `portao-ci.sh --verificar --sha <sha40> --branch <nome>`. Decide como uma ref `refs/heads/<nome>` empurrada com o SHA local `<sha>`, chamando `pr_decide_ref` (mesmas regras e mesmo modo do `pre-push`). Imprime `decisao=`, `motivo=`, `entrega=`. Códigos: 0 passa ou avisa, 1 barra, 64 uso. O template roda o checkout com `fetch-depth: 0` e chama `portao-ci.sh` com o SHA da cabeça do PR e a branch de origem dele.

- [ ] **Step 1: Escrever o grupo `ci` (RED)**

Casos:
- `ci reprova o SHA que o pre-push barraria` (vencido, ausente, `historia_incompleta`, `erro_ambiente`);
- `ci aprova o SHA que o pre-push libera`;
- `ci usa o SHA do PR, não o HEAD local` (checkout em outro commit);
- `null no CI segue o modo de .expx/hooks.json`;
- `template fixa fetch-depth 0 e passa o SHA da cabeça do PR` (verificação estática do YAML: `fetch-depth: 0`, `pull_request.head.sha`, chamada a `portao-ci.sh`);
- `nenhum workflow ativo nesta branch` (`git ls-files .github/workflows` vazio);
- `documentação não afirma CI ativo` (o reference diz que esta branch não ativa CI em produto, e nenhum arquivo versionado afirma o contrário pela frase-alvo verificada em `validate-mergex-contract.sh`);
- `PR #192 fica em rascunho até instalação, CI e gates` (a condição está no reference, com os três itens).

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r2-barreira-push.sh ci`
Expected: FAIL com `portao-ci.sh: No such file`.

- [ ] **Step 3: Implementar**

O executável, o template e a seção "CI" do reference. Em `validate-mergex-contract.sh`, acrescente a asserção de que nenhum arquivo versionado afirma CI ativo (`# guarda:CIATIVO` na linha da verificação). Inclua esse arquivo no commit.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r2-barreira-push.sh ci prepush && bash scripts/ci/validate-mergex-contract.sh`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Revisão independente**

Revisor novo, com o diff e a seção 13, item 8, da spec. Foco: mesma decisão do `pre-push` para a mesma entrada; nada ativa CI; o texto não promete proteção já em vigor.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/mergex/scripts/portao-ci.sh .claude/skills/mergex/assets/ci/mergex-portao.yml .claude/skills/mergex/references/12-barreira-de-push.md scripts/ci/test-r2-barreira-push.sh scripts/ci/validate-mergex-contract.sh
git commit -m "feat(mergex): contrato e template de ci do portao"
```

### Task 17: Hook do Claude consultivo

**Files:**
- Modify: `.claude/hooks/mergex/pr-so-com-portao.sh` (reescrito como consultivo; a varredura de branches, o prazo de 45 s e a leitura de diretório encadeado da implementação superada saem)
- Modify: `.claude/hooks/teste.sh` (remove as expectativas da implementação superada; casos novos)
- Modify: `.claude/hooks/README.md` (seção do hook: consultivo, limites, papel do `pre-push` e do CI)
- Modify: `.claude/settings.json` e `.opencode/plugin/mergex.ts` (timeout do hook volta a 10 s, como os demais)
- Modify: `scripts/ci/test-r2-barreira-push.sh` (grupo `modo`)

**Interfaces:**
- Consumes: `pr_decide_ref`, `pr_modo_null` (Task 14); `portao-ci.sh` (Task 16, no grupo `modo`); o parser compartilhado de `comum/base.sh`, inalterado.
- Produces: comportamento do hook.
  - **Bloqueia (exit 2) só com prova:** o comando é um único `git push` simples, sem `;`, `&&`, `||`, `|`, subshell, `cd`, `-C` ou expansão, no repositório do cwd legível pelo Git, com refspec que resolve sem ambiguidade para uma ref aplicável, e `pr_decide_ref` dá `barra`.
  - **Bloqueia sempre** o `--no-verify` literal num comando que publica (`# guarda:HKNV`).
  - **Em qualquer outro caso** (comando composto, UNC, `dubious ownership`, diretório que não determina, `git rev-parse` que falha, validade que não termina dentro do orçamento interno de 8 s): imprime aviso e sai 0. O `pre-push` decide.
  - Sem varredura de branches; sem laço de subida de diretório; nenhum caminho de código espera mais que o orçamento.

- [ ] **Step 1: Escrever os casos (RED)**

Na bancada:
- `push simples com portão vencido bloqueia`;
- `push simples com portão válido passa`;
- `--no-verify reconhecido bloqueia`;
- `comando composto avisa e sai 0` (`cd x && git push`, `bash -c 'git push'`, `xargs`);
- `dubious ownership avisa e sai 0` (repositório de outro dono, sem `safe.directory`);
- `cwd UNC sem repositório não entra em laço` (termina em menos de 2 s com `//`);
- `validade lenta não segura o comando` (stub que dorme 120 s: o hook sai 0 com aviso em menos de 9 s; e o `git push` real seguinte é barrado pelo `pre-push`);
- `regressão do falso bloqueio desta máquina: portão válido sobre UNC passa`;
- `git for windows sobre UNC: aviso sem bloqueio` (com `git.exe` e `wslpath`: push legítimo pelo Git Bash sobre `\\wsl.localhost\...` não é bloqueado pelo hook; sem eles, `NAO_EXECUTADO`, que não conta como ok);
- `hook não varre branches` (50 branches entregues: no máximo uma chamada da validade).
Os casos da implementação superada que esperavam bloqueio em comando composto, `cd`, `-C`, `GIT_DIR` ou varredura de branches passam a esperar aviso e exit 0, ou saem, se testavam mecanismo removido.

No grupo `modo` da `test-r2`: `null nos três modos: consumidores iguais`, com a mesma entrada no `portao-push.sh`, no `portao-ci.sh` e no hook (caso simples), em `bloqueio`, `aviso` e `desligado`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash .claude/hooks/teste.sh; bash scripts/ci/test-r2-barreira-push.sh modo`
Expected: FAIL. O `comando composto avisa e sai 0` falha, porque o hook atual bloqueia; o `validade lenta não segura o comando` falha, porque o hook atual espera até 45 s; e o `modo` falha, porque o hook ainda não usa `pr_decide_ref`.

- [ ] **Step 3: Implementar**

Reescrever o hook sobre `pr_decide_ref`, com orçamento interno de 8 s (`timeout` do coreutils na chamada à validade; sem `timeout`, só o caso simples sem validade lenta é avaliado e o resto avisa). Voltar o timeout em `settings.json` e no plugin a 10 s. Atualizar o README.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash .claude/hooks/teste.sh && bash scripts/ci/test-r2-barreira-push.sh todos && bash scripts/ci/validate-mergex-contract.sh`
Expected: todos `ok` (`NAO_EXECUTADO` listado à parte), rc 0. O lado a lado do `git-perigoso` contra `bd4c1c5`, com 300 comandos ou mais, continua com zero diferenças.

- [ ] **Step 5: Revisão independente**

Revisor novo, com o diff e a seção 13, item 8, da spec. Foco: nenhum bloqueio sem prova; `--no-verify`; nenhum caminho que espere ou entre em laço; nada que trate o hook como fronteira; o `git-perigoso` intacto.

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/mergex/pr-so-com-portao.sh .claude/hooks/teste.sh .claude/hooks/README.md .claude/settings.json .opencode/plugin/mergex.ts scripts/ci/test-r2-barreira-push.sh
git commit -m "fix(mergex): hook de portao passa a ser consultivo"
```

### Task 18: Hooks de commit no merge de integração

**Files:**
- Modify: `.claude/hooks/mergex/commit-por-task.sh`
- Modify: `.claude/hooks/mergex/arquivo-fora-do-plano.sh`
- Test: `.claude/hooks/teste.sh`

**Interfaces:**
- Consumes: `contrato-de-commit.sh --validar-integracao --arquivo`.
- Produces: com `MERGE_HEAD` presente, `commit-por-task` trata o `git commit` como integração de base: valida a mensagem quando ela vem de `-F <arquivo>` ou `-m` e não aplica as regras de mistura de tasks, status ou suíte; `arquivo-fora-do-plano` avalia só `git diff --cached --name-only MERGE_HEAD` (o que a integração muda em relação à base), não tudo o que veio dela.

- [ ] **Step 1: Escrever os casos (RED)**

```bash
echo "merge de integração da base"
merge_em_andamento_com_ajuste feature/ft-02     # deixa MERGE_HEAD e a resolução no índice
caso "integração não é mistura de tasks" mergex/commit-por-task.sh "$(bash_json 'git commit -F msg-integracao.txt')" 0
caso "integração com Task: barra" mergex/commit-por-task.sh "$(bash_json 'git commit -F msg-integracao-com-task.txt')" 2
caso "fora-do-plano não acusa o que veio da base" mergex/arquivo-fora-do-plano.sh "$(bash_json 'git commit -F msg-integracao.txt')" 0
```

O caso de `arquivo-fora-do-plano` roda em modo `bloqueio` para que um falso positivo apareça como exit 2. O helper `merge_em_andamento_com_ajuste <branch>` fica na bancada junto do helper `entrega`: faz a `main` da raiz temporária ganhar um arquivo novo e mudar um arquivo da task, roda `git merge --no-ff --no-commit main` na branch, resolve combinando os lados e ajusta o arquivo novo; grava `msg-integracao.txt` com `Trabalho:` e `Integra-base:` (o SHA de `MERGE_HEAD`) e `msg-integracao-com-task.txt` com os mesmos trailers mais `Task: T-01.01`.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash .claude/hooks/teste.sh`
Expected: FAIL em `integração não é mistura de tasks` e `fora-do-plano não acusa o que veio da base`.

- [ ] **Step 3: Implementar**

Nos dois hooks, detectar `git rev-parse -q --verify MERGE_HEAD` na raiz resolvida antes das regras atuais.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash .claude/hooks/teste.sh`
Expected: todos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/mergex/commit-por-task.sh .claude/hooks/mergex/arquivo-fora-do-plano.sh .claude/hooks/teste.sh
git commit -m "fix(mergex): hooks reconhecem o commit de integracao da base"
```

### Task 19: Contrato textual e decisões

**Files:**
- Create: `.claude/skills/mergex/references/11-reconciliacao-base.md`
- Modify: `.claude/skills/mergex/references/00-abertura.md` (E0 grava `base_validada_sha` e `origem_base: registrada_e0`; o passo do `pre-push` já vem da Task 15)
- Modify: `.claude/skills/mergex/references/00-schema.md` (chaves novas do `kind: entrega`; `kind: reconciliacao_base`; "Arquivos SEM frontmatter" não lista o artefato novo)
- Modify: `.claude/skills/mergex/references/01-commits.md` (classe integração; enum de checkpoints)
- Modify: `.claude/skills/mergex/references/02-prontidao.md` (ordem reconciliação → validade → push; barreira `--verificar --checkpoint reconciliacao-base`; V9 roda `portao-v9.sh`; a prova do `pre-push` e a gravação por `registrar-portao.sh`, com o `portao_sha`, já vêm da Task 15)
- Modify: `.claude/skills/mergex/references/06-push.md`, `07-abertura-pr.md` (pré-requisito de validade; o `pre-push` decide; o hook do Claude é consultivo; aponta para `12-barreira-de-push.md`)
- Modify: `.claude/skills/mergex/references/08-registro.md` (tabela "Quando o arquivo é escrito" com a reconciliação; catálogo cumulativo)
- Modify: `.claude/skills/mergex/SKILL.md` (fluxo e enum de checkpoints)
- Modify: `.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md` (chaves novas)
- Modify: `.claude/skills/mergex/DECISOES-DA-SKILL.md` (DM-178 a DM-184, texto da spec)
- Modify: `.claude/commands/mergex-check.md`, `.opencode/commands/mergex-check.md` (V9 por script; a prova do `pre-push` já vem da Task 15)
- Modify: `.claude/hooks/README.md` (validade do portão; integração; o texto do hook consultivo já vem da Task 17)
- Modify: `AGENTS.md` e `.claude/skills/mergex/SKILL.md`:
  - a frase "Uma única condição de método barra **mesmo em aviso**", que trata da regra de task irmã do `commit-por-task`, ganha a ressalva de que, fora dos hooks do Claude, o `pre-push` do Git barra o portão inválido em qualquer modo (DM-184);
  - a lista de hooks que nascem em aviso continua citando `pr-so-com-portao`, agora descrito como consultivo;
  - nenhuma frase passa a tratar esse hook como barreira.
- Test: `scripts/ci/validate-mergex-contract.sh`

**Interfaces:**
- Consumes: os executáveis e o reference `12-barreira-de-push.md` das Tasks 14–17.
- Produces: asserções de prosa:
  - enum `pre-e2 | reconciliacao-base | pre-e6 | e8` idêntico em `SKILL.md`, `01-commits.md`, `08-registro.md`, `catalogo-de-metodo.sh`, `persistir-metodo.sh` e `contrato-de-commit.sh`;
  - `02-prontidao.md` cita `portao-v9.sh` e `validade-do-portao.sh` (as asserções de `ativacao-pre-push.sh` e `registrar-portao.sh` nos entrypoints são da Task 15 e continuam valendo);
  - `11-reconciliacao-base.md` tem as quatro provas, a tabela de códigos de saída e os riscos residuais da seção 15.1 da spec;
  - DM-178..DM-184 presentes;
  - nenhum texto versionado trata `pr-so-com-portao` como barreira autoritativa;
  - nenhum script em `.claude/skills/mergex/scripts/` aceita opção que case `force|sem-prova|bypass` (`# guarda` não se aplica: é varredura).

- [ ] **Step 1: Escrever as asserções (RED)**

```bash
for f in "$SKILL" "$REF/01-commits.md" "$REF/08-registro.md"; do
  grep -Fq 'pre-e2 | reconciliacao-base | pre-e6 | e8' "$f" || fail "$f sem o enum de checkpoints novo"
done
grep -Fq 'portao-v9.sh' "$REF/02-prontidao.md" || fail "02-prontidao não manda rodar portao-v9.sh"
grep -Fq 'portao_sha' "$REF/02-prontidao.md" || fail "02-prontidao não grava portao_sha"
for dm in DM-178 DM-179 DM-180 DM-181 DM-182 DM-183 DM-184; do
  grep -q "^| $dm |" "$SKILL_DIR/DECISOES-DA-SKILL.md" || fail "falta $dm"
done
if grep -nE -- '--(force|sem-prova|bypass)' "$SKILL_DIR"/scripts/*.sh; then fail "flag de bypass encontrada"; fi
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/validate-mergex-contract.sh`
Expected: FAIL com as primeiras mensagens `sem o enum de checkpoints novo`.

- [ ] **Step 3: Escrever a prosa**

Transcrever as seções 4–20 da spec para os references indicados (`11-reconciliacao-base.md` leva as seções 4–9, 14, 15 com a 15.1, 19 e 20; a seção 13, itens 5–8, já está em `12-barreira-de-push.md` pelas Tasks 15 e 16; os demais references, o trecho da sua etapa), sem prosa nova de desenho; DM-178..DM-184 com o texto da seção "Decisões propostas".

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/validate-mergex-contract.sh`
Expected: rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex AGENTS.md .claude/commands/mergex-check.md .opencode/commands/mergex-check.md .claude/hooks/README.md scripts/ci/validate-mergex-contract.sh
git commit -m "docs(mergex): contrato da reconciliacao de base e do portao por sha"
```

### Task 20: Fluxo ponta a ponta

**Files:**
- Modify: `scripts/ci/test-r1-reconciliacao-base.sh` (grupos `fluxo` e `invariantes`)
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh`

**Interfaces:**
- Consumes: todos os executáveis anteriores, sem atalhos; `fx_worktree_vinculada` (Task 15); `fx_remoto_bare` e `fx_push_real` (Task 14).
- Produces: `fx_fluxo_completo <dir>`.

O grupo `fluxo` executa, na ordem da spec (seção 16), sobre o cenário:
1. `ativacao-pre-push.sh --instalar`, como no E0;
2. `--registrar` dos dois testes;
3. `persistir-metodo --checkpoint reconciliacao-base`;
4. barreira `--verificar --checkpoint reconciliacao-base`;
5. `portao-v9.sh` ok e `ativacao-pre-push.sh --provar` ok;
6. `registrar-portao.sh --resultado pronto` grava `portao: pronto` e `portao_sha`;
7. `persistir-metodo --checkpoint pre-e6`, com `ATENCAO.md` contendo os dois reconciliados em O10;
8. validade ok;
9. `persistir-metodo --checkpoint e8`;
10. validade ok;
11. push real ao remoto bare aceito pelo `pre-push`;
12. um commit de produto depois do portão, e o push real seguinte barrado.

O grupo `invariantes` repete o fluxo e exige `tasks.md` com o mesmo hash, `sequencia-de-commits.sh --ler` idêntico e V11 OK, e roda o mesmo fluxo dentro de `FX_WT` (Review Focus 5).

- [ ] **Step 1: Escrever os grupos (RED)**

```bash
grupo_fluxo() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  fx_fluxo_completo "$d" || { falha "fluxo: $FX_ERRO"; cd "$REPO"; return; }
  ok "fluxo completo depois da reconciliação"
  fx_remoto_bare "$d"
  fx_push_real "$d" origin feature/ft-rec | grep -q '^rc=0' && ok "pre-push libera o push real" || falha "push real"
  fx_commit_produto_apos_portao "$d"
  fx_push_real "$d" origin feature/ft-rec | grep -q '^rc=1' && ok "pre-push barra o push vencido" || falha "push vencido"
  cd "$REPO" || return
}
grupo_invariantes() {
  local d antes; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; fx_worktree_vinculada "$d"; cd "$FX_WT" || return
  antes="$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)$(bash "$SEQ" --ler "$FX_ENTREGA")"
  fx_fluxo_completo "$FX_WT" && ok "fluxo na worktree vinculada" || falha "worktree: $FX_ERRO"
  [ "$(git ls-files -z -- 'docs/sprintx/**/tasks.md' | xargs -0 cat | rb_sha256)$(bash "$SEQ" --ler "$FX_ENTREGA")" = "$antes" ] \
    && ok "plano e seq intactos" || falha "plano ou seq mudou"
  rc_igual "V11 OK" 0 bash "$PROVA" --verificar "$FX_ENTREGA" docs/sprintx/features/ft-rec/sprint-*/tasks.md
  cd "$REPO" || return
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh fluxo invariantes`
Expected: FAIL (`fx_fluxo_completo: command not found`); `fx_worktree_vinculada`, `fx_remoto_bare` e `fx_push_real` já existem (Tasks 14 e 15).

- [ ] **Step 3: Implementar os helpers de fixture**

`fx_fluxo_completo` só chama os executáveis da skill (inclusive `registrar-portao.sh` para `portao` e `portao_sha`) e nunca edita o `ENTREGA.md` à mão; falha na primeira etapa com rc diferente de 0, preenchendo `FX_ERRO`. `fx_commit_produto_apos_portao <dir>` faz um commit de produto comum na branch do trabalho. O push é sempre real, pelo `pre-push` instalado no passo 1; o hook do Claude não participa desta suíte.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh todos`
Expected: todos os grupos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "test(mergex): fluxo completo depois da reconciliacao de base"
```

### Task 21: Mutantes

**Files:**
- Create: `scripts/ci/mutacao-r1-reconciliacao-base.sh`

**Interfaces:**
- Consumes: as linhas marcadas `# guarda:<ID>` das Tasks 3–18 e a verificação `CIATIVO` de `validate-mergex-contract.sh` (Task 16).
- Produces: matriz com controle verde e 25 mutantes, no padrão de `mutacao-m3-fixture-lock-lf.sh` (`copia`, troca de **todas** as linhas marcadas com o ID por `: # mutante <ID>`, suíte alvo, resultado `morto|vivo`); rc 0 só com controle verde e todos mortos. Os 17 primeiros são a lista da spec (seção 21); os 8 seguintes completam a barreira de push da DM-184.

| # | ID | Mutação | Suíte que tem de reprovar |
|---|---|---|---|
| 1 | `P1` | prova 1 desligada | `r1 provas` |
| 2 | `P1D` | prova 1 aceita status `D` | `r1 provas` |
| 3 | `P2FP` | prova 2 sem `--first-parent` | `r1 provas`, `r1 cadeia` |
| 4 | `P3` | prova 3 desligada | `r1 provas` |
| 5 | `P4` | prova 4 desligada | `r1 provas` |
| 6 | `INV` | inventário desligado | `r1 provas` |
| 7 | `ASS` | assinatura não conferida | `r1 artefato` |
| 8 | `CAD` | encadeamento não conferido | `r1 cadeia` |
| 9 | `BLOBM` | cobertura sem `blob_m` | `r1 verificar` |
| 10 | `V9SHA` | V9 pela ref em vez do SHA | `r1 v9` |
| 11 | `PTPROD` | portão aceita commit de produto | `r1 portao` |
| 12 | `PTMERGE` | portão aceita merge | `r1 portao` |
| 13 | `PPSHA` | `pre-push` valida o `HEAD` do checkout em vez do SHA enviado | `r2 prepush` |
| 14 | `PPMODO` | `pre-push` deixa o modo `aviso` afrouxar `pronto` vencido | `r2 prepush` |
| 15 | `LEG2` | legado aceita dois merge-bases | `r1 legado` |
| 16 | `SEQ` | registro grava `seq` (acrescenta chamada a `sequencia-de-commits.sh --acrescentar`) | `r1 entrega`, `r1 invariantes` |
| 17 | `O10` | O10 permite faixa média | `test-atencao-metodo.sh` |
| 18 | `PPMULTI` | `pre-push` ignora uma segunda ref inválida | `r2 prepush` |
| 19 | `VALOBJ` | objeto Git ausente classificado como `erro_ambiente` | `r1 portao`, `r2 prepush` |
| 20 | `ATVTXT` | prova aceita hook que só cita a MergeX (sem conferir o sinal) | `r2 ativacao` |
| 21 | `ATVSOB` | E0 sobrescreve um `pre-push` de terceiro | `r2 ativacao` |
| 22 | `ATVHP` | E0 grava `core.hooksPath` | `r2 ativacao` |
| 23 | `HKNV` | hook do Claude aceita `--no-verify` como se a proteção local bastasse | `.claude/hooks/teste.sh` |
| 24 | `CIATIVO` | o contrato aceita texto que afirma CI ativo sem instalação no produto (a verificação é desligada e o mutante insere a frase-alvo no reference) | `validate-mergex-contract.sh`, `r2 ci` |
| 25 | `E2SEMHOOK` | E2 ignora a prova funcional e emite/persiste `PRONTO` (as linhas marcadas em `registrar-portao.sh` e em `persistir-metodo.sh` são neutralizadas juntas) | `r2 entrypoints` |

- [ ] **Step 1: Escrever a matriz e rodar o controle**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh controle`
Expected: `controle verde`.

- [ ] **Step 2: Rodar a matriz**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh`
Expected: `25 mortos, 0 vivos`, rc 0. Um mutante vivo é teste faltando na task dona da guarda: voltar àquela task, acrescentar o caso e só então reexecutar.

- [ ] **Step 3: Commit**

```bash
git add scripts/ci/mutacao-r1-reconciliacao-base.sh
git commit -m "test(mergex): mutantes da reconciliacao e do portao por sha"
```

### Task 22: Suíte ampla e validação do contrato

**Files:**
- Nenhum arquivo novo; correções só onde uma suíte apontar regressão real.

- [ ] **Step 1: Rodar tudo**

Run:
```bash
for t in scripts/ci/test-*.sh; do bash "$t" || echo "FALHOU $t"; done
for m in scripts/ci/mutacao-*.sh; do bash "$m" || echo "FALHOU $m"; done
bash .claude/hooks/teste.sh
bash scripts/ci/validate-mergex-contract.sh
```
Expected: nenhuma linha `FALHOU`; todos rc 0. As linhas `NAO_EXECUTADO` (Git for Windows ausente) são listadas no relatório final como não executadas, nunca como aprovadas.

- [ ] **Step 2: Conferir o escopo da branch**

Run: `git diff --name-only bd4c1c58c2ec36635aa365a3e79b3acbc7b7357d..HEAD`
Expected: só caminhos sob `.claude/`, `.opencode/`, `scripts/ci/`, `docs/superpowers/` e `AGENTS.md`; nenhum caminho de SprintX, BuildX ou ExpxDev; nenhum caminho sob `.github/workflows/`; `git grep -nE '/home/|C:\\\\'` vazio nos arquivos alterados.

- [ ] **Step 3: Corrigir regressão, se houver**

Uma suíte vermelha no Step 1 é regressão de uma task anterior: corrigir na task dona, com teste que a reproduza, e commitar só os arquivos tocados com a mensagem `fix(mergex): corrige regressao da suite ampla`. Sem regressão, esta task não gera commit.

### Task 23: Seleção da entrega pelo conteúdo (DM-185)

Spec: seção 13, itens 5, 7 e 8; seção 15; seção 15.1, itens 9–12; seção 21, caso 22; DM-185. Corrige o item bloqueante da auditoria de segurança final (contorno do CI e do `pre-push` pelo nome da branch) e o minor M3 da revisão final.

**Files:**
- Modify: `.claude/skills/mergex/scripts/portao-regras.sh`
- Modify: `.claude/skills/mergex/scripts/portao-ci.sh`
- Modify: `.claude/skills/mergex/scripts/portao-push.sh`
- Modify: `.claude/skills/mergex/assets/pre-push-gerenciado.sh`
- Modify: `.claude/skills/mergex/assets/ci/mergex-portao.yml` (só o comentário de limites; os argumentos da chamada continuam os mesmos)
- Modify: `.claude/skills/mergex/references/12-barreira-de-push.md` (seleção, CI, `pre-push`, limites da seção 15.1, itens 9–12)
- Modify: `.claude/skills/mergex/references/11-reconciliacao-base.md` e `.claude/hooks/README.md` só onde citam a regra de aplicabilidade pelo nome
- Modify: `scripts/ci/test-r2-barreira-push.sh` (grupos `ci`, `prepush`, `modo`, `ativacao`)
- Modify: `scripts/ci/validate-mergex-contract.sh` só se uma verificação existente depender do texto alterado

**Interfaces:**
- Consumes: `validade-do-portao.sh --rev` (Task 13/14), `pr_modo_null` e `pr_decide_ref` (Task 14), `portao-ci.sh` (Task 16), a prova funcional de `ativacao-pre-push.sh` (Task 15), o hook `pr-so-com-portao` (Task 17, inalterado: continua pelo nome).
- Produces, em `portao-regras.sh`:
  - `pr_entregas_do_intervalo <raiz> <base> <sha>`: imprime, um por linha, ordenados e sem repetição, os `docs/entregas/<id>/ENTREGA.md` selecionados pela spec, seção 13, item 5: `git merge-base --all` (mais de um → rc 1, motivo `base_ambigua`, `# guarda:CIMBALL` na linha que exige um único merge-base); parcela (a) `git diff-tree -r --no-renames -z MB <sha>` com qualquer status (`# guarda:CIDIFF` na linha que a acrescenta; `# guarda:CIDEL` na linha que define os status aceitos, que inclui `D`); parcela (b) `git log --full-history --no-merges --no-renames -z MB..<sha>` (`# guarda:CIHIST` na linha que a acrescenta; `# guarda:CIFULL2` na linha que passa `--full-history`); só o caminho canônico; caminho com controle → rc 1, `caminho_com_controle`; sem merge-base: árvore vazia (`git hash-object -t tree /dev/null`) em clone completo, `historia_incompleta` em clone raso; objeto ausente → `historia_incompleta`. Número constante de processos Git.
  - uma função que decide UMA entrega para um SHA (a cauda atual de `pr_decide_ref`, extraída sem mudar a decisão; `pr_decide_ref` passa a chamá-la; as marcas `PPSHA` e `PPMODO` continuam nas linhas equivalentes) e uma que decide uma lista de entregas, imprimindo `entrega[<i>]=`, `decisao[<i>]=`, `motivo[<i>]=` por entrega e o resumo `decisao=`, `motivo=`, `entrega=` (`-` com mais de uma) e `quantidade_entregas=` uma única vez no fim, com a agregação `barra` > `avisa` > `passa` (`# guarda:CIAGREG` na linha que agrega). Lista vazia: resumo `passa`, `ref_nao_aplicavel`.
- Produces, em `portao-ci.sh`: mesma interface de linha de comando (`--verificar --sha --branch --base`, códigos 0/1/64); a seleção é só `pr_entregas_do_intervalo` com `--base` e `--sha` (`# guarda:CINOME` na linha que a chama; o fallback pela história com filtro de nome, e suas marcas `CIFULL`/`CIHIST` antigas, deixam de existir); saída indexada da spec, seção 13, item 8; `aviso=branch_divergente` quando `--branch` não é o `branch:` de nenhuma entrega selecionada, sem mudar a decisão (`# guarda:BRDIV` na linha que emite o aviso); diagnóstico de base defasada quando há mais de uma entrega. As marcas `CISHA`, `CIBARRA` e `CIBRANCH` continuam nas linhas equivalentes.
- Produces, em `portao-push.sh` (por ref `refs/heads/*`; exclusão e tag como hoje): união das parcelas da spec, seção 13, item 7 — (a) `pr_entregas_do_intervalo` com `refs/remotes/<remoto>/HEAD` quando resolve para commit (`# guarda:PPBASE`), (b) a regra legada pelo nome (`_pr_entrega`, `# guarda:PPLEG`), (c) o trailer `Trabalho:` do SHA enviado, lido com `git interpret-trailers --parse` ou equivalente do commit (`# guarda:PPTRL`); decisão da lista com a agregação; `avisa` com `cobertura_indeterminada` quando não há (a) e (b)/(c) são vazias e a árvore enviada tem `ENTREGA.md` canônico (`# guarda:PPCOB`). As marcas `PPSHA` e `PPMULTI` continuam. O sinal `mergex-pre-push <sha> <decisao>` usa a decisão agregada da ref.
- Produces, em `pre-push-gerenciado.sh`: `[ -r "$MERGEX_PORTAO_PUSH" ]` antes do `exec`; sem o validador, mensagem `mergex pre-push: validador ausente neste checkout (<caminho>): push barrado; reinstale a skill ou rode ativacao-pre-push.sh --reverter` em stderr e código 1 (`# guarda:M3CHAM`). O marcador da segunda linha não muda.

- [ ] **Step 1: Escrever os testes (RED)**

No grupo `ci`, os dez cenários da auditoria de segurança final como regressão (uma fixture com `ENTREGA.md` de `branch: feature/ft-rec`, um SHA válido, um com produto depois do portão, um com `pronto` sem `portao_sha`, um com duas entregas, um com duas entregas declarando a mesma branch, um fork, um só de produto, clone sem `refs/heads` como o `actions/checkout`), cada um conferindo a decisão, o código e se a validade foi executada:
- passam: nome esperado com portão válido; mesmo SHA válido com outro nome; branch renomeada válida (estes dois com `aviso=branch_divergente`); PR sem `ENTREGA.md` alterado com o nome do trabalho e com outro nome (`ref_nao_aplicavel`);
- barram: nome esperado vencido e ausente; outro nome vencido; outro nome ausente; renomeada vencida; fork `patch-1` vencido; nome qualquer vencido; duas entregas com o nome de uma, de outra e de nenhuma; duas entregas declarando a mesma branch; `--branch` forjado e forjado com o nome de outra entrega.

Mais, no grupo `ci`: `merge que restaura o ENTREGA de um pai barra` (grafo P/C/M da DM-185); `criss-cross barra com base_ambigua`; `merge que altera o ENTREGA contra os dois pais barra`; `merge que apaga um ENTREGA da base barra`; `cria e apaga no PR barra`; `renomear o diretório da entrega barra`; `integração da base não seleciona entregas alheias`; `base defasada barra com o diagnóstico de base defasada`; `órfã completa sem entrega passa`; `órfã completa com entrega vencida barra`; `órfã em clone raso é historia_incompleta`; `saída indexada com uma entrega`; `saída indexada com duas entregas e resumo único`; `custo constante com centenas de entregas` (contagem de processos Git, como na Task 14).

No grupo `prepush`: `ref renomeada com origin/HEAD barra pelo conteúdo`; `push que apaga o ENTREGA da branch de mesmo nome barra pelo nome sem base`; `push por URL com nome divergente barra pelo trailer Trabalho do commit enviado`; `sem base, sem nome e sem trailer, com ENTREGA na árvore, avisa cobertura_indeterminada`; `sem base e sem ENTREGA na árvore passa`; `chamador gerenciado sem o validador barra com a mensagem da MergeX`. No grupo `modo`: `portao: null` nos três modos com a seleção pelo conteúdo, mesmo resultado no CI e no `pre-push`. No grupo `ativacao`: a prova funcional do E0/E2 continua com os dois lados (barra a ref inválida; passa o controle) depois da mudança. Os casos existentes dos grupos que assumiam a aplicabilidade pelo nome no CI (o caso `residual: PR de branch com outro nome não é aplicável`) passam a afirmar o comportamento novo; nenhum caso é apagado sem um substituto que afirme o comportamento novo.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/test-r2-barreira-push.sh ci prepush modo ativacao`
Expected: FAIL nos cenários de contorno (rc 0 onde se espera 1, validade não executada), na saída indexada e no chamador sem validador (`No such file`).

- [ ] **Step 3: Implementar**

As interfaces acima, em Bash 3.2. O hook `pr-so-com-portao` não muda. A prosa do reference, do template e dos cabeçalhos diz exatamente o limite da DM-185: fecha o contorno pelo nome; o CI não é barreira contra todo contorno deliberado (seção 15.1, itens 1 e 12).

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r2-barreira-push.sh && bash .claude/hooks/teste.sh && bash scripts/ci/test-r1-reconciliacao-base.sh fluxo && bash scripts/ci/validate-mergex-contract.sh`
Expected: todos `ok`, rc 0; nenhum `NAO_EXECUTADO` contado como ok.

- [ ] **Step 5: Revisão independente**

Revisor novo, com o diff, a DM-185 e a auditoria de segurança final. Foco: nenhum caminho em que o nome selecione ou isente no CI; falso negativo de seleção (merges, renomeação, criss-cross, órfã); a prova funcional do E0/E2 intacta; o texto não promete mais do que a DM-185.

- [ ] **Step 6: Commit**

```bash
git add .claude/skills/mergex/scripts/portao-regras.sh .claude/skills/mergex/scripts/portao-ci.sh .claude/skills/mergex/scripts/portao-push.sh .claude/skills/mergex/assets/pre-push-gerenciado.sh .claude/skills/mergex/assets/ci/mergex-portao.yml .claude/skills/mergex/references/12-barreira-de-push.md scripts/ci/test-r2-barreira-push.sh
git commit -m "fix(mergex): seleciona a entrega do portao pelo conteudo"
```
(acrescentar ao `git add` os demais arquivos da lista que a task de fato alterou)

### Task 24: Mutantes da DM-185

**Files:**
- Modify: `scripts/ci/mutacao-r1-reconciliacao-base.sh`

**Interfaces:**
- Consumes: as marcas `# guarda:<ID>` da Task 23.
- Produces: a matriz da Task 21 com 13 mutantes novos (25 → 38), no mesmo padrão; nenhum dos 25 existentes é removido ou enfraquecido; resultado individual de cada um.

| # | ID | Mutação | Suíte que tem de reprovar |
|---|---|---|---|
| 26 | `CINOME` | o CI seleciona pela regra do nome (`--branch`) em vez de `pr_entregas_do_intervalo` (exceção de troca, documentada) | `r2 ci` |
| 27 | `CIDIFF` | sem a parcela do diff de árvores | `r2 ci` (merge que altera o ENTREGA contra os dois pais) |
| 28 | `CIHIST` | sem a parcela dos commits não-merge | `r2 ci` (cria e apaga) |
| 29 | `CIFULL2` | parcela dos commits sem `--full-history` (exceção literal: só a opção sai) | `r2 ci` (merge que restaura) |
| 30 | `CIMBALL` | aceita o primeiro de vários merge-bases (exceção literal) | `r2 ci` (criss-cross) |
| 31 | `CIDEL` | a parcela do diff de árvores ignora o status `D` (exceção literal) | `r2 ci` (merge que apaga) |
| 32 | `CIAGREG` | a agregação devolve a decisão da primeira entrega | `r2 ci` (duas entregas) |
| 33 | `BRDIV` | `branch_divergente` barra em vez de avisar (exceção de troca) | `r2 ci` (outro nome, portão válido) |
| 34 | `PPBASE` | `pre-push` sem a parcela do conteúdo | `r2 prepush` |
| 35 | `PPLEG` | `pre-push` sem a parcela legada pelo nome | `r2 prepush` |
| 36 | `PPTRL` | `pre-push` sem a parcela do trailer | `r2 prepush` |
| 37 | `PPCOB` | `pre-push` sem o aviso `cobertura_indeterminada` | `r2 prepush` |
| 38 | `M3CHAM` | chamador gerenciado sem conferir o validador | `r2 prepush` |

- [ ] **Step 1: Rodar o controle**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh controle`
Expected: `controle verde`.

- [ ] **Step 2: Rodar a matriz**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh`
Expected: `38 mortos, 0 vivos`, rc 0. Um mutante vivo é teste faltando na Task 23: acrescentar o caso lá (no mesmo commit desta task, como na Task 21) e reexecutar. Um mutante equivalente (nenhum caso alcançável o distingue) é provado no relatório e decidido pelo controlador; a matriz não encolhe sem decisão registrada.

- [ ] **Step 3: Commit**

```bash
git add scripts/ci/mutacao-r1-reconciliacao-base.sh
git commit -m "test(mergex): mutantes da selecao do portao pelo conteudo"
```

### Revisão final da branch

Depois da Task 24, um revisor novo, no modelo mais capaz, avalia a branch inteira contra a spec, este plano e os contratos. Além da conformidade geral, o relatório classifica cada um dos doze riscos residuais da spec (seção 15.1) numa destas categorias, citando o teste ou o trecho de código que sustenta a classificação:
- **eliminado:** o desenho atual o remove;
- **testado e aceito:** existe teste que fixa o comportamento aceito;
- **documentado sem mitigação técnica nesta rodada:** só cabeçalho ou reference.

Classificação esperada, que o revisor confirma ou contesta com evidência:

| # | Risco (spec 15.1) | Categoria esperada |
|---|---|---|
| 1 | Portão reposicionado por commit de método | testado e aceito (teste `residual: portão reposicionado por commit de método`) |
| 2 | Legado com ref de base movida; âncora nascida errada | testado e aceito (testes `residual: legado com ref movida` e `residual: âncora nascida errada`) |
| 3 | B1 lateral | documentado sem mitigação técnica |
| 4 | Clone raso legítimo falha fechado | testado e aceito (`clone raso barra com historia_incompleta`) |
| 5 | Isenção por prefixo em `docs/entregas/<id>/` | testado e aceito (`isenção por prefixo: .ts em docs/entregas depois do portão invalida`, Task 14) |
| 6 | `core.autocrlf` na barreira | documentado sem mitigação técnica |
| 7 | Hash do diff com atributos `-diff`/`binary` | documentado sem mitigação técnica |
| 8 | Escala por branches entregues | eliminado (`custo independe das branches entregues`, `hook não varre branches`) |
| 9 | PR sem `ENTREGA.md` | testado e aceito (`PR sem ENTREGA.md alterado … ref_nao_aplicavel`, Task 23) |
| 10 | Várias entregas ativas; remoção ou toque-e-restaura | testado e aceito (casos de duas entregas e de remoção, Task 23) |
| 11 | Base do evento defasada | testado e aceito (`base defasada barra com o diagnóstico de base defasada`, Task 23) |
| 12 | Limite do CI frente ao autor do PR | documentado sem mitigação técnica |

Também lista os casos `NAO_EXECUTADO` e confirma que nenhum foi contado como aprovado.

---

## Handoff posterior (fora desta branch)

Nenhum destes passos é código desta branch; cada um tem dono e autorização próprios.

1. **PR da MergeX:** `fix/mergex-reconciliacao-base-pos-e8` → `p0.2/mergex-historico-yaml-escalar`, com o resultado da Task 22 e da revisão final na descrição. O PR não declara CI ativo em produto nenhum.
2. **Recertificação:** a Task 22 reexecutada no commit integrado.
3. **ExpxDev:** atualizar pin/lock da MergeX e os candidatos de certificação, e rodar a certificação P0.2 (spec, seção 18.3). Se o empacotamento do `pre-push` ou do template de CI exigir mudança no ExpxDev, ela é handoff próprio.
4. **Conselhos Municipais:** PR separado de instalação na `main`, com o lock novo e `doctor` limpo (spec, seção 18.4). Ativação do `pre-push` pelo E0 (`ativacao-pre-push.sh --instalar`) e do check de CI a partir de `assets/ci/mergex-portao.yml`, com proteção de merge exigindo o check: handoffs próprios desse passo, comprovados antes do passo 5.
5. **Retomada do PR #192:** pela spec, seção 17, preservando a resolução que está no índice. O PR continua em rascunho até o QA aprovar e até estarem comprovados a instalação com o `pre-push` ativo, o check de CI com a proteção de merge e os gates.
