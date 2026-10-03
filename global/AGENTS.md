# Instruções globais para agents (agent-harness)

Fonte: `~/Developer/agent-harness/global/AGENTS.md`. Vale para Claude Code e Codex em qualquer repo.

## 1. Precedência
1. Pedido explícito do usuário na conversa.
2. `AGENTS.md`/`CLAUDE.md` do repo, convenções e configs existentes (package manager, test runner, lint, error model, arquitetura).
3. Este arquivo e `~/Developer/agent-harness/rules/<stack>.md`.

Os defaults de stack do harness valem **só para projetos novos**. Em repo existente, siga o que já existe: não troque Vitest por Jest, pnpm por npm, exceptions por Result etc. só para adequar ao harness.

## 2. De onde vem a tarefa
- **GitHub Issue com label `agent-ready`** (`gh issue view <n> --json title,body,labels,comments`): a issue já é o plano aprovado. Explore o código e implemente direto, sem criar `docs/plans/` e sem pedir aprovação. Slug: `issue-<n>`.
- **Issue sem `agent-ready`:** use a issue como input e siga o fluxo de plano + aprovação.
- **Pedido ad hoc, tarefa não trivial:** escreva `docs/plans/<slug>.md` seguindo `~/Developer/agent-harness/templates/plan.md` e **pare até o usuário aprovar**. Tarefas triviais (typo, rename, ajuste de uma linha) dispensam plano.

Antes da primeira edição da tarefa, rode:
```bash
~/Developer/agent-harness/skills/ship/ship.sh baseline <slug>
```
O comando registra as mudanças que já estavam no working tree, para o `/ship` nunca commitar o que não é da tarefa.

## 3. Quando perguntar
- **Issue `agent-ready`:** pergunte só em decisão material que a issue não autoriza: aumento de escopo, dependência nova, mudança de API pública ou schema não prevista, operação destrutiva, conflito com os critérios de aceite.
- **Demais fluxos:** ambiguidade pequena → decida, registre no "Log de decisões" do plano (ou no resumo final) e siga. Escopo, API pública, schema ou dependência nova → pergunte.
- **Schema/migrations:**
  - exigida/autorizada por issue `agent-ready` → pode implementar; registre em `.harness/allow-schema` (`<path ou glob> :: issue #<n> (agent-ready)`);
  - não prevista pela tarefa → peça aprovação; depois de aprovada, registre `:: aprovado pelo usuário em <AAAA-MM-DD>`;
  - **sempre** peça aprovação explícita antes de executar migration destrutiva, alterar dados reais ou aplicar migration em ambiente remoto/produção.
- **Nunca sem perguntar:** desabilitar ou pular testes/lint (`eslint-disable`, `@ts-ignore`, `# type: ignore`, `# noqa`, `swiftlint:disable`, `.skip`, `.only`...).

## 4. Implementação
- Toda mudança de comportamento vem com testes (não precisa ser test-first).
- Siga as guidelines de estilo abaixo e as regras da stack:
  - TypeScript/Node/Next.js: `~/Developer/agent-harness/rules/typescript.md`
  - Python: `~/Developer/agent-harness/rules/python.md`
  - Swift: `~/Developer/agent-harness/rules/swift.md`

## 5. Verificação (definição de pronto)
- Rode `scripts/check` na raiz do repo até ficar verde. Se falhar, corrija a causa e rode de novo.
- Nunca contorne o check (suprimir regra, pular teste, editar o script). `harness-allow: <motivo>` e `.harness-no-tests` só com motivo aprovado pelo usuário ou autorizado pela issue.
- Se o repo não tiver `scripts/check`, rode o equivalente do repo (lint, typecheck, testes, build) e sugira `/harness-init`.
- Finalize com um resumo em **PT-BR**:
  - o que mudou;
  - decisões tomadas;
  - saída do `scripts/check` (resumida);
  - onde o usuário deve olhar com mais atenção.

## 6. Git e modos de execução
- **Modo padrão:** nenhuma operação de escrita no git (sem branch, commit, push, stash, reset ou checkout de arquivos). As mudanças ficam no working tree para revisão.
- **Modo ship:** só quando o usuário invocar `/ship` (Claude) ou a skill `ship` (Codex).
- **Review:** `/review` é manual. Se existir `docs/plans/<slug>.review.md` e o usuário pedir para corrigir os findings, trate os bloqueantes e rode `scripts/check` de novo.

## 7. Guidelines de estilo
- Código, identificadores e comentários em inglês. Planos, PRs, reviews e resumos em PT-BR.
- Comentários só para explicar o **porquê** de decisões não óbvias, nunca o quê.
- Early return e guard clauses; pouco nesting; sem `else` depois de `return`.
- Funções coesas e arquivos com responsabilidade clara. Sem limite numérico de linhas: não faça refactor artificial só para encolher código.
- Preferir funções puras e dados imutáveis; composição em vez de herança.
- Sem abstração prematura nem "future-proofing"; duplicar um pouco é melhor que a abstração errada.
- Organização por feature (vertical slices) em projetos novos; em repo existente, siga a estrutura atual.
- Commits em Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`...).
