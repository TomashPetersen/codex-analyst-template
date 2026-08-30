---
artifact_kind: business-rule
id: RULE-0001
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

# RULE-0001 - Название

## Atomic normative statement и scope

Зафиксируй subject, obligation/prohibition/permission, object и observable outcome. Не объединяй независимые rules в одну формулировку.

## Source, authority, effective context и rationale

## Conditions, exceptions, precedence и conflict resolution

## DMN-aligned decision semantics

Если применимо, укажи inputs, decision, output, linked `RULE-*` и подтвержденную conflict policy как semantic subset без заявления DMN conformance.

## Enforcement, violations, error/recovery behavior и impact

## Relations: BP, BR, UC/FR/NFR и dependencies

## Acceptance и factual verification evidence

Approved `RULE-*` имеет минимум один `AC-*` в `acceptance_refs`. Фактический результат выполнения критерия хранится отдельно в `verification_refs` связанного `AC-*`.

## Requirements verification, stakeholder validation и approval

`decision_refs` связывает rule с `REV-*`; review или validation не заменяет `approval_ref`.
