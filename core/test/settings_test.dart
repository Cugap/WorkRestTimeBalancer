import 'package:test/test.dart';
import 'package:work_rest_core/work_rest_core.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

RhythmSettings _changed({
  ClockTime workStart = const ClockTime(9, 0),
  ClockTime workEnd = const ClockTime(18, 0),
  Duration shortRestInterval = const Duration(minutes: 25),
  Duration shortRestDuration = const Duration(minutes: 3),
  Duration longRestInterval = const Duration(minutes: 90),
  Duration longRestDuration = const Duration(minutes: 10),
  ClockTime mealStart = const ClockTime(13, 0),
  Duration mealDuration = const Duration(minutes: 60),
  bool notificationsEnabled = true,
  bool soundEnabled = true,
  bool minimizeToTray = true,
  bool launchAtStartup = false,
}) => RhythmSettings(
  workStart: workStart,
  workEnd: workEnd,
  shortRestInterval: shortRestInterval,
  shortRestDuration: shortRestDuration,
  longRestInterval: longRestInterval,
  longRestDuration: longRestDuration,
  mealStart: mealStart,
  mealDuration: mealDuration,
  notificationsEnabled: notificationsEnabled,
  soundEnabled: soundEnabled,
  minimizeToTray: minimizeToTray,
  launchAtStartup: launchAtStartup,
);

