#!/usr/bin/env bash
# Bancada do P0.2 / reparo D-04 — valor efetivo de escalares YAML no HISTORICO.
#
# O CodeAnt apontou no PR #136, e um microteste confirmou contra o d3ca3aa,
# que `ler_historico` tirava as aspas e usava o miolo sem decodificar: grafias
# equivalentes ('d''agua', "tela\x20de cadastro", "diz \"oi\"", "d'agua")
# barravam como entrada reescrita, e "a\n" com quebra de linha comparava igual
# ao texto literal a\n — uma entrada histórica mudava de valor e a DM-175 não
# via. Aqui ficam, permanentes, os casos do microteste e os que a DM-176 fixa:
# grafia equivalente compara igual, valor diferente compara diferente, e
# escape que não cabe no contrato de uma linha ou fora do subconjunto barra —
# sempre antes do `git add`.
#
# As fixtures são as da bancada D-02 (base calibrada, C7-C, F6), carregadas
# com `.`. Portabilidade: rode também com outro awk primeiro no PATH (mawk).
#
# Uso: bash scripts/ci/test-d04-historico-yaml-escalar.sh [equivalencia|barra|identidade|sinais|first|checkpoints|e1]

set -uo pipefail

AQUI_D04="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-d02-historico-inicial.sh
. "$AQUI_D04/test-d02-historico-inicial.sh"

N_CASO=0
novo_repo() { N_CASO=$((N_CASO + 1)); CASO="$D/d04-$N_CASO"; }

# O que o checkpoint pede além do método já sujo, como na bancada D-02.
extra_checkpoint() { # <repo> <checkpoint>
  case "$2" in
    pre-e6) printf 'pr\n' > "$1/docs/entregas/$TRAB/PR.md" ;;
    e8) printf 'estado: bloqueado\n' >> "$1/$ENT" ;;
  esac
}

# Caso tracked: a base calibrada da D-02, com <head> no lugar da <ancora>
# (a N-ésima) já versionada em HEAD; a working tree faz o acréscimo da F6 do
# trabalho corrente e troca <head> por <wt>. Quando <head> difere da âncora,
# ele é uma linha só e única no arquivo; quando é igual, a âncora pode ser
# linha do próprio acréscimo da F6.
prepara_t() { # <repo> <ancora> <head> <wt> <ocorrencia>
  local repo="$1" ancora="$2" head="$3" wt="$4" n="$5" n_wt="$5"
  repo_c7c "$repo" calibrado || return 1
  if [ "$head" != "$ancora" ]; then
    grep -Fxq -- "$ancora" "$repo/$HIST" || { printf 'fixture sem a ancora: %s\n' "$ancora" >&2; return 1; }
    troca_linha "$repo/$HIST" "$ancora" "$head" "$n"
    git -C "$repo" commit -qam 'chore: grafia da base' || return 1
    n_wt=1
  fi
  conclui "$repo" T-01.01; conclui "$repo" T-02.01; acrescimo_f6 "$repo"
  if [ "$wt" != "$head" ]; then
    [ "$(grep -Fxc -- "$head" "$repo/$HIST")" -ge "$n_wt" ] \
      || { printf 'working tree sem a linha: %s\n' "$head" >&2; return 1; }
    troca_linha "$repo/$HIST" "$head" "$wt" "$n_wt"
  fi
}

passa_t() { # <descricao> <ancora> <head> <wt> [ocorrencia] [checkpoint]
  local descricao="$1" cp="${6:-pre-e2}" repo rc saida
  novo_repo; repo="$CASO"
  prepara_t "$repo" "$2" "$3" "$4" "${5:-1}" || { falha "fixture nao montou: $descricao"; return; }
  extra_checkpoint "$repo" "$cp"
  cp "$repo/$HIST" "$D/t.antes"
  saida="$(metodo "$repo" --persistir "$cp" 2>"$D/t.err")"; rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$saida" | grep -Eq '^commit=[0-9a-f]{40}$' \
     && nomes_head "$repo" | grep -Fxq "$HIST" \
     && git -C "$repo" show "HEAD:$HIST" | cmp -s - "$D/t.antes" \
     && [ -z "$(staged "$repo")" ] && trava_livre "$repo" \
     && metodo "$repo" --verificar "$cp" >/dev/null 2>&1; then
    ok "passa ($cp): $descricao"
  else
    falha "nao passou ($cp): $descricao (rc=$rc; $(head -n 1 "$D/t.err"))"
  fi
}

