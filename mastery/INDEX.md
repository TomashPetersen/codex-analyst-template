# Project Mastery

Project-local mastery хранит только проверенные, переносимые методы, необходимые самому проекту. Это не копия внешней общей mastery-библиотеки и не место для данных конкретного исследования.

## Области

- [Researcher Mastery](researcher/INDEX.md) - методы исследования перспективности новых IT/web-возможностей до разработки и на ранней стадии проверки.
- [Analyst Mastery](analyst/INDEX.md) - immutable baseline методов бизнес-, системного и solution-анализа.
- [`INTENTS.json`](INTENTS.json) - расширяемый каталог категорий методов; новые intent IDs добавляются без изменения PowerShell-кода.
- [Local Mastery](local/INDEX.md) - производный реестр примененных project-local методов, созданных только в generated project.

## Retrieval route

Для research выбери baseline только из [`researcher/INDEX.md`](researcher/INDEX.md), для formal analysis - из [`analyst/INDEX.md`](analyst/INDEX.md). Для остальных типов работы используй зарегистрированный intent и при необходимости открой максимум одно active, непросроченное и релевантное расширение из [`local/INDEX.md`](local/INDEX.md). Точные baseline refs, local `method_id` и local refs запиши в рабочий plan или run.

Пустой `mastery/local/`, кроме `INDEX.md` и `TEMPLATE.md`, в template source и fresh generated copy является правильным состоянием. Реестр пересобирается `scripts/update-mastery-index.ps1`.

## Границы

- Процедура запуска, схема evidence и актуальные правила доступа находятся в [startup-researcher](../.agents/skills/startup-researcher/SKILL.md).
- Delivery workflow находится в [project-delivery](../.agents/skills/project-delivery/SKILL.md).
- Быстрое создание метода начинается с [`prompts/create-mastery.md`](../prompts/create-mastery.md), затем проходит method candidate, `new-mastery.ps1 -WhatIf` и отдельное approval.
- Данные конкретных запусков находятся в [research](../research/INDEX.md).
- Подтвержденные знания об идее находятся в [idea](../idea/INDEX.md).
- Внешние mastery-библиотеки не входят в шаблон. Их чтение или изменение требует отдельной явной интеграции; namespace `logical:shared-mastery/*` по умолчанию блокируется.
