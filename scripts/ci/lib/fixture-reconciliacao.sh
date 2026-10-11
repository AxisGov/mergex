#!/usr/bin/env bash
# Fixture Git real do cenário "a base avança depois do E8".
#
# Funções:
#   fx_cenario <dir> [legado]   monta o cenário inteiro e exporta
#                               FX_B0 FX_P1 FX_B1 FX_M FX_TRAB FX_ENTREGA FX_NOVO1 FX_NOVO2
#   fx_merge_sem_commit <dir>   o mesmo cenário, parado com o merge resolvido
#                               e no índice, sem commit (MERGE_HEAD presente)
#   fx_segunda_base <dir> [ajusta]  segunda base B2 integrada num merge M2
#                               (HEAD): FX_B2 FX_M2 FX_NOVO3
#   fx_terceira_base <dir>      terceira base B3 integrada num merge M3 (HEAD),
#                               que ajusta FX_NOVO4: FX_B3 FX_M3 FX_NOVO4
#   fx_persiste_reconciliacao <dir>  commita ENTREGA.md e os artefatos
#                               (checkpoint de método reconciliacao-base)
#   fx_emite_reconciliacao <dir> <n> <b0> <m> [caminho...]  artefato NNN
#                               coerente e assinado (rb_emitir), sem provar nada
#   fx_forja_artefato <dir> <caminho>...  o 001 (FX_B0, FX_M) com esses caminhos
#   fx_entrega_sincroniza <dir> ENTREGA.md do disco com a lista dos artefatos
#   fx_entrega_chaves_legado <dir> ENTREGA.md legado do disco com as chaves
#                               que o registro legado grava (para forjar)
#   fx_portao_em <dir> <rev>    portao: pronto e portao_sha = <rev>, commit pre-e6
#   fx_portao_sem_sha <dir>     portao: pronto sem portao_sha, commit pre-e6
#   fx_commit_metodo <dir> <checkpoint> <caminho>...  commit de método que
#                               acrescenta uma linha a cada caminho
#   fx_commit_solto <dir>       commit fora da história de HEAD (imprime o SHA)
#   fx_remoto_bare <dir>        remoto.git bare ao lado de <dir> (no temporário
#                               do teste), como `origin` de <dir>: FX_REMOTO
#   fx_push_real <dir> <args do git push>...  `git push` real com o pre-push
#                               apontando para portao-push.sh (chamador mínimo
#                               da fixture); imprime rc=, ref= e stderr=
#   fx_push_efetivo <dir> <args do git push>...  o mesmo push real e a mesma
#                               saída, sem chamador mínimo nem core.hooksPath:
#                               decide o pre-push do diretório efetivo (o do E0)
#   fx_fluxo_completo <dir>     o fluxo da spec, seção 16, só pelos executáveis
#                               da skill (E0 ao e8); falha na primeira etapa
#                               com FX_ERRO; saídas em FX_FLUXO_DIR
#   fx_commit_produto_apos_portao <dir>  commit de produto comum na branch
#   fx_worktree_vinculada <dir> worktree vinculada (`.git` é arquivo) com
#                               feature/ft-rec, ao lado de <dir> (o checkout
#                               principal fica destacado no mesmo commit): FX_WT
#   fx_hook_terceiro <dir> <variante>  grava um pre-push de terceiro no
#                               diretório de hooks efetivo de <dir>
#                               (`git rev-parse --git-path hooks`), executável:
#     nao_composto  não chama a MergeX e sai 0
#     composto      repassa a entrada ao portao-push.sh e propaga o código
#     so_cita       cita o portao-push.sh num comentário e sai 1 sozinho
#     nao_propaga   chama o portao-push.sh com a entrada e sai 0
#     libera        chama o portao-push.sh SEM a entrada e propaga (sai 0)
#     sinal         chama o portao-push.sh com a entrada e se mata (SIGKILL)
#     ecoa_sinal    não chama a MergeX: forja linhas de sinal (a antiga e uma
#                   com SHA arbitrário) e sai 1
#     sem_entrada   chama o portao-push.sh com </dev/null e sai 1 sozinho
#     lento         chama o portao-push.sh com a entrada e dorme (`sleep
#                   3077`) antes de sair 1: para o orçamento de tempo
#     ignora_term   como `lento`, ignorando SIGTERM (só o KILL o encerra)
#     regra_propria chama o portao-push.sh, ignora o código dele e sai 1
#                   quando a URL é file:///dev/null (0 nas demais)
#     sempre_barra  repassa a entrada e propaga o código, num ambiente em que
#                   a MergeX barra toda ref (GIT_OBJECT_DIRECTORY vazio)
#
# Variantes (FX_VARIANTE=<nome> fx_cenario <dir>): sem FX_VARIANTE o cenário é
# o padrão, idêntico ao de sempre. Toda montagem exporta FX_LISTA_VARIANTE, os
# caminhos que o caso tenta registrar, UM POR LINHA (caminho com espaço chega
# inteiro: leia com `while IFS= read -r`), e FX_ESPECIAL.
#   base_removeu          a base remove README.md e a integração o mantém
#   integracao_removeu    a integração remove FX_NOVO2
#   renomeado             a base renomeia README.md para LEIAME.md
#   resolucao_igual_base  FX_NOVO2 resolvido com o lado da base inteiro
#   m_um_pai              M é um commit comum (um pai) com a árvore do merge
#   pais_trocados         M^1 é a base e M^2 é a feature
#   fora_primeiro_pai     a integração real fica num ramo lateral; HEAD é um
#                         merge que a traz como segundo pai
#   m_sem_integra_base    mensagem de M sem Integra-base:
#   m_com_metodo          mensagem de M com Metodo: e8
#   caminho_especial      a base cria FX_ESPECIAL (espaço, acento e apóstrofo),
#                         ajustado no merge; o repositório usa core.quotepath true
#   base_alterou          a base altera README.md (existia em B0); ajustado no merge
#   diretorio             a base cria tests/base/{x,y,z}.ts; o merge ajusta x e y
#   substring_declarado   o merge cria tests/ui/ft-rec.test (prefixo de um
#                         caminho declarado, sem ser declarado)
#   tipo_mudou            a base troca README.md por link simbólico (status T);
#                         o merge muda o alvo do link
#   b0_fora_b1            o merge grava base_validada_sha = commit do plano
#   b0_fora_p1            o merge grava base_validada_sha = B1
#   b0_ref                o merge grava base_validada_sha = main (nome de ref)
#   entrega_kind          o merge grava kind: outro no ENTREGA.md
#   entrega_trabalho      o merge grava trabalho_id: outro no ENTREGA.md
#   entrega_sem_branch_base  o merge remove branch_base do ENTREGA.md
#   entrega_sem_chaves    o merge tira do ENTREGA.md reconciliacoes, causa,
#                         push_feito, entregue_em, portao_sha, falhas_portao e
#                         atualizado_em, e põe chaves ANINHADAS com esses nomes
#                         em atencao
#   entrega_dup           o merge repete `estado:` no frontmatter do ENTREGA.md
#   entrega_reconc_cheia  o merge grava uma reconciliação na lista do ENTREGA.md
#   entrega_bloco         o merge grava falhas_portao e causa em forma de bloco
#   entrega_crlf          o ENTREGA.md do merge usa CRLF
#   entrega_bloco_vazia   falhas_portao em bloco com linha em branco no meio
#   entrega_bloco_comentario  falhas_portao em bloco com `#` na coluna 0 no meio
#   entrega_bloco_escalar causa como escalar `|` com linha vazia
#   entrega_bloco_col0    falhas_portao com itens `- ` na coluna 0
#   entrega_bloco_estranho  falhas_portao seguido de linha solta não reconhecível
#   entrega_aspas_d       chave de topo "estado" entre aspas duplas
#   entrega_aspas_s       chave de topo 'portao' entre aspas simples
#   entrega_symlink       o merge troca o ENTREGA.md por link para ENTREGA-real.md
#   plano_symlink         o merge cria um link simbólico na pasta do trabalho
#   merge_area_base       o merge cria docs/sprintx/features/ft-rec/base/notas.md
#   plano_nl              a base cria, na pasta do trabalho, `foo` e
#                         `foo<NL>$FX_NL_ALVO/tasks.md` (FX_NL_ALVO: diretório
#                         absoluto, obrigatório nesta variante)
#   plano_tab             a base cria `tab<TAB>no nome.md` na pasta do trabalho
#   duas_pastas           a base cria docs/ft-rec/notas.md (pasta legada) e M
#                         passa a ter a canônica e a legada
#   runx                  o trabalho é RunX: plano em docs/manutencao/ft-rec e
#                         ENTREGA.expx_tool runx
#   entrega_no_merge      o PRÓPRIO merge reescreve base_validada_sha no
#                         ENTREGA.md (M difere de P1 no ENTREGA.md)
#   criss_cross           dois ramos laterais da base (docs/lateral/um.md e
#                         dois.md) integrados por merges distintos na feature
#                         (antes do merge, em P1) e na main (antes de B1):
#                         `git merge-base --all P1 B1` tem dois resultados
#   merge_previo          a feature integra uma main intermediária
#                         (docs/intermediario.md) num merge comum antes do
#                         merge de integração: a linha de primeiro pai de P1
#                         desde o merge-base contém merge
#   base_com_pai          um commit raiz (RAIZ.md) antes de B0: B0 tem pai
#   lateral_reverte       um commit raiz com o README.md antigo antes de B0 (B0
#                         o reescreve); um ramo lateral parte da raiz sem
#                         mudança própria, e a feature o integra, antes do
#                         merge de integração, num merge (P1) cuja resolução
#                         desfaz o README.md para a versão da raiz; a base
#                         altera o README.md entre B0 e B1 e M o ajusta (como
#                         base_alterou). Na linha de primeiro pai de P1 só esse
#                         merge toca o README.md; o histórico completo (sem
#                         --first-parent) segue o lado lateral, igual à raiz, e
#                         não vê toque nenhum
#   entrega_sem_base      o ENTREGA.md (não legado) perde base_validada_sha e
#                         mantém origem_base
#   entrega_base_vazia    base_validada_sha presente e vazia
#   entrega_base_null     base_validada_sha: null
#   entrega_base_aspas    "base_validada_sha" entre aspas
# As demais variantes de ENTREGA.md e de B0 alteram o ENTREGA.md num commit da
# feature logo antes do merge (que passa a ser P1), porque o merge de
# integração não pode mexer no ENTREGA.md; a árvore continua limpa.
#
# Só comandos Git reais. Nenhum SHA é fixo: tudo é lido com `git rev-parse`.
# Não depende do cwd do chamador além do diretório alvo; ao final, o repositório
# alvo fica na branch feature/ft-rec e o cwd do chamador é restaurado.

