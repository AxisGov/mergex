#!/usr/bin/env bash
# portao-regras — a regra única da barreira de push (DM-184). Biblioteca: é
# carregada com `.` e não executa nada sozinha.
#
# Contrato: docs/superpowers/specs/2026-10-07-reconciliacao-base-pos-e8-design.md,
# seção 13, itens 5 a 8. As três camadas da barreira (o pre-push do Git, o hook
# do Claude `pr-so-com-portao` e o CI) decidem por estas funções: a mesma
# validade (validade-do-portao.sh --rev) e o mesmo modo de `portao: null`.
# Decidem só pelo que o Git entrega (refs, SHAs, árvores); nada aqui lê texto de
# comando de shell. Nenhuma opção de força.
#
# Quem carrega fixa antes o ambiente Git (arvore_ambiente_git, de
# reconciliacao-arvore.sh, que esta biblioteca também carrega).
#
# Funções (rc 0 ou 1; em falha, PR_ERRO descreve o motivo):
#
#   pr_modo_null <raiz>
#       Imprime bloqueio|aviso|desligado: o modo de `pr-so-com-portao` em
#       <raiz>/.expx/hooks.json (`.hooks["pr-so-com-portao"].modo`; a forma
#       antiga `.modos["pr-so-com-portao"]` também, como em expx_modo). Sem o
#       arquivo, ou sem a chave (ou com ela `null`): aviso, o padrão do
#       repositório. Falha fechada: arquivo presente que não se lê, jq ausente,
#       JSON inválido ou vazio, ou modo fora de bloqueio|aviso|desligado (texto
#       desconhecido, número, booleano, objeto) imprime bloqueio e rc 1.
#
#   pr_entrega_da_ref <raiz> <ref_remota> <sha_local> <sha_remoto>
#       Imprime o caminho do docs/entregas/<id>/ENTREGA.md (arquivo regular)
#       que declara `branch: <b>` para a ref `refs/heads/<b>`, lido das árvores
#       do SHA enviado, do SHA remoto anterior (quando o objeto existe aqui) e
#       da ponta local de refs/heads/<b>. Nada (rc 0) quando a ref não é
#       aplicável: outro namespace, nenhuma dessas árvores declara a branch.
#       rc 1: SHA enviado sem objeto, árvore ou blob que não se lê (com
#       PR_FALTA=1 quando é objeto Git ausente), ou mais de um ENTREGA.md
#       diferente declarando a branch (ambíguo; inclusive reúso de nome de
#       branch por uma entrega antiga). `branch:` é lido como catalogo_fm lê,
#       mas com um ls-tree e um cat-file --batch por árvore: o número de
#       processos não cresce com as entregas da árvore.
#
#   pr_decide_ref <raiz> <ref_local> <sha_local> <ref_remota> <sha_remoto>
#       Imprime
#         decisao=<passa|avisa|barra>
#         motivo=<texto>
#         entrega=<caminho|->
#       e deixa em PR_DIAG o diagnóstico legível (vazio quando passa sem nada
#       a dizer). rc 0 para passa/avisa, rc 1 para barra (PR_ERRO = PR_DIAG).
#       - exclusão (SHA local nulo): passa, motivo exclusao;
#       - tag (refs/tags/*): passa, motivo tag;
#       - ref não aplicável (pr_entrega_da_ref vazio): passa, ref_nao_aplicavel;
#       - ref aplicável: validade-do-portao.sh --verificar --entrega <E>
#         --rev <SHA local> (o SHA enviado, nunca o HEAD do checkout):
#           ok=true: passa, portao_valido;
#           portao: null (o ENTREGA.md do SHA enviado é arquivo regular,
#             kind: entrega, trabalho_id do caminho, expx_tool sprintx|runx e
#             `portao: null`): segue pr_modo_null — bloqueio barra, aviso
#             avisa, desligado passa (motivo portao_null);
#           todo o resto barra, em qualquer modo, com o motivo da validade:
#             pronto vencido, ausente, inconsistente ou ilegível,
#             historia_incompleta, erro_ambiente (inclusive o validador
#             ausente ou saída inesperada) e entrega_indeterminada; objeto
#             ausente já na leitura das entregas da ref é historia_incompleta.
#       Os diagnósticos de historia_incompleta e de erro_ambiente são
#       distintos: o primeiro manda completar a história, o segundo descreve a
#       falha do ambiente.
#
# Custo: uma validade por ref aplicável; nenhuma varredura de branches; um
# número constante de processos Git por árvore lida (até três por ref).
#
# Risco residual: um SHA remoto anterior que este repositório não conhece é
# pulado; se nem o SHA enviado nem a ponta local declaram a branch, a ref não
# é aplicável. Só se alcança com push forçado (sem força o Git recusa antes
# do pre-push), que o hook git-perigoso bloqueia; o CI é a barreira contra o
# contorno.
#
# Bash 3.2 (macOS): sem arrays associativos, mapfile ou recursos de Bash 4+.

