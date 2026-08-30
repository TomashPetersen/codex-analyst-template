# Скрипты шаблона

- `new-project.ps1` - portable атомарный bootstrap из проверенного `template-source + source-placeholder` или `distribution-template + github-template`; копирует exact allowlist в отсутствующий destination и создает независимый Git `main` без remote. Нейтральные metadata используются по умолчанию.
- `initialize-project.ps1` - создает `generated-project + initialized + report-only`, UUID и `TEMPLATE-ORIGIN.md`; `-InitializeGit` принимает локальную source copy или distribution copy без `.git`, а `-FromGitHubTemplate` сохраняет Git и remote отдельного repository пользователя. Все пути имеют rollback и не выполняют stage, commit или push.
- [`lib/ModelProject.Platform.psm1`](lib/ModelProject.Platform.psm1) - единые cross-platform primitives для path containment, case semantics, link chain, trusted `git`/`pwsh`, child process, sanitized Git environment, null device, bounded input и temp lock-file.
- [`lib/ModelProject.Knowledge.psm1`](lib/ModelProject.Knowledge.psm1) - portable модуль чистых parser/safety primitives и общего эвристического privacy scanner; entrypoints загружают его только по фиксированному пути относительно доверенного `$PSScriptRoot`, никогда из проверяемого `-Root`, а уникальные business rules остаются в scripts.
- [`lib/ModelProject.Mastery.psm1`](lib/ModelProject.Mastery.psm1) - data-driven контракт Local Mastery, intent catalog и детерминированный registry.
- [`lib/ModelProject.Plan.psm1`](lib/ModelProject.Plan.psm1) - Plan v2 parser, schema, transition rules, deterministic index и worktree checkpoint fingerprint.
- `new-knowledge-candidate.ps1` - после полной валидации атомарно создает один `ready` candidate по разрешенному repository mode и write intent.
- `new-mastery.ps1` - показывает `-WhatIf` preview и только после direct authority применяет один method candidate с rollback, backlink, index, graph и gates.
- `new-plan.ps1`, `set-plan-status.ps1`, `update-plan-checkpoint.ps1` - создают один Plan v2, управляют lifecycle и сохраняют resume checkpoint.
- `new-analysis-run.ps1` - атомарно создает exact eight-file analysis run в допустимом generated mode.
- `verify-analysis.ps1` - проверяет run lifecycle, formal artifact namespace, method refs, attachments, Mermaid, traceability и safety; поддерживает `-Report` и `-SelfTest`.
- `test-it-analysis-semantics.ps1` - source-only offline runner проверяет normalized JSON fixtures и независимые forward-test results по IDs, refs, relations и verdicts без model, network или MCP calls.
- `verify-codex-agents.ps1` - статически проверяет точный TOML-контракт пяти read-only ролей и лимит трех specialist threads.
- `verify-template-sanitization.ps1` - блокирует project-specific traces, PII, credentials и абсолютные пользовательские пути в source или consumer payload.
- `verify-knowledge.ps1` - проверяет project modes, candidates, RAW, evidence, mastery и root reachability; поддерживает `-Report` и `-SelfTest`.
- `update-knowledge-graph.ps1` - детерминированно строит или проверяет tracked `knowledge/graph/INDEX.md`; поддерживает `-Mode Check | Write | Report | SelfTest`.
- `update-mastery-index.ps1` - детерминированно строит или проверяет `mastery/local/INDEX.md` по `mastery/INTENTS.json` и Local Mastery v2.
- `update-plan-index.ps1` - детерминированно строит или проверяет `plans/INDEX.md`.
- `verify-structure.ps1` - проверяет manifest, reserved roots, Markdown-ссылки, anchors, регистр и пути, затем вызывает trusted graph, mastery, core canon, formal-analysis, Codex agents, plans и knowledge gates.

Source-only `build-github-template.ps1` строит consumer payload из exact clean source tag/commit, сверяет declared repository с GitHub identity `origin`, требует обычный tracked index state всех manifest-файлов, заполняет `TEMPLATE-DISTRIBUTION.json` и проверяет `DistributionTemplate`. Source-only `test-github-template-distribution.ps1` воспроизводит happy path и negative trust fixtures во временных Git repositories. Оба скрипта не входят в generated project.

Source-only `test-mastery-v2.ps1` создает fresh generated project и проверяет preview без мутаций, direct authority, apply, data-driven intents, stale registry и SHA-точный rollback. Расширенный `test-knowledge-mastery.ps1` сохраняет baseline, supersedes, overdue и research-use regressions.

Source-only `test-it-analysis-semantics.ps1` хранит eval corpus вне consumer payload. Его normalized projection допускает pre-materialization intake без canonical subject только для exact closed reasons `missing-evaluable-subject` и `quarantined-before-materialization` при отрицательном verdict и всех закрытых guards. Это не `REV-*`, не canonical handoff и не ослабление обязательных `subject_refs` в analysis contract. Consumer получает усиленные methods и run assets, но не frozen semantic fixtures.

