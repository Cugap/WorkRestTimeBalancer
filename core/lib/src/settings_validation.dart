import 'clock_time.dart';
import 'rhythm_settings.dart';
import 'work_day_command.dart';

/// Первое отклонение диапазонов в [settings] в порядке полей; null, если
/// настройки допустимы. Порядок фиксирован, чтобы отказ был воспроизводимым:
/// рабочее окно, короткий отдых, длинный отдых, обед.
///
/// Правила обеда: длительность положительная, а сам обед целиком помещается в
/// рабочее окно — начало не раньше начала окна, конец не позже конца окна.
RejectionReason? settingsViolation(RhythmSettings settings) {
  if (settings.workStart.compareTo(settings.workEnd) >= 0) {
    return RejectionReason.workWindowStartNotBeforeEnd;
  }
  if (!_within(
    settings.shortRestInterval,
    RhythmSettings.minShortRestInterval,
    RhythmSettings.maxShortRestInterval,
  )) {
    return RejectionReason.shortRestIntervalOutOfRange;
  }
  if (!_within(
    settings.shortRestDuration,
    RhythmSettings.minShortRestDuration,
    RhythmSettings.maxShortRestDuration,
  )) {
    return RejectionReason.shortRestDurationOutOfRange;
  }
  if (!_within(
    settings.longRestInterval,
    RhythmSettings.minLongRestInterval,
    RhythmSettings.maxLongRestInterval,
  )) {
    return RejectionReason.longRestIntervalOutOfRange;
  }
  if (!_within(
    settings.longRestDuration,
    RhythmSettings.minLongRestDuration,
    RhythmSettings.maxLongRestDuration,
  )) {
    return RejectionReason.longRestDurationOutOfRange;
  }
  if (settings.mealDuration <= Duration.zero) {
    return RejectionReason.mealDurationNotPositive;
  }
  if (!_mealFits(settings)) {
    return RejectionReason.mealNotInsideWorkWindow;
  }
  return null;
}

/// Объяснение отказа [settingsViolation] словами. Одно место, где правило
/// названо человеку: тем же текстом отвечают экран настроек и отказ импорта
/// файла, поэтому подсказки не расходятся с диапазонами.
String settingsViolationText(RejectionReason reason) => switch (reason) {
  RejectionReason.workWindowStartNotBeforeEnd =>
    'Начало рабочего окна должно быть раньше конца',
  RejectionReason.shortRestIntervalOutOfRange =>
    'Интервал короткого отдыха — от 20 до 30 минут',
  RejectionReason.shortRestDurationOutOfRange =>
    'Длительность короткого отдыха — от 20 секунд до 5 минут',
  RejectionReason.longRestIntervalOutOfRange =>
    'Интервал длинного отдыха — от 1 до 2 часов',
  RejectionReason.longRestDurationOutOfRange =>
    'Длительность длинного отдыха — от 5 до 15 минут',
  RejectionReason.mealDurationNotPositive =>
    'Длительность обеда должна быть больше нуля',
  RejectionReason.mealNotInsideWorkWindow =>
    'Обед должен целиком помещаться в рабочее окно',
  _ => throw ArgumentError.value(reason, 'reason', 'не отказ по настройкам'),
};

bool _within(Duration value, Duration min, Duration max) =>
    value >= min && value <= max;

/// Обед целиком лежит внутри рабочего окна одних суток.
bool _mealFits(RhythmSettings settings) {
  final windowStart = _secondsOfDay(settings.workStart);
  final windowEnd = _secondsOfDay(settings.workEnd);
  final mealStart = _secondsOfDay(settings.mealStart);
  final mealEnd = mealStart + settings.mealDuration.inSeconds;
  return mealStart >= windowStart && mealEnd <= windowEnd;
}

int _secondsOfDay(ClockTime time) =>
    (time.hour * Duration.secondsPerHour) +
    (time.minute * Duration.secondsPerMinute);
