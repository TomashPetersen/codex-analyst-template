---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: existing
---

# Продолжение работы по плану

```text
Продолжи работу по <PLAN_REF>. Полностью прочитай AGENTS.md, plans/README.md,
plans/INDEX.md, сам plan и Resume checkpoint. Проверь Plan v2 schema и сравни
Git state с сохраненным checkpoint. При расхождении остановись с
blocked: plan-worktree-drift и опиши безопасный способ сверки.

Возобнови только current_phase. Перед предметной записью обнови status при
необходимости. После каждой фазы сохрани checklist, evidence, проверки, точные
paths, следующий шаг, timestamp и индекс. Не создавай новый plan и не объявляй
готовность при stale checkpoint.
```
