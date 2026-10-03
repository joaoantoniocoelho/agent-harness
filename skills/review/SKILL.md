---
name: review
description: Revisa as mudanças do working tree completo (modified, staged e untracked) contra o plano/issue e as regras do repo, e grava os findings em docs/plans/<slug>.review.md sem alterar código. Use só quando o usuário invocar /review explicitamente.
disable-model-invocation: true
context: fork
---

# /review

Você é um revisor independente. **Não altere código.** O único arquivo que você escreve é o relatório.

## 1. Coletar o working tree completo
Não use só `git diff`. Rode todos:
```bash
git status --porcelain=v1 --untracked-files=all   # modified, staged, untracked
git diff                                          # unstaged
git diff --cached                                 # staged
git diff "$(git merge-base origin/HEAD HEAD 2>/dev/null || git rev-parse HEAD)" --stat  # commits da branch, se houver
```
- Leia **inteiro** cada arquivo untracked relevante (código, testes, configs, migrations). Ignore artefatos de build, dependências e o que estiver no `.gitignore`.
- Para arquivos modificados, leia o contexto em volta do diff, não só as linhas alteradas.

## 2. Entender a tarefa
- **Fonte da tarefa:** `docs/plans/<slug>.md`, ou a issue (`gh issue view <n> --json title,body,labels,comments`). Se não estiver claro qual é a tarefa, use o plano mais recente em `docs/plans/` e diga isso no relatório.
- **Regras:** o `AGENTS.md` do repo (prevalece), `~/Developer/agent-harness/global/AGENTS.md` e `~/Developer/agent-harness/rules/<stack>.md`.

## 3. Revisar
- **Aderência:** cada critério de aceite foi atendido? Tem algo fora do escopo?
- **Corretude:** bugs, edge cases, tratamento de erro, concorrência, segurança (input externo, injeção, segredos).
- **Testes:** cobrem o comportamento novo e os casos de borda? São fracos (só happy path, mocks demais)?
- **Estilo que o lint não pega:** nomes, nesting, abstração prematura, comentários que explicam o quê em vez do porquê, funções sem coesão.
- **Convenções do repo:** o código segue o package manager, o error model e a arquitetura existentes?
- **Guardrails:**
  - supressões ou testes desligados sem motivo aprovado;
  - mudança de schema sem autorização em `.harness/allow-schema`;
  - statement destrutivo;
  - dependência nova não pedida.

## 4. Relatório
Grave `docs/plans/<slug>.review.md` (ou `docs/plans/issue-<n>.review.md`):

```markdown
# Review: <título>
- Data: <AAAA-MM-DD>
- Escopo revisado: <N arquivos: lista curta, incluindo untracked>

## Bloqueantes
- [ ] `path:line` — <problema> — <por que importa> — <sugestão de correção>

## Sugestões
- [ ] `path:line` — <melhoria>

## Resumo
<2-4 frases: está pronto? o que falta?>
```

Só é bloqueante o que causa bug, viola critério de aceite, guardrail ou convenção do repo, ou deixa comportamento sem teste. O resto é sugestão. Sem findings, diga isso explicitamente.

Responda ao usuário em PT-BR com o caminho do relatório e a contagem de bloqueantes e sugestões.
