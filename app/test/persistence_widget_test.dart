import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/persistence.dart';
import 'package:work_rest_time_balancer/src/settings_screen.dart';

import 'fake_clock.dart';
import 'fake_document_store.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

/// Проигрывает перезапуск: приложение строится заново из того же хранилища.
Future<WorkDaySession> _restart(FakeDocumentStore store) =>
    WorkDaySession.restore(store);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('команда экрана сохраняется и переживает перезапуск', (
    tester,
  ) async {
    final store = FakeDocumentStore();
    final session = await WorkDaySession.restore(store);
    final clock = FakeClock(_at(9));

    await tester.pumpWidget(WorkRestApp(session: session, clock: clock));
    await _tap(tester, find.byKey(const ValueKey('command-start')));

    expect(store.document, isNotNull);
    expect(
      PersistedDocument.fromJsonString(store.document!).journal,
      contains(WorkDayEvent.started(_at(9))),
    );

    final restarted = await _restart(store);
    await tester.pumpWidget(
      WorkRestApp(
        key: UniqueKey(),
        session: restarted,
        clock: FakeClock(_at(10)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('command-pause')), findsOneWidget);
    expect(restarted.engine.snapshot(_at(10)).worked, const Duration(hours: 1));
  });

  testWidgets('изменённые настройки переживают перезапуск', (tester) async {
    final store = FakeDocumentStore();
    final session = await WorkDaySession.restore(store);
    final clock = FakeClock(_at(9));

    await tester.pumpWidget(WorkRestApp(session: session, clock: clock));
    await _tap(tester, find.byKey(const ValueKey('open-settings-screen')));
    await tester.enterText(
      find.byKey(const ValueKey('settings-short-rest-interval')),
      '30',
    );
    await tester.pump();
    await _tap(tester, find.byKey(const ValueKey('settings-save')));

    expect(find.byType(SettingsScreen), findsNothing);
    expect(store.document, isNotNull);

    final restarted = await _restart(store);
    expect(
      restarted.engine.snapshot(_at(9)).settings.shortRestInterval,
      const Duration(minutes: 30),
    );
  });

  testWidgets('отдых, начатый до перезапуска, продолжается после него', (
    tester,
  ) async {
    final store = FakeDocumentStore();
    final clock = FakeClock(_at(9));
    final session = await WorkDaySession.restore(store);

    await tester.pumpWidget(WorkRestApp(session: session, clock: clock));
    await _tap(tester, find.byKey(const ValueKey('command-start')));

    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, find.byKey(const ValueKey('command-startRest')));
    expect(store.document, isNotNull);

    final restarted = await _restart(store);
    await tester.pumpWidget(
      WorkRestApp(
        key: UniqueKey(),
        session: restarted,
        clock: FakeClock(_at(9, 26)),
      ),
    );
    await tester.pump();

    final snapshot = restarted.engine.snapshot(_at(9, 26));
    expect(snapshot.phase, WorkDayPhase.resting);
    expect(snapshot.remainingRest, const Duration(minutes: 2));
  });
}
