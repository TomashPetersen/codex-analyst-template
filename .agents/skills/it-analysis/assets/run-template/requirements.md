---
run_id: "{{RUN_ID}}"
run_asset: requirements
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
proposed_ids: []
canonical_target_refs: []
---

# Requirements - {{RUN_TITLE}}

## Working proposals и proposed owner IDs

Используй canonical-form IDs или безопасные локальные labels только как proposals. Этот файл не становится canonical owner.

## STK proposals

Роль, concern/need, influence, responsibility, conflicts, engagement и confirmation status.

## CAP proposals

Capability, accountable owner, intended outcome/value, current/target state, dependencies и evidence.

## BP proposals

Process owner, trigger/event, start/end criteria, participants, AS-IS/TO-BE, steps, decisions, exceptions/recovery, controls, observed KPI evidence и gaps. Не изобретай KPI.

## RULE proposals

Atomic condition/constraint, source/owner, applicability, exceptions, conflicts и examples. RULE связывается с BP или BR и имеет AC proposal; связь не прячется внутри prose.

## BR proposals

Business need/outcome, минимум один STK/CAP/BP parent, rationale, constraints, priority, AC proposal и отдельная validation need.

## Representation selection gate

Выбери narrative, BPMN-aligned process semantics или DMN-aligned decision semantics по характеру вопроса. BPMN/DMN здесь являются ограниченными semantic subsets без заявления formal conformance.

## UC proposal: goal, boundary, actors, trigger и preconditions

## UC main flow

## UC alternate flows

## UC error/recovery flows

## UC postconditions, RULE/BP refs и acceptance

## FR proposal: observable behavior, inputs, outputs, state change, rules и failure behavior

## NFR proposal: source, stimulus, environment, affected artifact, response, response measure с metric/threshold/unit, priority/decision owner и verification method/test condition

## AC proposal: parent BR/RULE/UC/FR/NFR, deterministic pass condition, test data, observable result и verification method

На proposal stage укажи требуемый способ проверки и evidence gap. Не создавай factual `verification_ref` до фактического выполнения проверки; для approved handoff такой evidence уже обязателен.

## Positive, negative, boundary, error и recovery examples

## Sources, parents и rationale

## Prioritization scheme и decision owner

Scheme, criteria, scale, dependencies, conflicts, result и exact decision owner. При отсутствии scheme или owner приоритизация остается blocked.

## Requirements verification results

Однозначность, полнота в границах scope, consistency, feasibility, testability, traceability, defects и `REV-*` decision ref.

## Stakeholder validation results

Need/intended-use fit, confirmed stakeholders/evidence, dissent, limitations и отдельный `REV-*` decision ref.

## Verification evidence, AC и approval boundary

`verification_refs` содержит фактические проверки; `decision_refs` ведет к `REV-*`; `approval_ref` является единственной approval authority. Verification, validation и approval не взаимозаменяемы.

Для approved handoff обязательны relations `BR -> STK/CAP/BP + AC`, `RULE -> BP/BR + AC`, `AC -> BR/RULE/UC/FR/NFR + factual verification_refs`. Prose `not-applicable` не заменяет edge.

## Lifecycle и change relations

Draft/in-review proposal, supersedes/dependencies, change impact и follow-up owner refs.

## Conflicts и unresolved questions
