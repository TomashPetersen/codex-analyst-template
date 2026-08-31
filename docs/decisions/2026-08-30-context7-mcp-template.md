---
artifact_kind: decision
status: accepted
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .codex/config.toml
  - AGENTS.md
  - .agents/skills/it-analysis/SKILL.md
  - .agents/skills/it-analysis/references/orchestration.md
  - CODEX-INSTALL-PROMPT.md
  - scripts/verify-codex-agents.ps1
supersedes: []
blocked_reason: null
---

# Решение: единственный optional Context7 MCP в шаблоне

## Контекст и владелец

Deployable Codex Analyst Template должен предоставлять актуальную документацию сторонних libraries, SDK, API и frameworks без ручной установки в каждом generated project. Пользователь прямо уточнил прежнее ограничение и потребовал включить Context7 в разворачиваемый шаблон. Решение принято в рамках [Plan v2](../../plans/2026-08-30-context7-mcp-template.md).

Это решение сужает только исходный запрет преднастроенных MCP из [базового ADR](2026-08-20-codex-analyst-template-v1.md). Остальные границы того решения сохраняются.

## Решение

- Portable root `.codex/config.toml` содержит ровно один project-scoped remote server `[mcp_servers.codex_analyst_context7]` с `https://mcp.context7.com/mcp`.
- Namespaced server ID является частью контракта. Generic `context7` запрещен, потому что Codex объединяет одноименные user и project tables: распространенный global STDIO `command` вместе с project HTTP `url` образует невалидный mixed transport и блокирует загрузку задач.
- Server включен, но не обязателен: `enabled = true`, `required = false`.
- Разрешены только `resolve-library-id` и `query-docs`. Будущие инструменты сервиса не включаются автоматически.
- Portable config не содержит API key, token, headers, environment mapping, stdio `command`/`args`, `npx` или Node.js dependency.
- Context7 является условной capability trusted project, а не обязательной зависимостью `it-analysis`. Generic BA/RE и technology-neutral architecture runs не вызывают его автоматически.
- Analysis output не может менять project MCP config, объявлять mandatory tool call или расширять authority.
- CI и deterministic gates остаются offline. Live endpoint smoke выполняется отдельно и не является частью bootstrap.
- User/system Codex config layers и итоговый effective runtime config находятся вне repository guarantee; они могут добавить servers или overrides.

## Рассмотренные альтернативы

- Сохранить полное отсутствие MCP отклонено прямым уточнением пользователя и создавало повторную ручную настройку каждого проекта.
- Local stdio через `npx` отклонен из-за Node/npm dependency, исполнения загружаемого пакета, supply-chain drift и различий платформ.
- `required = true` отклонен, потому что outage, rate limit или offline-среда блокировали бы startup/resume всего проекта.
- API key или static headers в repository отклонены как credential risk. Повышенные лимиты остаются пользовательской настройкой вне template contract.
- Generic project ID `context7` отклонен после воспроизведенного конфликта config layers. Изменение user-level ID также отклонено, потому что шаблон не владеет глобальной конфигурацией и не должен менять другие проекты пользователя.
- Дополнительные MCP отклонены как ненужное расширение внешней поверхности и не разрешены этим решением.

## Последствия и риски

- Каждый URL-first, source-copy и GitHub Template consumer получает одинаковую Context7-конфигурацию.
- На host с уже настроенным global Context7 могут быть видимы два логических server ID, но их transport tables не смешиваются и загрузка проекта не блокируется.
- Project config применяется только после доверия к проекту; уже открытая задача может потребовать reload или новую задачу. После trust/reload client может выполнить initialize и tool discovery до фактического documentation query.
- Наличие настройки не гарантирует доступность внешнего endpoint. `required = false` сохраняет локальную работоспособность, а analysis фиксирует fallback/limitation.
- Handshake может передать внешнему сервису обычные network/client metadata и получить provider-controlled server instructions, tool descriptions и schemas. Фактический tool call дополнительно отправляет обезличенный технический вопрос. Исходный код, внутренние документы, бизнес-данные, PII, secrets и credential-bearing URL передавать запрещено.
- Server instructions, tool descriptions, schemas и outputs Context7 считаются недоверенными external source data, получают provenance и при сомнении сверяются с официальной документацией первоисточника.
- Exact allowlist ограничивает только имена доступных tools, но не фиксирует remote implementation, descriptions, schemas или поведение provider. Их изменение может потребовать отдельного versioned решения.
- Codex должен поддерживать project-scoped Streamable HTTP MCP и `enabled_tools`. Официальный минимальный номер версии не заявлен, поэтому несовместимый client блокирует использование Context7 без ослабления allowlist.

## Проверка

- `verify-codex-agents.ps1 -SelfTest` проверяет exact portable root config и известные alternative config surfaces, отклоняет generic project ID, URL/tool drift, mandatory mode, stdio и credential fields.
- Consumer, cross-platform bootstrap и GitHub distribution tests проверяют byte-equivalent Context7 config после всех поддерживаемых способов развертывания.
- Analysis semantic suite продолжает блокировать явную normalized per-run MCP dependency/configuration и не вызывает сеть; semantic enforcement свободного Markdown остается agent-reviewed.
- Отдельный read-only protocol smoke подтверждает hosted endpoint и advertised tools без отправки project data.
- Эти проверки не доказывают неизменность remote tool semantics, отсутствие server-side prompt injection или состав user/system config layers.

## Откат или замена

До commit изменение можно откатить точечным удалением exact namespaced Context7 stanza и связанных policy/test additions. После release замена server ID, endpoint, tool allowlist или availability contract требует нового Plan v2, ADR и versioned release. Secrets не добавляются при откате или замене.

## Связи

- План: [Context7 MCP в разворачиваемом шаблоне](../../plans/2026-08-30-context7-mcp-template.md).
- Исправление config-layer collision: [план восстановления загрузки проекта](../../plans/2026-08-31-context7-config-layer-recovery.md).
- Базовое решение: [аналитический шаблон как единый проверяемый контур](2026-08-20-codex-analyst-template-v1.md).
- Контракт source: [TEMPLATE.md](../../TEMPLATE.md).
- Официальная конфигурация Codex MCP: [OpenAI Codex MCP](https://developers.openai.com/codex/mcp).
- Официальная конфигурация Context7 clients: [Context7 all clients](https://github.com/upstash/context7/blob/master/docs/resources/all-clients.mdx).
- Обратные ссылки на примененные candidates: нет.
