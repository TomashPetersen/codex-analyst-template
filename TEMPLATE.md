# Source maintenance: Codex Analyst Template

Этот файл существует только в ветке source и не входит в consumer payload.

## Контракт версии 1.0.1

- публичное имя: Codex Analyst Template;
- source branch: `source`;
- производная GitHub Template branch: `main`;
- текущий release tag: `v1.0.1`;
- исходный tag `v1.0.0` неизменяем;
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

Consumer строится только по `portable_files` из `.template-manifest.json`. В него входят URL-first `new-project.ps1`, formal-analysis, четыре project-local skills, пять read-only Codex roles, Plan v2, product/business/research, knowledge и mastery. Source-only планы, ADR, retrospectives, regression harnesses, builder, workflow и release history не переносятся.

В source и consumer запрещены данные конкретного продукта, заполненные runs, RAW, candidates, local mastery, origin, персональные сведения, credentials и абсолютные пользовательские пути.

## Проверочный профиль

Перед release-кандидатом выполни:

```powershell
pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode TemplateSource
pwsh -NoProfile -File ./scripts/verify-analysis.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/test-plan-lifecycle.ps1
pwsh -NoProfile -File ./scripts/test-canon-graph.ps1
pwsh -NoProfile -File ./scripts/test-mastery-v2.ps1
pwsh -NoProfile -File ./scripts/test-analyst-consumer-boundary.ps1
pwsh -NoProfile -File ./scripts/test-cross-platform-bootstrap.ps1
pwsh -NoProfile -File ./scripts/test-github-template-distribution.ps1
pwsh -NoProfile -File ./scripts/verify-template-sanitization.ps1 -Scope Source
```

Builder требует чистый tracked source tag, совпадение version contract и GitHub identity origin:

```powershell
pwsh -NoProfile -File ./scripts/build-github-template.ps1 `
  -Destination <EMPTY_LOCAL_DIRECTORY> `
  -SourceTag v1.0.1 `
  -TemplateRepositoryUrl https://github.com/<OWNER>/<REPOSITORY>
```

## Release gate

Commit, tag, push, перенос consumer payload в `main`, смена default branch и публикация GitHub не выполняются без отдельной прямой команды. Неизменяемый source tag создается только после полного локального и CI-профиля. Ошибка любого gate блокирует release, но не разрешает ослаблять manifest или sanitizer.

Source-only история этой версии: [архитектурное решение шаблона](docs/decisions/2026-08-20-codex-analyst-template-v1.md), [решение URL-first установки](docs/decisions/2026-08-22-url-first-codex-install.md), [план шаблона](plans/2026-08-20-codex-analyst-template-v1.md), [план URL-first установки](plans/2026-08-22-url-first-codex-install.md), [план GitHub release](plans/2026-08-23-github-release-v1-0-0.md), [ретроспектива шаблона](retrospectives/2026-08-21_19-27_codex-analyst-template-v1.md), [ретроспектива URL-first установки](retrospectives/2026-08-22_14-55_url-first-codex-install.md), [changelog](TEMPLATE-CHANGELOG.md).
