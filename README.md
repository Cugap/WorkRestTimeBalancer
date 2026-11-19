# WorkRestTimeBalancer

Приложение для баланса работы и отдыха в течение рабочего дня (Android, Windows).

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

## Сборка под Android

Нужны Android SDK с платформой `android-37` (её требует `compileSdk 37` из-за
`flutter_local_notifications`), build-tools 36+ и JDK 17+. Flutter берёт JDK из
Android Studio, пока путь не задан через `flutter config --jdk-dir`.

```powershell
# проверка SDK, JDK и лицензий: у Android toolchain должны стоять галочки
flutter doctor -v

cd app
flutter pub get

# отладочная сборка: app\build\app\outputs\flutter-apk\app-debug.apk
flutter build apk --debug
```

Путь к Android SDK Flutter записывает в `app/android/local.properties` при первой
сборке (`sdk.dir=...`, рядом `flutter.sdk=...`); файл машинно-зависимый и в
репозиторий не попадает.

Установка на подключённый телефон или эмулятор:

```powershell
flutter devices                     # список устройств и их id
flutter emulators                   # список эмуляторов
flutter emulators --launch <name>   # запуск эмулятора
flutter install -d <device-id>      # установка собранного APK

# либо напрямую
adb install -r app\build\app\outputs\flutter-apk\app-debug.apk
```

Release-сборка (`flutter build apk --release`) сейчас подписывается debug-ключом
из `app/android/app/build.gradle.kts` — для публикации нужен собственный
keystore. Если Gradle падает на инкрементальной компиляции Kotlin, помогает
`flutter build apk --debug -P kotlin.incremental=false`.

Сборка под Windows требует Visual Studio с workload «Desktop development with
C++»; запуск — `flutter run -d windows`. Целевые платформы MVP — Android и
Windows; iOS выведен из MVP (см.
[docs/adr/0006-bez-ios-v-mvp.md](./docs/adr/0006-bez-ios-v-mvp.md)).
