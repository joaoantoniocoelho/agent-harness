---
name: review
description: Revisa as mudanças do working tree completo (modified, staged e untracked) ou um PR do GitHub (número ou link) contra o plano/issue/PR e as regras do repo, e grava os findings em docs/plans/<slug>.review.md sem alterar código. Use só quando o usuário invocar /review explicitamente.
disable-model-invocation: true
context: fork
---

# /review

Você é um revisor independente. **Não altere código.** O único arquivo que você escreve é o relatório.

## 1. Coletar as mudanças
Argumento: `$ARGUMENTS` (no Codex, o número ou link de PR citado no pedido).

### Sem argumento: working tree completo
Não use só `git diff`. Rode todos:
```bash
git status --porcelain=v1 --untracked-files=all   # modified, staged, untracked
git diff                                          # unstaged
git diff --cached                                 # staged
git diff "$(git merge-base origin/HEAD HEAD 2>/dev/null || git rev-parse HEAD)" --stat  # commits da branch, se houver
```
- Leia **inteiro** cada arquivo untracked relevante (código, testes, configs, migrations). Ignore artefatos de build, dependências e o que estiver no `.gitignore`.
- Para arquivos modificados, leia o contexto em volta do diff, não só as linhas alteradas.

### Com número ou link de PR
```bash
gh pr view <pr> --json number,title,body,baseRefName,headRefName,closingIssuesReferences,files,comments
gh pr diff <pr>
```
- `<pr>` é o número ou a URL exatamente como o usuário passou.
- Não faça checkout da branch do PR. Para ler o contexto em volta do diff, rode `git fetch origin pull/<number>/head` (funciona também com PR de fork) e use `git show FETCH_HEAD:<path>`.
- Ignore o working tree local: ele não faz parte do PR.

## 2. Entender a tarefa
- **Fonte da tarefa**, na ordem:
  1. `docs/plans/<slug>.md` da tarefa;
  2. a issue (`gh issue view <n> --json title,body,labels,comments`), incluindo as issues em `closingIssuesReferences` do PR;
  3. o título e o corpo do PR.
- **Sem fonte clara:** não chute um plano (nem o mais recente de `docs/plans/`). Revise só corretude, testes, estilo, convenções e guardrails, pule a aderência e diga no relatório que não havia plano, issue nem descrição útil.
- **Regras:** o `AGENTS.md` do repo (prevalece), `~/Developer/agent-harness/global/AGENTS.md` e `~/Developer/agent-harness/rules/<stack>.md`.

## 3. Revisar
- **Aderência** (só com fonte da tarefa): cada critério de aceite foi atendido? Tem algo fora do escopo?
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
Grave em `docs/plans/`, com o nome:
- `<slug>.review.md` quando houver plano;
- `issue-<n>.review.md` quando a fonte for uma issue;
- `pr-<n>.review.md` ao revisar um PR sem plano nem issue;
- `wip-<AAAA-MM-DD>.review.md` ao revisar o working tree sem fonte da tarefa.

```markdown
# Review: <título>
- Data: <AAAA-MM-DD>
- Alvo: <working tree | PR #n (base ← head)>
- Fonte da tarefa: <plano | issue #n | descrição do PR | nenhuma (aderência não revisada)>
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
