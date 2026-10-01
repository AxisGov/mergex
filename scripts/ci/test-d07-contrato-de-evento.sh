#!/usr/bin/env bash
#
# Bancada D-07 — os exemplos normativos de rastro obedecem o contrato
# `expx-eventos` v1.
#
# Todo exemplo de linha de rastro escrito nas instruções da mergex é normativo:
# é dele que quem executa copia a linha que vai para
# `docs/eventos/<trabalho_id>.jsonl`. Um exemplo fora do contrato não é erro de
# documentação — é a skill mandando gravar rastro que o painel reprova.
#
# Esta bancada confere, exemplo por exemplo:
#   1. as doze chaves obrigatórias estão todas presentes (R6);
#   2. `agente` está no enum fechado e **nunca** é `null` — `principal` é o
#      valor quando não há subagente, e "foi o principal" é informação, não
#      ausência;
#   3. `evento` está no vocabulário fechado — nenhum nome inventado.
#
# E confere a política da lacuna (DM-43, estendida pela DM-177): quando o
# vocabulário não nomeia a ocorrência, a passagem é SILENCIOSA e a lacuna fica
# escrita para o dono do contrato. Nada de evento novo, nada de evento existente
# com semântica falsa.
#
# A fonte do contrato é a ExpxDev (`docs/contrato/CONTRATO-expx-eventos.md` e
# `src/parser/esquema/evento.ts`, enums `EventoNome` e `Agente`), que não é
# alcançável deste repositório. As duas listas abaixo são a cópia conferida
# contra o `780cc5cc` daquele repositório — o commit em que o enum foi
# reconciliado com o catálogo congelado da sprintx, e que mantém
# `artefato_gravado` reprovando. Ampliar qualquer uma destas listas aqui
# afrouxaria o contrato de um lado só: o enum mora lá.
#
# Sem rede, sem jq. Nada fora deste repositório é lido ou tocado.
#
# Uso: bash scripts/ci/test-d07-contrato-de-evento.sh

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO" || exit 1

OK=0; FALHOU=0; PULADOS=0
ok()    { OK=$((OK+1));         printf '  ok    %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  FALHA %s\n' "$1"; }
pula()  { PULADOS=$((PULADOS+1)); printf '  pulado %s\n' "$1"; }

# As doze chaves obrigatórias, na ordem do contrato.
CHAVES='ts expx_eventos trabalho_id ferramenta origem evento fase task agente resultado detalhe arquivos'

# O enum `Agente`. `principal` é o valor quando não há subagente.
AGENTES='principal auditor-plano revisor-testes qa investigador cartografo revisor-diff analista-de-conflito avaliador-de-raio'

# O enum `EventoNome`. `artefato_gravado` NÃO está aqui, e é isso que esta
# bancada defende: a mergex não tem evento para "gravou artefato".
EVENTOS='fase_iniciada fase_concluida task_iniciada task_concluida task_bloqueada
task_reaberta checkpoint_planejamento replanejamento_execucao_iniciado
replanejamento_execucao_retomado replanejamento_execucao_aprovado
replanejamento_execucao_esgotado replanejamento_execucao_recusado
bloqueio_resolvido suite_executada arquivo_alterado regra_violada acao_bloqueada
agente_iniciado agente_concluido veredito_emitido commit_criado pr_aberto'

# Os arquivos de instrução da skill e dos hooks. Fixture não entra: ela é dado
# de teste de outra bancada, não instrução que alguém copia.
instrucoes() {
  find .claude .opencode docs AGENTS.md README.md \
       -type f \( -name '*.md' -o -name '*.sh' \) 2>/dev/null \
    | grep -v '/scripts/ci/fixtures/' \
    | LC_ALL=C sort
}

# Trecho entre crases é CITAÇÃO, não instrução: é assim que um texto nomeia o
# que proíbe, e a DM-175 já fixou essa distinção para `{{...}}`. As varreduras
# de regressão abaixo leem as instruções com os trechos `assim` apagados, para
# que explicar a proibição não conte como cometê-la. Bloco cercado (```) não é
# trecho inline e continua inteiro — é lá que vivem os exemplos normativos.
sem_citacao() { # <arquivo> — imprime arq:num:linha, sem os trechos inline
  # `substr`/`length` e nada de split com FS vazio: isto roda no awk do macOS
  # também (ver "Nota de portabilidade" em `.claude/hooks/README.md`).
  awk -v arq="$1" '{
    if ($0 ~ /^[[:space:]]*```/) { print arq ":" NR ":" $0; next }
    fora = ""; dentro = 0
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "`") { dentro = !dentro; continue }
      if (!dentro) fora = fora c
    }
    print arq ":" NR ":" fora
  }' "$1"
}