# Barra antes do `git add`: nenhum commit, stage vazio, trava livre, HEAD e
# arquivo intactos, e o motivo esperado na mensagem.
barra_t() { # <descricao> <trecho> <ancora> <head> <wt> [ocorrencia] [checkpoint]
  local descricao="$1" trecho="$2" cp="${7:-pre-e2}" repo rc antes head_antes
  novo_repo; repo="$CASO"
  prepara_t "$repo" "$3" "$4" "$5" "${6:-1}" || { falha "fixture nao montou: $descricao"; return; }
  extra_checkpoint "$repo" "$cp"
  cp "$repo/$HIST" "$D/t.antes"
  antes="$(commits "$repo")"; head_antes="$(git -C "$repo" rev-parse "HEAD:$HIST")"
  metodo "$repo" --persistir "$cp" >/dev/null 2>"$D/t.err"; rc=$?
  if [ "$rc" != 0 ] && grep -Fq -- "$trecho" "$D/t.err" \
     && [ "$(commits "$repo")" = "$antes" ] && [ -z "$(staged "$repo")" ] \
     && trava_livre "$repo" && [ "$(git -C "$repo" rev-parse "HEAD:$HIST")" = "$head_antes" ] \
     && cmp -s "$repo/$HIST" "$D/t.antes"; then
    ok "barra ($cp): $descricao"
  else
    falha "nao barrou ($cp): $descricao (rc=$rc; esperava '$trecho'; $(head -n 1 "$D/t.err"))"
  fi
}

AREA='    area: tela de cadastro'
REESCRITA='remove ou reescreve'
QUEBRA='controle ou quebra de linha'
SUBCONJUNTO='fora do subconjunto'
IMPRIMIVEL='fora de ASCII imprimível'

grupo_equivalencia() {
  printf '\nEQUIVALENCIA — mesma grafia efetiva, mesmo valor (DM-176)\n'
  passa_t 'C0 nenhuma mudanca semantica' "$AREA" "$AREA" "$AREA"
  passa_t 'C1 plain -> aspas simples' "$AREA" "$AREA" "    area: 'tela de cadastro'"
  passa_t 'C2 plain -> aspas duplas' "$AREA" "$AREA" '    area: "tela de cadastro"'
  passa_t 'C3 aspas simples -> aspas duplas' "$AREA" "    area: 'tela de cadastro'" '    area: "tela de cadastro"'
  passa_t "E1 d'agua -> 'd''agua'" "$AREA" "    area: d'agua" "    area: 'd''agua'"
  passa_t 'E3 tela de cadastro -> "tela\x20de cadastro"' "$AREA" "$AREA" '    area: "tela\x20de cadastro"'
  passa_t 'E4 diz "oi" -> "diz \"oi\""' "$AREA" '    area: diz "oi"' '    area: "diz \"oi\""'
  passa_t "E5 'd''agua' -> \"d'agua\"" "$AREA" "    area: 'd''agua'" "    area: \"d'agua\""
  passa_t 'E6 a\b -> "a\\b"' "$AREA" '    area: a\b' '    area: "a\\b"'
  passa_t "E7 a\\n -> 'a\\n' (aspas simples nao decodificam barra)" "$AREA" '    area: a\n' "    area: 'a\\n'"
  passa_t 'E8 a/b -> "a\/b"' "$AREA" '    area: a/b' '    area: "a\/b"'
  passa_t 'E9 tela de cadastro -> "tela\ de cadastro"' "$AREA" "$AREA" '    area: "tela\ de cadastro"'
  passa_t "E10 d'agua -> \"d\\x27agua\"" "$AREA" "    area: d'agua" '    area: "d\x27agua"'
  passa_t 'E11 Jota -> "\x4aota" (hexa minusculo)' "$AREA" '    area: Jota' '    area: "\x4aota"'
  passa_t 'E12 Jota -> "\x4Aota" (hexa maiusculo)' "$AREA" '    area: Jota' '    area: "\x4Aota"'
  passa_t "E13 aspas com comentario YAML depois" "$AREA" "    area: d'agua" "    area: \"d'agua\"  # grafia nova"
  passa_t 'E14 escape do lado de HEAD, plain na working tree' "$AREA" '    area: "tela\x20de cadastro"' "$AREA"
  passa_t 'E15 aspas simples com barra e aspa dobrada' "$AREA" "    area: 'a\\b d''agua'" "    area: \"a\\\\b d'agua\""
}

