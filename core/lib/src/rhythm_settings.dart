import 'clock_time.dart';
import 'work_window.dart';

/// Настройки ритма и рабочего окна. Модель принадлежит ядру: оболочка только
/// показывает значения из снимка и отправляет изменённые обратно в движок, не
/// зная ни диапазонов, ни правил ритма.
///
/// Конструктор значения не проверяет: через него проходят доверенные настройки
/// — значения по умолчанию и настройки, восстановленные из хранилища. Ввод
/// пользователя проходит через [WorkDayEngine.updateSettings], где диапазоны
/// проверяет [settingsViolation].
final class RhythmSettings {
  const RhythmSettings({
    this.workStart = const ClockTime(9, 0),
    this.workEnd = const ClockTime(18, 0),
    this.shortRestInterval = const Duration(minutes: 25),
    this.shortRestDuration = const Duration(minutes: 3),
    this.longRestInterval = const Duration(minutes: 90),
    this.longRestDuration = const Duration(minutes: 10),
    this.mealStart = const ClockTime(13, 0),
    this.mealDuration = const Duration(minutes: 60),
    this.notificationsEnabled = true,
    this.soundEnabled = true,
  });

  /// Значения по умолчанию из спецификации: 09:00–18:00, короткий отдых
  /// каждые 25 минут по 3 минуты, длинный каждые 90 минут по 10 минут, обед в
  /// 13:00 на 60 минут.
  static const RhythmSettings defaults = RhythmSettings();

  /// Минимальный интервал короткого отдыха.
  static const Duration minShortRestInterval = Duration(minutes: 20);

  /// Максимальный интервал короткого отдыха.
  static const Duration maxShortRestInterval = Duration(minutes: 30);

  /// Минимальная длительность короткого отдыха.
  static const Duration minShortRestDuration = Duration(seconds: 20);

  /// Максимальная длительность короткого отдыха.
  static const Duration maxShortRestDuration = Duration(minutes: 5);

  /// Минимальный интервал длинного отдыха.
  static const Duration minLongRestInterval = Duration(hours: 1);

  /// Максимальный интервал длинного отдыха.
  static const Duration maxLongRestInterval = Duration(hours: 2);

  /// Минимальная длительность длинного отдыха.
  static const Duration minLongRestDuration = Duration(minutes: 5);

  /// Максимальная длительность длинного отдыха.
  static const Duration maxLongRestDuration = Duration(minutes: 15);

  /// Начало рабочего окна в настенном времени.
  final ClockTime workStart;

  /// Конец рабочего окна в настенном времени; всегда позже начала в пределах
  /// одних суток.
  final ClockTime workEnd;

  /// Интервал работы между короткими отдыхами.
  final Duration shortRestInterval;

  /// Плановая длительность короткого отдыха.
  final Duration shortRestDuration;

  /// Интервал работы между длинными отдыхами.
  final Duration longRestInterval;

  /// Плановая длительность длинного отдыха.
  final Duration longRestDuration;

  /// Время суток, когда предлагается обед.
  final ClockTime mealStart;

  /// Плановая длительность обеда.
  final Duration mealDuration;

  /// Напоминания включены. Ядро хранит только флаг, реализация — в оболочке.
  final bool notificationsEnabled;

  /// Звук напоминаний включён. Ядро хранит только флаг.
  final bool soundEnabled;

  /// Рабочее окно для расчёта ритма; null, если начало не раньше конца.
  /// Движок хранит только допустимые настройки, поэтому у него окно всегда есть.
  WorkWindow? get workWindow => workStart.compareTo(workEnd) < 0
      ? WorkWindow(start: workStart, end: workEnd)
      : null;

  RhythmSettings copyWith({
    ClockTime? workStart,
    ClockTime? workEnd,
    Duration? shortRestInterval,
    Duration? shortRestDuration,
    Duration? longRestInterval,
    Duration? longRestDuration,
    ClockTime? mealStart,
    Duration? mealDuration,
    bool? notificationsEnabled,
    bool? soundEnabled,
  }) => RhythmSettings(
    workStart: workStart ?? this.workStart,
    workEnd: workEnd ?? this.workEnd,
    shortRestInterval: shortRestInterval ?? this.shortRestInterval,
    shortRestDuration: shortRestDuration ?? this.shortRestDuration,
    longRestInterval: longRestInterval ?? this.longRestInterval,
    longRestDuration: longRestDuration ?? this.longRestDuration,
    mealStart: mealStart ?? this.mealStart,
    mealDuration: mealDuration ?? this.mealDuration,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
  );

  @override
  bool operator ==(Object other) =>
      other is RhythmSettings &&
      other.workStart == workStart &&
      other.workEnd == workEnd &&
      other.shortRestInterval == shortRestInterval &&
      other.shortRestDuration == shortRestDuration &&
      other.longRestInterval == longRestInterval &&
      other.longRestDuration == longRestDuration &&
      other.mealStart == mealStart &&
      other.mealDuration == mealDuration &&
      other.notificationsEnabled == notificationsEnabled &&
      other.soundEnabled == soundEnabled;

  @override
  int get hashCode => Object.hash(
    workStart,
    workEnd,
    shortRestInterval,
    shortRestDuration,
    longRestInterval,
    longRestDuration,
    mealStart,
    mealDuration,
    notificationsEnabled,
    soundEnabled,
  );

  @override
  String toString() =>
      'RhythmSettings($workStart–$workEnd, '
      'short $shortRestInterval/$shortRestDuration, '
      'long $longRestInterval/$longRestDuration, '
      'meal $mealStart/$mealDuration, '
      'notifications $notificationsEnabled, sound $soundEnabled)';
}
