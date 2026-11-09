import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/src/persistence.dart';

import 'fake_document_store.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

void main() {
  test('сессия восстанавливает движок из сохранённого документа', () async {
    final store = FakeDocumentStore();
    final first = await WorkDaySession.restore(store);
    first.engine.startWorkDay(_at(9));
    await first.save();

    final second = await WorkDaySession.restore(store);

    expect(second.persistenceBlocked, isFalse);
    final snapshot = second.engine.snapshot(_at(9, 10));
    expect(snapshot.phase, WorkDayPhase.running);
    expect(snapshot.worked, const Duration(minutes: 10));
    expect(snapshot.settings, RhythmSettings.defaults);
  });

  test('настройки, изменённые в сессии, тоже переживают перезапуск', () async {
    final store = FakeDocumentStore();
    final first = await WorkDaySession.restore(store);
    first.engine.updateSettings(
      _at(9),
      RhythmSettings.defaults.copyWith(
        shortRestInterval: const Duration(minutes: 30),
      ),
    );
    await first.save();

    final second = await WorkDaySession.restore(store);

    expect(
      second.engine.snapshot(_at(9, 1)).settings.shortRestInterval,
      const Duration(minutes: 30),
    );
  });

  test('пустое хранилище даёт новый день без сохранений', () async {
    final store = FakeDocumentStore();
    final session = await WorkDaySession.restore(store);

    expect(session.persistenceBlocked, isFalse);
    expect(session.engine.snapshot(_at(9)).phase, WorkDayPhase.notStarted);
    await session.save();
    expect(store.writes, 1);
  });

  test('повреждённый документ не применяется и не затирается', () async {
    final store = FakeDocumentStore('{это не документ');
    final session = await WorkDaySession.restore(store);

    expect(session.persistenceBlocked, isTrue);
    expect(session.engine.snapshot(_at(9)).phase, WorkDayPhase.notStarted);

    session.engine.startWorkDay(_at(9));
    await session.save();

    expect(store.document, '{это не документ');
    expect(store.writes, 0);
  });

  test('документ чужой версии не применяется и не затирается', () async {
    final store = FakeDocumentStore(
      '{"formatVersion":99,"settings":{},"journal":[]}',
    );
    final session = await WorkDaySession.restore(store);

    expect(session.persistenceBlocked, isTrue);
    await session.save();
    expect(store.document, '{"formatVersion":99,"settings":{},"journal":[]}');
  });

  test('сохранение пишет состояние после каждого изменения', () async {
    final store = FakeDocumentStore();
    final session = await WorkDaySession.restore(store);

    session.engine.startWorkDay(_at(9));
    await session.save();
    session.engine.pause(_at(9, 10));
    await session.save();

    final saved = PersistedDocument.fromJsonString(store.document!);
    expect(saved.journal.map((event) => event.type), [
      WorkDayEventType.workDayStarted,
      WorkDayEventType.workDayPaused,
    ]);
    expect(saved.day?.phase, WorkDayPhase.paused);
  });
}
