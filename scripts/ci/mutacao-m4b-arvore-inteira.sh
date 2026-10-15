#!/usr/bin/env bash
# Controle sem mutação de P0.2-C7-B / M4-B.
# Cada mutante altera uma cópia temporária e precisa fazer a bancada M4-B falhar.
#
# Uso: bash scripts/ci/mutacao-m4b-arvore-inteira.sh [M1 M2 ...]

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FECHA='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
OWN='.claude/skills/mergex/scripts/ownership-da-task.sh'
V9='.claude/hooks/mergex/arquivo-fora-do-plano.sh'
BANCADA='scripts/ci/test-m4b-arvore-inteira.sh'
TMPS=""
trap 'for d in $TMPS; do rm -rf "$d"; done' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

troca() { # <arquivo> <linha exata> <linha nova>
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || return 1
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

M1() { # só inspeciona os paths passados pelo agente
  troca "$FECHA" '  inventaria_arvore' '  DIRTY="" # mutante: sem inventário'
}
M2() { # ignora não rastreados
  troca "$FECHA" '  git status --porcelain=v1 -z --untracked-files=all > "$INVENTARIO_TMP" \' \
    '  git status --porcelain=v1 -z --untracked-files=no > "$INVENTARIO_TMP" \'
}
M3() { # ignora a origem do rename
  troca "$FECHA" "        DIRTY=\"\$DIRTY\$origem_nome\"\$'\\n' ;;" '        : ;; # mutante: origem descartada'
}
M4() { # método genérico docs/** esconde produto
  troca "$FECHA" '    if grep -Fxq -- "$caminho" "$CATALOGO_TMP" && [ ! -L "$caminho" ]; then' \
    '    if case "$caminho" in docs/*) true ;; *) false ;; esac; then'
}
M5() { # irmã vira atual (ownership usa a união)
  troca "$OWN" "  elif declara \"\$1\" \"\$2\"; then printf '1\\t%s\\n' \"\$S_ATUAL\"" \
    "  elif [ -n \"\$(tasks_de \"\$2\")\" ]; then printf '1\\t%s\\n' \"\$S_ATUAL\""
}
M6() { # desvio omitido não é visto: só produto citado no plano é classificado
  troca "$FECHA" "      PRODUTO=\"\$PRODUTO\$caminho\"\$'\\n'" \
    "      grep -rFq -- \"\$caminho\" \"docs/sprintx/features/\$TRABALHO\" && PRODUTO=\"\$PRODUTO\$caminho\"\$'\\n'"
}
M7() { # inventário depois do git add
  troca "$FECHA" '    classifica_arvore "$TASK" "$@"     # 4 (M4: árvore inteira + dados)' \
    '    STAGING="$(printf '\''%s\n'\'' "$@")"; prepara; classifica_arvore "$TASK" "$@"' &&
  troca "$FECHA" '    prepara                            # 5 (A) e 6 (B)' '    : # mutante'
}
M8() { # stage existente é aceito
  troca "$FECHA" '    confere_stage_de_entrada           # 3' '    : # mutante: stage aceito'
}
M9() { # bloqueio consome seq
  troca "$FECHA" "      irma=\"\$(printf '%s\\n' \"\$saida\" | awk -F'\\t' '\$1 == \"arquivo_de_task_irma\" { print \"  - \" \$2 \"   (declarado em \" \$3 \")\" }')\"" \
    "      bash \"\$SEQ_SH\" --acrescentar \"\$ENTREGA\" \"\$task\" 0000000 >/dev/null 2>&1; irma=\"\$(printf '%s\\n' \"\$saida\" | awk -F'\\t' '\$1 == \"arquivo_de_task_irma\" { print \"  - \" \$2 }')\""
}
M10() { # bloqueio cria prova em ENTREGA.commits
  troca "$FECHA" "      irma=\"\$(printf '%s\\n' \"\$saida\" | awk -F'\\t' '\$1 == \"arquivo_de_task_irma\" { print \"  - \" \$2 \"   (declarado em \" \$3 \")\" }')\"" \
    "      bash \"\$SEQ_SH\" --acrescentar \"\$ENTREGA\" \"\$task\" \"\$(git rev-parse --short HEAD)\" >/dev/null 2>&1; irma=\"\$(printf '%s\\n' \"\$saida\" | awk -F'\\t' '\$1 == \"arquivo_de_task_irma\" { print \"  - \" \$2 }')\""
}
M11() { # bypass/timeout simulado: a irmã descoberta entra no commit
  troca "$FECHA" '  CLASSIFICACAO="$saida"' \
    "  CLASSIFICACAO=\"\$(printf '%s\\n' \"\$saida\" | sed 's/^arquivo_de_task_irma/na_task_atual/')\"; [ \"\$rc\" = 2 ] && rc=0"
}
M12() { # V9 vira unitária
  troca "$V9" '[ -n "$DECLARADOS" ] || exit 0' \
    "[ -n \"\$DECLARADOS\" ] || exit 0; DECLARADOS=\"\$(bash \"\$DIR/../../skills/mergex/scripts/ownership-da-task.sh\" --classificar \"\$RAIZ\" sprintx \"\$(expx_trabalho_atual_por_branch \"\$RAIZ\")\" \"\$(printf '%s\\n' \"\$CMD\" | sed -n 's/^Task:[[:space:]]*//p' | head -1)\" </dev/null 2>/dev/null | awk -F'\\t' '\$1 == \"declarado_nao_mudou\" { print \$2 }')\""
}

