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
[ "$(bash "$causa_sh" --causas | grep -c .)" = 12 ] || fail 'causa enum gained or lost a value'
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

# ---------------------------------------------------------------------------
# P0.2-C3 — V11: task concluída sem commit do E1. Reference, template, comandos
# nos dois harnesses, script e enum carregam a MESMA verificação.
# ---------------------------------------------------------------------------
prova_sh='.claude/skills/mergex/scripts/prova-de-commit.sh'
template_prontidao='.claude/skills/mergex/assets/TEMPLATE-prontidao.md'
check_cmd='.claude/commands/mergex-check.md'
check_oc='.opencode/commands/mergex-check.md'
hook_pr='.claude/hooks/mergex/pr-so-com-portao.sh'
for f in "$prova_sh" "$template_prontidao" "$check_cmd" "$check_oc" "$hook_pr" \
         scripts/ci/test-portao-v11.sh; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# O espelho OpenCode do comando do portão nunca diverge.
cmp -s "$check_cmd" "$check_oc" || fail 'OpenCode mergex-check command diverges from Claude Code'

# São ONZE verificações, e a contagem antiga não pode voltar em lugar nenhum.
# A varredura ignora as fixtures (snapshots congelados) e este próprio arquivo,
# que precisa citar a forma antiga para poder proibi-la. `-i` porque a contagem
# aparece no começo de frase ("Dez verificações") e no badge ("10 verificacoes").
if grep -rIl -i --exclude-dir=.git -e 'dez verifica' -e '10 verifica' -e 'V1\.\.V10)' -e 'as dez linhas' . \
   | grep -v -e '^\./scripts/ci/fixtures/' -e '^\./scripts/ci/validate-mergex-contract\.sh$' \
   | grep -q .; then
  fail 'the gate is still described as ten checks somewhere'
fi
grep -Fq 'Onze verificações' "$readme" || fail 'README no longer announces eleven checks'
grep -Fq '11 verificacoes' .github/assets/badge-portao.svg || fail 'gate badge still shows ten checks'
grep -Fq '## As onze verificações' "$prontidao" || fail 'E2 no longer announces eleven checks'
grep -Fq 'a tabela das onze verificações' "$prontidao" || fail 'E2 output table is not eleven rows'
grep -Fq 'As onze linhas da tabela' "$template_prontidao" || fail 'readiness template is not eleven rows'
grep -Fq '| V11 |' "$template_prontidao" || fail 'readiness template has no V11 row'
grep -Fq '| V11 |' "$check_cmd" || fail 'E2 command has no V11 row'
grep -Fq 'onze verificações (V1..V11)' "$hook_pr" || fail 'PR hook still announces ten checks'

# A V11 existe, é própria, e não é uma V1/V2 ampliada.
grep -Fq '### V11 — Task concluída sem commit do E1 correspondente' "$prontidao" \
  || fail 'E2 has no V11 section'
grep -Fq 'pelo menos um** item em `ENTREGA.commits`' "$prontidao" \
  || fail 'V11 does not require at least one commits item'
grep -Fq 'nunca exatamente um' "$prontidao" \
  || fail 'V11 may demand exactly one commit per task'
grep -Fq 'não é alvo positivo** da V11' "$prontidao" \
  || fail 'V11 no longer spares tasks that are not concluded'
grep -Fq 'A V11 não audita o `git log`' "$prontidao" \
  || fail 'V11 turned into a git log audit'
grep -Fq 'prova-de-commit.sh' "$prontidao" || fail 'E2 does not call the V11 script'
grep -Fq 'prova-de-commit.sh' "$check_cmd" || fail 'E2 command does not call the V11 script'

# `versionado` é do repositório, nunca da task: a isenção não vira exceção textual.
grep -Fq '`versionado: false` | `n/a`' "$prontidao" \
  || fail 'V11 does not mark n/a for an unversioned repository'
