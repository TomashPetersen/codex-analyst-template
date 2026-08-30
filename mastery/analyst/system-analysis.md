# System Analysis

## Назначение и границы

Метод определяет system boundary, actors, external systems, states, sequences, constraints и trust boundaries. Он не заменяет детальный architecture decision.

## Входы

- approved или review-ready business requirements;
- existing code, interfaces и operational constraints;
- data, privacy и security context.

## Method

1. Определить system-of-interest и внешние зависимости.
2. Построить context, state и sequence views с refs.
3. Выявить functional boundaries, error paths и trust boundaries.
4. Связать SYS с FR, NFR, DATA, INT и verification.
5. Проверить assumptions и failure modes независимым review.

## Выходы и quality gate

SYS proposals и связанные model refs. Gate требует ясной границы, известных actors/interfaces, error paths и проверяемых constraints.

## Anti-patterns

- рисовать диаграмму без источников и semantics;
- путать текущую реализацию с обязательным будущим решением;
- скрывать внешнюю зависимость внутри компонента.

## Ограничения применимости

Не выбирает stack и не принимает ADR без отдельной authority.

## Provenance

Оригинальная операционализация шаблона; source-of-truth - [analysis contract](../../analysis/CONTRACT.md).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Data and integration analysis](data-and-integration-analysis.md)
- [NFR and quality attributes](nfr-and-quality-attributes.md)
- [Analyst Mastery](INDEX.md)
