# NFR and Quality Attributes

## Назначение и границы

Метод превращает quality expectations и risks в измеримые NFR и quality scenarios. Классификация quality attributes помогает задавать вопросы, но не поставляет готовые thresholds, SLA или architecture decisions.

## Входы

- stakeholder outcomes, source refs, priorities и risks;
- workload, environment, affected artifacts и failure context;
- security, privacy, accessibility и operational constraints;
- доступные measurement sources и verification capabilities.

## Quality scenario contract

Каждый NFR или связанный scenario содержит:

1. `source` - stakeholder, rule, incident, regulation, measurement или иной evidence ref;
2. `stimulus` - наблюдаемое событие, нагрузку, отказ или воздействие;
3. `environment` - состояние и условия, при которых действует stimulus;
4. `affected_artifact` - конкретную system, component, interface, data set или operation;
5. `response` - требуемое наблюдаемое поведение;
6. `response_measure` - metric, threshold/range, unit, population, aggregation window и допустимый способ измерения;
7. `priority` - scheme, rationale и decision owner;
8. `verification_method` - repeatable check, environment, data source и evidence output.

Неизвестное поле остается явным gap. Аналитик не подставляет универсальное значение.

## Method

1. Вывести quality concern из конкретного source, business outcome, threat, failure или operational need.
2. Выбрать подходящий quality attribute как классификацию, затем сформулировать полный scenario contract.
3. Проверить population, workload profile, boundary conditions, units, aggregation window и measurement uncertainty.
4. Разделить target, текущую baseline и наблюдаемое runtime evidence. Target без owner validation остается proposal.
5. Описать positive, overload/boundary, degradation, failure и recovery conditions, если они относятся к риску.
6. Выбрать verification method: test, inspection, analysis, simulation или operational measurement; указать требуемый evidence.
7. Связать NFR с STK/BR/CAP/RULE, affected SYS/DATA/INT, AC/verification и SPEC.
8. Проверить feasibility и architecture impact, не выбирая вариант решения автоматически.

## Выходы и quality gate

Измеримые NFR proposals и quality scenarios. Gate отклоняет qualitative-only statements, отсутствующие source, stimulus, environment, affected artifact, response measure, priority owner или verification method.

Порог без evidence может оставаться hypothesis/proposal, но не подтвержденным обязательством. Verification result не является stakeholder validation или approval.

## Anti-patterns

- `система должна быть быстрой`;
- percentile без population, workload и window;
- availability без observation period и excluded/treated events;
- security requirement без threat и trust boundary;
- recovery expectation без failure state и evidence method;
- копировать threshold из generic best practice;
- превращать ISO quality category в готовое requirement.

## Ограничения применимости

Порог требует owner validation и может измениться после измерений. Метод не доказывает runtime characteristic без verification evidence и не заявляет formal conformance с ISO/IEC 25010 или ISO/IEC/IEEE 29148.

## Provenance

Оригинальная русская операционализация шаблона по [NFR invariant](../../analysis/CONTRACT.md#traceability-invariants). Нормативные тексты не копируются.

- `method_version`: `1.1.0`
- `source`: [ISO/IEC 25010:2023](https://www.iso.org/standard/78176.html), edition `2`, published `2023-11`, verified `2026-08-29`, rights `ISO/IEC - all rights reserved`, usage `public product-quality model metadata and concept-level classification only`
- `source`: [ISO/IEC/IEEE 29148:2018](https://www.iso.org/standard/72089.html), edition `2`, published `2018-11`, verified `2026-08-29`, rights `ISO/IEC/IEEE - all rights reserved`, usage `public requirements metadata and concepts only`
- `formal_conformance`: `not-claimed`

## Проверка

- `verified_at`: `2026-08-29`
- `review_due`: `2027-02-25`

## Связи

- [Requirements engineering](requirements-engineering.md)
- [Data and integration analysis](data-and-integration-analysis.md)
- [Solution architecture](solution-architecture.md)
- [Analyst Mastery](INDEX.md)
