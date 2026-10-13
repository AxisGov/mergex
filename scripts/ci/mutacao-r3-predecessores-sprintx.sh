#!/usr/bin/env bash
# Certificação por mutação do contrato de predecessores SprintX / MergeX.
# Cada mutante vive numa cópia Git temporária; o repositório corrente nunca é
# alterado. Os 15 primeiros correspondem à seção 14 da spec; 16–23 fecham o
# protocolo e o fluxo exigidos pela Task 10.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mutacao-r3.XXXXXX")" || exit 1
if [ "${MUTACAO_KEEP:-0}" = 1 ]; then
  trap 'printf "temporario=%s\n" "$TMP"' EXIT
else
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fi

MATRIZ='1|PREFIXALL|v9|aceita todo docs/superpowers
2|PREFIX|v9|usa prefixo em vez do caminho exato
3|DISK|verificador|confia no manifesto do disco
4|NOBLOB|verificador|não compara o blob atual
5|POSTERIOR|verificador|aceita predecessor posterior ao planejamento
6|IGUAL|verificador|aceita predecessor no nascimento
7|IGNORA|verificador|ignora uma entrada inválida
8|INVALIDAUSENTE|consumidor|transforma inválido em ausente
9|MULTIFALHA|retomada|reabre com falhas além de v9
10|PORTAOSHA|retomada|não limpa portao_sha
11|COMMITSEQ|mp27b|altera ENTREGA.commits e seq
12|TASKARTIFICIAL|mp27b|cria task artificial
13|DIRTY|retomada|aceita árvore suja
14|HUMAN|verificador|aceita SHA humano sem a prova estrita
15|E2SOMENTEV9|contrato|documenta somente V9 depois da retomada
16|RC1VAZIO|consumidor|rc 1 sem resultado
17|RCDIVERGE|consumidor|texto ok com rc 1
18|TRUNCADO|consumidor|resultado v9 sem fora_do_plano
19|DUPRESULT|consumidor|duas linhas resultado
20|EVENTO|validate|inventa evento fora do enum
21|TASKARTIFICIAL2|mp27b|segunda forma de task artificial
22|SEQ|mp27b|checkpoint entra em ENTREGA.commits
23|E2PARCIAL|contrato|pula V1-V8 V10 e V11'

copia() { # <id>
  local d="$TMP/$1"
  mkdir -p "$d" || return 1
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | tar -cf - --null -T - ) \
    | ( cd "$d" && tar -xf - ) || return 1
  ( cd "$d" && git init -q -b main && git config user.email teste@expx.local \
      && git config user.name 'Teste Expx' && git add -A && git commit -qm fixture ) || return 1
  printf '%s\n' "$d"
}

troca_linha() { # <arquivo> <trecho literal> <linha nova>
  local f="$1" trecho="$2" nova="$3"
  TRECHO="$trecho" NOVA="$nova" awk '
    index($0, ENVIRON["TRECHO"]) { print ENVIRON["NOVA"]; n++; next }
    { print }
    END { if (n != 1) exit 7 }
  ' "$f" > "$f.mut" || { rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f"
}

insere_antes() { # <arquivo> <trecho literal> <linha nova>
  local f="$1" trecho="$2" nova="$3"
  TRECHO="$trecho" NOVA="$nova" awk '
    index($0, ENVIRON["TRECHO"]) { print ENVIRON["NOVA"]; n++ }
    { print }
    END { if (n != 1) exit 7 }
  ' "$f" > "$f.mut" || { rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f"
}

troca_bloco2() { # <arquivo> <trecho da primeira linha> <linha nova>
  local f="$1" trecho="$2" nova="$3"
  TRECHO="$trecho" NOVA="$nova" awk '
    index($0, ENVIRON["TRECHO"]) { print ENVIRON["NOVA"]; getline; n++; next }
    { print }
    END { if (n != 1) exit 7 }
  ' "$f" > "$f.mut" || { rm -f "$f.mut"; return 1; }
  mv "$f.mut" "$f"
}

