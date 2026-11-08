import 'package:work_rest_core/work_rest_core.dart';

/// Форматирование для экрана: превращает готовые значения ядра в текст.
String formatSpan(Duration duration) {
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

String phaseTitle(WorkDayPhase phase) => switch (phase) {
  WorkDayPhase.notStarted => 'Рабочий день не начат',
  WorkDayPhase.running => 'Рабочий день идёт',
  WorkDayPhase.paused => 'Рабочий день на паузе',
  WorkDayPhase.finished => 'Рабочий день завершён',
};

String commandLabel(WorkDayCommand command, WorkDayPhase phase) =>
    switch (command) {
      WorkDayCommand.start =>
        phase == WorkDayPhase.finished ? 'Начать новый рабочий день' : 'Начать',
      WorkDayCommand.pause => 'Пауза',
      WorkDayCommand.resume => 'Продолжить',
      WorkDayCommand.finish => 'Завершить',
    };

String rejectionText(RejectionReason reason) => switch (reason) {
  RejectionReason.workDayNotStarted => 'Рабочий день ещё не начат',
  RejectionReason.workDayAlreadyInProgress => 'Рабочий день уже идёт',
  RejectionReason.workDayAlreadyPaused => 'Рабочий день уже на паузе',
  RejectionReason.workDayNotPaused => 'Рабочий день не на паузе',
  RejectionReason.workDayAlreadyFinished => 'Рабочий день уже завершён',
  RejectionReason.outsideWorkWindow => 'Сейчас вне рабочего окна',
};
