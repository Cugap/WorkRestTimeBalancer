# WorkRestTimeBalancer

Приложение для баланса работы и отдыха в течение рабочего дня (Android, iOS, Windows).

## Структура

- `core/` — чистое Dart-ядро (`work_rest_core`): рабочий день и правила ритма. Без импортов Flutter, тестируется без UI.
- `app/` — Flutter-оболочка: экраны, уведомления, хранение, системные интеграции. Состояние и время считает только ядро.

Подробности — в [AGENTS.md](./AGENTS.md), [GLOSSARY.md](./GLOSSARY.md), [`docs/adr/`](./docs/adr) и спецификации MVP в `.scratch/mvp/spec.md`.

## Разработка

```powershell
# ядро: тесты и анализ
cd core
dart pub get
dart test
dart analyze

# приложение: тесты и анализ
cd app
flutter pub get
flutter test
flutter analyze

# запуск на Windows
flutter run -d windows
```

Сборка под Android требует Android SDK и JDK 17+, под iOS — macOS с Xcode, под Windows — Visual Studio с workload «Desktop development with C++».
