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

## Сборка

Собираются две платформы: Android и Windows. iOS выведен из MVP (см.
[docs/adr/0006-bez-ios-v-mvp.md](./docs/adr/0006-bez-ios-v-mvp.md)).

### Требования

| Что | Версия и зачем |
| --- | --- |
| Flutter | 3.47+ (приносит Dart 3.13); `flutter --version` |
| Android SDK | платформа `android-37` — её требует `compileSdk 37` из-за `flutter_local_notifications`; build-tools 36+; принятые лицензии |
| JDK | 17+; Flutter берёт JBR из Android Studio, пока путь не задан через `flutter config --jdk-dir`. `java` из PATH не используется |
| Visual Studio | workload «Desktop development with C++» и Windows 10 SDK — только для сборки под Windows |
| Windows | включённый режим разработчика — иначе `flutter pub get` не создаст symlink-ссылки плагинов (см. «Решение проблем») |

Одного взгляда на окружение достаточно:

```powershell
flutter doctor -v
```

У Android toolchain и Visual Studio должны стоять галочки.

### Android

```powershell
cd app
flutter pub get

# отладочная сборка (все ABI, debug-ключ)
flutter build apk --debug

# готовый файл: app\build\app\outputs\flutter-apk\app-debug.apk
```

Если Gradle падает на инкрементальной компиляции Kotlin (`Could not close
incremental caches ... kotlin`), соберите с выключенным инкрементом — проверенный
на этой машине обход:

```powershell
flutter build apk --debug -P kotlin.incremental=false
```

Путь к Android SDK Flutter записывает в `app/android/local.properties` при первой
сборке (`sdk.dir=...`, рядом `flutter.sdk=...`); файл машинно-зависимый и в
репозиторий не попадает.

**Установка на устройство.** Отладочный APK содержит все ABI и весит под 200 МБ;
на телефон удобнее ставить собранный файл напрямую:

```powershell
flutter devices                          # список устройств и их id
flutter install -d <device-id>           # установка собранного APK

# либо через adb; -d добавляется, если на телефоне стоит сборка новее
adb devices
adb install -r app\build\app\outputs\flutter-apk\app-debug.apk

# запуск установленного приложения
adb shell monkey -p com.cugap.work_rest_time_balancer 1
```

**Эмулятор.**

```powershell
flutter emulators                        # список эмуляторов
flutter emulators --launch <name>        # запуск
flutter run -d emulator-5554             # запуск с горячей перезагрузкой
```

**Release и подпись.** Сейчас `release` в
[app/android/app/build.gradle.kts](./app/android/app/build.gradle.kts)
подписывается debug-ключом — этого хватает для `flutter run --release` и ручных
проверок, но не для публикации. Свой ключ:

```powershell
# keytool лежит рядом с JDK из Android Studio
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair `
  -v -keystore $env:USERPROFILE\wrb-upload.jks -keyalg RSA -keysize 2048 `
  -validity 10000 -alias upload
```

Затем в `app/android/key.properties` (он, как и `*.jks`, уже в
`app/android/.gitignore` — секреты в репозиторий не попадут):

```properties
storePassword=<пароль>
keyPassword=<пароль>
keyAlias=upload
storeFile=C:/Users/<вы>/wrb-upload.jks
```

и в `build.gradle.kts` — `signingConfigs { create("release") { ... } }` с чтением
этих значений, после чего заменить `signingConfig = signingConfigs.getByName("debug")`
на созданную конфигурацию.

```powershell
flutter build apk --release                            # один APK на все ABI
flutter build apk --release --split-per-abi             # отдельные APK под arm64/armeabi/x86_64
flutter build appbundle --release                       # .aab для Google Play
```

**Разрешения.** Напоминания требуют `POST_NOTIFICATIONS` (спрашивается при
запуске), `SCHEDULE_EXACT_ALARM` и на Android 14+ `USE_FULL_SCREEN_INTENT`;
сборка объявляет их в `app/android/app/src/main/AndroidManifest.xml`. Если
разрешение на точные будильники не выдано, приложение честно работает с
неточными и пишет об этом в настройках.

### Windows

```powershell
cd app
flutter pub get

flutter build windows --debug            # app\build\windows\x64\runner\Debug\work_rest_time_balancer.exe
flutter build windows --release          # app\build\windows\x64\runner\Release\work_rest_time_balancer.exe

flutter run -d windows                   # запуск с горячей перезагрузкой
```

`.exe` не переносится в одиночку: рядом лежат `data\` и DLL из того же каталога —
копируйте папку целиком.

Запланированные уведомления на Windows доставляются только приложению с
идентичностью в системе. Для ручной проверки напоминаний создайте ярлык
`work_rest_time_balancer.exe` в меню «Пуск»: без ярлыка немедленные toast'ы
появляются, а запланированные молча теряются (подробности — тикет 12).

## Решение проблем

- **`flutter pub get` падает на symlink-ссылках** (`Building with plugins
  requires the Windows Developer Mode to be enabled`). Первый путь — включить
  режим разработчика: Параметры → Система → Для разработчиков. Второй — создать
  junction-ы вручную там, где Flutter ждёт symlink:

  ```powershell
  $deps = Get-Content -Raw app\.flutter-plugins-dependencies | ConvertFrom-Json
  $links = 'app\windows\flutter\ephemeral\.plugin_symlinks'
  New-Item -ItemType Directory -Force -Path $links | Out-Null
  foreach ($plugin in $deps.plugins.windows) {
      $link = Join-Path $links $plugin.name
      if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$($plugin.path)" }
  }
  ```

- **`Could not close incremental caches ... kotlin`** — добавить
  `-P kotlin.incremental=false` к команде `flutter build apk`.
- **`flutter doctor` ругается на незакрытые лицензии** —
  `flutter doctor --android-licenses`, принять все.
- **Gradle берёт не ту Java или не видит Android SDK** — посмотреть, что
  настроено, и задать явно:

  ```powershell
  flutter config --list                         # строки android-sdk и jdk-dir
  flutter config --android-sdk D:\tools\androidSDK
  flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
  flutter doctor -v
  ```

  `JAVA_HOME` на JDK 8 сборку не улучшит: для Android нужен JDK 17+.
- **Сборка под Windows падает на MSVC или Windows SDK** — в Visual Studio
  Installer не хватает workload «Desktop development with C++» либо Windows 10
  SDK; `flutter doctor -v` покажет, что именно не видно.
