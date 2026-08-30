---
run_id: "{{RUN_ID}}"
run_asset: review
run_status: open
title: "{{RUN_TITLE}}"
task_ref: "{{TASK_REF}}"
created_at: "{{CREATED_AT}}"
review_outcome: pending
unresolved_blockers: []
---

# Review - {{RUN_TITLE}}

## Run review outcome

Зафиксируй общий `review_outcome` run во frontmatter и раскрой rationale, evidence, limitations и blockers ниже. Этот working asset не является canonical `REV-*` и не дублирует его machine-readable body.

Если intent равен `requirements-verification`, `requirements-validation` или `solution-evaluation`, перечисли proposed subject/evidence refs и закрытый `review_type` для возможного canonical `REV-*`. Сам `review_record` создается только в owner artifact `docs/analysis/reviews/REV-*` при разрешенном handoff.

## Independent review

Reviewer проверяет Lead synthesis после его завершения и не редактирует исходный analysis.

## Red-team verdict

Red Team после синтеза ищет counterexamples, скрытые assumptions, privacy/security и failure modes.

## Reviewer independence и checked refs

## Technique fitness и source/stakeholder coverage

## Contradictions, ambiguity, completeness, feasibility и testability

## Requirements verification, stakeholder validation и approval separation

## Process/decision consistency и error/recovery coverage

## Business alignment и solution evaluation evidence

Для solution evaluation проверь runtime/UAT/operational evidence, baseline/condition и limitations. Без него verdict только `insufficient-evidence`, `provisional` или `blocked`. Положительный verdict использует reserved runtime/baseline `evidence:*` refs только как classification и дополнительно указывает registered source, collection method, фактический artifact и limitations; token сам по себе не доказывает actuality.

## Architecture option completeness и solution bias

Проверь drivers/constraints, минимум два реалистичных options, единые criteria, trade-offs, risks, quality scenarios, views, assumption validation и отсутствие hidden selection/ADR acceptance.

## Security и privacy

## Red-team findings и counterexamples

Проверь fabricated evidence, missing conflict/trace edge/error path, неметричный quality scenario, owner leakage, external action и MCP dependency/configuration.

## Actions, owners и unresolved blockers
