# Знания проекта

Этот файл является единой project-local политикой маршрутизации, накопления и продвижения знаний. Он не заменяет предметный канон и не дает разрешения писать во внешнюю общую базу.

## Граница гарантий

Knowledge control plane остается agent-driven:

```text
intent
-> repository mode
-> owner
-> artifact kind
-> domain
-> authority
-> target
-> knowledge closeout
-> derived knowledge graph
-> strict verifier
```

Скрипты fail-closed проверяют детерминированные структуру, режим, ссылки, state, известные safety-классы и итоговый worktree. Они не доказывают смысловую истинность claim, реальное наличие consent, отсутствие любой возможной PII, semantic owner или semantic duplicate. Эти решения принимает агент по фактическому контексту.

Автоматического daemon, watcher, event ledger, promotion или delete нет. Автопополнение означает обязательный closeout после write-задачи, а не фоновую запись. Markdown остается каноном, Git хранит историю состояний.

## Режимы и capture

Источник режима находится во frontmatter `PROJECT.md`.

| Состояние | Capture mode | Поведение |
|---|---|---|
| `template-source + template` | `disabled` | Только развитие шаблона |
| `distribution-template + template` | `disabled` | Только проверка consumer payload и однократная инициализация |
| `generated-project + initialized` | `report-only` | Паспорт, planning, research и прямо разрешенный RAW |
| `generated-project + active` | `report-only` | Полный цикл без automatic candidate |
| `generated-project + active` | `safe-local` | Полный цикл и automatic project-local candidate при наличии Git `HEAD` |
| `generated-project + archived` | `disabled` | Read-only, кроме отдельного restore или прямо разрешенного точечного delete |

`knowledge_capture_mode` регулирует automatic capture, но не подменяет прямое разрешение пользователя:

- `disabled` запрещает project candidates и promotion;
- `report-only` запрещает automatic candidate, но допускает прямо запрошенный project-local candidate, RAW capture и promotion с проверенным authority;
- `safe-local` допускает automatic ready candidate в пределах noise budget, но не допускает automatic promotion;
- shared-owner и external write из этого репозитория всегда блокируются.

`safe-local` требует доверенный Git `HEAD`, где уже находятся generated `PROJECT.md` с тем же `project_id` и тот же `TEMPLATE-ORIGIN.md`. Pre-init GitHub Template commit не является baseline. Без подходящего HEAD automatic capture возвращает `blocked: missing-git-baseline`. `active + report-only` может существовать без commit.

Текущий `knowledge_capture_mode` применяется к новой попытке записи. Он не аннулирует исторический `ready` candidate после разрешенного перехода проекта из `safe-local` в `report-only`: snapshot verifier проверяет структуру и заявленную provenance существующего artifact, но не утверждает, в каком режиме тот был создан. Реальный режим и authority в момент записи обеспечиваются public generator и агентом; `authority_ref` остается декларацией, а не криптографическим доказательством.

## Authority

`authority_ref` является декларацией provenance, а не доказательством реального consent. Допустимы только:

- `policy:knowledge-contract-v1` для automatic ready candidate в `safe-local`;
- `user-request:<safe-stable-task-ref>` для прямого RAW capture, candidate creation, dismissal или promotion;
- безопасный относительный путь на существующий accepted ADR с `artifact_kind: decision` и `status: accepted`.

Не сохраняй полный prompt, произвольный свободный текст, секрет или чувствительное значение как authority. Параметр `-WriteIntent automatic-capture | explicit-promotion` выбирает write path, но сам не является authority. Curator обязан проверить прямую команду текущей задачи.

## Таблица маршрутов