grupo_barra() {
  printf '\nBARRA — valor diferente, escape fora do contrato, aspas mal fechadas\n'
  barra_t 'C4 controle: valor realmente diferente' "$REESCRITA" "$AREA" "$AREA" '    area: tela de cadastros'
  barra_t 'F1 a\n literal -> "a\n" com quebra de linha' "$QUEBRA" "$AREA" '    area: a\n' '    area: "a\n"'
  barra_t "F2 'a\\n' -> \"a\\n\"" "$QUEBRA" "$AREA" "    area: 'a\\n'" '    area: "a\n"'
  barra_t "F2b d'agua -> \"d''agua\" (aspa dobrada nao e escape em aspas duplas)" "$REESCRITA" "$AREA" \
    "    area: d'agua" "    area: \"d''agua\""
  barra_t "F2c diz \"oi\" -> 'diz \\\"oi\\\"' (aspas simples nao decodificam)" "$REESCRITA" "$AREA" \
    '    area: diz "oi"' "    area: 'diz \\\"oi\\\"'"
  barra_t 'F2d aspas simples com \x20 e texto' "$REESCRITA" "$AREA" "$AREA" "    area: 'tela\\x20de cadastro'"
  # F3 — escape YAML válido fora do subconjunto: barra mesmo quando o valor
  # seria igual; nunca é conservado como texto.
  barra_t 'F3 \u0020 (valor igual, fora do subconjunto)' "$SUBCONJUNTO" "$AREA" "$AREA" '    area: "tela\u0020de cadastro"'
  barra_t 'F3b \U00000020' "$SUBCONJUNTO" "$AREA" "$AREA" '    area: "tela\U00000020de cadastro"'
  barra_t 'F3c \_ (espaco sem quebra)' "$SUBCONJUNTO" "$AREA" "$AREA" '    area: "tela\_de cadastro"'
  barra_t 'F3d escape invalido \q' 'escape inválido' "$AREA" "$AREA" '    area: "tela\qde cadastro"'
  barra_t 'F3e \x sem dois digitos' 'dois dígitos' "$AREA" "$AREA" '    area: "tela\x2 de cadastro"'
  barra_t 'F3f \x com digito nao hexadecimal' 'dois dígitos' "$AREA" "$AREA" '    area: "tela\xZZde cadastro"'
  barra_t 'F3g \x7f (DEL)' "$IMPRIMIVEL" "$AREA" "$AREA" '    area: "tela\x7fde cadastro"'
  barra_t 'F3h \xe9 (fora de ASCII)' "$IMPRIMIVEL" "$AREA" "$AREA" '    area: "tela\xe9de cadastro"'
  # F4 — TAB.
  barra_t 'F4 \t' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\tde cadastro"'
  barra_t 'F4b \x09' "$IMPRIMIVEL" "$AREA" "$AREA" '    area: "tela\x09de cadastro"'
  barra_t 'F4c barra seguida de TAB cru' 'tabulação' "$AREA" "$AREA" "$(printf '    area: "tela\\\tde cadastro"')"
  # F5 — CR/LF e demais controles.
  barra_t 'F5 \r' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\rde cadastro"'
  barra_t 'F5b \n' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\nde cadastro"'
  barra_t 'F5c \x0a' "$IMPRIMIVEL" "$AREA" "$AREA" '    area: "tela\x0ade cadastro"'
  barra_t 'F5d \0' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\0de cadastro"'
  barra_t 'F5e \x00' "$IMPRIMIVEL" "$AREA" "$AREA" '    area: "tela\x00de cadastro"'
  barra_t 'F5f \e' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\ede cadastro"'
  barra_t 'F5g \N (NEL)' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\Nde cadastro"'
  barra_t 'F5h \L (separador de linha)' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\Lde cadastro"'
  barra_t 'F5i \P (separador de paragrafo)' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\Pde cadastro"'
  barra_t 'F5j \a \b \v \f' "$QUEBRA" "$AREA" "$AREA" '    area: "tela\a\b\v\fde cadastro"'
  barra_t 'F5k controle cru \037 no plain (separador da saida)' 'caractere de controle' "$AREA" "$AREA" \
    "$(printf '    area: tela\037de cadastro')"
  barra_t 'F5l controle cru \001 entre aspas' 'caractere de controle' "$AREA" "$AREA" \
    "$(printf '    area: "tela\001de cadastro"')"
  # F6 — aspas mal fechadas.
  barra_t 'F6 aspas duplas sem fechamento' 'sem fechamento' "$AREA" "$AREA" '    area: "tela de cadastro'
  barra_t "F6b aspa simples solta no meio" 'depois das aspas' "$AREA" "$AREA" "    area: 'd'agua'"
  barra_t 'F6c barra escapando a aspa de fechamento' 'sem fechamento' "$AREA" "$AREA" '    area: "tela de cadastro\"'
  barra_t "F6d aspa dobrada no fim sem fechamento" 'sem fechamento' "$AREA" "$AREA" "    area: 'tela de cadastro''"
  # O lado de HEAD passa pelo mesmo leitor: escape fora do subconjunto lá
  # não serve de base.
  barra_t 'F7 HEAD com escape fora do subconjunto' 'em HEAD fora do contrato' "$AREA" \
    '    area: "tela\u0020de cadastro"' '    area: "tela\u0020de cadastro"'
  # Célula de identidade da tabela oficial com TAB cru deslocaria os campos
  # da saída e casaria Trabalho + Task com outra linha.
  barra_t 'F8 TAB cru na celula de identidade da tabela oficial' 'caractere de controle em linha oficial' \
    "$LINHA_ANT_T0201" "$LINHA_ANT_T0201" \
    "$LINHA_ANT_T0201
$(printf '| %s\tT-01.01 | outra task | ui | accountability | — | — | — | 1 h | — |' "$TRAB")"
}

