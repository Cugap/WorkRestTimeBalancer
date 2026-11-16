# iOS: как собрать и проверить

iOS собирается только на macOS с Xcode. На Windows `flutter build ios` и `flutter run` под iOS
не работают, поэтому ниже — самый короткий путь для каждой задачи.

| Что нужно проверить | Самый простой путь |
| --- | --- |
| Логика и UI (Dart и widget-тесты) | эта машина: `dart test`, `flutter test` |
| Что iOS-сборка компилируется: Swift, плагины, `Info.plist` | GitHub Actions, workflow **iOS build** |
| Уведомления, нажатие, холодный запуск на iPhone | Mac + Xcode + бесплатный Apple ID, `flutter run` |
| Поставить сборку на телефон без своего Mac | неподписанный `.ipa` из CI + Sideloadly/AltStore |
| Раздать сборку без кабеля и без 7-дневного лимита | TestFlight (Apple Developer Program) |

## 1. Что проверяется без Mac

```powershell
cd core; dart test; dart analyze
cd app; flutter test; flutter analyze
```

Эти тесты гоняют ядро и UI на Dart VM и не собирают нативный код. Ошибки Swift,
подключения плагинов, подписи и `Info.plist` они не поймают — для этого нужен шаг 2 или 3.

## 2. Сборка без своего Mac: GitHub Actions

В репозитории есть workflow [`.github/workflows/ios-build.yml`](../.github/workflows/ios-build.yml).
Он запускается вручную или на push:

1. Открыть вкладку **Actions** → **iOS build** → **Run workflow**.
2. Дождаться зелёной сборки: на macOS-раннере выполняются `flutter analyze`, `flutter test`,
   `flutter build ios --release --no-codesign`.
3. Скачать артефакт `ios-runner-unsigned`: внутри `Runner.app` и
   `WorkRestTimeBalancer-unsigned.ipa`.

Сборка без подписи доказывает, что проект компилируется под iOS и ничего не сломано в
нативном слое. Запустить её на устройстве или в симуляторе workflow не может — это шаги 3–5.
В приватном репозитории macOS-раннер расходует минуты с коэффициентом ×10, поэтому
push-триггер ограничен путями `app/**` и `core/**`.

## 3. Проверка на iPhone через Mac (самый короткий ручной путь)

Нужен любой Mac с Xcode и iPhone под рукой. Аккаунт разработчика не нужен: бесплатный Apple ID
подписывает сборку на 7 дней.

1. Установить Xcode из App Store, открыть его один раз и принять лицензию:

   ```bash
   sudo xcodebuild -runFirstLaunch
   ```

2. Установить Flutter (`brew install --cask flutter` или архив с flutter.dev) и проверить окружение:

   ```bash
   flutter doctor
   ```

   В отчёте должен быть зелёным Xcode; CocoaPods нужен только если появится плагин без
   поддержки SwiftPM.

3. Забрать проект и зависимости:

   ```bash
   git clone https://github.com/Cugap/WorkRestTimeBalancer.git
   cd WorkRestTimeBalancer/app
   flutter pub get
   ```

4. Настроить подпись: открыть `ios/Runner.xcworkspace`, выбрать таргет **Runner** →
   **Signing & Capabilities** → включить **Automatically manage signing** и выбрать свою команду
   (**Personal Team**). Apple ID добавляется в Xcode → **Settings** → **Accounts**. Если
   `com.cugap.workRestTimeBalancer` уже занят другим аккаунтом, заменить Bundle Identifier на
   свой, например `com.cugap.workRestTimeBalancer.dev`.

5. Подготовить iPhone: iOS 15+, включить **Settings → Privacy & Security → Developer Mode**,
   подключить кабелем и подтвердить доверие компьютеру.

6. Запустить:

   ```bash
   flutter devices
   flutter run -d <id-устройства>
   ```

   Либо открыть `ios/Runner.xcworkspace` и нажать **Run**.

Ограничения бесплатного Apple ID: сборка живёт 7 дней, одновременно можно держать 3 приложения,
через неделю нужно запускать заново из Xcode. Локальные уведомления работают, платные
capabilities — нет.

**Симулятор** вместо телефона: `open -a Simulator`, затем `flutter run -d "iPhone 16"`. Удобно
для UI, но доставку уведомлений на заблокированный экран и системный лимит так не проверить.