_FXR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=fixture-git.sh
. "$_FXR_LIB/fixture-git.sh"

# Caminho do contrato de commit da própria skill (validação da fixture).
_FXR_CONTRATO="$(cd "$_FXR_LIB/../../.." && pwd)/.claude/skills/mergex/scripts/contrato-de-commit.sh"

_fx_commit() { # <arquivo-de-mensagem> — commita o índice atual
  git commit -q -F "$1"
}

_fx_msg() { # <arquivo> <assunto> [trailer...]
  local arq="$1" assunto="$2"; shift 2
  { printf '%s\n' "$assunto"
    if [ "$#" -gt 0 ]; then printf '\n'; printf '%s\n' "$@"; fi
  } > "$arq"
}

_fx_plano() { # <pasta do trabalho> <expx_tool>
  local p="$1" ferramenta="$2"
  mkdir -p "$p/sprint-01" || return 1
  cat > "$p/sprint-01/tasks.md" <<EOF
---
expx_schema: 1
expx_tool: $ferramenta
kind: plano
trabalho_id: ft-rec
sprint:
  titulo: Sprint de teste
  status: concluido
fases:
  - id: F-01.1
    titulo: Fase
    tasks: [T-01.01]
tasks:
  - id: T-01.01
    titulo: Task T-01.01
    fase: F-01.1
    status: concluida
    objetivo: Ajustar o painel
    suite: verde
    arquivos:
      cria: [tests/ui/ft-rec.test.ts]
      altera: [src/painel.ts]
    teste_integracao: integra o painel
    teste_funcional: painel funciona
---

# Plano

Prosa do plano.
EOF
  cat > "$p/ORQUESTRADOR.md" <<EOF
---
expx_schema: 1
expx_tool: $ferramenta
kind: orquestrador
trabalho_id: ft-rec
---

# Orquestrador

Mapa de execução da feature.
EOF
}

# Fases do ENTREGA: aberto (pre-e2: portao null), pronto (pre-e6: portao pronto
# e portao_sha = pre-e2) e entregue (e8).
_fx_entrega() { # <legado:0|1> <e1_curto> <b0_sha> <fase> <portao_sha|->
  local legado="$1" e1="$2" b0="$3" fase="$4" portao="$5" estado=aberto pg=pronto pushed=false ent=null
  if [ "$fase" = aberto ]; then pg=null; fi
  if [ "$fase" = entregue ]; then estado=entregue; pushed=true; ent=2026-10-02; fi
  mkdir -p docs/entregas/ft-rec || return 1
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: %s\nkind: entrega\ntrabalho_id: ft-rec\n' "${fx_ferramenta:-sprintx}"
    printf 'entregue_por: mergex\nestado: %s\nversionado: true\n' "$estado"
    printf 'branch: feature/ft-rec\nbranch_base: main\n'
    if [ "$legado" != 1 ]; then
      printf 'base_validada_sha: %s\norigem_base: registrada_e0\nreconciliacoes: []\n' "$b0"
      if [ "$fase" = aberto ]; then printf 'portao_sha: null\n'; else printf 'portao_sha: %s\n' "$portao"; fi
    fi
    printf 'commits:\n  - seq: 1\n    task: T-01.01\n    commit: %s\n' "$e1"
    printf 'modulo_afetado: []\narquivos_alterados: []\nfaixa_atencao: []\nraio: null\n'
    printf 'atencao:\n  olho_obrigatorio: 0\n  leitura_rapida: 0\n  dispensavel: 0\n'
    printf 'portao: %s\nfalhas_portao: []\ncausa: null\ndesvios: []\n' "$pg"
    printf 'push_feito: %s\npr_url: null\npr_estado: null\n' "$pushed"
    printf 'criado_em: 2026-10-01\natualizado_em: 2026-10-02\nentregue_em: %s\n' "$ent"
    printf -- '---\n\n# Entrega\n\nProsa da entrega.\n'
  } > docs/entregas/ft-rec/ENTREGA.md
}

FX_ESPECIAL="tests/ui/caso com espaço e ação d'água.test.tsx"
_FX_VARIANTES=" base_removeu integracao_removeu renomeado resolucao_igual_base m_um_pai pais_trocados fora_primeiro_pai m_sem_integra_base m_com_metodo caminho_especial base_alterou diretorio substring_declarado tipo_mudou b0_fora_b1 b0_fora_p1 b0_ref entrega_kind entrega_trabalho entrega_sem_branch_base entrega_sem_chaves entrega_dup entrega_reconc_cheia entrega_bloco entrega_crlf entrega_bloco_vazia entrega_bloco_comentario entrega_bloco_escalar entrega_bloco_col0 entrega_bloco_estranho entrega_aspas_d entrega_aspas_s entrega_symlink plano_symlink merge_area_base plano_nl plano_tab duas_pastas runx entrega_no_merge criss_cross merge_previo base_com_pai lateral_reverte entrega_sem_base entrega_base_vazia entrega_base_null entrega_base_aspas "

# Reescreve o ENTREGA.md da fixture com um sed e o põe no índice (sem sed -i).
_fx_entrega_sed() { # <expressão> | -e <expressão>...
  local e=docs/entregas/ft-rec/ENTREGA.md
  sed "$@" "$e" > "$e.tmp" && mv "$e.tmp" "$e" && git add "$e"
}

# Commita a árvore do índice com os pais dados, sem passar pelo `git commit`
# (que faria um merge de dois pais). Encerra o merge em andamento.
# _fx_commit_arvore <msg> <pai>...
_fx_commit_arvore() {
  local msg="$1" arvore c; shift
  arvore="$(git write-tree)"
  git merge --quit
  c="$(git commit-tree "$arvore" $(printf -- '-p %s ' "$@") -F "$msg")"
  git update-ref HEAD "$c"
}