grupo_identidade() {
  printf '\nIDENTIDADE — trabalho_id, task_id e tipo_task pelo valor efetivo\n'
  local T3='    task_id: T-03.01' W4='  - trabalho_id: trabalho-anterior' TI='    tipo_task: infra'
  passa_t "task_id T-03.01 -> 'T-03.01'" "$T3" "$T3" "    task_id: 'T-03.01'"
  passa_t 'task_id T-03.01 -> "T-03.01"' "$T3" "$T3" '    task_id: "T-03.01"'
  passa_t 'task_id T-03.01 -> "T\x2d03.01"' "$T3" "$T3" '    task_id: "T\x2d03.01"'
  passa_t "task_id 'T-03.01' em HEAD -> \"T-03.01\"" "$T3" "    task_id: 'T-03.01'" '    task_id: "T-03.01"'
  passa_t 'trabalho_id -> "trabalho-anterior"' "$W4" "$W4" '  - trabalho_id: "trabalho-anterior"' 4
  passa_t 'trabalho_id -> "trabalho\x2danterior"' "$W4" "$W4" '  - trabalho_id: "trabalho\x2danterior"' 4
  passa_t "tipo_task infra -> 'infra'" "$TI" "$TI" "    tipo_task: 'infra'"
  passa_t 'tipo_task infra -> "\x69nfra"' "$TI" "$TI" '    tipo_task: "\x69nfra"'
  # Entrada nova do trabalho corrente com identidade entre aspas: é dele.
  passa_t 'entrada nova com trabalho_id entre aspas e escape' "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB" \
    '  - trabalho_id: "issue-123-rotulo\x2dparecer"' 1
  passa_t "entrada nova com task_id 'T-01.01'" '    task_id: T-01.01' '    task_id: T-01.01' "    task_id: 'T-01.01'" 2
  passa_t 'entrada nova com tipo_task "\x61pi"' '    tipo_task: api' '    tipo_task: api' '    tipo_task: "\x61pi"' 3

  barra_t 'trabalho_id com espaco a mais dentro das aspas' "$REESCRITA" "$W4" "$W4" '  - trabalho_id: "trabalho-anterior "' 4
  barra_t "trabalho_id 'trabalho\\x2danterior' (aspas simples nao decodificam)" "$REESCRITA" "$W4" "$W4" \
    "  - trabalho_id: 'trabalho\\x2danterior'" 4
  barra_t 'task_id "T-03.01\x20"' "$REESCRITA" "$T3" "$T3" '    task_id: "T-03.01\x20"'
  barra_t 'tipo_task "infra " fora do enum' 'enum' "$TI" "$TI" '    tipo_task: "infra "'
  # Canonicalizar não pode mudar o dono: a entrada anterior citada com o id do
  # trabalho corrente é a entrada anterior removida.
  barra_t 'entrada anterior regravada como do trabalho corrente, entre aspas' "$REESCRITA" "$W4" "$W4" \
    "  - trabalho_id: \"$TRAB\"" 4
  barra_t 'entrada nova de "outro-trabalho"' 'outro trabalho' "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB" \
    '  - trabalho_id: "outro-trabalho"' 1
  barra_t 'entrada nova de outro trabalho por escape' 'outro trabalho' "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB" \
    '  - trabalho_id: "issue-123-rotulo-parecer\x2dx"' 1
  barra_t 'trabalho_id com \t' "$QUEBRA" "  - trabalho_id: $TRAB" "  - trabalho_id: $TRAB" \
    '  - trabalho_id: "issue-123-rotulo-parecer\t"' 1
  # Duplicata é pelo valor: a mesma entrada em outra grafia é a mesma entrada.
  barra_t 'entrada nova duplicada em outra grafia' 'duplicada' 'calibracao:' 'calibracao:' \
    "  - trabalho_id: \"$TRAB\"
    task_id: \"T\\x2d01.01\"
    tipo_task: api
    area: accountability
    sinais: []
    real: 3
    desvio: null
    registrado_em: 2026-09-26
calibracao:" 1
}

