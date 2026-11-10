/// Разрешения, от которых зависят напоминания.
///
/// Ядро решает, когда напоминать, а платформа — можно ли это делать точно и
/// вообще. Экран настроек показывает состояние честно, чтобы неточные
/// напоминания не выглядели поломкой.
final class ReminderStatus {
  const ReminderStatus({
    required this.exactAlarms,
    required this.notificationsAllowed,
  });

  /// Разрешены точные будильники: напоминание приходит в назначенную минуту.
  final bool exactAlarms;

  /// Система разрешает показывать уведомления приложения.
  final bool notificationsAllowed;

  @override
  bool operator ==(Object other) =>
      other is ReminderStatus &&
      other.exactAlarms == exactAlarms &&
      other.notificationsAllowed == notificationsAllowed;

  @override
  int get hashCode => Object.hash(exactAlarms, notificationsAllowed);

  @override
  String toString() =>
      'ReminderStatus(exact: $exactAlarms, allowed: $notificationsAllowed)';
}

/// Источник состояния разрешений напоминаний. Экран настроек читает его и
/// просит систему выдать точные будильники; ядро об этом ничего не знает.
abstract interface class ReminderStatusSource {
  /// Текущее состояние разрешений.
  Future<ReminderStatus> read();

  /// Попросить разрешение на точные будильники, открыв системный экран.
  Future<ReminderStatus> requestExactAlarms();
}
