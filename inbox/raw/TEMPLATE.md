---
id: raw-YYYYMMDD-HHmm-slug
captured_at: YYYY-MM-DDTHH:mm:ss+00:00
storage_basis: null
authority_ref: null
data_class: public | internal | sensitive
content_mode: summary | verbatim
personal_data: none | anonymized
retention: YYYY-MM-DD | rule
source: logical-source-identifier
rights: user-owned | user-authorized | public-summary | other
author: unknown
scope: idea | product | business | architecture | codebase | project
status: captured | reviewed | rejected | retention-due
related: []
---

# Краткое название

## Сохраненный материал

Только разрешенное пользователем резюме или допустимый дословный фрагмент в соответствии с `content_mode`. Для реального RAW сначала замени null basis и authority на проверенные значения. После capture этот payload не переписывается.

## Классификация

- Факты:
- Наблюдения:
- Мнения:
- Гипотезы:
- Цитаты и права:
- Что проверить:
- Возможные дубли:

Менять после capture разрешено только lifecycle frontmatter. Promotion доказывается внешним графом `RAW -> candidate.source_refs -> applied candidate -> target <- backlink`; RAW не хранит candidate ID, target или knowledge outcome.