# Corpo da montagem. Roda num `bash` filho com `set -e` (ver _fx_monta): qualquer
# comando que falhe aborta a fixture, mesmo quando o chamador usa `||`.
# _fx_corpo <dir> <legado:0|1> <com_commit:0|1> <msg> <arquivo-de-shas> [variante]
_fx_corpo() {
  local dir="$1" legado="$2" com_commit="$3" msg="$4" shas="$5" var="${6:-}"
  local e1 e1c pre2 FX_B0 FX_P1 FX_B1 FX_M lateral
  local fx_pasta=docs/sprintx/features/ft-rec fx_ferramenta=sprintx nl='
' tab='	'
  if [ "$var" = runx ]; then fx_pasta=docs/manutencao/ft-rec; fx_ferramenta=runx; fi
  {
    cd "$dir"
    git init -q -b main
    git config user.email teste@expx.local
    git config user.name "Teste Expx"
    git config core.autocrlf false
    git config core.quotepath false
    git config commit.gpgsign false

    # base_com_pai: um commit raiz antes de B0
    if [ "$var" = base_com_pai ]; then
      printf '# Raiz\n' > RAIZ.md
      git add RAIZ.md
      _fx_msg "$msg" "chore: raiz"
      _fx_commit "$msg"
    fi
    # lateral_reverte: um commit raiz com o README.md antigo antes de B0 (B0
    # o reescreve); o ramo lateral parte daqui e o carrega intacto
    if [ "$var" = lateral_reverte ]; then
      printf '# Projeto antigo\n' > README.md
      git add README.md
      _fx_msg "$msg" "chore: raiz com o README.md antigo"
      _fx_commit "$msg"
    fi

    # main: B0
    mkdir -p src
    printf 'export const versao = 1;\nexport const titulo = "Painel";\nexport const rodape = "fim";\n' > src/painel.ts
    printf '# Projeto\n' > README.md
    git add src/painel.ts README.md
    _fx_msg "$msg" "chore: base inicial"
    _fx_commit "$msg"
    FX_B0="$(git rev-parse HEAD)"

    # feature: plano
    fixture_switch_exato feature/ft-rec -c feature/ft-rec
    _fx_plano "$fx_pasta" "$fx_ferramenta"
    git add "$fx_pasta/sprint-01/tasks.md" "$fx_pasta/ORQUESTRADOR.md"
    _fx_msg "$msg" "docs: plano da feature ft-rec"
    _fx_commit "$msg"

    # E1 da T-01.01: cria o teste e altera a linha de titulo
    mkdir -p tests/ui
    printf 'export const casoPainel = "ft-rec";\n' > tests/ui/ft-rec.test.ts
    printf 'export const versao = 1;\nexport const titulo = "Painel da feature";\nexport const rodape = "fim";\n' > src/painel.ts
    git add tests/ui/ft-rec.test.ts src/painel.ts
    _fx_msg "$msg" "feat(ft-rec): ajusta o painel" "Task: T-01.01" "Trabalho: ft-rec"
    bash "$_FXR_CONTRATO" --validar-e1 --trabalho ft-rec --task T-01.01 --arquivo "$msg" >/dev/null
    _fx_commit "$msg"
    e1="$(git rev-parse HEAD)"

    # pre-e2: ENTREGA aberta, portao null. O E2 avalia este HEAD.
    e1c="$(git rev-parse --short "$e1")"
    _fx_entrega "$legado" "$e1c" "$FX_B0" aberto -
    git add docs/entregas/ft-rec/ENTREGA.md
    _fx_msg "$msg" "docs(mergex): abre a entrega" "Trabalho: ft-rec" "Metodo: pre-e2"
    bash "$_FXR_CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint pre-e2 --arquivo "$msg" >/dev/null
    _fx_commit "$msg"
    pre2="$(git rev-parse HEAD)"

    # pre-e6: portao pronto + portao_sha = pre-e2; ATENCAO, PR e QA-PACOTE
    _fx_entrega "$legado" "$e1c" "$FX_B0" pronto "$pre2"
    printf '# Atenção\n\nClassificação do diff.\n' > docs/entregas/ft-rec/ATENCAO.md
    printf '# PR\n\nDescrição do pull request.\n' > docs/entregas/ft-rec/PR.md
    printf '# QA\n\nPacote para o QA.\n' > docs/entregas/ft-rec/QA-PACOTE.md
    git add docs/entregas/ft-rec/ENTREGA.md docs/entregas/ft-rec/ATENCAO.md docs/entregas/ft-rec/PR.md docs/entregas/ft-rec/QA-PACOTE.md
    _fx_msg "$msg" "docs(mergex): registra o portao e o pacote" "Trabalho: ft-rec" "Metodo: pre-e6"
    bash "$_FXR_CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint pre-e6 --arquivo "$msg" >/dev/null
    _fx_commit "$msg"

    # e8: entrega fechada
    _fx_entrega "$legado" "$e1c" "$FX_B0" entregue "$pre2"
    git add docs/entregas/ft-rec/ENTREGA.md
    _fx_msg "$msg" "docs(mergex): fecha a entrega" "Trabalho: ft-rec" "Metodo: e8"
    bash "$_FXR_CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint e8 --arquivo "$msg" >/dev/null
    _fx_commit "$msg"
    FX_P1="$(git rev-parse HEAD)"

    # histórico com merge na feature antes do merge de integração (P1 muda)
    case "$var" in
      criss_cross)
        # dois ramos laterais da base, integrados por merges distintos dos
        # dois lados: os dois são merge-bases de P1 e B1
        fixture_switch_exato lado1 -c lado1 "$FX_B0"
        mkdir -p docs/lateral
        printf '# Lateral um\n' > docs/lateral/um.md
        git add docs/lateral/um.md
        _fx_msg "$msg" "docs: lateral um"
        _fx_commit "$msg"
        fixture_switch_exato lado2 -c lado2 "$FX_B0"
        mkdir -p docs/lateral
        printf '# Lateral dois\n' > docs/lateral/dois.md
        git add docs/lateral/dois.md
        _fx_msg "$msg" "docs: lateral dois"
        _fx_commit "$msg"
        fixture_switch_exato feature/ft-rec feature/ft-rec
        git merge -q --no-ff -m "merge: lateral um na feature" lado1
        git merge -q --no-ff -m "merge: lateral dois na feature" lado2
        FX_P1="$(git rev-parse HEAD)"
        fixture_switch_exato main main
        git merge -q --no-ff -m "merge: lateral um na base" lado1
        git merge -q --no-ff -m "merge: lateral dois na base" lado2
        fixture_switch_exato feature/ft-rec feature/ft-rec ;;
      merge_previo)
        # a feature integra uma main intermediária num merge comum
        fixture_switch_exato main main
        mkdir -p docs
        printf '# Intermediário\n' > docs/intermediario.md
        git add docs/intermediario.md
        _fx_msg "$msg" "docs: base intermediaria"
        _fx_commit "$msg"
        fixture_switch_exato feature/ft-rec feature/ft-rec
        git merge -q --no-ff -m "merge: traz a base intermediaria" main
        FX_P1="$(git rev-parse HEAD)" ;;
      lateral_reverte)
        # ramo lateral anterior a B0: parte da raiz, sem mudança própria (um
        # commit vazio, para o inventário de M não ganhar caminho novo), com o
        # README.md antigo. A feature o integra num merge comum e a resolução
        # desfaz o README.md para a versão da raiz: esse merge vira P1
        fixture_switch_exato lateral -c lateral "$FX_B0^"
        _fx_msg "$msg" "chore: ramo lateral anterior a B0"
        git commit -q --allow-empty -F "$msg"
        fixture_switch_exato feature/ft-rec feature/ft-rec
        git merge -q --no-ff --no-commit lateral
        [ -f .git/MERGE_HEAD ]
        git show lateral:README.md > README.md
        git add README.md
        _fx_msg "$msg" "merge: traz o ramo lateral e desfaz o README.md"
        _fx_commit "$msg"
        FX_P1="$(git rev-parse HEAD)" ;;
    esac

    # main avança: dois testes novos + mesma linha de painel.ts
    fixture_switch_exato main main
    mkdir -p tests/ui
    printf 'export const versao = 1;\nexport const titulo = "Painel da base";\nexport const rodape = "fim";\n' > src/painel.ts
    printf 'export const casoCompliance = "base";\n' > tests/ui/compliance-ksmv-primitives.test.tsx
    printf 'export const casoAttendance = "base";\n' > tests/ui/attendance-ksmv-primitives.test.tsx
    git add src/painel.ts tests/ui/compliance-ksmv-primitives.test.tsx tests/ui/attendance-ksmv-primitives.test.tsx
    case "$var" in
      base_removeu) git rm -q README.md ;;
      renomeado) git mv README.md LEIAME.md ;;
      caminho_especial)
        printf 'export const casoEspecial = "base";\n' > "$FX_ESPECIAL"
        git add -- "$FX_ESPECIAL" ;;
      base_alterou|lateral_reverte)
        printf '# Projeto\n\nSeção da base.\n' > README.md
        git add README.md ;;
      diretorio)
        mkdir -p tests/base
        printf 'export const x = 1;\n' > tests/base/x.ts
        printf 'export const y = 1;\n' > tests/base/y.ts
        printf 'export const z = 1;\n' > tests/base/z.ts
        git add tests/base ;;
      tipo_mudou)
        rm -f README.md; ln -s src/painel.ts README.md
        git add README.md ;;
      # nomes que a base traz para a pasta do trabalho (fora do diff B1..M)
      plano_nl)
        mkdir -p "docs/sprintx/features/ft-rec/foo$nl${FX_NL_ALVO:?FX_NL_ALVO absoluto}"
        printf 'nada\n' > docs/sprintx/features/ft-rec/foo
        printf '# vazio\n' > "docs/sprintx/features/ft-rec/foo$nl$FX_NL_ALVO/tasks.md"
        git add -A -- docs/sprintx/features/ft-rec ;;
      plano_tab)
        mkdir -p docs/sprintx/features/ft-rec
        printf 'nada\n' > "docs/sprintx/features/ft-rec/tab${tab}no nome.md"
        git add -A -- docs/sprintx/features/ft-rec ;;
      duas_pastas)
        mkdir -p docs/ft-rec
        printf '# Notas\n' > docs/ft-rec/notas.md
        git add docs/ft-rec/notas.md ;;
    esac
    _fx_msg "$msg" "feat: primitivas ksmv e titulo da base"
    _fx_commit "$msg"
    FX_B1="$(git rev-parse HEAD)"

    fixture_switch_exato feature/ft-rec feature/ft-rec

    # variantes do ENTREGA.md e de B0: num commit da feature ANTES do merge
    # (passa a ser P1), porque o merge de integração não pode mexer no
    # ENTREGA.md (guarda estrutura[entrega]); M herda o ENTREGA.md de P1
    case "$var" in
      b0_fora_b1) _fx_entrega_sed "s/^base_validada_sha: .*/base_validada_sha: $(git rev-parse "$FX_P1~4")/" ;;
      b0_fora_p1) _fx_entrega_sed "s/^base_validada_sha: .*/base_validada_sha: $FX_B1/" ;;
      b0_ref) _fx_entrega_sed 's/^base_validada_sha: .*/base_validada_sha: main/' ;;
      entrega_kind) _fx_entrega_sed 's/^kind: entrega$/kind: outro/' ;;
      entrega_trabalho) _fx_entrega_sed 's/^trabalho_id: ft-rec$/trabalho_id: outro/' ;;
      entrega_sem_branch_base) _fx_entrega_sed '/^branch_base:/d' ;;
      entrega_sem_chaves)
        _fx_entrega_sed -e '/^reconciliacoes:/d' -e '/^causa:/d' -e '/^push_feito:/d' -e '/^entregue_em:/d' \
          -e '/^portao_sha:/d' -e '/^falhas_portao:/d' -e '/^atualizado_em:/d' \
          -e 's/^  dispensavel: 0$/  dispensavel: 0\n  estado: interno\n  causa: aninhada\n  push_feito: aninhado/' ;;
      entrega_dup) _fx_entrega_sed 's/^estado: .*/&\nestado: aberto/' ;;
      entrega_reconc_cheia)
        _fx_entrega_sed 's/^reconciliacoes: \[\]$/reconciliacoes:\n  - numero: 1\n    arquivo: RECONCILIACAO-BASE-001.md\n    b1_sha: 1111111111111111111111111111111111111111\n    m_sha: 2222222222222222222222222222222222222222/' ;;
      entrega_bloco)
        _fx_entrega_sed -e 's/^falhas_portao: \[\]$/falhas_portao:\n  - v1\n  - v7/' -e 's/^causa: null$/causa:\n  - antiga/' ;;
      entrega_crlf) _fx_entrega_sed 's/$/\r/' ;;
      entrega_bloco_vazia) _fx_entrega_sed 's/^falhas_portao: \[\]$/falhas_portao:\n  - v1\n\n  - v7/' ;;
      entrega_bloco_comentario) _fx_entrega_sed 's/^falhas_portao: \[\]$/falhas_portao:\n  - v1\n# comentario na coluna 0\n  - v7/' ;;
      entrega_bloco_escalar) _fx_entrega_sed 's/^causa: null$/causa: |\n  primeira linha\n\n  terceira linha/' ;;
      entrega_bloco_col0) _fx_entrega_sed 's/^falhas_portao: \[\]$/falhas_portao:\n- v1\n- v7/' ;;
      entrega_bloco_estranho) _fx_entrega_sed 's/^falhas_portao: \[\]$/falhas_portao:\n  - v1\nsolto sem indentacao/' ;;
      entrega_aspas_d) _fx_entrega_sed 's/^estado: /"estado": /' ;;
      entrega_aspas_s) _fx_entrega_sed "s/^portao: /'portao': /" ;;
      entrega_sem_base) _fx_entrega_sed '/^base_validada_sha:/d' ;;
      entrega_base_vazia) _fx_entrega_sed 's/^base_validada_sha: .*/base_validada_sha:/' ;;
      entrega_base_null) _fx_entrega_sed 's/^base_validada_sha: .*/base_validada_sha: null/' ;;
      entrega_base_aspas) _fx_entrega_sed 's/^base_validada_sha:/"base_validada_sha":/' ;;
      entrega_symlink)
        git mv docs/entregas/ft-rec/ENTREGA.md docs/entregas/ft-rec/ENTREGA-real.md
        ln -s ENTREGA-real.md docs/entregas/ft-rec/ENTREGA.md
        git add docs/entregas/ft-rec/ENTREGA.md ;;
    esac
    if ! git diff --cached --quiet; then
      _fx_msg "$msg" "docs(mergex): ajusta a entrega" "Trabalho: ft-rec"
      _fx_commit "$msg"
      FX_P1="$(git rev-parse HEAD)"
    fi

    # merge com conflito em src/painel.ts
    git merge --no-ff --no-commit main >/dev/null 2>&1 || true
    [ -f .git/MERGE_HEAD ]
    printf 'export const versao = 1;\nexport const titulo = "Painel da base e da feature";\nexport const rodape = "fim";\n' > src/painel.ts
    # os dois testes novos ajustados na resolução
    printf 'export const casoCompliance = "base";\nexport const ajusteCompliance = "ft-rec";\n' > tests/ui/compliance-ksmv-primitives.test.tsx
    printf 'export const casoAttendance = "base";\nexport const ajusteAttendance = "ft-rec";\n' > tests/ui/attendance-ksmv-primitives.test.tsx
    git add src/painel.ts tests/ui/compliance-ksmv-primitives.test.tsx tests/ui/attendance-ksmv-primitives.test.tsx
    case "$var" in
      base_removeu)
        git show "$FX_B0:README.md" > README.md
        git add README.md ;;
      integracao_removeu) git rm -q -f tests/ui/attendance-ksmv-primitives.test.tsx ;;
      resolucao_igual_base)
        git show "$FX_B1:tests/ui/attendance-ksmv-primitives.test.tsx" > tests/ui/attendance-ksmv-primitives.test.tsx
        git add tests/ui/attendance-ksmv-primitives.test.tsx ;;
      caminho_especial)
        printf 'export const casoEspecial = "base";\nexport const ajusteEspecial = "ft-rec";\n' > "$FX_ESPECIAL"
        git add -- "$FX_ESPECIAL" ;;
      base_alterou|lateral_reverte)
        printf '# Projeto\n\nSeção da base, ajustada para a feature.\n' > README.md
        git add README.md ;;
      diretorio)
        printf 'export const x = 2;\n' > tests/base/x.ts
        printf 'export const y = 2;\n' > tests/base/y.ts
        git add tests/base/x.ts tests/base/y.ts ;;
      substring_declarado)
        printf 'prefixo de um caminho declarado\n' > tests/ui/ft-rec.test
        git add tests/ui/ft-rec.test ;;
      tipo_mudou)
        rm -f README.md; ln -s tests/ui/ft-rec.test.ts README.md
        git add README.md ;;
      # o próprio merge reescreve o ENTREGA.md (o que a guarda estrutura[entrega] barra)
      entrega_no_merge) _fx_entrega_sed "s/^base_validada_sha: .*/base_validada_sha: $(git rev-parse "$FX_P1~4")/" ;;
      plano_symlink)
        ln -s sprint-01/tasks.md docs/sprintx/features/ft-rec/LINK.md
        git add docs/sprintx/features/ft-rec/LINK.md ;;
      merge_area_base)
        mkdir -p docs/sprintx/features/ft-rec/base
        printf '# Notas\n' > docs/sprintx/features/ft-rec/base/notas.md
        git add docs/sprintx/features/ft-rec/base/notas.md ;;
    esac
    [ -z "$(git diff --name-only --diff-filter=U)" ]

    if [ "$com_commit" = 1 ]; then
      case "$var" in
        m_sem_integra_base) _fx_msg "$msg" "merge: integra a main na feature ft-rec" "Trabalho: ft-rec" ;;
        m_com_metodo) _fx_msg "$msg" "merge: integra a main na feature ft-rec" "Trabalho: ft-rec" "Integra-base: $FX_B1" "Metodo: e8" ;;
        *) _fx_msg "$msg" "merge: integra a main na feature ft-rec" "Trabalho: ft-rec" "Integra-base: $FX_B1" ;;
      esac
      case "$var" in
        m_um_pai) _fx_commit_arvore "$msg" "$FX_P1" ;;
        pais_trocados) _fx_commit_arvore "$msg" "$FX_B1" "$FX_P1" ;;
        fora_primeiro_pai)
          # a integração válida (P1, B1) fica de lado; HEAD a traz como 2º pai
          _fx_commit_arvore "$msg" "$FX_P1" "$FX_B1"
          lateral="$(git rev-parse HEAD)"
          git update-ref HEAD "$FX_P1"
          _fx_msg "$msg" "merge: traz o ramo lateral" "Trabalho: ft-rec" "Integra-base: $lateral"
          git commit-tree "$lateral^{tree}" -p "$FX_P1" -p "$lateral" -F "$msg" > "$msg.c"
          git update-ref HEAD "$(cat "$msg.c")"
          rm -f "$msg.c" ;;
        *) _fx_commit "$msg" ;;
      esac
      [ -z "$(git status --porcelain)" ]
      FX_M="$(git rev-parse HEAD)"
      printf '%s %s %s %s\n' "$FX_B0" "$FX_P1" "$FX_B1" "$FX_M" > "$shas"
    else
      printf '%s %s %s -\n' "$FX_B0" "$FX_P1" "$FX_B1" > "$shas"
    fi
  }
}

