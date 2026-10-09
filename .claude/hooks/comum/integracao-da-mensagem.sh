#!/usr/bin/env bash
# integracao-da-mensagem — biblioteca (carregada com `.`) dos hooks de commit.
#
# Reconhece a classe "integração de base" pela MENSAGEM do commit, nunca pelo
# estado do Git: só vale a mensagem que declara `Integra-base:` como trailer
# isolado e limpo. O que a leitura não isola (aspas soltas, lixo depois dos 40
# hex, trailers que o Git não acha) é classe "nenhuma": regras de sempre.
# Bloquear só com prova.
#
# Requer RAIZ (raiz do repositório) definida pelo chamador.

# integracao_le_m <comando> — a(s) mensagem(ns) de `-m "..."`, cada uma cortada
# na aspa de fechamento; `-m "a" -m "b"` vira dois parágrafos. Vazio se não há.
integracao_le_m() {
  local rest out="" seg
  case "$1" in *' -m "'*) ;; *) return 0 ;; esac
  rest="${1#*' -m "'}"
  while :; do
    seg="${rest%%\"*}"
    out="${out:+$out$'\n\n'}$seg"
    [ "$seg" = "$rest" ] && break
    rest="${rest#*\"}"
    case "$rest" in
      ' -m "'*) rest="${rest#' -m "'}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$out"
}

# integracao_mensagem_do_comando <comando> — `-F <arquivo>` (relativo à RAIZ) ou
# `-m`; vazio se o hook não consegue ler a mensagem.
integracao_mensagem_do_comando() {
  local arq
  arq="$(printf '%s' "$1" | sed -n 's/.*[[:space:]]-F[[:space:]]*\([^[:space:]]*\).*/\1/p; s/.*--file=\([^[:space:]]*\).*/\1/p' | head -1)"
  if [ -n "$arq" ]; then
    arq="$(printf '%s' "$arq" | sed "s/^['\"]//; s/['\"]$//")"
    case "$arq" in /*) : ;; *) arq="$RAIZ/$arq" ;; esac
    [ -r "$arq" ] && cat "$arq" 2>/dev/null
    return 0
  fi
  integracao_le_m "$1"
}

# integracao_da_mensagem <mensagem-lida> <trabalho-da-branch> <contrato>
# Variável opcional INT_SEM_CONTRATO: `invalida` (padrão) ou `nenhuma` — o que
# fazer quando o contrato-de-commit.sh não está instalado.
# Define INT_CLASSE (nenhuma | valida | invalida) e INT_SAIDA.
integracao_da_mensagem() {
  INT_CLASSE=nenhuma; INT_SAIDA=""
  local txt tr integra trab tmp mh rc
  # Invólucro do heredoc `-m "$(cat <<'EOF' ... EOF)"`.
  txt="$(printf '%s\n' "$1" | awk 'NR==1 && /^\$\(cat[[:space:]]*<</ { h=1; next } h && /^[A-Z_]+[[:space:]]*$/ { exit } { print }')"
  tr="$(printf '%s\n' "$txt" | git interpret-trailers --parse 2>/dev/null)"
  printf '%s\n' "$tr" | grep -Eq '^Integra-base:' || return 0
  integra="$(printf '%s\n' "$tr" | sed -n 's/^Integra-base:[[:space:]]*//p' | head -1)"
  # Lixo depois dos 40 hex: a leitura não isolou o trailer.
  printf '%s' "$integra" | grep -Eq '^[0-9a-f]{40}[^0-9a-f]' && return 0
  trab="$2"
  [ -n "$trab" ] || trab="$(printf '%s\n' "$tr" | sed -n 's/^Trabalho:[[:space:]]*//p' | head -1)"
  if [ ! -r "$3" ]; then
    if [ "${INT_SEM_CONTRATO:-invalida}" = invalida ]; then
      INT_CLASSE=invalida; INT_SAIDA="instalação MergeX incompleta: $3"
    fi
    return 0
  fi
  tmp="$(mktemp)" || { INT_CLASSE=invalida; INT_SAIDA="sem arquivo temporário"; return 0; }
  printf '%s\n' "$txt" > "$tmp"
  INT_SAIDA="$(bash "$3" --validar-integracao --trabalho "${trab:-?}" --arquivo "$tmp" 2>&1)"; rc=$?
  rm -f "$tmp"
  if [ "$rc" != 0 ]; then INT_CLASSE=invalida; return 0; fi
  mh="$(git -C "$RAIZ" rev-parse -q --verify MERGE_HEAD 2>/dev/null)"
  if [ "$integra" != "$mh" ]; then
    INT_CLASSE=invalida
    INT_SAIDA="Integra-base diverge de MERGE_HEAD: mensagem=$integra MERGE_HEAD=$mh"
    return 0
  fi
  INT_CLASSE=valida
}
