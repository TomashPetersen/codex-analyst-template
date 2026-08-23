---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---

# Планирование и выполнение значимого изменения

```text
Задача: <ЗАДАЧА>. Task key: <TASK_KEY>.

До любых предметных изменений прочитай AGENTS.md, PROJECT.md, INDEX.md,
plans/README.md и plans/INDEX.md. Найди active plan с этим task_key. Если его нет,
создай через scripts/new-plan.ps1. Покажи plan ID и путь. Не создавай второй plan
для той же задачи. Переведи plan в in-progress через scripts/set-plan-status.ps1
и только после зеленой проверки plan contract начинай первую фазу. После каждой
фазы обновляй plan и Resume checkpoint.

Запиши проблему, границы, non-goals, измеримые acceptance criteria, риски,
rollback, фазы и проверки. Работай только по current_phase. Сверяй фактический
diff, тесты и решения с plan. Перед остановкой сохрани точный следующий шаг и
пересобери plans/INDEX.md. Перед complete выполни plan closeout. Не выполняй
commit, push или deploy без отдельной команды.
```
