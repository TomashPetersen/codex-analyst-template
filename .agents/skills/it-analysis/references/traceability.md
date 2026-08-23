# Traceability

## Обязательный граф

```text
source -> STK/CAP/BP/problem -> BR
       -> UC/FR/NFR/DATA/INT/SYS
       -> AC или verification -> SPEC
       -> ADR или CR -> REV/decision
```

## Gate

- Каждый approved artifact имеет source.
- FR/NFR имеет BR или применимый STK/CAP parent и acceptance или verification.
- NFR содержит metric, threshold, unit и test condition.
- INT связан с DATA и SYS.
- SPEC агрегирует exact refs и не копирует нормативный текст.
- Supersedes graph не имеет missing nodes, self-edge или cycle.
- Canonical owner file зарегистрирован thematic index и достижим от root.

Machine refs считаются от repository root. Markdown links считаются от содержащего файла. Не подставляй одну форму вместо другой. Матрица хранит только IDs, statuses и refs.

После разрешенного handoff обнови [`knowledge/graph/INDEX.md`](../../../../knowledge/graph/INDEX.md). Граф помогает искать backlinks и orphans, но не заменяет эту traceability-схему и owner artifacts.

[Основной контракт](../../../../analysis/CONTRACT.md) - [Вернуться к skill](../SKILL.md).
