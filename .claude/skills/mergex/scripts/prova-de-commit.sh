#!/usr/bin/env bash
# prova-de-commit — a V11 do portão de prontidão (E2): toda task `concluida`
# tem prova de E1 em `ENTREGA.commits`?
#
# Contrato: references/02-prontidao.md, "V11 — Task concluída sem commit do E1";
# references/00-schema.md, "O kind que a mergex produz" (a lista `commits`);
# references/01-commits.md, "commits é histórico de execução, não índice de plano".
#
# A V11 responde UMA pergunta, e só ela: para cada task marcada `concluida` no
# plano executado, existe pelo menos UM item de `ENTREGA.commits` cujo `task`
# é exatamente o id dela e cujo `commit` é um identificador válido?
#
#   1. Ela NÃO lê `suite` (V2), `teste_integracao`/`teste_funcional` (V3), nem
#      o status das tasks não concluídas (V1). Task não concluída não é alvo
#      positivo da V11: a razão dela é da V1, e duas verificações não dão a
#      mesma razão duas vezes.
#   2. EXISTE pelo menos um item — nunca "exatamente um". Uma task pode
#      reaparecer em `commits` depois de replanejamento, e isso é histórico de
#      execução válido, não erro. Ordem e seção crítica não são assunto daqui.
#   3. Prova é o item inteiro. `task` sem `commit`, `commit` vazio, marcador de
#      template ou SHA malformado não provam nada: o item existe, a prova não.
#   4. A evidência canônica do E1 é `ENTREGA.commits` (é o que o E1 grava, e o
#      que o E8 commita). A V11 não audita `git log`: o cruzamento que faltava
#      é `tasks.md` × `ENTREGA.commits`, e é só esse que ela fecha.
#   5. Sem versionador (`versionado: false`) não há commit a exigir — o schema
#      já define `commits: []` nesse caso. A V11 é `n/a`, nunca FALHA.
#   6. O que não pôde ser lido sai como SEM_PROVA (código 2), para o E2
#      registrar `v11_sem_prova`. Ausência de prova não é prova.
#
# Uso:
#   prova-de-commit.sh --verificar <ENTREGA.md|-> <tasks.md>...
#   prova-de-commit.sh --commits <ENTREGA.md|->     # `task<TAB>commit` dos itens VÁLIDOS
#   prova-de-commit.sh --concluidas <tasks.md>...   # `id<TAB>arquivo` das tasks concluídas
#   prova-de-commit.sh --sha <valor>                # 0 quando é identificador válido
#
# Saída de --verificar, primeira linha sempre:
#   V11=OK         (código 0) — toda task concluída tem prova
#   V11=n/a        (código 0) — mais `motivo=`; a verificação não se aplica
#   V11=FALHA      (código 1) — mais uma linha `id<TAB>arquivo` por task sem prova
#   V11=SEM_PROVA  (código 2) — mais `motivo=`; não foi possível verificar
# Opção inválida: 64.
#
# Bash 3.2 (macOS): nada de mapfile, arrays associativos ou ${v,,}.

set -uo pipefail

ERRO=""

# ---------------------------------------------------------------------------
# Leitura do frontmatter. Mesma disciplina do causa-do-portao.sh: o bloco é a
# primeira coisa do arquivo, delimitado por `---`, e CR de fim de linha some.
# O que muda aqui é o alvo: `commits` e `tasks` são listas de mapas, que aquele
# leitor (chaves de topo escalares) não enxerga — não há parser a reutilizar.
# ---------------------------------------------------------------------------

# bloco <arquivo> <chave de topo> — as linhas indentadas sob a chave, dentro do
# frontmatter. Imprime `\001<valor inline>` na primeira linha quando a chave
# trouxe valor na mesma linha (`commits: []`).
bloco() {
  awk -v chave="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) { print "\002sem-frontmatter"; exit }; fm = 1; next }
    fm && /^---[[:space:]]*$/ { fechado = 1; exit }
    !fm { next }
    # Chave de topo (coluna 0). A indentada não abre nem fecha bloco nenhum.
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
      nome = $0; sub(/:.*/, "", nome)
      if (nome == chave) {
        dentro = 1; visto = 1
        inline = $0; sub(/^[^:]*:[[:space:]]*/, "", inline); sub(/[[:space:]]+$/, "", inline)
        print "\001" inline
        next
      }
      dentro = 0; next
    }
    dentro { print }
    END {
      if (fm && !fechado) print "\002aberto"
      else if (!visto) print "\002sem-chave"
    }
  ' "$1"
}

