---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Read-only review

```text
Прочитай AGENTS.md, PROJECT.md и релевантные indexes. Выполни только review или
diagnose: проверь фактический код, тесты, diff и канон, ранжируй findings по риску,
дай точные file refs и укажи пробелы evidence. Не меняй файлы и не создавай plan.

Если пользователь попросит исправить найденное или изменение окажется значимым,
остановись и предложи feature-bugfix-delivery.md или plan-and-deliver.md с
plan_policy: required.
```
