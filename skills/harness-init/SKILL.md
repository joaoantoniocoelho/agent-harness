---
name: harness-init
description: Instala o agent-harness no repo atual (scripts/check, guardrails, CI, AGENTS.md, configs de lint), integrando com as ferramentas que o repo já usa. Use só quando o usuário invocar /harness-init explicitamente.
disable-model-invocation: true
---

# /harness-init

Instala o harness no repo atual sem transformar a adoção numa migração de stack. A parte mecânica fica no script `init.sh`; você cuida das decisões e da conversa com o usuário.

```bash
INIT=~/Developer/agent-harness/skills/harness-init/init.sh
```

Regras:
- **Preserve o que existe.** O package manager, o test runner, o lint, o error model e a arquitetura do repo prevalecem. Nunca troque ferramentas (ex: Vitest → Jest, pnpm → npm).
- **Nada é sobrescrito sem pergunta.** Cada conflito é decidido pelo usuário, um a um.
- **Nenhuma dependência é instalada sem o ok do usuário.**
- Não faça commit.

## Passos

1. **Detectar.** Rode `$INIT detect` e leia:
   - `stacks`:
     - vazio (projeto novo): pergunte a stack e crie o projeto mínimo com os defaults do harness (`npm init -y`, `uv init`; projeto Xcode é criado pelo usuário), depois rode `detect` de novo;
     - mais de uma: pergunte qual configurar (v0 = uma stack por repo);
   - as linhas `set KEY=...` são os comandos sugeridos para `scripts/check`, montados a partir do que o repo já usa;
   - as linhas `missing ...` são ferramentas ausentes;
   - `ci.install` é o comando de instalação para o CI.

   Confira as sugestões olhando `package.json`/`pyproject.toml`/projeto Xcode. Ajuste se precisar (ex: o script `lint` do repo já tem `--max-warnings`).

2. **Planejar.** Rode `$INIT plan --stack <stack>`. Status possíveis:
   - `NEW`: será criado;
   - `SAME` / `PRESENT` / `UPDATE`: nada a decidir;
   - `SKIP`: o repo já tem ferramenta equivalente; mantém a do repo;
   - `BLOCK`: o `AGENTS.md`/`CLAUDE.md` existente recebe só a seção do harness, entre marcadores; o resto fica intacto;
   - `CONFLICT`: o repo tem a própria versão. Para **cada** conflito, rode `$INIT diff --stack <stack> <target>`, mostre o diff ao usuário e pergunte se o harness deve sobrescrever (com backup) ou manter a versão do repo.

   Mostre o plano completo ao usuário antes de aplicar.

3. **Aplicar.**
   ```bash
   $INIT apply --stack <stack> \
     --set 'FORMAT_CMD=...' --set 'LINT_CMD=...' --set 'TYPECHECK_CMD=...' \
     --set 'TEST_CMD=...' --set 'BUILD_CMD=...' \
     [--set 'SCHEME=...' --set 'DESTINATION=...'] \
     --install-cmd '<ci.install>' \
     [--overwrite <target>]... [--skip <target>]...
   ```
   - Use `--skip` para o que o usuário não quiser, incluindo configs de lint do harness num repo que não vai adotar a ferramenta.
   - Comando vazio (`--set 'BUILD_CMD='`) pula o passo.

4. **Dependências.** Para cada linha `missing` que ainda se aplica (ex: o usuário aceitou a config de ESLint do harness), mostre o comando exato no package manager **do repo**. Exemplos:
   - `npm i -D ...`, `pnpm add -D ...`;
   - `uv add --dev ...`;
   - `brew install swiftlint`.

   Instale só com o ok do usuário. Depois registre:
   ```bash
   $INIT record-deps --pm <pm> <pkg>...
   ```
   Projeto TS novo com Jest: também crie o `jest.config` (`npx ts-jest config:init`).

5. **Preencher o `AGENTS.md` do repo.** Explore o código e preencha as seções (Projeto, Stack e comandos, Estrutura, Convenções deste repo), registrando as convenções existentes: modelo de erro, arquitetura, padrões de teste. Mantenha curto. Se o `AGENTS.md` já existia (BLOCK), não reescreva o conteúdo do usuário. Depois:
   ```bash
   $INIT rehash AGENTS.md   # só se o arquivo foi criado pelo harness (NEW)
   ```

6. **Verificar.** Rode `scripts/check`.
   - **Verde:** pronto.
   - **Vermelho:** não corrija nada agora. Escreva `docs/plans/harness-migration.md` (template: `~/Developer/agent-harness/templates/plan.md`) com:
     - os erros agrupados por regra e por arquivo;
     - a ordem de correção sugerida;
     - os riscos.

     A migração só ajusta o código à verificação; **nunca** troca a stack. Pare e peça aprovação.

7. **Resumo em PT-BR:**
   - o que foi criado, mantido, sobrescrito e pulado;
   - deps instaladas;
   - o resultado do check;
   - como desfazer: `~/Developer/agent-harness/uninstall.sh --repo .`.