wrapper() { # <dir> <modo>
  local f="$1/mutante-predecessores.sh" modo="$2"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    case "$modo" in
      INVALIDAUSENTE) printf '%s\n' 'printf "resultado=ausente\n"; exit 0' ;;
      RC1VAZIO) printf '%s\n' 'exit 1' ;;
      RCDIVERGE) printf '%s\n' 'printf "resultado=ok\n"; exit 1' ;;
      TRUNCADO) printf '%s\n' 'printf "resultado=v9\n"; exit 1' ;;
      DUPRESULT) printf '%s\n' 'printf "resultado=ok\nresultado=ok\n"; exit 0' ;;
    esac
  } > "$f"
  chmod +x "$f"
  printf '%s\n' "$f"
}

aplica() { # <dir> <id>; imprime override PREDS, se houver
  local d="$1" id="$2" pre="$d/.claude/skills/mergex/scripts/predecessores-sprintx.sh"
  local v9="$d/.claude/skills/mergex/scripts/portao-v9.sh" ret="$d/.claude/skills/mergex/scripts/retomar-v9-predecessores.sh"
  case "$id" in
    PREFIXALL)
      insere_antes "$v9" 'contem "$TMP_DIR/uniao" "$p" && continue' \
        '  case "$p" in docs/superpowers/*) continue ;; esac' ;;
    PREFIX)
      insere_antes "$v9" 'contem "$TMP_DIR/uniao" "$p" && continue' \
        '  case "$p" in docs/superpowers/specs/*|docs/superpowers/plans/*) continue ;; esac' ;;
    DISK)
      troca_linha "$pre" 'git cat-file blob "$REV_SHA:$MANIFESTO"' \
        'cp "$MANIFESTO" "$TMP_DIR/manifesto" 2>/dev/null || sem_prova "manifesto ilegivel"' ;;
    NOBLOB)
      troca_linha "$pre" 'if [ "$oid_head" != "$blob" ]; then' '  if false; then' ;;
    POSTERIOR)
      troca_bloco2 "$pre" '[ "$commit" != "$NASCIMENTO" ] && git merge-base --is-ancestor' \
        '  [ "$commit" != "$NASCIMENTO" ] || sem_prova "predecessor nao antecede estritamente o planejamento: $caminho"' ;;
    IGUAL)
      troca_bloco2 "$pre" '[ "$commit" != "$NASCIMENTO" ] && git merge-base --is-ancestor' \
        '  git merge-base --is-ancestor "$commit" "$NASCIMENTO" >/dev/null 2>&1 || sem_prova "predecessor posterior ao planejamento: $caminho"' ;;
    HUMAN)
      troca_linha "$pre" 'printf '\''%s'\'' "$commit" | grep -Eq '\''^[0-9a-f]{40}$'\''' \
        '  commit="$(git rev-parse --verify "$commit^{commit}" 2>/dev/null)" || sem_prova "commit_sha invalido: $caminho"' ;;
    IGNORA)
      troca_linha "$pre" '[ "$origem" = superpowers ] || sem_prova' '  : # origem não conferida' ;;
    INVALIDAUSENTE|RC1VAZIO|RCDIVERGE|TRUNCADO|DUPRESULT)
      wrapper "$d" "$id" ;;
    MULTIFALHA)
      troca_linha "$ret" 'catalogo_fm "$TMP_DIR/entrega-head" falhas_portao' '    && : \' ;;
    PORTAOSHA)
      troca_linha "$ret" 'entrega_define "$TMP_DIR/novo" portao_sha null' '  && : \' ;;
    COMMITSEQ)
      insere_antes "$ret" 'bash "$PERSISTE_SH" --persistir' \
        'bash "$AQUI/sequencia-de-commits.sh" --acrescentar "$ENTREGA" T-ART "$(git rev-parse HEAD)" >/dev/null' ;;
    SEQ)
      insere_antes "$ret" 'bash "$PERSISTE_SH" --persistir' \
        'sed "0,/^  - seq: 1$/s//  - seq: 99/" "$ENTREGA" > "$ENTREGA.seq" && mv "$ENTREGA.seq" "$ENTREGA"' ;;
    TASKARTIFICIAL)
      insere_antes "$ret" 'bash "$PERSISTE_SH" --persistir' \
        'printf "\n# task artificial\n" >> "docs/sprintx/features/$TRABALHO/sprint-01/tasks.md"' ;;
    TASKARTIFICIAL2)
      insere_antes "$ret" 'bash "$PERSISTE_SH" --persistir' \
        'printf "\n  - id: T-ART\n    status: concluida\n" >> "docs/sprintx/features/$TRABALHO/sprint-01/tasks.md"' ;;
    DIRTY)
      troca_linha "$ret" '[ -z "$(git status --porcelain=v1 --untracked-files=all' '  : \' ;;
    E2SOMENTEV9)
      troca_linha "$d/.claude/commands/mergex-check.md" \
        'depois rode novamente todas as V1–V11' \
        'depois rode novamente somente V9.' ;;
    E2PARCIAL)
      troca_linha "$d/.claude/skills/mergex/references/integracao/sprintx.md" \
        'aplicar/checkpoint retomada → pre-e2 → E2 completo' \
        'aplicar/checkpoint retomada → pre-e2 → somente V9' ;;
    EVENTO)
      printf '\nevento: "predecessor_registrado"\n' >> "$d/.claude/skills/mergex/references/13-predecessores-sprintx.md" ;;
    *) return 1 ;;
  esac
}

