---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---

# Архитектурное изменение, миграция или выпуск

```text
Задача: <ЗАДАЧА>. Task key: <TASK_KEY>.

До любых предметных изменений прочитай AGENTS.md, PROJECT.md, INDEX.md,
plans/README.md и plans/INDEX.md. Найди active plan с этим task_key. Если его нет,
создай через scripts/new-plan.ps1. Покажи plan ID и путь. Не создавай второй plan
для той же задачи. Переведи plan в in-progress через scripts/set-plan-status.ps1
и только после зеленой проверки plan contract начинай первую фазу. После каждой
фазы обновляй plan и Resume checkpoint.

Зафиксируй границы системы, варианты, совместимость, data migration, trust
boundaries, rollout и rollback. Accepted ADR создавай только для реального выбора.
Реализуй по фазам, проверь фактический diff и обнови docs/architecture и
docs/codebase только по подтвержденным фактам. Не выполняй commit, tag, push или
deploy без отдельной команды.
```
