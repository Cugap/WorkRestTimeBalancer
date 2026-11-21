import 'rest_counters.dart';
import 'rest_kind_profile.dart';
import 'rest_reminder.dart';
import 'rhythm_settings.dart';

/// Раскладка напоминаний: ближайшие точки отдыха вперёд от счётчиков ритма.
///
/// Единственный вход: счётчики и настройки. Правила продвижения берутся из
/// [countersAfterRest] — те же, что у настоящего ритма, поэтому раскладка не
/// расходится с тем, что произойдёт на самом деле.
///
/// Пустой список означает «отменить всё».
List<RestReminder> planReminders({
  required RestCounters counters,
  required DateTime from,
  required DateTime workWindowEndsAt,
  required RhythmSettings settings,
  required int limit,
}) {
  var shortAt = counters.shortAt;
  var longAt = counters.longAt;
  var mealAt = counters.mealAt;
  final reminders = <RestReminder>[];
  while (reminders.length < limit) {
    final point = nearestRestPoint((
      shortAt: _withinWindow(shortAt, from, workWindowEndsAt),
      longAt: _withinWindow(longAt, from, workWindowEndsAt),
      mealAt: _withinWindow(mealAt, from, workWindowEndsAt),
    ));
    if (point == null) {
      break;
    }
    final (at, kind) = point;
    final duration = restDuration(kind, settings);
    reminders.add(
      RestReminder.planned(at: at, kind: kind, settings: settings),
    );
    final next = countersAfterRest(
      counters: (shortAt: shortAt, longAt: longAt, mealAt: mealAt),
      kind: kind,
      endedAt: at.add(duration),
      settings: settings,
      shortRestDuration: duration,
    );
    shortAt = next.shortAt;
    longAt = next.longAt;
    mealAt = next.mealAt;
  }
  return List<RestReminder>.unmodifiable(reminders);
}

/// Точка остаётся в раскладке, только если она впереди [from] и до конца
/// рабочего окна: отдых за концом окна не предлагается.
DateTime? _withinWindow(DateTime? at, DateTime from, DateTime endsAt) =>
    at != null && at.isAfter(from) && at.isBefore(endsAt) ? at : null;
