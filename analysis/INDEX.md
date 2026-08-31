# Аналитический контур

`analysis/` содержит рабочий слой бизнес-, системного и solution-анализа. Он не является предметным каноном и не выдает агентный вывод за принятое решение.

## Маршрут

1. Прочитать [контракт](CONTRACT.md), `PROJECT.md`, корневой `INDEX.md` и [knowledge contract](../knowledge/INDEX.md).
2. Запустить [it-analysis](../.agents/skills/it-analysis/SKILL.md) через `scripts/new-analysis-run.ps1`.
3. Вести один exact eight-file run в `runs/<RUN-ID>/`.
4. Пройти independent review, traceability и authority gates.
5. При прямом разрешении обновить единственного владельца канона в [business analysis](../business/analysis/INDEX.md) или [system analysis](../docs/analysis/INDEX.md).
6. Завершить [knowledge closeout](../knowledge/INDEX.md#closeout).
7. После разрешенного изменения канона, candidate lifecycle или local mastery обновить [derived knowledge graph](../knowledge/graph/INDEX.md) и пройти strict structure gate.

## Границы

- `runs/` - project-owned working evidence. В исходном шаблоне и fresh copy каталог пуст.
- Run допустим как дополнительный `source_ref`, но запрещен как canonical target или `affected_canon`.
- Канонические требования, модели и спецификации живут только в owner paths из [контракта](CONTRACT.md#закрытый-namespace).
- `context/` и `traceability/` в документации являются derived views, а не дополнительными владельцами нормативного текста.

## Инструменты

- [`scripts/new-analysis-run.ps1`](../scripts/new-analysis-run.ps1) - атомарный scaffold.
- [`scripts/verify-analysis.ps1`](../scripts/verify-analysis.ps1) - machine-verifiable structure/contract gate, report и self-tests.
- [`mastery/analyst/INDEX.md`](../mastery/analyst/INDEX.md) - baseline методов аналитика.
- [`.codex/config.toml`](../.codex/config.toml) - project-scoped read-only специалисты и независимые review-роли.
- [`prompts/analysis-run.md`](../prompts/analysis-run.md) - один bounded run без Plan v2.
- [`prompts/analysis-program.md`](../prompts/analysis-program.md) - программа runs через обязательный Plan v2.
- [`knowledge/graph/INDEX.md`](../knowledge/graph/INDEX.md) - производные outgoing links и backlinks, не второй канон.
