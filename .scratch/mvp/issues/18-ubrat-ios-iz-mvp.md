# 18: Убрать iOS из кода, сборки и документации

**What to build:** iOS выведен из условий MVP (ADR-0006): целевые платформы — Android и Windows. Нужно убрать всё, что существовало только ради iOS, и не оставить в репозитории следов третьей платформы: платформенную папку, workflow сборки, документацию, Darwin-настройки уведомлений, ветки iOS в адаптере, флаг «платформа без точных будильников» в состоянии разрешений, iOS-тесты и упоминания в README. Правила ритма, поведение на Android и Windows не меняются.

**Blocked by:** None (can start immediately).

**Status:** done

- [x] `app/ios/` удалена; `app/analysis_options.yaml` больше не исключает `ios/**`.
- [x] `.github/workflows/ios-build.yml` и `docs/ios-build-and-test.md` удалены.
- [x] `RestNotificationPlatform.initialize` не принимает `DarwinInitializationSettings`; `RestNotifications` не держит `darwinSettings`; в `detailsFor` нет `DarwinNotificationDetails`; в `PluginRestNotificationPlatform` нет ветки `_ios`, чтения `checkPermissions` и `IOSFlutterLocalNotificationsPlugin`.
- [x] `ReminderStatus.exactAlarmsApplicable` удалён, экран настроек не проверяет его и по-прежнему честно показывает неточные напоминания и запрет уведомлений.
- [x] Тесты: iOS-специфичные проверки удалены, а покрытие «нажатие открывает экран отдыха», «холодный запуск», «нажатие без предложения», «выключенные напоминания не просят разрешений» сохранено (файл `app/test/ios_reminders_test.dart` стал `app/test/notification_open_test.dart`, iOS-комментарии убраны).
- [x] README, `pubspec.yaml` и тесты ядра больше не называют iOS целевой платформой; ограничение раскладки напоминаний описано как защитная граница, а не как лимит iOS.
- [x] Комментарий `reminderLimit` в `core/lib/src/work_day_engine.dart` больше не ссылается на iOS: лимит описан как защитная граница раскладки.
- [x] `dart analyze`, `dart test`, `flutter analyze`, `flutter test` проходят; сборки под Windows и Android собираются.

## Comments

- Заведено вместе с правкой спецификации: iOS выведен из MVP, тикет 11 закрыт как `wontfix`. Решение и последствия — в `docs/adr/0006-bez-ios-v-mvp.md`.
- Поведение на Android и Windows не должно измениться ни на шаг: это удаление платформенной ветки, а не переделка адаптера.
- Сделано: удалены `app/ios/` (вся папка), `.github/workflows/ios-build.yml`, `docs/ios-build-and-test.md`; из `app/analysis_options.yaml` убран exclude `ios/**`.
- Адаптер уведомлений: `RestNotificationPlatform.initialize` принимает только обработчик нажатия, `RestNotifications` больше не держит `darwinSettings`, в `detailsFor` остались Android и Windows, из `PluginRestNotificationPlatform` ушли ветка `_ios`, чтение `checkPermissions` и `iOS: darwin` в `InitializationSettings`.
- `ReminderStatus.exactAlarmsApplicable` удалён вместе с проверками в `settings_screen.dart`: состояние точности и запрет уведомлений показываются всегда, потому что на обеих целевых платформах они применимы.
- Тесты: `app/test/ios_reminders_test.dart` переименован в `app/test/notification_open_test.dart` (покрытие нажатия, холодного запуска, «нажатия без предложения» и «выключенные напоминания не просят разрешений» сохранено); из `rest_notifications_test.dart` убраны Darwin- и iOS-детали, проверка текста напоминания выделена в отдельный тест; в `settings_screen_test.dart` тест про iOS заменён тестом про запрет уведомлений в системе; в `core/test/reminders_test.dart` тест и комментарии про лимит iOS переписаны как защитная граница раскладки.
- README: платформы — Android и Windows, ссылка на ADR-0006, абзац про workflow iOS и `docs/ios-build-and-test.md` убран.
- Комментарий `reminderLimit` в `core/lib/src/work_day_engine.dart` переписан: лимит — защитная граница раскладки, а не ответ на системный лимит iOS.
- Проверено: `dart analyze` — чисто, `dart test` — 194 теста; `flutter analyze` — чисто, `flutter test` — 62 теста; `flutter build windows --debug` и `flutter build apk --debug` собираются.
