import 'dart:convert';

import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Порт хранения в памяти: тесты не трогают ни файлы, ни настройки платформы.
final class FakeStore implements LocalDocumentStore {
  FakeStore([this.document]);

  String? document;
  int writes = 0;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async {
    writes++;
    this.document = document;
  }
}

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

/// Настройки без обеденного предложения: формат документа проверяется отдельно
/// от ритма.
const RhythmSettings _quietSettings = RhythmSettings(
  shortRestInterval: Duration(hours: 12),
  longRestInterval: Duration(hours: 12),
);

PersistedDocument _sampleDocument() {
  final engine = WorkDayEngine(settings: _quietSettings);
  engine.startWorkDay(_at(9));
  engine.snapshot(_at(9, 30));
  return engine.document();
}

void main() {
  group('документ хранилища', () {
    test('настройки и журнал переживают запись и чтение', () {
      final source = PersistedDocument(
        settings: RhythmSettings.defaults.copyWith(
          shortRestInterval: const Duration(minutes: 30),
          notificationsEnabled: false,
        ),
        journal: [
          WorkDayEvent.started(_at(9)),
          WorkDayEvent.paused(_at(10)),
          WorkDayEvent.resumed(_at(10, 5)),
          WorkDayEvent.restOffered(
            _at(10, 30),
            RestKind.long,
            plannedDuration: const Duration(minutes: 10),
          ),
          WorkDayEvent.restStarted(
            _at(10, 30),
            RestKind.long,
            plannedDuration: const Duration(minutes: 10),
          ),
          WorkDayEvent.restFinished(
            _at(10, 37),
            RestKind.long,
            restFinishReason: RestFinishReason.early,
            plannedDuration: const Duration(minutes: 10),
            actualDuration: const Duration(minutes: 7),
          ),
          WorkDayEvent.settingsChanged(_at(11)),
          WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
        ],
        day: null,
      );

      final restored = PersistedDocument.fromJsonString(source.toJsonString());

      expect(restored.settings, source.settings);
      expect(restored.journal, source.journal);
      expect(restored.day, isNull);
      expect(restored, source);
    });

    test('состояние дня переживает запись и чтение без потерь', () {
      final source = _sampleDocument();
      expect(source.day, isNotNull);

      final restored = PersistedDocument.fromJsonString(source.toJsonString());

      expect(restored.day, source.day);
      expect(restored.day!.lastObservedAt, _at(9, 30));
      expect(restored.day!.phase, WorkDayPhase.running);
      expect(restored.journal, source.journal);
    });

    test('документ содержит явную версию формата', () {
      final json = _sampleDocument().toJson();

      expect(json['formatVersion'], PersistedDocument.formatVersion);
      expect(PersistedDocument.formatVersion, 1);
    });

    test('настройки и журнал выбираются отдельно от состояния дня', () {
      final source = _sampleDocument();
      final withoutDay = source.withDay(null);

      expect(withoutDay.settings, source.settings);
      expect(withoutDay.journal, source.journal);
      expect(withoutDay.day, isNull);

      final withOtherJournal = source.withSettingsAndJournal(
        RhythmSettings.defaults,
        [WorkDayEvent.started(DateTime(2026, 3, 5, 9))],
      );
      expect(withOtherJournal.settings, RhythmSettings.defaults);
      expect(withOtherJournal.journal, hasLength(1));
      expect(withOtherJournal.day, source.day);
    });

    test('неизвестная версия отклоняется, данные не меняются', () {
      final json = _sampleDocument().toJson()..['formatVersion'] = 99;

      expect(
        () => PersistedDocument.fromJsonString(jsonEncode(json)),
        throwsA(
          isA<DocumentFormatException>().having(
            (error) => error.reason,
            'причина',
            DocumentRejection.unsupportedVersion,
          ),
        ),
      );
    });

    test('повреждённый JSON отклоняется', () {
      expect(
        () => PersistedDocument.fromJsonString('{не json'),
        throwsA(
          isA<DocumentFormatException>().having(
            (error) => error.reason,
            'причина',
            DocumentRejection.malformed,
          ),
        ),
      );
    });

    test('документ без обязательных полей отклоняется', () {
      for (final source in <String>[
        '{}',
        '[]',
        '{"formatVersion":1}',
        '{"formatVersion":1,"settings":{},"journal":[]}',
      ]) {
        expect(
          () => PersistedDocument.fromJsonString(source),
          throwsA(
            isA<DocumentFormatException>().having(
              (error) => error.reason,
              'причина',
              DocumentRejection.malformed,
            ),
          ),
          reason: source,
        );
      }
    });

    test('неизвестный тип события отклоняется', () {
      final json = _sampleDocument().toJson();
      (json['journal']! as List<Object?>)[0] = {
        'type': 'что-то новое',
        'at': _at(9).toIso8601String(),
      };

      expect(
        () => PersistedDocument.fromJsonString(jsonEncode(json)),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('неизвестная фаза дня отклоняется', () {
      final json = _sampleDocument().toJson();
      (json['day']! as Map<String, Object?>)['phase'] = 'телепорт';

      expect(
        () => PersistedDocument.fromJsonString(jsonEncode(json)),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('непригодные для движка настройки отклоняются', () {
      final json = _sampleDocument().toJson();
      (json['settings']! as Map<String, Object?>)['workStart'] = '18:00';
      (json['settings']! as Map<String, Object?>)['workEnd'] = '09:00';

      expect(
        () => PersistedDocument.fromJsonString(jsonEncode(json)),
        throwsA(
          isA<DocumentFormatException>().having(
            (error) => error.reason,
            'причина',
            DocumentRejection.malformed,
          ),
        ),
      );
    });
  });

  group('порт хранения', () {
    test('фейковый порт возвращает записанный документ', () async {
      final store = FakeStore();
      expect(await store.read(), isNull);

      final document = _sampleDocument().toJsonString();
      await store.write(document);

      expect(await store.read(), document);
      expect(store.writes, 1);
      expect(
        PersistedDocument.fromJsonString((await store.read())!).journal,
        _sampleDocument().journal,
      );
    });
  });

  group('журнал событий', () {
    test('в журнале есть все события рабочего дня, отдыха и обеда', () {
      final engine = WorkDayEngine(
        settings: RhythmSettings(
          shortRestInterval: const Duration(minutes: 25),
          longRestInterval: const Duration(minutes: 50),
        ),
      );
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.postponeRest(_at(9, 25));
      engine.startRest(_at(9, 30));
      engine.finishRest(_at(9, 32));
      engine.pause(_at(9, 40));
      engine.resume(_at(9, 45));
      engine.snapshot(_at(10, 15));
      engine.skipRest(_at(10, 15));
      engine.startMeal(_at(11));
      engine.finishRest(_at(11, 30));
      engine.updateSettings(
        _at(11, 35),
        RhythmSettings(
          shortRestInterval: const Duration(minutes: 30),
          longRestInterval: const Duration(minutes: 60),
        ),
      );
      engine.finishWorkDay(_at(12));
      engine.recordExport(_at(12, 5));
      // Импорт собственного документа заменяет настройки и журнал теми же
      // данными и дописывает событие импорта: так в журнале оказываются все
      // виды событий, включая перенос.
      engine.applyImportedDocument(_at(12, 10), engine.document());

      final events = engine.document().journal;
      final types = events.map((event) => event.type).toSet();
      expect(types, WorkDayEventType.values.toSet());

      for (final event in events) {
        expect(event.at, isNotNull);
      }
      for (final event in events.where(
        (event) =>
            event.type != WorkDayEventType.workDayStarted &&
            event.type != WorkDayEventType.workDayPaused &&
            event.type != WorkDayEventType.workDayResumed &&
            event.type != WorkDayEventType.workDayFinished &&
            event.type != WorkDayEventType.settingsChanged &&
            event.type != WorkDayEventType.dataExported &&
            event.type != WorkDayEventType.dataImported,
      )) {
        expect(event.restKind, isNotNull, reason: '${event.type}');
        expect(event.plannedDuration, isNotNull, reason: '${event.type}');
      }
      final finished = events
          .where((event) => event.type == WorkDayEventType.restFinished)
          .first;
      expect(finished.restFinishReason, RestFinishReason.early);
      expect(finished.actualDuration, const Duration(minutes: 2));
      final dayFinished = events.singleWhere(
        (event) => event.type == WorkDayEventType.workDayFinished,
      );
      expect(dayFinished.finishReason, WorkDayFinishReason.manual);
    });
  });
}
