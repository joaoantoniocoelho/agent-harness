# agent-harness

Harness mínimo para trabalhar com agents de código (**Claude Code** e **Codex**) de forma confiável. Os agents planejam e implementam sozinhos, e você revisa. Tudo que pode ser verificado por script é verificado por script.

- **Instruções globais únicas** para os dois agents: workflow, quando perguntar, estilo, guardrails.
- **`scripts/check` por repo**: guardrails, teste junto da mudança, format, lint, typecheck, testes e build. Os agents, o `/ship` e o CI rodam o mesmo script.
- **Skills:** `/harness-init` (setup do repo), `/review` (revisão manual) e `/ship` (PR draft).
- **Integra com o que o repo já usa.** Os defaults de stack valem só para projetos novos.

## O que é garantido por código e o que é instrução

| Garantido por script | Depende de instrução (`AGENTS.md`) |
|---|---|
| Estilo via configs de lint (sem `any`/`as`, nesting, strict) | Escrever o plano e esperar aprovação |
| `guardrails.sh`: supressões, testes desligados, schema sem autorização, SQL destrutivo | Rodar `scripts/check` antes de dizer "pronto" no modo padrão |
| `tests-touched.sh`: mudança em código sem mudança em teste | Política de quando perguntar |
| `ship.sh`: PR só com check verde e só com os arquivos da tarefa | |
| CI: o mesmo `scripts/check` em todo PR | |

## Instalação (uma vez por máquina)

```bash
git clone https://github.com/joaoantoniocoelho/agent-harness ~/Developer/agent-harness
~/Developer/agent-harness/install.sh
```

O `install.sh` cria os symlinks abaixo. Se já existir algo nesses caminhos, vai para `.backup/`.

| Link | Aponta para |
|---|---|
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | `global/AGENTS.md` |
| `~/.claude/skills/<skill>`, `~/.codex/skills/<skill>` | `skills/<skill>` |

Requisitos: `git`, `jq`, `gh` (para o `/ship`) e as ferramentas da stack de cada repo.

O caminho `~/Developer/agent-harness` é referenciado nas instruções. Se clonar em outro lugar, ajuste-o em `global/AGENTS.md` e nos `SKILL.md`.

## Instalação num repo

Na raiz do repo, abra o agent e rode **`/harness-init`** (no Codex: `$harness-init` ou pelo menu `/skills`). A skill:

1. Detecta a stack e as ferramentas existentes (package manager, test runner, lint) e monta o `scripts/check` com os comandos do próprio repo.
2. Mostra o plano: cada arquivo como novo, conflito ou pulado (quando o repo já tem uma ferramenta equivalente).
3. Para cada conflito, mostra o diff e pergunta se sobrescreve (com backup).
4. Lista as dependências que faltam e só instala com o seu ok.
5. Preenche o `AGENTS.md` do repo com as convenções existentes.
6. Roda `scripts/check`. Se o legado não passar, gera `docs/plans/harness-migration.md` para você aprovar.

Arquivos que o `/harness-init` cria no repo:
- `scripts/check`, `scripts/guardrails.sh`, `scripts/tests-touched.sh`;
- `.github/workflows/check.yml`;
- `AGENTS.md` e `CLAUDE.md`, ou só uma seção entre `<!-- harness:start -->`/`<!-- harness:end -->` se já existirem;
- configs de lint do harness, só onde não existir equivalente (no Node, `eslint.config.mjs` vem com um `tsconfig.eslint.json` que cobre testes e `*.config.ts`);
- `.harness/manifest`, usado pelo uninstall;
- as linhas `docs/plans/` e `.harness/backup/` no `.gitignore`.

## Fluxo do dia a dia

### 1. Tarefa
| Origem | O que acontece |
|---|---|
| Issue com label **`agent-ready`** ("implementa a issue #42") | A issue é o plano aprovado: o agent implementa direto. Só pergunta em decisão material que a issue não autoriza. |
| Issue sem `agent-ready` | O agent usa a issue como input, escreve o plano e espera sua aprovação. |
| Pedido ad hoc não trivial | O agent escreve `docs/plans/<slug>.md` e espera sua aprovação. |

