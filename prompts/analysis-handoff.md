---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: existing
---

# Разрешенная передача аналитики в канон

```text
Plan: <PLAN_REF>. Run: <RUN_REF>. Authority: <AUTHORITY_REF>.

Полностью прочитай переданный <PLAN_REF>, его Resume checkpoint,
analysis/CONTRACT.md, run и точные owner indexes. Проверь plan через
scripts/assert-plan-resume.ps1. Не создавай новый plan и не подменяй прямое
разрешение ссылкой на ADR, review или вывод агента.

Сначала получи независимые analysis_reviewer и analysis_red_team findings.
Lead Analyst как единственный writer переносит только подтвержденные statements
в единственный owner artifact, сохраняет provenance, traceability, backlink и
authority_ref. Обнови knowledge graph и plan checkpoint, затем запусти все
релевантные gates. Не выполняй commit, push, tag или deploy.
```