if grep -RIn --exclude-dir=.git -e 'task.*versionado: false' -e 'versionado.*por task' \
     .claude/skills/mergex/references | grep -qv 'nunca'; then
  fail 'a per-task versionado exemption was invented for V11'
fi

# O E1 tardio continua permitido, acrescenta ao fim e não reordena o histórico.
grep -Fq '### O E1 tardio' "$commits" || fail 'E1 has no late-commit procedure'
grep -Fq '**Não reordene** os itens antigos' "$commits" \
  || fail 'the late E1 may reorder the existing commit history'
grep -Fq 'E1 tardio' "$prontidao" || fail 'E2 does not point to the late E1 as the fix'
grep -Fq 'a **V11**' "$commits" || fail 'E1 does not name V11 as the check that enforces its promise'

# A causa da V11: valor próprio, última posição do grupo que lê a execução.
grep -Fq '| 11 | `v11` | `commit_nao_registrado` |' "$schema" \
  || fail 'schema has no causa row for v11'
grep -Fq '`v1` … `v11`' "$schema" || fail 'schema falhas_portao enum does not reach v11'
[ "$(bash "$causa_sh" --derivar v11)" = commit_nao_registrado ] \
  || fail 'v11 does not derive commit_nao_registrado'
[ "$(bash "$causa_sh" --derivar v1 v11)" = tarefa_nao_concluida ] \
  || fail 'v11 outranks v1 in the precedence order'
[ "$(bash "$causa_sh" --derivar v11_sem_prova)" = indeterminada ] \
  || fail 'v11 without proof does not derive indeterminada'
grep -Fq '`commit_nao_registrado` não é `tarefa_nao_concluida`' "$schema" \
  || fail 'schema does not separate commit_nao_registrado from tarefa_nao_concluida'
grep -Eq '^falhas_portao: .*v1\.\.v11' "$template_entrega" \
  || fail 'ENTREGA template does not reach v11 in falhas_portao'

# ---------------------------------------------------------------------------
# P0.2-C4 — a ordem de registro de ENTREGA.commits: a chave `seq`
# ---------------------------------------------------------------------------
seq_sh='.claude/skills/mergex/scripts/sequencia-de-commits.sh'
[ -f "$seq_sh" ] || fail "missing required file: $seq_sh"

# O contrato da chave vive no schema, e é um contrato só.
grep -Fq '## A ordem de registro — a chave `seq`' "$schema" \
  || fail 'schema has no section for the commits order key'
grep -Fq 'Inteiro **positivo**' "$schema" || fail 'seq is not declared a positive integer'
grep -Fq '**Global à ENTREGA**' "$schema" || fail 'seq is not declared global to the ENTREGA'
grep -Fq 'o maior `seq` efetivo existente + 1' "$schema" \
  || fail 'schema does not define how the next seq is computed'
grep -Fq 'Reutilizado, renumerado, reordenado, diminuído, nem escolhido por task' "$schema" \
  || fail 'schema dropped what seq must never be'
grep -Fq 'Ele conta **registros de E1**, e nada mais' "$schema" \
  || fail 'schema does not fence off what seq is not'

# O prefixo legado é exceção de LEITURA, com fim declarado — e sem backfill.
grep -Fq '### O prefixo legado' "$schema" || fail 'schema has no legacy-prefix rule'
grep -Fq 'nenhum item posterior pode voltar a omiti-lo' "$schema" \
  || fail 'the legacy prefix has no declared end'
grep -Fq '| `[legado, legado, seq 3, seq 4]` | válida |' "$schema" \
  || fail 'schema lost the valid legacy-prefix example'
grep -Fq '| `[seq 1, legado]` | **inválida** |' "$schema" \
  || fail 'schema lost the invalid legacy-after-modern example'
for f in "$schema" "$commits" "$template_entrega"; do
  grep -Fq 'backfill' "$f" || fail "$f does not forbid backfilling seq on legacy items"
done
grep -Fq 'NÃO autoriza **backfill de `seq`**' "$schema" \
  || fail 'the migration rule does not forbid seq backfill'