grupo_sinais() {
  printf '\nSINAIS — itens pelo mesmo decodificador, ordem e cardinalidade preservadas\n'
  local S1='    sinais: [sem_cobertura, integracao_externa]' S0='    sinais: []'
  passa_t "[\"d'agua\"] -> bloco 'd''agua'" "$S0" "    sinais: [\"d'agua\"]" "    sinais:
      - 'd''agua'"
  passa_t "['d''agua'] -> [\"d\\x27agua\"]" "$S0" "    sinais: ['d''agua']" '    sinais: ["d\x27agua"]'
  passa_t 'inline plain -> inline entre aspas com escape' "$S1" "$S1" \
    "    sinais: ['sem_cobertura', \"integracao\\x5fexterna\"]"
  passa_t 'inline plain -> bloco entre aspas com comentario' "$S1" "$S1" "    sinais:
      - \"sem\\x5fcobertura\"
      - 'integracao_externa'  # como na estimativa"

  barra_t 'ordem trocada' "$REESCRITA" "$S1" "$S1" '    sinais: [integracao_externa, sem_cobertura]'
  barra_t 'ordem trocada entre aspas' "$REESCRITA" "$S1" "$S1" "    sinais: ['integracao_externa', \"sem_cobertura\"]"
  barra_t 'cardinalidade: item repetido' "$REESCRITA" "$S1" "$S1" \
    "    sinais: [sem_cobertura, 'sem_cobertura', integracao_externa]"
  barra_t 'cardinalidade: item a menos' "$REESCRITA" "$S1" "$S1" "    sinais: ['sem_cobertura']"
  barra_t 'itens distintos fundidos' "$REESCRITA" "$S1" "$S1" '    sinais: ["sem_cobertura integracao_externa"]'
  barra_t "[\"d'agua\"] -> [\"d''agua\"]" "$REESCRITA" "$S0" "    sinais: [\"d'agua\"]" "    sinais: [\"d''agua\"]"
  barra_t 'item com \n' "$QUEBRA" "$S1" "$S1" '    sinais: [sem_cobertura, "integracao\nexterna"]'
  barra_t 'item em bloco com \r' "$QUEBRA" "$S1" "$S1" "    sinais:
      - sem_cobertura
      - \"integracao_externa\\r\""
  barra_t 'item fora do subconjunto' "$SUBCONJUNTO" "$S1" "$S1" '    sinais: [sem_cobertura, "\u0069ntegracao_externa"]'
  barra_t 'item entre aspas vazio depois de decodificar' 'item inválido' "$S1" "$S1" "    sinais: [sem_cobertura, '']"
}

