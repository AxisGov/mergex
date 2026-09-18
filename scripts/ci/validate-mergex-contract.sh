#!/usr/bin/env bash
#
# Validador de contrato da mergex — compatibilidade com os worktrees da sprintx.
#
# Checagens determinísticas sobre o texto dos contratos: o que este P0 fixou
# precisa continuar escrito, e o que ele proibiu não pode voltar. Roda em
# qualquer máquina com bash e grep, sem rede e sem dependência nova.
#
# Uso: bash scripts/ci/validate-mergex-contract.sh

set -euo pipefail

fail() {
  printf 'contract check failed: %s\n' "$*" >&2
  exit 1
}

skill='.claude/skills/mergex/SKILL.md'
abertura='.claude/skills/mergex/references/00-abertura.md'
commits='.claude/skills/mergex/references/01-commits.md'
prontidao='.claude/skills/mergex/references/02-prontidao.md'
integ_sprintx='.claude/skills/mergex/references/integracao/sprintx.md'
patch_sprintx='docs/integracao/patch-sprintx.md'
base_sh='.claude/hooks/comum/base.sh'
hook_escopo='.claude/hooks/mergex/arquivo-fora-do-plano.sh'
abrir_cmd='.claude/commands/mergex-abrir.md'
abrir_oc='.opencode/commands/mergex-abrir.md'
mergex_cmd='.claude/commands/mergex.md'
mergex_oc='.opencode/commands/mergex.md'

for f in "$skill" "$abertura" "$commits" "$prontidao" "$integ_sprintx" \
         "$patch_sprintx" "$base_sh" "$hook_escopo" "$abrir_cmd" "$abrir_oc" \
         "$mergex_cmd" "$mergex_oc"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# ---------------------------------------------------------------------------
# Caminho canônico da sprintx, com fallback legado e sem migração automática
# ---------------------------------------------------------------------------
for f in "$abertura" "$integ_sprintx" "$abrir_cmd" "$abrir_oc" "$mergex_cmd" \
         "$mergex_oc" "$skill"; do
  grep -Fq 'docs/sprintx/features/' "$f" \
    || fail "$f does not use the canonical sprintx path"
  grep -Fq 'docs/<slug>/' "$f" \
    || fail "$f dropped the legacy sprintx path fallback"
done
grep -Fq 'Nunca mova a pasta legada' "$abertura" \
  || fail 'E0 no longer forbids moving a legacy work folder'

# V6 e V7 procuram o canônico antes do legado.
grep -Fq 'docs/sprintx/features/<slug>/00-AUDITORIA.md' "$prontidao" \
  || fail 'V6 missing the canonical audit path'
grep -Fq 'docs/<slug>/00-AUDITORIA.md' "$prontidao" \
  || fail 'V6 dropped the legacy audit path'
grep -Fq 'docs/sprintx/features/<slug>/00-BLOQUEIOS.md' "$prontidao" \
  || fail 'V7 missing the canonical blockers path'

# ---------------------------------------------------------------------------
# A runx não regride: os caminhos canônicos dela continuam nos mesmos contratos
# ---------------------------------------------------------------------------
grep -Fq 'docs/manutencao/<OC-ID>-<slug>/ORQUESTRADOR.md' "$abertura" \
  || fail 'E0 lost the runx work path'
grep -Fq 'docs/manutencao/<OC-ID>-<slug>/QA.md' "$prontidao" \
  || fail 'V5 lost the runx QA path'
grep -Fq 'docs/manutencao/<trabalho_id>/' "$commits" \
  || fail 'E1 lost the runx folder among the method artifacts'

# ---------------------------------------------------------------------------
# Base informada pelo chamador: precedência mais alta, validada, sem troca muda
# ---------------------------------------------------------------------------
grep -Fq '1. **Base informada pelo chamador**' "$abertura" \
  || fail 'caller-provided base is not the highest precedence in E0'
grep -Fq 'nunca substitua silenciosamente por outra' "$abertura" \
  || fail 'E0 may silently replace an invalid explicit base'

