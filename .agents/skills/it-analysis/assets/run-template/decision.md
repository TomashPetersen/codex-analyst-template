---
run_id: "{{RUN_ID}}"
run_asset: decision
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
decision_outcome: pending
capture_basis: null
provenance_refs: []
canonical_target_refs: []
authority_ref: null
knowledge_outcome: null
candidate_ids: []
affected_canon: []
blocked_reason: null
---

# Decision - {{RUN_TITLE}}

## Recommendation proposal и rationale

Сформулируй recommendation как предложение, указав evidence, criteria, trade-offs, limitations, residual risks и unresolved questions. Не скрывай выбор в словах `approved`, `selected`, `final` или эквивалентах без authority.

## Blockers и authority status

## Delivery readiness

Что аналитически готово, что остается `insufficient-evidence`/`provisional`/`blocked`, какие verification/validation/approval refs отсутствуют. Для solution evaluation требуется runtime/UAT/operational evidence.

## Dependencies и follow-up refs

Перечисли владельцев, зависимости, последующие analysis/Plan/ADR/CR refs и условия продолжения. Не помещай сюда implementation plan, decomposition, бюджет или schedule - реализация ведется отдельным Plan v2.

## Proposed canonical handoff

Перечисли exact targets либо зафиксируй `no-change`. Этот run ничего не утверждает и не записывает в канон автоматически.

Для `architecture` targets ограничены существующими `SYS`, `DATA`, `INT`, `NFR` и `SPEC`. Proposed strategy или ADR candidate не становится подтвержденной архитектурой и не принимает ADR.

## Knowledge closeout