# Primeira criação (DM-174) com identidade, valores e sinais entre aspas e
# escapes suportados: a leitura é a mesma do caminho tracked.
AREA_DUPLA='    area: "d'\''agua \"x\" a\\b a\/b\ c"'
AREA_DUPLA_PLANA='    area: d'\''agua "x" a\b a/b c'
AREA_SIMPLES='    area: '\''a\n d'\'\''agua'\'
AREA_SIMPLES_PLANA='    area: a\n d'\''agua'
SINAIS_CITADOS='    sinais: ['\''d'\'\''agua'\'', "x\x20y"]'
SINAIS_PLANOS="    sinais:
      - d'agua
      - x y"

f_citado() {
  local h="$1/$HIST"
  troca_linha "$h" "  - trabalho_id: $TRAB" '  - trabalho_id: "issue-123-rotulo\x2dparecer"'
  troca_linha "$h" "  - trabalho_id: $TRAB" "  - trabalho_id: '$TRAB'"
  troca_linha "$h" '    task_id: T-01.01' '    task_id: "T-01.01"  # entre aspas'
  troca_linha "$h" '    task_id: T-02.01' "    task_id: 'T-02.01'"
  troca_linha "$h" '    tipo_task: teste' '    tipo_task: "t\x65ste"'
  troca_linha "$h" '    tipo_task: ui' "    tipo_task: 'ui'"
  troca_linha "$h" '    area: accountability' "$AREA_DUPLA"
  troca_linha "$h" '    area: accountability' "$AREA_SIMPLES"
  troca_linha "$h" '    sinais: []' "$SINAIS_CITADOS"
  troca_linha "$h" '    registrado_em: 2026-09-26' '    registrado_em: "2026-09-26"'
}
f_barra_n() { troca_linha "$1/$HIST" '    area: accountability' '    area: "a\n"'; }
f_barra_u() { troca_linha "$1/$HIST" '    area: accountability' '    area: "\u0061ccountability"'; }
f_barra_x09() { troca_linha "$1/$HIST" '    area: accountability' '    area: "account\x09ability"'; }
f_barra_q() { troca_linha "$1/$HIST" '    area: accountability' '    area: "account\qability"'; }
f_outro_escape() { troca_linha "$1/$HIST" "  - trabalho_id: $TRAB" '  - trabalho_id: "outro\x2dtrabalho"'; }
f_task_simples() { troca_linha "$1/$HIST" '    task_id: T-02.01' "    task_id: 'T\\x2d02.01'"; }
f_task_espaco() { troca_linha "$1/$HIST" '    task_id: T-01.01' '    task_id: "T-01.01\x20"'; }
f_sinal_r() { troca_linha "$1/$HIST" '    sinais: []' '    sinais: ["a\r"]'; }
f_mal_fechada() { troca_linha "$1/$HIST" '    area: accountability' "    area: 'd'agua'"; }
f_controle_cru() { troca_linha "$1/$HIST" '    area: accountability' "$(printf '    area: account\037ability')"; }
f_tipo_espaco() { troca_linha "$1/$HIST" '    tipo_task: ui' '    tipo_task: "ui\x20"'; }