Source-only `test-platform.ps1` и `test-cross-platform-bootstrap.ps1` проверяют Windows/macOS semantics, local copy и GitHub-style initialization. Consumer-boundary test дополнительно проверяет URL-first distribution copy -> independent generated project. Workflow `.github/workflows/template-integrity.yml` запускает ключевые gates на `windows-latest` и `macos-latest` и не входит в consumer payload.

## Portable manifest

`.template-manifest.json` является единственным источником:

- переносимых файлов и пустых каталогов;
- Git-tracked `.gitkeep` marker для пустого корня `research/runs`, чтобы он сохранялся после настоящего clone;
- source-only истории шаблона;
- запрещенных generated paths;
- extension zones контролируемых деревьев;
- версии и SHA-256 Researcher и Analyst Mastery baseline.

До и после копирования проверяются exact inventory, descriptor hashes, traversal, case и reparse points. UNC, device и сетевые destinations запрещены. При ошибке final destination не появляется, а удаляется только проверенный GUID-staging без перехода по reparse points. `.git` source, source-maintenance artifacts, заполненные runs и candidates не копируются. Exact `.codex`, четыре `.agents/skills` и portable `new-project.ps1` входят в consumer; посторонние роли и skills блокируются. В generated project выбранный стек может создавать `src/`, `tests/`, `package.json` и другие пути вне template-controlled roots.

## Режимы проверки

```powershell
.\scripts\verify-structure.ps1 -Mode TemplateSource
.\scripts\verify-structure.ps1 -Mode DistributionTemplate
.\scripts\verify-structure.ps1 -Mode GeneratedProject
.\scripts\verify-structure.ps1 -Mode Auto
```

- `TemplateSource` требует placeholders и статус `template`, проверяет portable Markdown-граф от `INDEX.md`, статический source-maintenance граф от `TEMPLATE.md`, пустые runs/candidates/local mastery и точные project-local mastery, skills и Codex agents. Source-only plan, ADR, retrospective и regression harness не требуют consumer reachability.
- `DistributionTemplate` требует производный `distribution-template + template + disabled`, exact descriptor и pre-init payload hashes. Semantic project gates выполняются после инициализации, когда repository становится generated.
- `GeneratedProject` принимает `initialized`, `active` или `archived` только с согласованным capture mode, сохраняет exact read-only `.codex`, запрещает все source-only пути и защищает contract roots.
- `Auto` выбирает режим по `repository_kind`.

Параметр `-Root` всегда считается данными. Structural verifier вызывает semantic verifier только рядом с собственным доверенным `$PSScriptRoot` и не запускает Git внутри произвольного внешнего root. Внешние `git` и PowerShell host разрешаются как точные application-файлы вне контролируемого root и без reparse chain. Git subprocess не наследует управляющие `GIT_*`, не читает system/global config, ограничивает вывод, а linked worktree принимается только с обратной ссылкой административного `gitdir` на текущий `.git` marker. Markdown URI, frontmatter и evidence проверяются до использования; опасные схемы, credential-bearing URLs, reparse points и превышение файловых лимитов блокируются.

Bootstrap и structural child processes запускаются через отдельный `ProcessStartInfo`: `GIT_*` очищаются только в окружении ребенка, exit code берется из process object, а PowerShell output декодируется как UTF-8. Bounded `git ls-files` читает stdout построчно и останавливается при лимите tracked paths.

Semantic commands:

```powershell
.\scripts\verify-knowledge.ps1
.\scripts\verify-knowledge.ps1 -Report
.\scripts\verify-knowledge.ps1 -SelfTest
.\scripts\verify-analysis.ps1 -SelfTest
.\scripts\test-it-analysis-semantics.ps1 -SelfTest
.\scripts\verify-codex-agents.ps1 -SelfTest
.\scripts\update-knowledge-graph.ps1 -Mode Check
.\scripts\update-knowledge-graph.ps1 -Mode Write
.\scripts\update-knowledge-graph.ps1 -Mode Report
.\scripts\update-knowledge-graph.ps1 -Mode SelfTest
.\scripts\update-mastery-index.ps1 -Mode Check
.\scripts\update-mastery-index.ps1 -Mode Write
.\scripts\update-plan-index.ps1 -Mode Check
```

Чистота `research/runs/` и `knowledge/candidates/` обязательна непосредственно после `new-project.ps1`. Позднее generated project допускает валидные динамические записи; plans и Local Mastery получают производные индексы.

Скрипты не используют сеть и не читают `.env`. URL clone и cleanup temporary source выполняет Codex по публичному install prompt после audit; bootstrap scripts работают только с уже локальными файлами.
