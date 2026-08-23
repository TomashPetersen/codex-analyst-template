# Business Analysis

## Назначение и границы

Метод выявляет stakeholders, capabilities, процессы, business rules, проблемы и ожидаемые outcomes. Он не проектирует техническое решение вместо system analysis.

## Входы

- проверяемые project или user sources;
- problem statement и scope;
- известные actors, процессы и ограничения.

## Метод

1. Отделить факты, наблюдения, гипотезы и неизвестное.
2. Разделить stakeholder, user, buyer, operator и approver.
3. Восстановить capability и AS-IS process с evidence refs.
4. Зафиксировать rules, gaps, conflicts и desired outcomes.
5. Сформировать BR proposals без преждевременного system design.

## Выходы и quality gate

STK, CAP, BP, RULE и BR proposals с источниками, owners, scope и проверяемыми критериями. Gate проходит, если отсутствуют бездоказательные универсальные claims и роли не смешаны.

## Anti-patterns

- превращать пожелание в факт;
- смешивать проблему и выбранное решение;
- копировать один normative claim в несколько owner files.

## Ограничения применимости

Не заменяет market research, legal interpretation или approval владельца.

## Provenance

Оригинальная операционализация шаблона, согласованная с [analysis contract](../../analysis/CONTRACT.md). Нормативные тексты внешних стандартов не копируются.

## Проверка

- `verified_at`: `2026-08-14`
- `review_due`: `2027-02-14`

## Связи

- [Requirements engineering](requirements-engineering.md)
- [Process and use-case modeling](process-and-use-case-modeling.md)
- [Analyst Mastery](INDEX.md)
