#!/usr/bin/env bash
# persistir-metodo — catálogo e lifecycle versionado dos artefatos de método.
#
# O trabalho corrente vem exclusivamente dos argumentos explícitos, conferidos
# contra ENTREGA.md. A branch ativa é somente uma prova de consistência.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_SH="$AQUI/../../../hooks/comum/base.sh"
TRAVA_SH="$AQUI/trava-do-e1.sh"
CONTRATO_SH="$AQUI/contrato-de-commit.sh"
SEGREDO_SH="$AQUI/../../../hooks/comum/sem-segredo.sh"
CATALOGO_SH="$AQUI/catalogo-de-metodo.sh"
PROVA_SH="$AQUI/prova-de-commit.sh"

for dependencia in "$BASE_SH" "$TRAVA_SH" "$CONTRATO_SH" "$SEGREDO_SH" "$CATALOGO_SH" "$PROVA_SH"; do
  [ -r "$dependencia" ] || { printf 'persistir-metodo: dependência indisponível: %s\n' "$dependencia" >&2; exit 1; }
done
# shellcheck source=../../../hooks/comum/base.sh
. "$BASE_SH"
# shellcheck source=trava-do-e1.sh
. "$TRAVA_SH"
# shellcheck source=catalogo-de-metodo.sh
. "$CATALOGO_SH"
set +e

MODO=""
ENTREGA=""
ORIGEM=""
TRABALHO=""
CHECKPOINT=""

uso() {
  printf '%s\n' \
    'uso: persistir-metodo.sh --listar|--persistir|--verificar --entrega <ENTREGA.md> --origem <sprintx|runx> --trabalho <id> --checkpoint <pre-e2|pre-e6|e8>' >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --listar) [ -z "$MODO" ] || uso; MODO=listar; shift ;;
    --persistir) [ -z "$MODO" ] || uso; MODO=persistir; shift ;;
    --verificar) [ -z "$MODO" ] || uso; MODO=verificar; shift ;;
    --entrega) [ "$#" -ge 2 ] || uso; ENTREGA="$2"; shift 2 ;;
    --origem) [ "$#" -ge 2 ] || uso; ORIGEM="$2"; shift 2 ;;
    --trabalho) [ "$#" -ge 2 ] || uso; TRABALHO="$2"; shift 2 ;;
    --checkpoint) [ "$#" -ge 2 ] || uso; CHECKPOINT="$2"; shift 2 ;;
    *) uso ;;
  esac
done

case "$MODO" in listar|persistir|verificar) ;; *) uso ;; esac
case "$ORIGEM" in sprintx|runx) ;; *) uso ;; esac
case "$CHECKPOINT" in pre-e2|pre-e6|e8) ;; *) uso ;; esac
case "$TRABALHO" in
  ''|*[!A-Za-z0-9._-]*|.*|sprintx|manutencao|entregas|eventos|relatorios|legado|stack|projeto) uso ;;
esac

RAIZ="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'persistir-metodo: fora de um repositório Git\n' >&2
  exit 1
}

fm() { expx_frontmatter_valor "$1" "$2"; }

para() {
  printf 'persistir-metodo: %s\n' "$1" >&2
  exit 1
}

TOKEN=""
LIBERAR_NA_SAIDA=0
TMP_LISTA=""
TMP_MSG=""
TMP_CATALOGO=""

encerrar() {
  local rc="$1"
  [ -z "$TMP_LISTA" ] || rm -f "$TMP_LISTA"
  [ -z "$TMP_MSG" ] || rm -f "$TMP_MSG"
  [ -z "$TMP_CATALOGO" ] || rm -f "$TMP_CATALOGO"
  if [ "$LIBERAR_NA_SAIDA" = 1 ] && [ -n "$TOKEN" ]; then
    liberar "$TOKEN" >/dev/null 2>&1
  fi
  exit "$rc"
}
trap 'encerrar $?' EXIT

