---
artifact_kind: functional-requirement
id: FR-0001
status: draft
owner_scope: project
capture_basis: repo-derived
provenance_refs: []
source_refs: []
parent_refs: []
related_refs: []
decision_refs: []
acceptance_refs: []
verification_refs: []
supersedes_ref: null
approval_ref: null
approved_at: null
approved_by: null
created_at: YYYY-MM-DD
verified_at: YYYY-MM-DD
review_due: YYYY-MM-DD
---

# FR-0001 - Название

Выбери ровно один kind: UC, FR, NFR или AC, затем синхронно измени `artifact_kind`, ID, filename и применимые разделы.

## Common: statement, source, rationale, glossary terms и parents

Разделяй atomic statements, используй один термин для одного понятия и связывай `parent_refs` с business need, rule или subject requirement. Неизвестное не заменяй допущением.

## Common: representation choice, priority scheme и decision owner

Зафиксируй, почему выбран UC, FR, NFR или AC. Priority требует названной scheme, rationale и decision owner.

## UC: goal, actors, trigger, preconditions и success postconditions

## UC: main, alternate, negative, boundary, error и recovery flows

Свяжи каждый применимый branch с `RULE-*`, observable result и postcondition.

## FR: shall behavior, trigger, inputs, outputs, state change и RULE refs

## FR: negative, boundary, error, timeout, retry и recovery behavior

## NFR: quality scenario

- Source:
- Stimulus:
- Environment:
- Affected artifact:
- Response:
- Response measure with threshold and unit:
- Priority and decision owner:
- Verification method and test condition:

Не изобретай threshold. Неметричный response measure не является проверяемым quality scenario.

## AC: deterministic condition и observable result

Используй Given/When/Then или эквивалентное deterministic pass condition. Укажи test data, positive, negative, boundary, error и recovery examples, когда они применимы.

## AC: subject parents и execution evidence

Approved `AC-*` связан через `parent_refs` минимум с одним `BR-*`, `RULE-*`, `UC-*`, `FR-*` или `NFR-*`; фактический результат исполнения находится в `verification_refs`.

## Normalization findings, conflicts, assumptions и unresolved questions

## Requirements verification result и evidence

## Stakeholder validation result и evidence

## Decision refs и approval separation

`decision_refs` связывает artifact с `REV-*`, `verification_refs` хранит фактические test/check evidence, а `approval_ref` остается единственной approval authority.
