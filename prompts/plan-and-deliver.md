---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---

# Планирование и выполнение значимого изменения

```text
Задача: <ЗАДАЧА>. Task key: <TASK_KEY>.

До любых предметных изменений прочитай AGENTS.md, PROJECT.md, INDEX.md,
plans/README.md и plans/INDEX.md. Вызови scripts/new-plan.ps1 с этим task_key,
покажи plan ID и путь, не создавай второй plan. При PLAN_ACTION=existing сначала
полностью прочитай plan и Resume checkpoint, сохрани выбор метода либо осознанно
измени его после gate. Только при PLAN_ACTION=created выбери intent через
mastery/INTENTS.json, проверь mastery/local/INDEX.md и заполни «Метод выполнения»
максимум одним active, непросроченным и применимым local method либо none.
Переведи plan в in-progress
через scripts/set-plan-status.ps1 и только после зеленой проверки plan contract
начинай первую фазу. После каждой фазы обновляй plan и Resume checkpoint.

Запиши проблему, границы, non-goals, измеримые acceptance criteria, риски,
rollback, фазы и проверки. Работай только по current_phase. Сверяй фактический
diff, тесты и решения с plan. Перед остановкой сохрани точный следующий шаг и
пересобери plans/INDEX.md. Перед complete выполни plan closeout. Не выполняй
commit, push или deploy без отдельной команды.
```