# ---------------------------------------------------------------------------
# Adoção de branch e worktree; árvore limpa continua barrando criação/troca
# ---------------------------------------------------------------------------
grep -Fq 'Caso A — a branch ativa já é a branch do trabalho' "$abertura" \
  || fail 'E0 has no adoption case for an already-correct branch'
grep -Fq 'não execute `git switch`' "$abertura" \
  || fail 'E0 adoption still switches branches'
grep -Fq 'Caso B — a branch alvo existe e está em uso por outro worktree' "$abertura" \
  || fail 'E0 has no case for a branch checked out in another worktree'
grep -Fq 'git worktree list --porcelain' "$abertura" \
  || fail 'E0 cannot locate a branch checked out in another worktree'
grep -Fq 'nunca remova o worktree de ninguém' "$abertura" \
  || fail 'E0 no longer forbids removing someone else worktree'
grep -Fq 'Árvore limpa é pré-condição para criar ou trocar branch' "$abertura" \
  || fail 'E0 lost the clean-tree precondition wording'
grep -Fq 'Arquivo apenas não rastreado' "$abertura" \
  || fail 'E0 no longer counts untracked files in the clean-tree gate'
grep -Fq 'nunca cria uma segunda branch para o mesmo trabalho' "$abertura" \
  || fail 'E0 no longer forbids a second branch for the same work'
grep -Fq 'adota a branch e o worktree' "$skill" \
  || fail 'SKILL.md does not describe E0 adoption'
grep -Fq 'F1 da sprintx é a dona' "$integ_sprintx" \
  || fail 'integration doc no longer names sprintx F1 as branch/worktree owner'

# A raiz é a que o versionador informa; num worktree, `.git` é arquivo.
grep -Fq 'num worktree é `arquivo`, não diretório' "$skill" \
  || fail 'SKILL.md still assumes .git is a directory when anchoring docs/entregas/'

# ---------------------------------------------------------------------------
# Suíte por task: parcial e verde valem; vermelha e nao_executada barram
# ---------------------------------------------------------------------------
grep -Fq 'Suíte da task: `parcial` ou `verde`' "$commits" \
  || fail 'E1 still demands a green whole suite per task'
grep -Fq '`parcial` e `verde` são registros válidos' "$prontidao" \
  || fail 'V2 does not accept suite: parcial'
grep -Fq '`vermelha` e `nao_executada` são FALHA' "$prontidao" \
  || fail 'V2 no longer fails on red or unexecuted suites'
grep -Fq 'evidência da suíte inteira no fechamento de cada sprint' "$prontidao" \
  || fail 'V2 dropped the whole-suite evidence requirement'

# ---------------------------------------------------------------------------
# Artefato de método do próprio trabalho não é desvio; produto fora do plano é
# ---------------------------------------------------------------------------
grep -Fq 'artefatos de método do próprio trabalho' "$commits" \
  || fail 'E1 does not define method artifacts'
grep -Fq 'docs/sprintx/features/<trabalho_id>/' "$commits" \
  || fail 'E1 does not scope the method-artifact exemption to the work folder'
grep -Fq 'Commit de artefatos de método' "$commits" \
  || fail 'E1 has no deterministic moment for method artifacts'
grep -Fq 'continua sendo desvio' "$commits" \
  || fail 'E1 no longer treats undeclared product files as deviations'
grep -Fq 'artefatos de método do próprio trabalho não são desvio' "$prontidao" \
  || fail 'V9 does not exempt the work own method artifacts'

# ---------------------------------------------------------------------------
# Trabalho corrente do hook de escopo: pela branch, nunca por recência
# ---------------------------------------------------------------------------
grep -Fq 'expx_trabalho_atual_por_branch()' "$base_sh" \
  || fail 'base.sh does not define the branch-based current-work resolver'
grep -Fq 'branch --show-current' "$base_sh" \
  || fail 'the resolver does not read the current branch'

# O helper histórico do rastro continua existindo. A IMPLEMENTAÇÃO dele não é
# contrato: o que este script protege é que o hook de escopo não dependa dela.
grep -Fq 'expx_trabalho_id()' "$base_sh" \
  || fail 'expx_trabalho_id was removed from base.sh'

