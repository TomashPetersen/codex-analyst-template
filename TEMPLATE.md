# Разработка и публикация Codex Analyst Template

Этот файл находится только в ветке `source`. В устанавливаемую копию шаблона он не входит.

## Текущая версия

- Название: Codex Analyst Template.
- Ветка разработки: `source`.
- Ветка для установки и кнопки GitHub Template: `main`.
- Версия: `1.1.0`.
- Тег исходников этой версии: `v1.1.0`.
- Набор файлов для `main` собирается только из проверенного тега `v1.1.0`.
- Теги `v1.0.0` и `v1.0.1` сохраняются без изменений.
- Основная платформа: Windows 10/11. Проверки macOS выполняются с PowerShell 7, в том числе в GitHub Actions. Linux пока не входит в проверяемый набор платформ.

## Краткое описание на GitHub

```text
Шаблон для бизнес- и системного анализа с Codex: требования, процессы, исследования и технические задания. Установка и настройка на компьютере готовыми запросами.
```

Основной путь пользователя: открыть локальную папку в Codex, отправить запрос с адресом репозитория, дождаться установки и заполнить сведения о своем проекте. Готовые запросы находятся в [README.md](README.md) и [инструкции установки](CODEX-INSTALL-PROMPT.md). Кнопка `Use this template` нужна для дополнительного пути с собственным репозиторием GitHub.

## Что попадает в установленную копию

Состав определяет список `portable_files` в `.template-manifest.json`. Он включает установщик, аналитические документы, четыре набора инструкций, пять ролей помощников с доступом только для чтения, предусмотренную настройку Context7, планы, исследования, описание продукта и бизнеса, правила знаний и методы работы.

Планы разработки шаблона, технические решения по самому шаблону, история выпусков, сборщик и служебные тесты не переносятся. В исходниках и устанавливаемой копии не должно быть данных конкретного продукта, заполненных рабочих разборов, личного профиля, секретов и абсолютных пользовательских путей.

Настройка Context7 не содержит ключей доступа. Скрипты установки не вызывают этот сервис. Другие внешние подключения шаблон не добавляет.

## Проверки перед публикацией

Выполни полный профиль:

```powershell
pwsh -NoProfile -File ./scripts/test-platform.ps1
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
pwsh -NoProfile -File ./scripts/verify-knowledge.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/test-knowledge-privacy.ps1
```

Проверки GitHub Actions находятся в [процессе проверки шаблона](.github/workflows/template-integrity.yml).

## Сборка и публикация

Сборка выполняется после прямого разрешения на выпуск. Она требует неизмененного состояния исходников, соответствующего тегу `v1.1.0`, совпадения версии и адреса репозитория:

```powershell
pwsh -NoProfile -File ./scripts/build-github-template.ps1 `
  -Destination <EMPTY_LOCAL_DIRECTORY> `
  -SourceTag v1.1.0 `
  -TemplateRepositoryUrl https://github.com/<OWNER>/<REPOSITORY>
```

Коммит, создание тега, отправка изменений, перенос собранных файлов в `main`, смена основной ветки и публикация выпуска требуют соответствующей прямой команды. Тег создается после полного набора локальных проверок и успешных проверок GitHub Actions. Ошибка проверки останавливает публикацию.

Нельзя вручную подменять файлы в `main` и пересчитывать их контрольные суммы: сборщик сверяет содержимое с исходниками тега. Для следующей версии нужен новый тег; старые теги не перемещаются.

## История разработки

- [Устройство шаблона](docs/decisions/2026-08-20-codex-analyst-template-v1.md).
- [Установка по ссылке](docs/decisions/2026-08-22-url-first-codex-install.md).
- [Подключение Context7](docs/decisions/2026-08-30-context7-mcp-template.md).
- [Первоначальный план](plans/2026-08-20-codex-analyst-template-v1.md).
- [План установки по ссылке](plans/2026-08-22-url-first-codex-install.md).
- [План первого выпуска](plans/2026-08-23-github-release-v1-0-0.md).
- [План улучшения анализа](plans/2026-08-29-it-analysis-v1-1.md).
- [Публикация улучшений анализа](plans/2026-08-30-publish-it-analysis-v1-1-source.md).
- [План подключения Context7](plans/2026-08-30-context7-mcp-template.md).
- [Восстановление загрузки настроек](plans/2026-08-31-context7-config-layer-recovery.md).
- [План выпуска 1.1.0](plans/2026-08-31-active-learning-v1-1-release.md).
- [Понятное описание и быстрый запуск](plans/2026-09-05-plain-russian-quickstart.md).
- [Выводы из создания шаблона](retrospectives/2026-08-21_19-27_codex-analyst-template-v1.md).
- [Выводы из разработки установки](retrospectives/2026-08-22_14-55_url-first-codex-install.md).
- [Выводы из первого выпуска](retrospectives/2026-08-28_11-20_github-release-v1-0-1.md).
- [Выводы из восстановления настроек](retrospectives/2026-08-31_09-25_context7-config-layer-recovery.md).
- [Выводы из выпуска 1.1.0](retrospectives/2026-09-01_00-35_codex-analyst-template-v1-1-0.md).
- [Изменения версий](TEMPLATE-CHANGELOG.md).
