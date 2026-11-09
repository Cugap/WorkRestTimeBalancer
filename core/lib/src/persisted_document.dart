import 'dart:convert';

import 'clock_time.dart';
import 'exercise.dart';
import 'rest_kind.dart';
import 'rhythm_settings.dart';
import 'work_day_command.dart';
import 'work_day_event.dart';

/// Почему документ не принят. Отказ не меняет ни одного значения: вызывающий
/// обязан сохранить прежние данные как есть.
enum DocumentRejection {
  /// Версия формата не поддерживается этой сборкой.
  unsupportedVersion,

  /// Документ повреждён: не JSON, нет обязательного поля или значение
  /// неизвестно.
  malformed,
}

/// Отказ разобрать документ. Документ с таким отказом никогда не применяется
/// и не перезаписывается: данные пользователя не сбрасываются молча.
final class DocumentFormatException implements Exception {
  const DocumentFormatException(this.reason, this.message);

  final DocumentRejection reason;
  final String message;

  @override
  String toString() => 'DocumentFormatException(${reason.name}: $message)';
}

/// Состояние текущего рабочего дня: всё, что нужно движку, чтобы продолжить
/// день после перезапуска ровно с того места, где он остановился.
///
/// Журнал сюда не входит: он лежит рядом в [PersistedDocument] и переносится
/// отдельно от дня.
final class WorkDayState {
  WorkDayState({
    required this.lastObservedAt,
    required this.phase,
    this.startedAt,
    this.finishedAt,
    this.runningSince,
    this.pausedAt,
    this.workWindowEndsAt,
    this.nextShortRestAt,
    this.nextLongRestAt,
    this.nextMealAt,
    this.mealTaken = false,
    this.nextRestAt,
    this.offerKind,
    this.currentRestKind,
    this.restOffered = false,
    this.restEndsAt,
    this.restStartedAt,
    this.restPlannedDuration,
    this.workIntervalStartedAt,
    this.postponesUsed = 0,
    List<Exercise> restExercises = const <Exercise>[],
    this.nextExerciseIndex = 0,
    this.worked = Duration.zero,
  }) : restExercises = List.unmodifiable(restExercises);

  /// Последний момент, который движок уже видел. После восстановления он
  /// задаёт нижнюю границу времени: перевод системных часов назад не отматывает
  /// ритм.
  final DateTime? lastObservedAt;

  final WorkDayPhase phase;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? runningSince;
  final DateTime? pausedAt;
  final DateTime? workWindowEndsAt;
  final DateTime? nextShortRestAt;
  final DateTime? nextLongRestAt;
  final DateTime? nextMealAt;
  final bool mealTaken;
  final DateTime? nextRestAt;
  final RestKind? offerKind;
  final RestKind? currentRestKind;
  final bool restOffered;
  final DateTime? restEndsAt;
  final DateTime? restStartedAt;
  final Duration? restPlannedDuration;
  final DateTime? workIntervalStartedAt;
  final int postponesUsed;
  final List<Exercise> restExercises;
  final int nextExerciseIndex;

  /// Отработанное время на момент [lastObservedAt], без идущего интервала.
  final Duration worked;