# A invariante, e as quatro listas que ela recusa.
grep -Fq 'todo `seq` explícito é igual à posição do seu item' "$schema" \
  || fail 'schema does not state the sequence invariant'
for d in duplicata buraco 'regressão' 'reordenação'; do
  grep -Fq "$d" "$schema" || fail "schema does not name $d as an invalid sequence"
done

# Sequência quebrada é contrato inválido, não causa de negócio do portão.
grep -Fq 'não são causa de negócio do' "$schema" \
  || fail 'schema turns a broken sequence into a gate cause'
grep -Fq 'não entram em `falhas_portao`' "$schema" \
  || fail 'schema lets a broken sequence enter falhas_portao'
grep -Fq 'Nunca "conserte" escolhendo outro número' "$schema" \
  || fail 'schema allows picking another number to fit'
# `seq` como identificador, não como pedaço de "sequência"/"consequência": a
# causa do bloqueio não conhece a chave de ordem, e nunca vai derivar dela.
if grep -Eq '(^|[^a-zà-ú])seq($|[^a-zà-ú])' "$causa_sh"; then
  fail 'the gate cause script learned about seq'
fi

# Data é registro; quando há ordem contratual, existe campo de ordem.
grep -Fq 'datas são registro' "$schema" \
  || fail 'schema does not state the date-vs-order rule'
grep -Fq 'não é fonte canônica' "$schema" \
  || fail 'schema does not rule out the local event trail as the order source'

# Entrega nova: a lista nasce vazia e não há contador de topo.
grep -Fq '**Não existe `seq` de topo**' "$schema" \
  || fail 'schema does not forbid a top-level seq counter'
grep -Fq '**Não existe `seq` de topo**' "$abertura" \
  || fail 'E0 does not forbid a top-level seq counter'
grep -Fq 'commits: []' "$abertura" || fail 'E0 no longer opens the list empty'

# O escritor canônico: um só, e é ele que o E1 chama.
grep -Fq 'sequencia-de-commits.sh --acrescentar' "$commits" \
  || fail 'E1 does not call the canonical commits writer'
grep -Fq 'Não escreva o item à mão' "$commits" \
  || fail 'E1 still lets the item be written by hand'
grep -Fq 'Gravação nova nunca cria item sem `seq`' "$commits" \
  || fail 'E1 allows a new legacy item'
grep -Fq 'Sequência quebrada PARA' "$commits" \
  || fail 'E1 does not stop on a broken sequence'
grep -Fq 'sequencia-de-commits.sh' "$template_entrega" \
  || fail 'ENTREGA template does not point at the commits writer'
grep -Fq '  - seq: ' "$template_entrega" \
  || fail 'ENTREGA template item has no seq key'
grep -Fq '  - seq: 1' "$schema" || fail 'schema example item has no seq key'
grep -Fq '  - seq: 1' "$registro" || fail 'E8 example item has no seq key'

# O E1 tardio recebe o próximo seq e nunca é inserido no meio.
grep -Fq 'O E1 tardio recebe SEMPRE o próximo `seq` global' "$commits" \
  || fail 'the late E1 does not take the next global seq'
grep -Fq 'não a ordem numérica das tasks' "$commits" \
  || fail 'the late E1 may be inserted at the task position'

# A V11 não passa a depender da ordem.
grep -Fq '**A V11 não lê `seq`.**' "$prontidao" \
  || fail 'V11 no longer declares itself independent of seq'
grep -Fq 'exige `seq` em leitura histórica' "$prontidao" \
  || fail 'V11 may demand seq on historical reads'
grep -Fq 'quantidade de commits esperada para a task' "$prontidao" \
  || fail 'V11 does not rule out reading seq as a commit count'

# Um leitor de `commits` só no repositório inteiro.
grep -Fq 'sequencia-de-commits.sh' "$prova_sh" \
  || fail 'the V11 script does not use the shared commits reader'
