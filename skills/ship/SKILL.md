---
name: ship
description: Envia a tarefa atual como PR draft. Roda scripts/check, cria a branch se estiver na main, commita só os arquivos da tarefa (Conventional Commits), faz push e abre o PR com o template do harness. Use só quando o usuário invocar /ship explicitamente.
disable-model-invocation: true
---

# /ship

Toda a parte de git é feita por um script determinístico. Você só escreve os textos (mensagem de commit, título e corpo do PR) e conversa com o usuário.

```bash
SHIP=~/Developer/agent-harness/skills/ship/ship.sh
H=$(git rev-parse --absolute-git-dir)/harness   # textos temporários ficam aqui, fora do working tree
```

Regras:
- Nunca rode `git add -A`, `git add .`, `git reset`, `git checkout -- <file>`, `git stash` ou `git commit` por conta própria. Só o `ship.sh` mexe no git.
- Se o `ship.sh` sair com **código 3**, ele precisa de confirmação: mostre a lista de arquivos ao usuário, pergunte quais são da tarefa, grave a lista confirmada (um path por linha) em `$H/files-<slug>.txt` e rode de novo com `--files-from`.
- Se o check falhar, pare e reporte. Não corrija nada no modo ship sem o usuário pedir.

## Passos

1. **Identificar a tarefa.**
   - **Slug:** `issue-<n>`, ou o slug do plano em `docs/plans/<slug>.md`.
   - **Tipo** Conventional Commit: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`.

2. **Conferir os arquivos.** Rode:
   ```bash
   $SHIP files <slug>
   ```
   O comando mostra o que é da tarefa (`+`), o que é preexistente e fica intocado (`=`) e o que é ambíguo (`!`). Exit 3 → siga a regra de confirmação acima.

3. **Escrever os textos.**
   - `$H/commit-<slug>.txt`: mensagem Conventional Commit em inglês, com assunto ≤ 72 caracteres (`feat(billing): add retry with backoff`), linha em branco e corpo curto com o porquê.
   - `$H/pr-<slug>.md`: corpo do PR em **PT-BR**, seguindo `~/Developer/agent-harness/templates/pull_request.md`. Preencha com o plano ou a issue, o diff e o Log de decisões:
     - **O que** / **Por que**;
     - **Como testar / evidência**, com a saída do `scripts/check`;
     - **Decisões e trade-offs**;
     - **Riscos e pontos de atenção para review**.

     Se houver `docs/plans/<slug>.review.md`, mencione os findings resolvidos e os pendentes. O plano não é commitado; o resumo dele vai no PR.
   - **Título do PR:** em PT-BR ou igual ao assunto do commit, curto.

4. **Enviar.**
   ```bash
   $SHIP run <slug> --type <type> --title "<título>" \
     --message-file "$H/commit-<slug>.txt" --body-file "$H/pr-<slug>.md" \
     [--issue <n>] [--files-from "$H/files-<slug>.txt"]
   ```
   O script, nesta ordem:
   1. classifica os arquivos;
   2. roda `scripts/check` (aborta se falhar ou se o check gerar arquivos novos);
   3. cria `<type>/<slug>` se estiver na branch padrão;
   4. commita só os arquivos da tarefa;
   5. faz push;
   6. abre o PR **draft**, com `Closes #<n>` se for issue.

5. **Responder em PT-BR** com o link do PR, a branch, os arquivos commitados e os preexistentes que ficaram de fora.
