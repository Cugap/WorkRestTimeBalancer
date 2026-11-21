import 'dart:async';

import 'package:flutter/widgets.dart';

/// Секундный тикер экрана: идёт, только пока экран виден.
///
/// В фоне (заблокированный телефон, свёрнутое окно) приложение не должно само
/// создавать предложение отдыха: иначе оно снимает ещё не показанное
/// напоминание. В фоне работают только уведомления, а день догоняется при
/// возврате — на `resumed` тикер сначала обновляет снимок, потом запускается.
mixin ScreenTicker<T extends StatefulWidget> on State<T> {
  Timer? _ticker;
  late final AppLifecycleListener _lifecycle;

  /// Обновить экран по снимку ядра: раз в секунду и при возврате в приложение.
  void refresh();

  @override
  void initState() {
    super.initState();
    _start();
    _lifecycle = AppLifecycleListener(
      onShow: () {
        refresh();
        _start();
      },
      onResume: () {
        refresh();
        _start();
      },
      onHide: _stop,
      onPause: _stop,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
  }
}