# Só o código conta: o comentário do hook cita o helper antigo justamente para
# dizer que não o usa.
grep -Fq 'expx_trabalho_atual_por_branch' "$hook_escopo" \
  || fail 'scope hook does not use the branch-based resolver'
if grep -v '^[[:space:]]*#' "$hook_escopo" | grep -Fq 'expx_trabalho_id'; then
  fail 'scope hook still resolves the current work by most recent ENTREGA.md'
fi
if grep -Fq 'estado.json' "$hook_escopo"; then
  fail 'scope hook must never read estado.json to decide the current work'
fi

# A regra está escrita no contrato, não só no código.
grep -Fq 'exatamente um' "$commits" \
  || fail 'E1 does not state the exactly-one rule for identifying the current work'
grep -Fq 'nunca por recência' "$commits" \
  || fail 'E1 does not forbid resolving the current work by recency'

# ---------------------------------------------------------------------------
# O comando manual de revisão nunca é encadeado por contrato nenhum
# ---------------------------------------------------------------------------
# `09-revisao.md` fica fora da varredura: é o reference do PRÓPRIO E9, onde o
# comando é o assunto. Esta varredura existe para pegar menção solta em
# QUALQUER OUTRO contrato, do tipo "ao terminar, rode /mergex-revisar".
encontrou=0
while IFS= read -r linha; do
  [ -n "$linha" ] || continue
  case "$linha" in
    .claude/skills/mergex/references/09-revisao.md:*) continue ;;
    *não*|*NÃO*|*nunca*|*NUNCA*|*nenhum*|*Nenhum*|*manual*|*MANUAL*|*explícit*|*Explícit*|*jamais*) continue ;;
  esac
  printf 'unqualified mergex-revisar mention: %s\n' "$linha" >&2
  encontrou=1
done <<EOF
$(grep -RIn -- 'mergex-revisar' \
    .claude/skills/mergex/references .claude/skills/mergex/assets docs/integracao \
    "$mergex_cmd" "$abrir_cmd" .claude/commands/mergex-pr.md \
    .claude/commands/mergex-check.md 2>/dev/null || true)
EOF
[ "$encontrou" = '0' ] || fail 'mergex-revisar mentioned without an explicit prohibition'

# ---------------------------------------------------------------------------
# P0 — o estado final do E8 é persistido: commit de fechamento + publicação
# ---------------------------------------------------------------------------
registro='.claude/skills/mergex/references/08-registro.md'
push='.claude/skills/mergex/references/06-push.md'
schema='.claude/skills/mergex/references/00-schema.md'
for f in "$registro" "$push" "$schema"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# A regra antiga — deixar a gravação do E8 no disco — não pode voltar.
if grep -Fq 'entra no próximo commit de artefatos' "$commits"; then
  fail 'E1 still defers the E8 final update to a future artifact commit'
fi

grep -Fq '## O fechamento final' "$registro" \
  || fail 'E8 has no final closing step'
grep -Fq 'git status --porcelain' "$registro" \
  || fail 'E8 closing step does not inspect the dirty tree'
grep -Fq 'chore(entrega): finalizar registro do trabalho' "$registro" \
  || fail 'E8 closing commit message missing'
grep -Fq 'chore(entrega): finalizar registro do trabalho' "$commits" \
  || fail 'E1 does not describe the E8 closing commit'
grep -Fq 'Três momentos, e só esses três' "$commits" \
  || fail 'E1 no longer lists the three moments for method artifacts'

# O commit de fechamento é artefato de método, nunca task nem produto.
grep -Fq 'não entra na lista `commits`' "$registro" \
  || fail 'E8 closing commit is not excluded from the task commit list'
grep -Fq 'Nenhum arquivo de produto entra nele' "$registro" \
  || fail 'E8 closing commit does not exclude product files'
grep -Fq 'Nunca `git add .`' "$registro" \
  || fail 'E8 closing commit no longer forbids bulk staging'
grep -Fq 'Varredura de segredo' "$registro" \
  || fail 'E8 closing commit skips the secret sweep'
grep -Fq 'Nunca `--amend`' "$registro" \
  || fail 'E8 closing commit no longer forbids history rewriting'

