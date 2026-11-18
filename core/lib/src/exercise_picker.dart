import 'exercise.dart';

/// Взять [count] упражнений из [catalog] по кругу, начиная с [startIndex].
///
/// Внутри одного отдыха упражнения не повторяются и берутся из разных
/// категорий: это делает длинный отдых и обед разминкой разных частей тела.
/// Курсор переходит за последним выбранным, поэтому следующий отдых не начнёт
/// с того же упражнения, а после конца набора круг начинается заново.
///
/// Если упражнений не хватает, набор может оказаться короче [count]: лучше
/// меньше упражнений, чем повтор внутри одного отдыха.
({List<Exercise> exercises, int nextIndex}) pickExercises({
  required List<Exercise> catalog,
  required int startIndex,
  required int count,
}) {
  if (catalog.isEmpty) {
    return (exercises: const <Exercise>[], nextIndex: startIndex);
  }
  var cursor = startIndex;
  final taken = <Exercise>[];
  for (var slot = 0; slot < count; slot++) {
    Exercise? chosen;
    for (var step = 0; step < catalog.length; step++) {
      final index = (cursor + step) % catalog.length;
      final candidate = catalog[index];
      if (taken.contains(candidate)) {
        continue;
      }
      if (taken.any((exercise) => exercise.category == candidate.category)) {
        continue;
      }
      chosen = candidate;
      cursor = (index + 1) % catalog.length;
      break;
    }
    if (chosen == null) {
      break;
    }
    taken.add(chosen);
  }
  return (exercises: List<Exercise>.unmodifiable(taken), nextIndex: cursor);
}