  Map<String, Object?> toJson() => {
    'lastObservedAt': lastObservedAt?.toIso8601String(),
    'phase': phase.name,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'runningSince': runningSince?.toIso8601String(),
    'pausedAt': pausedAt?.toIso8601String(),
    'workWindowEndsAt': workWindowEndsAt?.toIso8601String(),
    'nextShortRestAt': nextShortRestAt?.toIso8601String(),
    'nextLongRestAt': nextLongRestAt?.toIso8601String(),
    'nextMealAt': nextMealAt?.toIso8601String(),
    'mealTaken': mealTaken,
    'nextRestAt': nextRestAt?.toIso8601String(),
    'offerKind': offerKind?.name,
    'currentRestKind': currentRestKind?.name,
    'restOffered': restOffered,
    'restEndsAt': restEndsAt?.toIso8601String(),
    'restStartedAt': restStartedAt?.toIso8601String(),
    'restPlannedDurationMs': restPlannedDuration?.inMilliseconds,
    'workIntervalStartedAt': workIntervalStartedAt?.toIso8601String(),
    'postponesUsed': postponesUsed,
    'restExercises': [
      for (final exercise in restExercises) _exerciseToJson(exercise),
    ],
    'nextExerciseIndex': nextExerciseIndex,
    'workedMs': worked.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkDayState &&
      other.lastObservedAt == lastObservedAt &&
      other.phase == phase &&
      other.startedAt == startedAt &&
      other.finishedAt == finishedAt &&
      other.runningSince == runningSince &&
      other.pausedAt == pausedAt &&
      other.workWindowEndsAt == workWindowEndsAt &&
      other.nextShortRestAt == nextShortRestAt &&
      other.nextLongRestAt == nextLongRestAt &&
      other.nextMealAt == nextMealAt &&
      other.mealTaken == mealTaken &&
      other.nextRestAt == nextRestAt &&
      other.offerKind == offerKind &&
      other.currentRestKind == currentRestKind &&
      other.restOffered == restOffered &&
      other.restEndsAt == restEndsAt &&
      other.restStartedAt == restStartedAt &&
      other.restPlannedDuration == restPlannedDuration &&
      other.workIntervalStartedAt == workIntervalStartedAt &&
      other.postponesUsed == postponesUsed &&
      _sameExercises(other.restExercises) &&
      other.nextExerciseIndex == nextExerciseIndex &&
      other.worked == worked;

  @override
  int get hashCode => Object.hash(
    lastObservedAt,
    phase,
    startedAt,
    finishedAt,
    runningSince,
    pausedAt,
    workWindowEndsAt,
    nextShortRestAt,
    nextLongRestAt,
    nextMealAt,
    mealTaken,
    nextRestAt,
    offerKind,
    currentRestKind,
    restOffered,
    restEndsAt,
    restStartedAt,
    restPlannedDuration,
    workIntervalStartedAt,
    Object.hash(postponesUsed, restExercises.length, nextExerciseIndex, worked),
  );

  bool _sameExercises(List<Exercise> other) {
    if (other.length != restExercises.length) {
      return false;
    }
    for (var index = 0; index < other.length; index++) {
      if (other[index] != restExercises[index]) {
        return false;
      }
    }
    return true;
  }

  factory WorkDayState.fromJson(Map<String, Object?> json) => WorkDayState(
    lastObservedAt: _momentOrNull(json, 'lastObservedAt'),
    phase: _enumByName(WorkDayPhase.values, json['phase'], 'phase'),
    startedAt: _momentOrNull(json, 'startedAt'),
    finishedAt: _momentOrNull(json, 'finishedAt'),
    runningSince: _momentOrNull(json, 'runningSince'),
    pausedAt: _momentOrNull(json, 'pausedAt'),
    workWindowEndsAt: _momentOrNull(json, 'workWindowEndsAt'),
    nextShortRestAt: _momentOrNull(json, 'nextShortRestAt'),
    nextLongRestAt: _momentOrNull(json, 'nextLongRestAt'),
    nextMealAt: _momentOrNull(json, 'nextMealAt'),
    mealTaken: _boolOrNull(json, 'mealTaken') ?? false,
    nextRestAt: _momentOrNull(json, 'nextRestAt'),
    offerKind: _restKindOrNull(json, 'offerKind'),
    currentRestKind: _restKindOrNull(json, 'currentRestKind'),
    restOffered: _boolOrNull(json, 'restOffered') ?? false,
    restEndsAt: _momentOrNull(json, 'restEndsAt'),
    restStartedAt: _momentOrNull(json, 'restStartedAt'),
    restPlannedDuration: _durationOrNull(json, 'restPlannedDurationMs'),
    workIntervalStartedAt: _momentOrNull(json, 'workIntervalStartedAt'),
    postponesUsed: _intOrNull(json, 'postponesUsed') ?? 0,
    restExercises: [
      for (final item in _listOrEmpty(json, 'restExercises'))
        _exerciseFromJson(_map(item, 'restExercises[]')),
    ],
    nextExerciseIndex: _intOrNull(json, 'nextExerciseIndex') ?? 0,
    worked: Duration(milliseconds: _intOrNull(json, 'workedMs') ?? 0),
  );
}

/// Версионированный документ приложения: настройки, журнал событий и состояние
/// текущего рабочего дня. Единственный источник правды и для локального
/// хранения, и для экспорта/импорта: настройки и журнал выбираются из него
/// отдельно от состояния дня, поэтому импорт не обязан знать про день.
final class PersistedDocument {
  PersistedDocument({
    required this.settings,
    required List<WorkDayEvent> journal,
    this.day,
  }) : journal = List.unmodifiable(journal);