# _fx_monta <dir> <legado:0|1> <com_commit:0|1>
_fx_monta() {
  local dir="$1" legado="$2" com_commit="$3" msg rc var="${FX_VARIANTE:-}"
  if [ -n "$var" ]; then
    case "$_FX_VARIANTES" in *" $var "*) ;; *) printf 'fixture: variante desconhecida: %s\n' "$var" >&2; return 1 ;; esac
  fi
  msg="$(mktemp)" || return 1
  mkdir -p "$dir" || return 1
  FX_NL_ALVO="${FX_NL_ALVO:-}" bash -c 'set -e; . "$1"; shift; _fx_corpo "$@"' _ \
    "$_FXR_LIB/fixture-reconciliacao.sh" "$dir" "$legado" "$com_commit" "$msg" "$msg.shas" "$var"
  rc=$?
  [ "$rc" -eq 0 ] || { rm -f "$msg" "$msg.shas"; return 1; }
  # os SHAs voltam do processo filho por arquivo
  read -r FX_B0 FX_P1 FX_B1 FX_M < "$msg.shas"
  [ "$FX_M" != - ] || FX_M=""
  rm -f "$msg" "$msg.shas"
  export FX_B0 FX_P1 FX_B1 FX_M
  FX_TRAB=ft-rec
  FX_ENTREGA=docs/entregas/ft-rec/ENTREGA.md
  FX_NOVO1=tests/ui/compliance-ksmv-primitives.test.tsx
  FX_NOVO2=tests/ui/attendance-ksmv-primitives.test.tsx
  FX_LISTA_VARIANTE="$FX_NOVO1
$FX_NOVO2"
  case "$var" in
    base_removeu|renomeado|base_alterou|tipo_mudou|lateral_reverte) FX_LISTA_VARIANTE="$FX_LISTA_VARIANTE
README.md" ;;
    diretorio) FX_LISTA_VARIANTE="$FX_LISTA_VARIANTE
tests/base/x.ts
tests/base/y.ts" ;;
    caminho_especial) FX_LISTA_VARIANTE="$FX_LISTA_VARIANTE
$FX_ESPECIAL"
      git -C "$dir" config core.quotepath true ;;
  esac
  export FX_TRAB FX_ENTREGA FX_NOVO1 FX_NOVO2 FX_LISTA_VARIANTE FX_ESPECIAL
}

fx_cenario() {
  local dir="$1" legado=0
  [ -n "$dir" ] || return 64
  [ "${2:-}" = legado ] && legado=1
  _fx_monta "$dir" "$legado" 1
}

fx_merge_sem_commit() {
  [ -n "${1:-}" ] || return 64
  _fx_monta "$1" 0 0
}

# ---------------------------------------------------------------------------
# Segunda base e artefatos forjados (--verificar)
# ---------------------------------------------------------------------------

# Biblioteca do artefato da própria skill (rb_emitir, rb_diff_sha, rb_ler).
_FXR_ARTEFATO="$(cd "$_FXR_LIB/../../.." && pwd)/.claude/skills/mergex/scripts/reconciliacao-artefato.sh"

