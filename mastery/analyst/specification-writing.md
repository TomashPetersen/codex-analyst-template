# Specification Writing

## Назначение и границы

Метод собирает reviewable SRS/ТЗ как контекст и refs на единственных владельцев требований и моделей. SPEC не создает вторую нормативную версию.

## Входы

- scope и non-goals;
- requirement, model, acceptance и decision refs;
- risks, security/privacy и unresolved questions.

## Method

1. Зафиксировать purpose, audience, scope и exclusions.
2. Сослаться на context, requirements и models по exact IDs.
3. Связать acceptance и verification без копирования statements.
4. Добавить risks, assumptions, decisions и unresolved questions.
5. Провести independent review на полноту, consistency и testability.

## Выходы и quality gate

SPEC proposal с traceability. Gate требует всех обязательных ref-классов, явных рисков/unknowns и отсутствия competing normative text.

## Anti-patterns

- копировать requirements в длинный документ;
- скрывать unresolved questions в prose;
- смешивать approved и draft без статусов.

## Ограничения применимости

Не заменяет contract/legal review и не принимает решение владельца.

## Provenance

Оригинальная операционализация шаблона по [SPEC invariants](../../analysis/CONTRACT.md#traceability-invariants).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Traceability and change impact](traceability-and-change-impact.md)
- [Requirements engineering](requirements-engineering.md)
- [Analyst Mastery](INDEX.md)