  /// Версия формата. Несовпадение — отказ [DocumentRejection.unsupportedVersion],
  /// а не молчаливый сброс данных.
  static const int formatVersion = 1;

  final RhythmSettings settings;
  final List<WorkDayEvent> journal;

  /// Состояние текущего рабочего дня; null — дня нет (он ещё не начат).
  final WorkDayState? day;

  /// Тот же документ с другим состоянием дня: так импорт (тикет 09) меняет
  /// только настройки и журнал и не трогает идущий день.
  PersistedDocument withDay(WorkDayState? day) =>
      PersistedDocument(settings: settings, journal: journal, day: day);

  /// Тот же документ с другими настройками и журналом, но прежним днём.
  PersistedDocument withSettingsAndJournal(
    RhythmSettings settings,
    List<WorkDayEvent> journal,
  ) => PersistedDocument(settings: settings, journal: journal, day: day);

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'settings': _settingsToJson(settings),
    'journal': [for (final event in journal) _eventToJson(event)],
    if (day != null) 'day': day!.toJson(),
  };

  /// Разобрать документ. Любая ошибка — [DocumentFormatException]; документ
  /// при отказе не применяется.
  factory PersistedDocument.fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DocumentFormatException(
        DocumentRejection.malformed,
        'не удалось разобрать JSON: ${error.message}',
      );
    }
    return PersistedDocument.fromJson(_map(decoded, 'документ'));
  }

  factory PersistedDocument.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version is! int) {
      _malformed('поле «formatVersion» должно быть целым числом');
    }
    if (version != formatVersion) {
      throw DocumentFormatException(
        DocumentRejection.unsupportedVersion,
        'версия документа $version не поддерживается, ожидается $formatVersion',
      );
    }

    final settings = _settingsFromJson(_map(json['settings'], 'settings'));
    final violation = _documentViolation(settings);
    if (violation != null) {
      _malformed('настройки в документе непригодны: $violation');
    }

    final journal = [
      for (final item in _list(json['journal'], 'journal'))
        _eventFromJson(_map(item, 'journal[]')),
    ];
    final dayJson = json['day'];
    return PersistedDocument(
      settings: settings,
      journal: journal,
      day: dayJson == null ? null : WorkDayState.fromJson(_map(dayJson, 'day')),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is PersistedDocument &&
      other.settings == settings &&
      other.day == day &&
      _sameEvents(other.journal, journal);

  @override
  int get hashCode => Object.hash(settings, day, journal.length);

  @override
  String toString() =>
      'PersistedDocument(v$formatVersion, ${journal.length} событий, '
      '${day == null ? 'без дня' : 'день ${day!.phase.name}'})';

  static bool _sameEvents(List<WorkDayEvent> a, List<WorkDayEvent> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// Проверка настроек из документа на пригодность для движка: окно должно
/// существовать, а интервалы и длительности — быть положительными. Пользовательские
/// диапазоны проверяет движок в updateSettings; документ, записанный движком,
/// всегда им соответствует, и повторять их здесь нельзя — иначе документ нельзя
/// было бы прочитать обратно.
String? _documentViolation(RhythmSettings settings) {
  if (settings.workWindow == null) {
    return 'начало рабочего окна не раньше его конца';
  }
  final durations = <String, Duration>{
    'shortRestInterval': settings.shortRestInterval,
    'shortRestDuration': settings.shortRestDuration,
    'longRestInterval': settings.longRestInterval,
    'longRestDuration': settings.longRestDuration,
    'mealDuration': settings.mealDuration,
  };
  for (final entry in durations.entries) {
    if (entry.value <= Duration.zero) {
      return '${entry.key} должен быть положительным';
    }
  }
  return null;
}

Map<String, Object?> _settingsToJson(RhythmSettings settings) => {
  'workStart': settings.workStart.toString(),
  'workEnd': settings.workEnd.toString(),
  'shortRestIntervalMs': settings.shortRestInterval.inMilliseconds,
  'shortRestDurationMs': settings.shortRestDuration.inMilliseconds,
  'longRestIntervalMs': settings.longRestInterval.inMilliseconds,
  'longRestDurationMs': settings.longRestDuration.inMilliseconds,
  'mealStart': settings.mealStart.toString(),
  'mealDurationMs': settings.mealDuration.inMilliseconds,
  'notificationsEnabled': settings.notificationsEnabled,
  'soundEnabled': settings.soundEnabled,
};

RhythmSettings _settingsFromJson(Map<String, Object?> json) => RhythmSettings(
  workStart: _clockTime(json, 'workStart'),
  workEnd: _clockTime(json, 'workEnd'),
  shortRestInterval: _duration(json, 'shortRestIntervalMs'),
  shortRestDuration: _duration(json, 'shortRestDurationMs'),
  longRestInterval: _duration(json, 'longRestIntervalMs'),
  longRestDuration: _duration(json, 'longRestDurationMs'),
  mealStart: _clockTime(json, 'mealStart'),
  mealDuration: _duration(json, 'mealDurationMs'),
  notificationsEnabled: _bool(json, 'notificationsEnabled'),
  soundEnabled: _bool(json, 'soundEnabled'),
);

Map<String, Object?> _eventToJson(WorkDayEvent event) => {
  'type': event.type.name,
  'at': event.at.toIso8601String(),
  if (event.finishReason != null) 'finishReason': event.finishReason!.name,
  if (event.restKind != null) 'restKind': event.restKind!.name,
  if (event.restFinishReason != null)
    'restFinishReason': event.restFinishReason!.name,
  if (event.plannedDuration != null)
    'plannedDurationMs': event.plannedDuration!.inMilliseconds,
  if (event.actualDuration != null)
    'actualDurationMs': event.actualDuration!.inMilliseconds,
};

WorkDayEvent _eventFromJson(Map<String, Object?> json) {
  final at = _moment(json, 'at');
  final plannedDuration = _durationOrNull(json, 'plannedDurationMs');
  final type = _enumByName(WorkDayEventType.values, json['type'], 'type');
  return switch (type) {
    WorkDayEventType.workDayStarted => WorkDayEvent.started(at),
    WorkDayEventType.workDayPaused => WorkDayEvent.paused(at),
    WorkDayEventType.workDayResumed => WorkDayEvent.resumed(at),
    WorkDayEventType.workDayFinished => WorkDayEvent.finished(
      at,
      _enumByName(
        WorkDayFinishReason.values,
        json['finishReason'],
        'finishReason',
      ),
    ),
    WorkDayEventType.restOffered => WorkDayEvent.restOffered(
      at,
      _restKind(json, 'restKind'),
      plannedDuration: plannedDuration,
    ),
    WorkDayEventType.restStarted => WorkDayEvent.restStarted(
      at,
      _restKind(json, 'restKind'),
      plannedDuration: plannedDuration,
    ),
    WorkDayEventType.restSkipped => WorkDayEvent.restSkipped(
      at,
      _restKind(json, 'restKind'),
      plannedDuration: plannedDuration,
    ),
    WorkDayEventType.restPostponed => WorkDayEvent.restPostponed(
      at,
      _restKind(json, 'restKind'),
      plannedDuration: plannedDuration,
    ),
    WorkDayEventType.restFinished => WorkDayEvent.restFinished(
      at,
      _restKind(json, 'restKind'),
      restFinishReason: _enumByName(
        RestFinishReason.values,
        json['restFinishReason'],
        'restFinishReason',
      ),
      plannedDuration: plannedDuration,
      actualDuration: _durationOrNull(json, 'actualDurationMs'),
    ),
    WorkDayEventType.settingsChanged => WorkDayEvent.settingsChanged(at),
    WorkDayEventType.dataExported => WorkDayEvent.dataExported(at),
    WorkDayEventType.dataImported => WorkDayEvent.dataImported(at),
  };
}

Map<String, Object?> _exerciseToJson(Exercise exercise) => {
  'id': exercise.id,
  'name': exercise.name,
  'description': exercise.description,
  'durationMs': exercise.duration.inMilliseconds,
  'category': exercise.category.name,
};

Exercise _exerciseFromJson(Map<String, Object?> json) => Exercise(
  id: _string(json, 'id'),
  name: _string(json, 'name'),
  description: _string(json, 'description'),
  duration: _duration(json, 'durationMs'),
  category: _enumByName(ExerciseCategory.values, json['category'], 'category'),
);

Never _malformed(String detail) =>
    throw DocumentFormatException(DocumentRejection.malformed, detail);

Map<String, Object?> _map(Object? value, String field) {
  if (value is Map<String, Object?>) {
    return value;
  }
  _malformed('поле «$field» должно быть объектом');
}

List<Object?> _list(Object? value, String field) {
  if (value is List<Object?>) {
    return value;
  }
  _malformed('поле «$field» должно быть массивом');
}

List<Object?> _listOrEmpty(Map<String, Object?> json, String field) {
  final value = json[field];
  return value == null ? const <Object?>[] : _list(value, field);
}

String _string(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String) {
    return value;
  }
  _malformed('поле «$field» должно быть строкой');
}

int _int(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is int) {
    return value;
  }
  _malformed('поле «$field» должно быть целым числом');
}