_fx_segunda_corpo() { # <dir> <ajusta> <msg> <arquivo-de-shas>
  local dir="$1" ajusta="$2" msg="$3" shas="$4" b2
  local novo3=tests/ui/frequency-ksmv-primitives.test.tsx m1
  local novo1=tests/ui/compliance-ksmv-primitives.test.tsx novo2=tests/ui/attendance-ksmv-primitives.test.tsx
  cd "$dir"
  m1="$(git rev-parse feature/ft-rec)"
  fixture_switch_exato main main
  mkdir -p tests/ui
  printf 'export const casoFrequency = "base";\n' > "$novo3"
  git add "$novo3"
  case "$ajusta" in
    reajusta|descarta)
      printf 'export const casoCompliance = "base";\nexport const segundaBase = 2;\n' > "$novo1"
      git add "$novo1" ;;
    ressuscita) git rm -q "$novo1" ;;
  esac
  _fx_msg "$msg" "feat: primitiva ksmv de frequencia"
  _fx_commit "$msg"
  b2="$(git rev-parse HEAD)"
  fixture_switch_exato feature/ft-rec feature/ft-rec
  git merge --no-ff --no-commit main >/dev/null 2>&1 || true
  [ -f .git/MERGE_HEAD ]
  case "$ajusta" in
    ajusta|reajusta|descarta|ressuscita|esconde)
      printf 'export const casoFrequency = "base";\nexport const ajusteFrequency = "ft-rec";\n' > "$novo3"
      git add "$novo3" ;;
  esac
  case "$ajusta" in
    reajusta)
      printf 'export const casoCompliance = "base";\nexport const segundaBase = 2;\nexport const ajusteCompliance = "ft-rec";\n' > "$novo1"
      git add "$novo1" ;;
    # a resolução fica com a versão do M1: descarta a mudança (ou a remoção) da base
    descarta|ressuscita) git show "$m1:$novo1" > "$novo1"; git add "$novo1" ;;
    # o merge muda um caminho do 001 que a base não tocou
    esconde)
      printf 'export const casoAttendance = "base";\nexport const ajusteAttendance = "ft-rec";\nexport const produtoEscondido = 1;\n' > "$novo2"
      git add "$novo2" ;;
  esac
  [ -z "$(git diff --name-only --diff-filter=U)" ]
  _fx_msg "$msg" "merge: integra a main de novo na feature ft-rec" "Trabalho: ft-rec" "Integra-base: $b2"
  _fx_commit "$msg"
  printf '%s %s\n' "$b2" "$(git rev-parse HEAD)" > "$shas"
}

# fx_segunda_base <dir> [ajusta] — depois de fx_cenario, a base avança de novo
# (B2 cria FX_NOVO3) e é integrada à feature num segundo merge M2, que fica em
# HEAD, com `Trabalho: ft-rec` e `Integra-base: B2`. Com `ajusta`, a resolução
# ajusta FX_NOVO3; sem, M2 não muda nada do que veio da base. Com `reajusta`,
# além disso B2 altera FX_NOVO1 (já reconciliado no 001) e M2 o ajusta de
# novo (conflito resolvido pela fixture). Com `descarta`, B2 altera FX_NOVO1 e
# M2 fica com a versão do M1; com `ressuscita`, B2 remove FX_NOVO1 e M2 o traz
# de volta com a versão do M1; com `esconde`, B2 não toca FX_NOVO2 e M2 o muda.
# Nesses três, M2 também ajusta FX_NOVO3. Exporta FX_B2,
# FX_M2 e FX_NOVO3. Só cria commits: arquivos não rastreados ficam onde estão.
fx_segunda_base() {
  local dir="$1" ajusta="${2:-}" msg rc
  [ -n "$dir" ] || return 64
  msg="$(mktemp)" || return 1
  bash -c 'set -e; . "$1"; shift; _fx_segunda_corpo "$@"' _ \
    "$_FXR_LIB/fixture-reconciliacao.sh" "$dir" "$ajusta" "$msg" "$msg.shas"
  rc=$?
  [ "$rc" -eq 0 ] || { rm -f "$msg" "$msg.shas"; return 1; }
  read -r FX_B2 FX_M2 < "$msg.shas"
  rm -f "$msg" "$msg.shas"
  FX_NOVO3=tests/ui/frequency-ksmv-primitives.test.tsx
  export FX_B2 FX_M2 FX_NOVO3
}

_fx_terceira_corpo() { # <dir> <msg> <arquivo-de-shas>
  local dir="$1" msg="$2" shas="$3" b3 novo4=tests/ui/schedule-ksmv-primitives.test.tsx
  cd "$dir"
  fixture_switch_exato main main
  mkdir -p tests/ui
  printf 'export const casoSchedule = "base";\n' > "$novo4"
  git add "$novo4"
  _fx_msg "$msg" "feat: primitiva ksmv de agenda"
  _fx_commit "$msg"
  b3="$(git rev-parse HEAD)"
  fixture_switch_exato feature/ft-rec feature/ft-rec
  git merge --no-ff --no-commit main >/dev/null 2>&1 || true
  [ -f .git/MERGE_HEAD ]
  printf 'export const casoSchedule = "base";\nexport const ajusteSchedule = "ft-rec";\n' > "$novo4"
  git add "$novo4"
  [ -z "$(git diff --name-only --diff-filter=U)" ]
  _fx_msg "$msg" "merge: integra a main pela terceira vez na feature ft-rec" "Trabalho: ft-rec" "Integra-base: $b3"
  _fx_commit "$msg"
  printf '%s %s\n' "$b3" "$(git rev-parse HEAD)" > "$shas"
}

# fx_terceira_base <dir> — depois de fx_segunda_base, a base avança mais uma
# vez (B3 cria FX_NOVO4) e é integrada num terceiro merge M3, que fica em HEAD
# e ajusta FX_NOVO4; os demais caminhos ficam como em M2. Exporta FX_B3, FX_M3
# e FX_NOVO4. Só cria commits.
fx_terceira_base() {
  local dir="$1" msg rc
  [ -n "$dir" ] || return 64
  msg="$(mktemp)" || return 1
  bash -c 'set -e; . "$1"; shift; _fx_terceira_corpo "$@"' _ \
    "$_FXR_LIB/fixture-reconciliacao.sh" "$dir" "$msg" "$msg.shas"
  rc=$?
  [ "$rc" -eq 0 ] || { rm -f "$msg" "$msg.shas"; return 1; }
  read -r FX_B3 FX_M3 < "$msg.shas"
  rm -f "$msg" "$msg.shas"
  FX_NOVO4=tests/ui/schedule-ksmv-primitives.test.tsx
  export FX_B3 FX_M3 FX_NOVO4
}

# fx_persiste_reconciliacao <dir> — o checkpoint de método reconciliacao-base:
# commita o ENTREGA.md e os RECONCILIACAO-BASE-NNN.md da pasta da entrega, com
# a mensagem do contrato (Trabalho: + Metodo: reconciliacao-base).
fx_persiste_reconciliacao() {
  local dir="$1" msg rc
  [ -n "$dir" ] || return 64
  msg="$(mktemp)" || return 1
  ( cd "$dir" || exit 1
    git add -- docs/entregas/ft-rec/ENTREGA.md docs/entregas/ft-rec/RECONCILIACAO-BASE-[0-9][0-9][0-9].md || exit 1
    _fx_msg "$msg" "chore(mergex): persiste metodo reconciliacao-base" "Trabalho: ft-rec" "Metodo: reconciliacao-base"
    bash "$_FXR_CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint reconciliacao-base --arquivo "$msg" >/dev/null || exit 1
    git commit -q -F "$msg" )
  rc=$?
  rm -f "$msg"
  return "$rc"
}

# fx_emite_reconciliacao <dir> <numero> <b0> <m> [caminho...] — grava
# docs/entregas/ft-rec/RECONCILIACAO-BASE-<NNN>.md com rb_emitir: coerente e
# assinado, com P1 = M^1, B1 = M^2 e os campos de cada caminho tirados do Git.
# NÃO prova nada (é para forjar): status fora de A|M vira M, blob ausente vira
# 40 zeros. `anterior` e `origem_base` seguem o número (null/registrada_e0 no
# 001; o nome anterior/reconciliacao_anterior nos demais).
# Ambiente opcional: FX_ESTADO (ativa), FX_ORIGEM_BASE, FX_P1_SHA e FX_B1_SHA
# (só os escalares gravados; os campos seguem M^1/M^2), FX_FORJA_AWK (programa
# awk, -F/OFS = TAB, aplicado ao TSV de arquivos antes da emissão: colunas
# caminho status_base blob_b1 blob_m diff_b1_m_sha256 motivo).
fx_emite_reconciliacao() {
  local dir="$1" num="$2" b0="$3" m="$4"
  shift 4
  ( cd "$dir" || exit 1
    . "$_FXR_ARTEFATO" || exit 1
    t="$(mktemp -d)" || exit 1
    p1="$(git rev-parse "$m^1")" && b1="$(git rev-parse "$m^2")" || { rm -rf "$t"; exit 1; }
    nome="$(printf 'RECONCILIACAO-BASE-%03d.md' "$num")"
    if [ "$num" = 1 ]; then ant=null; ob=registrada_e0
    else ant="$(printf 'RECONCILIACAO-BASE-%03d.md' $((num - 1)))"; ob=reconciliacao_anterior; fi
    ob="${FX_ORIGEM_BASE:-$ob}"
    printf 'expx_tool\tsprintx\ntrabalho_id\tft-rec\nnumero\t%s\nanterior\t%s\nbranch\tfeature/ft-rec\nbranch_base\tmain\norigem_base\t%s\nb0_sha\t%s\np1_sha\t%s\nb1_sha\t%s\nm_sha\t%s\nestado\t%s\nregistrado_em\t2026-10-07\n' \
      "$num" "$ant" "$ob" "$b0" "${FX_P1_SHA:-$p1}" "${FX_B1_SHA:-$b1}" "$m" "${FX_ESTADO:-ativa}" > "$t/esc"
    : > "$t/arq"
    for f in "$@"; do
      st="$(git -c core.quotepath=false diff --no-renames --name-status -z "$b0" "$b1" -- ":(literal)$f" | tr '\0' '\n' | head -n1)"
      case "$st" in A|M) ;; *) st=M ;; esac
      bb="$(git rev-parse -q --verify "$b1:$f")" || bb=0000000000000000000000000000000000000000
      bm="$(git rev-parse -q --verify "$m:$f")" || bm=0000000000000000000000000000000000000000
      ds="$(rb_diff_sha "$b1" "$m" "$f")" || { rm -rf "$t"; exit 1; }
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$bb" "$bm" "$ds" "forjado pela fixture" >> "$t/arq"
    done
    if [ -n "${FX_FORJA_AWK:-}" ]; then
      awk -F'\t' -v OFS='\t' "$FX_FORJA_AWK" "$t/arq" > "$t/arq2" && mv "$t/arq2" "$t/arq" || { rm -rf "$t"; exit 1; }
    fi
    mkdir -p docs/entregas/ft-rec
    RB_ERRO=""
    rb_emitir "docs/entregas/ft-rec/$nome" "$t/esc" "$t/arq" || { printf 'fixture: %s\n' "$RB_ERRO" >&2; rm -rf "$t"; exit 1; }
    rm -rf "$t"
  )
}

