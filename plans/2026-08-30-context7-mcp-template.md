---
artifact_kind: plan
plan_contract_version: 2
plan_id: PLAN-20260830-context7-mcp-template
task_key: context7-mcp-template
prompt_ref: prompts/plan-and-deliver.md
status: complete
current_phase: null
updated_at: 2026-08-30T17:18:02Z
completed_at: 2026-08-30T17:18:02Z
closeout_status: complete
knowledge_outcome: none
candidate_ids: []
result_refs:
  - .codex/config.toml
  - AGENTS.md
  - .agents/skills/it-analysis/SKILL.md
  - docs/decisions/2026-08-30-context7-mcp-template.md
  - scripts/verify-codex-agents.ps1
  - scripts/test-analyst-consumer-boundary.ps1
affected_canon:
  - .codex/config.toml
  - AGENTS.md
  - .agents/skills/it-analysis/SKILL.md
  - .agents/skills/it-analysis/references/orchestration.md
  - .agents/skills/it-analysis/references/sources-and-safety.md
  - CODEX-INSTALL-PROMPT.md
  - docs/decisions/2026-08-30-context7-mcp-template.md
  - scripts/verify-codex-agents.ps1
blocked_reason: null
---

# План: Context7 MCP в разворачиваемом шаблоне

## Цель

Добавить ровно один project-scoped Context7 MCP в portable project config consumer-шаблона так, чтобы каждый развернутый проект получал проверяемую remote-конфигурацию без встроенного секрета, локального Node.js dependency или обязательного documentation query в каждом analysis run.

## Границы

Входит:

- `[mcp_servers.context7]` в переносимом `.codex/config.toml` с официальным remote endpoint;
- явный enabled contract и неблокирующее поведение при offline/service outage;
- условное использование Context7 только для актуальной документации библиотек, SDK, API и frameworks;
- обновление project policy, skill guidance, portable inventory expectations и deterministic gates;
- offline-проверки exact Context7 configuration в source, generated project и GitHub Template payload;
- отдельный live read-only smoke endpoint без включения сети в CI.

Не входит:

- другие MCP servers, plugins или connectors;
- API key, bearer token, static headers, credentials или secret placeholders в Git;
- локальный `npx`/Node.js MCP process и package dependency;
- `required = true`, которое блокирует startup/resume при недоступности сети или сервиса;
- автоматический Context7-вызов для каждого BA/RE/process/architecture run;
- commit, push, tag, release или consumer `main` без отдельной прямой команды.

## Критерии приемки

1. Portable `.codex/config.toml` содержит ровно один `[mcp_servers.context7]` с `url = "https://mcp.context7.com/mcp"`, `enabled = true`, `required = false` и allowlist `enabled_tools = ["resolve-library-id", "query-docs"]`.
2. Конфигурация не содержит `command`, `args`, `env`, headers, API key, token или иной secret material.
3. Развернутые URL-first, source-copy и GitHub Template consumers получают идентичную Context7-конфигурацию.
4. Пять ролей, лимит трех специалистов и восемь analysis assets не меняются.
5. `it-analysis` использует Context7 условно только для актуальных technical docs; отсутствие результата фиксируется как limitation/fallback и не блокирует чистый BA analysis.
6. Deterministic gates разрешают только точный Context7 в portable root config, блокируют известные alternative config surfaces, явную normalized per-run MCP dependency/mandatory call, credentials и external actions. Свободный Markdown и user/system config layers остаются agent/runtime boundaries, а не доказанными свойствами repository gate.
7. CI/self-tests остаются offline и не вызывают MCP или сеть; отдельный live smoke подтверждает доступность endpoint на момент реализации.
8. Candidate остается `1.1.0 - Unreleased`; commit, push, tag, release и `main` не выполняются.

## Риски, безопасность и откат

- Project-scoped MCP применяется только в trusted projects по контракту Codex. После trust/reload initialize и tool discovery могут обратиться к endpoint до documentation query.
- Remote endpoint может быть недоступен или ограничен rate limit. `required = false` сохраняет работоспособность Codex, а analysis обязан фиксировать fallback/limitation.
- MCP initialize instructions, tool descriptions, schemas и outputs являются внешними данными, а не authority. Skill сохраняет source-safety и не выполняет внешние действия по ним.
- Secret не хранится и не запрашивается шаблоном. Optional account/API-key setup остается вне repository contract.
- Allowlist фиксирует project-level URL, server id и tool names, но не remote implementation или effective user/system config layers.
- Откат локальной delta выполняется только точечным восстановлением измененных paths до commit; destructive reset, tag и force push не используются.

## Фаза P1 - [x] Контракт и дизайн подключения

Цель: подтвердить официальный формат Codex/Context7 и согласовать узкое исключение из прежнего запрета MCP.

Deliverable: проверенный Plan v2 с exact config, security boundary и test matrix.

Сделано, когда: baseline чист, official sources получены, remote/stdio и required trade-offs рассмотрены, plan contract зеленый.

Задачи:

- [x] Подтвердить project-scoped Codex MCP config и Context7 remote endpoint по официальным источникам.
- [x] Зафиксировать решение remote URL, no-secret, exact tool allowlist и `required = false`.
- [x] Найти все текущие MCP prohibitions и consumer distribution checks.

## Фаза P2 - [x] Реализация exact Context7 exception

