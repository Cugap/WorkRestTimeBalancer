/// Источник времени для оболочки.
abstract interface class Clock {
  DateTime now();
}

/// Часы оболочки: настенное время на старте плюс монотонно прошедшее время,
/// но не позади настенных часов и никогда назад.
///
/// `Stopwatch` не идёт, пока устройство в глубоком сне, а на телефоне экран
/// блокируется надолго: одни лишь монотонные часы теряют время сна, и рабочий
/// день отстаёт от настенных часов. Поэтому берётся позднее из двух показаний:
/// настенные часы догоняют сон, а перевод часов назад ритм не откатывает —
/// монотонное показание продолжает идти, и отданное однажды время не
/// уменьшается.
final class MonotonicClock implements Clock {
  MonotonicClock({
    DateTime Function()? wallNow,
    Duration Function()? monotonicElapsed,
  }) : _wallNow = wallNow ?? DateTime.now,
       _anchor = (wallNow ?? DateTime.now)(),
       _elapsedSinceStart = monotonicElapsed ?? _runningStopwatch();

  /// Настенные часы: их показания догоняют глубокий сон.
  final DateTime Function() _wallNow;

  /// Сколько прошло по монотонным часам. В тестах подменяется, чтобы изобразить
  /// сон, в котором `Stopwatch` стоит.
  final Duration Function() _elapsedSinceStart;

  /// Момент старта часов: от него считается монотонное время.
  final DateTime _anchor;

  /// Последнее отданное время: перевод настенных часов назад сильнее, чем шло
  /// сна, не должен откатывать показание.
  DateTime? _last;

  @override
  DateTime now() {
    final monotonic = _anchor.add(_elapsedSinceStart());
    final wall = _wallNow();
    final candidate = wall.isAfter(monotonic) ? wall : monotonic;
    final last = _last;
    if (last != null && !candidate.isAfter(last)) {
      return last;
    }
    return _last = candidate;
  }

  static Duration Function() _runningStopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
