# Requirements Engineering

## Назначение и границы

Метод превращает доказанные needs в однозначные BR, UC, FR, NFR и AC, сохраняя provenance и уровень уверенности. Он не выдает draft за approved requirement.

## Входы

- STK, CAP, BP, RULE и BR refs;
- source registry и unresolved questions;
- ограничения, риски и decision context.

## Метод

1. Выявить intent, actor, trigger, outcome и boundary.
2. Разделить business, functional, nonfunctional и acceptance semantics.
3. Написать атомарные, проверяемые statements без solution bias.
4. Добавить parents, acceptance, verification, conflicts и dependencies.
5. Провести validation с представителями владельца до handoff.

## Выходы и quality gate

Трассируемые requirement proposals. Gate требует однозначности, необходимости, реализуемости, testability и отсутствия скрытого approval.

## Anti-patterns

- объединять несколько требований в одном ID;
- использовать `быстро`, `удобно`, `надежно` без меры;
- делать feature request нормативным без problem/source.

## Ограничения применимости

Не доказывает ценность продукта, feasibility или consent без соответствующих источников и review.

## Provenance

Оригинальная операционализация шаблона по [closed schema](../../analysis/CONTRACT.md#canonical-schema).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Business analysis](business-analysis.md)
- [NFR and quality attributes](nfr-and-quality-attributes.md)
- [Analyst Mastery](INDEX.md)