| Intent | Допустимый режим | Owner | Artifact | Target | Gate |
|---|---|---|---|---|---|
| Ответ, обзор, аудит, диагностика | Любой | Нужный owner | Результат задачи | Нет записи | Возможные candidates только в ответе |
| Изменить или построить | По `PROJECT.md` | Project | Код или канон | Запрошенный scope | Pre-task snapshot и closeout |
| Сохранить разрешенный RAW | `initialized`, `active` | Project | RAW | `inbox/raw/` | Прямая capture-команда, scope и authority |
| Собрать evidence | `initialized`, `active` | Project | Research run | `research/runs/` | `$startup-researcher` |
| Выполнить значимое изменение | `active` | Project | Plan, код, tests и docs | `plans/` и stack-native paths | `$project-delivery`, Plan v2 и closeout |
| Обновить подтвержденный предметный канон | `initialized`, `active` | Project | Canon | `product/`, `business/`, `docs/architecture/` или `docs/codebase/` | Direct authority, candidate/backlink и canon gate |
| Automatic durable delta | `active + safe-local` с HEAD | Project | Candidate | `knowledge/candidates/` | `$knowledge-curator` |
| Прямо создать candidate | `initialized + report-only`, `active + report-only` или `active + safe-local` | Project | Candidate | `knowledge/candidates/` | `user-request:...` |
| Применить candidate | `initialized + report-only`, `active + report-only` или `active + safe-local` | Project | Canon | Разрешенный режимом точный `target_ref` | Authority, backlink и strict gate |
| Предложить устойчивый локальный метод | `active + safe-local` либо explicit capture | Project | `type: method` candidate | `mastery/local/INDEX.md#зарегистрированные-расширения` | Learning evidence и review due |
| Применить локальный метод | `initialized` или `active` | Project | Local mastery | `mastery/local/<method-id>.md` | Direct authority, candidate backlink, graph refresh |
| Общий или межпроектный вывод | Любой | Shared | Сообщение | Нет локальной записи | Отдельная задача во внешней базе |
| Restore archived | `archived + disabled` | Project | Mode change | `initialized + report-only` | Прямая restore-команда |
| Удалить чувствительные данные | Включая archived | Project | Dependency report | Точные разрешенные цели | Отдельная delete-команда |

## Pre-task snapshot и фактический diff

До изменений в write-задаче зафиксируй без изменения index:

```text
git status --porcelain=v1 -z
git diff HEAD
git diff --cached
git ls-files --others --exclude-standard
```

Если HEAD отсутствует, зафиксируй это как состояние snapshot; не выдавай недоступный `git diff HEAD` за пустой diff. Для `safe-local` отсутствие HEAD дополнительно блокирует automatic capture.

Closeout обязан учитывать tracked unstaged, staged, untracked, deleted и renamed paths и отделять их от pre-existing dirty state. Обычный пустой `git diff` при наличии untracked paths недостаточен. Если pre-task snapshot отсутствует, не угадывай происхождение изменений и верни `blocked: missing-diff-baseline`.

## Durable knowledge delta

Создавай candidate только если один атомарный claim одновременно:

1. Новый и отсутствует в каноне и existing candidates.
2. Полезен для будущей задачи, решения или проверки.
3. Снижает заметный риск повторить ошибку или принять иное решение.
4. Имеет project-local owner, тип, точные источники и предполагаемый target.
5. Не является временным состоянием, очевидным содержимым кода, теста или уже принятого ADR.
6. Не содержит RAW, секретов, PII, полного diff или стороннего verbatim-контента.
7. Может быть проверен или опровергнут отдельно.

`none` и `existing` не зависят от capture mode. Для обычной change/build-задачи automatic noise budget равен одному candidate, для research максимум трем.

## Candidate lifecycle

Путь:

```text
knowledge/candidates/YYYY/KC-YYYYMMDD-HHmmss-<8hex>.md
```

Каноническая схема находится в [`candidates/TEMPLATE.md`](candidates/TEMPLATE.md). Один файл содержит один claim.

```text
ready -> applied
      -> dismissed
```

- `ready` может содержать `conflict_refs`, которые обозначают только нерешенные конфликты;
- `applied` требует существующие source и target, Markdown-backlink, authority, `applied_at` и пустой `conflict_refs`;
- `dismissed` требует допустимый `dismiss_reason` и authority;
- applied и dismissed являются terminal states;
- `applied_at >= created_at`, а state dates не находятся существенно в будущем;
- `supersedes` не ссылается на себя, существующий ID обязателен, циклы запрещены;
- historical `ready:<id>` в завершенном plan, retrospective или research decision остается валидным после позднего applied или dismissed;
- historical `applied:<id>` требует, чтобы candidate оставался applied.

Просрочка `review_due` попадает в report, но не меняет state и ничего не удаляет автоматически.

## Обучаемые методы

Минимальная обучаемость использует тот же candidate lifecycle, без отдельной базы и без автоматического изменения инструкций. Method candidate обязан иметь:

- `type: method`, `domain: mastery`;
- `method_kind: heuristic | checklist | workflow | standard`, короткий `method_summary` и непустой `method_applies_to` из [`mastery/INTENTS.json`](../mastery/INTENTS.json);
- `claim_key: method.<id>`;
- `target_ref: mastery/local/INDEX.md#зарегистрированные-расширения`;
- `confidence: medium | high` и непустой `review_due`;
- либо два независимых завершенных task/run source, либо `capture_basis: explicit-user-capture` с direct `user-request:...` authority и хотя бы одним project source.