# fx_forja_artefato <dir> <caminho>... — reescreve o RECONCILIACAO-BASE-001.md
# (B0 = FX_B0, M = FX_M) listando os caminhos dados, coerente e com assinatura
# válida, mesmo que nenhum seja elegível.
fx_forja_artefato() {
  local dir="$1"; shift
  fx_emite_reconciliacao "$dir" 1 "$FX_B0" "$FX_M" "$@"
}

# fx_entrega_sincroniza <dir> — reescreve, no ENTREGA.md do disco, a lista
# `reconciliacoes` a partir dos artefatos RECONCILIACAO-BASE-NNN.md presentes
# (na ordem do nome) e `base_validada_sha` com o b1_sha do último. Sem artefato:
# `reconciliacoes: []` e a base fica como está.
fx_entrega_sincroniza() {
  ( cd "$1" || exit 1
    . "$_FXR_ARTEFATO" || exit 1
    e=docs/entregas/ft-rec/ENTREGA.md; bloco='reconciliacoes:'; ultimo=""; n=0
    for a in docs/entregas/ft-rec/RECONCILIACAO-BASE-[0-9][0-9][0-9].md; do
      [ -f "$a" ] || continue
      lido="$(rb_ler "$a")" || exit 1
      num="$(printf '%s\n' "$lido" | awk -F'\t' '$1 == "escalar" && $2 == "numero" { print $3 }')"
      b1="$(printf '%s\n' "$lido" | awk -F'\t' '$1 == "escalar" && $2 == "b1_sha" { print $3 }')"
      m="$(printf '%s\n' "$lido" | awk -F'\t' '$1 == "escalar" && $2 == "m_sha" { print $3 }')"
      bloco="$bloco
  - numero: $num
    arquivo: ${a##*/}
    b1_sha: $b1
    m_sha: $m"
      ultimo="$b1"; n=$((n + 1))
    done
    [ "$n" -gt 0 ] || bloco='reconciliacoes: []'
    BLOCO="$bloco" B1="$ultimo" awk '
      NR == 1 { print; fm = 1; next }
      fm && /^---/ { fm = 0; print; next }
      fm && /^reconciliacoes:/ { print ENVIRON["BLOCO"]; pula = 1; next }
      fm && pula && /^[ \t-]/ { next }
      { pula = 0 }
      fm && /^base_validada_sha:/ && ENVIRON["B1"] != "" { print "base_validada_sha: " ENVIRON["B1"]; next }
      { print }
    ' "$e" > "$e.fx" && cat "$e.fx" > "$e" && rm -f "$e.fx"
  )
}

# fx_entrega_chaves_legado <dir> — no ENTREGA.md legado do disco, acrescenta
# antes do fechamento as chaves que um registro legado grava
# (base_validada_sha, origem_base: inferida_legado, reconciliacoes, portao_sha:
# null) e sincroniza a lista e a base com os artefatos presentes. Para forjar.
fx_entrega_chaves_legado() {
  ( cd "$1" || exit 1
    e=docs/entregas/ft-rec/ENTREGA.md
    awk '
      NR == 1 { print; fm = 1; next }
      fm && /^---/ { print "base_validada_sha: pendente"; print "origem_base: inferida_legado"; print "reconciliacoes: []"; print "portao_sha: null"; fm = 0 }
      { print }
    ' "$e" > "$e.fx" && cat "$e.fx" > "$e" && rm -f "$e.fx"
  ) && fx_entrega_sincroniza "$1"
}

# ---------------------------------------------------------------------------
# Validade do portão (commits depois de portao_sha)
# ---------------------------------------------------------------------------

# _fx_commit_metodo_msg <checkpoint> <assunto> — commita o índice com
# `Trabalho: ft-rec` e `Metodo: <checkpoint>`, validado pelo contrato. Roda no
# cwd (o repositório da fixture).
_fx_commit_metodo_msg() {
  local cp="$1" assunto="$2" msg rc
  msg="$(mktemp)" || return 1
  _fx_msg "$msg" "$assunto" "Trabalho: ft-rec" "Metodo: $cp"
  bash "$_FXR_CONTRATO" --validar-metodo --trabalho ft-rec --checkpoint "$cp" --arquivo "$msg" >/dev/null \
    && git commit -q -F "$msg"
  rc=$?
  rm -f "$msg"
  return "$rc"
}

# fx_portao_em <dir> <rev> — grava `portao: pronto` e `portao_sha: <rev
# resolvido para o SHA completo>` no ENTREGA.md (a revisão é resolvida ANTES do
# commit) e commita só o ENTREGA.md como checkpoint de método pre-e6.
fx_portao_em() {
  local dir="$1" rev="$2"
  [ -n "$dir" ] && [ -n "$rev" ] || return 64
  ( cd "$dir" || exit 1
    sha="$(git rev-parse --verify -q "$rev^{commit}")" || exit 1
    e=docs/entregas/ft-rec/ENTREGA.md
    SHA="$sha" awk '
      NR == 1 { print; fm = 1; next }
      fm && /^---/ {
        if (!feito) { print "portao: pronto"; print "portao_sha: " ENVIRON["SHA"] }
        fm = 0; print; next
      }
      fm && /^portao_sha:/ { next }
      fm && /^portao:/ { print "portao: pronto"; print "portao_sha: " ENVIRON["SHA"]; feito = 1; next }
      { print }
    ' "$e" > "$e.fx" && cat "$e.fx" > "$e" && rm -f "$e.fx" || exit 1
    git add -- "$e" || exit 1
    _fx_commit_metodo_msg pre-e6 "docs(mergex): registra o portao" )
}

# fx_portao_sem_sha <dir> — `portao: pronto` e nenhuma linha portao_sha no
# ENTREGA.md (entrega legada), commitado como pre-e6.
fx_portao_sem_sha() {
  local dir="$1"
  [ -n "$dir" ] || return 64
  ( cd "$dir" || exit 1
    e=docs/entregas/ft-rec/ENTREGA.md
    awk '
      NR == 1 { print; fm = 1; next }
      fm && /^---/ { if (!feito) print "portao: pronto"; fm = 0; print; next }
      fm && /^portao_sha:/ { next }
      fm && /^portao:/ { print "portao: pronto"; feito = 1; next }
      { print }
    ' "$e" > "$e.fx" && cat "$e.fx" > "$e" && rm -f "$e.fx" || exit 1
    git add -- "$e" || exit 1
    _fx_commit_metodo_msg pre-e6 "docs(mergex): portao sem sha" )
}

# fx_commit_metodo <dir> <checkpoint> <caminho>... — acrescenta uma linha a
# cada caminho (criando o diretório) e commita como checkpoint de método.
fx_commit_metodo() {
  local dir="$1" cp="$2"
  [ -n "$dir" ] && [ -n "$cp" ] && [ "$#" -ge 3 ] || return 64
  shift 2
  ( cd "$dir" || exit 1
    for f in "$@"; do
      mkdir -p "$(dirname "$f")" || exit 1
      printf 'linha de %s\n' "$cp" >> "$f" || exit 1
      git add -- "$f" || exit 1
    done
    _fx_commit_metodo_msg "$cp" "docs(mergex): checkpoint $cp" )
}

# fx_commit_solto <dir> — um commit num ramo novo a partir de FX_B0, fora da
# história de HEAD; imprime o SHA e volta para feature/ft-rec.
fx_commit_solto() {
  local dir="$1"
  [ -n "$dir" ] && [ -n "${FX_B0:-}" ] || return 64
  ( cd "$dir" || exit 1
    n=1; while git rev-parse -q --verify "refs/heads/fx-solto-$n" >/dev/null; do n=$((n + 1)); done
    fixture_switch_exato "fx-solto-$n" -c "fx-solto-$n" "$FX_B0" || exit 1
    printf '# solto\n' > SOLTO.md
    git add SOLTO.md || exit 1
    git commit -q -m "chore: commit solto" || exit 1
    sha="$(git rev-parse HEAD)" || exit 1
    fixture_switch_exato feature/ft-rec feature/ft-rec || exit 1
    printf '%s\n' "$sha" )
}

# ---------------------------------------------------------------------------
# Barreira de push (DM-184): remoto bare local e push real
# ---------------------------------------------------------------------------

# Validador de push da própria skill: o padrão do chamador mínimo.
_FXR_PORTAO_PUSH="$(cd "$_FXR_LIB/../../.." && pwd)/.claude/skills/mergex/scripts/portao-push.sh"

# fx_remoto_bare <dir> — cria `remoto.git` bare ao lado de <dir> (no mesmo
# diretório pai, que é o temporário do teste), aponta o `origin` do repositório
# <dir> para ele e exporta FX_REMOTO (caminho absoluto). Nunca toca rede nem o
# remoto de outro repositório. Falha se o remoto já existe.
fx_remoto_bare() {
  local dir="$1" r
  [ -n "$dir" ] && [ -e "$dir/.git" ] || return 64
  r="$(cd "$dir/.." && pwd)/remoto.git" || return 1
  [ ! -e "$r" ] || return 1
  git init -q --bare "$r" || return 1
  if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$dir" remote set-url origin "$r" || return 1
  else
    git -C "$dir" remote add origin "$r" || return 1
  fi
  FX_REMOTO="$r"
  export FX_REMOTO
}

# _fx_pre_push_minimo <dir> <portao-push> — o chamador mínimo da fixture (o
# oficial, com marcador e ativação pelo E0, é da Task 15): um `pre-push` que só
# repassa a entrada padrão ao validador de push e propaga o código de saída.
# Fica em <diretório Git comum>/hooks-fx, com core.hooksPath LOCAL do
# repositório de teste apontando para ele (um hooksPath global não o desvia).
_fx_pre_push_minimo() {
  local dir="$1" pp="$2" hd
  hd="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)/hooks-fx" || return 1
  mkdir -p "$hd" || return 1
  { printf '#!/usr/bin/env bash\n# chamador mínimo da fixture de teste\n'
    printf 'exec bash %q --pre-push "$@"\n' "$pp"
  } > "$hd/pre-push" || return 1
  chmod +x "$hd/pre-push" || return 1
  git -C "$dir" config core.hooksPath "$hd"
}

# fx_push_real <dir> <args do git push>... — roda `git push <args>` REAL no
# repositório <dir>, com o pre-push apontando para FX_PORTAO_PUSH (padrão: o
# portao-push.sh da skill). Imprime:
#   rc=<código do git push>
#   ref=<SHA da ref FX_PUSH_REF no `origin` depois do push | ->
#   stderr=<arquivo com o stderr do push, no diretório Git comum de <dir>>
# FX_PUSH_REF padrão: refs/heads/feature/ft-rec. rc 1 se o chamador não instala.
fx_push_real() {
  local dir="$1"
  [ -n "$dir" ] && [ "$#" -ge 2 ] || return 64
  _fx_pre_push_minimo "$dir" "${FX_PORTAO_PUSH:-$_FXR_PORTAO_PUSH}" || return 1
  _fx_push "$@"
}

# fx_push_efetivo <dir> <args do git push>... — o mesmo push REAL e a mesma
# saída de fx_push_real, SEM instalar o chamador mínimo nem tocar
# core.hooksPath: quem decide é o pre-push do diretório efetivo do Git (`git
# rev-parse --git-path hooks`), o que o E0 instalou.
fx_push_efetivo() {
  [ -n "${1:-}" ] && [ "$#" -ge 2 ] || return 64
  _fx_push "$@"
}

# _fx_push <dir> <args do git push>... — o núcleo dos dois: push e saída
_fx_push() {
  local dir="$1" rc ref err alvo="${FX_PUSH_REF:-refs/heads/feature/ft-rec}"
  shift
  err="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)/fx-push-stderr" || return 1
  git -C "$dir" push "$@" > /dev/null 2> "$err"; rc=$?
  ref="$(git -C "$dir" ls-remote origin "$alvo" 2>/dev/null | awk -v r="$alvo" '$2 == r { print $1 }')"
  printf 'rc=%s\nref=%s\nstderr=%s\n' "$rc" "${ref:--}" "$err"
}

# ---------------------------------------------------------------------------
# Ativação do pre-push (Task 15): worktree vinculada e hooks de terceiro
# ---------------------------------------------------------------------------

# fx_worktree_vinculada <dir> — cria `<dir>-wt`, worktree vinculada de <dir>
# com feature/ft-rec (o `.git` dela é arquivo; o diretório Git comum é o de
# <dir>). O checkout principal fica destacado no mesmo commit, sem mudar
# arquivo nenhum. Exporta FX_WT (caminho absoluto). Falha se `<dir>-wt` existe.
fx_worktree_vinculada() {
  local dir="$1" wt
  [ -n "$dir" ] && [ -e "$dir/.git" ] || return 64
  wt="$(cd "$dir/.." && pwd)/$(basename "$dir")-wt" || return 1
  [ ! -e "$wt" ] || return 1
  git -C "$dir" switch -q --detach || return 1
  git -C "$dir" worktree add -q "$wt" feature/ft-rec >/dev/null 2>&1 || return 1
  [ -f "$wt/.git" ] || return 1
  FX_WT="$wt"
  export FX_WT
}

# _fx_hook_corpo <variante> — o corpo do pre-push de terceiro, com __PP__ no
# lugar do validador de push
_fx_hook_corpo() {
  case "$1" in
    nao_composto) cat <<'EOF'
cat >/dev/null
echo 'lint de terceiro: ok' >&2
exit 0
EOF
      ;;
    composto) cat <<'EOF'