# confere_bloco <saída de bloco> — traduz o marcador \002 em ERRO
confere_bloco() {
  case "$1" in
    *$'\002'sem-frontmatter*) ERRO="o arquivo não começa com frontmatter"; return 1 ;;
    *$'\002'aberto*)          ERRO="o frontmatter não foi fechado"; return 1 ;;
    *$'\002'sem-chave*)       ERRO="chave ausente no frontmatter"; return 1 ;;
  esac
  return 0
}

# escalar <arquivo> <chave de topo> — o valor de uma chave escalar de topo
escalar() {
  awk -v chave="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; fm = 1; next }
    fm && /^---[[:space:]]*$/ { exit }
    !fm { next }
    /^[A-Za-z_][A-Za-z0-9_]*:/ {
      nome = $0; sub(/:.*/, "", nome)
      if (nome != chave) next
      v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; exit
    }
  ' "$1"
}

legivel() { # <arquivo>
  if [ "$1" = - ]; then return 0; fi
  [ -f "$1" ] && [ -r "$1" ] && return 0
  ERRO="arquivo ilegível: $1"; return 1
}

# ---------------------------------------------------------------------------
# A prova: um identificador de commit válido.
#
# O E1 registra o que `git rev-parse --short HEAD` devolveu — hexadecimal
# minúsculo, do tamanho curto do versionador ao SHA-1 inteiro. Vazio, `null`,
# marcador de template e qualquer coisa fora disso NÃO é prova: o item existe,
# mas não prova o commit que a V11 foi criada para cobrar.
# ---------------------------------------------------------------------------
sha_valido() { # <valor>
  case "$1" in
    ''|null|'~') return 1 ;;
    *[!0-9a-f]*) return 1 ;;
  esac
  case "${#1}" in
    7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40) return 0 ;;
    *) return 1 ;;
  esac
}

limpa() { # <valor> — tira aspas e espaço das pontas
  local v="$1"
  v="${v%"${v##*[![:space:]]}"}"; v="${v#"${v%%[![:space:]]*}"}"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s\n' "$v"
}

# ---------------------------------------------------------------------------
# commits_validos <ENTREGA.md> — `task<TAB>commit` de cada item VÁLIDO de
# `ENTREGA.commits`, na ordem em que estão no arquivo. Item sem `task`, sem
# `commit` ou com `commit` malformado não sai: ele não é prova de nada.
# ---------------------------------------------------------------------------
commits_validos() {
  local arq="$1" b par t c
  legivel "$arq" || return 1
  b="$(bloco "$arq" commits)"
  confere_bloco "$b" || return 1
  # `commits: []` (inline) é lista vazia declarada: legítimo, sem nenhuma prova.
  case "$(printf '%s\n' "$b" | head -1)" in
    $'\001'|$'\001'\[\]) ;;
    $'\001'*) ERRO="commits não é lista de itens: ${b#?}"; return 1 ;;
  esac
  printf '%s\n' "$b" | awk '
    /^\001/ { next }
    { sub(/\r$/, "") }
    /^[[:space:]]*-[[:space:]]*task:/ {
      if (t != "") print t "\t" c
      t = $0; sub(/^[[:space:]]*-[[:space:]]*task:[[:space:]]*/, "", t); sub(/[[:space:]]+$/, "", t)
      c = ""; next
    }
    /^[[:space:]]*commit:/ {
      if (t == "") next
      c = $0; sub(/^[[:space:]]*commit:[[:space:]]*/, "", c); sub(/[[:space:]]+$/, "", c)
      next
    }
    END { if (t != "") print t "\t" c }
  ' | while IFS=$'\t' read -r par c; do
    t="$(limpa "$par")"; c="$(limpa "${c:-}")"
    [ -n "$t" ] || continue
    sha_valido "$c" || continue
    printf '%s\t%s\n' "$t" "$c"
  done
}

