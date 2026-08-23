---
name: project-delivery
description: Выполняет значимые функции, bugfix, архитектурные изменения, миграции и выпуски через обязательный tracked Plan v2, фазовые checkpoints, проверки и knowledge closeout. Использовать для реализации и продолжения работы, когда prompt имеет plan_policy required или existing. Не использовать для read-only review, простого ответа или research run.
---

# Project Delivery

Этот skill обеспечивает repository-level resumability. Источник текущего состояния - plan в `plans/`, а не чат, память модели или retrospective. Контракт и команды находятся в [`plans/README.md`](../../../plans/README.md).

## Preflight до предметной записи

1. Прочитай `AGENTS.md`, `PROJECT.md`, корневой `INDEX.md`, `plans/README.md` и `plans/INDEX.md`.
2. Зафиксируй read-only Git snapshot по knowledge closeout contract. Не меняй index.
3. Определи `plan_policy` активного prompt.
4. Для `required` выбери стабильный lowercase `task_key` и вызови `scripts/new-plan.ps1`. Команда обязана вернуть ровно один existing или created plan.
5. Для `existing` используй только переданный `<PLAN_REF>`. Не ищи замену и не создавай новый plan.
6. Полностью прочитай plan, проверь schema и покажи пользователю точные `plan_id` и `plan_ref`.
7. Переведи `planned` или возобновляемый `blocked` plan в `in-progress` через `scripts/set-plan-status.ps1`. Только после зеленого plan gate начинай предметные изменения.

Если одинаковый `task_key` имеет несколько active plans, точный plan не найден или pre-task snapshot отсутствует, остановись с безопасным `blocked` outcome.

## Возобновление

Перед продолжением перечитай `Resume checkpoint` и вызови `scripts/assert-plan-resume.ps1 -PlanRef <PLAN_REF>`. Необъяснимое расхождение означает `blocked: plan-worktree-drift`. Не перезаписывай чужие изменения и не выводи состояние только из истории чата.

Работай только по `current_phase`. Перед фазой поставь `[WIP]`. После фазы:

- закрой ее checklist и поставь `[x]`;
- запиши фактический deliverable и проверки;
- выбери следующую фазу или очисти `current_phase` перед complete;
- обнови `updated_at`, рабочие paths, следующий точный шаг и `Resume checkpoint` через `scripts/update-plan-checkpoint.ps1`;
- пересобери и проверь `plans/INDEX.md`.

Обновляй checkpoint также перед остановкой, compaction, сменой задачи и финальным ответом. При нехватке authority сохрани текущую фазу, `blocked_reason` и способ разблокировки.

## Реализация и проверка

Планируй фазы по наблюдаемым результатам. Сверяй acceptance criteria с фактическим diff и тестами. Код и тесты остаются источником истины о поведении; `docs/architecture/` и `docs/codebase/` обновляются только по подтвержденным изменениям. Accepted ADR фиксирует выбор, plan - ход работы.

Нельзя объявлять готовность при stale plan, незакрытых criteria, `[WIP]`, отсутствующих проверках или result refs.

## Closeout

Перед `complete` примени `knowledge-curator` в plan-closeout mode:

1. Сравни plan, pre-task snapshot, фактический diff, тесты, ADR и канон.
2. Не копируй полный plan, diff, код, тесты, логи, временные детали, секреты или PII.
3. Допускай максимум один candidate устойчивого результата и один method candidate с двумя независимыми learning sources либо прямой коррекцией владельца.
4. Automatic ready допустим только в `active + safe-local`; promotion требует отдельного approval.
5. Заполни `result_refs`, `affected_canon`, `closeout_status`, `knowledge_outcome`, итог и финальный checkpoint.
6. Запусти plan, knowledge, graph, privacy, structure и stack-specific gates.
7. Переведи plan в terminal `complete` через `scripts/set-plan-status.ps1`.

В финальном ответе всегда верни status и кликабельный абсолютный путь plan. Commit, tag, push и deploy выполняются только по отдельной прямой команде.