M13() { # produto da task atual omitido é absorvido (inclusão automática)
  troca "$FECHA" '  [ -z "$omitidos" ] || para 11 '\''PARADO — produto da task atual alterado e não listado no E1'\'' \' \
    '  omitidos=""; [ -z "$omitidos" ] || para 11 '\''mutante'\'' \' &&
  troca "$FECHA" '        printf '\''%s\n'\'' "$@" | grep -Fxq -- "$caminho" && printf '\''%s\n'\'' "$caminho"' \
    '        printf '\''%s\n'\'' "$caminho"'
}

LISTA='M1|só inspeciona os paths passados pelo agente
M2|ignora não rastreados
M3|ignora a origem do rename
M4|método genérico docs/** esconde produto
M5|irmã vira atual
M6|desvio omitido não é visto
M7|inventário roda depois do git add
M8|stage existente é aceito
M9|bloqueio consome seq
M10|bloqueio cria prova em ENTREGA.commits
M11|timeout/bypass simulado permite commit da irmã
M12|V9 vira unitária
M13|produto atual omitido é absorvido no commit'

FILTRAR=" $* "
FALHAS="$REPO/.mutacao-m4b-falhas-$$"
rm -f "$FALHAS"

printf 'Controle — cópia SEM mutação: a bancada M4-B tem que passar\n'
controle="$(copia)"
if ( cd "$controle" && bash "$BANCADA" > controle.log 2>&1 ); then
  printf 'ok    controle verde\n\n'
else
  printf 'FALHA controle sem mutação\n' >&2
  cat "$controle/controle.log" >&2
  exit 1
fi

printf '%s\n' "$LISTA" | while IFS='|' read -r id desc; do
  if [ "$FILTRAR" != '  ' ]; then case "$FILTRAR" in *" $id "*) ;; *) continue ;; esac; fi
  d="$(copia)"
  if ! ( cd "$d" && "$id" ); then
    printf 'FALHA %-4s mutação não aplicada — %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
    continue
  fi
  if ( cd "$d" && bash "$BANCADA" >/dev/null 2>&1 ); then
    printf 'VIVO  %-4s %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
  else
    printf 'morto %-4s %s\n' "$id" "$desc"
  fi
  rm -rf "$d"
done

if [ -f "$FALHAS" ]; then
  n="$(wc -l < "$FALHAS" | tr -d ' ')"
  rm -f "$FALHAS"
  printf '%s mutante(s) sobreviveram ou não foram aplicados\n' "$n" >&2
  exit 1
fi
printf '13 mutantes mortos\n'
