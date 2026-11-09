import 'package:work_rest_core/work_rest_core.dart';

/// Форматирование для экрана: превращает готовые значения ядра в текст.
String formatHoursMinutes(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return '$minutes мин';
  }
  if (minutes == 0) {
    return '$hours ч';
  }
  return '$hours ч $minutes мин';
}

/// Обратный отсчёт: минуты и секунды, с часами для интервалов от часа.
String formatClock(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  final minutesAndSeconds =
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
  return hours == 0 ? minutesAndSeconds : '$hours:$minutesAndSeconds';
}

String phaseTitle(WorkDayPhase phase) => switch (phase) {
  WorkDayPhase.notStarted => 'Рабочий день не начат',
  WorkDayPhase.running => 'Рабочий день идёт',
  WorkDayPhase.paused => 'Рабочий день на паузе',
  WorkDayPhase.restOffered => 'Пора отдохнуть',
  WorkDayPhase.resting => 'Отдых идёт',
  WorkDayPhase.finished => 'Рабочий день завершён',
};

String commandLabel(
  WorkDayCommand command,
  WorkDayPhase phase, {
  RestKind? restKind,
}) => switch (command) {
  WorkDayCommand.start =>
    phase == WorkDayPhase.finished ? 'Начать новый рабочий день' : 'Начать',
  WorkDayCommand.pause => 'Пауза',
  WorkDayCommand.resume => 'Продолжить',
  WorkDayCommand.finish => 'Завершить',
  WorkDayCommand.startRest =>
    restKind == RestKind.meal ? 'Начать обед' : 'Начать отдых',
  WorkDayCommand.finishRest => 'Закончить сейчас',
  WorkDayCommand.skipRest => 'Пропустить',
  WorkDayCommand.postponeRest => 'Отложить на 5 минут',
  WorkDayCommand.startMeal => 'Начать обед',
};

String restKindLabel(RestKind kind) => switch (kind) {
  RestKind.short => 'Короткий отдых',
  RestKind.long => 'Длинный отдых',
  RestKind.meal => 'Обед',
};

String exerciseCategoryLabel(ExerciseCategory category) => switch (category) {
  ExerciseCategory.eyes => 'Глаза',
  ExerciseCategory.hands => 'Руки',
  ExerciseCategory.body => 'Тело',
};

/// Длительность упражнения: секунды или минуты с секундами.
String formatExerciseDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < Duration.secondsPerMinute) {
    return '$totalSeconds с';
  }
  final minutes = totalSeconds ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  return seconds == 0 ? '$minutes мин' : '$minutes мин $seconds с';
}

String rejectionText(RejectionReason reason) => switch (reason) {
  RejectionReason.workDayNotStarted => 'Рабочий день ещё не начат',
  RejectionReason.workDayAlreadyInProgress => 'Рабочий день уже идёт',
  RejectionReason.workDayAlreadyPaused => 'Рабочий день уже на паузе',
  RejectionReason.workDayNotPaused => 'Рабочий день не на паузе',
  RejectionReason.workDayAlreadyFinished => 'Рабочий день уже завершён',
  RejectionReason.outsideWorkWindow => 'Сейчас вне рабочего окна',
  RejectionReason.restNotOffered => 'Отдых сейчас не предложен',
  RejectionReason.restInProgress => 'Сначала дождитесь конца отдыха',
  RejectionReason.postponeLimitReached =>
    'Отдых уже отложен дважды: можно начать или пропустить',
  RejectionReason.restNotInProgress => 'Отдых сейчас не идёт',
  RejectionReason.mealAlreadyTaken => 'Обед на сегодня уже состоялся',
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
};
