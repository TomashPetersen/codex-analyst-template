# Business Analysis

## Назначение и границы

Метод выявляет change, needs, value, stakeholders, context, capabilities, процессы, business rules и ожидаемые outcomes. Он адаптируется к масштабу решения, но не проектирует техническое решение вместо system analysis, не назначает KPI и не выдает recommendation за approval.

## Входы

- проверяемые project или user sources с provenance, confirmation status и limitations;
- problem statement, scope, decision context, audience и governance;
- известные stakeholders, capabilities, процессы, ограничения и decision owners;
- runtime, UAT или operational evidence, если intent равен `solution-evaluation`.

## Tailoring preflight

До анализа зафиксировать в `brief.md`:

1. analysis intent, требуемое решение, audience и границы;
2. применимые governance и authority gates;
3. выбранные techniques и причину их пригодности;
4. exit criteria, остаточный риск и неизвестные;
5. глубину анализа, соразмерную цене ошибки, доступному evidence и влиянию изменения.

## Method

1. Пройти BACCM preflight: для `Change`, `Need`, `Solution`, `Value`, `Stakeholder` и `Context` отделить evidence-backed facts от assumptions, conflicts и unknowns. `Solution` на этом шаге является предметом анализа, а не уже выбранным ответом.
2. Разделить stakeholder, user, buyer, operator, sponsor, approver и decision owner. Для каждой значимой стороны определить concern, влияние, способ вовлечения и требуемое подтверждение.
3. Выполнить strategy analysis: восстановить evidence-backed AS-IS, root causes, capabilities и constraints; описать TO-BE outcomes и gaps без преждевременного system design.
4. Спланировать elicitation techniques по источнику и риску, зафиксировать результаты, stakeholder refs, confirmation status, corroboration, conflicts и limitations. Неподтвержденное интервью не превращать в общий факт.
5. Нормализовать STK, CAP, BP, RULE и BR proposals, сохраняя source refs, scope, owner, rationale, conflicts и lifecycle state.
6. Приоритизировать только по объявленной схеме, критериям и decision owner. Отделять аналитическую оценку urgency/value/risk от решения владельца.
7. Поддерживать requirements lifecycle: trace, state, dependencies, change impact, verification, stakeholder validation и approval остаются разными отношениями.
8. Для `solution-evaluation` сопоставить фактическую performance/value baseline с согласованными мерами, выявить solution и enterprise limitations и предложить действия. Без runtime, UAT или operational evidence verdict может быть только `insufficient-evidence`, `provisional` или `blocked`.

## Выходы и quality gate

STK, CAP, BP, RULE и BR proposals с источниками, owners, scope, priorities, conflicts и проверяемыми критериями. При solution evaluation добавляется `REV-*` proposal с evidence refs и limitations.

Gate проходит, если:

- techniques соответствуют context и exit criteria;
- stakeholders и существенные conflicts покрыты либо отмечены как gaps;
- problem, root cause, outcome и solution option не смешаны;
- priority имеет scheme и decision owner;
- solution evaluation основана на runtime, UAT или operational evidence;
- recommendation не объявлена approval или architecture choice.

## Anti-patterns

- превращать пожелание в факт;
- использовать BACCM как checklist без связей между концептами;
- смешивать проблему и выбранное решение;
- приоритизировать по мнению аналитика без scheme и decision owner;
- объявлять solution успешным только по design documents;
- копировать один normative claim в несколько owner files.

## Ограничения применимости

Не заменяет market research, legal interpretation, runtime measurement, feasibility review или approval владельца. Метод не заявляет formal conformance с IIBA или BABOK Guide.

## Provenance

Оригинальная русская операционализация шаблона, согласованная с [analysis contract](../../analysis/CONTRACT.md). Нормативные и проприетарные тексты не копируются.

- `method_version`: `1.1.0`
- `source`: [IIBA The Business Analysis Standard](https://www.iiba.org/knowledgehub/the-business-analysis-standard/), version `2.0`, public web/PDF edition, verified `2026-08-29`, rights `International Institute of Business Analysis (IIBA); BACCM and BABOK are IIBA marks`, usage `concept-level adaptation only`
- `formal_conformance`: `not-claimed`

## Проверка

- `verified_at`: `2026-08-29`
- `review_due`: `2027-02-25`

## Связи

- [Requirements engineering](requirements-engineering.md)
- [Process and use-case modeling](process-and-use-case-modeling.md)
- [Solution architecture](solution-architecture.md)
- [Analyst Mastery](INDEX.md)