if grep -Fq 'bloco "$arq" commits' "$prova_sh"; then
  fail 'the V11 script still carries its own commits parser'
fi

# A C4 não implementa a seção crítica, que é da C5.
for t in flock 'mkdir -p "$arq.lock' ownership; do
  if grep -Fq "$t" "$seq_sh"; then fail "the commits writer implements $t (that is C5)"; fi
done
grep -Fq 'não resolve corrida' "$schema" \
  || fail 'schema claims the order key solves concurrency'

# ---------------------------------------------------------------------------
# P0.2-C5 — o índice é do E1, e o E1 não é reentrante
# ---------------------------------------------------------------------------
trava_sh='.claude/skills/mergex/scripts/trava-do-e1.sh'
fecha_sh='.claude/skills/mergex/scripts/fechamento-do-e1.sh'
for f in "$trava_sh" "$fecha_sh"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# A seção crítica é contrato do E1, não detalhe de implementação.
grep -Fq '## A seção crítica do E1' "$commits" \
  || fail 'E1 has no critical-section contract'
grep -Fq '**O índice Git é recurso de DONO ÚNICO durante o E1.**' "$commits" \
  || fail 'E1 does not declare the index a single-owner resource'
grep -Fq 'o **fechamento** delas é serial' "$commits" \
  || fail 'E1 no longer serializes task closing'
grep -Fq 'Travar depois de montar o stage é não travar' "$commits" \
  || fail 'E1 allows acquiring the lock after staging'
grep -Fq 'A atribuição do `seq` acontece **dentro** da seção' "$commits" \
  || fail 'E1 lets seq be assigned outside the critical section'
grep -Fq '**Quem impede a corrida é o E1**' "$schema" \
  || fail 'schema does not place the race fix in the E1 critical section'

# O escopo é o índice DA WORKTREE. Trava global é proibida, e `.git` pode ser arquivo.
grep -Fq '<git-path do index>.mergex-e1.lock' "$commits" \
  || fail 'E1 does not say where the lock lives'
grep -Fq '**Nunca use `[ -d .git ]`.**' "$commits" \
  || fail 'E1 allows deciding the gitdir by testing a directory'
grep -Fq 'git rev-parse --git-path index' "$commits" \
  || fail 'E1 does not ask the versioner where the index is'
grep -Fq 'Trava no **diretório Git comum** é proibida' "$commits" \
  || fail 'E1 allows a repository-wide lock'
grep -Fq 'git rev-parse --git-path index' "$trava_sh" \
  || fail 'the E1 lock does not resolve the index through git'
if grep -Fq 'git-common-dir' "$trava_sh"; then
  fail 'the E1 lock reaches the common git dir'
fi
# Só o código conta: os comentários citam `.git/index` justamente para dizer
# que o caminho vem do versionador, e não de uma suposição sobre o layout.
# Só o CÓDIGO conta. Os comentários destes scripts citam `.git/index`, `flock`
# e `rm -rf` justamente para dizer que nenhum deles é usado — uma varredura que
# não descontasse comentário reprovaria a explicação junto com a violação.
codigo() { grep -v '^[[:space:]]*#' "$1"; }

if codigo "$trava_sh" | grep -Fq '.git'; then
  fail 'the E1 lock hardcodes the gitdir layout'
fi

# O mecanismo é `mkdir` atômico; `flock` quebraria Windows/macOS/Git Bash.
codigo "$trava_sh" | grep -Fq 'mkdir "$trava"' \
  || fail 'the E1 lock is not an atomic mkdir'
for f in "$trava_sh" "$fecha_sh"; do
  if codigo "$f" | grep -Fq 'flock'; then fail "$f depends on flock"; fi
done

# Nada de recuperação automática, e nada de remover a trava de outro E1.
grep -Fq '**Não remova a trava automaticamente.**' "$commits" \
  || fail 'E1 allows removing an orphan lock automatically'
