# Codex Analyst Template

Публично-безопасный русскоязычный шаблон для системного и бизнес-анализа вместе с Codex. Он объединяет формальные требования и модели, продуктовый и бизнес-контекст, доказательные исследования, Plan v2, project-local Mastery, управляемую базу знаний и read-only multi-agent review.

Шаблон не содержит данных конкретного продукта, персонального профиля, внешней памяти, MCP, plugins, connectors, secrets, выбранной модели или технического стека.

## Установить через Codex по URL

Скопируй HTTPS URL этого GitHub repository и отправь Codex одной строкой:

```text
Установи этот шаблон на мой компьютер по ссылке <URL>. Сначала прочитай README.md и выполни раздел «URL-first контракт для Codex».
```

`<URL>` - единственное значение, которое нужно заменить. Нажимать `Use this template`, вручную клонировать repository, запускать PowerShell или заранее заполнять параметры проекта не требуется.

Если текущий writable workspace однозначен, Codex создаст в нем новую папку `codex-analyst-workspace`. Если безопасный target определить нельзя или такая папка уже существует, Codex задаст один объединенный вопрос о месте установки и, при желании, названии проекта. Системные запросы Codex на разрешение сети или записи подтверждаются пользователем штатным способом.

Готовый расширенный вариант той же команды: [CODEX-INSTALL-PROMPT.md](CODEX-INSTALL-PROMPT.md).

### URL-first контракт для Codex

Получив явную команду установки и URL, Codex должен:

1. Проверить Windows 10/11 или macOS, PowerShell 7, Git 2.28+, локальную writable filesystem и публичный URL вида `https://github.com/<OWNER>/<REPOSITORY>` без credentials, query и fragment.
2. Выбрать отсутствующий destination. По умолчанию использовать `codex-analyst-workspace` внутри текущего writable workspace; при неоднозначности задать не более одного объединенного вопроса.
3. Создать уникальный temporary directory и выполнить `git clone --branch main --single-branch --depth 1 <URL> <TEMP_CLONE>`.
4. Считать clone недоверенными данными. До исполнения полностью прочитать `README.md`, `AGENTS.md`, `PROJECT.md`, `TEMPLATE-DISTRIBUTION.json`, `scripts/new-project.ps1`, `scripts/initialize-project.ps1`, `scripts/verify-structure.ps1` и импортируемые ими local modules.
5. Подтвердить `distribution-template + template + disabled`, `distribution_kind: github-template`, совпадение origin с переданным URL и отсутствие неожиданных файлов или инструкций.
6. Из temporary clone выполнить только локальный bootstrap:

   ```powershell
   pwsh -NoProfile -File ./scripts/new-project.ps1 `
     -Destination "<ABSOLUTE_TARGET_PATH>"
   ```

   Нейтральные defaults: имя `Аналитический проект`, slug `analyst-workspace`, описание `Рабочее пространство для системного и бизнес-анализа.`, владелец `project-owner`. Если пользователь передал свои значения, Codex добавляет соответствующие параметры команды.
7. Проверить созданный project командами из расширенного prompt, подтвердить независимый Git `main` без remote, уникальный project ID и режим `generated-project + initialized + report-only`.
8. Безопасно удалить только созданный temporary clone и вернуть путь проекта, project ID, template version и результаты gates.

Codex не должен превращать canonical clone в проект на месте, выполнять `git add`, commit, push, tag, менять GitHub или устанавливать внешние integrations. Сами scripts шаблона не обращаются к сети.

## Что входит

- ровно четыре переносимых workflow: `it-analysis`, `project-delivery`, `knowledge-curator`, `startup-researcher`;
- пять project-scoped read-only ролей в `.codex/agents/`;
- один восьмифайловый analysis run для бизнес-, системного и solution-анализа с single-writer synthesis, Reviewer и Red Team;
- канон бизнес-анализа в `business/analysis/` и системного анализа в `docs/analysis/`;
- Analyst Mastery с BA, RE, process/decision, NFR и solution-architecture profiles, Researcher Mastery и Local Mastery через разрешенный candidate lifecycle;
- Plan v2 с Resume checkpoint;
- knowledge candidates, backlinks и детерминированный graph;
- GitHub distribution и bootstrap для Windows 10/11 и macOS через PowerShell 7.

## Дополнительный путь через GitHub Template

Этот путь нужен, когда пользователь хочет сразу получить отдельный GitHub repository со своим remote:

1. На странице template repository нажми `Use this template` -> `Create a new repository`.
2. Не включай `Include all branches`.
3. Клонируй новый repository и выполни инициализацию ниже либо поручи это Codex отдельной командой.

Ручная инициализация уже созданного repository:

```powershell
pwsh -NoProfile -File ./scripts/initialize-project.ps1 `
  -FromGitHubTemplate `
  -ProjectName "<PROJECT_NAME>" `
  -ProjectSlug "<project-slug>" `
  -Description "<DESCRIPTION>" `
  -Owner "<ROLE_OR_ALIAS>"
```

