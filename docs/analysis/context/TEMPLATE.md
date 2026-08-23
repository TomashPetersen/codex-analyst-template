# Context view - не канон

Этот файл является справочным block-template для раздела внутри canonical `SYS-*`. Не создавай по нему отдельный context artifact: он не создает canonical owner file и не заменяет `SYS-*`.

## Purpose и boundary

## Actors и external systems

## Inputs, outputs и trust boundaries

## States, transitions и invariants

## Main sequence

Для каждого message укажи sender, receiver, sync/async, protocol, payload ref и state effect.

## Alternate, error, timeout, retry и compensation flows

## Mermaid diagram

```mermaid
sequenceDiagram
    participant Actor
    participant System
    Actor->>System: Request
    alt Успех
        System-->>Actor: Result
    else Ошибка
        System-->>Actor: Safe error
    end
```

## Refs на SYS и INT
