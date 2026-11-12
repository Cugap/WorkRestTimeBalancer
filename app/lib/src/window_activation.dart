import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Класс главного окна Windows-раннера (`app/windows/runner/win32_window.cpp`).
/// Такой же класс у любого Flutter-приложения, поэтому окно ищется вместе с
/// идентификатором своего процесса.
const String _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// `SW_RESTORE`: развернуть свёрнутое окно, не меняя его размеров.
const int _swRestore = 9;

/// `SW_HIDE`: спрятать окно, оставив приложение работать.
const int _swHide = 0;

typedef _EnumWindowsNative = Int32 Function(
  Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>> callback,
  IntPtr extra,
);
typedef _EnumWindowsDart = int Function(
  Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>> callback,
  int extra,
);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
  IntPtr window,
  Pointer<Uint32> processId,
);
typedef _GetWindowThreadProcessIdDart = int Function(
  int window,
  Pointer<Uint32> processId,
);
typedef _GetClassNameNative = Int32 Function(
  IntPtr window,
  Pointer<Utf16> name,
  Int32 size,
);
typedef _GetClassNameDart = int Function(
  int window,
  Pointer<Utf16> name,
  int size,
);
typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();
typedef _ShowWindowNative = Int32 Function(IntPtr window, Int32 command);
typedef _ShowWindowDart = int Function(int window, int command);
typedef _SetForegroundWindowNative = Int32 Function(IntPtr window);
typedef _SetForegroundWindowDart = int Function(int window);

/// Показать окно приложения и поднять его на передний план.
///
/// Нажатие на toast приходит в уже запущенный процесс (COM-активатор плагина),
/// но Windows не восстанавливает свёрнутое окно сама, и экран отдыха открылся
/// бы невидимым. Ошибки платформы не должны срывать ритм, поэтому любые сбои
/// только логируются.
void activateAppWindow() {
  if (!Platform.isWindows) {
    return;
  }
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final window = _findOwnWindow(user32, kernel32);
    if (window == 0) {
      return;
    }
    user32
        .lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow')
        .call(window, _swRestore);
    user32
        .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
          'SetForegroundWindow',
        )
        .call(window);
  } catch (error) {
    debugPrint('rest reminders: cannot raise window: $error');
  }
}

/// Спрятать окно приложения в трей: процесс продолжает жить, ритм и
/// напоминания работают. Окно вернёт [activateAppWindow].
void hideAppWindow() {
  if (!Platform.isWindows) {
    return;
  }
  try {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final window = _findOwnWindow(user32, kernel32);
    if (window == 0) {
      return;
    }
    user32
        .lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow')
        .call(window, _swHide);
  } catch (error) {
    debugPrint('desktop: cannot hide window: $error');
  }
}

/// Окно раннера этого процесса: 0, если окна ещё нет.
int _findOwnWindow(DynamicLibrary user32, DynamicLibrary kernel32) {
  final ownProcess = kernel32
      .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
        'GetCurrentProcessId',
      )
      .call();
  final enumWindows = user32
      .lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');
  final processOf = user32
      .lookupFunction<
        _GetWindowThreadProcessIdNative,
        _GetWindowThreadProcessIdDart
      >('GetWindowThreadProcessId');
  final classNameOf = user32
      .lookupFunction<_GetClassNameNative, _GetClassNameDart>('GetClassNameW');

  final process = calloc<Uint32>();
  final className = calloc<Uint16>(_windowClass.length + 1).cast<Utf16>();
  var found = 0;
  final callback = NativeCallable<Int32 Function(IntPtr, IntPtr)>.isolateLocal((
    int window,
    int extra,
  ) {
    processOf(window, process);
    if (process.value != ownProcess) {
      return 1;
    }
    classNameOf(window, className, _windowClass.length + 1);
    if (className.toDartString() != _windowClass) {
      return 1;
    }
    found = window;
    return 0;
  }, exceptionalReturn: 0);
  try {
    enumWindows(callback.nativeFunction, 0);
  } finally {
    callback.close();
    calloc
      ..free(process)
      ..free(className);
  }
  return found;
}