# Publicação final: mesmo princípio conservador do E6, sem reconciliar nem forçar.
grep -Fq 'git rev-list --count HEAD..origin/<branch>' "$registro" \
  || fail 'E8 final push does not check whether the remote is ahead'
grep -Fq 'nunca `--force-with-lease`' "$registro" \
  || fail 'E8 final push no longer forbids forced publication'
grep -Fq 'O fechamento final' "$push" \
  || fail 'E6 does not point to the E8 final closing'

# push_feito diz a verdade sobre o remoto, e nenhum enum novo foi criado.
grep -Fq 'o commit que carrega este registro está no remoto' "$registro" \
  || fail 'push_feito semantics do not cover the closing commit'
grep -Fq 'commit corretivo' "$registro" \
  || fail 'E8 has no corrective commit when the final push fails'
if grep -Fq 'pending' "$schema"; then
  fail 'expx-schema gained a pending value'
fi

# Sem remoto o fechamento continua acontecendo: a evidência não depende de hospedagem.
grep -Fq 'Sem remoto, sem versionador, sem PR' "$registro" \
  || fail 'E8 does not define the closing behaviour without a remote'

# ---------------------------------------------------------------------------
# P0 final — push_feito por estágio, bloqueio persistido, E0 idempotente
# ---------------------------------------------------------------------------
# A definição antiga de push_feito não pode conviver com o fechamento final.
if grep -Fq '`true` só quando o E6 confirmou que o remoto tem o mesmo commit' "$registro"; then
  fail 'E8 field table still defines push_feito only by the E6 push'
fi
grep -Fq 'Ao encerrar o E8' "$registro" \
  || fail 'push_feito has no end-of-E8 meaning'
grep -Fq 'O E8 revalida a verdade final' "$registro" \
  || fail 'E8 does not revalidate push_feito at the end'
grep -Fq 'A palavra final é do E8' "$push" \
  || fail 'E6 does not defer the final push_feito truth to E8'

# E2 BLOQUEADO: encerra a ENTREGA, mas o bloqueio é persistido pelo E8.
if grep -Fq 'encerre o fluxo da mergex' "$prontidao"; then
  fail 'E2 still ends the whole flow instead of going to E8 for the blocked closing'
fi
grep -Fq 'encerra as etapas de entrega e segue apenas ao E8' "$prontidao" \
  || fail 'E2 does not route a blocked gate to E8'
grep -Fq 'encerra as etapas de entrega' "$skill" \
  || fail 'SKILL.md does not describe the blocked route to E8'
grep -Fq '### Fechamento bloqueado' "$registro" \
  || fail 'E8 has no blocked closing section'
grep -Fq '**O passo 4 não roda**' "$registro" \
  || fail 'blocked closing does not forbid publishing the branch'
grep -Fq 'E2 → E8 (fechamento bloqueado)' "$integ_sprintx" \
  || fail 'sprintx integration does not describe the blocked closing'

# A garantia do fechamento é sobre artefato de método, não sobre a árvore inteira.
if grep -Fq 'árvore fica limpa' "$registro"; then
  fail 'E8 promises a fully clean tree again'
fi
grep -Fq 'não é "árvore inteira limpa"' "$registro" \
  || fail 'E8 lost the precise clean-tree guarantee'

# E0 idempotente: retomada não recria e não apaga histórico.
grep -Fq 'CASO 2 — o arquivo existe' "$abertura" \
  || fail 'E0 has no resume case for an existing ENTREGA.md'
grep -Fq 'Nunca zere' "$abertura" \
  || fail 'E0 resume does not preserve the commit history'
grep -Fq 'Nunca abra um segundo PR e nunca recrie a branch' "$abertura" \
  || fail 'E0 resume may open a second PR or recreate the branch'

# commits é histórico de execução, não índice de plano.
grep -Fq 'um commit por fechamento de task em cada execução' "$commits" \
  || fail 'E1 does not define commits as per-execution history'
grep -Fq 'Nunca apague item antigo' "$commits" \
  || fail 'E1 allows deleting past commit entries on replanning'

