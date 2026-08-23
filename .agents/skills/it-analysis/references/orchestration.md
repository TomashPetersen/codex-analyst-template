# Orchestration

## Роли

- Lead Analyst - brief, decomposition, synthesis, ownership и единственный writer.
- `business_analyst` - stakeholders, capabilities, processes, rules, AS-IS/TO-BE.
- `system_analyst` - context, FR/NFR, data, integrations, states, sequences, constraints.
- `requirements_analyst` - normalization, use cases, acceptance и traceability.
- `analysis_reviewer` - completeness, consistency, testability, source quality и ambiguity.
- `analysis_red_team` - counterexamples, hidden assumptions, privacy/security и failure modes.
- Knowledge Curator - только closeout и отдельно разрешенный candidate/promotion lifecycle.

## Порядок исполнения

Lead создает максимум три параллельных read-only specialist assignments. `business_analyst`, `system_analyst` и `requirements_analyst` выбираются по задаче; ненужные роли не запускаются. Specialist не пишет файлы и не создает subagents.

После получения findings Lead разрешает конфликты и единолично записывает `analysis.md`, requirements/models proposals и traceability. Только после Lead synthesis отдельно выполняются `analysis_reviewer` и `analysis_red_team`. Они не редактируют синтез, а возвращают независимые findings в `review.md`. Если multi-agent недоступен, Lead последовательно применяет те же инструкции и фиксирует `sequential-fallback` в run.

Project-scoped TOML не задает модель, MCP, hooks или дополнительные права. Его единственная capability-настройка - `sandbox_mode = "read-only"`; лимит трех specialist threads задан в `.codex/config.toml`.

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
