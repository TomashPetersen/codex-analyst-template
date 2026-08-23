---
artifact_kind: system-model
id: SYS-0001
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

# SYS-0001 - Название

Выбери ровно один kind: DATA, INT или SYS, затем синхронно измени `artifact_kind`, ID, filename и применимые разделы.

## DATA: owner, entities, fields, identifiers, constraints, lifecycle, retention и classification

## INT: scope, producer, consumer, protocol и direction

## INT: operations/messages, versioning, schema и optional OpenAPI/AsyncAPI attachment

## INT: auth mechanism, trust boundary, privacy и data classification

## INT: errors, timeout, retry, idempotency, ordering, deduplication и compensation

## INT: compatibility, deprecation, SLA/SLO, observability и verification

## SYS: boundary, actors, components, responsibilities и external systems

## SYS: states, transitions, invariants и recovery

## SYS: sequences, alternate/error flows, timeout/retry/compensation и trust boundaries

```mermaid
sequenceDiagram
    participant A as Участник A
    participant B as Участник B
    A->>B: Сообщение
    B-->>A: Результат или ошибка
```

```mermaid
stateDiagram-v2
    [*] --> Created
    Created --> Processing: команда принята
    Processing --> Completed: результат подтвержден
    Processing --> Failed: ошибка или timeout
    Failed --> Processing: допустимый retry
    Completed --> [*]
```

Диаграммы только визуализируют семантику сообщений, ошибок, состояний и переходов. Нормативное описание остается в соответствующем `SYS-*` или `INT-*`.

## Assumptions, risks, relations и verification
