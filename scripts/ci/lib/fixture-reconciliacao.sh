#!/usr/bin/env bash
# Fixture Git real do cenário "a base avança depois do E8".
#
# Funções:
#   fx_cenario <dir> [legado]   monta o cenário inteiro e exporta
#                               FX_B0 FX_P1 FX_B1 FX_M FX_TRAB FX_ENTREGA FX_NOVO1 FX_NOVO2
#   fx_merge_sem_commit <dir>   o mesmo cenário, parado com o merge resolvido
#                               e no índice, sem commit (MERGE_HEAD presente)
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

_fx_plano() {
  mkdir -p docs/sprintx/features/ft-rec/sprint-01 || return 1
  cat > docs/sprintx/features/ft-rec/sprint-01/tasks.md <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
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
  cat > docs/sprintx/features/ft-rec/ORQUESTRADOR.md <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
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
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: ft-rec\n'
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
_FX_VARIANTES=" base_removeu integracao_removeu renomeado resolucao_igual_base m_um_pai pais_trocados fora_primeiro_pai m_sem_integra_base m_com_metodo caminho_especial base_alterou "

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
  {
    cd "$dir"
    git init -q -b main
    git config user.email teste@expx.local
    git config user.name "Teste Expx"
    git config core.autocrlf false
    git config core.quotepath false
    git config commit.gpgsign false

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
    _fx_plano
    git add docs/sprintx/features/ft-rec/sprint-01/tasks.md docs/sprintx/features/ft-rec/ORQUESTRADOR.md
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
      base_alterou)
        printf '# Projeto\n\nSeção da base.\n' > README.md
        git add README.md ;;
    esac
    _fx_msg "$msg" "feat: primitivas ksmv e titulo da base"
    _fx_commit "$msg"
    FX_B1="$(git rev-parse HEAD)"

    # merge com conflito em src/painel.ts
    fixture_switch_exato feature/ft-rec feature/ft-rec
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
      base_alterou)
        printf '# Projeto\n\nSeção da base, ajustada para a feature.\n' > README.md
        git add README.md ;;
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
  bash -c 'set -e; . "$1"; shift; _fx_corpo "$@"' _ \
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
    base_removeu|renomeado|base_alterou) FX_LISTA_VARIANTE="$FX_LISTA_VARIANTE
README.md" ;;
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