# instrucoes_sem_citacao — todas as instruções, já sem os trechos entre crases
instrucoes_sem_citacao() {
  local f
  instrucoes | while IFS= read -r f; do sem_citacao "$f"; done
}

# em_lista <valor> <lista>
em_lista() {
  local v="$1" x
  for x in $2; do [ "$x" = "$v" ] && return 0; done
  return 1
}

# valor_de <chave> <linha json> — devolve o valor cru, com aspas se as tiver
valor_de() {
  printf '%s\n' "$2" | sed -n "s/.*\"$1\":\\([^,}]*\\).*/\\1/p"
}

# ---------------------------------------------------------------------------
# 1. Cada exemplo de linha de rastro, chave por chave
# ---------------------------------------------------------------------------
echo 'Exemplos normativos de linha de rastro'

ACHADOS=0
while IFS= read -r achado; do
  [ -n "$achado" ] || continue
  arq="${achado%%:*}"; resto="${achado#*:}"
  num="${resto%%:*}"; linha="${resto#*:}"
  ACHADOS=$((ACHADOS + 1))
  onde="$arq:$num"

  faltando=''
  for c in $CHAVES; do
    case "$linha" in *"\"$c\":"*) ;; *) faltando="$faltando $c" ;; esac
  done
  if [ -n "$faltando" ]; then
    falha "$onde — chave omitida:$faltando (use null; R6)"
  else
    ok "$onde — as doze chaves estão presentes"
  fi

  ag="$(valor_de agente "$linha")"
  case "$ag" in
    null) falha "$onde — agente:null; sem subagente o valor é \"principal\", nunca null" ;;
    '"'*'"')
      if em_lista "${ag//\"/}" "$AGENTES"; then
        ok "$onde — agente=$ag está no enum"
      else
        falha "$onde — agente=$ag fora do enum Agente"
      fi ;;
    *) falha "$onde — agente=${ag:-<ausente>} não é um valor do enum" ;;
  esac

  ev="$(valor_de evento "$linha")"
  case "$ev" in
    '"'*'"')
      if em_lista "${ev//\"/}" "$EVENTOS"; then
        ok "$onde — evento=$ev está no vocabulário"
      else
        falha "$onde — evento=$ev fora do vocabulário fechado (nenhum nome inventado)"
      fi ;;
    *) falha "$onde — evento=${ev:-<ausente>} não é um nome do vocabulário" ;;
  esac
done <<EOF
$(instrucoes | xargs grep -n '"expx_eventos":1' 2>/dev/null)
EOF

[ "$ACHADOS" -ge 4 ] \
  && ok "$ACHADOS exemplos conferidos" \
  || falha "só $ACHADOS exemplo(s) encontrado(s) — a varredura deixou de ver os exemplos"

# Os escritores que a skill tem em disco também gravam a linha, e o enum vale
# para eles igual: o jq do rastro dos hooks não pode voltar a `agente: null`.
base_sh='.claude/hooks/comum/base.sh'
if grep -Fq 'agente:"principal"' "$base_sh"; then
  ok "$base_sh — o rastro dos hooks grava agente:\"principal\""
else
  falha "$base_sh — o rastro dos hooks deixou de gravar agente:\"principal\""
fi

# ---------------------------------------------------------------------------
# 2. Nenhum exemplo volta a `agente: null`, em nenhuma grafia
# ---------------------------------------------------------------------------
echo
echo 'Regressão: agente nunca volta a null'

for padrao in '"agente":null' '"agente": null' 'agente:null' 'agente: null'; do
  if achou="$(instrucoes_sem_citacao | grep -F -- "$padrao" 2>/dev/null)" && [ -n "$achou" ]; then
    falha "\`$padrao\` reapareceu:"
    printf '        %s\n' "$achou"
  else
    ok "nenhuma ocorrência de \`$padrao\`"
  fi
