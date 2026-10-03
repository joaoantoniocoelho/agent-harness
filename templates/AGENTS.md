# AGENTS.md

<!-- Preenchido pelo /harness-init. Mantenha curto: só o que um agent precisa saber para trabalhar aqui. -->

## Projeto
<!-- O que é, para quem, estado atual. -->

## Stack e comandos
<!-- Linguagem, framework, package manager, test runner. -->
- Instalar deps: `...`
- Rodar local: `...`
- Testes: `...`

## Estrutura
<!-- Onde fica cada coisa; padrão de organização (por feature, por camada...). -->

## Convenções deste repo
<!-- Modelo de erro, padrões de API, nomes, o que evitar. Estas convenções prevalecem sobre os defaults globais. -->

<!-- harness:start -->
## Agent harness
Este repo usa o [agent-harness](https://github.com/joaoantoniocoelho/agent-harness).
- **Verificação:** `scripts/check` é a definição de pronto (guardrails, teste junto da mudança, format, lint, typecheck, testes, build). O CI roda o mesmo script.
- **Planos:** `docs/plans/<slug>.md` (fora do git). Issues com label `agent-ready` já são o plano aprovado.
- **Precedência:** as convenções deste arquivo e as configs do repo prevalecem sobre os defaults globais do harness.
- **Schema/migrations:** autorizações registradas em `.harness/allow-schema`; statements destrutivos sempre exigem aprovação explícita.
<!-- harness:end -->
