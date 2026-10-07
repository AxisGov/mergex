# MergeX — Reconciliação de base pós-E8 — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar à MergeX um caminho fechado e verificável para integrar uma base que avançou depois do E8: artefato de reconciliação com quatro provas recalculadas do Git, V9 executável por SHA, E3 obrigatório para reconciliados e portão vinculado a commit.

**Architecture:** Um executável novo (`reconciliacao-base.sh`) registra e verifica a reconciliação, apoiado numa biblioteca de artefato (`reconciliacao-artefato.sh`) que emite, lê, valida e assina `RECONCILIACAO-BASE-NNN.md`. A V9 passa a ser o executável `portao-v9.sh`, que compõe a união das tasks (exposta por `ownership-da-task.sh --uniao`) com os caminhos que a verificação da reconciliação declara cobertos. A validade do portão é o executável `validade-do-portao.sh`, consumido pelo hook `pr-so-com-portao`; o checkpoint `reconciliacao-base` entra no enum fechado de `contrato-de-commit.sh`, `catalogo-de-metodo.sh` e `persistir-metodo.sh`.

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
- Portão `pronto` vencido barra o push em qualquer modo do hook; portão `null` ou `bloqueado` continua respeitando o modo configurado, como hoje.
- Toda linha que implementa uma guarda listada nos mutantes termina com o comentário `# guarda:<ID>`; os mutantes trocam essas linhas pelo identificador.
- Commits pequenos, um por task, no formato do repositório (`test(mergex):`, `fix(mergex):`, `docs(mergex):`), sem push.
- Nenhum caminho absoluto nem estado de máquina nos arquivos versionados.

## Review Focus

1. **Caminho com espaço, acento ou aspas** entre os reconciliados — o registro grava, a verificação cobre e a V9 aceita exatamente aquele caminho, sem `core.quotepath` escapar nomes. Teste na Task 5 (`caminho com espaço e acento`).
2. **Entrega legada com `portao: pronto` e sem `portao_sha`** — o push é barrado com instrução de rodar o E2 de novo, nunca liberado. Teste na Task 14 (`pronto legado sem portao_sha`).
3. **Ref local da base parada enquanto a remota avançou** — a V9 dá o mesmo resultado, porque usa o SHA validado, não o nome. Teste na Task 11 (`ref local desatualizada`).
4. **Conflito resolvido pegando o lado da base inteiro para um arquivo** — sem diferença `B1..M`, o arquivo não pode ser reconciliado (prova 4) e também não aparece na V9. Teste na Task 5 (`resolução igual à base`).
5. **Produto rodando numa worktree vinculada** (`.git` é arquivo) — registro, trava C5 e checkpoint funcionam igual. Teste na Task 17 (`worktree vinculada`).

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

### Task 14: Hook `pr-so-com-portao`

**Files:**
- Modify: `.claude/hooks/mergex/pr-so-com-portao.sh`
- Test: `.claude/hooks/teste.sh`

**Interfaces:**
- Consumes: `expx_trabalho_atual_por_branch` (base.sh), `validade-do-portao.sh --verificar`.
- Produces: o hook resolve o `ENTREGA.md` pelo trabalho da branch ativa (nunca `ls -t`; `# guarda:HKREC`); sem trabalho determinado, sai 0 como hoje; `portao: pronto` com `validade ok=false` barra com exit 2 em qualquer modo (`# guarda:HKAVISO`), com mensagem nomeando `motivo` e `primeiro_commit` e mandando rodar o E2; `null`/`bloqueado` mantêm o comportamento por modo.

- [ ] **Step 1: Escrever os casos (RED)**

