# Premissas pendentes do BuildX

### PR-15 — Formatação decimal só garantida na faixa segura

- origem: f2_autonoma
- decisao: A parte numerica do codigo e a representacao decimal padrao do numero (String) com zeros a esquerda ate 6 digitos; o contrato de formato so e garantido para numeros ate Number.MAX_SAFE_INTEGER, sem tratamento especial acima disso
- justificativa: PR-06 nao impoe teto e ja registra MAX_SAFE_INTEGER como invalidador; PR-08 e PR-09 definem largura minima e nao truncamento sem falar de notacao; String(1e21) devolve 1e+21, entao prometer so digitos acima da faixa segura exigiria regra nova que nenhum arquivo declara
- o_que_invalida: a sequencia precisar gerar codigos para numeros acima de Number.MAX_SAFE_INTEGER, ou o consumidor exigir apenas digitos em qualquer faixa
- status: pendente_promocao