int? _intOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  _malformed('поле «$field» должно быть целым числом');
}

bool _bool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is bool) {
    return value;
  }
  _malformed('поле «$field» должно быть да/нет');
}

bool? _boolOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  _malformed('поле «$field» должно быть да/нет');
}

DateTime _moment(Map<String, Object?> json, String field) {
  final moment = _momentOrNull(json, field);
  if (moment == null) {
    _malformed('поле «$field» обязательно');
  }
  return moment;
}

DateTime? _momentOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) {
    _malformed('поле «$field» должно быть моментом времени');
  }
  return parsed;
}

Duration _duration(Map<String, Object?> json, String field) =>
    Duration(milliseconds: _int(json, field));

Duration? _durationOrNull(Map<String, Object?> json, String field) {
  final value = _intOrNull(json, field);
  return value == null ? null : Duration(milliseconds: value);
}

ClockTime _clockTime(Map<String, Object?> json, String field) {
  final text = _string(json, field).trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (match == null) {
    _malformed('поле «$field» должно быть временем вида ЧЧ:ММ');
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    _malformed('поле «$field» выходит за пределы суток');
  }
  return ClockTime(hour, minute);
}

RestKind _restKind(Map<String, Object?> json, String field) {
  final kind = _restKindOrNull(json, field);
  if (kind == null) {
    _malformed('поле «$field» обязательно');
  }
  return kind;
}

RestKind? _restKindOrNull(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  return _enumByName(RestKind.values, value, field);
}

T _enumByName<T extends Enum>(List<T> values, Object? value, String field) {
  if (value is! String) {
    _malformed('поле «$field» должно быть строкой');
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  _malformed('неизвестное значение «$value» в поле «$field»');
}
