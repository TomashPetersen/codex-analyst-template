# Process and Use-Case Modeling

## Назначение и границы

Метод выбирает минимальное представление, достаточное для actor goals, end-to-end process и business decisions. Narrative, BPMN-aligned и DMN-aligned views являются разными семантическими инструментами, а не тремя обязательными копиями одного требования.

## Входы

- stakeholder, process и decision evidence;
- goals, triggers, preconditions, rules и outcomes;
- system boundary, participants, known exceptions и recovery expectations;
- audience и цель модели.

## Selection gate

- Выбрать **narrative use case**, когда нужно проверить цель актора, boundary, основной, альтернативные, error и recovery flows без сложной межролевой оркестрации.
- Выбрать **BPMN-aligned semantic subset**, когда значимы участники, events, activities, sequence/message flows, gateways, concurrency, exceptions или compensation.
- Выбрать **DMN-aligned semantic subset**, когда повторно используемое решение зависит от входных facts и business rules и должно анализироваться отдельно от порядка процесса.
- Если process вызывает decision, связать BP с RULE/decision model по ID. Не копировать decision table в process flow.

Выбранный subset фиксируется в `brief.md` вместе с rationale и limitations. Создание BPMN/DMN XML и formal conformance не требуется.

## Method

1. Зафиксировать scope, audience, start/end events или actor goal, system boundary и participants.
2. Описать evidence-backed AS-IS, handoffs, waits, controls и root causes; отдельно обозначить unknowns.
3. Сформировать TO-BE outcome и изменения без скрытых assumptions или architecture choice.
4. Для narrative use case описать actor, trigger, preconditions, main flow, alternate, negative, boundary, error и recovery flows, postconditions и refs на BR/RULE.
5. Для BPMN-aligned subset проверить ownership шагов, допустимые sequence/message semantics, gateway conditions, concurrency, exception paths, compensation и terminal outcomes.
6. Для DMN-aligned subset определить decision, input facts, knowledge/rule refs, output, rule completeness, overlap/conflict и unknown cases. Приоритет rule задается только источником или decision owner.
7. Сопоставить process, decision и use-case views по IDs, triggers, rules и outcomes; противоречия фиксировать, а не сглаживать.
8. Подтвердить модель у релевантных stakeholders и отдельно проверить feasibility/error handling с system analyst.

## Выходы и quality gate

BP, RULE и UC proposals с traceability и явным типом представления. Gate требует конкретных triggers, outcomes, actor/participant responsibility, decision coverage и failure/recovery paths.

Для BPMN-aligned subset все значимые branches имеют условия и terminal outcome. Для DMN-aligned subset проверены missing, overlapping и conflicting rules. Модель не заявляется формально BPMN- или DMN-conformant.

## Anti-patterns

- описывать UI clicks вместо actor goal;
- смешивать AS-IS и TO-BE;
- считать happy path полным use case;
- использовать gateway без условия или owner;
- смешивать порядок процесса и логику решения;
- рисовать BPMN/DMN ради нотации, когда narrative достаточен;
- дублировать normative rule в нескольких views.

## Ограничения применимости

Не заменяет workflow telemetry, executable process definition, formal notation validation, usability testing или process/decision owner approval.

## Provenance

Оригинальная русская операционализация шаблона по [traceability invariants](../../analysis/CONTRACT.md#traceability-invariants). Используются только semantic subsets; нормативные тексты и изображения OMG не копируются.

- `method_version`: `1.1.0`
- `source`: [OMG BPMN](https://www.omg.org/spec/BPMN/2.0.2/), version `2.0.2`, published `2014-01`, verified `2026-08-29`, rights `Object Management Group and listed contributors`, usage `semantic subset only`
- `source`: [OMG DMN](https://www.omg.org/spec/DMN/1.5/), version `1.5`, formal publication `2024-08`, verified `2026-08-29`, rights `Object Management Group and listed contributors`, usage `semantic subset only`
- `formal_conformance`: `not-claimed`

## Проверка

- `verified_at`: `2026-08-29`
- `review_due`: `2027-02-25`

## Связи

- [Business analysis](business-analysis.md)
- [Requirements engineering](requirements-engineering.md)
- [Analyst Mastery](INDEX.md)
