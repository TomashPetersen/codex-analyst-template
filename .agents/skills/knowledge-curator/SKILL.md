---
name: knowledge-curator
description: Безопасно завершает project-local change, build или research через pre-task Git snapshot, анализ фактического diff, durable-delta gate, review, dismissal и разрешенное promotion central candidate. Использовать для обязательного knowledge closeout после записи в репозиторий, прямого capture или promotion. Не использовать для скрытого RAW, shared knowledge, персональных данных, external write или delete.
---

# Knowledge Curator

Этот skill исполняет closeout, но не является вторым policy-файлом. Режимы, authority, durable delta, candidate lifecycle, RAW, promotion и archived lifecycle канонически определены в [`knowledge/INDEX.md`](../../../knowledge/INDEX.md).

## Подготовить контекст

1. Полностью прочитать `PROJECT.md`, корневой `INDEX.md` и `knowledge/INDEX.md`.
2. Определить маршрут `intent -> repository mode -> owner -> artifact kind -> domain -> authority -> target`.
3. Для write-задачи до изменений зафиксировать read-only snapshot без изменения index:

```text
git status --porcelain=v1 -z
git diff HEAD
git diff --cached
git ls-files --others --exclude-standard
```

Если HEAD отсутствует, зафиксировать это как состояние, а не пустой diff. Если snapshot отсутствует, вернуть `blocked: missing-diff-baseline`.

## Собрать фактический diff

Сопоставить post-task state со snapshot. Учитывать tracked unstaged, staged без изменения index, untracked, deleted и renamed paths. Отделить pre-existing dirty state от изменений текущей задачи и не выводить delta только из истории чата.

## Выполнить durable-delta gate

1. Начать с dry-run и поиска существующего канона/candidates.
2. Проверить текущие mode, owner, authority и write intent по canonical [режимам](../../../knowledge/INDEX.md#режимы-и-capture) и [authority](../../../knowledge/INDEX.md#authority).
3. Применить критерии раздела [Durable knowledge delta](../../../knowledge/INDEX.md#durable-knowledge-delta) и noise budget.
4. Для answer, review, audit и diagnose не создавать knowledge-файл.
5. Вернуть ровно один основной итог:

```text
none | existing | ready:<candidate-id> | applied:<candidate-id> | blocked
```


`none` и `existing` не зависят от capture mode. Для `blocked` указывать безопасную точную причину. При нескольких research candidates выбрать основной влияющий claim, а полный упорядоченный список вернуть как `candidate_ids`.

## Создать candidate

1. Проверить source refs, target, normalized claim key, case-insensitive дубли, conflicts и safety.
2. Вызвать `scripts/new-knowledge-candidate.ps1` с разрешенными `WriteIntent` и `AuthorityRef` из canonical policy.
3. Не создавать draft и не исправлять неполный final после публикации.
4. Обработать controlled duplicate как `existing` с ID существующего candidate.
5. Запустить `scripts/verify-knowledge.ps1` и показать пользователю ID, claim, path и state.

Для устойчивого улучшения аналитического процесса используй обычный `type: method` candidate, а не редактируй skill или `mastery/local` автоматически. Такой candidate проходит дополнительные gates из [Обучаемых методов](../../../knowledge/INDEX.md#обучаемые-методы): точные domain/claim/target, medium или high confidence, review due и независимые learning sources либо явная коррекция оператора.

RAW не является candidate и сохраняется только по прямой просьбе по разделу [RAW](../../../knowledge/INDEX.md#raw).

## Review и dismissal

Следовать canonical [candidate lifecycle](../../../knowledge/INDEX.md#candidate-lifecycle) и [review contract](../../../knowledge/INDEX.md#review-dismissal-и-promotion). Перед изменением проверить state, review due, sources, conflicts, target, authority и `supersedes` graph. Не переписывать historical outcomes.

## Продвинуть candidate

Выполнить восстановимый change set, не называя его межфайловой атомарной операцией:

1. Проверить ready state, target, authority, review due и unresolved conflicts.
2. Обновить canonical target.
3. Добавить видимый Markdown-backlink на candidate.
4. Установить `state: applied`.
5. Установить `applied_at` и `authority_ref`.
6. Очистить разрешенные `conflict_refs`; applied candidate обязан иметь пустой список.
7. Запустить strict verifier.
8. Считать promotion завершенным только после зеленого gate.

Для method candidate прямое promotion дополнительно создает один файл из [`mastery/local/TEMPLATE.md`](../../../mastery/local/TEMPLATE.md), регистрирует его обычной ссылкой в local INDEX, добавляет backlink на applied candidate и ставит review due. Это не дает права менять baseline mastery или сам skill.

При ошибке исправить незавершенный change set в разрешенном scope. Не изменять RAW/evidence ради backlink и не выполнять shared write. Archived restore/delete следует только canonical [archived lifecycle](../../../knowledge/INDEX.md#archived-lifecycle) и отдельной прямой команде.

## Завершить closeout

Перед финальным ответом:

1. После изменения предметного канона, candidate lifecycle или local mastery запустить `scripts/update-knowledge-graph.ps1 -Mode Write`.
2. Запустить `scripts/verify-knowledge.ps1`.
3. После изменения структуры, routes, mastery или scripts запустить `scripts/verify-structure.ps1`; он независимо проверит актуальность графа.
4. Сопоставить итоговый state с pre-task snapshot и зафиксировать основной outcome.
5. Показать все automatic candidate IDs и полный `candidate_ids` для research.
6. Для `blocked` указать безопасную причину без скрытой записи.
7. Не печатать secret, sensitive value или небезопасный locator.