grep -Fq 'decisão sobre uma trava órfã é humana' "$commits" \
  || fail 'E1 does not leave the orphan-lock call to a person'
if codigo "$trava_sh" | grep -Fq 'rm -rf'; then
  fail 'the E1 lock wipes a directory tree'
fi
grep -Fq 'nenhuma execução remove a trava de outra' "$commits" \
  || fail 'E1 lets one run release another run lock'

# Stage de entrada: PARA, e nada é desfeito.
grep -Fq '**Stage já não vazio antes de o E1 preparar qualquer coisa: PARE.**' "$commits" \
  || fail 'E1 no longer stops on a dirty index'
grep -Fq '**Deixe exatamente como estava**' "$commits" \
  || fail 'E1 no longer preserves a preexisting stage'
for g in 'git reset' 'git stash' 'git restore' 'git checkout' 'git clean'; do
  if codigo "$fecha_sh" | grep -Fq "$g"; then
    fail "the E1 critical section runs $g on state it does not own"
  fi
done

# Commit feito e registro não concluído: PARA, sem segundo commit.
grep -Fq '**NÃO crie um segundo commit.**' "$commits" \
  || fail 'E1 allows a second commit when the append fails'
for f in "$commits" "$fecha_sh"; do
  grep -Fq 'commit Git existe; registro E1 não foi concluído' "$f" \
    || fail "$f lost the commit-without-record outcome"
done
# Só chamada ao versionador: a mensagem do código 5 cita `--no-verify` para
# PROIBI-LO, e proibir não é usar.
for g in '--amend' '--no-verify' 'reset --hard'; do
  if codigo "$fecha_sh" | grep -F 'git ' | grep -Fq -- "$g"; then
    fail 'the E1 critical section rewrites or discards history'
  fi
done

# O escritor da lista não ganhou trava própria, e leitura nunca trava.
for t in mkdir flock; do
  if codigo "$seq_sh" | grep -Fq "$t"; then
    fail "the commits writer implements its own lock ($t)"
  fi
done
grep -Fq '**Leitura não trava nada**' "$commits" \
  || fail 'E1 turns reading the list into a locked operation'

# Um segundo escritor REAL não escapa da regra: os call sites executáveis de
# `--acrescentar` são a seção crítica, o próprio escritor e as bancadas.
escritores="$(grep -rlF --include='*.sh' --exclude-dir=.git -e '--acrescentar' . \
  | LC_ALL=C sort | tr '\n' ' ')"
esperado='./.claude/skills/mergex/scripts/fechamento-do-e1.sh ./.claude/skills/mergex/scripts/sequencia-de-commits.sh ./scripts/ci/mutacao-atencao-metodo.sh ./scripts/ci/mutacao-trava-e1.sh ./scripts/ci/test-sequencia-commits.sh ./scripts/ci/test-trava-e1.sh ./scripts/ci/validate-mergex-contract.sh '
[ "$escritores" = "$esperado" ] \
  || fail "unexpected executable writer of ENTREGA.commits: $escritores"
grep -Fq 'gravação nova do E1 só acontece sob a seção crítica' "$commits" \
  || fail 'E1 does not fence new writes behind the critical section'

# ---------------------------------------------------------------------------
# P0.2-C1 — arquivo de task irmã: ownership unitário no E1, união na V9
# ---------------------------------------------------------------------------
own_sh='.claude/skills/mergex/scripts/ownership-da-task.sh'
own_teste='scripts/ci/test-ownership-task.sh'
hook_task='.claude/hooks/mergex/commit-por-task.sh'
hooks_readme='.claude/hooks/README.md'

for f in "$own_sh" "$own_teste" "$hook_task" "$hooks_readme"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# As quatro situações existem, são exatamente quatro, e o reference nomeia
# cada uma delas com o mesmo termo do script. Prosa e script ficam amarrados:
# renomear de um lado só quebra aqui.
situacoes="$(bash "$own_sh" --situacoes | cut -d'|' -f1)"
[ "$(printf '%s\n' "$situacoes" | grep -c .)" = 4 ] \
  || fail 'ownership-da-task no longer declares exactly four situations'
