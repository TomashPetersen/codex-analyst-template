# Process and Use-Case Modeling

## Назначение и границы

Метод связывает end-to-end business process с use cases, actors, triggers, main, alternate и error flows. Он не копирует один процесс в несколько нормативных представлений.

## Входы

- stakeholder и process evidence;
- goals, triggers, preconditions и rules;
- system boundary и known exceptions.

## Метод

1. Зафиксировать scope, start/end events и actors.
2. Описать AS-IS и причины gaps.
3. Сформировать TO-BE без скрытых assumptions.
4. Выделить use cases и связать их с BP/BR.
5. Проверить alternate, exception и recovery flows.

## Выходы и quality gate

BP и UC proposals с traceability. Gate требует конкретных triggers, outcomes, actor responsibility и failure paths.

## Anti-patterns

- описывать UI clicks вместо actor goal;
- смешивать AS-IS и TO-BE;
- считать happy path полным use case.

## Ограничения применимости

Не заменяет workflow telemetry, usability testing или process owner approval.

## Provenance

Оригинальная операционализация шаблона по [traceability invariants](../../analysis/CONTRACT.md#traceability-invariants).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Business analysis](business-analysis.md)
- [Requirements engineering](requirements-engineering.md)
- [Analyst Mastery](INDEX.md)
