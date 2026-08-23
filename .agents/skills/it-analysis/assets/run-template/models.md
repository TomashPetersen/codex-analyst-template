---
run_id: "{{RUN_ID}}"
run_asset: models
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
proposed_ids: []
canonical_target_refs: []
---

# Models - {{RUN_TITLE}}

## SYS context: purpose, boundary, actors, components, external systems и trust boundaries

```mermaid
flowchart LR
    Actor[Actor] -->|Request| System[System under analysis]
    System -->|Result| Actor
    External[External system] <--> System
```

## DATA: owner, entities, identifiers, constraints, lifecycle, retention и classification

## SYS states, transitions, invariants и recovery

```mermaid
stateDiagram-v2
    [*] --> Created
    Created --> Processing
    Processing --> Completed
    Processing --> Failed
    Failed --> Processing: allowed retry
```

## SYS/INT sequence, alternate/error flows и trust crossings

```mermaid
sequenceDiagram
    participant Producer
    participant System
    participant Consumer
    Producer->>System: Message or operation
    System->>Consumer: Validated request
    Consumer-->>System: Result or error
    System-->>Producer: Outcome
```

## INT owners, producer/consumer, direction, protocol и operations/messages

## INT schemas, versioning, auth mechanism, privacy и data classification

## INT errors, timeout, retry, idempotency, ordering, deduplication и compensation

## INT compatibility, deprecation, SLA/SLO, observability и verification

Mermaid является portable default. Диаграмма должна иметь refs на proposed SYS/INT и не заменяет текстовую семантику.

## Assumptions и refs
