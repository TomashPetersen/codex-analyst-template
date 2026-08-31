# Artifact contracts

Канонический machine source - [`analysis/CONTRACT.md`](../../../../analysis/CONTRACT.md). Этот файл только маршрутизирует выполнение и не переопределяет namespace.

## Working

Run имеет UTC ID `RUN-YYYYMMDD-HHmmss-<slug>-<6hex>`, exact eight-file inventory и closed schemas. Run status не использует `approved`. Working proposals могут упоминать canonical-form IDs, но не становятся owner files.

Восемь и только восемь run assets: `brief.md`, `sources.md`, `analysis.md`, `requirements.md`, `models.md`, `traceability.md`, `review.md`, `decision.md`. Solution architecture распределяется по ним и не создает `overview.md`, `architecture.md`, `implementation.md`, SOP decomposition или второго canonical owner.

## Canon

Закрытые prefixes: `STK`, `CAP`, `BP`, `RULE`, `BR`, `UC`, `FR`, `NFR`, `DATA`, `INT`, `SYS`, `AC`, `SPEC`, `CR`, `REV`. Exact mapping kind/path/filename и closed schema бери только из основного контракта.

`docs/analysis/context` и `docs/analysis/traceability` - derived view zones. Не создавай там новые canonical artifacts.

## Verification, validation и approval

```text
requirements verification != stakeholder validation != approval
```

- Verification проверяет структуру, однозначность, согласованность, feasibility, testability и traceability требования.
- Validation сопоставляет предложение с подтвержденной stakeholder need, intended use и ожидаемой ценностью.
- Approval является отдельным authority event и не выводится из review, evidence, ADR или статуса run.

`REV-*` содержит machine-readable JSON-блок `review_record` с полями `review_type`, `subject_refs`, `evidence_refs`, `verdict`, `limitations`. Закрытые `review_type`: `requirements-verification`, `requirements-validation`, `solution-evaluation`. Закрытые `verdict`: `pass`, `pass-with-actions`, `reject`, `insufficient-evidence`, `provisional`, `blocked`. `decision_refs` связывает предмет с `REV-*`; `verification_refs` содержит только фактические проверки или тестовое evidence; `approval_ref` остается единственной approval authority.

Положительный `solution-evaluation` требует совпадающие в `evidence_refs` и `verification_refs` runtime-class refs `evidence:runtime:<id>`, `evidence:uat:<id>` или `evidence:operational:<id>` и baseline ref `evidence:baseline:<id>`. Эти tokens дают machine classification, но не доказывают actuality. Проверь registered source, provenance, collection method, фактический artifact и limitations; без этой основы token не создавай.

Для approved body contracts действуют строгие relations без prose-исключения `not-applicable`: `BR -> STK/CAP/BP + AC`; `RULE -> BP/BR + AC`; `AC -> BR/RULE/UC/FR/NFR + factual verification_refs`.

## Lifecycle

- Подготовь `draft` или `in-review`, если нет прямой approval authority.
- `approved` требует source, applicable parent, acceptance/verification, direct `user-request:*`, date и approver.
- Replacement указывает назад через `supersedes_ref`; self-ref, missing target и cycles запрещены.
- Handoff перечисляет exact targets. `no-change` оставляет target list пустым.
- При `intent_id: architecture` handoff допускает только существующие `SYS`, `DATA`, `INT`, `NFR` и `SPEC`. Proposed solution strategy и ADR candidate остаются аналитическими предложениями. Подтвержденная архитектура, accepted ADR и implementation plan требуют отдельного Plan v2 и прямой authority.
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
