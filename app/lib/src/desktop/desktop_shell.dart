// Трей и окно намеренно используют классический API пакетов: новые
// nativeapi-биндинги строят меню собственными билдерами, а приложению нужен
// трей с двумя пунктами и перехват закрытия окна. Мост помечен deprecated,
// поэтому предупреждения подавлены осознанно — это единственное место, где
// они возникают.
// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// Трей на классическом API пакета: приложению нужен значок с двумя пунктами
// меню, а новые nativeapi-биндинги строят меню собственными билдерами.
import 'package:tray_manager/legacy.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:work_rest_core/work_rest_core.dart';

import '../clock.dart';
import '../window_activation.dart';

/// Автозапуск вместе с системой. Ядро хранит только настройку, а запись в
/// систему делает этот порт: правила ритма и экраны о реестре не знают.
abstract interface class AutostartPort {
  Future<bool> isEnabled();
  Future<bool> setEnabled(bool enabled);
}

/// Автозапуск через ключ Run текущего пользователя: права администратора не
/// нужны, а запись действует только для этого пользователя (ADR-0005).
final class RegistryAutostart implements AutostartPort {
  RegistryAutostart({String? executable})
    : _executable = executable ?? Platform.resolvedExecutable;

  /// Ключ автозапуска текущего пользователя.
  static const String runKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';

  /// Имя значения в ключе автозапуска.
  static const String valueName = 'WorkRestTimeBalancer';

  final String _executable;

  @override
  Future<bool> isEnabled() async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      final key = CURRENT_USER.open(runKeyPath);
      try {
        return key.getString(valueName) != null;
      } finally {
        key.close();
      }
    } on Object catch (error) {
      debugPrint('autostart: cannot read: $error');
      return false;
    }
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return false;
    }
    try {
      final key = CURRENT_USER.create(runKeyPath);
      try {
        if (enabled) {
          // Кавычки нужны, если в пути есть пробелы.
          key.setValue(valueName, RegistryValue.string('"$_executable"'));
        } else if (key.getString(valueName) != null) {
          key.removeValue(valueName);
        }
      } finally {
        key.close();
      }
      // Честный ответ: проверяем, что запись действительно применилась.
      return await isEnabled() == enabled;
    } on Object catch (error) {
      debugPrint('autostart: cannot write: $error');
      return false;
    }
  }
}

/// Возможности оболочки Windows, нужные экрану настроек. Порт отделён, чтобы
/// экран проверялся без трея и реестра.
abstract interface class DesktopPreferences {
  /// Windows-интеграции доступны: есть и трей, и реестр.
  bool get isSupported;

  /// Закрытие окна сворачивает приложение в трей.
  Future<bool> setCloseToTray(bool enabled);

  /// Приложение запускается вместе с системой.
  Future<bool> setLaunchAtStartup(bool enabled);
}

/// Трей и поведение окна на Windows.
///
/// Ядро о трее не знает: ритм и напоминания идут как обычно, а трей только
/// прячет окно и даёт открыть приложение или завершить рабочий день. Ошибки
/// платформы логируются: интеграции не должны срывать работу приложения.
final class DesktopShell with TrayListener implements DesktopPreferences {
  DesktopShell({
    required this.engine,
    required this.clock,
    AutostartPort? autostart,
  }) : autostart = autostart ?? RegistryAutostart();

  /// Ключ пункта меню «Открыть».
  static const String openItemKey = 'open';

  /// Ключ пункта меню «Завершить рабочий день».
  static const String finishItemKey = 'finish';

  final WorkDayEngine engine;
  final Clock clock;
  final AutostartPort autostart;

  /// Канал раннера: поведение окна при закрытии задаёт он.
  static const MethodChannel _windowChannel = MethodChannel(
    'work_rest/desktop',
  );

  bool _closeToTray = true;
  bool _started = false;

  @override
  bool get isSupported => Platform.isWindows;

