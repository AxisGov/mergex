#!/usr/bin/env bash
# Controle e mutacao do P0.2-C7-B / M2.
# Cada mutante altera somente uma copia temporaria e precisa ser morto pelo
# menor grupo da bancada que observa a propriedade violada.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PERSISTE='.claude/skills/mergex/scripts/persistir-metodo.sh'
FECHA='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
CMD='.claude/commands/mergex.md'
TMPS=""
FALHAS="$REPO/.mutacao-m2-falhas-$$"
trap 'for d in $TMPS; do rm -rf "$d"; done; rm -f "$FALHAS"' EXIT

copia() {
  local d
  d="$(mktemp -d)"; TMPS="$TMPS $d"
  ( cd "$REPO" && git ls-files -z -co --exclude-standard | xargs -0 tar -cf - ) \
    | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}

troca() { # <arquivo> <linha exata> <linha nova, que pode conter newline>
  local arq="$1" antes="$2" depois="$3"
  grep -Fxq -- "$antes" "$arq" || return 1
  A="$antes" B="$depois" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' \
    "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

remove_contendo() { # <arquivo> <literal>
  local arq="$1" literal="$2"
  grep -Fq -- "$literal" "$arq" || return 1
  S="$literal" awk 'index($0, ENVIRON["S"]) == 0 { print }' "$arq" > "$arq.m" || return 1
  mv "$arq.m" "$arq"
}

M1()  { remove_contendo "$CMD" '--checkpoint pre-e2'; }
M2()  { troca "$PERSISTE" 'adiciona "$ENTREGA"' 'adiciona "$ENTREGA"
adiciona "src/ORQUESTRADOR.md" # mutante: produto entra no catalogo'; }
M3()  { troca "$PERSISTE" '  printf '\''Metodo: %s\n'\'' "$CHECKPOINT"' '  printf '\''Task: T-00.00\n'\'' # mutante: metodo recebe Task
  printf '\''Metodo: %s\n'\'' "$CHECKPOINT"'; }
M4()  { troca "$PERSISTE" 'while IFS= read -r caminho; do' 'sed -i '\''s/^commits: \[\]$/commits:\n  - task: METHOD\n    commit: method/'\'' "$RAIZ/$ENTREGA" # mutante: metodo entra em ENTREGA.commits
while IFS= read -r caminho; do'; }
M5()  { troca "$PERSISTE" 'while IFS= read -r caminho; do' 'sed -i '\''s/^commits: \[\]$/commits:\n  - seq: 1\n    task: METHOD\n    commit: method/'\'' "$RAIZ/$ENTREGA" # mutante: metodo consome seq
while IFS= read -r caminho; do'; }
M6()  { troca "$PERSISTE" 'if [ "$MODO" = verificar ]; then' 'if [ "$MODO" = verificar ]; then
  printf '\''ok=true\n'\''; exit 0 # mutante: barreira aceita metodo dirty'; }
M7()  { remove_contendo "$CMD" '--checkpoint pre-e6'; }
M8()  { troca "$PERSISTE" 'adiciona "$ENTREGA"' '[ "$CHECKPOINT" = e8 ] || adiciona "$ENTREGA" # mutante: E8 deixa terminal dirty'; }
M9()  { troca "$FECHA" '  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \' '  git commit --allow-empty -qm '\''mutante: segundo E1'\'' # mutante: recovery cria commit
  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \'; }
M10() { troca "$FECHA" "  printf '%s\\n' \"\$sha\" | grep -Eq '^[0-9A-Fa-f]{40}\$' \\" "  printf '%s\\n' \"\$sha\" | grep -Eq '^[0-9A-Fa-f]{7,40}\$' \\"; }
M11() { troca "$FECHA" '  git merge-base --is-ancestor "$sha" HEAD >/dev/null 2>&1 \' '  true # mutante: ignora alcançabilidade
  true \'; }
M12() { troca "$FECHA" '  [ "$rc" = 0 ] || para 4 '\''PARADO — trailers do commit existente não provam este E1'\'' "$saida"' '  : # mutante: ignora trailers divergentes'; }
M13() { troca "$FECHA" '  verifica_ownership "$task" "${caminhos[@]}"' '  : # mutante: ignora ownership dos paths do commit'; }
M14() { troca "$FECHA" '      return 0' '      : # mutante: SHA ja registrado continua para novo append'; }
M15() { troca "$FECHA" '  sha="$(printf '\''%s'\'' "$sha" | tr '\''A-F'\'' '\''a-f'\'')"' '  sha="$(printf '\''%s'\'' "$sha" | tr '\''A-F'\'' '\''a-f'\'')"
  sha="$(git rev-parse HEAD)" # mutante: usa o ultimo commit, nao o informado'; }
M16() { troca "$FECHA" '  confere_stage_de_entrada' '  git reset -q # mutante: limpa stage alheio
  confere_stage_de_entrada'; }
M17() { troca "$FECHA" '  abre_secao "recovery:$task"          # mesma trava C5, antes de qualquer prova mutável' '  : # mutante: recovery ignora a trava C5'; }
M18() { troca "$FECHA" '  saida="$(bash "$SEQ_SH" --acrescentar "$entrega" "$task" "$sha" 2>&1)" \' '  saida='\''seq=1'\''; true # mutante: reporta sucesso sem registrar, V11 continua falhando
  true \'; }

LISTA='M1|integration|omite pre-e2 do fluxo
M2|lifecycle|inclui produto no commit de metodo
M3|lifecycle|adiciona Task ao commit de metodo
M4|lifecycle|insere commit de metodo em ENTREGA.commits
M5|lifecycle|faz commit de metodo consumir seq
M6|lifecycle|deixa E2 seguir com pre-e2 pendente
M7|integration|omite pre-e6 do fluxo
M8|lifecycle|deixa o terminal E8 dirty
M9|recovery|recovery cria um segundo commit
M10|recovery|aceita SHA abreviado na entrada
M11|recovery|aceita commit nao alcancavel de HEAD
M12|recovery|ignora trailers divergentes
M13|recovery|ignora ownership dos paths do commit
M14|recovery|duplica SHA ja registrado
M15|recovery|usa HEAD no lugar do SHA informado
M16|recovery|limpa stage preexistente
M17|recovery|ignora a trava C5
M18|v11|reporta recovery sem fazer V11 passar'

SEM_CONTROLE=false
if [ "${1:-}" = --sem-controle ]; then SEM_CONTROLE=true; shift; fi
FILTRAR=" $* "

if [ "$SEM_CONTROLE" = false ]; then
  printf 'Controle — copia SEM mutacao: toda a bancada M2 tem que passar\n'
  controle="$(copia)"
  if ( cd "$controle" && bash scripts/ci/test-m2-lifecycle-recuperacao.sh > controle.log 2>&1 ); then
    printf 'ok    controle verde\n\n'
  else
    printf 'FALHA controle sem mutacao\n' >&2
    cat "$controle/controle.log" >&2
    exit 1
  fi
else
  printf 'Controle ja executado separadamente — iniciando somente os mutantes\n\n'
fi

executa_mutante() { # <id> <grupo> <descricao>
  local id="$1" grupo="$2" desc="$3" d
  d="$(copia)"
  if ! ( cd "$d" && "$id" ); then
    printf 'FALHA %-4s mutacao nao aplicada — %s\n' "$id" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
    rm -rf "$d"
    return
  fi
  if ( cd "$d" && M2_FAIL_FAST=1 bash scripts/ci/test-m2-lifecycle-recuperacao.sh "$grupo" >/dev/null 2>&1 ); then
    printf 'VIVO  %-4s %-11s %s\n' "$id" "$grupo" "$desc"
    printf '%s\n' "$id" >> "$FALHAS"
  else
    printf 'morto %-4s %-11s %s\n' "$id" "$grupo" "$desc"
  fi
  rm -rf "$d"
}

# As copias nao compartilham Git, indice, stage nem lock. Quatro workers
# reduzem o custo de processo no Windows sem mudar o isolamento da prova.
ativos=0
total=0
while IFS='|' read -r id grupo desc; do
  if [ "$FILTRAR" != '  ' ]; then case "$FILTRAR" in *" $id "*) ;; *) continue ;; esac; fi
  ( trap - EXIT; executa_mutante "$id" "$grupo" "$desc" ) &
  ativos=$((ativos + 1))
  total=$((total + 1))
  if [ "$ativos" = 4 ]; then wait; ativos=0; fi
done <<EOF
$LISTA
EOF
wait

if [ -f "$FALHAS" ]; then
  n="$(wc -l < "$FALHAS" | tr -d ' ')"
  printf '%s mutante(s) sobreviveram ou nao foram aplicados\n' "$n" >&2
  exit 1
fi
printf '%s mutantes mortos\n' "$total"