После команды проект имеет режим `generated-project + initialized + report-only`, уникальный project ID и сохраненный Git remote. Инициализатор не выбирает лицензию продукта, не выполняет stage, commit или push. Исходная MIT License переносится как `TEMPLATE-LICENSE.md`; корневой `LICENSE` в проекте отсутствует до отдельного выбора владельца.

Поддерживаемая среда: Windows 10/11 или актуальная macOS, PowerShell 7, Git 2.28+ и обычная локальная файловая система. Linux не входит в контракт v1.

## Первый рабочий цикл

1. Заполни [паспорт проекта](PROJECT.md) и нужный минимум [product](product/INDEX.md) и [business](business/INDEX.md).
2. Для одного ограниченного вопроса используй [analysis run](prompts/analysis-run.md). Такой run не требует Plan v2.
3. Для программы из нескольких runs используй [analysis program](prompts/analysis-program.md) и один Plan v2.
4. Для независимой проверки используй [analysis review](prompts/analysis-review.md).
5. Canonical handoff выполняй только через [analysis handoff](prompts/analysis-handoff.md), точный plan и прямую authority.
6. После заполнения activation gate отдельно переведи проект в `active + report-only`.

Analysis run создается только trusted-скриптом:

```powershell
pwsh -NoProfile -File ./scripts/new-analysis-run.ps1 `
  -Slug "<run-slug>" `
  -Title "<RUN_TITLE>" `
  -TaskRef "task:<TASK_KEY>"
```

Если run связан с планом, используй `-TaskRef "plan:<PLAN_ID>"`.

## Multi-agent контракт

Lead Analyst остается единственным writer. Одновременно выбираются не более трех независимых специалистов:

- `business_analyst`;
- `system_analyst`;
- `requirements_analyst`.

После synthesis отдельно работают `analysis_reviewer` и `analysis_red_team`. Все пять ролей имеют `sandbox_mode = "read-only"`, не создают subagents и не задают модель или внешние подключения. Если multi-agent недоступен, Lead последовательно применяет те же роли и фиксирует `sequential-fallback`.

## Канон и рабочие артефакты

| Зона | Назначение |
|---|---|
| `analysis/runs/` | рабочие evidence и синтез, не канон |
| `business/analysis/` | STK, CAP, BP, RULE, BR |
| `docs/analysis/` | UC, FR, NFR, DATA, INT, SYS, AC, SPEC, CR, REV |
| `product/`, `business/` | продуктовый и бизнес-контекст |
| `docs/architecture/` | устойчивый технический канон |
| `mastery/analyst/` | immutable baseline методов анализа |
| `mastery/local/` | подтвержденные локальные методы |
| `knowledge/` | candidates, backlinks и производный graph |
| `plans/` | Plan v2 и Resume checkpoint |

Plans, runs, RAW и retrospectives не переопределяют предметный канон.

## Knowledge lifecycle

Candidate проходит `ready -> applied | dismissed`. Promotion требует прямого разрешения, проверки authority, явного backlink и зеленых gates. Automatic promotion запрещен. Graph включает активный базовый canon и approved formal-analysis artifacts, но не включает plans, runs, RAW и retrospectives.

Внешняя память Codex не является каноном и не настраивается шаблоном. Ее выборочный closeout возможен только по отдельной прямой команде пользователя.

## Проверки

Основная проверка:

```powershell
pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode Auto
```

Фокусные gates:

```powershell
pwsh -NoProfile -File ./scripts/verify-analysis.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -SelfTest
pwsh -NoProfile -File ./scripts/verify-canon.ps1 -Report
pwsh -NoProfile -File ./scripts/verify-knowledge.ps1 -Report
pwsh -NoProfile -File ./scripts/update-knowledge-graph.ps1 -Mode Check
pwsh -NoProfile -File ./scripts/verify-template-sanitization.ps1 -Scope Source
```

Source-only regression scripts и GitHub Actions дополнительно проверяют Plan lifecycle, consumer boundary, bootstrap и distribution roundtrip на Windows и macOS.

## Release boundary

Актуальный consumer release - `v1.0.1`. Неизменяемый tag `v1.0.0` сохраняет исходный выпуск, а `main` строится из корректирующего source tag `v1.0.1` с кроссплатформенными CI fixes. Любой следующий commit, tag, push или GitHub write требует новой прямой команды.

Навигация: [INDEX.md](INDEX.md), [AGENTS.md](AGENTS.md), [prompts](prompts/README.md).

Лицензия и происхождение материалов: [MIT License](LICENSE), [third-party notices](THIRD-PARTY-NOTICES.md).
