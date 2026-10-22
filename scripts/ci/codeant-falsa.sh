#!/usr/bin/env bash
# shellcheck shell=bash
#
# A CLI do CodeAnt falsa dos testes da V12 (biblioteca, carregada com `.`).
#
# O `revisar` do nucleo do expx so roda a CLI que acha no PATH, dentro do pacote npm
# `codeant-cli` homologado e com o manifesto do perfil (contrato `expx-revisao` v2, "A
# CLI"). Para gravar evidencias de verdade nos testes, sem rede e sem credencial, esta
# biblioteca monta um pacote `codeant-cli` 0.5.14 falso no layout do npm em POSIX e troca,
# na copia do nucleo montada no projeto temporario (nunca na copia versionada em
# `scripts/ci/fixtures/candidatos/`), so o `manifesto` e o `package_json` do perfil 0.5.14
# pelos da falsa. Nenhuma variavel de ambiente troca o perfil, e nenhum teste escreve
# evidencia a mao: quem grava e o `revisar`.
#
#   instala_codeant_falsa <prefixo> <resposta.json> [<stderr>]
#     <prefixo>/lib/node_modules/codeant-cli/ (package.json e src/index.js) e o link
#     <prefixo>/bin/codeant -> ../lib/node_modules/codeant-cli/src/index.js. O bin imprime
#     a resposta; com `"reviewed_files": "__include__"` em `meta`, devolve o `--include`
#     recebido e `total_changed` = revisados + pulados. Com <stderr>, escreve esse texto no
#     stderr (falha de lote). Chamar de novo troca so a resposta e o stderr: o bin e o
#     package.json nao mudam, e o manifesto continua valendo.
#   nucleo_com_falsa <nucleo> <prefixo>
#     reescreve <nucleo>/perfis/codeant-cli-0.5.14.json com o manifesto (sha256 de cada
#     arquivo do pacote) e o package_json da falsa (jq).
#
# No Git Bash do Windows nao ha link simbolico confiavel (o `ln -s` copia), e o nucleo nao
# acharia o pacote: os casos que precisam da falsa saem com `passa` e o CI em Linux os cobre.
#
# Bash 3.2: nada de mapfile nem arrays associativos.

codeant_falsa_suportada() {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 1 ;; esac
  return 0
}

_falsa_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

instala_codeant_falsa() {
  local prefixo="$1" resposta="$2" erro="${3:-}" pacote
  pacote="$prefixo/lib/node_modules/codeant-cli"
  mkdir -p "$pacote/src" "$prefixo/bin" || return 1
  printf '%s\n' '{"name":"codeant-cli","version":"0.5.14","bin":{"codeant":"src/index.js"}}' > "$pacote/package.json"
  cat > "$pacote/src/index.js" <<'JS'
#!/usr/bin/env node
// CLI do CodeAnt falsa dos testes da mergex (scripts/ci/codeant-falsa.sh)
const fs = require("fs");
const path = require("path");
const args = process.argv.slice(2);
const i = args.indexOf("--include");
const include = i >= 0 && args[i + 1] !== undefined ? args[i + 1].split(",") : [];
const resposta = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "resposta.json"), "utf8"));
if (resposta.meta && resposta.meta.reviewed_files === "__include__") {
  resposta.meta.reviewed_files = include;
  resposta.meta.total_changed = include.length + (resposta.meta.skipped || []).length;
}
const erro = path.join(__dirname, "..", "stderr.txt");
if (fs.existsSync(erro)) process.stderr.write(fs.readFileSync(erro));
process.stdout.write(JSON.stringify(resposta));
JS
  chmod +x "$pacote/src/index.js" || return 1
  cp "$resposta" "$pacote/resposta.json" || return 1
  rm -f "$pacote/stderr.txt"
  [ -z "$erro" ] || printf '%s\n' "$erro" > "$pacote/stderr.txt"
  ln -sfn ../lib/node_modules/codeant-cli/src/index.js "$prefixo/bin/codeant"
}

nucleo_com_falsa() {
  local nucleo="$1" pacote="$2/lib/node_modules/codeant-cli" perfil tmp
  perfil="$nucleo/perfis/codeant-cli-0.5.14.json"
  tmp="$perfil.tmp"
  jq --arg pj "$(_falsa_sha256 "$pacote/package.json")" --arg ix "$(_falsa_sha256 "$pacote/src/index.js")" \
     --argjson pkg "$(cat "$pacote/package.json")" \
     '.manifesto = {"package.json": $pj, "src/index.js": $ix} | .package_json = $pkg' "$perfil" > "$tmp" \
    && mv "$tmp" "$perfil"
}