PR_AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_VALIDADE="$PR_AQUI/validade-do-portao.sh"
PR_ERRO=""
PR_DIAG=""
PR_MODO=""
PR_ENTREGA=""
PR_FALTA=0

if [ ! -r "$PR_AQUI/catalogo-de-metodo.sh" ] || [ ! -r "$PR_AQUI/reconciliacao-arvore.sh" ]; then
  PR_ERRO="dependência indisponível ao lado de $PR_AQUI/portao-regras.sh"
  return 1 2>/dev/null || exit 1
fi
# shellcheck source=catalogo-de-metodo.sh
. "$PR_AQUI/catalogo-de-metodo.sh"
# shellcheck source=reconciliacao-arvore.sh
. "$PR_AQUI/reconciliacao-arvore.sh"

_pr_g() { git -c core.quotepath=false "$@"; }
_pr_nulo() { printf '%s' "$1" | grep -Eq '^0+$'; }

# _pr_modo <raiz> — PR_MODO (sem subshell, para ler PR_ERRO)
_pr_modo() {
  local arq="$1/.expx/hooks.json" v
  PR_ERRO=""; PR_MODO=aviso
  if [ ! -e "$arq" ] && [ ! -L "$arq" ]; then return 0; fi
  if [ ! -f "$arq" ] || [ ! -r "$arq" ]; then
    PR_MODO=bloqueio; PR_ERRO="$arq não se lê: modo de pr-so-com-portao tratado como bloqueio"; return 1
  fi
  command -v jq >/dev/null 2>&1 \
    || { PR_MODO=bloqueio; PR_ERRO="jq ausente: modo de pr-so-com-portao tratado como bloqueio"; return 1; }
  v="$(jq -c 'if (.hooks["pr-so-com-portao"].modo) != null then .hooks["pr-so-com-portao"].modo else .modos["pr-so-com-portao"] end' "$arq" 2>/dev/null)" \
    || { PR_MODO=bloqueio; PR_ERRO="$arq ilegível: modo de pr-so-com-portao tratado como bloqueio"; return 1; }
  case "$v" in
    '"bloqueio"') PR_MODO=bloqueio ;;
    '"aviso"') PR_MODO=aviso ;;
    '"desligado"') PR_MODO=desligado ;;
    null) PR_MODO=aviso ;;
    *) PR_MODO=bloqueio; PR_ERRO="modo de pr-so-com-portao inválido em $arq (${v:-vazio}): tratado como bloqueio"; return 1 ;;
  esac
  return 0
}

pr_modo_null() {
  local rc
  _pr_modo "$1"; rc=$?
  printf '%s\n' "$PR_MODO"
  return "$rc"
}

# _pr_falta_objeto <raiz> <rev> — rc 0 se falta algum objeto (árvore ou blob)
# da árvore de <rev>. Só nos caminhos de falha.
_pr_falta_objeto() {
  local o
  o="$(_pr_g -C "$1" rev-list --objects --no-walk --missing=print "$2" 2>/dev/null)" || return 0
  printf '%s\n' "$o" | grep -q '^?'
}