done

# ---------------------------------------------------------------------------
# 3. O vocabulário não foi ampliado: `artefato_gravado` não existe na mergex
# ---------------------------------------------------------------------------
echo
echo 'Regressão: nenhum evento inventado'

if em_lista artefato_gravado "$EVENTOS"; then
  falha 'a própria lista desta bancada foi ampliada com artefato_gravado'
else
  ok 'artefato_gravado continua fora do vocabulário desta bancada'
fi

# A cópia dos enums é conferida contra o tamanho canônico do `780cc5cc`: 22
# eventos e 9 agentes. Ampliar a cópia aqui afrouxaria o contrato de um lado só,
# e é a primeira coisa que esta bancada barra — inclusive para `null`, que não é
# valor de enum em lugar nenhum.
n_ev="$(printf '%s\n' $EVENTOS | grep -c .)"
[ "$n_ev" = 22 ] \
  && ok "o vocabulário desta bancada tem os 22 eventos canônicos" \
  || falha "o vocabulário desta bancada tem $n_ev eventos, não os 22 canônicos"
n_ag="$(printf '%s\n' $AGENTES | grep -c .)"
[ "$n_ag" = 9 ] \
  && ok "o enum de agente desta bancada tem os 9 valores canônicos" \
  || falha "o enum de agente desta bancada tem $n_ag valores, não os 9 canônicos"
if em_lista null "$AGENTES"; then
  falha 'null entrou no enum de agente desta bancada'
else
  ok 'null continua fora do enum de agente desta bancada'
fi

if achou="$(instrucoes_sem_citacao | grep -F -- 'artefato_gravado' 2>/dev/null)" && [ -n "$achou" ]; then
  falha 'artefato_gravado é gravado ou mandado gravar em instrução:'
  printf '        %s\n' "$achou"
else
  ok 'nenhuma instrução manda gravar artefato_gravado'
fi

# E não foi substituído por um evento existente com semântica falsa: a falha de
# gravação do estado.json não é commit, não é PR e não é veredito.
estado='.claude/skills/mergex/references/10-estado.md'
tolerancia="$(awk '/^## Tolerância a falha/ { f = 1; next } /^## / { f = 0 } f' "$estado")"
if printf '%s\n' "$tolerancia" | grep -Eq '"evento":"[a-z_]+"'; then
  falha "$estado — a tolerância a falha voltou a mandar gravar um evento"
else
  ok "$estado — a tolerância a falha não grava evento nenhum"
fi

# ---------------------------------------------------------------------------
# 4. A política da lacuna (DM-43, estendida pela DM-177)
# ---------------------------------------------------------------------------
echo
echo 'Política da lacuna: passagem silenciosa e lacuna registrada'

decisoes='.claude/skills/mergex/DECISOES-DA-SKILL.md'
grep -Fq '| DM-43 |' "$decisoes" \
  && ok 'DM-43 continua no registro de decisões' \
  || falha 'DM-43 saiu do registro de decisões'
grep -Fq '| DM-177 |' "$decisoes" \
  && ok 'DM-177 registra a extensão da política para o estado.json' \
  || falha 'DM-177 não está no registro de decisões'

# A lacuna fica escrita onde a ocorrência acontece, e nomeia o dono.
grep -Fq 'LACUNA REGISTRADA' "$estado" \
  && ok "$estado — a lacuna está registrada no texto" \
  || falha "$estado — a lacuna não está registrada"
grep -Fq 'dono do contrato' "$estado" \
  && ok "$estado — a lacuna nomeia o dono do contrato" \
  || falha "$estado — a lacuna não diz de quem é a decisão"
grep -Fq 'silenciosa' "$estado" \
  && ok "$estado — a passagem é declarada silenciosa" \
  || falha "$estado — o texto não declara a passagem silenciosa"

