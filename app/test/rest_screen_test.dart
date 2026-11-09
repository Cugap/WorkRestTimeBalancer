import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/rest_screen.dart';

import 'fake_clock.dart';

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;

  setUp(() {
    clock = FakeClock(DateTime(2026, 3, 4, 9));
    engine = WorkDayEngine();
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder phase(WorkDayPhase value) =>
      find.byKey(ValueKey('phase-${value.name}'));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(WorkRestApp(engine: engine, clock: clock));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    // Завершаем анимацию перехода и даём тику экрана обновить снимок.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Начать день и дождаться предложения отдыха через 25 минут работы.
  Future<void> offerRest(WidgetTester tester) async {
    await tap(tester, key('command-start'));
    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openRestScreen(WidgetTester tester) =>
      tap(tester, key('open-rest-screen'));

  testWidgets('предложение отдыха открывается на полном экране', (
    tester,
  ) async {
    await pumpApp(tester);
    await offerRest(tester);

    expect(phase(WorkDayPhase.restOffered), findsOneWidget);
    expect(key('open-rest-screen'), findsOneWidget);

    await openRestScreen(tester);

    expect(find.byType(RestScreen), findsOneWidget);
    expect(key('rest-command-startRest'), findsOneWidget);
    expect(key('rest-command-skipRest'), findsOneWidget);
  });

  testWidgets('экран отдыха показывает таймер и ровно одно упражнение', (
    tester,
  ) async {
    await pumpApp(tester);
    await offerRest(tester);
    await openRestScreen(tester);

    await tap(tester, key('rest-command-startRest'));

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.resting);
    expect(snapshot.exercises, hasLength(1));

    final exercise = snapshot.exercises.single;
    expect(find.byType(RestScreen), findsOneWidget);
    expect(key('rest-screen-countdown'), findsOneWidget);
    expect(find.byKey(ValueKey('exercise-${exercise.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('exercise-name-1')), findsNothing);
    expect(key('rest-command-finishRest'), findsOneWidget);
  });

  testWidgets('«Закончить сейчас» досрочно завершает отдых и возвращает к работе', (
    tester,
  ) async {
    await pumpApp(tester);
    await offerRest(tester);
    await openRestScreen(tester);
    await tap(tester, key('rest-command-startRest'));

    clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, key('rest-command-finishRest'));

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.running);
    expect(snapshot.workIntervalStartedAt, clock.now());
    expect(snapshot.nextRestAt, clock.now().add(const Duration(minutes: 25)));
    expect(
      snapshot.lastRestFinished?.restFinishReason,
      RestFinishReason.early,
    );
    expect(find.byType(RestScreen), findsNothing);
    expect(phase(WorkDayPhase.running), findsOneWidget);
  });

  testWidgets('закрытие экрана не прерывает отдых, повторное открытие '
      'возвращает к нему', (tester) async {
    await pumpApp(tester);
    await offerRest(tester);
    await openRestScreen(tester);
    await tap(tester, key('rest-command-startRest'));

    final exercise = engine.snapshot(clock.now()).exercises.single;

    await tap(tester, key('rest-screen-close'));

    expect(find.byType(RestScreen), findsNothing);
    expect(engine.snapshot(clock.now()).phase, WorkDayPhase.resting);
    expect(phase(WorkDayPhase.resting), findsOneWidget);
    expect(key('open-rest-screen'), findsOneWidget);

    clock.advance(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(key('rest-screen-countdown'), findsNothing);

    await openRestScreen(tester);

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.resting);
    expect(snapshot.remainingRest, const Duration(minutes: 2));
    expect(key('rest-screen-countdown'), findsOneWidget);
    expect(find.byKey(ValueKey('exercise-${exercise.id}')), findsOneWidget);
  });
}
