# Доменные промты

Короткие copy-paste entrypoints для заполнения ключевых зон проекта. Перед использованием замени значения в `<УГЛОВЫХ_СКОБКАХ>` и удали неприменимые пункты.

| Задача | Prompt | Plan policy | Владелец результата |
|---|---|---|---|
| Провести рабочее интервью с владельцем | [`ai-clone-interview.md`](ai-clone-interview.md) | `none` | [`ai-clone/`](../ai-clone/INDEX.md) |
| Заполнить паспорт и activation gate | [`project-passport.md`](project-passport.md) | `none` | [`PROJECT.md`](../PROJECT.md) |
| Оформить и ограничить идею | [`idea-validation.md`](idea-validation.md) | `none` | [`idea/`](../idea/INDEX.md) |
| Собрать знания о продукте | [`product-interview.md`](product-interview.md) | `none` | [`product/`](../product/INDEX.md) |
| Описать бизнес и его архитектуру | [`business-architecture-interview.md`](business-architecture-interview.md) | `none` | [`business/`](../business/INDEX.md) |
| Зафиксировать фактические architecture/codebase | [`architecture-codebase-inventory.md`](architecture-codebase-inventory.md) | `none` | [`docs/`](../docs/INDEX.md) |
| Запустить доказательное исследование | [`research-run.md`](research-run.md) | `none` | [`research/`](../research/INDEX.md) |
| Выполнить один bounded analysis run | [`analysis-run.md`](analysis-run.md) | `none` | [`analysis/runs/`](../analysis/INDEX.md) |
| Выполнить программу из нескольких runs | [`analysis-program.md`](analysis-program.md) | `required` | plan и [`analysis/runs/`](../analysis/INDEX.md) |
| Независимо проверить анализ | [`analysis-review.md`](analysis-review.md) | `none` | отчет без записи |
| Передать подтвержденный анализ в канон | [`analysis-handoff.md`](analysis-handoff.md) | `existing` | `<PLAN_REF>` и точный owner artifact |
| Провести read-only review | [`read-only-review.md`](read-only-review.md) | `none` | отчет без записи |
| Создать Local Mastery candidate | [`create-mastery.md`](create-mastery.md) | `none` | [`knowledge/`](../knowledge/INDEX.md) |
| Выполнить разрешенное promotion | [`knowledge-promotion.md`](knowledge-promotion.md) | `none` | указанный owner artifact |
| Спланировать и выполнить значимое изменение | [`plan-and-deliver.md`](plan-and-deliver.md) | `required` | [`plans/`](../plans/README.md) и код |
| Реализовать feature или bugfix | [`feature-bugfix-delivery.md`](feature-bugfix-delivery.md) | `required` | [`plans/`](../plans/README.md) и код |
| Выполнить архитектурное изменение | [`architecture-change.md`](architecture-change.md) | `required` | plan, ADR и реализация |
| Продолжить существующий plan | [`continue-plan.md`](continue-plan.md) | `existing` | `<PLAN_REF>` |
| Закрыть существующий plan | [`plan-closeout.md`](plan-closeout.md) | `existing` | `<PLAN_REF>` и knowledge outcome |

## Общие правила

- Сначала прочитать `AGENTS.md`, `PROJECT.md` и индекс выбранного домена.
- Проверить режим репозитория до записи.
- Не придумывать факты, evidence, согласие, цены, метрики или решения владельца.
- Разделять `FACT`, `OBSERVATION`, `HYPOTHESIS`, `OPINION` и `QUOTE`.
- Перед записью назвать точные target paths; после записи показать diff и проверки.
- Для `required` сначала создать или найти ровно один tracked Plan v2; для `existing` полностью прочитать переданный `<PLAN_REF>`.
- Prompt не является разрешением на commit, push, external write, promotion или canonical handoff.

Начать весь проект одним маршрутом можно через [корневой README](../README.md#первый-рабочий-цикл).