# A justificativa da passagem silenciosa não pode afirmar o que o fluxo não
# garante no instante da falha. O `estado.json` é gravado no E0, no E7, no E8 e
# no E9; nos dois primeiros o `ENTREGA.md` está **só na árvore de trabalho** —
# quem o leva ao histórico é o fechamento final do E8 (`07-abertura-pr.md`:
# "O E7 não commita e não faz push"; `08-registro.md`, passo 2). Dizer ali que
# ele "já foi commitado" troca a razão verdadeira — derivado nunca é entrada de
# decisão nenhuma — por uma garantia que o E0 e o E7 não dão.
if grep -Fq 'foi gravado e commitado de todo modo' "$estado"; then
  falha "$estado — a justificativa afirma commit do ENTREGA.md que o E0 e o E7 não fizeram"
else
  ok "$estado — a justificativa não inventa commit do ENTREGA.md no E0 nem no E7"
fi
grep -Fq 'fechamento final do E8' "$estado" \
  && ok "$estado — a justificativa nomeia quem leva o ENTREGA.md ao histórico" \
  || falha "$estado — a justificativa não nomeia o fechamento final do E8"
# E a razão que sustenta a passagem silenciosa continua sendo a do derivado.
grep -Fq 'saída derivada' "$estado" \
  && ok "$estado — a razão da passagem silenciosa continua sendo o derivado" \
  || falha "$estado — o texto perdeu a razão de que o estado.json é saída derivada"

# A lacuna do hook (DM-43) não foi apagada nem reaproveitada.
grep -Fq 'LACUNA REGISTRADA' '.claude/hooks/comum/base.sh' \
  && ok 'base.sh — a lacuna da passagem limpa do hook continua registrada' \
  || falha 'base.sh — a lacuna da DM-43 foi apagada'
grep -Fq 'Lacuna registrada no contrato' '.claude/hooks/README.md' \
  && ok 'hooks/README.md — a lacuna da DM-43 continua documentada' \
  || falha 'hooks/README.md — a seção da lacuna da DM-43 desapareceu'

# ---------------------------------------------------------------------------
# 5. A falha de gravação continua não interrompendo o fluxo
# ---------------------------------------------------------------------------
echo
echo 'Regressão: a falha de gravação do estado.json não interrompe nada'

# Todo lugar que fala da falha de gravação do estado.json: nenhum pode mandar
# gravar rastro, e todos têm que continuar dizendo que o fluxo segue.
R='.claude/skills/mergex/references'
for par in \
  "$R/00-abertura.md|o E0 continua OK" \
  "$R/07-abertura-pr.md|não interrompe o E7" \
  "$R/08-registro.md|não interrompe" \
  "$R/09-revisao.md|sem interromper" \
  "$estado|nunca interrompe" \
  "$estado|A barra nunca é motivo de interrupção de trabalho"
do
  arq="${par%%|*}"; frase="${par##*|}"
  grep -Fq "$frase" "$arq" \
    && ok "$arq — \"$frase\" continua escrito" \
    || falha "$arq — perdeu a regra de que a falha não interrompe (\"$frase\")"
done

# A frase que mandava gravar a falha no rastro não sobreviveu em lugar nenhum:
# ela é a instrução que produzia a linha fora do contrato.
if achou="$(grep -rn -i -e 'gravação vai para o rastro' -e 'gravação vai\s*$' -e 'Registra no rastro e segue' "$R" 2>/dev/null)" && [ -n "$achou" ]; then
  falha 'ainda há instrução mandando gravar a falha do estado.json no rastro:'
  printf '        %s\n' "$achou"
else
  ok 'nenhuma instrução manda a falha do estado.json para o rastro'
fi

# ---------------------------------------------------------------------------
# 6. O arranjo da bancada de mutação não mede mutante em cópia parcial
# ---------------------------------------------------------------------------
# `copia()` monta cada cópia com `git ls-files | tar | tar`. Se esse pipeline
# falhar, a cópia sai incompleta — e aí o mutante morre por arquivo faltando,
# não pela mutação, ou sobrevive porque a bancada não encontrou o que conferir.
# Mutante medido em cópia parcial não é evidência de nada, e o relatório
# o relatório de mutantes mortos passaria a afirmar o que não foi verificado.
#
# O caso é real, não hipotético: o `tar` sai 1 em aviso ("file changed as we
# read it") com o arquivo já gravado por inteiro. O arranjo abaixo reproduz
# exatamente isso — árvore completa, status de falha — e a bancada de mutação
# tem que abortar em vez de relatar mutante.
#
# Esta seção não roda dentro das cópias (MERGEX_D07_EM_COPIA): ela invoca a
# própria bancada de mutação, e sem o guarda a recursão não teria fundo.
echo
echo 'Arranjo: a bancada de mutação aborta quando a cópia da árvore falha'
mutacao='scripts/ci/mutacao-d07-contrato-de-evento.sh'