entrada="$(cat)"
echo 'lint de terceiro: ok' >&2
printf '%s\n' "$entrada" | bash __PP__ --pre-push "$@" || exit $?
exit 0
EOF
      ;;
    so_cita) cat <<'EOF'
# integra com a MergeX: bash __PP__ --pre-push "$@"
cat >/dev/null
echo 'lint de terceiro: barrado por conta própria' >&2
exit 1
EOF
      ;;
    nao_propaga) cat <<'EOF'
bash __PP__ --pre-push "$@"
exit 0
EOF
      ;;
    libera) cat <<'EOF'
cat >/dev/null
bash __PP__ --pre-push "$@" </dev/null
exit $?
EOF
      ;;
    sinal) cat <<'EOF'
bash __PP__ --pre-push "$@"
kill -KILL $$
EOF
      ;;
    ecoa_sinal) cat <<'EOF'
# forja o sinal sem executar a MergeX: a linha antiga e uma com SHA arbitrário
cat >/dev/null
printf 'mergex-pre-push invocado 1\n' >> "${MERGEX_PRE_PUSH_SINAL:-/dev/null}"
printf 'mergex-pre-push 0123456789abcdef0123456789abcdef01234567 barra\n' >> "${MERGEX_PRE_PUSH_SINAL:-/dev/null}"
exit 1
EOF
      ;;
    sem_entrada) cat <<'EOF'
cat >/dev/null
bash __PP__ --pre-push "$@" </dev/null
exit 1
EOF
      ;;
    lento) cat <<'EOF'
bash __PP__ --pre-push "$@"
sleep 3077
exit 1
EOF
      ;;
    ignora_term) cat <<'EOF'
trap '' TERM
bash __PP__ --pre-push "$@"
sleep 3077
exit 1
EOF
      ;;
    regra_propria) cat <<'EOF'
# chama a MergeX, ignora o código dela e decide por regra própria
bash __PP__ --pre-push "$@"
[ "$2" = file:///dev/null ] && exit 1
exit 0
EOF
      ;;
    sempre_barra) cat <<'EOF'
# repassa a entrada e propaga o código, mas num ambiente em que a MergeX barra
# toda ref: o diretório de objetos que ela enxerga está vazio
o="$(mktemp -d)" || exit 1
GIT_OBJECT_DIRECTORY="$o" bash __PP__ --pre-push "$@"
rc=$?
rmdir "$o"
exit "$rc"
EOF
      ;;
    *) return 1 ;;
  esac
}

# fx_hook_terceiro <dir> <variante> — grava (sobrescrevendo) o pre-push de
# terceiro da variante no diretório de hooks efetivo de <dir>, com o bit de
# execução. O validador é FX_PORTAO_PUSH (padrão: o portao-push.sh da skill).
fx_hook_terceiro() {
  local dir="$1" var="$2" hd corpo pp
  [ -n "$dir" ] && [ -n "$var" ] && [ -e "$dir/.git" ] || return 64
  corpo="$(_fx_hook_corpo "$var")" || { printf 'fixture: variante de hook desconhecida: %s\n' "$var" >&2; return 64; }
  hd="$(git -C "$dir" rev-parse --path-format=absolute --git-path hooks)" || return 1
  mkdir -p "$hd" || return 1
  pp="$(printf '%q' "${FX_PORTAO_PUSH:-$_FXR_PORTAO_PUSH}")"
  { printf '#!/usr/bin/env bash\n# pre-push de terceiro (fixture): variante %s\n' "$var"
    # substituição literal (entre aspas: nem & nem \ do %q são especiais)
    printf '%s\n' "${corpo//__PP__/"$pp"}"
  } > "$hd/pre-push" || return 1
  chmod 755 "$hd/pre-push"
}

# ---------------------------------------------------------------------------
# Fluxo ponta a ponta depois da reconciliação (Task 20, spec seção 16)
# ---------------------------------------------------------------------------

# Os executáveis da própria skill, chamados pelo fluxo.
_FXR_SKILL="$(cd "$_FXR_LIB/../../.." && pwd)/.claude/skills/mergex/scripts"

# _fx_etapa <rótulo> <dir> <comando>... — roda o comando em <dir> (num
# subshell), grava stdout, stderr e código em FX_FLUXO_DIR/<rótulo>.{out,err,rc}.
# Código diferente de 0 preenche FX_ERRO com a etapa e a saída, e devolve 1.
_fx_etapa() {
  local rot="$1" dir="$2" rc; shift 2
  ( cd "$dir" && "$@" ) > "$FX_FLUXO_DIR/$rot.out" 2> "$FX_FLUXO_DIR/$rot.err"; rc=$?
  printf '%s\n' "$rc" > "$FX_FLUXO_DIR/$rot.rc"
  [ "$rc" = 0 ] && return 0
  FX_ERRO="etapa $rot (rc=$rc): $(cat "$FX_FLUXO_DIR/$rot.out" "$FX_FLUXO_DIR/$rot.err" | tr '\n' '|')"
  return 1
}