  /// Показать окно приложения: из трея или из уведомления.
  VoidCallback? onOpenRequested;

  bool get closeToTray => _closeToTray;

  /// Поднять трей и подписаться на закрытие окна. Вызывается один раз при
  /// запуске; повторный вызов ничего не делает.
  ///
  /// Шаги независимы: сбой трея не должен лишать приложение защиты окна, а
  /// сбой автозапуска — ломать трей. Поэтому каждый шаг ловит ошибку сам.
  Future<void> start() async {
    if (!isSupported || _started) {
      return;
    }
    _started = true;

    final settings = engine.snapshot(clock.now()).settings;
    _closeToTray = settings.minimizeToTray;
    // Раннер перехватывает закрытие окна сам: сообщаем ему решение.
    await _attempt(
      'close',
      () => _windowChannel.invokeMethod<void>(
        'setCloseToTray',
        _closeToTray,
      ),
    );

    // Автозапуск приводится к настройке при каждом старте: так реестр
    // восстанавливается, даже если запись потерялась.
    await _attempt(
      'autostart',
      () => autostart.setEnabled(settings.launchAtStartup),
    );

    await _attempt('tray', () async {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('WorkRestTimeBalancer');
      await _applyMenu();
      trayManager.addListener(this);
    });
  }

  /// Выполнить шаг интеграции, не давая его ошибке сорвать остальные.
  Future<void> _attempt(String step, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      debugPrint('desktop: $step unavailable: $error');
    }
  }

  /// Пункты меню зависят от фазы: завершать можно только идущий день.
  Future<void> _applyMenu() async {
    final snapshot = engine.snapshot(clock.now());
    final canFinish = snapshot.availableCommands.contains(
      WorkDayCommand.finish,
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: openItemKey, label: 'Открыть приложение'),
          MenuItem(
            key: finishItemKey,
            label: canFinish
                ? 'Завершить рабочий день'
                : 'Завершить рабочий день (недоступно)',
          ),
          MenuItem.separator(),
        ],
      ),
    );
  }

  /// Обновить трей после смены состояния: меню показывает, что можно сейчас.
  Future<void> refresh() async {
    if (!isSupported || !_started) {
      return;
    }
    try {
      await _applyMenu();
    } on Object catch (error) {
      debugPrint('desktop: cannot refresh menu: $error');
    }
  }

  Future<void> _showWindow() async {
    activateAppWindow();
    onOpenRequested?.call();
  }

  @override
  Future<bool> setCloseToTray(bool enabled) async {
    _closeToTray = enabled;
    if (!isSupported) {
      return false;
    }
    // Решение принимает раннер: он перехватывает закрытие окна.
    try {
      await _windowChannel.invokeMethod<void>('setCloseToTray', enabled);
      return true;
    } on MissingPluginException catch (error) {
      debugPrint('desktop: window channel unavailable: $error');
      return false;
    } on PlatformException catch (error) {
      debugPrint('desktop: window channel failed: $error');
      return false;
    }
  }

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async {
    if (!isSupported) {
      return false;
    }
    return autostart.setEnabled(enabled);
  }

  /// Пункт меню трея.
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case openItemKey:
        _showWindow();
      case finishItemKey:
        engine.finishWorkDay(clock.now());
        refresh();
    }
  }

  /// Клик по значку трея открывает окно: привычное поведение Windows.
  @override
  void onTrayIconMouseDown() => _showWindow();

  /// Закрытие окна системой: спрятать в трей или выйти по-настоящему.
  /// Оболочка спрашивает это у Flutter перед завершением приложения.
  bool get shouldHideOnClose => _closeToTray;

  /// Спрятать окно в трей, оставив приложение работать.
  void hideToTray() => hideAppWindow();

  /// Отпустить платформенные подписки.
  Future<void> dispose() async {
    if (!isSupported || !_started) {
      return;
    }
    trayManager.removeListener(this);
    await trayManager.destroy();
    _started = false;
  }
}
