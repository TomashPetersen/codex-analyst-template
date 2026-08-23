---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---

# Программа из нескольких аналитических запусков

```text
Программа: <ПРОГРАММА>. Task key: <TASK_KEY>.

До предметной записи прочитай AGENTS.md, PROJECT.md, INDEX.md, plans/README.md,
plans/INDEX.md и analysis/CONTRACT.md. Найди active plan с этим task_key. Если
его нет, создай его через scripts/new-plan.ps1. Покажи plan ID и путь. Не создавай второй
plan для той же программы. Переведи его в in-progress через
scripts/set-plan-status.ps1 и начинай только после зеленого plan gate.

Раздели программу на bounded runs с независимыми решениями и критериями
остановки. В каждом run установи task_ref: plan:<PLAN_ID>, используй не более
трех read-only специалистов, затем Lead synthesis, analysis_reviewer и
analysis_red_team. После каждой фазы обновляй Resume checkpoint.

Canonical handoff, архитектурное изменение, реализация и выпуск требуют точной
authority и остаются внутри этого plan. Commit, push, tag и deploy не выполняй
без отдельной команды.
```