# Antes do arranjo executável, uma conferência estática sobre o mutante M15.
# O que o M15 faz é apagar do arranjo a âncora de diagnóstico do aborto da
# cópia — e só ela: `copia()` continua abortando pelos dois `return 1`, e o
# mutante morre na âncora que o validador de contrato exige. Quem mede o aborto
# de verdade é o arranjo executável logo abaixo. Um M15 que se anuncie como
# "volta a mascarar falha do pipeline" descreve um defeito que ele não produz, e
# o relatório de mutantes mortos passa a prometer cobertura que vem de outro
# lugar — exatamente o tipo de alegação a mais que esta bancada existe para
# barrar no texto da skill.
if grep -Fq 'volta a mascarar falha do pipeline' "$mutacao"; then
  falha "$mutacao — M15 alega restaurar o mascaramento, mas a mutação só remove a âncora de diagnóstico"
else
  ok "$mutacao — M15 anuncia o que a mutação faz: remover a âncora, não o aborto"
fi
grep -Fq 'M15|a âncora do aborto da cópia' "$mutacao" \
  && ok "$mutacao — M15 nomeia a âncora do aborto da cópia como o que ele mede" \
  || falha "$mutacao — M15 não nomeia a âncora do aborto da cópia como o que ele mede"

tar_real="$(command -v tar 2>/dev/null || true)"
if [ -n "${MERGEX_D07_EM_COPIA:-}" ]; then
  pula "$mutacao — arranjo não é medido dentro da cópia da própria bancada"
elif [ -z "$tar_real" ]; then
  pula "$mutacao — sem tar nesta máquina, o arranjo não pode ser reproduzido"
else
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/tar" <<STUB
#!/bin/sh
# tar que faz o trabalho inteiro e ainda assim sai 1, como no aviso do GNU tar.
"$tar_real" "\$@"
exit 1
STUB
  chmod +x "$stub_dir/tar"
  if PATH="$stub_dir:$PATH" bash "$mutacao" M1 >/dev/null 2>&1; then
    falha "$mutacao — copia() mascara falha do pipeline: mutante relatado sobre cópia suspeita"
  else
    ok "$mutacao — copia() aborta quando o pipeline git ls-files | tar falha"
  fi
  rm -rf "$stub_dir"

  # O outro caminho da cópia parcial: árvore incompleta com status ZERO, que é o
  # que `xargs` partindo a lista em várias chamadas de `tar` produz. O arranjo
  # tem que poupar a PRIMEIRA extração — a do controle —, senão o controle
  # reprova e o arranjo passaria por ele, não por `copia()`. Poupado o controle,
  # a cópia do mutante sai sem o arquivo que a bancada lê: sem o guarda, o M1 é
  # declarado "morto" porque a bancada não achou o que conferir, e o relatório
  # "mutantes mortos" afirma o que não foi medido.
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/tar" <<STUB
#!/bin/sh
"$tar_real" "\$@"
st=\$?
case " \$* " in
  *" -xf "*)
    n=0
    [ -f "$stub_dir/n" ] && n=\$(cat "$stub_dir/n")
    n=\$((n + 1)); printf '%s' "\$n" > "$stub_dir/n"
    [ "\$n" -ge 2 ] && rm -f .claude/skills/mergex/references/10-estado.md
    ;;
esac
exit \$st
STUB
  chmod +x "$stub_dir/tar"
  if PATH="$stub_dir:$PATH" bash "$mutacao" M1 >/dev/null 2>&1; then
    falha "$mutacao — copia() aceita cópia incompleta com status zero: o mutante seria medido sem o arquivo que ele muta"
  else
    ok "$mutacao — copia() aborta quando a cópia sai incompleta com status zero"
  fi
  rm -rf "$stub_dir"
fi

echo
echo '---------------------------------------------'
printf '%d ok, %d falha(s), %d pulado(s)\n' "$OK" "$FALHOU" "$PULADOS"
[ "$FALHOU" = "0" ]
