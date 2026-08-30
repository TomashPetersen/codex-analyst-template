# Traceability and Change Impact

## Назначение и границы

Метод проверяет целостность графа source-to-review и оценивает последствия изменений. Матрица хранит IDs и refs, а не вторую копию нормативного текста.

## Входы

- canonical IDs и refs;
- proposed change и affected scope;
- verification, decisions и unresolved conflicts.

## Method

1. Построить directed graph от source до review.
2. Найти missing parent, acceptance, verification и decision edges.
3. Проверить orphan nodes, duplicates и cycles supersedes.
4. Для CR пройти requirements, models, data, integrations, tests, security, privacy и operations.
5. Зафиксировать findings, owners, mitigation и rollback.

## Выходы и quality gate

Traceability result и impact report. Gate требует отсутствия обязательных missing edges и явного решения по каждому blocker.

## Anti-patterns

- считать таблицу источником истины;
- игнорировать rejected/conflicting evidence;
- оценивать impact только поиском текста.

## Ограничения применимости

Статический граф не доказывает runtime behavior или полноту неизвестных внешних зависимостей.

## Provenance

Оригинальная операционализация шаблона по [обязательному графу](../../analysis/CONTRACT.md#traceability-invariants).

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Specification writing](specification-writing.md)
- [System analysis](system-analysis.md)
- [Analyst Mastery](INDEX.md)