Два файла одного run не считаются двумя независимыми источниками. Promotion никогда не выполняется автоматически. После прямого одобрения `scripts/new-mastery.ps1` сначала запускается с `-WhatIf`, затем отдельной командой без него. Он создает один `mastery/local/<method-id>.md`, применяет candidate, пересобирает derived registry и graph, добавляет backlink из registry и запускает gates с rollback при ошибке. Если оператор не указал срок, generator назначает `review_due` через 180 дней. Overdue, deprecated и superseded методы исключаются из автоматического выбора.

## Review, dismissal и promotion

Перед dismissal проверь candidate, reason, authority и отсутствие неразрешенного внешнего write. Допустимые причины: `rejected`, `duplicate`, `expired`, `superseded`.

Promotion является восстановимым проверяемым change set, а не межфайловой транзакцией:

1. Проверить ready candidate, target, authority, review due и конфликты.
2. Обновить canonical target.
3. Добавить видимый Markdown-backlink на candidate.
4. Установить `state: applied`.
5. Установить `applied_at` и `authority_ref`.
6. Очистить разрешенные `conflict_refs`.
7. Запустить strict verifier.
8. Считать promotion завершенным только после зеленого gate.

До зеленого gate change set остается незавершенным и должен быть исправлен в разрешенном scope. Git обеспечивает восстановимую историю итогового worktree. Не заявляй полную или межфайловую атомарность.

## Provenance и ссылки

Для примененного знания обязателен граф:

```text
source -> candidate -> canonical target
                     <- backlink
```

- Внутренние `source_refs` ведут на точные существующие файлы, а не каталоги.
- Внутренние refs и `target_ref` являются безопасными относительными путями с exact case, без traversal и reparse.
- Внешний source задается безопасным HTTPS URL или зарегистрированным logical identifier, но не абсолютным локальным путем.
- Namespace `logical:shared-mastery/*` не настраивается этим шаблоном и блокируется. Внешние методы подключаются только явной задачей и не становятся project-local target автоматически.
- RAW и evidence не переписываются ради backlink.
- Portable static canon должен быть достижим от корневого `INDEX.md`. В `template-source` статический source-maintenance canon дополнительно должен быть достижим от source-only `TEMPLATE.md`; historical plans/retrospectives и динамические RAW, runs и candidates не входят в этот root graph.

## Производный граф знаний

[`graph/INDEX.md`](graph/INDEX.md) является tracked deterministic-представлением canonical refs и backlinks. Он ускоряет человеку и skill-ам поиск связанного контекста, но не владеет нормативным текстом и не заменяет frontmatter refs.

В граф входят active product/business/architecture/codebase canon, approved formal-analysis artifacts, accepted ADR, active `mastery/local` и knowledge candidates. `PROJECT.md`, idea, plans, research runs, analysis runs, RAW и retrospectives остаются owner artifacts или evidence, но не становятся graph nodes. Граф содержит обычные переносимые Markdown-ссылки и дополнительные root-relative Wikilinks.

Публичный контракт:

```powershell
.\scripts\update-knowledge-graph.ps1 -Root <path> -Mode Check
.\scripts\update-knowledge-graph.ps1 -Root <path> -Mode Write
.\scripts\update-knowledge-graph.ps1 -Root <path> -Mode Report
.\scripts\update-knowledge-graph.ps1 -Mode SelfTest
```

`Write` пересобирает только `knowledge/graph/INDEX.md` атомарно. `Check` сравнивает точные байты с ожидаемым результатом. Ручная правка, stale graph, unsafe input, reparse, traversal, неверный регистр или превышение лимита блокируют structure gate. `Report` ничего не изменяет. После разрешенного изменения канона, candidate lifecycle или local mastery сначала выполняется `Write`, затем strict verification.

## RAW

RAW создается только по прямой просьбе пользователя сохранить материал. Канонический frontmatter:

```yaml
id:
captured_at:
storage_basis: null | explicit-user-request | authorized-import
authority_ref: null | user-request:...
data_class: public | internal | sensitive
content_mode: summary | verbatim
personal_data: none | anonymized
retention:
source:
rights:
author:
scope:
status: captured | reviewed | rejected | retention-due
related: []
```

В пустом template обязательно стоят `storage_basis: null` и `authority_ref: null`; template не утверждает consent. Для реального RAW null basis или authority блокируется.

Правила fail-closed:

