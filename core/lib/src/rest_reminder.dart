import 'rest_kind.dart';
import 'rest_kind_profile.dart';
import 'rhythm_settings.dart';

/// Одна будущая точка отдыха, о которой приложение напомнит заранее.
///
/// Момент [at] — это момент, когда отдых будет предложен, а [duration] —
/// плановая длительность самого отдыха (её оболочка показывает в тексте
/// напоминания). [playSound] несёт настройку звука: при выключенном звуке
/// оболочка ставит напоминание молча.
final class RestReminder {
  const RestReminder({
    required this.at,
    required this.kind,
    required this.duration,
    this.playSound = true,
  });

  /// Напоминание о плановой точке отдыха: длительность и звук берутся из
  /// настроек так же, как их строит раскладка ядра.
  factory RestReminder.planned({
    required DateTime at,
    required RestKind kind,
    required RhythmSettings settings,
  }) => RestReminder(
    at: at,
    kind: kind,
    duration: restDuration(kind, settings),
    playSound: settings.soundEnabled,
  );

  /// Момент, когда отдых будет предложен.
  final DateTime at;

  /// Вид отдыха: короткий, длинный или обед.
  final RestKind kind;

  /// Плановая длительность отдыха.
  final Duration duration;

  /// Напоминать со звуком.
  final bool playSound;

  @override
  bool operator ==(Object other) =>
      other is RestReminder &&
      other.at == at &&
      other.kind == kind &&
      other.duration == duration &&
      other.playSound == playSound;

  @override
  int get hashCode => Object.hash(at, kind, duration, playSound);

  @override
  String toString() =>
      'RestReminder($kind at $at, $duration'
      '${playSound ? '' : ', silent'})';
}
