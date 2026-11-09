import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

/// Настройки без длинных отдыхов и с коротким отдыхом каждые 25 минут:
/// прошедшие точки легко перечислить в ожиданиях.
const RhythmSettings _shortRhythm = RhythmSettings(
  shortRestInterval: Duration(minutes: 25),
  longRestInterval: Duration(hours: 12),
);

/// Настройки, в которых отдых не предлагается вовсе: проверяется только ход
/// рабочего дня.
const RhythmSettings _noRests = RhythmSettings(
  shortRestInterval: Duration(hours: 12),
  longRestInterval: Duration(hours: 12),
);

/// Тот же документ, что отдал бы перезапуск: запись и чтение через JSON.
PersistedDocument _roundTrip(PersistedDocument document) =>
    PersistedDocument.fromJsonString(document.toJsonString());

WorkDayEngine _restore(PersistedDocument document) =>
    WorkDayEngine.restore(_roundTrip(document));

void main() {
  group('восстановление рабочего дня', () {
    test('идущий день продолжается с остатком окна и накопленным временем', () {
      final engine = WorkDayEngine(settings: _noRests);
      engine.startWorkDay(_at(9));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(10));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, const Duration(hours: 1));
      expect(snapshot.remainingInWorkWindow, const Duration(hours: 8));
      expect(snapshot.startedAt, _at(9));
      expect(snapshot.workWindowEndsAt, _at(18));
      expect(snapshot.events, [WorkDayEvent.started(_at(9))]);
    });

    test('день на паузе остаётся на паузе и не считает время', () {
      final engine = WorkDayEngine(settings: _noRests);
      engine.startWorkDay(_at(9));
      engine.pause(_at(9, 40));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(11));

      expect(snapshot.phase, WorkDayPhase.paused);
      expect(snapshot.worked, const Duration(minutes: 40));
      expect(snapshot.availableCommands, [
        WorkDayCommand.resume,
        WorkDayCommand.finish,
      ]);
    });

    test('завершённый день восстанавливается завершённым без повторов', () {
      final engine = WorkDayEngine(settings: _noRests);
      engine.startWorkDay(_at(9));
      engine.finishWorkDay(_at(12));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(13));

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.finishedAt, _at(12));
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.workDayFinished,
        ),
        hasLength(1),
      );
    });

    test('настройки переживают перезапуск', () {
      final engine = WorkDayEngine(settings: _noRests);
      engine.updateSettings(
        _at(9),
        RhythmSettings.defaults.copyWith(
          workStart: const ClockTime(8, 0),
          workEnd: const ClockTime(17, 0),
          soundEnabled: false,
        ),
      );

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(9, 5));

      expect(snapshot.settings.workStart, const ClockTime(8, 0));
      expect(snapshot.settings.workEnd, const ClockTime(17, 0));
      expect(snapshot.settings.soundEnabled, isFalse);
      expect(snapshot.phase, WorkDayPhase.notStarted);
      expect(snapshot.events, [WorkDayEvent.settingsChanged(_at(9))]);
    });
  });

  group('восстановление отдыха', () {
    test('идущий отдых продолжается до запланированного конца', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      expect(engine.snapshot(_at(9, 25)).phase, WorkDayPhase.restOffered);
      engine.startRest(_at(9, 25));

      final restored = _restore(engine.document());
      final duringRest = restored.snapshot(_at(9, 26));

      expect(duringRest.phase, WorkDayPhase.resting);
      expect(duringRest.restKind, RestKind.short);
      expect(duringRest.remainingRest, const Duration(minutes: 2));
      expect(duringRest.exercises, hasLength(1));

      final afterRest = restored.snapshot(_at(9, 28));

      expect(afterRest.phase, WorkDayPhase.running);
      expect(afterRest.worked, const Duration(minutes: 25));
      expect(
        afterRest.events.last,
        WorkDayEvent.restFinished(
          _at(9, 28),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
          actualDuration: const Duration(minutes: 3),
        ),
      );
    });

    test('предложенный отдых остаётся предложенным после перезапуска', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(9, 26));

      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.restKind, RestKind.short);
      expect(snapshot.remainingPostponements, 2);
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );
    });

    test(
      'пропущенные точки отдыха пишутся пропусками, предлагается один отдых',
      () {
        final engine = WorkDayEngine(settings: _shortRhythm);
        engine.startWorkDay(_at(9));

        final restored = _restore(engine.document());
        final snapshot = restored.snapshot(_at(10));

        expect(snapshot.phase, WorkDayPhase.restOffered);
        expect(snapshot.restKind, RestKind.short);
        expect(snapshot.events, [
          WorkDayEvent.started(_at(9)),
          WorkDayEvent.restSkipped(
            _at(9, 25),
            RestKind.short,
            plannedDuration: const Duration(minutes: 3),
          ),
          WorkDayEvent.restSkipped(
            _at(9, 50),
            RestKind.short,
            plannedDuration: const Duration(minutes: 3),
          ),
          WorkDayEvent.restOffered(
            _at(10),
            RestKind.short,
            plannedDuration: const Duration(minutes: 3),
          ),
        ]);
        expect(snapshot.worked, const Duration(hours: 1));
      },
    );

    test('восстановление того же документа дважды не дублирует журнал', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      final saved = engine.document();

      final first = _restore(saved);
      final firstSnapshot = first.snapshot(_at(10));
      final second = _restore(saved);
      final secondSnapshot = second.snapshot(_at(10));

      expect(secondSnapshot.events, firstSnapshot.events);
      expect(secondSnapshot.phase, firstSnapshot.phase);

      final afterSave = _restore(first.document());
      expect(afterSave.snapshot(_at(10)).events, firstSnapshot.events);
      expect(
        afterSave.snapshot(_at(10, 30)).events,
        firstSnapshot.events,
        reason: 'очередь из пропущенных отдыхов не создаётся',
      );
    });

    test('отдых, доигранный при закрытом приложении, завершается сам', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(10));

      expect(snapshot.events, [
        WorkDayEvent.started(_at(9)),
        WorkDayEvent.restOffered(
          _at(9, 25),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.restStarted(
          _at(9, 25),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.restFinished(
          _at(9, 28),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
          actualDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.restSkipped(
          _at(9, 53),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.restOffered(
          _at(10),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
      ]);
      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.worked, const Duration(minutes: 57));
      expect(restored.startRest(_at(10, 1)), isA<WorkDayCommandAccepted>());
      expect(restored.snapshot(_at(10, 1)).phase, WorkDayPhase.resting);
    });

    test('пропуск обеда за время закрытия не предлагается повторно', () {
      final engine = WorkDayEngine(
        settings: _shortRhythm.copyWith(
          shortRestInterval: const Duration(hours: 5),
        ),
      );
      engine.startWorkDay(_at(9));

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(14));

      expect(
        snapshot.events,
        contains(
          WorkDayEvent.restSkipped(
            _at(13),
            RestKind.meal,
            plannedDuration: const Duration(minutes: 60),
          ),
        ),
      );
      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(snapshot.restKind, RestKind.short);
      expect(
        snapshot.events.where(
          (event) =>
              event.type == WorkDayEventType.restSkipped &&
              event.restKind == RestKind.meal,
        ),
        hasLength(1),
      );
    });
  });

  group('день, окончившийся при закрытом приложении', () {
    PersistedDocument savedLateDay() {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(17, 30));
      return engine.document();
    }

    test('восстанавливается завершённым в момент конца окна', () {
      final restored = _restore(savedLateDay());
      final snapshot = restored.snapshot(_at(19));

      expect(snapshot.phase, WorkDayPhase.finished);
      expect(snapshot.finishedAt, _at(18));
      expect(snapshot.worked, const Duration(minutes: 30));
      expect(snapshot.events, [
        WorkDayEvent.started(_at(17, 30)),
        WorkDayEvent.restSkipped(
          _at(17, 55),
          RestKind.short,
          plannedDuration: const Duration(minutes: 3),
        ),
        WorkDayEvent.finished(_at(18), WorkDayFinishReason.workWindowEnded),
      ]);
    });

    test('повторный перезапуск не добавляет второе завершение дня', () {
      final saved = savedLateDay();
      final first = _restore(saved);
      final firstSnapshot = first.snapshot(_at(19));

      final second = _restore(first.document());
      final secondSnapshot = second.snapshot(_at(20));

      expect(secondSnapshot.events, firstSnapshot.events);
      expect(
        secondSnapshot.events.where(
          (event) => event.type == WorkDayEventType.workDayFinished,
        ),
        hasLength(1),
      );
    });
  });

  group('перевод системных часов назад', () {
    test('не повторяет предложение отдыха и не отматывает работу', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      final offered = engine.snapshot(_at(9, 25));

      final backwards = engine.snapshot(_at(9, 5));

      expect(backwards.phase, WorkDayPhase.restOffered);
      expect(backwards.worked, offered.worked);
      expect(backwards.events, offered.events);
      expect(
        backwards.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );
    });

    test('после перезапуска часы назад не отматывают день', () {
      final engine = WorkDayEngine(settings: _noRests);
      engine.startWorkDay(_at(9));
      final saved = engine.snapshot(_at(10)).events;
      final document = engine.document();

      final restored = _restore(document);
      final snapshot = restored.snapshot(_at(8));

      expect(snapshot.phase, WorkDayPhase.running);
      expect(snapshot.worked, const Duration(hours: 1));
      expect(snapshot.events, saved);
    });

    test('часы назад после перезапуска не предлагают отдых повторно', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      final saved = engine.document();

      final restored = _restore(saved);
      final snapshot = restored.snapshot(_at(9, 10));

      expect(snapshot.phase, WorkDayPhase.restOffered);
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.restSkipped,
        ),
        isEmpty,
      );
    });

    test('восстановление с часами назад не создаёт пропусков', () {
      final engine = WorkDayEngine(settings: _shortRhythm);
      engine.startWorkDay(_at(9));
      engine.snapshot(_at(9, 50));
      final saved = engine.snapshot(_at(9, 50)).events;

      final restored = _restore(engine.document());
      final snapshot = restored.snapshot(_at(9, 10));

      expect(snapshot.events, saved);
      expect(snapshot.phase, WorkDayPhase.restOffered);
    });
  });
}