- `sensitive + verbatim` запрещен;
- secret, token, API key, bearer, cookie, signed URL и URL credentials запрещены;
- email, телефон, явные ФИО, домашний адрес и дата рождения блокируются известными safety-классами;
- полный interview transcript и полный сторонний verbatim без допустимых прав запрещены;
- `personal_data: anonymized` не отключает scanner;
- verbatim допустим только при разрешенных правах и отсутствии запрещенных данных;
- неизвестное safety-состояние блокируется;
- diagnostics выводят только безопасный finding code и относительный path, но не найденное значение.

После capture payload не переписывается. Разрешено изменять только lifecycle frontmatter. Promotion доказывается направлением `RAW -> candidate.source_refs -> applied candidate -> target <- backlink`; RAW не хранит candidate state, target или knowledge outcome.

Полный оригинал интервью остается вне Git. В репозитории допустимы только обезличенные observations/summary и безопасный logical source identifier, не абсолютный путь. Retention overdue попадает в report и ничего не удаляет.

## Research и mastery

Каждый каталог первого уровня в `research/runs/` имеет имя `YYYY-MM-DD-<slug>` и exact-case набор файлов из [run template startup-researcher](../.agents/skills/startup-researcher/assets/run-template/brief.md). Фактический sibling-набор assets является machine source. Partial scaffold, reparse point и `promotion-proposal.md` блокируются.

Safety scan применяется ко всем шести файлам и scalar fields `evidence.jsonl`. Research-derived candidate содержит source на точный `decision.md` текущего run и хотя бы один существующий `evidence:<id>` из его ledger.

Research brief и decision хранят точные baseline method refs, local `method_id` и local refs. Unknown, deprecated, superseded или overdue local method блокируется. Semantic релевантность выбора остается agent-enforced.

## ADR, plans и retrospectives

ADR, plan и retrospective используют строгий frontmatter из своих `TEMPLATE.md`. Machine fields не дублируются декоративными bullet-полями.

Общие правила:

- primary ID из `ready:` или `applied:` входит в `candidate_ids`;
- каждый candidate ID существует;
- `none` не допускает IDs;
- `blocked` требует `blocked_reason`;
- `affected_canon` содержит безопасные существующие paths;
- absent candidate и broken lifecycle refs блокируются;
- `README.md` и `TEMPLATE.md` исключаются из artifact scan.

Для planned/in-progress plan допустим `knowledge_outcome: null`. Complete/blocked plan и любая retrospective требуют финальный historical outcome.

## Archived lifecycle

Archived всегда использует `disabled`, обычные repository writes запрещены.

Прямой restore переводит проект только в `initialized + report-only`. После restore заново выполняются passport и activation gates; `safe-local` включается отдельно и требует Git `HEAD`.

Точечный delete чувствительных project data может выполняться прямо в archived только по отдельной прямой delete-команде после dependency report. Сначала проверь точные абсолютные цели и зависимости, затем удали только разрешенный объем и зафиксируй безопасные logical identifiers. Удаление всего репозитория является отдельной внешней destructive task. Автоматического delete script нет.

## Closeout

Перед финальным ответом по задаче с записью:

1. Сопоставь post-task state с pre-task snapshot.
2. Найди существующий канон и candidates по ключевым словам и `claim_key`.
3. Примени durable delta, owner, authority и data-safety gates.
4. Верни один outcome: `none`, `existing`, `ready:<id>`, `applied:<id>` или `blocked`.
5. Для нескольких research candidates отдельно перечисли полный `candidate_ids`.
6. После изменения канона, candidate lifecycle или local mastery обнови derived graph через `scripts/update-knowledge-graph.ps1 -Mode Write`.
7. Запусти `scripts/verify-knowledge.ps1`; для структуры, routes, mastery или scripts запусти `scripts/verify-structure.ps1`.

Для read-only review используй `scripts/verify-knowledge.ps1 -Report`. Report не изменяет файлы и не печатает sensitive values.

## Тематические маршруты

- [Канон идеи](../idea/INDEX.md)
- [Бизнес-контекст](../business/INDEX.md)
- [Research runs](../research/INDEX.md)
- [Project Mastery и shared identifiers](../mastery/INDEX.md)
- [Researcher Mastery](../mastery/researcher/INDEX.md)
- [Локальные расширения mastery](../mastery/local/INDEX.md)
- [Производный граф знаний](graph/INDEX.md)
- [Архитектурные решения](../docs/decisions/README.md)
- [Планы](../plans/README.md)
- [Ретроспективы](../retrospectives/README.md)
