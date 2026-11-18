# 17: Разделить движок ритма и планировщик напоминаний

**What to build:** `WorkDayEngine` меняется по шести независимым причинам: правила ритма, отложения, обед, выбор упражнений, сериализация рабочего дня и проецирование напоминаний. Вынести планирование напоминаний и выбор упражнений в отдельные модули, которые движок вызывает, но чьи правила живут отдельно.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] Проекция напоминаний (`_reminderPlan`, `_reminderCounters`, `_offerPriority`) вынесена из движка в самостоятельный модуль с одним входом: счётчики ритма и настройки → раскладка.
- [x] Правила продвижения счётчиков («какой отдых важнее», «что сбрасывает счётчик») не дублируются: планировщик и `_endRest`/`_skipAt` используют один общий код вместо двух копий.
- [x] Выбор упражнений вынесен из движка; таблица «вид отдыха → длительность, число упражнений, сдвиг счётчиков» собрана в одном месте вместо семи `switch` по `RestKind`.
- [x] Существующие тесты ядра продолжают проходить без изменения проверяемого поведения.

## Comments

- Заведено по итогам код-ревью интеграционной ветки `mvp` (оси Standards, judgement calls «Divergent Change», «Duplicated Code», «Repeated Switches»). Сознательно не исправлено в рамках реализации спецификации: это переписывание проверенной логики, а не дефект поведения.
- Конкретика: `core/lib/src/work_day_engine.dart` — 1320 строк; `_reminderPlan` повторяет правила продвижения счётчиков из `_endRest`/`_skipAt` и копирует список кандидатов и сортировку из `_scheduleNextOffer`; по `RestKind` есть семь каскадов (`_skipAt`, `_endRest`, `_reminderPlan`, `_reminderCounters`, `_offerPriority`, `_exerciseCountFor`, `_restDurationFor`), хотя длительность, число упражнений и сдвиг счётчиков — свойства одного вида.
- Сделано: `core/lib/src/reminder_plan.dart` — раскладка одним входом `planReminders(counters, from, workWindowEndsAt, settings, limit)`; `core/lib/src/rest_counters.dart` — `RestCounters`, `countersAfterRest`, `countersAfterSkip`, `nearestRestPoint`, общий порядок точек; `core/lib/src/rest_kind_profile.dart` — таблица «вид отдыха → длительность, число упражнений, приоритет»; `core/lib/src/exercise_picker.dart` — `pickExercises` по кругу без повтора и с разными категориями.
- Движок теперь только держит состояние и спрашивает модули: `_reminderPlan` делегирует в `planReminders`, `_endRest` и `_reminderCounters` используют `countersAfterRest`, `_skipAt` — `countersAfterSkip`, `_scheduleNextOffer` — `nearestRestPoint`, `_exercisesFor` — `pickExercises`. `_offerPriority`, `_exerciseCountFor`, `_restDurationFor`, `_takeExercises` удалены; `switch` по `RestKind` в движке не осталось.
- Проверено: `dart analyze` — чисто, `dart test` — 194 теста (193 прежних + регрессия тикета 15), поведение не менялось, ни один существующий тест не правился; `flutter analyze` и `flutter test` (62) тоже зелёные.
- Код-ревью коммита нашло регрессию в извлечении правил пропуска: старый `_skipAt` отодвигал прошедшую длинную точку для любого вида отдыха, кроме `long`, то есть и для обеда, а `countersAfterSkip` сначала применял это правило только к короткому отдыху. Из-за этого пропуск обеда, вытеснившего длинный отдых с того же момента (оба в 13:00), давал немедленное предложение длинного отдыха. Исправлено: правило снова действует и для обеда, добавлен тест «пропуск обеда отодвигает длинный отдых с того же момента» (`core/test/meal_test.dart`), `dart test` — 195 тестов.
