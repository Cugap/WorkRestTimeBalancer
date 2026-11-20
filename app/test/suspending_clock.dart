import 'package:work_rest_time_balancer/src/clock.dart';

/// Часы с подставными настенными часами и стоящим `Stopwatch`: так выглядит
/// глубокий сон устройства, в котором монотонное время не идёт.
final class SuspendingClock implements Clock {
  SuspendingClock(this.wall) {
    _clock = MonotonicClock(
      wallNow: () => wall,
      monotonicElapsed: () => monotonic,
    );
  }

  /// Настенные часы устройства: их двигает тест.
  DateTime wall;

  /// Сколько прошло по монотонным часам: во сне не растёт.
  Duration monotonic = Duration.zero;

  late final MonotonicClock _clock;

  @override
  DateTime now() => _clock.now();

  /// Время шло обычным ходом, без сна.
  void advance(Duration delta) {
    wall = wall.add(delta);
    monotonic += delta;
  }

  /// Устройство проспало [delta]: настенные часы ушли, монотонные стоят.
  void sleep(Duration delta) => wall = wall.add(delta);

  /// Настенные часы устройства перевели на [delta] назад.
  void setWallBack(Duration delta) => wall = wall.subtract(delta);
}
