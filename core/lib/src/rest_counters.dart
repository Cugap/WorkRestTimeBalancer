import 'rest_kind.dart';
import 'rest_kind_profile.dart';
import 'rhythm_settings.dart';

/// Три счётчика ритма: когда наступит следующий короткий отдых, следующий
/// длинный и когда предлагается обед.
typedef RestCounters = ({DateTime? shortAt, DateTime? longAt, DateTime? mealAt});

/// Счётчики после отдыха вида [kind], закончившегося в [endedAt].
///
/// Обед и длинный отдых начинают ритм заново от своего конца: оба счётчика
/// переезжают на интервал от [endedAt]. Короткий отдых перезапускает только
/// свой счётчик, а счётчик длинного сдвигает на [shortRestDuration]: время
/// отдыха не считается работой, но и не отдаляет длинный отдых.
///
/// Тот же расчёт использует планировщик напоминаний, поэтому правила не
/// расходятся между настоящим ритмом и раскладкой вперёд.
RestCounters countersAfterRest({
  required RestCounters counters,
  required RestKind kind,
  required DateTime endedAt,
  required RhythmSettings settings,
  required Duration shortRestDuration,
}) {
  final shortAt = endedAt.add(settings.shortRestInterval);
  if (kind == RestKind.short) {
    return (
      shortAt: shortAt,
      longAt: counters.longAt?.add(shortRestDuration),
      mealAt: counters.mealAt,
    );
  }
  return (
    shortAt: shortAt,
    longAt: endedAt.add(settings.longRestInterval),
    mealAt: kind == RestKind.meal ? null : counters.mealAt,
  );
}

/// Счётчики после пропуска отдыха вида [kind] в момент [at].
///
/// Пропуск не создаёт долга: счётчик короткого отдыха начинается заново от
/// момента пропуска, а счётчик длинного не обнуляется — следующий длинный
/// наступает через интервал от плановой точки пропущенного, а если пропуск
/// случился позже этого срока, то от момента пропуска. Пропущенный обед
/// ничего не переносит: он предлагается только раз за рабочий день, но
/// вытесненную им длинную точку тоже отодвигает — иначе следующий снимок
/// предложил бы длинный отдых сразу после пропущенного обеда.
RestCounters countersAfterSkip({
  required RestCounters counters,
  required RestKind kind,
  required DateTime skippedAt,
  required RhythmSettings settings,
}) {
  final shortAt = skippedAt.add(settings.shortRestInterval);
  if (kind == RestKind.long) {
    final planned = counters.longAt ?? skippedAt;
    final nextLong = planned.add(settings.longRestInterval);
    return (
      shortAt: shortAt,
      longAt: nextLong.isAfter(skippedAt)
          ? nextLong
          : skippedAt.add(settings.longRestInterval),
      mealAt: counters.mealAt,
    );
  }
  // Обед с приоритетом мог вытеснить длинный отдых, точка которого уже
  // прошла: сдвигаем её так, чтобы пропуск не создавал долга.
  final longAt = counters.longAt;
  return (
    shortAt: shortAt,
    longAt: longAt != null && !longAt.isAfter(skippedAt)
        ? skippedAt.add(settings.longRestInterval)
        : longAt,
    mealAt: kind == RestKind.meal ? null : counters.mealAt,
  );
}

/// Ближайшая точка отдыха по счётчикам: минимальная по моменту, при совпадении
/// побеждает более важный вид (обед, длинный, короткий). Null — отдыхов больше
/// нет.
(DateTime, RestKind)? nearestRestPoint(RestCounters counters) {
  final candidates = <(DateTime, RestKind)>[
    if (counters.shortAt != null) (counters.shortAt!, RestKind.short),
    if (counters.longAt != null) (counters.longAt!, RestKind.long),
    if (counters.mealAt != null) (counters.mealAt!, RestKind.meal),
  ];
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort(compareRestPoints);
  return candidates.first;
}

/// Порядок точек отдыха: по моменту, при равенстве — по приоритету вида.
int compareRestPoints((DateTime, RestKind) a, (DateTime, RestKind) b) {
  final byMoment = a.$1.compareTo(b.$1);
  return byMoment != 0 ? byMoment : restPriority(a.$2) - restPriority(b.$2);
}
