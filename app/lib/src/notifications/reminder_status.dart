/// Разрешения, от которых зависят напоминания.
///
/// Ядро решает, когда напоминать, а платформа — можно ли это делать точно и
/// вообще. Экран настроек показывает состояние честно, чтобы неточные
/// напоминания не выглядели поломкой.
final class ReminderStatus {
  const ReminderStatus({
    required this.exactAlarms,
    required this.notificationsAllowed,
    this.exactAlarmsApplicable = true,
  });

  /// Разрешены точные будильники: напоминание приходит в назначенную минуту.
  final bool exactAlarms;

  /// Система разрешает показывать уведомления приложения.
  final bool notificationsAllowed;

  /// Платформа вообще умеет точные будильники. На iOS их нет: локальные
  /// уведомления доставляет система, поэтому экран настроек не рассказывает
  /// про точность и не предлагает разрешение, которого не существует.
  final bool exactAlarmsApplicable;

  @override
  bool operator ==(Object other) =>
      other is ReminderStatus &&
      other.exactAlarms == exactAlarms &&
      other.notificationsAllowed == notificationsAllowed &&
      other.exactAlarmsApplicable == exactAlarmsApplicable;

  @override
  int get hashCode =>
      Object.hash(exactAlarms, notificationsAllowed, exactAlarmsApplicable);

  @override
  String toString() =>
      'ReminderStatus(exact: $exactAlarms, '
      'allowed: $notificationsAllowed, '
      'exactApplicable: $exactAlarmsApplicable)';
}

/// Источник состояния разрешений напоминаний. Экран настроек читает его и
/// просит систему выдать точные будильники; ядро об этом ничего не знает.
abstract interface class ReminderStatusSource {
  /// Текущее состояние разрешений.
  Future<ReminderStatus> read();

  /// Попросить разрешение на точные будильники, открыв системный экран.
  Future<ReminderStatus> requestExactAlarms();
}
