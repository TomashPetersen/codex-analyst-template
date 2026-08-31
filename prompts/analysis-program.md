---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---

# Программа из нескольких аналитических запусков

```text
Программа: <ПРОГРАММА>. Task key: <TASK_KEY>.

До предметной записи прочитай AGENTS.md, PROJECT.md, INDEX.md, plans/README.md,
plans/INDEX.md и analysis/CONTRACT.md. Вызови scripts/new-plan.ps1 с этим task_key,
покажи plan ID и путь, не создавай второй plan. При PLAN_ACTION=existing сначала
полностью прочитай plan и Resume checkpoint, сохрани выбор метода либо осознанно
измени его после gate. Только при PLAN_ACTION=created выбери intent через
mastery/INTENTS.json, проверь mastery/local/INDEX.md и заполни «Метод выполнения»
одним применимым local method либо none. Переведи его в in-progress через scripts/set-plan-status.ps1
и начинай только после зеленого plan gate.

Раздели программу на bounded runs с независимыми решениями и критериями
остановки. В каждом run установи task_ref: plan:<PLAN_ID>, используй не более
трех read-only специалистов, затем Lead synthesis, analysis_reviewer и
analysis_red_team. После каждой фазы обновляй Resume checkpoint.

Canonical handoff, архитектурное изменение, реализация и выпуск требуют точной
authority и остаются внутри этого plan. Commit, push, tag и deploy не выполняй
без отдельной команды.
```