# ---------------------------------------------------------------------------
# concluidas_de <tasks.md>... — `id<TAB>arquivo` das tasks `concluida`.
#
# As tasks vêm sempre da chave `tasks`, nos DOIS formatos de sprint da sprintx
# (`kind: plano` e `kind: tasks`) — o formato nunca muda quais campos existem
# (`references/integracao/sprintx.md`, "Como ler uma sprint da sprintx").
# ---------------------------------------------------------------------------
concluidas_de() {
  local arq b saida=0
  for arq in "$@"; do
    legivel "$arq" || return 1
    b="$(bloco "$arq" tasks)"
    confere_bloco "$b" || { ERRO="$ERRO: $arq"; return 1; }
    printf '%s\n' "$b" | awk -v arq="$arq" '
      /^\001/ { next }
      { sub(/\r$/, "") }
      /^[[:space:]]*-[[:space:]]*id:/ {
        if (id != "" && st == "concluida") print id "\t" arq
        id = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", id); sub(/[[:space:]]+$/, "", id)
        gsub(/^["'"'"']|["'"'"']$/, "", id)
        st = ""; next
      }
      /^[[:space:]]*status:/ {
        if (id == "") next
        st = $0; sub(/^[[:space:]]*status:[[:space:]]*/, "", st); sub(/[[:space:]]+$/, "", st)
        gsub(/^["'"'"']|["'"'"']$/, "", st)
        next
      }
      END { if (id != "" && st == "concluida") print id "\t" arq }
    ' || saida=1
  done
  return "$saida"
}

# ---------------------------------------------------------------------------
verificar() { # <ENTREGA.md> <tasks.md>...
  local ent="$1" versionado provadas concluidas faltam id arq; shift
  if [ "$#" -eq 0 ]; then
    printf 'V11=SEM_PROVA\nmotivo=nenhum-tasks-md-informado\n'; return 2
  fi
  if ! legivel "$ent"; then
    printf 'V11=SEM_PROVA\nmotivo=entrega-ilegivel\n'; printf 'prova-de-commit: %s\n' "$ERRO" >&2; return 2
  fi

  # Sem versionador o schema já define `commits: []`: não há commit a exigir.
  versionado="$(escalar "$ent" versionado)"
  if [ "$(limpa "$versionado")" = false ]; then
    printf 'V11=n/a\nmotivo=sem-versionador\n'; return 0
  fi

  if ! concluidas="$(concluidas_de "$@")"; then
    printf 'V11=SEM_PROVA\nmotivo=plano-ilegivel\n'; printf 'prova-de-commit: %s\n' "$ERRO" >&2; return 2
  fi
  if ! provadas="$(commits_validos "$ent")"; then
    printf 'V11=SEM_PROVA\nmotivo=commits-ilegivel\n'; printf 'prova-de-commit: %s\n' "$ERRO" >&2; return 2
  fi

  # Nenhuma task concluída: a V11 não tem alvo positivo. A razão de não haver
  # task concluída é da V1, e a V11 não a repete.
  if [ -z "$concluidas" ]; then
    printf 'V11=n/a\nmotivo=nenhuma-task-concluida\n'; return 0
  fi

  faltam=""
  while IFS=$'\t' read -r id arq; do
    [ -n "$id" ] || continue
    # EXISTE pelo menos um item: casamento EXATO do id, nunca prefixo ou trecho.
    printf '%s\n' "$provadas" | cut -f1 | grep -Fxq -- "$id" && continue
    faltam="$faltam$id	$arq
"
  done <<EOF
$concluidas
EOF

  if [ -z "$faltam" ]; then printf 'V11=OK\n'; return 0; fi
  printf 'V11=FALHA\n'
  printf '%s' "$faltam"
  return 1
}

case "${1:-}" in
  --verificar)
    shift
    [ "$#" -ge 1 ] || { printf 'prova-de-commit: --verificar <ENTREGA.md> <tasks.md>...\n' >&2; exit 64; }
    verificar "$@"; exit $? ;;
  --commits)
    [ "$#" -eq 2 ] || { printf 'prova-de-commit: --commits <ENTREGA.md|->\n' >&2; exit 64; }
    commits_validos "$2" && exit 0
    printf 'prova-de-commit: %s\n' "$ERRO" >&2; exit 1 ;;
  --concluidas)
    shift
    [ "$#" -ge 1 ] || { printf 'prova-de-commit: --concluidas <tasks.md>...\n' >&2; exit 64; }
    concluidas_de "$@" && exit 0
    printf 'prova-de-commit: %s\n' "$ERRO" >&2; exit 1 ;;
  --sha)
    [ "$#" -eq 2 ] || { printf 'prova-de-commit: --sha <valor>\n' >&2; exit 64; }
    sha_valido "$(limpa "$2")" && exit 0 || exit 1 ;;
  *) printf 'prova-de-commit: opção desconhecida: %s\n' "${1:-}" >&2; exit 64 ;;
esac