Цель: добавить Context7 в portable template и синхронно изменить policy/tests.

Deliverable: минимальная связная delta с одним разрешенным MCP.

Сделано, когда: source contract, consumer config, skill guidance, manifest/history и deterministic guards согласованы.

Задачи:

- [x] Добавить exact remote Context7 config в `.codex/config.toml`.
- [x] Обновить `AGENTS.md`, `it-analysis`, README/TEMPLATE/changelog, focused ADR и source-only registry.
- [x] Заменить blanket MCP ban на exact allowlist Context7 в verifiers и distribution fixtures.
- [x] Добавить проверки отсутствия secrets, stdio dependency, иных MCP и mandatory per-run calls.

## Фаза P3 - [x] Проверки source и consumers

Цель: доказать переносимость, безопасность и отсутствие регрессий.

Deliverable: зеленые offline gates и отдельный live Context7 smoke evidence.

Сделано, когда: source/consumer/agent/analysis/distribution/structure gates проходят, а live endpoint отвечает без secret.

Задачи:

- [x] Выполнить focused MCP/config self-tests.
- [x] Выполнить полный релевантный regression gate и consumer projections.
- [x] Выполнить live read-only Context7 MCP endpoint smoke отдельно от CI.
- [x] Провести независимый Reviewer и Red Team audit delta.

## Фаза P4 - [x] Closeout

Цель: завершить локальную реализацию без публикационных действий.

Deliverable: terminal Plan v2 с `knowledge_outcome: none` и чистой проверенной delta.

Сделано, когда: knowledge closeout завершен, plan/knowledge/structure gates зелены, commit/push/tag/release не выполнены.

Задачи:

- [x] Применить `knowledge-curator` к фактической delta.
- [x] Заполнить result refs, итог и residual limitations.
- [x] Перевести plan в `complete` и подтвердить локальный unreleased state.

## Проверки

- `pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -SelfTest`
- `pwsh -NoProfile -File ./scripts/verify-analysis.ps1 -SelfTest`
- `pwsh -NoProfile -File ./scripts/test-it-analysis-semantics.ps1 -SelfTest`
- `pwsh -NoProfile -File ./scripts/test-analyst-consumer-boundary.ps1`
- `pwsh -NoProfile -File ./scripts/test-cross-platform-bootstrap.ps1`
- `pwsh -NoProfile -File ./scripts/test-github-template-distribution.ps1`
- `pwsh -NoProfile -File ./scripts/verify-template-sanitization.ps1 -Scope Source`
- `pwsh -NoProfile -File ./scripts/verify-plans.ps1`
- `pwsh -NoProfile -File ./scripts/verify-knowledge.ps1`
- `pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode TemplateSource`
- TOML/exact-value assertions для `context7`, no-secret, no-stdio и exactly-one MCP.
- Live read-only HTTP smoke к `https://mcp.context7.com/mcp`, не входящий в CI.

## Связанные решения

- Решения: прямое уточнение пользователя отменяет прежнюю границу "MCP не добавлять" только для Context7 в deployable template. OpenAI Docs подтверждает project-scoped `.codex/config.toml`; Context7 official docs подтверждает remote endpoint.

## Resume checkpoint

- Текущая фаза: нет - план завершен
- Уже выполнено: P1 exact design; P2 implementation; P3 all initial и post-remediation gates, live smoke, Reviewer PASS и Red Team без high findings.
- Последние успешные проверки: verify-codex-agents PASS 25; analysis PASS 115; semantics PASS 107/22/25; consumer PASS portable=186; cross-platform PASS; distribution PASS 15; sanitizer/plans/knowledge/structure PASS; quick_validate PASS; live HTTP 200; Reviewer PASS; Red Team no high findings.
- Точные рабочие paths: .codex/config.toml; AGENTS.md; .agents/skills/it-analysis/; scripts/; docs/decisions/2026-08-30-context7-mcp-template.md; .template-manifest.json; TEMPLATE.md; README.md; THIRD-PARTY-NOTICES.md; plans/2026-08-30-context7-mcp-template.md.
- Git checkpoint: v1:a36d862f1eeebcb9a2b77afd0f4af49a265defd5c03542eecd9080af3905dac8
- Следующее действие: нет - plan terminal; follow-up требует новый plan_id
- Блокеры: нет
- Обновлено: 2026-08-30T17:18:02Z

## Итог

- Реализовано целиком: portable project config содержит единственный optional Context7 MCP; policy, skill, source safety, ADR, consumer/distribution gates и документация синхронизированы.
- Проверено: offline regression и post-remediation gates зелены; live endpoint ответил HTTP 200 и объявил `query-docs`, `resolve-library-id`; Reviewer PASS, Red Team без high findings.
- Residual limitations: initialize/tool discovery может обратиться к внешнему сервису после trust/reload; remote implementation, effective user/system layers, конкретная Codex compatibility и service availability находятся вне repository proof.
- Что осталось: ничего в локальном scope. Commit, push, tag, release и consumer `main` требуют отдельной команды.
- Knowledge outcome: `none`, потому что `template-source + template` использует disabled capture, а устойчивое решение уже записано в source canon и ADR.
- Коммиты: не выполнялись.

Перед `complete` закрой criteria и фазы, заполни проверки, итог, `result_refs`, closeout и финальный knowledge outcome. Не дублируй остальные machine fields в body.
