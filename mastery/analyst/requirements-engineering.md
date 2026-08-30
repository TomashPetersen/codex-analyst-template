# Requirements Engineering

## Назначение и границы

Метод превращает доказанные needs в однозначные BR, UC, FR, NFR и AC, сохраняя provenance, representation choice и lifecycle. Он не выдает draft, успешную verification или stakeholder validation за approved requirement.

## Входы

- STK, CAP, BP, RULE и BR refs;
- source registry, glossary, unresolved questions и conflicts;
- system boundary, constraints, risks и decision context;
- выбранная priority scheme и ее decision owner, если intent равен `requirements-prioritization`.

## Method

1. Зарегистрировать sources: collection method, covered scope, stakeholder refs, confirmation status, corroboration и limitations. Отделить source claim от интерпретации аналитика.
2. Создать или уточнить glossary: preferred terms, aliases, запрещенные неоднозначные термины, units и domain constraints. Проверить единообразие терминов во всех proposals.
3. Выбрать representation по семантике и audience: атомарный statement, use case, таблица rule/decision, state/sequence/process model, data/integration contract или quality scenario. Не дублировать один нормативный claim в нескольких владельцах.
4. Нормализовать intent, actor или subject, trigger, conditions, response/outcome и boundary. Разделить compound statements, устранить pronoun ambiguity, скрытые quantifiers и необоснованный solution bias.
5. Выполнить requirements verification: проверить структуру, однозначность, consistency, completeness в заявленном scope, necessity evidence, feasibility evidence, testability, traceability и допустимые dependencies.
6. Подготовить positive, negative, boundary, error и recovery examples. Связать AC и verification method с наблюдаемым результатом, не превращая примеры в конкурирующий normative owner.
7. Выполнить stakeholder validation отдельно: подтвердить, что requirement выражает нужный outcome и пригоден в контексте. Зафиксировать участника, evidence, limitations и unresolved disagreement.
8. Управлять lifecycle: source, parent, conflict, dependency, priority, verification, validation, change и decision refs. Приоритизация требует явных scheme, criteria и decision owner; аналитический rank не является approval.

## Ключевое различие

```text
requirements verification != stakeholder validation != approval
```

- verification оценивает качество и внутреннюю пригодность requirement artifact;
- stakeholder validation оценивает соответствие нужде и контексту;
- approval возникает только из отдельного authority source через `approval_ref`.

## Выходы и quality gate

Трассируемые requirement proposals и, когда нужен формальный review record, `REV-*` proposal. Gate требует source/glossary coverage, атомарности, однозначности, feasibility, testability, error/recovery coverage и отсутствия скрытого approval.

Для `requirements-verification` обязателен отдельный verdict с subject/evidence refs и limitations. Для `requirements-prioritization` обязательны scheme, критерии, decision owner и unresolved ties; без них результат блокируется.

## Anti-patterns

- объединять несколько требований в одном ID;
- использовать `быстро`, `удобно`, `надежно` без меры;
- считать stakeholder confirmation технической verification;
- считать passed review approval владельца;
- ранжировать без объявленной scheme или decision owner;
- делать feature request нормативным без problem/source;
- описывать только positive example.

## Ограничения применимости

Не доказывает ценность продукта, feasibility, runtime behavior или consent без соответствующих sources и review. Метод не заявляет formal conformance с IREB, IIBA или ISO/IEC/IEEE 29148.

## Provenance

Оригинальная русская операционализация шаблона по [closed schema](../../analysis/CONTRACT.md#canonical-schema). Нормативные и учебные тексты внешних источников не копируются.

- `method_version`: `1.1.0`
- `source`: [IREB CPRE Foundation Level](https://cpre.ireb.org/en/downloads-and-resources/downloads), syllabus version `3.3.0`, verified `2026-08-29`, rights `International Requirements Engineering Board (IREB)`, usage `concept-level adaptation only`
- `source`: [ISO/IEC/IEEE 29148:2018](https://www.iso.org/standard/72089.html), edition `2`, published `2018-11`, verified `2026-08-29`, rights `ISO/IEC/IEEE - all rights reserved`, status `published; revision work noted by ISO`, usage `public metadata and concepts only`
- `source`: [IIBA The Business Analysis Standard](https://www.iiba.org/knowledgehub/the-business-analysis-standard/), version `2.0`, verified `2026-08-29`, rights `International Institute of Business Analysis (IIBA)`, usage `public task concepts only`
- `formal_conformance`: `not-claimed`

## Проверка

- `verified_at`: `2026-08-29`
- `review_due`: `2027-02-25`

## Связи

- [Business analysis](business-analysis.md)
- [Process and use-case modeling](process-and-use-case-modeling.md)
- [NFR and quality attributes](nfr-and-quality-attributes.md)
- [Analyst Mastery](INDEX.md)