### 2. Implementação
- Antes da primeira edição, o agent registra um baseline do working tree (`ship.sh baseline <slug>`).
- Implementa com testes.
- Roda `scripts/check` até ficar verde.
- Entrega um resumo em PT-BR. Tudo fica **sem commit** para você revisar.

### 3. Review (opcional, manual)
- `/review` revisa o working tree completo (modified, staged e untracked) e grava `docs/plans/<slug>.review.md` com os findings bloqueantes e as sugestões.
- No Claude, roda com contexto isolado. No Codex, use uma sessão nova.
- Para corrigir, diga na sessão de implementação: "corrige os findings do review".

### 4. Modos de execução
| Modo | Como ativar | Git |
|---|---|---|
| **Padrão** | Só pedir a tarefa | Nenhuma operação de escrita |
| **Ship** | `/ship` (Claude) · `$ship` (Codex) | branch → commit → push → PR draft |

O `/ship` executa o `ship.sh`, que:
1. separa os arquivos da tarefa das mudanças preexistentes, usando o baseline;
2. roda `scripts/check` (aborta se falhar ou se o check gerar arquivos);
3. cria a branch `<type>/<slug>` se você estiver na branch padrão;
4. commita **só** os arquivos da tarefa, sem `git add -A` e sem tocar no que já estava sujo ou staged;
5. faz push;
6. abre o PR **draft** com o template: O que / Por que · Como testar · Decisões · Riscos.

Se não der para separar os arquivos com segurança, o script aborta e pergunta.

### 5. CI
O workflow `check` roda `scripts/check` em todo PR. É o gate final.

## Schema e migrations
- Mudança de schema exigida/autorizada por uma issue `agent-ready`: pode ser implementada. O agent registra em `.harness/allow-schema`:
  ```
  db/migrations/** :: issue #42 (agent-ready)
  ```
- Mudança de schema não prevista: exige aprovação (`:: aprovado pelo usuário em AAAA-MM-DD`).
- SQL destrutivo (`DROP TABLE/COLUMN`, `TRUNCATE`, `DELETE FROM`, `ALTER ... DROP`): bloqueado mesmo com autorização. Só passa com aprovação explícita e `harness-allow: <motivo>` na linha.
- Executar migrations, alterar dados reais ou aplicar em remoto/produção: sempre com aprovação explícita (regra de instrução, não aparece no diff).

Só contam as autorizações adicionadas na mudança atual: entradas antigas não autorizam mudanças futuras.

## Escapes (sempre visíveis no diff)
| Escape | Uso |
|---|---|
| `harness-allow: <motivo>` na linha | Supressão de lint/tipo, teste desligado ou SQL destrutivo aprovado |
| `.harness-no-tests` (com justificativa) | Mudança em código sem teste, aprovada. Só vale se o arquivo mudar no mesmo diff |
| `.harness/allow-schema` | Autorização de mudança de schema |

## Desinstalação

```bash
~/Developer/agent-harness/uninstall.sh                 # da máquina
~/Developer/agent-harness/uninstall.sh --repo <path>   # de um repo
```
- Os dois mostram o plano e pedem confirmação. `--dry-run` só mostra; `--yes` confirma sem perguntar.
- **Máquina:** remove só os symlinks que apontam para o harness e restaura os backups.
- **Repo:** usa `.harness/manifest` para:
  - apagar os arquivos criados (pergunta se você os editou; com `--yes`, mantém);
  - restaurar os sobrescritos a partir de `.harness/backup/`;
  - remover só a seção do harness do `AGENTS.md`/`CLAUDE.md`;
  - limpar o `.gitignore`.

  Não remove dependências (mostra o comando), não apaga `docs/plans/` e não faz commit.

## Estrutura

```
global/AGENTS.md            instruções globais (Claude + Codex)
rules/<stack>.md            guidelines e defaults por stack
bin/                        guardrails.sh, tests-touched.sh (copiados para scripts/ do repo)
skills/harness-init/        SKILL.md + init.sh
skills/review/              SKILL.md
skills/ship/                SKILL.md + ship.sh
templates/                  AGENTS.md, CLAUDE.md, plan.md, pull_request.md, check/, lint/, ci/
install.sh / uninstall.sh
```

## Fora do v0
Stop hook rodando o check automaticamente, pre-commit, skills `/plan` e `/implement`, suporte a Copilot, monorepos com múltiplas stacks.