# Leitura de `branch:` igual à de catalogo_fm, num fluxo `git cat-file --batch`
# inteiro: cada blob começa por `<sha> blob <tamanho>` (ou `<sha> missing`),
# seguido de exatamente <tamanho> bytes e de uma quebra de linha. Para cada
# blob, o frontmatter só existe se a primeira linha é `---` (espaços e CR no
# fim aceitos); vale a primeira linha que começa por `branch:` antes do `---`
# seguinte (sem CR, sem um par de aspas nas pontas, sem espaços no fim).
# Imprime o número de ordem de cada blob cujo valor é a branch, FALTA para um
# objeto ausente e ERRO para um cabeçalho que não se entende.
_PR_AWK_BRANCH='
  est == 0 {
    if ($0 ~ / missing$/) { print "FALTA"; i++; next }
    if (split($0, h, " ") != 3 || h[2] != "blob") { print "ERRO"; exit }
    i++; resta = h[3] + 0; nl = 0; para = 0
    est = (resta == 0) ? 2 : 1
    next
  }
  est == 2 { est = 0; next }
  {
    resta -= length($0) + 1; nl++
    if (!para) {
      if (nl == 1) { if ($0 !~ /^---[[:space:]]*\r?$/) para = 1 }
      else if ($0 ~ /^---[[:space:]]*\r?$/) para = 1
      else {
        linha = $0; gsub(/\r/, "", linha)
        if (index(linha, "branch:") == 1) {
          sub(/^[^:]*:[[:space:]]*/, "", linha)
          gsub(/^["\047]|["\047]$/, "", linha)
          gsub(/[[:space:]]+$/, "", linha)
          if (linha == b) print i
          para = 1
        }
      }
    }
    if (resta == 0) est = 2
    else if (resta < 0) est = 0
  }
'

# _pr_entregas_em <raiz> <rev> <branch> <arquivo de saída> — acrescenta ao
# arquivo os ENTREGA.md da árvore de <rev> que declaram `branch: <branch>`.
# Custo constante em processos: um ls-tree e um cat-file --batch por árvore,
# qualquer que seja o número de entregas. Objeto ausente: PR_FALTA=1.
_pr_entregas_em() {
  local raiz="$1" rev="$2" b="$3" saida="$4"
  _pr_g -C "$raiz" ls-tree -r -z "$rev" -- docs/entregas > "$saida.lista" 2>/dev/null \
    || { _pr_falta_objeto "$raiz" "$rev" && PR_FALTA=1; PR_ERRO="árvore de $rev não se lê"; return 1; }
  # candidatos: `<sha> <caminho>` dos docs/entregas/<id>/ENTREGA.md regulares
  tr '\0' '\n' < "$saida.lista" | LC_ALL=C awk -F'\t' '
    NF == 2 && $2 ~ "^docs/entregas/[^/[:cntrl:]]+/ENTREGA[.]md$" && $1 ~ "^100(644|755) blob [0-9a-f]+$" {
      split($1, m, " "); print m[3] " " $2 }' > "$saida.cand" \
    || { PR_ERRO="árvore de $rev não se lê"; return 1; }
  [ -s "$saida.cand" ] || return 0
  cut -d' ' -f1 "$saida.cand" | _pr_g -C "$raiz" cat-file --batch > "$saida.batch" 2>/dev/null \
    || { PR_ERRO="entregas de $rev não se leem"; return 1; }
  LC_ALL=C awk -v b="$b" "$_PR_AWK_BRANCH" "$saida.batch" > "$saida.idx" \
    || { PR_ERRO="entregas de $rev não se leem"; return 1; }
  if grep -qx FALTA "$saida.idx"; then PR_FALTA=1; PR_ERRO="ENTREGA.md de $rev com objeto Git ausente"; return 1; fi
  grep -qx ERRO "$saida.idx" && { PR_ERRO="entregas de $rev não se leem"; return 1; }
  awk 'NR == FNR { q[$1] = 1; next } (FNR in q) { sub(/^[^ ]* /, ""); print }' "$saida.idx" "$saida.cand" >> "$saida"
  return 0
}