# ---------------------------------------------------------------------------
# P0 E2E — HISTORICO global da sprintx (exceção exata) e os dois formatos de sprint
# ---------------------------------------------------------------------------
historico='docs/sprintx/estimativas/HISTORICO.md'
readme='README.md'
[ -f "$readme" ] || fail "missing required file: $readme"

# A exceção existe, é do E1 ao E8, e é EXATA: nunca curinga.
for f in "$commits" "$prontidao" "$registro" "$integ_sprintx"; do
  grep -Fq "$historico" "$f" \
    || fail "$f does not declare the sprintx global method artifact"
done
# No código do hook, curinga nenhum. Nos contratos, o curinga só pode aparecer
# quando a frase o está PROIBINDO — é assim que a regra fica escrita, não só obedecida.
if grep -Fq 'docs/sprintx/estimativas/**' "$hook_escopo" || grep -Fq 'docs/sprintx/**' "$hook_escopo"; then
  fail 'scope hook turned the HISTORICO exception into a wildcard'
fi
for f in "$commits" "$prontidao" "$registro" "$integ_sprintx"; do
  if grep -F -e 'docs/sprintx/estimativas/**' -e 'docs/sprintx/**' "$f" \
     | grep -qv -e 'Não existe isenção' -e 'Nada mais sob' -e 'nada sob' \
                -e 'nada equivalente na runx' -e 'nem para'; then
    fail "$f turned the HISTORICO exception into a wildcard"
  fi
done
grep -Fq 'A exceção é exata' "$commits" \
  || fail 'E1 does not state that the HISTORICO exception is exact'
grep -Fq 'nada equivalente na runx' "$registro" \
  || fail 'E8 does not keep the HISTORICO exception out of runx'
grep -Fq 'a runx não ganha isenção equivalente' "$prontidao" \
  || fail 'V9 does not keep the HISTORICO exception out of runx'

# E1: não entra no commit de task; entra no commit pré-E6.
grep -Fq 'não entra no commit de uma task' "$commits" \
  || fail 'E1 lets the HISTORICO into a task commit'
grep -Fq 'quando a origem é a sprintx** e ele está sujo. É o ponto normal de versionamento' "$commits" \
  || fail 'E1 does not put the HISTORICO in the pre-E6 artifact commit'

# V9: exclusão cirúrgica e válida também para o que já está no histórico da branch.
grep -Fq 'exata e cirúrgica' "$prontidao" \
  || fail 'V9 HISTORICO exclusion is not surgical'
grep -Fq 'já está no histórico da branch' "$prontidao" \
  || fail 'V9 does not cover a HISTORICO committed in a previous attempt'

# E8: bloqueado persiste o HISTORICO; pronto não o perde.
grep -Fq 'Inclusive o `HISTORICO.md`' "$registro" \
  || fail 'blocked closing does not persist the HISTORICO'
grep -Fq 'não entrou no momento pré-E6 esperado' "$registro" \
  || fail 'final closing may lose a still-dirty HISTORICO'

# O hook de escopo implementa a mesma exceção exata, e só para a sprintx.
grep -Fq 'eh_historico_global_sprintx' "$hook_escopo" \
  || fail 'scope hook does not implement the HISTORICO exception'
grep -Fq 'runx nao ganha a isencao' "$hook_escopo" \
  || fail 'scope hook may exempt the HISTORICO for runx work'

# Regra única de leitura de sprint: os dois formatos, num lugar só.
grep -Fq '## Como ler uma sprint da sprintx' "$integ_sprintx" \
  || fail 'sprintx integration has no single sprint-format rule'
grep -Fq 'kind: plano' "$integ_sprintx" \
  || fail 'sprintx integration does not cover the condensed plan'
grep -Fq 'Não exija `sprint.md` nem' "$integ_sprintx" \
  || fail 'sprintx integration still demands sprint.md on condensed plans'
grep -Fq 'a sprintx escreve, a mergex versiona' "$integ_sprintx" \
  || fail 'sprintx integration does not declare HISTORICO ownership'
for f in "$commits" "$prontidao"; do
  grep -Fq 'Como ler uma sprint da sprintx' "$f" \
    || fail "$f does not point to the single sprint-format rule"
