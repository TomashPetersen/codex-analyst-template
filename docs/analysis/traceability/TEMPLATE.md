# Traceability matrix - не канон

Храни только IDs, statuses и refs. Не копируй нормативные формулировки.

```text
source -> STK/CAP/BP -> RULE/BR -> UC/FR/NFR/DATA/INT/SYS
       -> AC -> verification evidence -> SPEC/CR
artifact -> REV(review_type/verdict)    approval_ref -> approved status
architecture proposal -> separate Plan/authority workflow -> ADR
```

| Source | STK/CAP/BP | RULE | BR | UC/FR/NFR/DATA/INT/SYS | AC | Verification evidence | REV type/verdict | Approval ref/status | SPEC/CR |
|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | |

Проверяй отдельно:

- approved BR -> STK/CAP/BP parent и AC;
- approved RULE -> BP/BR и AC;
- approved AC -> BR/RULE/UC/FR/NFR subject и factual verification evidence;
- `decision_refs` -> `REV-*`, `verification_refs` -> test/check evidence, `approval_ref` -> единственная approval authority;
- conflict, negative/error/recovery path и unresolved edge не теряются при derived view;
- architecture intent передает только SYS/DATA/INT/NFR/SPEC proposals, а confirmed architecture и ADR остаются отдельным authority workflow.
