# Artifact contracts

Канонический machine source - [`analysis/CONTRACT.md`](../../../../analysis/CONTRACT.md). Этот файл только маршрутизирует выполнение и не переопределяет namespace.

## Working

Run имеет UTC ID `RUN-YYYYMMDD-HHmmss-<slug>-<6hex>`, exact eight-file inventory и closed schemas. Run status не использует `approved`. Working proposals могут упоминать canonical-form IDs, но не становятся owner files.

## Canon

Закрытые prefixes: `STK`, `CAP`, `BP`, `RULE`, `BR`, `UC`, `FR`, `NFR`, `DATA`, `INT`, `SYS`, `AC`, `SPEC`, `CR`, `REV`. Exact mapping kind/path/filename и closed schema бери только из основного контракта.

`docs/analysis/context` и `docs/analysis/traceability` - derived view zones. Не создавай там новые canonical artifacts.

## Lifecycle

- Подготовь `draft` или `in-review`, если нет прямой approval authority.
- `approved` требует source, applicable parent, acceptance/verification, direct `user-request:*`, date и approver.
- Replacement указывает назад через `supersedes_ref`; self-ref, missing target и cycles запрещены.
- Handoff перечисляет exact targets. `no-change` оставляет target list пустым.
- После разрешенного canonical handoff derived graph обновляется trusted generator-ом; ручное редактирование графа запрещено.

## Run templates

- [brief](../assets/run-template/brief.md)
- [sources](../assets/run-template/sources.md)
- [analysis](../assets/run-template/analysis.md)
- [requirements](../assets/run-template/requirements.md)
- [models](../assets/run-template/models.md)
- [traceability](../assets/run-template/traceability.md)
- [review](../assets/run-template/review.md)
- [decision](../assets/run-template/decision.md)

[Вернуться к skill](../SKILL.md).
