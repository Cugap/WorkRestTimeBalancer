/// Категория упражнения: глаза, руки или тело.
enum ExerciseCategory { eyes, hands, body }

/// Одно упражнение из локального набора: название, описание, длительность и
/// категория. Набор поставляется с приложением и доступен офлайн.
final class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.duration,
    required this.category,
  });

  /// Стабильный идентификатор: по нему экран отличает упражнения.
  final String id;
  final String name;
  final String description;
  final Duration duration;
  final ExerciseCategory category;

  @override
  bool operator ==(Object other) => other is Exercise && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Exercise($id)';
}
