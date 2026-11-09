/// Фаза рабочего дня.
enum WorkDayPhase {
  /// Рабочий день ещё не начат.
  notStarted,

  /// Рабочий день идёт и счёт рабочего времени тикает.
  running,

  /// Рабочий день на паузе: счёт рабочего времени заморожен.
  paused,

  /// Приложение предлагает отдых; время работы при этом продолжает идти.
  restOffered,

  /// Отдых идёт: время работы замерло, идёт таймер отдыха.
  resting,

  /// Рабочий день завершён — вручную или по концу рабочего окна.
  finished,
}

/// Действия, доступные в текущей фазе.
enum WorkDayCommand {
  start,
  pause,
  resume,
  finish,
  startRest,
  finishRest,
  skipRest,
  postponeRest,

  /// Начать обед вручную в любой момент идущего рабочего дня.
  startMeal,
}

/// Почему команда отклонена. Состояние при отказе не меняется.
enum RejectionReason {
  workDayNotStarted,
  workDayAlreadyInProgress,
  workDayAlreadyPaused,
  workDayNotPaused,
  workDayAlreadyFinished,
  outsideWorkWindow,

  /// Отдых сейчас не предложен, поэтому его нельзя начать или пропустить.
  restNotOffered,

  /// Отдых уже идёт, поэтому команда работы с ритмом недоступна.
  restInProgress,

  /// Отложений в этой цепочке предложений больше нет: отдых можно только
  /// начать или пропустить.
  postponeLimitReached,

  /// Отдых сейчас не идёт, поэтому его нельзя завершить досрочно.
  restNotInProgress,

  /// Обед в этом рабочем дне уже состоялся, поэтому повторно не начинается.
  mealAlreadyTaken,
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
