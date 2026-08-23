---
artifact_kind: retrospective
knowledge_outcome: none
candidate_ids: []
affected_canon:
  - .template-manifest.json
  - AGENTS.md
  - CODEX-INSTALL-PROMPT.md
  - README.md
  - PROJECT.md
  - scripts/README.md
blocked_reason: null
---

# Ретроспектива: URL-first установка через Codex

## Задача и связи

Follow-up к [плану выпуска шаблона](../plans/2026-08-20-codex-analyst-template-v1.md) уточнил основной install UX до первого публичного release. Реализация велась по [Plan v2 URL-first установки](../plans/2026-08-22-url-first-codex-install.md) и [accepted decision](../docs/decisions/2026-08-22-url-first-codex-install.md).

## Что сделано

- Начало README и отдельный install prompt дают одну явную команду с URL, после которой Codex сам выполняет локальный workflow.
- `Use this template` сохранен как дополнительный путь, но больше не является обязательной предпосылкой.
- Portable `scripts/new-project.ps1` принимает проверенный source или distribution payload и создает отдельный generated project с нейтральными defaults.
- Canonical distribution clone остается временным read-only источником; созданный проект получает собственный Git `main` без remote и commit.
- Consumer boundary, control plane, bootstrap и distribution fixtures дополнены позитивными и fail-closed сценариями URL-first режима.

## Что проверено и какими командами

- `scripts/test-analyst-consumer-boundary.ps1` - independent URL-first generated project и отсутствие source-only paths.
- `scripts/test-github-template-distribution.ps1` - 14 distribution checks.
- `scripts/test-cross-platform-bootstrap.ps1` - source-copy и дополнительный GitHub Template путь.
- `scripts/test-knowledge-control-plane.ps1 -CaseId 2` - A02 fail-closed boundaries.
- `scripts/test-knowledge-mastery.ps1` - 24/24 Mastery checks.
- `scripts/test-knowledge-privacy.ps1` - 37 privacy/RAW checks.
- `scripts/verify-analysis.ps1 -SelfTest` - 86/86 scenarios.
- `scripts/verify-codex-agents.ps1 -SelfTest` - 5/5 scenarios.
- `scripts/verify-template-sanitization.ps1 -Scope Source -Report` и `scripts/verify-structure.ps1 -Mode TemplateSource` - source privacy, inventory, owners и links.

## Что не получилось или осталось

- Bare URL без явного глагола установки не объявлен надежным интерфейсом Codex. Минимальный поддерживаемый вход - URL плюс одна короткая команда из README или GitHub About.
- Реальная публикация, настройка GitHub About, ветки `main`, tag и push не выполнялись и требуют отдельной прямой команды.
- Network clone не выполнялся из внешнего GitHub в этой локальной приемке; эквивалентный consumer payload проверен через реальный локальный Git clone и distribution harness.

## Как было и как стало

Раньше основной маршрут начинался с ручного `Use this template` и нового GitHub repository пользователя. Теперь основной маршрут начинается с URL canonical consumer `main`: Codex создает временный clone, читает и проверяет инструкции, запускает portable bootstrap в отдельный destination, проверяет результат и удаляет только свой temporary clone. GitHub Template путь остается доступен пользователям, которым сразу нужен собственный remote.

## Что выучено

- Надежный chat-install contract должен содержать не только URL, но и явную цель операции.
- Network orchestration безопаснее держать в проверяемом agent prompt, а скачиваемый entrypoint оставлять локальным, allowlist-based и без сетевых вызовов.
- Один portable bootstrap может обслуживать source и distribution, если mode, descriptor, hashes, inventory и generated boundary проверяются до записи final destination.

## Security review

- Персональные данные: не добавлялись; metadata по умолчанию нейтральны, sanitizer и privacy harness зеленые.
- Контент третьих лиц: новых материалов не добавлено; сохранены MIT License и notices шаблона.
- Внешние отправки: отсутствуют; network, push, GitHub write и публикация не выполнялись.
- Секреты: не читались и не записывались; URL contract запрещает credentials, query, fragment и signed URL.
