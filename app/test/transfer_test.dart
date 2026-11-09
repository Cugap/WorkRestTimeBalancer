import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/persistence.dart';

import 'fake_clock.dart';
import 'fake_document_store.dart';
import 'fake_file_gateway.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

/// Документ «с другого устройства»: другие настройки и другая история.
PersistedDocument _foreignDocument() => PersistedDocument(
  settings: RhythmSettings.defaults.copyWith(
    shortRestInterval: const Duration(minutes: 30),
    notificationsEnabled: false,
  ),
  journal: [
    WorkDayEvent.started(_at(8)),
    WorkDayEvent.finished(_at(12), WorkDayFinishReason.manual),
  ],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  // Завершаем анимацию перехода и диалога, даём тику экрана обновить снимок.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  late FakeClock clock;
  late FakeDocumentStore store;
  late WorkDaySession session;
  late FakeFileGateway gateway;

  // Сессия создаётся внутри теста: цепочка записей живёт в той же зоне, что и
  // часы теста, иначе `pump` не дожидается сохранения.
  Future<void> pumpApp(WidgetTester tester, {String? picked}) async {
    clock = FakeClock(_at(9));
    store = FakeDocumentStore();
    session = await WorkDaySession.restore(store);
    gateway = FakeFileGateway(picked: picked);
    await tester.pumpWidget(
      WorkRestApp(session: session, clock: clock, fileGateway: gateway),
    );
  }

  Future<void> openSettings(WidgetTester tester) async {
    await _tap(tester, _key('open-settings-screen'));
  }

  testWidgets('экспорт сохраняет документ и отмечает его в журнале', (
    tester,
  ) async {
    await pumpApp(tester);
    await _tap(tester, _key('command-start'));
    await openSettings(tester);

    await _tap(tester, _key('settings-export'));

    expect(gateway.saved, hasLength(1));
    final exported = PersistedDocument.fromJsonString(gateway.saved.single);
    expect(exported.settings, RhythmSettings.defaults);
    expect(exported.journal, [WorkDayEvent.started(_at(9))]);
    expect(exported.day, isNull);

    expect(store.document, isNotNull);
    expect(
      PersistedDocument.fromJsonString(store.document!).journal,
      [WorkDayEvent.started(_at(9)), WorkDayEvent.dataExported(_at(9))],
    );
  });

  testWidgets('импорт после подтверждения заменяет настройки и журнал', (
    tester,
  ) async {
    final foreign = _foreignDocument();
    await pumpApp(tester, picked: foreign.toJsonString());
    await _tap(tester, _key('command-start'));
    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
    final offered = session.engine.snapshot(clock.now());
    expect(offered.phase, WorkDayPhase.restOffered);

    await openSettings(tester);
    await _tap(tester, _key('settings-import'));

    expect(_key('import-confirmation'), findsOneWidget);
    expect(gateway.picks, 1);

    await _tap(tester, _key('import-confirm'));

    final snapshot = session.engine.snapshot(clock.now());
    expect(snapshot.settings, foreign.settings);
    expect(snapshot.events, [
      ...foreign.journal,
      WorkDayEvent.dataImported(_at(9, 25)),
    ]);
    expect(snapshot.phase, WorkDayPhase.restOffered);
    expect(snapshot.restKind, offered.restKind);
    expect(snapshot.startedAt, offered.startedAt);

    expect(store.document, isNotNull);
    final stored = PersistedDocument.fromJsonString(store.document!);
    expect(stored.settings, foreign.settings);
    expect(stored.journal, snapshot.events);
    expect(stored.day, isNotNull);
  });

  testWidgets('отмена подтверждения не меняет данные', (tester) async {
    await pumpApp(tester, picked: _foreignDocument().toJsonString());
    await _tap(tester, _key('command-start'));
    await openSettings(tester);
    final before = session.engine.document();
    final storedBefore = store.document;

    await _tap(tester, _key('settings-import'));
    await _tap(tester, _key('import-cancel'));

    expect(session.engine.document(), before);
    expect(store.document, storedBefore);
  });

  testWidgets('повреждённый файл показывает причину и не меняет данные', (
    tester,
  ) async {
    await pumpApp(tester, picked: '{"formatVersion":1,"settings":');
    await _tap(tester, _key('command-start'));
    await openSettings(tester);
    final before = session.engine.document();
    final storedBefore = store.document;

    await _tap(tester, _key('settings-import'));

    expect(_key('settings-transfer-error'), findsOneWidget);
    expect(_key('import-confirmation'), findsNothing);
    expect(session.engine.document(), before);
    expect(store.document, storedBefore);
  });

  testWidgets('файл другой версии отклоняется без потери данных', (
    tester,
  ) async {
    await pumpApp(
      tester,
      picked: jsonEncode({
        'formatVersion': PersistedDocument.formatVersion + 1,
        'settings': <String, Object?>{},
        'journal': <Object?>[],
      }),
    );
    await _tap(tester, _key('command-start'));
    await openSettings(tester);
    final before = session.engine.document();
    final storedBefore = store.document;

    await _tap(tester, _key('settings-import'));

    expect(_key('settings-transfer-error'), findsOneWidget);
    expect(session.engine.document(), before);
    expect(store.document, storedBefore);
  });

  testWidgets('отмена выбора файла ничего не меняет', (tester) async {
    await pumpApp(tester);
    await _tap(tester, _key('command-start'));
    await openSettings(tester);
    final before = session.engine.document();

    await _tap(tester, _key('settings-import'));

    expect(gateway.picks, 1);
    expect(_key('import-confirmation'), findsNothing);
    expect(_key('settings-transfer-error'), findsNothing);
    expect(session.engine.document(), before);
  });
}