# _pr_entrega <raiz> <ref_remota> <sha_local> <sha_remoto> — PR_ENTREGA
_pr_entrega() {
  local raiz="$1" rr="$2" sl="$3" sr="$4" b tmp rev ponta n rc=0 vistos=""
  PR_ERRO=""; PR_ENTREGA=""; PR_FALTA=0
  case "$rr" in refs/heads/?*) b="${rr#refs/heads/}" ;; *) return 0 ;; esac
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/mergex-portao-regras.XXXXXX")" || { PR_ERRO="não foi possível criar diretório temporário"; return 1; }
  : > "$tmp/achados"
  ponta="$(_pr_g -C "$raiz" rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null)" || ponta=""
  for rev in "$sl" "$sr" "$ponta"; do
    [ -n "$rev" ] && ! _pr_nulo "$rev" || continue
    case " $vistos " in *" $rev "*) continue ;; esac
    vistos="$vistos $rev"
    if ! _pr_g -C "$raiz" cat-file -e "$rev^{commit}" 2>/dev/null; then
      # o remoto pode ter avançado além do que este repositório conhece
      [ "$rev" = "$sr" ] && [ "$rev" != "$sl" ] && continue
      PR_ERRO="o commit $rev não está no repositório"; rc=1; break
    fi
    : > "$tmp/um"
    _pr_entregas_em "$raiz" "$rev" "$b" "$tmp/um" || { rc=1; break; }
    n="$(wc -l < "$tmp/um" | tr -d ' ')"
    [ "$n" -le 1 ] || { PR_ERRO="mais de um ENTREGA.md declara branch: $b em $rev"; rc=1; break; }
    cat "$tmp/um" >> "$tmp/achados"
  done
  if [ "$rc" = 0 ]; then
    n="$(sort -u "$tmp/achados" | wc -l | tr -d ' ')"
    if [ "$n" -gt 1 ]; then
      PR_ERRO="ENTREGA.md diferentes declaram branch: $b ($(sort -u "$tmp/achados" | tr '\n' ' '))"; rc=1
    else
      PR_ENTREGA="$(sed -n 1p "$tmp/achados")"
    fi
  fi
  rm -rf "$tmp"
  return "$rc"
}

pr_entrega_da_ref() {
  _pr_entrega "$1" "$2" "$3" "$4" || return 1
  [ -z "$PR_ENTREGA" ] || printf '%s\n' "$PR_ENTREGA"
  return 0
}

# _pr_portao_null <raiz> <sha> <entrega> — o ENTREGA.md do SHA é legível,
# consistente e declara `portao: null` (o E2 ainda não autorizou)
_pr_portao_null() {
  local raiz="$1" sha="$2" e="$3" id tmp modo r=1
  id="${e#docs/entregas/}"; id="${id%/ENTREGA.md}"
  modo="$(_pr_g -C "$raiz" ls-tree -z "$sha" -- "$e" 2>/dev/null | tr '\0' '\n' | sed -n '1s/ .*//p')"
  case "$modo" in 100644|100755) ;; *) return 1 ;; esac
  tmp="$(mktemp "${TMPDIR:-/tmp}/mergex-portao-null.XXXXXX")" || return 1
  if _pr_g -C "$raiz" cat-file blob "$sha:$e" > "$tmp" 2>/dev/null \
    && [ "$(catalogo_fm "$tmp" kind)" = entrega ] \
    && [ "$(catalogo_fm "$tmp" trabalho_id)" = "$id" ] \
    && case "$(catalogo_fm "$tmp" expx_tool)" in sprintx|runx) true ;; *) false ;; esac \
    && [ "$(catalogo_fm "$tmp" portao)" = null ]; then r=0; fi
  rm -f "$tmp"
  return "$r"
}

# _pr_sai <decisao> <motivo> <entrega> <diagnóstico>
_pr_sai() {
  PR_DIAG="$4"
  printf 'decisao=%s\nmotivo=%s\nentrega=%s\n' "$1" "$2" "${3:--}"
  if [ "$1" = barra ]; then PR_ERRO="$4"; return 1; fi
  return 0
}

# _pr_diag_invalido <motivo> <primeiro_commit> — o diagnóstico de cada motivo
# que barra
_pr_diag_invalido() {
  case "$1" in
    historia_incompleta)
      printf '%s' "história incompleta (historia_incompleta): clone raso ou objeto Git ausente; complete a história com 'git fetch --unshallow' ou busque os objetos que faltam, e repita o push" ;;
    erro_ambiente)
      printf '%s' "erro de ambiente (erro_ambiente): a validade do portão não pôde ser avaliada; corrija o ambiente e repita o push" ;;
    portao_sha_ausente)
      printf '%s' "portão pronto sem portao_sha válido (portao_sha_ausente): rode o E2 (/mergex-check) de novo para regravar o portão" ;;
    portao_nao_pronto)
      printf '%s' "ENTREGA.md ausente, ilegível, inconsistente ou com portão não pronto no SHA enviado (portao_nao_pronto): rode o E2 (/mergex-check) de novo" ;;
    entrega_indeterminada)
      printf '%s' "não foi possível determinar o ENTREGA.md da ref (entrega_indeterminada)" ;;
    *)
      printf 'portão inválido para o SHA enviado (%s' "$1"
      [ "${2:--}" = - ] || printf ', primeiro commit %s' "$2"
      printf '%s' "): rode o E2 (/mergex-check) de novo" ;;
  esac
}

