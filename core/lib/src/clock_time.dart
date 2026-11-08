/// Время суток без даты. Рабочее окно задаётся в локальном настенном времени.
final class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24, 'hour must be within 0..23'),
      assert(minute >= 0 && minute < 60, 'minute must be within 0..59');

  final int hour;
  final int minute;

  @override
  int compareTo(ClockTime other) =>
      (hour * 60 + minute) - (other.hour * 60 + other.minute);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