roda() { # <dir> <id> <grupo> <override>
  local d="$1" id="$2" grupo="$3" override="$4"
  if [ "$grupo" = validate ]; then
    ( cd "$d" && bash scripts/ci/validate-mergex-contract.sh )
  elif [ -n "$override" ]; then
    ( cd "$d" && R3_PREDS_CONSUMIDOR="$override" bash scripts/ci/test-r3-predecessores-sprintx.sh "$grupo" )
  else
    ( cd "$d" && bash scripts/ci/test-r3-predecessores-sprintx.sh "$grupo" )
  fi
}

printf 'controle: '
if ! ( cd "$REPO" && bash scripts/ci/test-r3-predecessores-sprintx.sh todos >/dev/null ); then
  printf 'FALHOU\n' >&2
  exit 1
fi
printf 'verde\n'

total=0; mortos=0; invalidos=0
while IFS='|' read -r num id grupo desc; do
  [ -n "$id" ] || continue
  [ -z "${MUTANTE_ID:-}" ] || [ "$id" = "$MUTANTE_ID" ] || continue
  total=$((total + 1))
  d="$(copia "$id")" || { printf 'INVALIDO %s: cópia\n' "$id"; invalidos=$((invalidos + 1)); continue; }
  override="$(aplica "$d" "$id")" || { printf 'INVALIDO %s: mutação\n' "$id"; invalidos=$((invalidos + 1)); continue; }
  if ! find "$d/.claude" "$d/scripts" -type f -name '*.sh' -exec bash -n {} \; ; then
    printf 'INVALIDO %s: sintaxe\n' "$id"; invalidos=$((invalidos + 1)); continue
  fi
  log="$TMP/$id.log"
  roda "$d" "$id" "$grupo" "$override" > "$log" 2>&1; rc=$?
  if [ "$rc" != 0 ] && grep -Eq 'FALHA|contract check failed' "$log"; then
    mortos=$((mortos + 1)); printf 'MORTO %02d %-18s %s\n' "$num" "$id" "$desc"
  else
    printf 'VIVO  %02d %-18s rc=%s %s\n' "$num" "$id" "$rc" "$desc"
    sed -n '1,80p' "$log"
  fi
done <<EOF
$MATRIZ
EOF

printf '%d/%d mortos; %d inválidos\n' "$mortos" "$total" "$invalidos"
[ "$mortos" -eq "$total" ] && [ "$invalidos" -eq 0 ]