grupo_first() {
  local repo rc
  printf '\nFIRST — primeira criacao com aspas e escapes, pelo mesmo leitor\n'
  aceita 'FIRST com identidade, valores e sinais entre aspas e escapes suportados' f_citado

  # Leitura integral correta: o que a primeira criação versionou é lido como
  # valor. Reescrito em plain equivalente, o caminho tracked aceita; um
  # valor diferente, barra.
  novo_repo; repo="$CASO"; repo_c7c "$repo"; fim_da_f6 "$repo"; f_citado "$repo"
  metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/first.err"; rc=$?
  [ "$rc" = 0 ] || falha "FIRST citado nao persistiu (rc=$rc; $(cat "$D/first.err"))"
  troca_linha "$repo/$HIST" '  - trabalho_id: "issue-123-rotulo\x2dparecer"' "  - trabalho_id: $TRAB"
  troca_linha "$repo/$HIST" "  - trabalho_id: '$TRAB'" "  - trabalho_id: $TRAB"
  troca_linha "$repo/$HIST" '    task_id: "T-01.01"  # entre aspas' '    task_id: T-01.01'
  troca_linha "$repo/$HIST" '    tipo_task: "t\x65ste"' '    tipo_task: teste'
  troca_linha "$repo/$HIST" "$AREA_DUPLA" "$AREA_DUPLA_PLANA"
  troca_linha "$repo/$HIST" "$AREA_SIMPLES" "$AREA_SIMPLES_PLANA"
  troca_linha "$repo/$HIST" "$SINAIS_CITADOS" "$SINAIS_PLANOS"
  printf 'pr\n' > "$repo/docs/entregas/$TRAB/PR.md"
  metodo "$repo" --persistir pre-e6 >/dev/null 2>"$D/first.err"; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
    && ok 'FIRST lido pelo valor: grafia plain equivalente passa no tracked seguinte' \
    || falha "FIRST nao foi lido pelo valor (rc=$rc; $(cat "$D/first.err"))"
  troca_linha "$repo/$HIST" '      - x y' '      - x  y'
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  metodo "$repo" --persistir e8 >/dev/null 2>"$D/first.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq "$REESCRITA" "$D/first.err" && [ -z "$(staged "$repo")" ] \
    && ok 'FIRST lido pelo valor: valor diferente barra no e8 seguinte' \
    || falha "FIRST: valor diferente passou no e8 (rc=$rc; $(cat "$D/first.err"))"

  nega 'FIRST area "a\n"' f_barra_n
  nega 'FIRST area com \u' f_barra_u
  nega 'FIRST area com \x09' f_barra_x09
  nega 'FIRST area com escape invalido' f_barra_q
  nega 'FIRST trabalho_id de outro trabalho por escape' f_outro_escape
  nega "FIRST task_id 'T\\x2d02.01' em aspas simples (nao decodifica)" f_task_simples
  nega 'FIRST task_id "T-01.01\x20"' f_task_espaco
  nega 'FIRST item de sinais com \r' f_sinal_r
  nega 'FIRST aspas mal fechadas' f_mal_fechada
  nega 'FIRST controle cru no valor' f_controle_cru
  nega 'FIRST tipo_task "ui\x20" fora do enum' f_tipo_espaco
}

