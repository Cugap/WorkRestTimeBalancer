import 'work_day_command.dart';
import 'work_day_event.dart';

/// Снимок рабочего дня: всё, что экран показывает, не вычисляя ничего сам.
final class WorkDaySnapshot {
  WorkDaySnapshot({
    required this.phase,
    required List<WorkDayCommand> availableCommands,
    required this.worked,
    required this.remainingInWorkWindow,
    required List<WorkDayEvent> events,
    this.startedAt,
    this.finishedAt,
    this.workWindowEndsAt,
  }) : availableCommands = List.unmodifiable(availableCommands),
       events = List.unmodifiable(events);

  final WorkDayPhase phase;

  /// Действия, которые ядро сейчас примет; экран не решает это сам.
  final List<WorkDayCommand> availableCommands;

  /// Отработанное время внутри рабочего дня без пауз.
  final Duration worked;

  /// Сколько осталось до конца рабочего окна; никогда не отрицательно.
  final Duration remainingInWorkWindow;

  /// Момент начала текущего рабочего дня.
  final DateTime? startedAt;

  /// Момент завершения рабочего дня.
  final DateTime? finishedAt;

  /// Конец рабочего окна текущего рабочего дня.
  final DateTime? workWindowEndsAt;

  /// Журнал событий рабочего дня.
  final List<WorkDayEvent> events;
}
