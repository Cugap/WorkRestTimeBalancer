import 'package:work_rest_time_balancer/src/clock.dart';

/// Часы, которые двигаются только по команде теста.
class FakeClock implements Clock {
  FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration delta) => _now = _now.add(delta);
}
