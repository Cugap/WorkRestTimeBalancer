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

String commandLabel(WorkDayCommand command, WorkDayPhase phase) =>
    switch (command) {
      WorkDayCommand.start =>
        phase == WorkDayPhase.finished ? 'Начать новый рабочий день' : 'Начать',
      WorkDayCommand.pause => 'Пауза',
      WorkDayCommand.resume => 'Продолжить',
      WorkDayCommand.finish => 'Завершить',
      WorkDayCommand.startRest => 'Начать отдых',
      WorkDayCommand.skipRest => 'Пропустить',
      WorkDayCommand.postponeRest => 'Отложить на 5 минут',
    };

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
};
