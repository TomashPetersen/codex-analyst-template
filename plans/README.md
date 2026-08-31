# Планы реализации

Plan - tracked Markdown source of truth для значимой реализации. Чат, память Codex и retrospective не заменяют plan. После перезапуска сначала открой [`INDEX.md`](INDEX.md), затем полностью прочитай найденный plan и его `Resume checkpoint`.

## Когда plan обязателен

Prompt с `plan_policy: required` обязан до первой предметной записи создать или продолжить один active plan. Prompt с `plan_policy: existing` принимает точный `<PLAN_REF>`. Для одинакового `task_key` не может существовать два active plans.

```powershell
pwsh -NoProfile -File ./scripts/new-plan.ps1 `
  -TaskKey <TASK_KEY> `
  -Title "<TITLE>" `
  -PromptRef prompts/plan-and-deliver.md

pwsh -NoProfile -File ./scripts/set-plan-status.ps1 `
  -PlanRef plans/YYYY-MM-DD-<task-key>.md `
  -Status in-progress
```

`new-plan.ps1` безопасно возвращает существующий active plan вместо дубля. При `PLAN_ACTION=existing` сначала прочитай plan и `Resume checkpoint`, сохрани его `Метод выполнения` либо осознанно измени выбор после gate. Только при `PLAN_ACTION=created` выбери intent из `mastery/INTENTS.json`, открой `mastery/local/INDEX.md` и заполни `Метод выполнения`: `none` либо максимум один зарегистрированный method с applied candidate, active status, непросроченным review и совпадающим intent. Файлы не перемещаются между status-папками.

Новый `planned` plan может временно содержать `pending + none + none`. Для `in-progress` intent уже закрыт; ID и ref одновременно равны `none` либо образуют одну пару. Если preflight ломается до выбора intent, переход в `blocked` может сохранить exact `pending + none + none`, но общий verifier остается красным до закрытия выбора. `complete` хранит исторический выбор и не становится невалидным из-за последующей deprecation или наступления `review_due`.

Переход в `blocked` сохраняет синтаксически закрытый выбор без требования live-доступности catalog, registry, method или candidate. Общий verifier продолжает показывать повреждение, а возврат в `in-progress` и переход в `complete` требуют полного method gate; для выбранного method он переиспользует canonical knowledge verifier.

## Lifecycle

```text
planned -> in-progress -> complete
   |            |
   -> blocked <-+
        |
        -> in-progress
```

- `complete` терминален. Follow-up получает новый `plan_id` и ссылку на завершенный plan.
- Перед фазой укажи `current_phase` и маркер `[WIP]`.
- После каждой фазы обнови checklist, evidence, проверки, `updated_at` и `Resume checkpoint`.
- Перед остановкой, compaction или финальным ответом снова сохрани checkpoint и пересобери индекс.
- При расхождении Git state и checkpoint остановись с `blocked: plan-worktree-drift`.
- При нехватке authority переведи plan в `blocked`, сохрани текущую фазу, причину и следующий шаг.

## Индекс и проверка

```powershell
pwsh -NoProfile -File ./scripts/update-plan-index.ps1 -Mode Write
pwsh -NoProfile -File ./scripts/update-plan-index.ps1 -Mode Check
pwsh -NoProfile -File ./scripts/verify-plans.ps1
pwsh -NoProfile -File ./scripts/assert-plan-resume.ps1 `
  -PlanRef plans/YYYY-MM-DD-<task-key>.md
```

[`INDEX.md`](INDEX.md) является детерминированным индексом. Его нельзя редактировать вручную. Полная схема нового plan находится в [`TEMPLATE.md`](TEMPLATE.md). Старые планы v1 допустимы только как явно source-only история шаблона.

После фазы обновляй checkpoint через `scripts/update-plan-checkpoint.ps1`. Команда сохраняет current phase, completed work, checks, точные paths, следующий шаг, blockers, UTC timestamp и детерминированный Git checkpoint. На старте новой сессии `assert-plan-resume.ps1` сравнивает его с текущим worktree и возвращает `blocked: plan-worktree-drift` при расхождении.

## Завершение

До `complete` обязательны закрытые criteria и фазы, заполненные проверки и итог, существующие `result_refs`, финальный checkpoint и knowledge closeout. Plan closeout переносит только устойчивый результат и, при достаточном evidence, повторяемый метод. Полный plan, diff, код, тесты, логи, секреты и персональные данные в knowledge не копируются. Promotion всегда требует отдельного одобрения.
