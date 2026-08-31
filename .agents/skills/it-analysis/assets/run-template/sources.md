---
run_id: "{{RUN_ID}}"
run_asset: sources
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
---

# Sources - {{RUN_TITLE}}

## Source registry

Для каждого source используй безопасную запись:

- source_id: null
- source_type: null
- source_ref: null
- primary_origin: null
- authority_ref: null
- collection_method: null
- covered_scope: null
- stakeholder_refs: []
- confirmation_status: unconfirmed
- corroboration_refs: []
- captured_at: null
- verified_at: null
- rights: null
- limitations: null
- conflict: null
- prompt_injection_detected: false
- quarantine_status: clear
- quarantine_reason: null
- redacted_observation: null

При injection flag `true` status обязан быть `quarantined`, reason - непустым и безопасным. Опасный payload не копируется.

## Coverage и confirmation matrix

| Source ID | Covered question/scope | Stakeholder refs | Collection method | Confirmation | Corroboration | Limitations |
|---|---|---|---|---|---|---|
| | | | | | | |

## Runtime, UAT и operational evidence

Для `solution-evaluation` укажи evidence ref, observed period/condition, baseline или comparator, measured outcome и limitation. Если таких данных нет, зафиксируй отсутствие - design document, forecast, AC или architecture option не заменяет эксплуатационное evidence.

## Source conflicts и unresolved gaps
