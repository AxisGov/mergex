/**
 * mergex — plugin do OpenCode.
 *
 * Paridade com os hooks do Claude Code, no mecanismo que o OpenCode oferece.
 * Os hooks são os MESMOS scripts em `.claude/hooks/` — este arquivo é só a
 * ponte. Duplicar a lógica criaria duas fontes divergindo com o tempo, que é o
 * pior defeito possível para uma skill cujo contrato é o produto.
 *
 * DIFERENÇAS DE MECANISMO (verificadas na documentação e no fonte do OpenCode,
 * não presumidas):
 *
 *  - Bloqueio: no Claude Code é `exit 2`; aqui é LANÇAR uma exceção em
 *    `tool.execute.before`. O `trigger` do OpenCode não tem try/catch em volta
 *    dos handlers, então a rejeição aborta a chamada da ferramenta.
 *
 *  - Aviso: o Claude Code lê o stderr do hook. O OpenCode não tem "permite mas
 *    avisa" no `before` — ou passa em silêncio, ou lança. Por isso o aviso é
 *    represado aqui e anexado ao resultado da ferramenta em
 *    `tool.execute.after`, que é o único caminho até o modelo.
 *    Os hooks emitem o aviso em JSON no stdout justamente para isto.
 *
 *  - Nomes de ferramenta são minúsculos no OpenCode (write/edit/bash).
 *
 *  - Em `tool.execute.before` os argumentos vêm em `output.args`; em
 *    `tool.execute.after`, em `input.args`. Ler só um dos dois deixaria metade
 *    dos hooks sem o comando.
 */

import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { join, dirname } from "node:path"

const TEMPO_LIMITE = 10_000

type Carga = {
  cwd: string
  tool_name: string
  tool_input: Record<string, unknown>
}

/** Sobe até achar `.git` — mesma regra do `base.sh` e do SKILL.md. */
function raizDoRepo(inicio: string): string {
  let d = inicio
  while (d !== "/" && d !== "") {
    if (existsSync(join(d, ".git"))) return d
    const pai = dirname(d)
    if (pai === d) break
    d = pai
  }
  return inicio
}

/**
 * Roda um hook e devolve o que ele decidiu.
 *   exit 2                            => bloqueia (motivo no stderr)
 *   stdout com additionalContext      => avisa
 * Qualquer outra coisa => passa. Falha aberta: hook que não roda não trava
 * trabalho — o de segurança já falhou fechado dentro do próprio script.
 */
function rodaHook(
  raiz: string,
  caminhoRelativo: string,
  carga: Carga,
): { bloqueia?: string; avisa?: string } {
  const hook = join(raiz, ".claude", "hooks", caminhoRelativo)
  if (!existsSync(hook)) return {}

  let r: ReturnType<typeof spawnSync>
  try {
    r = spawnSync("bash", [hook], {
      input: JSON.stringify(carga),
      encoding: "utf8",
      timeout: TEMPO_LIMITE,
      cwd: raiz,
    })
  } catch {
    return {}
  }

  if (r.status === 2) {
    return {
      bloqueia:
        (r.stderr || "").trim() || `bloqueado por ${caminhoRelativo}`,
    }
  }

  const saida = (r.stdout || "").trim()
  if (saida.startsWith("{")) {
    try {
      const j = JSON.parse(saida)
      const ctx = j?.hookSpecificOutput?.additionalContext
      if (typeof ctx === "string" && ctx) return { avisa: ctx }
    } catch {
      /* falha aberta: stdout que não é JSON válido não trava nada */
    }
  }
  return {}
}

/** Traduz o nome da ferramenta do OpenCode para o do Claude Code. */
function nomeCanonico(tool: string): string {
  switch (tool) {
    case "write":
      return "Write"
    case "edit":
      return "Edit"
    case "patch":
      return "MultiEdit"
    case "bash":
      return "Bash"
    default:
      return tool
  }
}

/** Os hooks de escrita e os de comando, na ordem em que rodam. */
const NA_ESCRITA = ["comum/sem-segredo.sh"]
const NO_COMANDO = [
  "comum/sem-segredo.sh",
  "mergex/git-perigoso.sh",
  "comum/branch-limpa.sh",
  "mergex/commit-por-task.sh",
  "mergex/arquivo-fora-do-plano.sh",
  "mergex/pr-so-com-portao.sh",
]

export default async ({ directory }: { directory?: string }) => {
  const raiz = raizDoRepo(directory || process.cwd())

  /** Avisos represados no `before`, para anexar ao resultado no `after`. */
  const avisosPendentes = new Map<string, string[]>()

  const monta = (input: any, output: any): Carga => {
    const args = {
      ...((output?.args ?? input?.args ?? {}) as Record<string, unknown>),
    }
    // O OpenCode usa camelCase; os hooks esperam o payload do Claude Code.
    if (args.filePath && !args.file_path) args.file_path = args.filePath
    if (args.newString && !args.new_string) args.new_string = args.newString
    return {
      cwd: raiz,
      tool_name: nomeCanonico(input.tool),
      tool_input: args,
    }
  }

  return {
    "tool.execute.before": async (input: any, output: any) => {
      const tool = input.tool
      let hooks: string[] = []
      if (tool === "write" || tool === "edit" || tool === "patch") {
        hooks = NA_ESCRITA
      } else if (tool === "bash") {
        hooks = NO_COMANDO
      }
      if (!hooks.length) return

      const carga = monta(input, output)
      const avisos: string[] = []

      for (const h of hooks) {
        const r = rodaHook(raiz, h, carga)
        // Lançar é o único jeito de barrar no OpenCode.
        if (r.bloqueia) throw new Error(r.bloqueia)
        if (r.avisa) avisos.push(r.avisa)
      }

      if (avisos.length) avisosPendentes.set(input.callID, avisos)
    },

    "tool.execute.after": async (input: any, output: any) => {
      const avisos = avisosPendentes.get(input.callID) ?? []
      avisosPendentes.delete(input.callID)
      if (!avisos.length) return

      // Único canal até o modelo no OpenCode: anexar ao resultado.
      // O prefixo deixa explícito que é o hook falando, não a ferramenta —
      // sem ele o modelo pode ler o aviso como saída do comando.
      if (typeof output?.output === "string") {
        output.output +=
          "\n\n[mergex/hooks — aviso, a ação NÃO foi bloqueada]\n" +
          avisos.map((a) => `- ${a}`).join("\n")
      }
    },
  }
}
