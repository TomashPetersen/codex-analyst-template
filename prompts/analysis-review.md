---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---

# Независимая проверка аналитики

```text
Проверь <RUN_REF_ИЛИ_ARTIFACT_REF> без записи. Прочитай AGENTS.md,
analysis/CONTRACT.md и owner indexes. Сначала привлеки analysis_reviewer для
полноты, корректности, provenance, traceability и authority, затем
analysis_red_team для контрпримеров, скрытых допущений и нежелательных
сценариев. Не сообщай им ожидаемый итог.

Верни findings по убыванию серьезности с evidence refs, confidence,
limitations, conflicts и unknowns. Не изменяй run, канон, plan, candidate или
Git state. Исправление findings является отдельной write-задачей.
```
