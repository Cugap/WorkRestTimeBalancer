import 'dart:convert';

import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Файловый порт в памяти: тесты не открывают системных диалогов.
final class FakeGateway implements DocumentFileGateway {
  FakeGateway({this.picked, this.saveSucceeds = true});

  /// Что вернёт выбор файла; null — пользователь отменил выбор.
  String? picked;

  /// false — пользователь отменил сохранение.
  bool saveSucceeds;

  final List<({String contents, String name})> saved =
      <({String contents, String name})>[];
  int picks = 0;

  @override
  Future<bool> save(String contents, {required String suggestedName}) async {
    saved.add((contents: contents, name: suggestedName));
    return saveSucceeds;
  }

  @override
  Future<String?> pick() async {
    picks++;
    return picked;
  }
}

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

void main() {
  test('экспорт пишет настройки и журнал одним документом с версией', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    final gateway = FakeGateway();
    final transfer = DocumentTransfer(engine: engine, gateway: gateway);

    final outcome = await transfer.export(_at(9, 10));

    expect(outcome, isA<ExportSaved>());
    expect(gateway.saved, hasLength(1));
    expect(gateway.saved.single.name, endsWith('.json'));

    final json =
        jsonDecode(gateway.saved.single.contents) as Map<String, Object?>;
    expect(json['formatVersion'], PersistedDocument.formatVersion);
    expect(json.containsKey('day'), isFalse);

    final exported = PersistedDocument.fromJsonString(
      gateway.saved.single.contents,
    );
    expect(exported.settings, RhythmSettings.defaults);
    expect(exported.journal, [WorkDayEvent.started(_at(9))]);
  });

  test('отменённое сохранение не пишет событие экспорта', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    final gateway = FakeGateway(saveSucceeds: false);
    final transfer = DocumentTransfer(engine: engine, gateway: gateway);

    final outcome = await transfer.export(_at(9, 10));

    expect(outcome, isA<ExportCancelled>());
    expect(gateway.saved, hasLength(1));
    expect(engine.snapshot(_at(9, 10)).events, [WorkDayEvent.started(_at(9))]);
  });

  test('импорт заменяет настройки и журнал, фиксируя момент импорта', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    final imported = PersistedDocument(
      settings: RhythmSettings.defaults.copyWith(
        shortRestInterval: const Duration(minutes: 30),
      ),
      journal: [
        WorkDayEvent.started(_at(8)),
        WorkDayEvent.finished(_at(12), WorkDayFinishReason.manual),
      ],
    );
    final transfer = DocumentTransfer(
      engine: engine,
      gateway: FakeGateway(picked: imported.toJsonString()),
    );

    final selection = await transfer.selectImport();

    expect(selection, isA<ImportRead>());
    expect(engine.snapshot(_at(9, 10)).settings, RhythmSettings.defaults);

    transfer.applyImport(_at(9, 10), (selection as ImportRead).document);

    final snapshot = engine.snapshot(_at(9, 10));
    expect(snapshot.settings.shortRestInterval, const Duration(minutes: 30));
    expect(snapshot.events, [
      ...imported.journal,
      WorkDayEvent.dataImported(_at(9, 10)),
    ]);
  });

  test('импорт не меняет идущий рабочий день', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    engine.snapshot(_at(9, 10));
    final before = engine.snapshot(_at(9, 10));
    final imported = PersistedDocument(
      settings: RhythmSettings.defaults.copyWith(
        shortRestDuration: const Duration(minutes: 5),
      ),
      journal: [WorkDayEvent.started(_at(8))],
    );
    final transfer = DocumentTransfer(engine: engine, gateway: FakeGateway());

    transfer.applyImport(_at(9, 10), imported);

    final after = engine.snapshot(_at(9, 10));
    expect(after.phase, WorkDayPhase.running);
    expect(after.startedAt, before.startedAt);
    expect(after.worked, before.worked);
    expect(after.settings.shortRestDuration, const Duration(minutes: 5));
  });

  test('импорт не меняет показанное предложение и идущий отдых', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    engine.snapshot(_at(9, 25));
    final offered = engine.snapshot(_at(9, 25));
    expect(offered.phase, WorkDayPhase.restOffered);
    final imported = PersistedDocument(
      settings: RhythmSettings.defaults.copyWith(
        shortRestInterval: const Duration(minutes: 20),
        shortRestDuration: const Duration(minutes: 5),
      ),
      journal: [WorkDayEvent.started(_at(8))],
    );
    final transfer = DocumentTransfer(engine: engine, gateway: FakeGateway());

    transfer.applyImport(_at(9, 25), imported);

    final stillOffered = engine.snapshot(_at(9, 25));
    expect(stillOffered.phase, WorkDayPhase.restOffered);
    expect(stillOffered.restKind, offered.restKind);
    expect(stillOffered.remainingPostponements, offered.remainingPostponements);

    engine.startRest(_at(9, 25));
    final resting = engine.snapshot(_at(9, 26));
    expect(resting.phase, WorkDayPhase.resting);

    transfer.applyImport(_at(9, 26), imported);

    final stillResting = engine.snapshot(_at(9, 26));
    expect(stillResting.phase, WorkDayPhase.resting);
    expect(stillResting.restKind, resting.restKind);
    expect(stillResting.remainingRest, resting.remainingRest);
  });

  test('импорт не берёт состояние дня из файла', () async {
    final other = WorkDayEngine();
    other.startWorkDay(_at(9));
    other.snapshot(_at(9, 10));
    final imported = other.document();
    expect(imported.day, isNotNull);

    final engine = WorkDayEngine();
    final transfer = DocumentTransfer(engine: engine, gateway: FakeGateway());

    transfer.applyImport(_at(9), imported);

    expect(engine.snapshot(_at(9)).phase, WorkDayPhase.notStarted);
  });

  test('файл другой версии отклоняется и не меняет данные', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    engine.snapshot(_at(9, 10));
    final before = engine.document();
    final gateway = FakeGateway(
      picked: jsonEncode({
        'formatVersion': PersistedDocument.formatVersion + 1,
        'settings': <String, Object?>{},
        'journal': <Object?>[],
      }),
    );
    final transfer = DocumentTransfer(engine: engine, gateway: gateway);

    final outcome = await transfer.selectImport();

    expect(outcome, isA<ImportRejected>());
    final rejected = outcome as ImportRejected;
    expect(rejected.rejection, DocumentRejection.unsupportedVersion);
    expect(rejected.message, isNotEmpty);
    expect(engine.document(), before);
  });

  test('повреждённый файл отклоняется и не меняет данные', () async {
    for (final payload in [
      '{"formatVersion":1,"settings":',
      jsonEncode({
        'formatVersion': PersistedDocument.formatVersion,
        'settings': {'workStart': '09:00'},
        'journal': <Object?>[],
      }),
      jsonEncode({
        'formatVersion': PersistedDocument.formatVersion,
        'settings': <String, Object?>{},
        'journal': [
          {'type': 'unknownEvent', 'at': '2026-03-04T09:00:00.000'},
        ],
      }),
    ]) {
      final engine = WorkDayEngine();
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 10));
      final before = engine.document();
      final transfer = DocumentTransfer(
        engine: engine,
        gateway: FakeGateway(picked: payload),
      );

      final outcome = await transfer.selectImport();

      expect(outcome, isA<ImportRejected>(), reason: payload);
      expect(
        (outcome as ImportRejected).rejection,
        DocumentRejection.malformed,
        reason: payload,
      );
      expect(outcome.message, isNotEmpty);
      expect(engine.document(), before, reason: payload);
    }
  });

  test('отменённый выбор файла ничего не меняет', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    final before = engine.document();
    final gateway = FakeGateway();
    final transfer = DocumentTransfer(engine: engine, gateway: gateway);

    final outcome = await transfer.selectImport();

    expect(outcome, isA<ImportCancelled>());
    expect(gateway.picks, 1);
    expect(engine.document(), before);
  });

  test('события экспорта и импорта переживают запись и чтение', () {
    final source = PersistedDocument(
      settings: RhythmSettings.defaults,
      journal: [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.dataExported(_at(9, 30)),
        WorkDayEvent.dataImported(_at(10)),
      ],
    );

    final restored = PersistedDocument.fromJsonString(source.toJsonString());

    expect(restored.journal, source.journal);
  });
}
