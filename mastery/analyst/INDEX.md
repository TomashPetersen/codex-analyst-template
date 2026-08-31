# Analyst Mastery

Immutable baseline методов бизнес-, системного и solution-анализа для candidate bundle `1.1.0`. Exact inventory и hashes задаются `.template-manifest.json`; project-specific расширения живут только в [`../local/`](../local/INDEX.md).

## Selection contract

1. Определи analysis intent.
2. Выбери один основной profile и не более одного дополняющего.
3. Запиши exact file и method anchor в `brief.md` run.
4. При необходимости выбери максимум одно зарегистрированное active, непросроченное local extension с совпадающим `applies_to`.

| Closed intent ID | Основной profile |
|---|---|
| `stakeholder-analysis`, `as-is-to-be`, `gap-analysis`, `business-rule-analysis`, `solution-evaluation` | [Business analysis](business-analysis.md) |
| `requirements-elicitation`, `functional-requirements`, `acceptance-criteria`, `requirements-validation`, `requirements-verification`, `requirements-prioritization` | [Requirements engineering](requirements-engineering.md) |
| `use-case-modeling`, `business-process-analysis` | [Process and use-case modeling](process-and-use-case-modeling.md) |
| `data-analysis`, `integration-analysis`, `api-contract-analysis` | [Data and integration analysis](data-and-integration-analysis.md) |
| `nonfunctional-requirements` | [NFR and quality attributes](nfr-and-quality-attributes.md) |
| `architecture` | [Solution architecture](solution-architecture.md) |
| `traceability`, `change-impact-analysis` | [Traceability and change impact](traceability-and-change-impact.md) |
| `specification-authoring`, `specification-review` | [Specification writing](specification-writing.md) |

Для `architecture` новый profile применяет существующий `system_analyst`; отдельная роль не создается. [System analysis](system-analysis.md) используется только как supplementary profile для отдельного пробела в system context, states или sequences, когда основной profile уже выбран таблицей. Он не заменяет обязательный primary mapping.

Дополняющий profile выбирается только для отдельного пробела, который не покрывает основной метод. Он не может заменить primary mapping, расширить authority или создать второй competing owner.

## Границы

- Baseline дает воспроизводимый метод, но не authority на approval или canonical write.
- Любой run использует ровно один основной и максимум один дополняющий baseline/local method.
- `solution-evaluation` без runtime, UAT или operational evidence завершается только как `insufficient-evidence`, `provisional` или `blocked`.
- Solution architecture готовит proposal и ADR candidate, но не выбирает вариант и не принимает ADR.
- Исполняемый workflow находится в [`it-analysis`](../../.agents/skills/it-analysis/SKILL.md).
- Artifact semantics определены в [analysis contract](../../analysis/CONTRACT.md).
- Research workflow выбирает только `mastery/researcher`, analysis workflow - только `mastery/analyst`.
