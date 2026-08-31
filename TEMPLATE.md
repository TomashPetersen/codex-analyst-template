# Source maintenance: Codex Analyst Template

Этот файл существует только в ветке source и не входит в consumer payload.

## Контракт version 1.1.0

- публичное имя: Codex Analyst Template;
- source branch: `source`;
- производная GitHub Template branch: `main`;
- release version: `1.1.0`;
- source tag этой версии: `v1.1.0`;
- consumer `main` строится только из source tag `v1.1.0`;
- tags `v1.0.0` и `v1.0.1` неизменяемы;
- Windows 10/11 является основной платформой;
- macOS проверяется PowerShell 7 и CI;
- Linux не входит в v1.

## GitHub About и основной пользовательский вход

Рекомендуемое описание repository:

```text
Скопируйте URL этого репозитория в Codex и напишите: «Установи этот шаблон на мой компьютер. Сначала прочитай README.md и выполни URL-first контракт».
```

Основной install UX - URL canonical consumer `main` плюс одна короткая команда. `Use this template` остается дополнительным маршрутом для пользователя, которому сразу нужен отдельный GitHub repository.

## Source и consumer boundary

Consumer строится только по `portable_files` из `.template-manifest.json`. В него входят URL-first `new-project.ps1`, formal-analysis, четыре project-local skills, пять read-only Codex roles, exact optional remote Context7 MCP config, Plan v2, product/business/research, knowledge и mastery. Source-only планы, ADR, retrospectives, regression harnesses, builder, workflow и release history не переносятся.

В source и consumer запрещены данные конкретного продукта, заполненные runs, RAW, candidates, local mastery, origin, персональные сведения, credentials, другие MCP/integrations и абсолютные пользовательские пути. Context7-конфигурация не содержит auth material, не является обязательной runtime dependency и не вызывается distribution scripts.

## Проверочный профиль

Перед release-кандидатом выполни:

```powershell
pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode TemplateSource
pwsh -NoProfile -File ./scripts/verify-analysis.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/test-it-analysis-semantics.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/test-plan-lifecycle.ps1
pwsh -NoProfile -File ./scripts/test-canon-graph.ps1
pwsh -NoProfile -File ./scripts/test-mastery-v2.ps1
pwsh -NoProfile -File ./scripts/test-knowledge-mastery.ps1
pwsh -NoProfile -File ./scripts/test-analyst-consumer-boundary.ps1
pwsh -NoProfile -File ./scripts/test-cross-platform-bootstrap.ps1
pwsh -NoProfile -File ./scripts/test-github-template-distribution.ps1
pwsh -NoProfile -File ./scripts/verify-template-sanitization.ps1 -Scope Source
```

Builder запускается только после отдельного release-разрешения. Тогда он требует чистый tracked source tag `v1.1.0`, совпадение version contract и GitHub identity origin:

```powershell
pwsh -NoProfile -File ./scripts/build-github-template.ps1 `
  -Destination <EMPTY_LOCAL_DIRECTORY> `
  -SourceTag v1.1.0 `
  -TemplateRepositoryUrl https://github.com/<OWNER>/<REPOSITORY>
```

## Release gate

Commit, tag, push, перенос consumer payload в `main`, смена default branch и публикация GitHub не выполняются без отдельной прямой команды. Неизменяемый source tag создается только после полного локального и CI-профиля. Ошибка любого gate блокирует release, но не разрешает ослаблять manifest или sanitizer.

Source-only история этой версии: [архитектурное решение шаблона](docs/decisions/2026-08-20-codex-analyst-template-v1.md), [решение URL-first установки](docs/decisions/2026-08-22-url-first-codex-install.md), [решение Context7 MCP](docs/decisions/2026-08-30-context7-mcp-template.md), [план шаблона](plans/2026-08-20-codex-analyst-template-v1.md), [план URL-first установки](plans/2026-08-22-url-first-codex-install.md), [план GitHub release](plans/2026-08-23-github-release-v1-0-0.md), [план усиления IT Analysis 1.1.0](plans/2026-08-29-it-analysis-v1-1.md), [план фиксации IT Analysis 1.1.0 в GitHub source](plans/2026-08-30-publish-it-analysis-v1-1-source.md), [план Context7 MCP](plans/2026-08-30-context7-mcp-template.md), [план восстановления Context7 config layers](plans/2026-08-31-context7-config-layer-recovery.md), [план выпуска 1.1.0](plans/2026-08-31-active-learning-v1-1-release.md), [ретроспектива шаблона](retrospectives/2026-08-21_19-27_codex-analyst-template-v1.md), [ретроспектива URL-first установки](retrospectives/2026-08-22_14-55_url-first-codex-install.md), [ретроспектива GitHub release](retrospectives/2026-08-28_11-20_github-release-v1-0-1.md), [ретроспектива Context7 recovery](retrospectives/2026-08-31_09-25_context7-config-layer-recovery.md), [changelog](TEMPLATE-CHANGELOG.md).
