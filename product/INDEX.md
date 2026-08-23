# Продукт - каноническая карта

Эта зона хранит подтвержденные знания о продукте. Гипотезы и evidence до подтверждения остаются в [`idea/`](../idea/INDEX.md) и [`research/`](../research/INDEX.md). Каждый canon-файл имеет status `template`, `active` или `deprecated`; в knowledge graph входит только `active`.

- [`overview.md`](overview.md) - назначение, ценность, границы и стадия.
- [`users-and-jobs.md`](users-and-jobs.md) - пользователи, контекст и jobs-to-be-done.
- [`experience.md`](experience.md) - ключевые сценарии и ожидаемый опыт.
- [`capabilities.md`](capabilities.md) - продуктовые способности без привязки к реализации.
- [`glossary.md`](glossary.md) - единые термины.

Перед canonical записью отделяй подтвержденное от hypothesis, указывай безопасные `source_refs`, дату проверки и прямое authority. Историю выбора храни в [`docs/decisions/`](../docs/decisions/README.md), а реализацию - в коде и тестах.