done
grep -Fq '`sprint.md` não existe' "$prontidao" \
  || fail 'V2 does not accept a condensed sprint without sprint.md'

# A documentação não pode voltar a dizer que a buildx chama a mergex direto.
if grep -Fq 'invoca `mergex-abrir`, `mergex-check`' "$readme"; then
  fail 'README still says buildx invokes mergex commands directly'
fi

# ---------------------------------------------------------------------------
# P1 — E3: artefatos de método (L4/D4). Reference, agente nos dois harnesses e
# classificador carregam o MESMO contrato efetivo.
# ---------------------------------------------------------------------------
atencao='.claude/skills/mergex/references/03-atencao-humana.md'
agente_cl='.claude/agents/revisor-diff.md'
agente_oc='.opencode/agent/revisor-diff.md'
classificador='.claude/skills/mergex/scripts/classificar-atencao.sh'
atencao_cmd='.claude/commands/mergex-atencao.md'
atencao_oc='.opencode/commands/mergex-atencao.md'
for f in "$atencao" "$agente_cl" "$agente_oc" "$classificador" "$atencao_cmd" "$atencao_oc"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# O espelho OpenCode do agente só pode diferir no frontmatter.
corpo_agente() { awk 'f { print } /^---[[:space:]]*$/ && NR > 1 && !f { f = 1 }' "$1" | sed '/./,$!d'; }
[ "$(corpo_agente "$agente_cl")" = "$(corpo_agente "$agente_oc")" ] \
  || fail 'OpenCode revisor-diff body diverges from the Claude Code agent'
cmp -s "$atencao_cmd" "$atencao_oc" || fail 'OpenCode mergex-atencao command diverges from Claude Code'

# A ordem dos critérios: a do classificador é a das tabelas do reference e do agente.
ordem_script="$(bash "$classificador" --ordem)"
[ "$ordem_script" = 'O1 O2 O3 O4 O5 O6 O7 O8 O9 L1 L2 L3 L4 D1 D2 D3 D4 PADRAO' ] \
  || fail "classifier order changed: $ordem_script"
ordem_tabelas() { grep -oE '^\| [OLD][0-9] \|' "$1" | tr -d '| ' | tr '\n' ' ' | sed 's/ $//'; }
for f in "$atencao" "$agente_cl"; do
  [ "$(ordem_tabelas "$f") PADRAO" = "$ordem_script" ] \
    || fail "$f criteria tables are not in the classifier order ($(ordem_tabelas "$f"))"
done

# L4 e D4: o critério é o mesmo texto no reference e no agente.
criterio_de() { grep -E "^\| $2 \|" "$1" | head -1 | awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3 }'; }
for c in L4 D4; do
  [ -n "$(criterio_de "$atencao" "$c")" ] || fail "reference has no $c criterion"
  [ "$(criterio_de "$atencao" "$c")" = "$(criterio_de "$agente_cl" "$c")" ] \
    || fail "$c criterion text diverges between reference and agent"
done

# O bloco da regra — precedência de O, O em artefato de método, L4, D4, reconhecimento —
# é idêntico, byte a byte, no reference e no agente.
bloco_metodo() { awk '/<!-- contrato-e3:artefato-de-metodo:inicio -->/ { f = 1 } f { print } /<!-- contrato-e3:artefato-de-metodo:fim -->/ { f = 0 }' "$1" | tr -d '\r'; }
[ -n "$(bloco_metodo "$atencao")" ] || fail 'reference lost the method-artifact contract block'
[ "$(bloco_metodo "$atencao")" = "$(bloco_metodo "$agente_cl")" ] \
  || fail 'method-artifact contract block diverges between reference and agent'
for frase in 'Artefato de método nunca anula critério O.' \
             'L4 e D4 só existem pela saída do classificador' \
             '`expx_tool` no frontmatter nunca basta' \
             'O6** fala de código sem cobertura'; do
  bloco_metodo "$atencao" | tr '\n' ' ' | sed 's/  */ /g' | grep -Fq "$frase" \
    || fail "method-artifact block lost: $frase"
done

# O padrão conservador continua escrito nos dois.
grep -Fq 'Um arquivo que não bate em nenhum critério de nenhuma faixa vai para **OLHO OBRIGATÓRIO** por padrão' "$atencao" \
  || fail 'reference lost the conservative default'
