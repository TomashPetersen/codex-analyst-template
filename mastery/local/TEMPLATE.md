---
mastery_contract_version: 2
method_id: project-method-id
method_kind: heuristic | checklist | workflow | standard
summary: Короткое описание повторяемого результата метода
owner_scope: project
applies_to:
  - planning
status: active | deprecated | superseded
source_refs:
  - knowledge/candidates/YYYY/KC-YYYYMMDD-HHmmss-8hex.md
verified_at: YYYY-MM-DD
review_due: YYYY-MM-DD
supersedes: null
---

# Название локального метода

## Purpose

Какой повторяемый результат дает метод и в каких границах он полезен.

## Use when

Наблюдаемые условия применения и релевантные intent IDs из `mastery/INTENTS.json`.

## Do not use when

Исключения, стоп-условия и ситуации, где нужен другой метод.

## Inputs

Минимальные входные артефакты, источники и ограничения.

## Workflow

Короткая воспроизводимая последовательность действий.

## Quality gate

Проверяемые условия достаточности результата.

## Failure modes

Типичные ошибки и безопасный fallback.

## Provenance

Applied method candidate указан в `source_refs`, а видимый backlink создается в derived registry. Candidate хранит learning evidence и authority; метод не копирует полный plan, diff, код, тесты или логи.

## Navigation

- [Local Mastery registry](INDEX.md)
