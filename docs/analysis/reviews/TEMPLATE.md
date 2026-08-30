---
artifact_kind: review-decision
id: REV-0001
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

# REV-0001 - Название

## Review record

Сохрани ровно один machine-readable JSON-блок с top-level key `review_record` и выбери один closed `review_type`: `requirements-verification`, `requirements-validation` или `solution-evaluation`. Closed `verdict`: `pass`, `pass-with-actions`, `reject`, `insufficient-evidence`, `provisional` или `blocked`.

```json
{
  "review_record": {
    "review_type": "requirements-verification",
    "subject_refs": ["docs/analysis/requirements/fr-0001-example.md"],
    "evidence_refs": ["tests/example-result.json"],
    "verdict": "pass-with-actions",
    "limitations": ["Не выполнена проверка в production environment"]
  }
}
```

## Scope и reviewer independence

## Subject, source и evidence coverage

`subject_refs` и `evidence_refs` из JSON должны соответствовать объяснению в body и machine refs artifact. Не подставляй plan, мнение или ожидаемый AC вместо фактического evidence.

## Findings: severity и evidence

## Requirements verification: ambiguity, completeness, consistency, feasibility и testability

Заполняй для `requirements-verification`; этот verdict не подтверждает stakeholder need.

## Requirements validation: stakeholder, method, confirmation и limitations

Заполняй для `requirements-validation`; stakeholder confirmation не дает approval authority.

## Solution evaluation: baseline, runtime/UAT/operational evidence и business outcome

Без runtime, UAT или operational evidence и baseline verdict ограничен значениями `insufficient-evidence`, `provisional` или `blocked`. Для `pass` или `pass-with-actions` используй в `evidence_refs` и `verification_refs` один и тот же runtime-class ref `evidence:runtime:<id>`, `evidence:uat:<id>` или `evidence:operational:<id>` и один и тот же `evidence:baseline:<id>`.

Reserved `evidence:*` ref только классифицирует evidence для machine gate. Он не доказывает, что измерение существует или достоверно. Укажи registered source, provenance, collection method, фактический проверочный artifact и limitations; не создавай token без такой основы.

## Business alignment, feasibility, security, privacy и residual risk

## Verdict, rationale и limitations

## Actions и owners

## Approval separation

`decision_refs` связывает subject artifact с этим `REV-*`; factual checks остаются в `verification_refs`. Review record не меняет status на `approved` и не заменяет `approval_ref`.
