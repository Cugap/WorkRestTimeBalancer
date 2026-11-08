import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';

void main() {
  late DateTime now;
  late WorkDayEngine engine;

  setUp(() {
    now = DateTime(2026, 3, 4, 9);
    engine = WorkDayEngine();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(WorkRestApp(engine: engine, clock: () => now));
  }

  Future<void> tapCommand(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pump();
  }

  testWidgets(
    'экран показывает фазу и остаток окна, кнопки соответствуют фазе',
    (tester) async {
      await pumpApp(tester);

      expect(find.text('Рабочий день не начат'), findsOneWidget);
      expect(find.text('До конца рабочего окна: 9 ч'), findsOneWidget);
      expect(find.text('Отработано: 0 мин'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Начать'), findsOneWidget);
      expect(find.text('Пауза'), findsNothing);

      now = now.add(const Duration(minutes: 10));
      await tapCommand(tester, 'Начать');

      expect(find.text('Рабочий день идёт'), findsOneWidget);
      expect(find.text('Отработано: 0 мин'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Пауза'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Завершить'), findsOneWidget);
      expect(find.text('Начать'), findsNothing);

      now = now.add(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Отработано: 10 мин'), findsOneWidget);
      expect(find.text('До конца рабочего окна: 8 ч 40 мин'), findsOneWidget);
    },
  );

  testWidgets('пауза замораживает счёт, продолжение возвращает ритм', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, 'Начать');

    now = now.add(const Duration(minutes: 30));
    await tapCommand(tester, 'Пауза');

    expect(find.text('Рабочий день на паузе'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Продолжить'), findsOneWidget);

    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Отработано: 30 мин'), findsOneWidget);

    await tapCommand(tester, 'Продолжить');
    expect(find.text('Рабочий день идёт'), findsOneWidget);
  });

  testWidgets('после ручного завершения можно начать новый рабочий день', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, 'Начать');
    await tapCommand(tester, 'Завершить');

    expect(find.text('Рабочий день завершён'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Начать новый рабочий день'),
      findsOneWidget,
    );

    now = now.add(const Duration(minutes: 5));
    await tapCommand(tester, 'Начать новый рабочий день');

    expect(find.text('Рабочий день идёт'), findsOneWidget);
    expect(find.text('Отработано: 0 мин'), findsOneWidget);
  });

  testWidgets('в конце рабочего окна день завершается без команд', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapCommand(tester, 'Начать');

    now = DateTime(2026, 3, 4, 18, 30);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Рабочий день завершён'), findsOneWidget);
    expect(find.text('До конца рабочего окна: 0 мин'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Начать новый рабочий день'),
      findsNothing,
    );
  });
}