# _fx_e3 — o E3 sobre o delta desde o último ATENCAO.md, no cwd: a lista de
# reconciliados vem das linhas `coberto` de `reconciliacao-base.sh
# --verificar`, a classificação vem de `classificar-atencao.sh --reconciliados`
# (O10), e o ATENCAO.md é regravado inteiro na forma de
# assets/TEMPLATE-atencao.md a partir da saída do classificador. Sem o agente
# revisor-diff, nenhum caminho leva evidência O1–O9, L1–L3 ou D1–D3: os
# reconciliados saem por O10, os artefatos de método pelo catálogo (L4/D4) e o
# resto pelo padrão do classificador.
_fx_e3() {
  local e=docs/entregas/ft-rec/ENTREGA.md a=docs/entregas/ft-rec/ATENCAO.md ult
  local rec="$FX_FLUXO_DIR/e3-reconciliados.tsv" ent="$FX_FLUXO_DIR/e3-entrada.txt" cls="$FX_FLUXO_DIR/e3-classificacao.tsv"
  local caminho faixa just st tam n=0 x=0 y=0 z=0 olho="" leit="" disp="" linha
  bash "$_FXR_SKILL/reconciliacao-base.sh" --verificar --entrega "$e" --origem sprintx --trabalho ft-rec > "$FX_FLUXO_DIR/e3-verificar.out" || return 1
  awk -F'\t' '$1 == "coberto" { print $2 "\t" $3 }' "$FX_FLUXO_DIR/e3-verificar.out" > "$rec" || return 1
  [ -s "$rec" ] || { printf 'e3: nenhum caminho coberto\n' >&2; return 1; }
  ult="$(git log -1 --format=%H -- "$a")" && [ -n "$ult" ] || { printf 'e3: sem ATENCAO.md anterior\n' >&2; return 1; }
  git -c core.quotepath=false diff --name-only --no-renames "$ult" HEAD > "$ent" || return 1
  bash "$_FXR_SKILL/classificar-atencao.sh" --base main --reconciliados "$rec" < "$ent" > "$cls" || return 1
  while IFS="$(printf '\t')" read -r caminho faixa just; do
    [ -n "$caminho" ] || continue
    st="$(git -c core.quotepath=false diff --name-status --no-renames "$ult" HEAD -- ":(literal)$caminho" | cut -f1)"
    tam="$(git -c core.quotepath=false diff --numstat --no-renames "$ult" HEAD -- ":(literal)$caminho" | awk -F'\t' '{ printf "+%s/-%s", $1, $2 }')"
    linha="| \`$caminho\` | ${st:--} | ${tam:--} | $just |"
    n=$((n + 1))
    case "$faixa" in
      'OLHO OBRIGATÓRIO') x=$((x + 1)); olho="$olho$linha
" ;;
      'LEITURA RÁPIDA') y=$((y + 1)); leit="$leit$linha
" ;;
      'DISPENSÁVEL') z=$((z + 1)); disp="$disp$linha
" ;;
      *) printf 'e3: faixa desconhecida para %s: %s\n' "$caminho" "$faixa" >&2; return 1 ;;
    esac
  done < "$cls"
  [ "$n" -gt 0 ] || { printf 'e3: classificação vazia\n' >&2; return 1; }
  { printf '# Onde gastar atenção — ft-rec\n\n'
    printf 'Branch: `feature/ft-rec` → `main`\nData: %s\n\n' "$(date +%Y-%m-%d)"
    printf '**%s arquivos — %s olho obrigatório, %s leitura rápida, %s dispensável**\n\n' "$n" "$x" "$y" "$z"
    printf 'A classificação é derivada de evidência registrada, nunca de sensação.\nTamanho de diff não é critério.\n\n'
    printf '## OLHO OBRIGATÓRIO — ler linha a linha\n\n| Arquivo | Mudança | Tamanho | Por quê |\n|---|---|---|---|\n%s\n' "$olho"
    printf '## LEITURA RÁPIDA — conferir intenção, não implementação\n\n| Arquivo | Mudança | Tamanho | Por quê |\n|---|---|---|---|\n%s\n' "$leit"
    printf '## DISPENSÁVEL — a máquina já provou\n\n| Arquivo | Mudança | Tamanho | Por quê |\n|---|---|---|---|\n%s\n' "$disp"
    printf '## Fontes consultadas\n\n- reconciliacao-base.sh --verificar — os caminhos cobertos (O10)\n- classificar-atencao.sh --reconciliados — a ordem dos critérios e o catálogo de método\n\n'
    printf '## Fontes ausentes\n\n- evidência O1–O9, L1–L3 e D1–D3 do revisor-diff — não avaliada nesta fixture\n'
  } > "$a"
}

# _fx_e7 — o E7 retoma o PR existente (nunca um segundo PR): regrava o PR.md
# com a nota da retomada, no cwd. Fica para o checkpoint e8.
_fx_e7() {
  printf '\n## Retomada depois da reconciliação de base\n\nO PR existente é retomado com RECONCILIACAO-BASE-001.md; nenhum PR novo é aberto.\n' \
    >> docs/entregas/ft-rec/PR.md
}

# fx_fluxo_completo <dir> — o fluxo da spec, seção 16, sobre o cenário em
# <dir> (o checkout principal ou uma worktree vinculada em feature/ft-rec),
# só pelos executáveis da skill, nesta ordem:
#   01-instalar            ativacao-pre-push.sh --instalar (E0)
#   02-registrar           reconciliacao-base.sh --registrar -- FX_NOVO1 FX_NOVO2
#   03-reconciliacao-base  persistir-metodo.sh --persistir --checkpoint reconciliacao-base
#   04-barreira            reconciliacao-base.sh --verificar --checkpoint reconciliacao-base
#   05-v9, 05-provar       portao-v9.sh --verificar; ativacao-pre-push.sh --provar
#   06-registrar-portao    registrar-portao.sh --resultado pronto (portao e portao_sha)
#   07-e3, 07-pre-e6       ATENCAO.md pelo classificador (O10); checkpoint pre-e6
#   08-validade            validade-do-portao.sh --verificar
#   09-e7, 09-e8           PR.md retomado; checkpoint e8
#   10-validade            validade-do-portao.sh --verificar
# Nunca edita o ENTREGA.md: o registro, o registrar-portao e os checkpoints são
# os únicos escritores. Para na primeira etapa com código diferente de 0, com
# FX_ERRO = a etapa e a saída. Cada etapa deixa <rótulo>.out/.err/.rc em
# FX_FLUXO_DIR (<diretório Git comum>/fx-fluxo, no temporário do teste).
# Exporta FX_FLUXO_DIR, FX_FLUXO_RECONC (o commit reconciliacao-base),
# FX_FLUXO_PORTAO (o portao_sha gravado), FX_FLUXO_PRE_E6 e FX_FLUXO_E8.
fx_fluxo_completo() {
  local dir="${1:-}" e=docs/entregas/ft-rec/ENTREGA.md
  FX_ERRO=""
  [ -n "$dir" ] && [ -e "$dir/.git" ] || { FX_ERRO="uso: fx_fluxo_completo <dir>"; return 64; }
  FX_FLUXO_DIR="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)/fx-fluxo" \
    || { FX_ERRO="diretório Git comum ilegível"; return 1; }
  rm -rf "$FX_FLUXO_DIR" && mkdir -p "$FX_FLUXO_DIR" || { FX_ERRO="não criou $FX_FLUXO_DIR"; return 1; }
  FX_FLUXO_RECONC=""; FX_FLUXO_PORTAO=""; FX_FLUXO_PRE_E6=""; FX_FLUXO_E8=""
  export FX_FLUXO_DIR FX_FLUXO_RECONC FX_FLUXO_PORTAO FX_FLUXO_PRE_E6 FX_FLUXO_E8
  set -- --entrega "$e" --origem sprintx --trabalho ft-rec
  _fx_etapa 01-instalar "$dir" bash "$_FXR_SKILL/ativacao-pre-push.sh" --instalar --entrega "$e" || return 1
  _fx_etapa 02-registrar "$dir" bash "$_FXR_SKILL/reconciliacao-base.sh" --registrar "$@" -- "$FX_NOVO1" "$FX_NOVO2" || return 1
  _fx_etapa 03-reconciliacao-base "$dir" bash "$_FXR_SKILL/persistir-metodo.sh" --persistir "$@" --checkpoint reconciliacao-base || return 1
  FX_FLUXO_RECONC="$(git -C "$dir" rev-parse HEAD)"
  _fx_etapa 04-barreira "$dir" bash "$_FXR_SKILL/reconciliacao-base.sh" --verificar --checkpoint reconciliacao-base "$@" || return 1
  _fx_etapa 05-v9 "$dir" bash "$_FXR_SKILL/portao-v9.sh" --verificar "$@" || return 1
  _fx_etapa 05-provar "$dir" bash "$_FXR_SKILL/ativacao-pre-push.sh" --provar --entrega "$e" || return 1
  _fx_etapa 06-registrar-portao "$dir" bash "$_FXR_SKILL/registrar-portao.sh" "$@" --resultado pronto || return 1
  FX_FLUXO_PORTAO="$(sed -n 's/^portao_sha=//p' "$FX_FLUXO_DIR/06-registrar-portao.out")"
  _fx_etapa 07-e3 "$dir" _fx_e3 || return 1
  _fx_etapa 07-pre-e6 "$dir" bash "$_FXR_SKILL/persistir-metodo.sh" --persistir "$@" --checkpoint pre-e6 || return 1
  FX_FLUXO_PRE_E6="$(git -C "$dir" rev-parse HEAD)"
  _fx_etapa 08-validade "$dir" bash "$_FXR_SKILL/validade-do-portao.sh" --verificar --entrega "$e" || return 1
  _fx_etapa 09-e7 "$dir" _fx_e7 || return 1
  _fx_etapa 09-e8 "$dir" bash "$_FXR_SKILL/persistir-metodo.sh" --persistir "$@" --checkpoint e8 || return 1
  FX_FLUXO_E8="$(git -C "$dir" rev-parse HEAD)"
  _fx_etapa 10-validade "$dir" bash "$_FXR_SKILL/validade-do-portao.sh" --verificar --entrega "$e" || return 1
  return 0
}

# fx_commit_produto_apos_portao <dir> — um commit de produto comum (sem
# Metodo:) na branch do trabalho: acrescenta uma linha a src/painel.ts.
fx_commit_produto_apos_portao() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -e "$dir/.git" ] || return 64
  ( cd "$dir" || exit 1
    printf 'export const depoisDoPortao = 1;\n' >> src/painel.ts || exit 1
    git add -- src/painel.ts || exit 1
    git commit -q -m "feat(ft-rec): ajuste do painel depois do portao" )
}
