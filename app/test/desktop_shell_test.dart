import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/main.dart';
import 'package:work_rest_time_balancer/src/desktop/desktop_shell.dart';

import 'fake_clock.dart';

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

  Future<void> openSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      WorkRestApp(engine: engine, clock: clock, desktop: null),
    );
    await tester.tap(key('open-settings-screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpWith(
    WidgetTester tester,
    DesktopPreferences desktop,
  ) async {
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
    await tester.tap(key('settings-minimize-to-tray'));
    await tester.pump();

    expect(desktop.closeToTray, isFalse);
    expect(
      engine.snapshot(clock.now()).settings.minimizeToTray,
      isFalse,
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
}
