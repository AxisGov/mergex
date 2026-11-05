#!/usr/bin/env bash
# shellcheck shell=bash
#
# Parte da bancada R1: scripts/ci/test-r1-reconciliacao-base.sh a carrega com
# `.`, na ordem de definição, e roda os grupos. Esta parte só define funções e
# variáveis, e não roda sozinha. Grupos: sha256 e oid_limites.
#
# O tamanho do OID vem do formato do repositório (DM-315): 40 hex no SHA-1, 64
# no SHA-256. O cenário do R1 roda inteiro num repositório SHA-256, e os
# limites ficam provados nos dois sentidos.

[ "${BASH_SOURCE[0]}" != "$0" ] || { echo "${0##*/}: parte da bancada R1; rode scripts/ci/test-r1-reconciliacao-base.sh" >&2; exit 64; }

grupo_sha256() {
  local t d
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t"); d="$t/repo"
  FX_OBJECT_FORMAT=sha256 fx_cenario "$d" || { falha "cenário SHA-256 não montou"; return; }
  cd "$d" || return
  [ "$(git rev-parse --show-object-format)" = sha256 ] && [ "${#FX_M}" = 64 ] \
    && ok "controle: repositório SHA-256, M com 64 hex" || falha "controle: formato $(git rev-parse --show-object-format), M=$FX_M"
  fx_fluxo_completo "$d" || { falha "fluxo SHA-256: ${FX_ERRO:-}"; cd "$REPO"; return; }
  ok "fluxo completo depois da reconciliação, em SHA-256"
  fl_passos sha256
  fx_remoto_bare "$d" || { falha "remoto bare não montou"; cd "$REPO"; return; }
  fl_pushes sha256 "$d" "$t"
  cd "$REPO" || return
}

# _ol_mensagem <arquivo> <integra> — mensagem de integração com esse Integra-base
_ol_mensagem() {
  printf 'merge: integra a main\n\nTrabalho: ft-rec\nIntegra-base: %s\n' "$2" > "$1"
}

# _ol_artefato_40 <dir> — o 001 do disco reescrito com todos os OIDs cortados em
# 40 hex (coerente e assinado: só o formato do repositório o recusa) e o
# ENTREGA.md sincronizado com ele
_ol_artefato_40() {
  FX_P1_SHA="$(printf '%.40s' "$FX_P1")" FX_B1_SHA="$(printf '%.40s' "$FX_B1")" \
  FX_FORJA_AWK='{ $3 = substr($3, 1, 40); $4 = substr($4, 1, 40); print }' \
  FX_M_SHA="$(printf '%.40s' "$FX_M")" \
    fx_emite_reconciliacao "$1" 1 "$(printf '%.40s' "$FX_B0")" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" \
    && fx_entrega_sincroniza "$1"
}

