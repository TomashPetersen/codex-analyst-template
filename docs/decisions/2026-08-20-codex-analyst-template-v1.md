---
artifact_kind: decision
status: accepted
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .template-manifest.json
  - AGENTS.md
  - analysis/CONTRACT.md
  - business/analysis/INDEX.md
  - docs/analysis/INDEX.md
  - mastery/analyst/INDEX.md
supersedes: []
blocked_reason: null
---

# Решение: аналитический шаблон как единый проверяемый контур

## Контекст и владелец

Публичный шаблон должен поддерживать полный системный и бизнес-анализ, но не наследовать предметные данные, историю или настройки конкретного проекта. Решение принято в рамках [source plan](../../plans/2026-08-20-codex-analyst-template-v1.md) по прямому запросу на создание шаблона.

## Решение

- Codex-first control plane, Plan v2, distribution и cross-platform bootstrap образуют базовый слой.
- Formal-analysis восстанавливается из неизменяемого release baseline, а универсальные улучшения проходят ручной нейтральный merge.
- Lead Analyst является единственным writer. До трех project-scoped специалистов работают read-only, затем отдельно выполняются Reviewer и Red Team.
- Один bounded run не требует Plan v2. Программа runs, значимый canonical handoff, архитектурное изменение, реализация и выпуск требуют plan.
- Product, core business, architecture и formal-analysis остаются непересекающимися owner zones.
- Approved formal-analysis входит в derived knowledge graph; runs, plans, RAW и retrospectives не становятся nodes.
- Внешняя память, MCP, plugins, connectors, automations, secrets и модели не преднастраиваются.
- Consumer строится exact allowlist-ом. Source-only история, заполненные data zones и release operations в payload не входят.

## Рассмотренные альтернативы

- Копирование целого рабочего продукта отклонено из-за предметного канона, истории и риска чувствительных следов.
- Один универсальный агент-writer отклонен как менее проверяемый для независимых аналитических вопросов и review.
- Автоматический handoff или promotion отклонен, потому что меняет канон без прямой authority.
- Обязательный plan для каждого одиночного run отклонен как лишняя стоимость для bounded анализа.

## Последствия и риски

- Шаблон крупнее универсального project starter, зато готов к полноценному аналитическому циклу.
- Статический TOML gate защищает role contract, но доступность multi-agent зависит от среды Codex; последовательный fallback обязателен.
- Windows проверяется локально, а фактический macOS runner доступен только после публикации workflow.
- Изменение baseline Mastery требует пересчета manifest hashes и полного release-профиля.

## Проверка

- Formal-analysis self-test подтверждает исходные 86 сценариев и интеграционные ограничения.
- Static role gate подтверждает пять read-only ролей и concurrency cap 3.
- Consumer-boundary test требует formal-analysis и `.codex`, исключая source-only и заполненные data artifacts.
- Sanitizer проверяет весь source и portable consumer inventory.
- Structure вызывает canon, analysis, agents, mastery, graph, plans, knowledge и privacy gates.

## Откат или замена

До первого commit шаблон можно удалить как отдельную рабочую копию после явного подтверждения точного пути. После выпуска новая несовместимая архитектура получает отдельный plan, ADR и versioned release; опубликованный tag не переписывается.

## Связи

- План: [Codex Analyst Template v1.0.0](../../plans/2026-08-20-codex-analyst-template-v1.md).
- Контракт source: [TEMPLATE.md](../../TEMPLATE.md).
- Аналитический контракт: [analysis/CONTRACT.md](../../analysis/CONTRACT.md).
- Обратные ссылки на примененные candidates: нет.
