# Analyst Mastery

Immutable baseline методов бизнес- и системного анализа для этой версии шаблона. Exact inventory и hashes задаются `.template-manifest.json`; project-specific расширения живут только в [`../local/`](../local/INDEX.md).

## Selection contract

1. Определи analysis intent.
2. Выбери один основной profile и не более одного дополняющего.
3. Запиши exact file и method anchor в `brief.md` run.
4. При необходимости выбери максимум одно зарегистрированное active, непросроченное local extension с совпадающим `applies_to`.

| Closed intent ID | Основной profile |
|---|---|
| `stakeholder-analysis`, `as-is-to-be`, `gap-analysis`, `business-rule-analysis` | [Business analysis](business-analysis.md) |
| `requirements-elicitation`, `functional-requirements`, `acceptance-criteria`, `requirements-validation` | [Requirements engineering](requirements-engineering.md) |
| `use-case-modeling`, `business-process-analysis` | [Process and use-case modeling](process-and-use-case-modeling.md) |
| `data-analysis`, `integration-analysis`, `api-contract-analysis` | [Data and integration analysis](data-and-integration-analysis.md) |
| `nonfunctional-requirements` | [NFR and quality attributes](nfr-and-quality-attributes.md) |
| `traceability`, `change-impact-analysis` | [Traceability and change impact](traceability-and-change-impact.md) |
| `specification-authoring`, `specification-review` | [Specification writing](specification-writing.md) |

Для system context, states и sequences основным остается [System analysis](system-analysis.md); конкретный closed intent выбирается по создаваемому артефакту, например `integration-analysis`, `nonfunctional-requirements` или `functional-requirements`.

## Границы

- Baseline дает воспроизводимый метод, но не authority на approval или canonical write.
- Исполняемый workflow находится в [`it-analysis`](../../.agents/skills/it-analysis/SKILL.md).
- Artifact semantics определены в [analysis contract](../../analysis/CONTRACT.md).
- Research workflow выбирает только `mastery/researcher`, analysis workflow - только `mastery/analyst`.
