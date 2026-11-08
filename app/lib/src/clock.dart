/// Источник времени для оболочки.
abstract interface class Clock {
  DateTime now();
}

/// Часы оболочки: настенное время на старте плюс монотонно прошедшее время.
/// Поэтому перевод системных часов не сдвигает ритм рабочего дня.
final class MonotonicClock implements Clock {
  MonotonicClock([DateTime? startedAt]) : _anchor = startedAt ?? DateTime.now();

  final DateTime _anchor;
  final Stopwatch _elapsed = Stopwatch()..start();

  @override
  DateTime now() => _anchor.add(_elapsed.elapsed);
}
