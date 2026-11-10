import 'dart:async';

import 'package:work_rest_core/work_rest_core.dart';

/// Загрузка и сохранение документа ядра: при запуске документ читается один раз
/// и из него восстанавливается движок, дальше каждое принятое изменение
/// состояния дописывается в хранилище.
final class WorkDaySession {
  WorkDaySession._(
    this._store,
    this.engine, {
    required this.persistenceBlocked,
  });

  /// Движок для тестов и превью: ничего не читает и не пишет.
  factory WorkDaySession.inMemory([WorkDayEngine? engine]) => WorkDaySession._(
    null,
    engine ?? WorkDayEngine(),
    persistenceBlocked: false,
  );

  final LocalDocumentStore? _store;
  final WorkDayEngine engine;

  /// Документ на устройстве есть, но не читается. Сохранять в этом случае
  /// нельзя: иначе нечитаемые данные пользователя были бы затёрты молча.
  /// Разбором такого документа займётся восстановление (тикет 10).
  final bool persistenceBlocked;

  /// Записи идут строго друг за другом: поздняя запись не обгоняет раннюю.
  Future<void> _writes = Future<void>.value();

  /// Восстановить сессию из хранилища. Повреждённый или чужий по версии
  /// документ не применяется и не перезаписывается.
  ///
  /// [reminders] — порт напоминаний: ядро перепланирует их при каждой смене
  /// состояния, в том числе сразу после восстановления.
  static Future<WorkDaySession> restore(
    LocalDocumentStore store, {
    RestReminderPort? reminders,
  }) async {
    final payload = await store.read();
    if (payload == null) {
      return WorkDaySession._(
        store,
        WorkDayEngine(reminders: reminders),
        persistenceBlocked: false,
      );
    }
    try {
      final document = PersistedDocument.fromJsonString(payload);
      return WorkDaySession._(
        store,
        WorkDayEngine.restore(document, reminders: reminders),
        persistenceBlocked: false,
      );
    } on DocumentFormatException {
      return WorkDaySession._(
        store,
        WorkDayEngine(reminders: reminders),
        persistenceBlocked: true,
      );
    }
  }

  /// Сохранить текущее состояние ядра: настройки, журнал и состояние дня.
  Future<void> save() {
    final store = _store;
    if (store == null || persistenceBlocked) {
      return Future<void>.value();
    }
    final document = engine.document().toJsonString();
    return _writes = _writes.then((_) => store.write(document)).catchError((
      Object _,
    ) {
      // Сбой записи не должен ломать следующие сохранения и работу экрана:
      // состояние остаётся в памяти, а следующее изменение запишет его снова.
    });
  }
}
