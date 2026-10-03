# Python

> Em repo existente, as convenções e configs do repo prevalecem. Os **defaults** abaixo valem para projetos novos.

## Defaults de projeto novo
- **uv** para dependências e venv (`uv add`, `uv add --dev`, `uv run`).
- **ruff** para lint e format, **pyright** em modo `strict`, **pytest**.
- Configs base: `~/Developer/agent-harness/templates/lint/python/`.

## Tipos
- Type hints em tudo que é público. Sem `Any` implícito; use `object`/`Protocol`/`TypeVar` quando o tipo for genérico.
- Sem `cast()` nem `# type: ignore`, salvo boundary com lib sem tipos, isolado e comentado.
- Dados: `@dataclass(frozen=True)` ou modelos imutáveis; valide input externo na borda.

## Erros
- Exceptions específicas do domínio (nunca `except Exception: pass`). Capture só o que você sabe tratar.
- Em repo que já usa outro modelo de erro, siga o repo.

## Estilo
- Early return; pouco nesting; funções puras quando possível; sem estado global mutável.
- Organização por feature (`src/<pkg>/<feature>/`).
- f-strings; `pathlib` em vez de `os.path`.

## Testes
- `tests/` espelhando a estrutura de `src/`, arquivos `test_*.py`.
- Fixtures do pytest para setup; `parametrize` para variações.