grep -Fq '**Arquivo que não bate em nenhum critério vai para OLHO OBRIGATÓRIO**' "$agente_cl" \
  || fail 'agent lost the conservative default'

# D1–D3 não foram afrouxados.
grep -Fq '| D1 | Arquivo de teste que só acrescenta caso |' "$atencao" || fail 'D1 changed in the reference'
grep -Fq '| D2 | Alteração mecânica coberta por teste de regressão verde |' "$atencao" || fail 'D2 changed in the reference'
grep -Fq '| D3 | Arquivo gerado automaticamente, **quando declarado como tal** |' "$atencao" || fail 'D3 changed in the reference'
grep -Fq '"Escrito por um agente" não é "gerado"' "$atencao" || fail 'reference no longer forbids D3 for agent-written files'

# O catálogo do reference é o catálogo do classificador — linha a linha.
catalogo_ref="$(grep -E '^\| (sprintx|runx|mergex) \|' "$atencao" \
  | sed 's/`//g' | awk -F'|' '{ l = ""; for (i = 2; i < NF; i++) { c = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); l = l (i > 2 ? "|" : "") c }; print l }' | sort)"
catalogo_script="$(bash "$classificador" --catalogo | sort)"
[ "$catalogo_ref" = "$catalogo_script" ] || {
  diff <(printf '%s\n' "$catalogo_ref") <(printf '%s\n' "$catalogo_script") >&2 || true
  fail 'method-artifact catalog diverges between reference and classifier'
}

# Nenhum curinga no catálogo: caminhos exatos, só `sprint-NN` e `base/<area>.md` como variáveis.
if bash "$classificador" --catalogo | cut -d'|' -f2 | grep -Eq '\*|\?|\[|^docs/?$|^docs/sprintx/?$|^docs/manutencao/?$'; then
  fail 'method-artifact catalog contains a wildcard'
fi
if grep -v '^[[:space:]]*#' "$classificador" | grep -Eq '"?docs/sprintx/"?\*|docs/sprintx/\*\*|"?docs/"?\*\)'; then
  fail 'classifier recognizes by directory wildcard'
fi
# Nos contratos, o curinga só aparece na frase que o proíbe.
for f in "$atencao" "$agente_cl" "$atencao_cmd" "$skill"; do
  # A frase proibitiva do bloco quebra em duas linhas; as duas são aceitas literalmente.
  if grep -F -e 'docs/sprintx/**' -e 'docs/**' "$f" \
       | grep -Fv -e 'Nenhum curinga de pasta reconhece nada — nem `docs/**`, nem' \
                  -e '`docs/sprintx/**`. Artefato não reconhecido segue a classificação normal' \
       | grep -qv -e 'docs/relatorios/\*\*` da runx' -e 'docs/projeto/\*\*` da buildx'; then
    fail "$f uses a directory wildcard for method artifacts"
  fi
done

# O frontmatter não reconhece nada sozinho: o classificador lê expx_tool só do ENTREGA.md.
if grep -v '^[[:space:]]*#' "$classificador" | grep -F 'expx_tool' | grep -vq 'ENTREGA.md'; then
  fail 'classifier reads expx_tool from something other than the ENTREGA.md'
fi

# A runx tem catálogo próprio e não herda nomes da sprintx.
for nome in 00-DECISOES.md FECHAMENTO.md 00-BLOQUEIOS.md docs/sprintx/estimativas/HISTORICO.md BUILDX-PREMISSAS.md; do
  if bash "$classificador" --catalogo | grep -Eq "^runx\|$nome\|"; then
    fail "runx catalog inherited the sprintx artifact $nome"
  fi
done

# Os comandos do E3 apontam para L1–L4, D1–D4 e para o classificador.
grep -Fq 'LEITURA RÁPIDA (L1–L4), DISPENSÁVEL (D1–D4)' "$atencao_cmd" || fail 'E3 command does not list L4/D4'
grep -Fq 'classificar-atencao.sh' "$atencao_cmd" || fail 'E3 command does not call the classifier'
grep -Fq 'classificar-atencao.sh' "$agente_cl" || fail 'agent does not call the classifier'

