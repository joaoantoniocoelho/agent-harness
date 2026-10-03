# TypeScript / Node.js / Next.js

> Em repo existente, as convenções e configs do repo prevalecem. Os **defaults** abaixo valem para projetos novos.

## Defaults de projeto novo
- Package manager: **npm**. Lint: **ESLint** (typescript-eslint `strictTypeChecked`). Format: **Prettier**. Testes: **Jest** (`ts-jest`).
- `tsconfig` com `strict: true`.
- Configs base: `~/Developer/agent-harness/templates/lint/node/`.

## Tipos
- Sem `any`. Use `unknown` e faça narrowing.
- Sem type assertions (`as Foo`, `<Foo>x`). `as const` é permitido. Se uma assertion for inevitável (ex: boundary com lib mal tipada), isole numa função pequena com comentário explicando o porquê.
- Sem non-null assertion (`x!`).
- Valide input externo (HTTP, env, arquivos, `JSON.parse`) na borda, antes de confiar no tipo.

## Erros
- Erros **esperados** (validação, not found, falha de rede tratável) como valores: `Result<T, E>` (`{ ok: true, value } | { ok: false, error }`), com `E` discriminado.
- `throw` só para bugs e invariantes quebradas.
- Em repo que já usa exceptions como modelo de erro, siga o repo.

## Estilo
- Early return; `max-depth` 3; sem `else` depois de `return`.
- Sem mutação de parâmetros; `const` por padrão; prefira `map`/`filter`/`reduce` e spreads a mutação in-place.
- Named exports. Um módulo = uma responsabilidade.
- Nomes descritivos; nada de abreviações obscuras.

## Testes
- Arquivo de teste ao lado do código (`foo.test.ts`) ou em `__tests__/`, seguindo o repo.
- Teste comportamento público, não detalhes de implementação. Sem mocks de módulos internos quando der para usar uma fake simples.

## Next.js
- App Router. **Server Components por padrão**; `'use client'` só quando o componente precisa de estado, efeitos, event handlers ou APIs do browser, e o mais baixo possível na árvore.
- Busca de dados no servidor (Server Components / route handlers), não em `useEffect`.
- Organização por feature: `src/features/<feature>/{components,server,lib,...}`. `app/` contém só rotas e composição.
