---
run_id: "{{RUN_ID}}"
run_asset: traceability
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
traceability_outcome: pending
---

# Traceability - {{RUN_TITLE}}

Храни IDs, relations, statuses и refs, не полный нормативный текст.

| Source | STK/CAP/BP/RULE | BR | UC/FR/NFR/DATA/INT/SYS | AC | verification_refs | validation REV | SPEC/CR/proposed ADR | decision_refs | approval_ref/status |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

## Relation semantics

```text
source -> STK/CAP/BP/RULE -> BR -> UC/FR/NFR/DATA/INT/SYS
subject -> AC
subject -> verification_refs -> factual test/check evidence
subject -> decision_refs -> REV(requirements-verification)
stakeholder need -> confirmation evidence -> REV(requirements-validation)
runtime/UAT/operations -> REV(solution-evaluation)
artifact -> decision_refs -> REV
approved artifact -> approval_ref -> direct user authority
```

`verification_refs` хранит фактическое test/check evidence. `decision_refs` связывает artifact с `REV-*`. `approval_ref` не выводится из validation, verification, recommendation или ADR candidate.

Strict approved edges: `BR -> STK/CAP/BP + AC`; `RULE -> BP/BR + AC`; `AC -> BR/RULE/UC/FR/NFR + factual verification_refs`. Пустой edge или prose `not-applicable` не проходит handoff gate.

## Architecture option и view coverage

Drivers/constraints -> минимум два options -> criteria/trade-offs/risks -> SYS/DATA/INT/NFR/SPEC proposals -> proposed strategy. Отсутствующий edge или скрытый architecture choice является blocker.

## Missing edges и blockers

Отдельно перечисли missing conflict edge, positive/negative/boundary/error/recovery path, неподтвержденное validation evidence, отсутствующий verification/AC и отсутствующую authority. Не заполняй пробелы fabricated evidence.
