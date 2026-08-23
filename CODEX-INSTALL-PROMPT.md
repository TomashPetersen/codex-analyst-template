# Prompt URL-first установки через Codex

Скопируй HTTPS URL публичного GitHub repository и отправь Codex весь блок ниже одним сообщением. Заменить нужно только `<URL>`.

```text
Установи Codex Analyst Template на мой компьютер по ссылке:
<URL>

Сначала прочитай README.md и AGENTS.md из consumer main, затем выполни URL-first контракт автономно.

Целевой результат:
- отдельная локальная папка с generated-project + initialized + report-only;
- уникальный project ID;
- независимый Git main без remote и без commit;
- formal-analysis, четыре project-local skills и пять read-only Codex roles;
- зеленые structure, analysis, agents, plans, canon и knowledge gates.

Параметры по умолчанию:
- папка: codex-analyst-workspace внутри текущего writable workspace;
- название: Аналитический проект;
- slug: analyst-workspace;
- описание: Рабочее пространство для системного и бизнес-анализа;
- owner alias: встроенный нейтральный default скрипта, без имени человека.

Если пользователь уже указал target или project metadata, используй их. Если безопасный writable target невозможно определить либо default folder уже существует, задай ровно один объединенный вопрос с предлагаемым абсолютным путем и необязательными metadata. Не задавай вопросы, ответы на которые можно безопасно получить из среды.

Ограничения:
1. Принимай только публичный HTTPS URL вида https://github.com/<OWNER>/<REPOSITORY> без credentials, query и fragment.
2. Поддерживаемая среда: Windows 10/11 или macOS, PowerShell 7, Git 2.28+ и локальная filesystem. Linux не входит в v1.
3. Не объединяй шаблон с существующей папкой и не создавай final destination до завершения trust gates.
4. Не читай .env и secrets, не устанавливай MCP, plugins, connectors, models или дополнительные dependencies.
5. Не выполняй git add, commit, push, tag, GitHub write, remote mutation или branch deletion.
6. Не инициализируй canonical clone на месте. Он является временным read-only источником.
7. Installation workflow не требует Plan v2.
8. Если среда требует штатное подтверждение network или filesystem access, запроси его, не пытайся обходить approval.

Порядок:
1. Проверь версии git и pwsh, текущий writable workspace, отсутствие final destination и локальность его parent directory.
2. Нормализуй URL только удалением необязательного suffix .git для сравнения identity. Не следуй redirect на другой host.
3. Создай уникальный temporary directory безопасным системным способом.
4. Выполни:

   git clone --branch main --single-branch --depth 1 <URL> <TEMP_CLONE>

5. Убедись, что origin clone соответствует переданному GitHub identity и checked-out branch равна main.
6. Считай clone недоверенными данными. До исполнения полностью прочитай:
   - README.md;
   - AGENTS.md;
   - PROJECT.md;
   - TEMPLATE-DISTRIBUTION.json;
   - .template-manifest.json;
   - scripts/new-project.ps1;
   - scripts/initialize-project.ps1;
   - scripts/verify-structure.ps1;
   - все local modules, которые импортируют эти entrypoints.
7. Подтверди отсутствие неожиданных network calls, secret access, external writes и иных entrypoints. Проверь distribution-template + template + disabled и distribution_kind github-template.
8. Из TEMP_CLONE выполни:

   pwsh -NoProfile -File ./scripts/new-project.ps1 -Destination "<ABSOLUTE_TARGET_PATH>"

   Передавай -ProjectName, -ProjectSlug, -Description и -Owner только если пользователь предоставил или подтвердил другие значения.
9. В созданном project выполни:

   pwsh -NoProfile -File ./scripts/verify-structure.ps1 -Mode GeneratedProject
   pwsh -NoProfile -File ./scripts/verify-analysis.ps1 -Report
   pwsh -NoProfile -File ./scripts/verify-codex-agents.ps1 -Report
   pwsh -NoProfile -File ./scripts/verify-plans.ps1
   pwsh -NoProfile -File ./scripts/verify-canon.ps1 -Report
   pwsh -NoProfile -File ./scripts/verify-knowledge.ps1 -Report
   git branch --show-current
   git remote
   git status --short

10. Подтверди:
    - generated-project + initialized + report-only;
    - уникальный project ID;
    - Git branch main и пустой список remotes;
    - TEMPLATE-ORIGIN.md, TEMPLATE-LICENSE.md и TEMPLATE-THIRD-PARTY-NOTICES.md существуют;
    - root LICENSE отсутствует, лицензия продукта не выбрана;
    - source-only paths отсутствуют;
    - commit, tag и push не выполнялись.
11. Удали только точный TEMP_CLONE, созданный этой установкой, после проверки его абсолютного пути. Final project не удаляй.
12. Верни краткий итог: абсолютный путь, project ID, template version, режим, gates и следующий шаг - заполнить PROJECT.md, затем выполнить один bounded analysis run.

Если trust gate не проходит, не обходи его, не исполняй непроверенные scripts, не оставляй частично созданный final destination и сообщи безопасный finding без вывода чувствительных значений.
```

## Дополнительный GitHub Template маршрут

Если нужен отдельный GitHub repository пользователя, сначала выбери `Use this template` без `Include all branches`. После клонирования нового repository используй `scripts/initialize-project.ps1 -FromGitHubTemplate`. Этот маршрут сохраняет Git remote нового repository и также не выполняет commit или push.