grupo_oid_limites() {
  local t d s1 r v a out m
  . "$REPO/scripts/ci/lib/fixture-reconciliacao.sh" || { falha "fixture ausente"; return; }
  t="$(mktemp -d)"; TMPS+=("$t")
  r=(bash "$RB" --registrar --entrega docs/entregas/ft-rec/ENTREGA.md --origem sprintx --trabalho ft-rec)

  # ---- base_validada_sha no tamanho do outro formato: rc 5 nos dois --------
  for formato in sha1 sha256; do
    d="$t/base-$formato"
    FX_OBJECT_FORMAT="$formato" FX_VARIANTE=entrega_base_outro_formato fx_cenario "$d" \
      || { falha "$formato: entrega_base_outro_formato não montou"; continue; }
    cd "$d" || return
    case "$formato" in sha1) m="não é SHA de 40 hex" ;; sha256) m="não é SHA de 64 hex" ;; esac
    reprova "$formato: base_validada_sha no tamanho do outro formato, rc 5" 5 "$m" -- "$FX_NOVO1" "$FX_NOVO2"
    cd "$REPO" || return
  done

  # ---- --merge: curto e completo em SHA-256 --------------------------------
  d="$t/merge-256"; FX_OBJECT_FORMAT=sha256 fx_cenario "$d" || { falha "SHA-256 não montou"; return; }
  cd "$d" || return
  out="$("${r[@]}" --merge "$FX_M" -- "$FX_NOVO1" "$FX_NOVO2" 2>&1)" \
    && printf '%s\n' "$out" | grep -Fxq "m=$FX_M" \
    && ok "sha256: --merge com o OID completo de 64 registra" || falha "sha256: --merge de 64 — $out"
  desfaz
  out="$("${r[@]}" --merge "$(printf '%.12s' "$FX_M")" -- "$FX_NOVO1" "$FX_NOVO2" 2>&1)" \
    && printf '%s\n' "$out" | grep -Fxq "m=$FX_M" \
    && ok "sha256: --merge abreviado resolve para os 64 hex" || falha "sha256: --merge curto — $out"
  desfaz

  # ---- Integra-base: o tamanho do formato ----------------------------------
  _ol_mensagem "$t/i64" "$FX_B1"; _ol_mensagem "$t/i40" "$(printf '%.40s' "$FX_B1")"
  rc_igual "sha256: Integra-base de 64 é integração" 0 bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo "$t/i64"
  rc_motivo "sha256: Integra-base de 40 (abreviação) reprova" 2 "de 64 hex" \
    bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo "$t/i40"
  cd "$REPO" || return
  rc_motivo "fora de um repositório, a integração é uso inválido" 64 "formato de objetos Git" \
    env GIT_CEILING_DIRECTORIES="$t" bash -c 'cd "$1" && bash "$2" --validar-integracao --trabalho ft-rec --arquivo "$1/i64"' _ "$t" "$CONTRATO"

  # ---- artefato: largura uniforme sem repositório; a do formato com ele -----
  d="$t/merge-256"; cd "$d" || return
  _ol_artefato_40 "$d" || { falha "artefato de 40 não foi emitido"; cd "$REPO"; return; }
  a=docs/entregas/ft-rec/RECONCILIACAO-BASE-001.md
  RB_ERRO=""; rb_validar "$a" ft-rec 1 && ok "artefato todo em 40 hex vale sem o formato (uniforme)" || falha "artefato de 40 sem formato: $RB_ERRO"
  RB_ERRO=""; rb_validar "$a" ft-rec 1 40 && ok "artefato todo em 40 hex vale com o formato 40" || falha "artefato de 40 com 40: $RB_ERRO"
  RB_ERRO=""
  if rb_validar "$a" ft-rec 1 64; then falha "artefato de 40 passou com o formato 64"
  else case "$RB_ERRO" in *"não é SHA de 64 hex"*) ok "artefato de 40 reprova com o formato 64" ;; *) falha "artefato de 40 com 64: $RB_ERRO" ;; esac; fi
  RB_ERRO=""; rb_validar "$a" ft-rec 1 32 && falha "tamanho 32 aceito" \
    || { case "$RB_ERRO" in *uso*) ok "rb_validar recusa tamanho fora de 40|64" ;; *) falha "tamanho 32: $RB_ERRO" ;; esac; }
  v=(bash "$V9" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec)
  out="$("${v[@]}" 2>/dev/null)"; s1=$?
  [ "$s1" = 3 ] && printf '%s\n' "$out" | grep -Fxq resultado=v9_sem_prova && printf '%s\n' "$out" | grep -Fq "não é SHA de 64 hex" \
    && ok "sha256: a V9 não toma como base o b1_sha de 40 do artefato" || falha "V9 com artefato de 40: rc=$s1 $(printf '%s' "$out" | tr '\n\t' '|>')"
  out="$(bash "$RB" --verificar --entrega "$FX_ENTREGA" --origem sprintx --trabalho ft-rec 2>/dev/null)"; s1=$?
  [ "$s1" = 5 ] && printf '%s\n' "$out" | grep -Fxq ok=false && printf '%s\n' "$out" | grep -Fq "contrato	RECONCILIACAO-BASE-001.md: b0_sha não é SHA de 64 hex" \
    && ok "sha256: --verificar recusa o artefato de 40 (contrato)" || falha "--verificar com artefato de 40: rc=$s1 $(printf '%s' "$out" | tr '\n\t' '|>')"
  desfaz
  cd "$REPO" || return

  # misto: um blob de 40 num artefato de 64 não é emitido
  d="$t/merge-256"; cd "$d" || return
  if FX_FORJA_AWK='NR == 1 { $3 = substr($3, 1, 40) } { print }' fx_emite_reconciliacao "$d" 1 "$FX_B0" "$FX_M" "$FX_NOVO1" "$FX_NOVO2" 2>"$t/misto.err"; then
    falha "artefato misto (um blob de 40 entre OIDs de 64) foi emitido"
  else grep -Fq "não é SHA de 64 hex" "$t/misto.err" && ok "artefato misto não é emitido" || falha "misto: $(cat "$t/misto.err")"; fi
  desfaz
  cd "$REPO" || return

  # ---- o cenário SHA-1 por último: fx_cenario sobrescreve os FX_* ----------
  d="$t/merge-1"; fx_cenario "$d" || { falha "SHA-1 não montou"; return; }
  cd "$d" || return
  rc_motivo "sha1: --merge de 64 dígitos é uso inválido" 64 "de 7 a 40 dígitos" \
    "${r[@]}" --merge "${FX_M}000000000000000000000000" -- "$FX_NOVO1" "$FX_NOVO2"
  rc_motivo "sha1: --merge de 41 dígitos é uso inválido" 64 "de 7 a 40 dígitos" \
    "${r[@]}" --merge "${FX_M}0" -- "$FX_NOVO1" "$FX_NOVO2"

  _ol_mensagem "$t/s64" "${FX_B1}000000000000000000000000"
  rc_motivo "sha1: Integra-base de 64 reprova" 2 "de 40 hex" \
    bash "$CONTRATO" --validar-integracao --trabalho ft-rec --arquivo "$t/s64"
  cd "$REPO" || return
}
