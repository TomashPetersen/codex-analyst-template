# NFR and Quality Attributes

## Назначение и границы

Метод превращает quality expectations в измеримые NFR с context, metric, threshold, unit и test condition. Он не обещает универсальную метрику без operational context.

## Входы

- stakeholder outcomes и risks;
- workload, environment и failure context;
- security, privacy, accessibility и operational constraints.

## Метод

1. Назвать quality attribute и сценарий воздействия.
2. Определить measurement context и population.
3. Задать metric, threshold, unit и aggregation window.
4. Описать repeatable test condition и data source.
5. Связать NFR с BR/STK/CAP, AC или verification и SPEC.

## Выходы и quality gate

Измеримые NFR proposals. Gate отклоняет qualitative-only statements, отсутствующие units, environment или verification conditions.

## Anti-patterns

- `система должна быть быстрой`;
- percentile без window и population;
- security requirement без threat/trust context.

## Ограничения применимости

Порог требует owner validation и может измениться после измерений.

## Provenance

Оригинальная операционализация шаблона по [NFR invariant](../../analysis/CONTRACT.md#traceability-invariants).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Requirements engineering](requirements-engineering.md)
- [Data and integration analysis](data-and-integration-analysis.md)
- [Analyst Mastery](INDEX.md)