for s in na_task_atual declarado_nao_mudou desvio arquivo_de_task_irma; do
  printf '%s\n' "$situacoes" | grep -Fxq "$s" \
    || fail "ownership-da-task dropped the situation: $s"
  grep -Fq "$s" "$commits" \
    || fail "E1 reference does not name the situation: $s"
done
[ "$(bash "$own_sh" --condicao)" = arquivo_de_task_irma ] \
  || fail 'the structured condition is no longer arquivo_de_task_irma'

# A mergex nomeia o que OBSERVA; a classe é da sprintx (DM-147).
if bash "$own_sh" --situacoes | grep -Fq 'defeito_de_plano'; then
  fail 'mergex emits the sprintx class defeito_de_plano instead of what it observes'
fi
# Só em comentário, explicando de quem é a classe: nunca em código que a emita.
if grep -v '^[[:space:]]*#' "$own_sh" | grep -Fq 'defeito_de_plano'; then
  fail 'the ownership script emits the sprintx class defeito_de_plano'
fi
grep -Fq 'defeito_de_plano' "$own_sh" \
  || fail 'the ownership script no longer says who owns the defeito_de_plano class'

# O E1 é unitário e diz que arquivo de task irmã NÃO é desvio.
grep -Fq 'O dono do arquivo é a task que está sendo fechada' "$commits" \
  || fail 'E1 no longer states unitary ownership'
grep -Fq 'ownership-da-task.sh --classificar' "$commits" \
  || fail 'E1 does not call the ownership script'
grep -Fq 'mudou e **só outra task** declara' "$commits" \
  || fail 'E1 dropped the fourth situation from the table'
grep -Fq 'não é desvio' "$commits" \
  || fail 'E1 no longer separates arquivo_de_task_irma from desvio'
grep -Fq 'commit parcial enganoso' "$commits" \
  || fail 'E1 no longer forbids the misleading partial commit'
for proibido in 'não** apague' 'não** faça `stash`' 'não** o mova para outra task'; do
  grep -Fq "$proibido" "$commits" \
    || fail "E1 dropped a forbidden recovery action: $proibido"
done

# A V9 continua com a UNIÃO, e o contrato proíbe convertê-la para unitário.
grep -Fq 'união dos `arquivos.cria` + `arquivos.altera` de todas as tasks' "$prontidao" \
  || fail 'V9 no longer compares against the union of all tasks'
grep -Fq '**Não converta a V9 para o conjunto unitário.**' "$prontidao" \
  || fail 'V9 lost the ban on switching to unitary scope'
grep -Fq 'passa na V9' "$prontidao" \
  || fail 'V9 no longer states that a sister-task file passes'

# O hook delega ao script (uma implementação só) e FALHA FECHADO: o bloco da
# condição não pode ser regido pelo modo do hook, senão em `aviso` — o padrão —
# ele deixaria passar o commit parcial que a condição existe para impedir.
grep -Fq 'ownership-da-task.sh' "$hook_task" \
  || fail 'commit-por-task does not delegate to the ownership script'
grep -Fq 'Task:[[:space:]]*T-[0-9]+\.[0-9]+' "$hook_task" \
  || fail 'commit-por-task no longer reads the declared current task from the Task: footer'
bloco_irma="$(awk '/^if \[ -n "\$TASK_ATUAL" \] && \[ -r "\$OWNERSHIP" \]; then$/, /^    exit 2$/' "$hook_task")"
[ -n "$bloco_irma" ] || fail 'commit-por-task lost the sister-task block'
if printf '%s\n' "$bloco_irma" | grep -Fq 'MODO'; then
  fail 'the sister-task block is gated by the hook mode: it must fail closed even in aviso'
fi
printf '%s\n' "$bloco_irma" | grep -Fxq '    exit 2' \
  || fail 'the sister-task block no longer blocks the commit'
