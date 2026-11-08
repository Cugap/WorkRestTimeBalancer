/// Фаза рабочего дня.
enum WorkDayPhase {
  /// Рабочий день ещё не начат.
  notStarted,

  /// Рабочий день идёт и счёт рабочего времени тикает.
  running,

  /// Рабочий день на паузе: счёт рабочего времени заморожен.
  paused,

  /// Рабочий день завершён — вручную или по концу рабочего окна.
  finished,
}

/// Действия, доступные в текущей фазе.
enum WorkDayCommand { start, pause, resume, finish }

/// Почему команда отклонена. Состояние при отказе не меняется.
enum RejectionReason {
  workDayNotStarted,
  workDayAlreadyInProgress,
  workDayAlreadyPaused,
  workDayNotPaused,
  workDayAlreadyFinished,
  outsideWorkWindow,
}

/// Результат команды рабочего дня.
sealed class WorkDayCommandResult {
  const WorkDayCommandResult();
}

final class WorkDayCommandAccepted extends WorkDayCommandResult {
  const WorkDayCommandAccepted();
}

final class WorkDayCommandRejected extends WorkDayCommandResult {
  const WorkDayCommandRejected(this.reason);

  final RejectionReason reason;
}