pr_decide_ref() {
  local raiz="$1" rl="$2" sl="$3" rr="$4" sr="$5" ent out rc okv mot pri avisos nulo d
  PR_ERRO=""; PR_DIAG=""
  : "$rl" # a ref local não decide: decidem o destino e o SHA enviado
  _pr_nulo "$sl" && { _pr_sai passa exclusao - ""; return; }
  case "$rr" in refs/tags/*) _pr_sai passa tag - ""; return ;; esac
  if ! _pr_entrega "$raiz" "$rr" "$sl" "$sr"; then
    # objeto ausente nas entregas da ref: história incompleta, não ambiente
    [ "$PR_FALTA" != 1 ] || { _pr_sai barra historia_incompleta - "$(_pr_diag_invalido historia_incompleta) [$PR_ERRO]"; return; } # guarda:VALOBJ
    _pr_sai barra entrega_indeterminada - "$(_pr_diag_invalido entrega_indeterminada): $PR_ERRO"; return
  fi
  ent="$PR_ENTREGA"
  [ -n "$ent" ] || { _pr_sai passa ref_nao_aplicavel - ""; return; }

  [ -r "$PR_VALIDADE" ] \
    || { _pr_sai barra erro_ambiente "$ent" "$(_pr_diag_invalido erro_ambiente): validador ausente: $PR_VALIDADE"; return; }
  set -- --verificar --entrega "$ent"
  set -- "$@" --rev "$sl" # guarda:PPSHA
  out="$(cd "$raiz" && bash "$PR_VALIDADE" "$@" 2>/dev/null)"; rc=$?
  okv="$(printf '%s\n' "$out" | sed -n 1p)"
  mot="$(printf '%s\n' "$out" | sed -n 's/^motivo=//p' | sed -n 1p)"
  pri="$(printf '%s\n' "$out" | sed -n 's/^primeiro_commit=//p' | sed -n 1p)"
  avisos="$(printf '%s\n' "$out" | sed -n 's/^aviso=//p' | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
  if [ "$rc" = 0 ] && [ "$okv" = ok=true ]; then
    _pr_sai passa portao_valido "$ent" ""; return
  fi
  if [ "$rc" != 1 ] || [ "$okv" != ok=false ] || [ -z "$mot" ]; then
    _pr_sai barra erro_ambiente "$ent" "$(_pr_diag_invalido erro_ambiente): a validade devolveu uma saída inesperada (rc=$rc)"; return
  fi
  d="$(_pr_diag_invalido "$mot" "$pri")"
  [ -z "$avisos" ] || d="$d [$avisos]"

  nulo=0
  [ "$mot" = portao_nao_pronto ] && _pr_portao_null "$raiz" "$sl" "$ent" && nulo=1
  # o modo nunca afrouxa pronto vencido, ausente, inconsistente ou ilegível,
  # nem historia_incompleta ou erro_ambiente
  [ "$nulo" = 1 ] || { _pr_sai barra "$mot" "$ent" "$d"; return; } # guarda:PPMODO

  _pr_modo "$raiz"
  d="portão ainda não autorizado pelo E2 (portao: null em $ent); modo $PR_MODO de pr-so-com-portao"
  [ -z "$PR_ERRO" ] || d="$d ($PR_ERRO)"
  case "$PR_MODO" in
    desligado) _pr_sai passa portao_null "$ent" "" ;;
    aviso) _pr_sai avisa portao_null "$ent" "$d: o push segue; rode o E2 (/mergex-check) antes do PR" ;;
    *) _pr_sai barra portao_null "$ent" "$d: o push fica barrado; rode o E2 (/mergex-check)" ;;
  esac
}
