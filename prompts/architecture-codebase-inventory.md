---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Инвентаризация архитектуры и кодовой базы

```text
Прочитай AGENTS.md, PROJECT.md, INDEX.md, docs/architecture/INDEX.md и
docs/codebase/INDEX.md. Выполни read-only осмотр репозитория: entrypoints,
компоненты, данные, интеграции, trust boundaries, deployment, команды run/build/
test, conventions и технический долг. Отдели наблюдаемое от гипотез.

Сначала покажи карту и source refs. Ничего не меняй без отдельной прямой команды.
Если обнаружена значимая реализация или исправление, предложи перейти к prompt с
plan_policy: required.
```
