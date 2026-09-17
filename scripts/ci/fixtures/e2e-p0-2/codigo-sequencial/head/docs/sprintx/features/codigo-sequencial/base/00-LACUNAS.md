# Lacunas

Uma linha por lacuna, com onde se procurou. Levantadas pelo agente `investigador` na F1.

## proximo-numero

- Formatação em string de números acima de `MAX_SAFE_INTEGER` ou a partir de `1e21` (notação exponencial de `String()`): NÃO DOCUMENTADO (procurado nos 7 arquivos; `FECHAMENTO.md:36` só registra perda de precisão em `valor + 1`)
- Conteúdo de D-09, D-10 e PR-06 além da citação curta: NÃO DOCUMENTADO nos arquivos lidos (`FECHAMENTO.md:16`, `:36`; `test/proximo-numero.test.js:29`)

## modulo-principal-e-harness

- Nome do arquivo e do teste da FT-02 (ex.: `src/proximo-codigo.js`): NÃO DOCUMENTADO (só o padrão análogo do D-04, `FECHAMENTO.md:32`, e `docs/stack/CONVENCOES.md:25-26`)
- Se `proximoCodigo` deve ser reexportado por `src/index.js`: NÃO DOCUMENTADO (procurado em `src/index.js` e `docs/stack/CONVENCOES.md`)
- Numeração das tasks da FT-02: NÃO DOCUMENTADO (`test/proximo-numero.test.js` só cobre as tasks da FT-01)
- Versão mínima do Node.js: NÃO DOCUMENTADO (sem `engines` em `package.json`; `docs/stack/CONVENCOES.md:19`)
- Regra de descoberta de arquivos do `node --test`: NÃO DOCUMENTADO nos arquivos lidos (`package.json:7`)

## convencoes

- Função `proximoCodigo`: NÃO DOCUMENTADO no código (procurado em `src/` e `test/`; só no briefing)
- Prefixo `SEQ-`: NÃO DOCUMENTADO (procurado nos 7 arquivos)
- Preenchimento com zeros à esquerda: NÃO DOCUMENTADO (nenhuma formatação de string em `src/` ou `test/`)
- Largura mínima de 6 dígitos: NÃO DOCUMENTADO (procurado em `src/`, `test/`, `docs/stack/CONVENCOES.md`, `FECHAMENTO.md`)
- Não truncar números com mais de 6 dígitos: NÃO DOCUMENTADO (procurado nos 7 arquivos)
- Mensagem de erro própria de `proximoCodigo`: NÃO DOCUMENTADO (`docs/stack/CONVENCOES.md:47-49` manda propagar; `FECHAMENTO.md:36` diz que mensagem não é contrato)
