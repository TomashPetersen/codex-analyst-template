# Data and Integration Analysis

## Назначение и границы

Метод определяет data semantics, ownership, lifecycle и integration contracts между конкретными systems. Он не хранит secrets и не проектирует production credentials.

## Входы

- SYS boundaries и consumers/producers;
- requirement и rule refs;
- existing schemas, APIs, events и data classification.

## Method

1. Определить canonical entities, fields, ownership и lifecycle.
2. Зафиксировать producers, consumers, protocol и schema.
3. Описать auth mechanism без secrets, errors, retries и idempotency.
4. Добавить SLA, privacy, retention и compatibility constraints.
5. Связать каждый INT минимум с DATA и SYS, затем с verification.

## Выходы и quality gate

DATA и INT proposals. Gate требует однозначной семантики, owners, failure handling, security/privacy и bidirectional traceability.

## Anti-patterns

- принимать transport payload за domain model;
- хранить токены или signed URLs;
- скрывать versioning и idempotency.

## Ограничения применимости

Не подтверждает производительность или безопасность без тестов и review.

## Provenance

Оригинальная операционализация шаблона по [INT invariants](../../analysis/CONTRACT.md#traceability-invariants).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [System analysis](system-analysis.md)
- [NFR and quality attributes](nfr-and-quality-attributes.md)
- [Analyst Mastery](INDEX.md)
