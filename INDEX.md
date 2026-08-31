# Карта Codex Analyst Template

## Начало

- [`README.md`](README.md) - установка и первый рабочий цикл.
- [`CODEX-INSTALL-PROMPT.md`](CODEX-INSTALL-PROMPT.md) - готовый URL-first prompt установки из GitHub через Codex.
- [`PROJECT.md`](PROJECT.md) - паспорт, границы и статус.
- [`AGENTS.md`](AGENTS.md) - маршрутизация Codex, Plan v2 и safety.
- [`ai-clone/INDEX.md`](ai-clone/INDEX.md) - обезличиваемый профиль сотрудничества.
- [`prompts/README.md`](prompts/README.md) - компактные доменные prompts.

## Знания и работа

- [`idea/INDEX.md`](idea/INDEX.md) - гипотезы, evidence, PoV, MVP и риски.
- [`product/INDEX.md`](product/INDEX.md) - продукт, пользователи, опыт и capabilities.
- [`business/INDEX.md`](business/INDEX.md) - бизнес-архитектура, экономика, продвижение и метрики.
- [`analysis/INDEX.md`](analysis/INDEX.md) - рабочие восьмифайловые analysis runs и единый контракт handoff.
- [`business/analysis/INDEX.md`](business/analysis/INDEX.md) - stakeholders, capabilities, процессы, правила и бизнес-требования.
- [`docs/analysis/INDEX.md`](docs/analysis/INDEX.md) - use cases, требования, модели, интеграции, спецификации и review.
- [`docs/architecture/INDEX.md`](docs/architecture/INDEX.md) - технический контекст и границы.
- [`docs/codebase/INDEX.md`](docs/codebase/INDEX.md) - фактическая карта реализации и команд.
- [`docs/decisions/README.md`](docs/decisions/README.md) - ADR и последствия выбора.
- [`plans/INDEX.md`](plans/INDEX.md) - производный индекс текущих и завершенных plans.
- [`knowledge/INDEX.md`](knowledge/INDEX.md) - candidates, provenance, closeout и promotion.
- [`knowledge/graph/INDEX.md`](knowledge/graph/INDEX.md) - производная карта активного канона и backlinks.
- [`mastery/INDEX.md`](mastery/INDEX.md) - Researcher, Analyst и Local Mastery.
- [`research/INDEX.md`](research/INDEX.md) - evidence runs.
- [`inbox/README.md`](inbox/README.md) - единая RAW-приемная и маршрут к [`inbox/raw/`](inbox/raw/README.md).
- [`retrospectives/README.md`](retrospectives/README.md) - необязательная история инцидентов и крупных выпусков.

## Skills и scripts

- [`.agents/skills/project-delivery/SKILL.md`](.agents/skills/project-delivery/SKILL.md) - реализация через сохраняемый Plan v2.
- [`.agents/skills/knowledge-curator/SKILL.md`](.agents/skills/knowledge-curator/SKILL.md) - closeout, candidates и разрешенный promotion.
- [`.agents/skills/startup-researcher/SKILL.md`](.agents/skills/startup-researcher/SKILL.md) - доказательное исследование.
- [`.agents/skills/it-analysis/SKILL.md`](.agents/skills/it-analysis/SKILL.md) - бизнес-, системный и solution-анализ с traceability и review.
- [`.codex/config.toml`](.codex/config.toml) - лимит трех specialist threads и единственный optional remote Context7 MCP; пять read-only ролей находятся в `.codex/agents/`.
- [`scripts/README.md`](scripts/README.md) - инициализация, generators и gates.

## Минимальные маршруты

| Задача | Начать с |
|---|---|
| Понять проект | `PROJECT.md` |
| Найти связанные знания в generated project | `scripts/update-knowledge-graph.ps1 -Mode Report`, затем `knowledge/graph/INDEX.md` и точные owner artifacts |
| Оценить impact развития template source | `TEMPLATE.md`, `.template-manifest.json`, scripts и точные source owners |
| Продолжить значимую работу | `plans/INDEX.md`, затем active plan и Resume checkpoint |
| Запланировать реализацию | `prompts/plan-and-deliver.md` и `$project-delivery` |
| Заполнить профиль | `prompts/ai-clone-interview.md` |
| Проверить идею | `prompts/idea-validation.md` и `$startup-researcher` |
| Выполнить один analysis run | `prompts/analysis-run.md` и `$it-analysis` |
| Выполнить программу анализа | `prompts/analysis-program.md` и `$project-delivery` |
| Проверить или передать анализ | `prompts/analysis-review.md` или `prompts/analysis-handoff.md` |
| Заполнить продукт | `prompts/product-interview.md` |
| Заполнить бизнес | `prompts/business-architecture-interview.md` |
| Инвентаризировать систему | `prompts/architecture-codebase-inventory.md` |
| Найти принятое решение | accepted ADR в `docs/decisions/` |
| Сохранить RAW | `knowledge/INDEX.md`, затем `inbox/raw/` |
| Создать или применить знание | `knowledge/INDEX.md`, затем `$knowledge-curator` |
| Создать Local Mastery | `prompts/create-mastery.md`, затем candidate lifecycle |
