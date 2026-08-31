# Traceability

## Обязательный граф

```text
source -> STK/CAP/BP/RULE/problem -> BR
       -> UC/FR/NFR/DATA/INT/SYS
       -> AC и verification evidence -> SPEC
       -> CR или proposed ADR candidate -> REV/decision

stakeholder need -> validation evidence -> REV(requirements-validation)
subject -> verification evidence -> REV(requirements-verification)
runtime/UAT/operations -> REV(solution-evaluation)
approved artifact -> approval_ref(user authority)
```

## Gate

- Каждый approved artifact имеет source, applicable parent, проверяемый outcome и отдельный `approval_ref`.
- Каждый approved `BR` имеет parent edge минимум к одному `STK`, `CAP` или `BP` и acceptance edge к `AC`; его approval не выводится из validation.
- Каждый approved `RULE` имеет relation edge к `BP` или `BR` и acceptance edge к `AC`.
- Каждый approved `AC` имеет parent edge к `BR`, `RULE`, `UC`, `FR` или `NFR` и непустой factual `verification_ref`.
- FR/NFR имеет BR или применимый STK/CAP parent и `AC` либо фактический `verification_ref`.
- NFR содержит source, stimulus, environment, affected artifact, response, response measure, priority и verification method.
- INT связан с DATA и SYS.
- SPEC агрегирует exact refs и не копирует нормативный текст.
- `decision_refs` ведет к `REV-*`; `verification_refs` не содержит stakeholder confirmation или approval; `approval_ref` не содержит тестовый result.
- Supersedes graph не имеет missing nodes, self-edge или cycle.
- Canonical owner file зарегистрирован thematic index и достижим от root.

Missing conflict edge, error/recovery path, validation evidence, verification/AC или authority отмечается как blocker, а не заполняется предположением.
Prose-исключение `not-applicable` не заменяет обязательные edges approved BR, RULE или AC.

Machine refs считаются от repository root. Markdown links считаются от содержащего файла. Не подставляй одну форму вместо другой. Матрица хранит только IDs, statuses и refs.

После разрешенного handoff обнови [`knowledge/graph/INDEX.md`](../../../../knowledge/graph/INDEX.md). Граф помогает искать backlinks и orphans, но не заменяет эту traceability-схему и owner artifacts.

[Основной контракт](../../../../analysis/CONTRACT.md) - [Вернуться к skill](../SKILL.md).
