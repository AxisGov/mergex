#!/usr/bin/env bash
# mergex: pre-push gerenciado
#
# Chamador do pre-push gerenciado pela MergeX (DM-184), instalado pelo E0
# (`ativacao-pre-push.sh --instalar`) no diretório de hooks efetivo do Git
# (`git rev-parse --git-path hooks`). Só chama o validador de push da skill
# (`portao-push.sh`), com os argumentos e a entrada padrão que o Git entregou,
# e propaga exatamente o código de saída dele. Não tem regra própria.
#
# Não edite este arquivo: a reversão (`ativacao-pre-push.sh --reverter`) o
# reconhece pelo marcador da segunda linha e o remove. Para combinar a MergeX
# com um pre-push próprio, componha à mão: references/12-barreira-de-push.md.
#
# Este é o modelo versionado; a instalação troca __MERGEX_PORTAO_PUSH__ pelo
# caminho do validador e dá o bit de execução à cópia instalada.
MERGEX_RAIZ="$(git rev-parse --show-toplevel)" || exit 1
MERGEX_PORTAO_PUSH=__MERGEX_PORTAO_PUSH__
exec bash "$MERGEX_PORTAO_PUSH" --pre-push "$@"
