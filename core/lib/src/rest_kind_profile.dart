import 'rest_kind.dart';
import 'rhythm_settings.dart';

/// Что вид отдыха значит для ритма и экрана.
///
/// Таблица ниже — единственное место, где вид отдыха превращается в числа:
/// остальной код спрашивает её, а не повторяет `switch` по [RestKind].
final class RestKindProfile {
  const RestKindProfile({
    required this.duration,
    required this.exerciseCount,
    required this.priority,
  });

  /// Плановая длительность отдыха по действующим настройкам.
  final Duration Function(RhythmSettings settings) duration;

  /// Сколько упражнений показывается на отдыхе.
  final int exerciseCount;

  /// Порядок при совпадении моментов: меньше — важнее. Обед вытесняет длинный
  /// отдых, длинный — короткий, поэтому отдыхи не идут очередью.
  final int priority;
}

final Map<RestKind, RestKindProfile> _profiles = {
  RestKind.short: RestKindProfile(
    duration: (settings) => settings.shortRestDuration,
    exerciseCount: 1,
    priority: 2,
  ),
  RestKind.long: RestKindProfile(
    duration: (settings) => settings.longRestDuration,
    exerciseCount: 2,
    priority: 1,
  ),
  RestKind.meal: RestKindProfile(
    duration: (settings) => settings.mealDuration,
    exerciseCount: 3,
    priority: 0,
  ),
};

/// Свойства [kind]: длительность, число упражнений и приоритет.
RestKindProfile restKindProfile(RestKind kind) => _profiles[kind]!;

/// Плановая длительность [kind] по настройкам [settings].
Duration restDuration(RestKind kind, RhythmSettings settings) =>
    restKindProfile(kind).duration(settings);

/// Сколько упражнений показывает [kind].
int restExerciseCount(RestKind kind) => restKindProfile(kind).exerciseCount;

/// Порядок выбора [kind] при совпадении моментов: обед, длинный, короткий.
int restPriority(RestKind kind) => restKindProfile(kind).priority;
