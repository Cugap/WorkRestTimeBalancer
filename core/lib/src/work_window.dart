import 'clock_time.dart';

/// Интервал суток, внутри которого приложение отслеживает ритм.
final class WorkWindow {
  const WorkWindow._({required this.start, required this.end});

  factory WorkWindow({required ClockTime start, required ClockTime end}) {
    assert(start.compareTo(end) < 0, 'work window must end after it starts');
    return WorkWindow._(start: start, end: end);
  }

  /// Значение по умолчанию из спецификации: 09:00–18:00.
  static const WorkWindow standard = WorkWindow._(
    start: ClockTime(9, 0),
    end: ClockTime(18, 0),
  );

  final ClockTime start;
  final ClockTime end;

  DateTime startOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, start.hour, start.minute);

  DateTime endOn(DateTime day) =>
      DateTime(day.year, day.month, day.day, end.hour, end.minute);

  bool contains(DateTime moment) =>
      !moment.isBefore(startOn(moment)) && moment.isBefore(endOn(moment));

  @override
  bool operator ==(Object other) =>
      other is WorkWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'WorkWindow($start–$end)';
}