grep -Fq 'falha fechada mesmo em aviso' "$hooks_readme" \
  || fail 'hooks README no longer documents the fail-closed exception'

# Nenhum outro hook foi promovido por oportunidade neste bloco.
grep -Fq '"commit-por-task": { "modo": "aviso" }' .expx/hooks.json \
  || fail 'commit-por-task was promoted out of aviso'
grep -Fq '"arquivo-fora-do-plano": { "modo": "aviso" }' .expx/hooks.json \
  || fail 'arquivo-fora-do-plano was promoted out of aviso'
grep -Fq '"pr-so-com-portao": { "modo": "aviso" }' .expx/hooks.json \
  || fail 'pr-so-com-portao was promoted out of aviso'

# As decisões ficaram registradas (renumeradas de DM-117..123 para DM-147..153
# na integração P0.2-C7-A: a faixa antiga colidia com a P0.2-C3).
for dm in DM-147 DM-148 DM-149 DM-150 DM-151 DM-152 DM-153; do
  grep -Fq "| $dm |" '.claude/skills/mergex/DECISOES-DA-SKILL.md' \
    || fail "decision log is missing $dm"
done

# ---------------------------------------------------------------------------
# P0.2-C7-A — compõe C1 (ownership) com C5 (seção crítica) no fechamento real
# ---------------------------------------------------------------------------
for f in "$fecha_sh" "$own_sh" "$hook_task"; do
  [ -f "$f" ] || fail "missing required file: $f"
done

# A ordem normativa dentro de `--fechar` e `--preparar`: resolver/lock, stage
# vazio, OWNERSHIP, e só então o primeiro `git add`. Checagem estrutural — não
# de execução — porque é exatamente a ordem das LINHAS que compõe os dois
# contratos sem ambiguidade.
bloco_fechar="$(awk '/^  --fechar\)$/,/^    exit 0 ;;$/' "$fecha_sh")"
[ -n "$bloco_fechar" ] || fail 'fechamento-do-e1 lost the --fechar block'
# A sequência de RÓTULOS, na ordem em que as linhas aparecem — nunca a
# ordenação das próprias linhas, que `grep -n` já devolve crescente por
# construção e não provaria nada.
ordem_fechar="$(printf '%s\n' "$bloco_fechar" | awk '
  /abre_secao /              { print "abre_secao"; next }
  /confere_stage_de_entrada/ { print "confere_stage_de_entrada"; next }
  /verifica_ownership /      { print "verifica_ownership"; next }
  /prepara "\$@"/            { print "prepara"; next }
  /verifica "\$VERIFICACAO"/ { print "verifica"; next }
  /conclui /                 { print "conclui"; next }
')"
esperado_fechar='abre_secao
confere_stage_de_entrada
verifica_ownership
prepara
verifica
conclui'
[ "$ordem_fechar" = "$esperado_fechar" ] \
  || fail "--fechar does not call the critical-section steps in the normative order: got [$ordem_fechar]"

bloco_preparar="$(awk '/^  --preparar\)$/,/^    exit 0 ;;$/' "$fecha_sh")"
[ -n "$bloco_preparar" ] || fail 'fechamento-do-e1 lost the --preparar block'
ordem_preparar="$(printf '%s\n' "$bloco_preparar" | awk '
  /abre_secao /              { print "abre_secao"; next }
  /confere_stage_de_entrada/ { print "confere_stage_de_entrada"; next }
  /verifica_ownership /      { print "verifica_ownership"; next }
  /prepara "\$@"/            { print "prepara"; next }
')"
esperado_preparar='abre_secao
confere_stage_de_entrada
verifica_ownership
prepara'
[ "$ordem_preparar" = "$esperado_preparar" ] \
  || fail "--preparar does not call the critical-section steps in the normative order: got [$ordem_preparar]"