```bash
echo "pr-so-com-portao — validade"
# ENTREGA de outro trabalho mais recente não decide pela branch ativa
entrega outro feature/outro; sed -i 's/^portao: .*/portao: pronto/' docs/entregas/outro/ENTREGA.md; touch docs/entregas/outro/ENTREGA.md
caso "entrega de outro trabalho mais recente não libera" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 2
echo '{"expx_hooks":1,"hooks":{"pr-so-com-portao":{"modo":"aviso"}}}' > .expx/hooks.json
portao_vencido_por_merge feature/ft-02
caso "portão vencido barra mesmo em aviso" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 2
portao_sem_sha feature/ft-02
caso "pronto legado sem portao_sha barra" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 2
portao_valido_com_metodo feature/ft-02
caso "portão válido com commit só de método libera" mergex/pr-so-com-portao.sh "$(bash_json 'git push origin feature/ft-02')" 0
```

Os helpers `portao_vencido_por_merge`, `portao_sem_sha` e `portao_valido_com_metodo` ficam junto do helper `entrega` existente na bancada.

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash .claude/hooks/teste.sh`
Expected: FAIL nos quatro casos novos (o hook atual lê o `ENTREGA.md` mais recente e libera `pronto`).

- [ ] **Step 3: Implementar**

Substituir a linha do `ls -t` pela resolução por branch e acrescentar a chamada à validade antes do `case "$PORTAO"`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash .claude/hooks/teste.sh`
Expected: todos `ok` (os casos antigos de `pronto` passam a montar `portao_sha` válido).

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/mergex/pr-so-com-portao.sh .claude/hooks/teste.sh
git commit -m "fix(mergex): push exige portao valido para o head da branch"
```

### Task 15: Hooks de commit no merge de integração

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

### Task 16: Contrato textual e decisões

**Files:**
- Create: `.claude/skills/mergex/references/11-reconciliacao-base.md`
- Modify: `.claude/skills/mergex/references/00-abertura.md` (E0 grava `base_validada_sha` e `origem_base: registrada_e0`)
- Modify: `.claude/skills/mergex/references/00-schema.md` (chaves novas do `kind: entrega`; `kind: reconciliacao_base`; "Arquivos SEM frontmatter" não lista o artefato novo)
- Modify: `.claude/skills/mergex/references/01-commits.md` (classe integração; enum de checkpoints)
- Modify: `.claude/skills/mergex/references/02-prontidao.md` (V9 roda `portao-v9.sh`; barreira `reconciliacao-base`; E2 grava `portao_sha`)
- Modify: `.claude/skills/mergex/references/06-push.md`, `07-abertura-pr.md` (pré-requisito de validade)
- Modify: `.claude/skills/mergex/references/08-registro.md` (tabela "Quando o arquivo é escrito" com a reconciliação; catálogo cumulativo)
- Modify: `.claude/skills/mergex/SKILL.md` (fluxo e enum de checkpoints)
- Modify: `.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md` (chaves novas)
- Modify: `.claude/skills/mergex/DECISOES-DA-SKILL.md` (DM-178 a DM-183, texto da spec)
- Modify: `.claude/commands/mergex-check.md`, `.opencode/commands/mergex-check.md` (V9 por script)
- Modify: `.claude/hooks/README.md` (validade do portão; integração)
- Test: `scripts/ci/validate-mergex-contract.sh`

**Interfaces:**
- Produces: asserções de prosa: enum `pre-e2 | reconciliacao-base | pre-e6 | e8` idêntico em `SKILL.md`, `01-commits.md`, `08-registro.md`, `catalogo-de-metodo.sh`, `persistir-metodo.sh`, `contrato-de-commit.sh`; `02-prontidao.md` cita `portao-v9.sh` e `validade-do-portao.sh`; `11-reconciliacao-base.md` tem as quatro provas e a tabela de códigos de saída da spec; DM-178..DM-183 presentes; nenhum script em `.claude/skills/mergex/scripts/` aceita opção que case `force|sem-prova|bypass` (`# guarda` não se aplica: é varredura).

- [ ] **Step 1: Escrever as asserções (RED)**