# ---------------------------------------------------------------------------
# P0.2-A4 — o portão registra as falhas e o E8 deriva a causa. Schema, E2, E8,
# E0, template e script carregam o MESMO enum e a MESMA ordem.
# ---------------------------------------------------------------------------
causa_sh='.claude/skills/mergex/scripts/causa-do-portao.sh'
template_entrega='.claude/skills/mergex/assets/TEMPLATE-ENTREGA.md'
for f in "$causa_sh" "$template_entrega" scripts/ci/test-causa-portao.sh; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# A tabela do schema é a tabela do script: ordem, verificação e causa, linha a linha.
tabela_schema="$(grep -E '^\| [0-9]+ \| `v[0-9]+` \| `[a-z_]+` \|$' "$schema" | tr -d '`' \
  | awk -F'|' '{ gsub(/ /, ""); print $3 "|" $4 }')"
[ -n "$tabela_schema" ] || fail 'schema lost the causa table'
ordem_schema="$(printf '%s\n' "$tabela_schema" | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')"
[ "$ordem_schema" = "$(bash "$causa_sh" --ordem)" ] \
  || fail "causa precedence diverges: schema '$ordem_schema' vs script '$(bash "$causa_sh" --ordem)'"
[ "$(printf '%s\n' "$tabela_schema" | sort)" = "$(bash "$causa_sh" --causas | grep -v '^\*' | sort)" ] \
  || fail 'causa enum diverges between schema and script'
[ "$(bash "$causa_sh" --causas | grep -c .)" = 11 ] || fail 'causa enum gained or lost a value'
bash "$causa_sh" --causas | grep -Fxq '*|indeterminada' || fail 'causa enum lost indeterminada'
grep -Fq '**`indeterminada`**' "$schema" || fail 'schema does not define indeterminada'
if bash "$causa_sh" --causas | grep -Eq 'falha_tecnica|decisao_humana|trabalho_novo|recurso_externo'; then
  fail 'causa enum absorbed a classification that is not observable by the gate'
fi

# A chave nunca é omitida: exemplos, template, E0 e E2 carregam as duas.
bloco_exemplo() { awk '/^```yaml$/ { n++; f = (n == ALVO) ; next } /^```$/ { f = 0 } f' ALVO="$2" "$1"; }
for par in "$schema:2" "$registro:1"; do
  arq="${par%:*}"; n="${par##*:}"
  bloco_exemplo "$arq" "$n" | bash "$causa_sh" --validar - >/dev/null 2>&1 \
    || fail "$arq example ENTREGA does not pass causa-do-portao --validar"
done
grep -Eq '^falhas_portao: ' "$template_entrega" || fail 'ENTREGA template omits falhas_portao'
grep -Eq '^causa: ' "$template_entrega" || fail 'ENTREGA template omits causa'
grep -Fq '`falhas_portao: []`, `causa: null`' "$abertura" || fail 'E0 does not create falhas_portao and causa'
grep -Fq '| `falhas_portao`, `causa` | voltam para `[]` e `null`' "$abertura" || fail 'E0 resume keeps a stale causa'
grep -Fq '## Registro das falhas' "$prontidao" || fail 'E2 does not register the failures'
grep -Fq '`vN_sem_prova`' "$prontidao" || fail 'E2 does not register unverifiable checks apart'
grep -Fq 'O portão **não grava `causa`**' "$prontidao" || fail 'E2 writes causa before the E8 closing'

# O E8 deriva pelo script, na mesma gravação do estado bloqueado, e nunca deixa null.
grep -Fq 'causa-do-portao.sh --derivar' "$registro" || fail 'E8 does not derive causa with the script'
grep -Fq 'causa-do-portao.sh --validar' "$registro" || fail 'E8 does not validate causa before committing'
grep -Fq '**nunca** `causa: null` com `estado: bloqueado`' "$registro" || fail 'E8 allows a null causa when blocked'
grep -Fq 'Um bloqueio legado nunca' "$schema" || fail 'schema may backfill a causa for legacy blocks'

printf 'contract checks passed\n'