# Ownership é chamado pelo fechamento real, mas degrada como o hook: ausente
# (instalação parcial), a seção crítica segue sem ele — ela não depende dele
# para o contrato central (trava, stage, commit, seq). A checagem obrigatória
# de dependência (`for f in ... exit 1`) cobre só trava e seq, nunca ownership.
grep -Fq 'OWNERSHIP_SH="$AQUI/ownership-da-task.sh"' "$fecha_sh" \
  || fail 'fechamento-do-e1 no longer wires the ownership script'
if grep -Fq 'for f in "$TRAVA_SH" "$SEQ_SH" "$OWNERSHIP_SH"' "$fecha_sh"; then
  fail 'fechamento-do-e1 hard-requires the ownership script at startup (breaks minimal/duble installs)'
fi
grep -Fq '  [ -f "$OWNERSHIP_SH" ] || return 0' "$fecha_sh" \
  || fail 'fechamento-do-e1 does not degrade gracefully when the ownership script is absent'

# `arquivo_de_task_irma`: nenhum `add` ocorreu, a trava é liberada, e a lista
# de commits não foi tocada por esse caminho.
grep -Fq 'para 8 ' "$fecha_sh" || fail 'fechamento-do-e1 lost the arquivo_de_task_irma exit code'
bloco_ownership="$(awk '/^verifica_ownership\(\) \{/,/^}$/' "$fecha_sh")"
[ -n "$bloco_ownership" ] || fail 'fechamento-do-e1 lost the verifica_ownership function'
if printf '%s\n' "$bloco_ownership" | grep -Fq 'git add -- '; then
  fail 'verifica_ownership stages something itself'
fi
if printf '%s\n' "$bloco_ownership" | grep -F 'sequencia-de-commits.sh' | grep -Fq -- '--acrescentar'; then
  fail 'verifica_ownership appends to ENTREGA.commits'
fi

# Ownership nunca "explica" um stage preexistente: DM-138 continua valendo, e
# a checagem do stage de entrada vem ANTES do ownership em todo call site.
if grep -Fq 'confere_stage_de_entrada' "$fecha_sh"; then
  linha_stage="$(grep -n '    confere_stage_de_entrada' "$fecha_sh" | head -1 | cut -d: -f1)"
  linha_own="$(grep -n '    verifica_ownership "\$TASK" "\$@"$' "$fecha_sh" | head -1 | cut -d: -f1)"
  [ -n "$linha_stage" ] && [ -n "$linha_own" ] && [ "$linha_stage" -lt "$linha_own" ] \
    || fail 'ownership runs before the entry-stage check somewhere in --fechar'
fi

# Uma implementação só de classificação: os call sites executáveis de
# `ownership-da-task.sh --classificar` são exatamente estes três — o
# fechamento real, o hook (defesa em profundidade) e a bancada dedicada.
own_chamadores="$(grep -rlF --include='*.sh' --exclude-dir=.git -e 'ownership-da-task.sh' . \
  | LC_ALL=C sort | tr '\n' ' ')"
own_esperado='./.claude/hooks/mergex/commit-por-task.sh ./.claude/skills/mergex/scripts/fechamento-do-e1.sh ./.claude/skills/mergex/scripts/ownership-da-task.sh ./scripts/ci/mutacao-atencao-metodo.sh ./scripts/ci/test-integracao-c7a.sh ./scripts/ci/test-ownership-task.sh ./scripts/ci/validate-mergex-contract.sh '
[ "$own_chamadores" = "$own_esperado" ] \
  || fail "unexpected caller of ownership-da-task.sh: $own_chamadores"

# O hook é defesa em profundidade, não uma segunda regra: ele classifica pelo
# MESMO script que o fechamento real, nunca por uma reimplementação própria.
if grep -v '^[[:space:]]*#' "$hook_task" | grep -Ev 'ownership-da-task\.sh|OWNERSHIP=' \
   | grep -Eq 'S_IRMA|arquivo_de_task_irma.*=.*\['; then
  fail 'commit-por-task reimplements the ownership classification instead of delegating'
fi

printf 'contract checks passed\n'