grupo_checkpoints() {
  local repo rc
  printf '\nCHECKPOINTS — pre-e2, pre-e6 e e8 com o mesmo leitor\n'
  local cp
  for cp in pre-e2 pre-e6 e8; do
    passa_t "E1 d'agua -> 'd''agua'" "$AREA" "    area: d'agua" "    area: 'd''agua'" 1 "$cp"
    passa_t 'E3 "tela\x20de cadastro"' "$AREA" "$AREA" '    area: "tela\x20de cadastro"' 1 "$cp"
    barra_t 'F1 a\n -> "a\n"' "$QUEBRA" "$AREA" '    area: a\n' '    area: "a\n"' 1 "$cp"
    barra_t 'F3 \u0020' "$SUBCONJUNTO" "$AREA" "$AREA" '    area: "tela\u0020de cadastro"' 1 "$cp"
  done

  # e8 sem checkpoint anterior: a primeira criação citada passa, a com "a\n"
  # barra antes do git add.
  novo_repo; repo="$CASO"; repo_c7c "$repo"; fim_da_f6 "$repo"; f_citado "$repo"
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  metodo "$repo" --persistir e8 >/dev/null 2>"$D/cp.err"; rc=$?
  [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" && metodo "$repo" --verificar e8 >/dev/null 2>&1 \
    && ok 'e8 persiste a primeira criacao citada' \
    || falha "e8 recusou a primeira criacao citada (rc=$rc; $(cat "$D/cp.err"))"
  novo_repo; repo="$CASO"; repo_c7c "$repo"; fim_da_f6 "$repo"; f_barra_n "$repo"
  printf 'estado: bloqueado\n' >> "$repo/$ENT"
  metodo "$repo" --persistir e8 >/dev/null 2>"$D/cp.err"; rc=$?
  [ "$rc" != 0 ] && grep -Fq "$QUEBRA" "$D/cp.err" && [ -z "$(staged "$repo")" ] \
    && [ -z "$(no_head "$repo")" ] && trava_livre "$repo" \
    && ok 'e8 barra a primeira criacao com "a\n" antes do git add' \
    || falha "e8 aceitou a primeira criacao com \"a\\n\" (rc=$rc; $(cat "$D/cp.err"))"
}

grupo_e1() {
  local repo rc msg caso
  printf '\nE1 — o HISTORICO citado continua metodo, nunca produto da task\n'
  for caso in equivalente invalido; do
    novo_repo; repo="$CASO"; repo_c7c "$repo" calibrado
    conclui "$repo" T-01.01
    printf 'test("rotulo", () => {});\n' > "$repo/test/rotulo.test.js"
    if [ "$caso" = equivalente ]; then
      troca_linha "$repo/$HIST" "$AREA" '    area: "tela\x20de cadastro"'
    else
      troca_linha "$repo/$HIST" "$AREA" '    area: "tela\nde cadastro"'
    fi
    msg="$D/e1-$caso.msg"
    printf 'test(rotulo): cobre rotulo do parecer\n\nTask: T-01.01\nTrabalho: %s\n' "$TRAB" > "$msg"
    (cd "$repo" && bash "$FECHA" --fechar --entrega "$ENT" --task T-01.01 --mensagem "$msg" \
      -- test/rotulo.test.js) >"$D/e1.out" 2>&1; rc=$?
    [ "$rc" = 0 ] && [ "$(nomes_head "$repo")" = 'test/rotulo.test.js' ] \
      && [ "$(git -C "$repo" status --porcelain -- "$HIST")" = " M $HIST" ] \
      && ok "E1 ($caso) commita so o produto e nao absorve o HISTORICO" \
      || falha "E1 ($caso) absorveu ou barrou (rc=$rc; $(tail -n 3 "$D/e1.out"))"
    metodo "$repo" --persistir pre-e2 >/dev/null 2>"$D/e1.err"; rc=$?
    if [ "$caso" = equivalente ]; then
      [ "$rc" = 0 ] && nomes_head "$repo" | grep -Fxq "$HIST" \
        && ok 'depois do E1, pre-e2 versiona a grafia equivalente' \
        || falha "pre-e2 recusou a grafia equivalente depois do E1 (rc=$rc; $(cat "$D/e1.err"))"
    else
      [ "$rc" != 0 ] && grep -Fq "$QUEBRA" "$D/e1.err" && [ -z "$(staged "$repo")" ] \
        && [ "$(git -C "$repo" status --porcelain -- "$HIST")" = " M $HIST" ] \
        && ok 'depois do E1, pre-e2 barra "\n" antes do git add' \
        || falha "pre-e2 aceitou \"\\n\" depois do E1 (rc=$rc; $(cat "$D/e1.err"))"
    fi
  done
}

grupo="${1:-all}"
case "$grupo" in
  all) grupo_equivalencia; grupo_barra; grupo_identidade; grupo_sinais; grupo_first; grupo_checkpoints; grupo_e1 ;;
  equivalencia) grupo_equivalencia ;;
  barra) grupo_barra ;;
  identidade) grupo_identidade ;;
  sinais) grupo_sinais ;;
  first) grupo_first ;;
  checkpoints) grupo_checkpoints ;;
  e1) grupo_e1 ;;
  *) printf 'grupo desconhecido: %s\n' "$grupo" >&2; exit 64 ;;
esac

printf '\n---------------------------------------------\n'
printf '%s ok, %s falha(s)\n' "$OK" "$FALHOU"
[ "$FALHOU" = 0 ]