## 4. Без Mac вообще: подписать сборку из CI вручную

1. Собрать `.ipa` в GitHub Actions (шаг 2) и скачать артефакт.
2. На Windows установить Apple Devices и Sideloadly (или AltStore).
3. Подключить iPhone, перетащить `.ipa` в Sideloadly, указать Apple ID — утилита подпишет
   сборку бесплатным сертификатом и установит её.

Ограничения те же: 7 дней и 3 приложения. Apple ID вводится только в доверенной утилите; для
аккаунта с двухфакторной аутентификацией используйте пароль приложения и отзывайте его после.

## 5. TestFlight: сборка на телефон без кабеля и без недельного лимита

Нужен Apple Developer Program и приложение в App Store Connect:

1. Создать запись приложения с bundle id `com.cugap.workRestTimeBalancer`.
2. Собрать и подписать сборку в облаке: Codemagic (пресет Flutter, бесплатный тариф) или
   GitHub Actions + fastlane. Подпись настраивается ключом App Store Connect API.
3. Загрузить сборку в TestFlight и установить её на iPhone через приложение TestFlight.

Это единственный путь, где сборка не перестаёт работать через неделю. Для разовой проверки
тикета 16 дешевле шаг 3.

## 6. Ручной чек-лист на iPhone

- Приложение запускается, рабочий день идёт, состояние сохраняется после перезапуска.
- Напоминание приходит, когда приложение свёрнуто или экран заблокирован.
- Нажатие на напоминание открывает экран отдыха, в том числе при холодном запуске.
- При выключенном звуке в настройках уведомление приходит молча.
- При выключенных напоминаниях уведомлений нет.
- После паузы и после конца рабочего дня напоминаний нет.
- После возврата в приложение фаза и отдых соответствуют реально прошедшему времени.
- Точки отдыха не теряются: ядро планирует 8 ближайших, системный лимит iOS — около 64.
- Экспорт и импорт открывают системные диалоги файлов, повреждённый файл отклоняется.
- Недопустимые значения в настройках отклоняются, прежнее значение сохраняется.

## 7. Особенности этого проекта

- Минимальная версия — iOS 15.0, bundle id — `com.cugap.workRestTimeBalancer`.
- Проект использует Swift Package Manager: `Podfile` нет, `pod install` не нужен. Все iOS-плагины
  (`flutter_local_notifications`, `file_picker_darwin`, `shared_preferences_foundation`)
  поставляются как Swift-пакеты.
- `ios/Runner/AppDelegate.swift` уже назначает `UNUserNotificationCenter` делегатом — без этого
  не работают нажатия и показ уведомления при открытом приложении.
- `Info.plist` править не нужно: локальные уведомления не требуют usage description, фоновые
  режимы приложению не нужны.
- `tray_manager` и `win32_registry` импортируются из `main.dart`, но их вызовы закрыты
  `Platform.isWindows`. Если iOS-сборка когда-нибудь упадёт на этих пакетах — выносить
  desktop-код за conditional import.

## 8. Частые ошибки

| Ошибка | Что делать |
| --- | --- |
| `No development team found` / `requires a development team` | Выбрать Team в Signing & Capabilities |
| `No signing certificate "iOS Development" found` | Xcode → Settings → Accounts → Manage Certificates → добавить iOS Development |
| Приложение не запускается после установки | iPhone: Settings → General → VPN & Device Management → доверять разработчику |
| `Provisioning profile ... doesn't include signing certificate` | Пересоздать профиль в Xcode, проверить, что устройство добавлено в Team |
| Сборка зелёная в CI, но не ставится на телефон | Это подпись: CI собирает без неё |
| `CocoaPods not installed` | `brew install cocoapods`, затем `pod install` в `ios/` (Flutter создаст `Podfile`, если появится плагин без SwiftPM) |
| Уведомление не появляется | Проверить разрешение в Settings → Notifications и что напоминания включены в настройках приложения |
| Уведомление без звука | Проверить переключатель «Без звука», режим фокусировки и настройку звука в приложении |
| Приложение перестало запускаться через неделю | Истёк бесплатный профиль: пересобрать из Xcode или перейти на TestFlight |