```bash
for f in "$SKILL" "$REF/01-commits.md" "$REF/08-registro.md"; do
  grep -Fq 'pre-e2 | reconciliacao-base | pre-e6 | e8' "$f" || fail "$f sem o enum de checkpoints novo"
done
grep -Fq 'portao-v9.sh' "$REF/02-prontidao.md" || fail "02-prontidao não manda rodar portao-v9.sh"
grep -Fq 'portao_sha' "$REF/02-prontidao.md" || fail "02-prontidao não grava portao_sha"
for dm in DM-178 DM-179 DM-180 DM-181 DM-182 DM-183; do
  grep -q "^| $dm |" "$SKILL_DIR/DECISOES-DA-SKILL.md" || fail "falta $dm"
done
if grep -nE -- '--(force|sem-prova|bypass)' "$SKILL_DIR"/scripts/*.sh; then fail "flag de bypass encontrada"; fi
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `bash scripts/ci/validate-mergex-contract.sh`
Expected: FAIL com as primeiras mensagens `sem o enum de checkpoints novo`.

- [ ] **Step 3: Escrever a prosa**

Transcrever as seções 4–20 da spec para os references indicados (`11-reconciliacao-base.md` leva as seções 4–9, 14, 15, 19 e 20; os demais references, o trecho da sua etapa), sem prosa nova de desenho; DM-178..DM-183 com o texto da seção "Decisões propostas".

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/validate-mergex-contract.sh`
Expected: rc 0.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/mergex .claude/commands/mergex-check.md .opencode/commands/mergex-check.md .claude/hooks/README.md scripts/ci/validate-mergex-contract.sh
git commit -m "docs(mergex): contrato da reconciliacao de base e do portao por sha"
```

### Task 17: Fluxo ponta a ponta

**Files:**
- Modify: `scripts/ci/test-r1-reconciliacao-base.sh` (grupos `fluxo` e `invariantes`)
- Modify: `scripts/ci/lib/fixture-reconciliacao.sh`

**Interfaces:**
- Consumes: todos os executáveis anteriores, sem atalhos.
- Produces: `fx_worktree_vinculada <dir>` (cria worktree e exporta `FX_WT`).

O grupo `fluxo` executa, na ordem da spec (seção 16), sobre o cenário: `--registrar` dos dois testes → `persistir-metodo --checkpoint reconciliacao-base` → barreira `--verificar` → `portao-v9.sh` ok → grava `portao: pronto` e `portao_sha` → `persistir-metodo --checkpoint pre-e6` com `ATENCAO.md` contendo os dois reconciliados em O10 → validade ok → `persistir-metodo --checkpoint e8` → validade ok → hook libera o push. O grupo `invariantes` repete o fluxo e exige `tasks.md` com o mesmo hash, `sequencia-de-commits.sh --ler` idêntico, V11 OK, e roda o mesmo fluxo dentro de `FX_WT` (Review Focus 5).

- [ ] **Step 1: Escrever os grupos (RED)**

```bash
grupo_fluxo() {
  local d; d="$(mktemp -d)"; TMPS="$TMPS $d"; fx_cenario "$d"; cd "$d" || return
  fx_fluxo_completo "$d" || { falha "fluxo: $FX_ERRO"; cd "$REPO"; return; }
  ok "fluxo completo depois da reconciliação"
  printf '%s\n' "$(fx_hook_push "$d" feature/ft-rec)" | grep -q '^rc=0' && ok "hook libera push" || falha "hook"
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
Expected: FAIL (`fx_fluxo_completo: command not found`).

- [ ] **Step 3: Implementar os helpers de fixture**

`fx_fluxo_completo` só chama os executáveis da skill e grava os campos do `ENTREGA.md` que o contrato manda o agente gravar (`portao`, `portao_sha`); falha na primeira etapa com rc diferente de 0, preenchendo `FX_ERRO`. `fx_hook_push` alimenta o hook com o JSON do harness e imprime `rc=<n>`.

- [ ] **Step 4: Rodar e ver passar**

Run: `bash scripts/ci/test-r1-reconciliacao-base.sh todos`
Expected: todos os grupos `ok`, rc 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci/lib/fixture-reconciliacao.sh scripts/ci/test-r1-reconciliacao-base.sh
git commit -m "test(mergex): fluxo completo depois da reconciliacao de base"
```

### Task 18: Mutantes

**Files:**
- Create: `scripts/ci/mutacao-r1-reconciliacao-base.sh`

**Interfaces:**
- Consumes: as linhas marcadas `# guarda:<ID>` das Tasks 3–15.
- Produces: matriz com controle verde e 17 mutantes, no padrão de `mutacao-m3-fixture-lock-lf.sh` (`copia`, troca da linha marcada por `: # mutante <ID>`, suíte alvo, resultado `morto|vivo`); rc 0 só com controle verde e todos mortos.

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
| 13 | `HKREC` | hook volta a ler o `ENTREGA.md` mais recente | `.claude/hooks/teste.sh` |
| 14 | `HKAVISO` | portão vencido respeita modo aviso | `.claude/hooks/teste.sh` |
| 15 | `LEG2` | legado aceita dois merge-bases | `r1 legado` |
| 16 | `SEQ` | registro grava `seq` (acrescenta chamada a `sequencia-de-commits.sh --acrescentar`) | `r1 entrega`, `r1 invariantes` |
| 17 | `O10` | O10 permite faixa média | `test-atencao-metodo.sh` |

- [ ] **Step 1: Escrever a matriz e rodar o controle**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh controle`
Expected: `controle verde`.

- [ ] **Step 2: Rodar a matriz**

Run: `bash scripts/ci/mutacao-r1-reconciliacao-base.sh`
Expected: `17 mortos, 0 vivos`, rc 0. Um mutante vivo é teste faltando na task dona da guarda: voltar àquela task, acrescentar o caso e só então reexecutar.

- [ ] **Step 3: Commit**

```bash
git add scripts/ci/mutacao-r1-reconciliacao-base.sh
git commit -m "test(mergex): mutantes da reconciliacao e do portao por sha"
```

### Task 19: Suíte ampla e validação do contrato

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
Expected: nenhuma linha `FALHOU`; todos rc 0.

- [ ] **Step 2: Conferir o escopo da branch**

Run: `git diff --name-only bd4c1c58c2ec36635aa365a3e79b3acbc7b7357d..HEAD`
Expected: só caminhos sob `.claude/`, `.opencode/`, `scripts/ci/` e `docs/superpowers/`; nenhum caminho de SprintX, BuildX ou ExpxDev; `git grep -nE '/home/|C:\\\\'` vazio nos arquivos alterados.

- [ ] **Step 3: Corrigir regressão, se houver**

Uma suíte vermelha no Step 1 é regressão de uma task anterior: corrigir na task dona, com teste que a reproduza, e commitar só os arquivos tocados com a mensagem `fix(mergex): corrige regressao da suite ampla`. Sem regressão, esta task não gera commit.

---

## Handoff posterior (fora desta branch)

Nenhum destes passos é código desta branch; cada um tem dono e autorização próprios.

1. **PR da MergeX:** `fix/mergex-reconciliacao-base-pos-e8` → `p0.2/mergex-historico-yaml-escalar`, com o resultado da Task 19 na descrição.
2. **Recertificação:** a Task 19 reexecutada no commit integrado.
3. **ExpxDev:** atualizar pin/lock da MergeX e os candidatos de certificação, e rodar a certificação P0.2 (spec, seção 18.3).
4. **Conselhos Municipais:** PR separado de instalação na `main`, com o lock novo e `doctor` limpo (spec, seção 18.4).
5. **Retomada do PR #192:** pela spec, seção 17, preservando a resolução que está no índice.
