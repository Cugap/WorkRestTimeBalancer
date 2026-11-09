import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';

import 'fake_clock.dart';

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;

  setUp(() {
    clock = FakeClock(DateTime(2026, 3, 4, 9));
    engine = WorkDayEngine();
  });

  Finder phase(WorkDayPhase value) =>
      find.byKey(ValueKey('phase-${value.name}'));
  Finder command(WorkDayCommand value) =>
      find.byKey(ValueKey('command-${value.name}'));

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(WorkRestApp(engine: engine, clock: clock));
  }

  Future<void> tapCommand(WidgetTester tester, WorkDayCommand value) async {
    await tester.tap(command(value));
    await tester.pump();
  }

  testWidgets('кнопки экрана соответствуют фазе ядра', (tester) async {
    await pumpApp(tester);

    expect(phase(WorkDayPhase.notStarted), findsOneWidget);
    expect(command(WorkDayCommand.start), findsOneWidget);
    expect(command(WorkDayCommand.pause), findsNothing);

    clock.advance(const Duration(minutes: 10));
    await tapCommand(tester, WorkDayCommand.start);

    expect(phase(WorkDayPhase.running), findsOneWidget);
    expect(command(WorkDayCommand.pause), findsOneWidget);
    expect(command(WorkDayCommand.finish), findsOneWidget);
    expect(command(WorkDayCommand.start), findsNothing);

    await tapCommand(tester, WorkDayCommand.pause);

    expect(phase(WorkDayPhase.paused), findsOneWidget);
    expect(command(WorkDayCommand.resume), findsOneWidget);
    expect(command(WorkDayCommand.finish), findsOneWidget);

    await tapCommand(tester, WorkDayCommand.resume);
    expect(phase(WorkDayPhase.running), findsOneWidget);

    await tapCommand(tester, WorkDayCommand.finish);
    expect(phase(WorkDayPhase.finished), findsOneWidget);
    expect(command(WorkDayCommand.start), findsOneWidget);
  });

  testWidgets('тик экрана завершает день на конце рабочего окна', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);

    clock.advance(const Duration(hours: 9));
    await tester.pump(const Duration(seconds: 1));

    expect(phase(WorkDayPhase.finished), findsOneWidget);
    expect(command(WorkDayCommand.start), findsNothing);
  });

  testWidgets('экран показывает отсчёт до отдыха и предложение начать его', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);

    expect(find.byKey(const ValueKey('next-rest-countdown')), findsOneWidget);
    expect(phase(WorkDayPhase.running), findsOneWidget);

    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));

    expect(phase(WorkDayPhase.restOffered), findsOneWidget);
    expect(command(WorkDayCommand.startRest), findsOneWidget);
    expect(command(WorkDayCommand.skipRest), findsOneWidget);

    await tapCommand(tester, WorkDayCommand.startRest);

    expect(phase(WorkDayPhase.resting), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-countdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-rest-countdown')), findsNothing);
    expect(command(WorkDayCommand.startRest), findsNothing);
  });

  testWidgets('тик экрана заканчивает отдых и начинает новый интервал', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);
    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));
    await tapCommand(tester, WorkDayCommand.startRest);

    clock.advance(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(phase(WorkDayPhase.running), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-countdown')), findsNothing);
    expect(find.byKey(const ValueKey('next-rest-countdown')), findsOneWidget);
    expect(command(WorkDayCommand.pause), findsOneWidget);
  });

  testWidgets('пропуск отдыха сразу возвращает отсчёт интервала', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);
    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));

    await tapCommand(tester, WorkDayCommand.skipRest);

    expect(phase(WorkDayPhase.running), findsOneWidget);
    expect(find.byKey(const ValueKey('next-rest-countdown')), findsOneWidget);
    expect(command(WorkDayCommand.skipRest), findsNothing);
  });

  testWidgets('ручной старт обеда доступен из главного экрана', (tester) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);

    expect(command(WorkDayCommand.startMeal), findsOneWidget);

    await tester.ensureVisible(command(WorkDayCommand.startMeal));
    await tester.tap(command(WorkDayCommand.startMeal));
    await tester.pump();

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.resting);
    expect(snapshot.restKind, RestKind.meal);
    expect(snapshot.exercises, hasLength(3));
    expect(phase(WorkDayPhase.resting), findsOneWidget);
    expect(find.byKey(const ValueKey('rest-kind')), findsOneWidget);
    expect(command(WorkDayCommand.startMeal), findsNothing);
    expect(find.byKey(const ValueKey('open-rest-screen')), findsOneWidget);
  });

  testWidgets('после состоявшегося обеда ручной старт больше не предлагается', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);
    await tester.ensureVisible(command(WorkDayCommand.startMeal));
    await tester.tap(command(WorkDayCommand.startMeal));
    await tester.pump();

    clock.advance(const Duration(minutes: 60));
    await tester.pump(const Duration(seconds: 1));

    final snapshot = engine.snapshot(clock.now());
    expect(snapshot.phase, WorkDayPhase.running);
    expect(snapshot.restKind, isNull);
    expect(command(WorkDayCommand.startMeal), findsNothing);
  });

  testWidgets('отложить отдых можно дважды, после этого кнопки нет', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, WorkDayCommand.start);

    clock.advance(const Duration(minutes: 25));
    await tester.pump(const Duration(seconds: 1));

    expect(phase(WorkDayPhase.restOffered), findsOneWidget);
    expect(command(WorkDayCommand.postponeRest), findsOneWidget);
    expect(find.byKey(const ValueKey('postponements-left')), findsOneWidget);

    await tapCommand(tester, WorkDayCommand.postponeRest);

    expect(phase(WorkDayPhase.running), findsOneWidget);
    expect(command(WorkDayCommand.postponeRest), findsNothing);
    expect(find.byKey(const ValueKey('next-rest-countdown')), findsOneWidget);

    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(phase(WorkDayPhase.restOffered), findsOneWidget);
    await tapCommand(tester, WorkDayCommand.postponeRest);

    clock.advance(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 1));

    expect(phase(WorkDayPhase.restOffered), findsOneWidget);
    expect(command(WorkDayCommand.postponeRest), findsNothing);
    expect(command(WorkDayCommand.startRest), findsOneWidget);
    expect(command(WorkDayCommand.skipRest), findsOneWidget);
  });
}
