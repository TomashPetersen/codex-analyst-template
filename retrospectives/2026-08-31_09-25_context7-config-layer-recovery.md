---
artifact_kind: retrospective
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .codex/config.toml
  - .template-manifest.json
  - AGENTS.md
  - README.md
  - TEMPLATE-CHANGELOG.md
  - docs/decisions/2026-08-30-context7-mcp-template.md
  - scripts/test-analyst-consumer-boundary.ps1
  - scripts/test-cross-platform-bootstrap.ps1
  - scripts/test-github-template-distribution.ps1
  - scripts/verify-codex-agents.ps1
blocked_reason: null
---

# Ретроспектива: восстановление загрузки задач после конфликта Context7

## Задача и связи

Инцидент устранялся по [Plan v2 восстановления](../plans/2026-08-31-context7-config-layer-recovery.md) как corrective follow-up к [решению о portable Context7](../docs/decisions/2026-08-30-context7-mcp-template.md). Пользовательские задачи проекта перестали загружаться после добавления project-level HTTP table с тем же MCP server ID `context7`, который уже использовался user-level STDIO table.

## Что сделано

- До записи сохранен полный Git snapshot с tracked, staged и untracked состоянием, чтобы не смешать repair с существующей незавершенной работой.
- Для аварийного восстановления project config временно возвращен к последнему committed agents-only состоянию. Обе существующие задачи после этого снова перешли в `idle`.
- История проверена отдельно: в задаче «Исследуй улучшения скилла аналитики» сохранены 8 из 8 turns, в задаче «Создай шаблон мультиагентной среды» сохранены 11 turns, включая один ранее interrupted turn.
- Durable repair заменил project server ID на `codex_analyst_context7`, сохранив remote endpoint, optional mode и allowlist tools без repair-записи в user-level config; отдельная concurrent delta `service_tier` разобрана ниже.
- Policy, ADR, changelog, consumer/distribution harnesses и manifest синхронизированы с namespaced ID.
- В `verify-codex-agents.ps1` добавлен negative fixture, который отклоняет generic `[mcp_servers.context7]` в portable project config.

## Что проверено и какими командами

- Desktop Codex CLI `mcp get codex_analyst_context7 --json` - effective project server использует `streamable_http` и ожидаемый URL.
- Desktop Codex CLI `mcp get context7 --json` - user-level server остается отдельным `stdio` transport с `npx`.
- Read-only byte audit user-level config - между двумя замерами приложение добавило только `service_tier = "priority"`; удаление этих 26 байт в памяти точно восстановило исходные длину и SHA-256, а shape `mcp_servers.context7` остался неизменным.
- `scripts/verify-codex-agents.ps1 -SelfTest` - 26 сценариев PASS, включая collision regression.
- `scripts/test-analyst-consumer-boundary.ps1` - portable payload из 186 файлов и exact Context7 config PASS.
- `scripts/test-cross-platform-bootstrap.ps1` - source-copy и consumer bootstrap PASS.
- `scripts/test-github-template-distribution.ps1` - 15 distribution checks PASS.
- `scripts/verify-analysis.ps1 -SelfTest` - 115 сценариев PASS.
- `scripts/test-it-analysis-semantics.ps1 -SelfTest` - 107 cases, 22 intents и 25 required hard-fail codes PASS.
- `scripts/verify-plans.ps1`, `scripts/verify-knowledge.ps1`, `scripts/verify-structure.ps1 -Mode TemplateSource` и `git diff --check` - PASS.
- Codex app повторно загрузил обе задачи без unavailable host/source и без config error.

## Что не получилось или осталось

- Попытки очистить унаследованный `command` через пустое значение или иной shape project table не устраняли layered merge. Transport выбирался как STDIO, а `url` оставался недопустимым полем.
- Первый полный cross-platform gate отклонил абсолютный локальный путь в новом plan. Путь заменен переносимым описанием `user-level Codex config`, после чего gate полностью перезапущен и прошел.
- Namespaced project server может отображаться рядом с отдельным user-level Context7. Это осознанный остаточный эффект, который сохраняет portable capability и исключает конфликт transport.
- Параллельную app-managed запись `service_tier` не откатывали: она не относится к MCP repair, а изменение пользовательской настройки без отдельного разрешения вышло бы за scope.
- Commit, push, tag, release и deploy не выполнялись.

## Как было и как стало

До исправления два config layer объединяли table `mcp_servers.context7`: user-level слой задавал `command`, project-level слой задавал `url`. Итоговая effective table одновременно содержала признаки STDIO и HTTP, поэтому весь project config отклонялся до загрузки задач. После исправления слои используют разные IDs: `context7` остается user-level STDIO server, а `codex_analyst_context7` является project-level HTTP server. Обе задачи снова доступны, а portable template сохраняет Context7 независимо от локальной настройки пользователя.

## Что выучено

- Идентификатор MCP server является merge key между config layers, поэтому reusable project config не должен занимать распространенный generic ID без проверки effective layering.
- Static validation одного project file недостаточна для transport collision. Нужны отдельный namespaced contract и negative fixture для известного конфликтного ID.
- Восстановление доступа безопаснее начинать с минимального reversible rollback, проверки сохранности истории и только затем выполнять durable contract change.
- Новый knowledge candidate не нужен: устойчивый вывод уже закреплен в accepted ADR, policy warning, regression harness и этой historical retrospective; режим template-source дополнительно запрещает automatic capture.

## Security review

- Персональные данные: не добавлялись; в репозиторий записаны только названия project tasks и агрегированные counts без содержимого переписки.
- Контент третьих лиц: новый сторонний контент не копировался; использовалась официальная документация OpenAI как read-only evidence.
- Внешние отправки: project data, source code, commit, push, release и deploy наружу не отправлялись.
- Секреты: secret values, credentials, headers и `.env` не читались и не записывались; repair не добавляет auth fields.
