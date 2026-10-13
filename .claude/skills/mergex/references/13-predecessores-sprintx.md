# Predecessores SprintX e retomada da V9

`00-PREDECESSORES.md` declara documentos Superpowers efetivamente consumidos antes do nascimento formal do planejamento SprintX. A V9 só aceita cada caminho quando `predecessores-sprintx.sh` prova, pela árvore de um SHA, a ancestralidade estrita e a identidade do blob. O catálogo de método isenta apenas o manifesto; nunca os caminhos que ele declara.

## Recuperação terminal

Uma entrega pode sair do E8 bloqueado somente quando o registro commitado contém exatamente `estado: bloqueado`, `portao: bloqueado`, `falhas_portao: [v9]`, `causa: arquivo_fora_do_plano`, nenhuma publicação/PR e nenhuma reconciliação pendente. Os `desvios` precisam ser exatamente os predecessores agora provados, e a V9 precisa retornar `resultado=ok`.

O fluxo tem dois commits de método, nenhum deles task e nenhum deles consumidor de `seq`:

1. `predecessores`: persiste somente `00-PREDECESSORES.md`;
2. `retomar-v9-predecessores`: persiste somente `ENTREGA.md`, reaberto com `portao`, `portao_sha`, `causa` em `null` e listas vazias.

Use primeiro `--verificar`. `--aplicar` repete as provas sob a trava, grava atomicamente e termina com `proxima=E2`. A retomada não emite `PRONTO`, não chama E3 e não autoriza publicação. Recomece pela barreira `persistir-metodo.sh --verificar --checkpoint pre-e2` e execute integralmente V1–V11.

Não existe `--force`. Árvore ou stage sujos, disco divergente de HEAD, schema inconclusivo, desvios adicionais, V9 ainda vermelha ou repetição depois da reabertura são recusados.
