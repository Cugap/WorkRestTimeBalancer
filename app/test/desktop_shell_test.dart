// Трей проверяется на том же классическом API, что и в оболочке: пункты меню
// нельзя собрать через новые nativeapi-билдеры, не поднимая трей.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/legacy.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/desktop/desktop_shell.dart';

import 'fake_clock.dart';

/// Автозапуск, который ничего не пишет в реестр.
final class FakeAutostart implements AutostartPort {
  bool enabled = false;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> setEnabled(bool value) async {
    enabled = value;
    return true;
  }
}

/// Оболочка Windows, которая запоминает запросы и умеет «отказать».
final class FakeDesktop implements DesktopPreferences {
  FakeDesktop({this.supported = true, this.accepts = true});

  final bool supported;
  bool accepts;

  bool? closeToTray;
  bool? launchAtStartup;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> setCloseToTray(bool enabled) async {
    if (!accepts) {
      return false;
    }
    closeToTray = enabled;
    return true;
  }

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async {
    if (!accepts) {
      return false;
    }
    launchAtStartup = enabled;
    return true;
  }
}

void main() {
  late FakeClock clock;
  late WorkDayEngine engine;

  setUp(() {
    clock = FakeClock(DateTime(2026, 3, 4, 9));
    engine = WorkDayEngine();
  });

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder field(String name) => key('settings-$name');

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      WorkRestApp(engine: engine, clock: clock, desktop: null),
    );
    await tester.tap(key('open-settings-screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpWith(WidgetTester tester, DesktopPreferences desktop) async {
    await tester.pumpWidget(
      WorkRestApp(
        engine: engine,
        clock: clock,
        desktop: desktop is DesktopShell ? desktop : null,
        desktopPreferences: desktop,
      ),
    );
    await tester.tap(key('open-settings-screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('без Windows-интеграций строк про трей нет', (tester) async {
    await openSettings(tester);

    expect(key('settings-minimize-to-tray'), findsNothing);
    expect(key('settings-launch-at-startup'), findsNothing);
  });

  testWidgets('переключатель трея применяется сразу и в ядре, и в оболочке', (
    tester,
  ) async {
    final desktop = FakeDesktop();
    await pumpWith(tester, desktop);

    expect(key('settings-minimize-to-tray'), findsOneWidget);
    // По умолчанию трей выключен: закрытие окна завершает приложение, пока
    // человек сам не включил эту настройку.
    expect(engine.snapshot(clock.now()).settings.minimizeToTray, isFalse);

    await tester.tap(key('settings-minimize-to-tray'));
    await tester.pump();

    expect(desktop.closeToTray, isTrue);
    expect(
      engine.snapshot(clock.now()).settings.minimizeToTray,
      isTrue,
      reason: 'настройка живёт в ядре, чтобы пережить перезапуск',
    );
  });

  testWidgets('переключатель автозапуска применяется сразу', (tester) async {
    final desktop = FakeDesktop();
    await pumpWith(tester, desktop);

    await tester.tap(key('settings-launch-at-startup'));
    await tester.pump();

    expect(desktop.launchAtStartup, isTrue);
    expect(engine.snapshot(clock.now()).settings.launchAtStartup, isTrue);
  });

  testWidgets('сохранение формы не сбрасывает трей и автозапуск', (
    tester,
  ) async {
    final desktop = FakeDesktop();
    await pumpWith(tester, desktop);

    await tester.tap(key('settings-launch-at-startup'));
    await tester.pump();
    await tester.enterText(field('short-rest-interval'), '30');
    await tester.pump();
    await tester.ensureVisible(key('settings-save'));
    await tester.tap(key('settings-save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final saved = engine.snapshot(clock.now()).settings;
    expect(saved.shortRestInterval, const Duration(minutes: 30));
    expect(
      saved.launchAtStartup,
      isTrue,
      reason: 'правка ритма не должна выключать автозапуск',
    );
    expect(saved.minimizeToTray, isFalse);
  });

  testWidgets('отказ системы виден и не меняет настройку', (tester) async {
    final desktop = FakeDesktop()..accepts = false;
    await pumpWith(tester, desktop);

    await tester.tap(key('settings-launch-at-startup'));
    await tester.pump();

    expect(key('settings-desktop-error'), findsOneWidget);
    expect(
      engine.snapshot(clock.now()).settings.launchAtStartup,
      isFalse,
      reason: 'настройка остаётся прежней, если система не дала применить',
    );
  });

  group('меню трея', () {
    late DesktopShell shell;

    setUp(() {
      shell = DesktopShell(
        engine: engine,
        clock: clock,
        autostart: FakeAutostart(),
      );
    });

    test('в меню есть «Выход», им приложение и закрывается', () {
      engine.startWorkDay(clock.now());
      clock.advance(const Duration(minutes: 5));

      final items = shell.menuItems();

      // Пункт выхода не должен теряться: при включённом трее это единственный
      // способ закрыть приложение.
      expect(items.map((item) => item.key), [
        DesktopShell.openItemKey,
        DesktopShell.finishItemKey,
        DesktopShell.exitItemKey,
      ]);
      expect(items.last.label, 'Выход');
      expect(items[1].label, isNot(contains('недоступно')));
    });

    test('пункт «Выход» отдаёт решение оболочке', () {
      var exits = 0;
      shell.onExitRequested = () => exits++;

      shell.onTrayMenuItemClick(MenuItem(key: DesktopShell.exitItemKey));

      // Само завершение процесса делает оболочка: она сохраняет день и снимает
      // напоминания, а трей только передаёт намерение.
      expect(exits, 1);
    });

    test('пункт «Завершить рабочий день» завершает день', () {
      engine.startWorkDay(clock.now());
      clock.advance(const Duration(hours: 1));

      shell.onTrayMenuItemClick(MenuItem(key: DesktopShell.finishItemKey));

      expect(engine.snapshot(clock.now()).phase, WorkDayPhase.finished);
    });
  });
}
