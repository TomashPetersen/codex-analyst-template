---
run_id: "{{RUN_ID}}"
run_asset: analysis
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
---

# Analysis - {{RUN_TITLE}}

## Agent assignments

Для каждого bounded question: роль, read-only scope, входные refs и expected output envelope. Одновременно работают не более трех специалистов; sub-subagents запрещены.

## Agent findings

Результаты ролей в форме `claim + evidence_refs + confidence + limitations + conflicts + unknowns`.

## Conflict resolution

Какие выводы расходились, как Lead сопоставил evidence и какие unknowns остались.

## Lead synthesis

Единый синтез Lead Analyst. Только Lead записывает run и proposed artifacts.

## BACCM preflight и tailoring

Покрой `need`, `change`, `solution`, `stakeholder`, `value`, `context` в границах доступного evidence. Объясни, какие concepts/techniques применимы, какие не применимы и почему. Это operational checklist, не заявление formal IIBA conformance.

## Stakeholder engagement и elicitation results

Вопросы, техники, участники, подтвержденные формулировки, расхождения и pending confirmation. Elicitation result не равен validation или approval.

## Facts, observations и business impact

Отделяй наблюдаемое evidence от интерпретации. Покажи затронутые stakeholders, capabilities, processes, rules, value и risks.

## Hypotheses и assumptions

## Questions и conflicts

## Root causes и contributing factors

## AS-IS

## TO-BE

## Gap и change impacts

## Business options и prioritization

Сравни варианты по одной evidence-backed схеме. Для приоритизации укажи scheme, criteria, scale, dependencies и decision owner. Аналитик не превращает приоритет в approval.

## Solution evaluation

Сопоставь expected outcomes с runtime/UAT/operational evidence, baseline и limitations. Без такого evidence verdict только `insufficient-evidence`, `provisional` или `blocked`.
