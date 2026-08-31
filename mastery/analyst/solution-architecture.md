# Solution Architecture

## Назначение и условие применения

Метод формирует проверяемое architecture proposal для конкретного decision context. Его применяет существующий `system_analyst` только при `intent_id: architecture`, когда [Analyst Mastery](INDEX.md) выбрал этот profile основным. Метод не создает новую роль, не принимает ADR и не дает authority на implementation, canonical architecture или approval.

## Входы

- decision context, audience, scope, governance и exit criteria;
- evidence-backed business outcomes, BR, SYS, DATA, INT и NFR refs;
- current-state constraints, operational evidence, risks и unresolved questions;
- stakeholder concerns, known viewpoints и authority boundaries.

## Architecture framing

В `brief.md` зафиксировать:

1. решение, которое нужно подготовить, и решения вне scope;
2. audience, stakeholders, concerns и требуемые viewpoints;
3. architecture drivers, constraints, assumptions и их evidence refs;
4. comparison criteria, governance, exit criteria и residual risk;
5. выбранную глубину views и причину tailoring.

## Method

1. Определить system-of-interest и decision boundary. Связать business goals, architecture drivers, constraints, quality scenarios и stakeholder concerns, не превращая preferred option в исходное условие.
2. Выбрать минимальный набор viewpoints, отвечающий concerns. Context, Container и Deployment views C4 использовать только когда они добавляют проверяемую информацию; полный arc42 и все уровни C4 не обязательны.
3. Описать requirements architecture: уровни и связи STK/CAP/BP/RULE/BR с UC/FR/NFR/SYS/DATA/INT/AC, conflicts и unresolved edges.
4. Сформировать минимум два технически реалистичных architecture options. Сравнить их по одинаковым evidence-backed criteria; для каждого указать assumptions, benefits, costs как качественные trade-offs без выдуманных budget/schedule, risks, constraints и unresolved questions.
5. Для каждого жизнеспособного варианта описать component catalog: responsibility, inputs, outputs, dependencies и owned data. Показать rationale хранения данных, integration paths, errors, retries/idempotency и compatibility constraints по существующим refs.
6. Выделить trust boundaries, assets, plausible threats и proposed controls. Не объявлять security control достаточным без отдельной проверки.
7. Описать deployment и operations view: environments, runtime dependencies, observability, scaling assumptions, failure/degradation, backup/restore и recovery. Не изобретать platform, topology или thresholds.
8. Проверить quality scenarios: source, stimulus, environment, affected artifact, response, response measure, priority и verification method. Неподтвержденные measures оставить gaps или proposals.
9. Составить assumption validation plan: для критичных assumptions указать evidence needed, проверку, owner и impact of failure. Отделить известный факт от inference.
10. Сформулировать proposed solution strategy и ADR candidate с options, criteria, trade-offs, risks и open questions. Recommendation остается proposal; option selection, ADR acceptance и implementation planning происходят только в отдельном Plan/authority workflow.

## Выходы и размещение

IBM-derived семантика полностью помещается в существующие восемь run assets. Метод не создает `overview.md`, `architecture.md`, `implementation.md`, SOP decomposition или второй canonical owner.

Analytical handoff использует только существующие proposals и refs:

- SYS - boundary, components, responsibilities, deployment и operations views;
- DATA - ownership, lifecycle, storage rationale и protections;
- INT - protocols/messages, contracts, dependencies и failure handling;
- NFR - measurable quality scenarios и verification methods;
- SPEC - связный reviewable index на owner artifacts;
- `models.md` - comparison matrix и views рабочего run;
- `decision.md` - recommendation proposal, delivery readiness, dependencies и follow-up refs, но не implementation plan.

## Quality gate

Gate проходит, если:

- decision context, audience, drivers, constraints, concerns и viewpoints явны;
- есть минимум два технически реалистичных варианта;
- criteria имеют evidence/rationale, а у вариантов раскрыты trade-offs, risks и unresolved questions;
- component, data, integration, security, deployment, operations и recovery concerns покрыты либо отмечены как gaps;
- quality scenarios измеримы, assumptions имеют validation path;
- proposed strategy не скрывает выбор, ADR acceptance или implementation authority.

## Anti-patterns

- начинать с любимого stack или единственного варианта;
- выдавать текущую систему за обязательную target architecture;
- сравнивать варианты по разным или выдуманным критериям;
- придумывать budget, schedule, KPI, NFR threshold или vendor constraint;
- рисовать diagram без audience, concern, semantics и evidence refs;
- объявлять proposed control доказанной security;
- принимать ADR или создавать implementation plan внутри analysis run.

## Ограничения применимости

Метод готовит решение, но не подтверждает feasibility, runtime quality или security без соответствующего evidence и review. Он не заявляет formal conformance с IBM method, ISO/IEC/IEEE 42010, C4 или arc42.

## Provenance

Оригинальная русская операционализация. Из IBM source перенесен общий паттерн движения от контекста и вариантов к views, trade-offs и delivery readiness; IBM examples, watsonx-specific assumptions, budgets, schedules и готовые NFR не копируются.

- `method_version`: `1.1.0`
- `source`: [IBM Solution Architect skill](https://github.com/IBM/ibm-watsonx-orchestrate-adk/blob/02c6b27d4c942c9685c394cf85416c87151ebeac/skills/solution-architect/SKILL.md), path `skills/solution-architect/SKILL.md`, commit `02c6b27d4c942c9685c394cf85416c87151ebeac`, extracted `2026-08-29`, rights `Copyright (c) 2024, 2025 IBM Corporation; MIT License`, usage `original adaptation, no copied examples`
- `source`: [ISO/IEC/IEEE 42010:2022](https://www.iso.org/standard/74393.html), edition `2`, published `2022-11`, verified `2026-08-29`, rights `ISO/IEC/IEEE - all rights reserved`, usage `public architecture-description concepts only`
- `source`: [C4 model](https://c4model.com/diagrams), version `living official guidance as retrieved 2026-08-29`, views `System Context, Container, Deployment`, rights `Simon Brown; official site content CC BY 4.0`, usage `concept-level view selection only`
- `source`: [arc42 quality scenarios](https://docs.arc42.org/section-10/), version `official web guidance as retrieved 2026-08-29`, rights `Gernot Starke and Peter Hruschka; arc42 template CC BY-SA 4.0`, usage `quality-scenario inspiration only; full arc42 not required`
- `formal_conformance`: `not-claimed`

## Проверка

- `verified_at`: `2026-08-29`
- `review_due`: `2027-02-25`

## Связи

- [System analysis](system-analysis.md)
- [Business analysis](business-analysis.md)
- [NFR and quality attributes](nfr-and-quality-attributes.md)
- [Data and integration analysis](data-and-integration-analysis.md)
- [Analyst Mastery](INDEX.md)
