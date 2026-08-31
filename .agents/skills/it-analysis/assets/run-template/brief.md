---
run_id: "{{RUN_ID}}"
run_asset: brief
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
intent_id: null
authority_ref: null
selected_method_refs: []
local_method_refs: []
---

# Brief - {{RUN_TITLE}}

## Decision context и bounded question

Какое решение или проверяемый вывод требуется, кто decision owner и какой выбор не входит в authority этого run.

## Audience и stakeholder concerns

Для каждой аудитории укажи `STK-*`/safe ref, concern, требуемый viewpoint и способ подтверждения понимания.

## Scope и non-goals

## Tailoring и governance

Почему выбран этот уровень анализа, какие representations и techniques применяются, какие роли участвуют, кто Lead-only writer и где находятся approval boundaries.

## Drivers, constraints и inputs

Не изобретай stack, budget, schedule, KPI, NFR threshold или architecture choice. Неподтвержденное помечай assumption/unknown.

## Deliverables, acceptance и exit criteria

Определи ожидаемые восемь run assets, semantic outcomes, достаточность evidence, blockers и условия `no-change`/handoff.

## Selected methods

Укажи closed `intent_id`; `selected_method_refs[0]` содержит exact primary ref на `mastery/analyst` со стабильным suffix `#method`, а не Markdown anchor заголовка. Дополнение допускается либо как `selected_method_refs[1]` с одним supplementary baseline, либо как `local_method_refs[0]` с одним active local extension, но не оба сразу. Суммарно baseline и local refs не больше двух. Для `architecture` primary обязан быть `mastery/analyst/solution-architecture.md#method`.

## Planned techniques и confirmation

Свяжи technique с вопросом, source/stakeholder, ожидаемым evidence и способом confirmation. Не заявляй formal conformance BPMN/DMN или нормативным стандартам.

## Residual risk и unresolved questions
