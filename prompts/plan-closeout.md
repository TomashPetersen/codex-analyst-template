---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: existing
---

# Завершение плана и knowledge closeout

```text
Заверши <PLAN_REF>. Полностью прочитай plan, его Resume checkpoint,
knowledge/INDEX.md и фактический Git diff относительно pre-task snapshot. Сверь
acceptance criteria, фазы, тесты, ADR и затронутый канон. При drift или
незавершенной работе не ставь complete, а сохрани точный blocked checkpoint.

Выдели только устойчивую delta. Допустимо максимум два candidates: один результат
проекта и один повторяемый метод с evidence из двух независимых завершенных задач
либо прямой коррекцией владельца. Не копируй полный plan, diff, код, тесты, логи,
секреты или PII. Automatic ready допустим только в active + safe-local, promotion
всегда отдельный. Заполни result_refs, closeout_status, knowledge_outcome и
финальный Resume checkpoint, проверь индекс и только затем переведи plan в
complete через scripts/set-plan-status.ps1.
```
