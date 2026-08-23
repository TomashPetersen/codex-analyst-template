# Решения и продвижение выводов

## Hard gates

До сравнительной оценки проверь:

- законность и этичность;
- существование конкретного покупателя;
- наблюдаемую проблему или текущую неудовлетворительную альтернативу;
- достижимость сегмента;
- техническую реализуемость;
- реалистичный путь к экономике;
- критические платформенные или регуляторные зависимости.

Неизвестность не является hard blocker. Hard blocker требует конкретного evidence и не усредняется благоприятными сигналами.

## Направления без псевдоточной суммы

Оцени отдельно:

- проблему и ее частоту;
- тяжесть последствий;
- существующие расходы и workaround;
- покупателя и процесс покупки;
- доступный первый сегмент;
- альтернативы и конкуренцию;
- дистрибуцию;
- экономику;
- техническую реализуемость;
- timing;
- правовые и платформенные риски;
- устойчивость преимущества.

Для каждого направления укажи:

- направление: `благоприятно | смешанно | неблагоприятно | неизвестно`;
- уверенность: `низкая | средняя | высокая`;
- ссылки `evidence:<evidence_id>`;
- противоречия;
- пробелы;
- следующий опровергающий тест.

Направление показывает знак evidence, уверенность показывает качество, прямоту, свежесть и независимость origin groups. `Неизвестно` не равно нейтральному или нулю. Не создавай итоговый балл.

## Допустимые решения

- перейти к следующей проверке;
- сузить сегмент;
- переформулировать гипотезу;
- провести поведенческий тест;
- приостановить;
- отклонить;
- недостаточно данных;
- перспективный кандидат не найден.

Окончательное продуктовое решение принимает пользователь.

## Central knowledge candidate

По умолчанию меняй только `research/runs/`. Если вывод проходит durable delta gate, сначала выполни dry-run `$knowledge-curator`. Не создавай отдельный proposal artifact внутри запуска.

Research может создать не более трех project-local candidates. Для каждого передай curator:

- один атомарный claim;
- ссылки `evidence:<evidence_id>` и точный существующий файл запуска, обычно `research/runs/RUN_ID/decision.md`, как `source_refs`; каталог запуска не является допустимым source;
- независимые `origin_group_id`;
- точный канонический target;
- направление и уверенность;
- противоречия и срок актуальности;
- причину фиксации и предлагаемое изменение;
- write intent и проверенный authority ref.

## Capture mode и authority

- В `report-only` automatic candidate запрещен и возвращает `blocked: report-only`.
- Прямо запрошенный project-local candidate или promotion в `initialized + report-only` либо `active + report-only` допустим с `-WriteIntent explicit-promotion`, если target разрешен текущим mode, и с `user-request:<safe-stable-task-ref>` либо accepted ADR authority.
- В `safe-local` automatic ready candidate допустим только при Git `HEAD`, с `-WriteIntent automatic-capture` и `policy:knowledge-contract-v1`.
- Automatic promotion запрещен во всех режимах.
- Template и archived не принимают candidate promotion.
- Shared owner возвращает `blocked: shared-owner`.

`authority_ref` является provenance, но не доказательством consent. Не используй полный prompt, произвольный текст или чувствительное значение. Сам `WriteIntent` не является authority.

Central candidate ID и полный упорядоченный список IDs записываются в `decision.md`. Один run создает не более трех candidates.

Возможные цели: существующие `idea/deep-research.md`, `idea/references.md`, `idea/why-now.md`, `idea/risks.md` или иной существующий канонический файл.

Не продвигай низкоуверенные claims, unresolved conflicts, PII, динамические значения без механизма обновления, выводы из одного слабого источника, funding, YC acceptance, лайки или поисковый интерес как самостоятельное доказательство спроса.

## Promotion change set

Изменяй `idea/` только если текущий запрос пользователя прямо включает promotion проверенных выводов в точный target. Promotion является восстановимым change set, а не межфайловой транзакцией:

1. Проверить ready candidate, target, authority, review due и conflicts.
2. Обновить существующий canonical target без дублей.
3. Добавить видимый Markdown-backlink.
4. Установить `state: applied`, `applied_at` и `authority_ref`.
5. Очистить unresolved `conflict_refs`.
6. Запустить strict verifier.
7. Считать promotion завершенным только после зеленого gate.

Git сохраняет восстановимую историю итогового worktree. Не заявляй полную или межфайловую атомарность.
