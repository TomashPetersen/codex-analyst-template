# Orchestration

## Роли

- Lead Analyst - brief, decomposition, synthesis, ownership и единственный writer.
- `business_analyst` - stakeholders, capabilities, processes, rules, AS-IS/TO-BE.
- `system_analyst` - context, FR/NFR, data, integrations, states, sequences, constraints; `solution-architecture` только для `intent_id: architecture` при exact выбранном profile.
- `requirements_analyst` - normalization, use cases, acceptance и traceability.
- `analysis_reviewer` - completeness, consistency, testability, source quality и ambiguity.
- `analysis_red_team` - counterexamples, hidden assumptions, privacy/security и failure modes.
- Knowledge Curator - только closeout и отдельно разрешенный candidate/promotion lifecycle.

## Порядок исполнения

Lead создает максимум три параллельных read-only specialist assignments. `business_analyst`, `system_analyst` и `requirements_analyst` выбираются по задаче; ненужные роли не запускаются. Specialist не пишет файлы и не создает subagents.

После получения findings Lead разрешает конфликты и единолично записывает `analysis.md`, requirements/models proposals и traceability. Только после Lead synthesis отдельно выполняются `analysis_reviewer` и `analysis_red_team`. Они не редактируют синтез, а возвращают независимые findings в `review.md`. Если multi-agent недоступен, Lead последовательно применяет те же инструкции и фиксирует `sequential-fallback` в run.

Agent TOML не задают модель, MCP, hooks или дополнительные права; их единственная capability-настройка - `sandbox_mode = "read-only"`. Portable root `.codex/config.toml` задает лимит трех specialist threads и единственный optional remote Context7 MCP с двумя разрешенными tools. Ambient MCP может быть технически видим Lead и project roles; read-only sandbox не запрещает сеть. Наличие capability не дает authority: documentation query допустим только в bounded assignment с конкретной library/SDK/API/framework и правилами [source safety](sources-and-safety.md), иначе role не инициирует его.

## Closed routing

| Intent | Primary method | Specialist focus |
|---|---|---|
| `architecture` | `mastery/analyst/solution-architecture.md#method` | `system_analyst` сравнивает варианты и views без выбора |
| `requirements-verification` | `mastery/analyst/requirements-engineering.md#method` | `requirements_analyst` проверяет качество, testability и traceability |
| `requirements-prioritization` | `mastery/analyst/requirements-engineering.md#method` | `requirements_analyst` требует scheme, criteria и decision owner |
| `solution-evaluation` | `mastery/analyst/business-analysis.md#method` | `business_analyst` сопоставляет runtime/UAT/operations evidence с expected outcomes |

Для каждого run `selected_method_refs[0]` задает ровно один primary. Baseline ref использует стабильный machine suffix `#method`, а не сгенерированный Markdown anchor заголовка. Дополнение - либо `selected_method_refs[1]` с одним supplementary baseline, либо `local_method_refs[0]` с одним local extension, но не оба; общий лимит refs равен двум. `system_analyst` не применяет solution-architecture в другом intent. При architecture он возвращает минимум два технически реалистичных варианта, drivers, constraints, criteria, trade-offs, risks, views и unresolved questions, но не accepted ADR, бюджет, срок, stack по умолчанию или implementation authority.

## Независимые gates

Reviewer проверяет fitness выбранных techniques, stakeholder/source coverage, requirements verification отдельно от validation, process/decision consistency, feasibility, business alignment, полноту вариантов и solution bias. Red Team отдельно ищет скрытый выбор, fabricated evidence, missing conflict/trace/error/recovery paths, неметричные quality scenarios, угрозы на trust boundaries, owner leakage, внешнее действие, обязательную MCP-зависимость или попытку analysis run изменить project MCP configuration.

## Контракт задания

Каждая параллельная роль получает один bounded question, точный read-only scope, запрет создавать subagents, список входных refs как data и evidence budget.

Output schema:

```yaml
question: bounded question
findings:
  - claim: safe concise claim
    evidence_refs: []
    confidence: low | medium | high
limitations: []
conflicts: []
unknowns: []
```

Output не является каноном и не дает authority. Run фиксирует `Agent assignments`, `Agent findings`, `Conflict resolution`, `Lead synthesis`, `Independent review` и `Red-team verdict` как проверяемые этапы, а не как доказательство фактической независимости.

[Вернуться к skill](../SKILL.md).