if [ "$MODO" = persistir ]; then
  SAIDA_TRAVA="$(adquirir "metodo:$CHECKPOINT")"; RC_TRAVA=$?
  if [ "$RC_TRAVA" = 2 ]; then
    printf 'persistir-metodo: índice ocupado pela trava C5\n' >&2
    exit 2
  fi
  [ "$RC_TRAVA" = 0 ] || para 'não foi possível adquirir a trava C5 do índice'
  TOKEN="$(printf '%s\n' "$SAIDA_TRAVA" | awk -F= '$1 == "token" { print $2 }')"
  [ -n "$TOKEN" ] || para 'a trava C5 foi criada sem token'
  LIBERAR_NA_SAIDA=1
fi

if [ "$MODO" = persistir ] || [ "$MODO" = verificar ]; then
  if [ -n "$(git diff --cached --name-only 2>/dev/null)" ]; then
    para 'o stage já estava preenchido; nada foi limpo ou adotado'
  fi
fi

# O caminho da entrega também é evidência explícita: ele não é procurado por
# branch, mtime ou glob. Aceita apenas a forma canônica relativa ao repositório.
case "$ENTREGA" in ./*) ENTREGA="${ENTREGA#./}" ;; esac
ENTREGA_ESPERADA="docs/entregas/$TRABALHO/ENTREGA.md"
[ "$ENTREGA" = "$ENTREGA_ESPERADA" ] || para "--entrega deve ser $ENTREGA_ESPERADA"
[ -f "$RAIZ/$ENTREGA" ] && [ ! -L "$RAIZ/$ENTREGA" ] || para "$ENTREGA não é arquivo regular"
[ "$(fm "$RAIZ/$ENTREGA" kind)" = entrega ] || para "$ENTREGA não declara kind: entrega"
[ "$(fm "$RAIZ/$ENTREGA" trabalho_id)" = "$TRABALHO" ] || para "trabalho explícito diverge de ENTREGA.trabalho_id"
[ "$(fm "$RAIZ/$ENTREGA" expx_tool)" = "$ORIGEM" ] || para "origem explícita diverge de ENTREGA.expx_tool"

BRANCH="$(git branch --show-current 2>/dev/null)" || BRANCH=""
[ -n "$BRANCH" ] || para 'HEAD destacado: branch não pode provar consistência'
[ "$(fm "$RAIZ/$ENTREGA" branch)" = "$BRANCH" ] || para "branch ativa diverge de ENTREGA.branch"

if [ "$ORIGEM" = sprintx ]; then
  CANONICA="docs/sprintx/features/$TRABALHO"
  LEGADA="docs/$TRABALHO"
  if [ -d "$RAIZ/$CANONICA" ] && [ -d "$RAIZ/$LEGADA" ]; then
    para "há duas pastas SprintX para $TRABALHO"
  elif [ -d "$RAIZ/$CANONICA" ]; then
    PASTA="$CANONICA"
  elif [ -d "$RAIZ/$LEGADA" ]; then
    PASTA="$LEGADA"
  else
    para "pasta SprintX do trabalho não existe"
  fi
else
  PASTA="docs/manutencao/$TRABALHO"
  [ -d "$RAIZ/$PASTA" ] || para "pasta RunX do trabalho não existe"
fi

ORQUESTRADOR="$RAIZ/$PASTA/ORQUESTRADOR.md"
[ -f "$ORQUESTRADOR" ] && [ ! -L "$ORQUESTRADOR" ] || para "$PASTA/ORQUESTRADOR.md não é arquivo regular"
[ "$(fm "$ORQUESTRADOR" kind)" = orquestrador ] || para "$PASTA/ORQUESTRADOR.md não declara kind: orquestrador"
[ "$(fm "$ORQUESTRADOR" trabalho_id)" = "$TRABALHO" ] || para "ORQUESTRADOR.md pertence a outro trabalho"

TMP_LISTA="$(mktemp "${TMPDIR:-/tmp}/mergex-metodo.XXXXXX")" || para 'não foi possível criar lista temporária'

sujo() {
  [ -n "$(git -C "$RAIZ" status --porcelain=v1 --untracked-files=all -- "$1" 2>/dev/null)" ]
}

adiciona() {
  local caminho="$1"
  [ -f "$RAIZ/$caminho" ] && [ ! -L "$RAIZ/$caminho" ] || return 0
  sujo "$caminho" || return 0
  printf '%s\n' "$caminho" >> "$TMP_LISTA"
}

# Primeira criação do HISTORICO global (DM-174). Sem versão em HEAD não existe
# diff que prove ownership: a prova é sobre o ARQUIVO INTEIRO, e falha fechado.
# Só depois dela o arquivo entra no commit de método, e dali em diante ele é
# tracked e cai na prova por diff de confere_historico_corrente.
confere_historico_inicial() {
  local caminho='docs/sprintx/estimativas/HISTORICO.md' presenca parcial componente
  local dir nome concluidas motivo
  git -C "$RAIZ" rev-parse -q --verify 'HEAD^{commit}' >/dev/null 2>&1 \
    || para 'HISTORICO global inicial sem HEAD para provar a ausência da versão anterior'
  presenca="$(git -C "$RAIZ" ls-tree --name-only HEAD -- "$caminho" 2>/dev/null)" \
    || para 'não foi possível provar a ausência do HISTORICO global em HEAD'
  [ -z "$presenca" ] \
    || para 'HISTORICO global existe em HEAD, mas está fora do índice; estado anômalo não é primeira criação'

  parcial="$RAIZ"
  for componente in docs sprintx estimativas HISTORICO.md; do
    parcial="$parcial/$componente"
    [ ! -L "$parcial" ] || para 'HISTORICO global inicial passa por link simbólico'
  done
  [ -f "$RAIZ/$caminho" ] || para 'HISTORICO global inicial não é arquivo regular'

  # Tasks concluídas do trabalho corrente, pelo leitor único da V11, sobre os
  # tasks.md que o catálogo reconhece como sprints deste trabalho.
  set --
  for dir in "$RAIZ/$PASTA"/sprint-*; do
    [ -d "$dir" ] || continue
    nome="$(basename "$dir")"
    printf '%s\n' "$nome" | grep -Eq '^sprint-[0-9]{2,}$' || continue
    [ -f "$dir/tasks.md" ] && set -- "$@" "$dir/tasks.md"
  done
  concluidas=""
  if [ "$#" -gt 0 ]; then
    concluidas="$(bash "$PROVA_SH" --concluidas "$@" 2>/dev/null)" \
      || para 'HISTORICO global inicial: tasks do trabalho ilegíveis'
    concluidas="$(printf '%s\n' "$concluidas" | cut -f1 | LC_ALL=C sort -u)"
  fi

  motivo="$(HIST_TRABALHO="$TRABALHO" HIST_CONCLUIDAS="$concluidas" awk '
    function erro(m) { if (!falhou) print m; falhou = 1; exit 1 }
    function apara(v) { sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); return v }
    function escalar(v) {
      v = apara(v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      return v
    }
    function cita_tasks(texto,   id) {
      while (match(texto, /T-[0-9]+\.[0-9]+/)) {
        id = substr(texto, RSTART, RLENGTH)
        if (!(id in concluida)) erro("cita task que não é concluída do trabalho corrente: " id)
        texto = substr(texto, RSTART + RLENGTH)
      }
    }
    function cita_trabalho(texto,   v) {
      while (match(texto, /trabalho_id:[[:space:]]*[^[:space:]`|,;]+/)) {
        v = substr(texto, RSTART, RLENGTH); sub(/^trabalho_id:[[:space:]]*/, "", v)
        gsub(/["\047]/, "", v)
        if (v != trabalho && v != "null") erro("cita outro trabalho: " v)
        texto = substr(texto, RSTART + RLENGTH)
      }
    }
    function fecha_item(   k) {
      if (!item) return
      if (secao == "entradas" && !("trabalho_id" in tem)) erro("entrada sem trabalho_id")
      if (secao == "entradas" && !("task_id" in tem)) erro("entrada sem task_id")
      if (secao == "calibracao" && !("tipo_task" in tem)) erro("calibração sem tipo_task")
      for (k in tem) delete tem[k]
      item = 0
    }
    function campo(chave, valor,   v) {
      if (secao == "entradas") {
        if (!(chave in campo_entrada)) erro("entrada com chave fora do contrato: " chave)
      } else if (secao == "calibracao") {
        if (!(chave in campo_calibracao)) erro("calibração com chave fora do contrato: " chave)
      } else erro("item fora de entradas/calibracao")
      if (chave in tem) erro("chave repetida no mesmo item: " chave)
      tem[chave] = 1
      v = escalar(valor)
      if (secao == "entradas" && chave == "trabalho_id" && v != trabalho)
        erro("entrada de outro trabalho: " v)
      if (secao == "entradas" && chave == "task_id") {
        if (!(v in concluida)) erro("entrada de task que não é concluída do trabalho corrente: " v)
        if (v in registrada) erro("entrada duplicada para a task: " v)
        registrada[v] = 1
      }
      if (chave == "tipo_task" && !(v in tipo)) erro("tipo_task fora do enum: " v)
      if (chave != "task_id") cita_tasks(valor)
      cita_trabalho(valor)
    }
    function linha_tabela(   partes, c1, c2) {
      split($0, partes, "|")
      c1 = apara(partes[2]); c2 = apara(partes[3])
      if (tabela == "") {
        if (c1 == "Trabalho") tabela = "entradas"
        else if (c1 == "Tipo de task") tabela = "calibracao"
        else erro("tabela fora do contrato no corpo: " c1)
        separador = 1; return
      }
      if (separador) {
        if ($0 !~ /^[[:space:]]*\|([[:space:]]*:?-+:?[[:space:]]*\|)+[[:space:]]*$/)
          erro("tabela sem linha separadora")
        separador = 0; return
      }
      if (tabela == "entradas") {
        if (c1 != trabalho) erro("linha da tabela de entradas de outro trabalho: " c1)
        if (!(c2 in concluida)) erro("linha da tabela de task que não é concluída do trabalho corrente: " c2)
        if (c2 in linha_vista) erro("linha duplicada na tabela de entradas: " c2)
        linha_vista[c2] = 1
      } else if (!(c1 in tipo)) erro("linha da tabela de calibração fora do enum tipo_task: " c1)
    }
    BEGIN {
      trabalho = ENVIRON["HIST_TRABALHO"]
      n = split(ENVIRON["HIST_CONCLUIDAS"], lista, "\n")
      for (i = 1; i <= n; i++) if (lista[i] != "") concluida[lista[i]] = 1
      n = split("expx_schema expx_tool kind trabalho_id atualizado_em unidade entradas calibracao", lista, " ")
      for (i = 1; i <= n; i++) { topo[lista[i]] = 1; ordem[i] = lista[i] }
      n_topo = n
      n = split("trabalho_id task_id tipo_task area sinais estimado_min estimado_max estimado_media real duracao_observada desvio registrado_em", lista, " ")
      for (i = 1; i <= n; i++) campo_entrada[lista[i]] = 1
      n = split("tipo_task entradas desvio_medio fator_ativo", lista, " ")
      for (i = 1; i <= n; i++) campo_calibracao[lista[i]] = 1
      n = split("config client dominio persistencia api ui integracao_externa teste infra refatoracao", lista, " ")
      for (i = 1; i <= n; i++) tipo[lista[i]] = 1
      estado = "inicio"
    }
    { sub(/\r$/, "") }
    estado == "inicio" {
      if ($0 !~ /^---[[:space:]]*$/) erro("não começa por frontmatter")
      estado = "fm"; next
    }
    estado == "fm" && /^---[[:space:]]*$/ { fecha_item(); estado = "corpo"; next }
    estado == "fm" {
      if ($0 ~ /\t/) erro("frontmatter com tabulação")
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[a-z0-9_]+:/) {
        fecha_item()
        chave = $0; sub(/:.*/, "", chave)
        valor = $0; sub(/^[^:]*:/, "", valor)
        if (!(chave in topo)) erro("chave de topo fora do contrato: " chave)
        if (chave in visto) erro("chave de topo repetida: " chave)
        visto[chave] = 1; valor_topo[chave] = escalar(valor)
        secao = ""
        if (chave == "entradas" || chave == "calibracao") {
          if (escalar(valor) == "") secao = chave
          else if (escalar(valor) != "[]") erro(chave " fora do formato de lista")
        } else { cita_tasks(valor); cita_trabalho(valor) }
        next
      }
      if ($0 ~ /^ +- [a-z0-9_]+:/) {
        fecha_item(); item = 1
        recuo = match($0, /-/) - 1
        resto = $0; sub(/^ +- /, "", resto)
        chave = resto; sub(/:.*/, "", chave)
        valor = resto; sub(/^[^:]*:/, "", valor)
        campo(chave, valor); next
      }
      if ($0 ~ /^ +[a-z0-9_]+:/) {
        if (!item || match($0, /[^ ]/) - 1 <= recuo) erro("linha fora de item: " $0)
        chave = $0; sub(/^ +/, "", chave); sub(/:.*/, "", chave)
        valor = $0; sub(/^[^:]*:/, "", valor)
        campo(chave, valor); next
      }
      erro("linha não reconhecida no frontmatter: " $0)
    }
    estado == "corpo" {
      cita_tasks($0); cita_trabalho($0)
      if ($0 ~ /^[[:space:]]*```/) { cerca = !cerca; tabela = ""; next }
      if (cerca) next
      if ($0 ~ /^[[:space:]]*\|/) { linha_tabela(); next }
      tabela = ""; separador = 0
    }
    END {
      if (falhou) exit 1
      if (estado != "corpo") { print "frontmatter não fechado"; exit 1 }
      for (i = 1; i <= n_topo; i++)
        if (!(ordem[i] in visto)) { print "falta a chave " ordem[i]; exit 1 }
      if (valor_topo["expx_schema"] != "1") { print "expx_schema não é 1"; exit 1 }
      if (valor_topo["expx_tool"] != "sprintx") { print "expx_tool não é sprintx"; exit 1 }
      if (valor_topo["kind"] != "estimativa_historico") { print "kind não é estimativa_historico"; exit 1 }
      if (valor_topo["trabalho_id"] != "null") { print "trabalho_id do cabeçalho não é null"; exit 1 }
      if (valor_topo["unidade"] != "h") { print "unidade não é h"; exit 1 }
      if (valor_topo["atualizado_em"] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        print "atualizado_em fora de AAAA-MM-DD"; exit 1
      }
    }
  ' "$RAIZ/$caminho" 2>&1)" \
    || para "HISTORICO global inicial sem ownership integral: ${motivo:-leitura falhou}"
  return 0
}

confere_historico_corrente() {
  local caminho='docs/sprintx/estimativas/HISTORICO.md' diff linha valor
  sujo "$caminho" || return 0
  if ! git -C "$RAIZ" ls-files --error-unmatch -- "$caminho" >/dev/null 2>&1; then
    confere_historico_inicial
    return 0
  fi
  diff="$(git -C "$RAIZ" diff HEAD --no-color --no-ext-diff -U0 -- "$caminho" 2>/dev/null)" \
    || para 'não foi possível provar o diff do HISTORICO global'
  while IFS= read -r linha; do
    case "$linha" in
      ''|'diff '*|'index '*|'--- '*|'+++ '*|'@@ '*|'\ No newline'|+|-)
        continue ;;
      -atualizado_em:*|+atualizado_em:*) continue ;;
      -*) para 'HISTORICO global remove ou reescreve evidência existente' ;;
      '+ '*|'+	'*)
        case "$linha" in
          *trabalho_id:*)
            valor="${linha#*trabalho_id:}"
            valor="$(printf '%s' "$valor" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
            [ "$valor" = "$TRABALHO" ] || para "HISTORICO global contém entrada de outro trabalho: $valor"
            ;;
        esac
        ;;
      '+|'*)
        valor="$(printf '%s' "${linha#+|}" | awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1 }')"
        [ "$valor" = "$TRABALHO" ] || para "HISTORICO global contém linha de outro trabalho: $valor"
        ;;
      +*) para 'HISTORICO global contém acréscimo não atribuível ao trabalho corrente' ;;
    esac
  done <<EOF
$diff
EOF
}

# Os caminhos vêm do catálogo compartilhado (catalogo-de-metodo.sh), o mesmo
# que o E1 usa para separar método de produto. Aqui cada um só entra se
# existe, é arquivo regular e está dirty.
TMP_CATALOGO="$(mktemp "${TMPDIR:-/tmp}/mergex-catalogo.XXXXXX")" || para 'não foi possível criar catálogo temporário'
catalogo_metodo "$RAIZ" "$ORIGEM" "$TRABALHO" "$PASTA" "$CHECKPOINT" > "$TMP_CATALOGO" || para "$CATALOGO_ERRO"
[ "$ORIGEM" = sprintx ] && confere_historico_corrente
while IFS= read -r caminho; do
  [ -n "$caminho" ] || continue
  adiciona "$caminho"
done < "$TMP_CATALOGO"

LC_ALL=C sort -u -o "$TMP_LISTA" "$TMP_LISTA"

if [ "$MODO" = listar ]; then
  cat "$TMP_LISTA"
  exit 0
fi

if [ "$MODO" = verificar ]; then
  if [ -s "$TMP_LISTA" ]; then
    printf 'persistir-metodo: checkpoint %s pendente; artefatos de método dirty:\n' "$CHECKPOINT" >&2
    sed 's/^/  - /' "$TMP_LISTA" >&2
    exit 1
  fi
  printf 'ok=true\n'
  exit 0
fi

if [ ! -s "$TMP_LISTA" ]; then
  printf 'noop=true\n'
  exit 0
fi

# O stage nasce vazio sob a trava. Cada path vem do catálogo fechado acima;
# nenhum diretório, glob ou `git add -A` participa desta operação.
while IFS= read -r caminho; do
  [ -n "$caminho" ] || continue
  git add -- "$caminho" || para "falha ao preparar $caminho; stage preservado"
done < "$TMP_LISTA"

STAGED="$(git diff --cached --name-only 2>/dev/null | LC_ALL=C sort -u)"
ESPERADO="$(cat "$TMP_LISTA")"
[ -n "$STAGED" ] || para 'nenhuma mudança elegível entrou no stage'
[ "$STAGED" = "$ESPERADO" ] || para 'o staged diff diverge do catálogo exato; stage preservado'

# Reutiliza literalmente o gate de segurança dos hooks sobre o staged diff.
# Falha de jq ou do hook também é fechada: método não ganha atalho de segredo.
command -v jq >/dev/null 2>&1 || para 'jq indisponível para o gate de segredo'
ENTRADA_SEGREDO="$(jq -cn --arg w "$RAIZ" \
  '{tool_name:"Bash",cwd:$w,tool_input:{command:"git commit"}}' 2>/dev/null)"
[ -n "$ENTRADA_SEGREDO" ] || para 'não foi possível preparar o gate de segredo'
printf '%s' "$ENTRADA_SEGREDO" | bash "$SEGREDO_SH" \
  || para 'gate de segredo reprovou; nenhum commit foi criado e o stage foi preservado'

TMP_MSG="$(mktemp "${TMPDIR:-/tmp}/mergex-metodo-msg.XXXXXX")" || para 'não foi possível criar a mensagem do commit'
{
  printf 'chore(mergex): persiste metodo %s\n\n' "$CHECKPOINT"
  printf 'Trabalho: %s\n' "$TRABALHO"
  printf 'Metodo: %s\n' "$CHECKPOINT"
} > "$TMP_MSG" || para 'não foi possível escrever a mensagem do commit'

bash "$CONTRATO_SH" --validar-metodo --trabalho "$TRABALHO" \
  --checkpoint "$CHECKPOINT" --arquivo "$TMP_MSG" >/dev/null 2>&1 \
  || para 'mensagem de método não satisfaz o contrato'

git commit -F "$TMP_MSG" >/dev/null \
  || para 'git commit falhou; nenhum estado foi limpo automaticamente'

bash "$CONTRATO_SH" --validar-metodo --trabalho "$TRABALHO" \
  --checkpoint "$CHECKPOINT" --commit HEAD >/dev/null 2>&1 \
  || para 'commit criado não satisfaz o contrato de método'

SHA="$(git rev-parse HEAD 2>/dev/null)"
printf '%s\n' "$SHA" | grep -Eq '^[0-9a-f]{40}$' || para 'commit criado sem SHA completo legível'
printf 'commit=%s\n' "$SHA"