void main() {
  group('значения по умолчанию', () {
    test('движок отдаёт значения из спецификации', () {
      final settings = WorkDayEngine().snapshot(_at(9)).settings;

      expect(settings, RhythmSettings.defaults);
      expect(settings.workStart, const ClockTime(9, 0));
      expect(settings.workEnd, const ClockTime(18, 0));
      expect(settings.shortRestInterval, const Duration(minutes: 25));
      expect(settings.shortRestDuration, const Duration(minutes: 3));
      expect(settings.longRestInterval, const Duration(minutes: 90));
      expect(settings.longRestDuration, const Duration(minutes: 10));
      expect(settings.mealStart, const ClockTime(13, 0));
      expect(settings.mealDuration, const Duration(minutes: 60));
      expect(settings.notificationsEnabled, isTrue);
      expect(settings.soundEnabled, isTrue);
    });

    test('по умолчанию окно сворачивается в трей, автозапуск выключен', () {
      const settings = RhythmSettings.defaults;

      expect(settings.minimizeToTray, isTrue);
      expect(settings.launchAtStartup, isFalse);
    });

    test('по умолчанию действует ритм 25/3, 90/10 и обед в 13:00', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));

      final offered = engine.snapshot(_at(9, 25));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.short);
      expect(offered.restDuration, const Duration(minutes: 3));
    });
  });

  group('проверка диапазонов', () {
    test('значения на границах диапазонов принимаются', () {
      final engine = WorkDayEngine();
      final candidates = [
        _changed(shortRestInterval: const Duration(minutes: 20)),
        _changed(shortRestInterval: const Duration(minutes: 30)),
        _changed(shortRestDuration: const Duration(seconds: 20)),
        _changed(shortRestDuration: const Duration(minutes: 5)),
        _changed(longRestInterval: const Duration(hours: 1)),
        _changed(longRestInterval: const Duration(hours: 2)),
        _changed(longRestDuration: const Duration(minutes: 5)),
        _changed(longRestDuration: const Duration(minutes: 15)),
        _changed(mealStart: const ClockTime(9, 0)),
        _changed(mealStart: const ClockTime(17, 0)),
      ];

      for (final candidate in candidates) {
        expect(
          engine.updateSettings(_at(8), candidate),
          isA<WorkDayCommandAccepted>(),
          reason: '$candidate',
        );
      }
    });

    test('недопустимые значения отклоняются с причиной', () {
      final engine = WorkDayEngine();
      final cases = <(RhythmSettings, RejectionReason)>[
        (
          _changed(
            workStart: const ClockTime(18, 0),
            workEnd: const ClockTime(9, 0),
          ),
          RejectionReason.workWindowStartNotBeforeEnd,
        ),
        (
          _changed(
            workStart: const ClockTime(10, 0),
            workEnd: const ClockTime(10, 0),
          ),
          RejectionReason.workWindowStartNotBeforeEnd,
        ),
        (
          _changed(shortRestInterval: const Duration(minutes: 19)),
          RejectionReason.shortRestIntervalOutOfRange,
        ),
        (
          _changed(shortRestInterval: const Duration(minutes: 31)),
          RejectionReason.shortRestIntervalOutOfRange,
        ),
        (
          _changed(shortRestDuration: const Duration(seconds: 19)),
          RejectionReason.shortRestDurationOutOfRange,
        ),
        (
          _changed(shortRestDuration: const Duration(minutes: 5, seconds: 1)),
          RejectionReason.shortRestDurationOutOfRange,
        ),
        (
          _changed(longRestInterval: const Duration(minutes: 59)),
          RejectionReason.longRestIntervalOutOfRange,
        ),
        (
          _changed(longRestInterval: const Duration(minutes: 121)),
          RejectionReason.longRestIntervalOutOfRange,
        ),
        (
          _changed(longRestDuration: const Duration(minutes: 4)),
          RejectionReason.longRestDurationOutOfRange,
        ),
        (
          _changed(longRestDuration: const Duration(minutes: 16)),
          RejectionReason.longRestDurationOutOfRange,
        ),
        (
          _changed(mealDuration: Duration.zero),
          RejectionReason.mealDurationNotPositive,
        ),
        (
          _changed(mealDuration: const Duration(minutes: -30)),
          RejectionReason.mealDurationNotPositive,
        ),
        (
          _changed(mealStart: const ClockTime(17, 30)),
          RejectionReason.mealNotInsideWorkWindow,
        ),
        (
          _changed(mealStart: const ClockTime(8, 30)),
          RejectionReason.mealNotInsideWorkWindow,
        ),
      ];

      for (final (candidate, reason) in cases) {
        final result = engine.updateSettings(_at(8), candidate);
        expect(
          (result as WorkDayCommandRejected).reason,
          reason,
          reason: '$candidate',
        );
      }
    });

    test('отклонённые настройки не меняют ни настройки, ни ритм', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      final before = engine.snapshot(_at(9, 5));

      final result = engine.updateSettings(
        _at(9, 5),
        _changed(shortRestInterval: const Duration(minutes: 10)),
      );

      expect(result, isA<WorkDayCommandRejected>());
      final after = engine.snapshot(_at(9, 5));
      expect(after.settings, RhythmSettings.defaults);
      expect(after.nextRestAt, before.nextRestAt);
      expect(after.nextRestAt, _at(9, 25));
      expect(
        after.events.where(
          (event) => event.type == WorkDayEventType.settingsChanged,
        ),
        isEmpty,
      );
    });
  });

  group('применение настроек', () {
    test('новый интервал короткого отдыха применяется к следующему отдыху', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(9, 10));

      final result = engine.updateSettings(
        _at(9, 10),
        _changed(shortRestInterval: const Duration(minutes: 20)),
      );

      expect(result, isA<WorkDayCommandAccepted>());
      final updated = engine.snapshot(_at(9, 10));
      expect(updated.settings.shortRestInterval, const Duration(minutes: 20));
      expect(updated.nextRestAt, _at(9, 20));
      expect(engine.snapshot(_at(9, 19)).phase, WorkDayPhase.running);
      final offered = engine.snapshot(_at(9, 20));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.short);
    });

    test(
      'новый интервал длинного отдыха применяется к следующему длинному',
      () {
        final engine = WorkDayEngine()..startWorkDay(_at(9));
        engine.updateSettings(
          _at(9, 10),
          _changed(longRestInterval: const Duration(hours: 1)),
        );

        engine.snapshot(_at(9, 25));
        engine.skipRest(_at(9, 25));
        engine.snapshot(_at(9, 50));
        engine.skipRest(_at(9, 50));

        final offered = engine.snapshot(_at(10));
        expect(offered.phase, WorkDayPhase.restOffered);
        expect(offered.restKind, RestKind.long);
      },
    );

    test('идущий отдых доигрывает до прежнего конца', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));
      engine.startRest(_at(9, 25));

      final result = engine.updateSettings(
        _at(9, 26),
        _changed(
          shortRestInterval: const Duration(minutes: 20),
          shortRestDuration: const Duration(minutes: 5),
        ),
      );

      expect(result, isA<WorkDayCommandAccepted>());
      final running = engine.snapshot(_at(9, 26));
      expect(running.phase, WorkDayPhase.resting);
      expect(running.restDuration, const Duration(minutes: 3));
      expect(running.remainingRest, const Duration(minutes: 2));

      final afterRest = engine.snapshot(_at(9, 28));
      expect(afterRest.phase, WorkDayPhase.running);
      expect(afterRest.nextRestAt, _at(9, 48));
    });

    test('предложенный отдых не отменяется изменением настроек', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.snapshot(_at(9, 25));

      engine.updateSettings(
        _at(9, 26),
        _changed(shortRestInterval: const Duration(minutes: 20)),
      );

      final offered = engine.snapshot(_at(9, 26));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.short);
      expect(offered.availableCommands, contains(WorkDayCommand.startRest));
      expect(
        offered.events.where(
          (event) => event.type == WorkDayEventType.restOffered,
        ),
        hasLength(1),
      );
      expect(engine.startRest(_at(9, 26)), isA<WorkDayCommandAccepted>());
    });

    test(
      'изменение рабочего окна пересчитывает конец дня и не завершает его',
      () {
        final engine = WorkDayEngine()..startWorkDay(_at(9));
        engine.snapshot(_at(9, 10));

        final result = engine.updateSettings(
          _at(9, 10),
          _changed(workEnd: const ClockTime(20, 0)),
        );

        expect(result, isA<WorkDayCommandAccepted>());
        final updated = engine.snapshot(_at(9, 10));
        expect(updated.phase, WorkDayPhase.running);
        expect(updated.workWindowEndsAt, _at(20));
        expect(
          updated.remainingInWorkWindow,
          const Duration(hours: 10, minutes: 50),
        );
        expect(
          updated.events.where(
            (event) => event.type == WorkDayEventType.workDayFinished,
          ),
          isEmpty,
        );

        expect(engine.snapshot(_at(20)).phase, WorkDayPhase.finished);
      },
    );

    test('новое время и длительность обеда применяются к текущему дню', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));

      engine.updateSettings(
        _at(9, 5),
        _changed(
          mealStart: const ClockTime(10, 30),
          mealDuration: const Duration(minutes: 45),
          longRestInterval: const Duration(hours: 2),
        ),
      );

      for (final moment in [_at(9, 25), _at(9, 50), _at(10, 15)]) {
        engine.snapshot(moment);
        engine.skipRest(moment);
      }

      final offered = engine.snapshot(_at(10, 30));
      expect(offered.phase, WorkDayPhase.restOffered);
      expect(offered.restKind, RestKind.meal);
      expect(offered.restDuration, const Duration(minutes: 45));
    });

    test('изменение настроек на паузе сохраняет остаток интервала', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.pause(_at(9, 10));

      engine.updateSettings(
        _at(9, 20),
        _changed(shortRestInterval: const Duration(minutes: 20)),
      );
      engine.resume(_at(9, 30));

      expect(engine.snapshot(_at(9, 30)).nextRestAt, _at(9, 40));
    });
  });

  group('сброс и журнал', () {
    test('изменение ритма сохраняет настройки трея и автозапуска', () {
      final engine = WorkDayEngine();
      engine.updateSettings(
        _at(8),
        _changed(minimizeToTray: false, launchAtStartup: true),
      );

      engine.updateSettings(
        _at(8, 1),
        engine.snapshot(_at(8, 1)).settings.copyWith(
          shortRestInterval: const Duration(minutes: 20),
        ),
      );

      final settings = engine.snapshot(_at(8, 1)).settings;
      expect(settings.minimizeToTray, isFalse);
      expect(settings.launchAtStartup, isTrue);
      expect(settings.shortRestInterval, const Duration(minutes: 20));
    });

    test('сброс возвращает значения по умолчанию и прежний ритм', () {
      final engine = WorkDayEngine()..startWorkDay(_at(9));
      engine.updateSettings(
        _at(9, 5),
        _changed(
          shortRestInterval: const Duration(minutes: 30),
          notificationsEnabled: false,
          soundEnabled: false,
        ),
      );
      expect(engine.snapshot(_at(9, 5)).nextRestAt, _at(9, 30));

      final result = engine.resetSettings(_at(9, 6));

      expect(result, isA<WorkDayCommandAccepted>());
      final snapshot = engine.snapshot(_at(9, 6));
      expect(snapshot.settings, RhythmSettings.defaults);
      expect(snapshot.settings.notificationsEnabled, isTrue);
      expect(snapshot.settings.soundEnabled, isTrue);
      expect(snapshot.nextRestAt, _at(9, 25));
      expect(
        snapshot.events.where(
          (event) => event.type == WorkDayEventType.settingsChanged,
        ),
        hasLength(2),
      );
    });

    test('изменение настроек пишется в журнал', () {
      final engine = WorkDayEngine();

      engine.updateSettings(
        _at(8),
        _changed(shortRestInterval: const Duration(minutes: 20)),
      );

      final events = engine.snapshot(_at(8)).events;
      expect(events.last, WorkDayEvent.settingsChanged(_at(8)));
      expect(events.last.type, WorkDayEventType.settingsChanged);
    });

    test('настройки можно поменять до начала рабочего дня', () {
      final engine = WorkDayEngine();

      expect(
        engine.updateSettings(
          _at(8),
          _changed(shortRestInterval: const Duration(minutes: 20)),
        ),
        isA<WorkDayCommandAccepted>(),
      );

      final beforeStart = engine.snapshot(_at(8));
      expect(beforeStart.phase, WorkDayPhase.notStarted);
      expect(
        beforeStart.settings.shortRestInterval,
        const Duration(minutes: 20),
      );
      expect(beforeStart.nextRestAt, isNull);

      engine.startWorkDay(_at(9));
      expect(engine.snapshot(_at(9, 20)).phase, WorkDayPhase.restOffered);
    });
  });
}
