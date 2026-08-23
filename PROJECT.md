---
repository_kind: distribution-template
project_status: template
project_id: "{{PROJECT_SLUG}}"
knowledge_contract_version: 1
knowledge_capture_mode: disabled
---

# {{PROJECT_NAME}}

Режим и статус проекта задаются frontmatter. URL-first или source-copy установка создает независимый Git repository из exact portable payload, а дополнительный GitHub Template setup сохраняет существующий Git repository пользователя. Все пути переводят копию в `generated-project + initialized + report-only` и не выполняют stage, commit или push. Canonical distribution clone не превращается в проект на месте. До перехода в `active` разрешены паспорт, planning, research, analysis runs и RAW по прямой просьбе, но не продуктовая реализация или canonical handoff без отдельной authority.

Допустимы только следующие пары:

| Состояние | Capture mode |
|---|---|
| `template-source + template` | `disabled` |
| `distribution-template + template` | `disabled` |
| `generated-project + initialized` | `report-only` |
| `generated-project + active` | `report-only` или `safe-local` |
| `generated-project + archived` | `disabled` |

`distribution-template` является временным производным режимом consumer branch и допускает только проверку или однократный setup. `active + report-only` может существовать без commit. Для `active + safe-local` обязателен доверенный Git `HEAD` с тем же generated `project_id` и `TEMPLATE-ORIGIN.md`; baseline commit создается только по отдельной прямой команде пользователя. Отсутствие подходящего HEAD блокирует automatic capture с результатом `blocked: missing-git-baseline`.

## Паспорт

- Slug: `{{PROJECT_SLUG}}`
- Описание: {{PROJECT_DESCRIPTION}}
- Владелец: `{{OWNER}}`
- Стадия: идея | исследование | proof of value | MVP | рост | поддержка | архив
- Канонический репозиторий: этот репозиторий
- Дата последней проверки паспорта: `YYYY-MM-DD`

## Проблема

Кто сталкивается с какой конкретной болью, в каком контексте и как часто.

## Проверяемая гипотеза

Если мы дадим [аудитории] [минимальный результат], то увидим [наблюдаемый сигнал], потому что [обоснование].

## Границы

Входит:

- Заполнить после инициализации.

Не входит:

- Заполнить после инициализации.

## Критерии успеха и провала

- Успех:
- Провал:
- Срок или объем проверки:
- Кто принимает финальное решение:

## Переход в active

Перед установкой `project_status: active` должны быть заполнены и не содержать исходных placeholders:

- реальный `project_id` и slug;
- описание и владелец;
- одна выбранная стадия;
- валидная дата последней проверки паспорта;
- проблема и проверяемая гипотеза;
- хотя бы по одному реальному пункту scope-in и scope-out;
- критерии успеха и провала;
- срок или объем проверки;
- лицо, принимающее решение.

Verifier блокирует `{{...}}`, `YYYY-MM-DD`, исходные placeholder-фразы, пустые обязательные пункты и несовместимую пару status/capture mode. Качество гипотезы остается agent-enforced. Выбранный технический стек на стадии исследования не требуется.

Explicit restore из `archived` переводит проект только в `initialized + report-only`. После restore паспорт и activation проверяются заново, а `safe-local` включается отдельным изменением после появления Git `HEAD`. Точечный delete чувствительных project data в archived следует отдельному контракту [`knowledge/INDEX.md`](knowledge/INDEX.md); автоматического delete нет.

## Реализация и эксплуатация после выбора стека

Этот раздел не входит в research-stage activation gate. Заполняй его при переходе к продуктовой реализации; до этого технический стек и эксплуатационные решения не фиксируются заранее.

- Стек:
- Проверки:
- Деплой и триггер:
- Откат:
- Мониторинг:

## Связи

- [Карта репозитория](INDEX.md)
- [Профиль владельца](ai-clone/INDEX.md)
- [Доменные промты](prompts/README.md)
- [Проработка идеи](idea/INDEX.md)
- [Канон продукта](product/INDEX.md)
- [Бизнес-контекст](business/INDEX.md)
- [Рабочие analysis runs](analysis/INDEX.md)
- [Канон бизнес-анализа](business/analysis/INDEX.md)
- [Канон системного анализа](docs/analysis/INDEX.md)
- [Техническая архитектура](docs/architecture/INDEX.md)
- [Карта кодовой базы](docs/codebase/INDEX.md)
- [Документация и решения](docs/INDEX.md)
- [Планы реализации](plans/README.md)
- [Политика знаний](knowledge/INDEX.md)
- [Методы исследования](mastery/researcher/INDEX.md)
- [Методы аналитика](mastery/analyst/INDEX.md)
- [Project-local Mastery](mastery/local/INDEX.md)
- [Исследовательские запуски](research/INDEX.md)
