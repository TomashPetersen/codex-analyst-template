# Research

Рабочая зона сбора нового evidence в конкретном initialized или active generated project. Текущий подтвержденный канон читается из [`idea/`](../idea/INDEX.md) и предметных зон, а новые наблюдения сначала остаются в запуске.

## Структура

- `runs/YYYY-MM-DD-<slug>/` - один отдельный запуск.
- [Startup Researcher](../.agents/skills/startup-researcher/SKILL.md) - исполняемый процесс.
- [Run template](../.agents/skills/startup-researcher/assets/run-template/brief.md) - assets directory является единственным машинным источником обязательного набора файлов.
- [Project Mastery](../mastery/INDEX.md) - маршрут baseline и local methods.
- [Knowledge](../knowledge/INDEX.md) - единый путь устойчивого вывода в central candidate и канон.

## Run contract

Каждый каталог первого уровня в `runs/` имеет exact-case имя `YYYY-MM-DD-<slug>` и содержит:

```text
brief.md
queries.md
evidence.jsonl
candidates.md
red-team.md
decision.md
```

Список получается из фактического `assets/run-template/`, а не из второго machine registry. Даже быстрый run сохраняет все шесть файлов; неприменимый раздел содержит `не применимо` с причиной. Partial scaffold, неправильный регистр, traversal, reparse point и run-local `promotion-proposal.md` блокируются. В template source `runs/` остается пустым.

Evidence schema, origin deduplication и safety принадлежат [исполняемому skill](../.agents/skills/startup-researcher/SKILL.md) и его [evidence contract](../.agents/skills/startup-researcher/references/evidence-and-deduplication.md). Общая privacy и promotion policy принадлежит [`knowledge/INDEX.md`](../knowledge/INDEX.md). Этот index не дублирует их.

## Methods

До сбора evidence выбери точные baseline method refs по [Researcher Mastery](../mastery/researcher/INDEX.md), затем прочитай [Local Mastery registry](../mastery/local/INDEX.md). Допустимо максимум одно active, непросроченное и релевантное local extension.

Brief и decision хранят точные baseline refs, local `method_id` и local file refs. Правила применимости и lifecycle методов находятся в mastery registry и проверяются semantic gate.

## Результат

Run сохраняет evidence и решение, но не меняет `idea/` автоматически. Candidate и promotion выполняются только по [`knowledge/INDEX.md`](../knowledge/INDEX.md) и `$knowledge-curator`; отдельный proposal artifact внутри run не создается.
