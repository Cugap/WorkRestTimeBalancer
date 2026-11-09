import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'src/clock.dart';
import 'src/file_picker_document_gateway.dart';
import 'src/persistence.dart';
import 'src/preferences_document_store.dart';
import 'src/work_day_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await WorkDaySession.restore(
    SharedPreferencesDocumentStore(),
  );
  runApp(WorkRestApp(session: session, clock: MonotonicClock()));
}

class WorkRestApp extends StatefulWidget {
  WorkRestApp({
    super.key,
    WorkDayEngine? engine,
    WorkDaySession? session,
    this.clock,
    this.fileGateway,
  }) : session = session ?? WorkDaySession.inMemory(engine);

  final WorkDaySession session;
  final Clock? clock;

  /// Файловый порт экспорта и импорта; тесты подменяют его фейком.
  final DocumentFileGateway? fileGateway;

  @override
  State<WorkRestApp> createState() => _WorkRestAppState();
}

class _WorkRestAppState extends State<WorkRestApp> {
  final Clock _fallbackClock = MonotonicClock();
  late final AppLifecycleListener _lifecycle;
  late final DocumentTransfer _transfer;

  Clock get _clock => widget.clock ?? _fallbackClock;

  @override
  void initState() {
    super.initState();
    _transfer = DocumentTransfer(
      engine: widget.session.engine,
      gateway: widget.fileGateway ?? const FilePickerDocumentGateway(),
    );
    // Уход в фон — последняя точка, где состояние ещё можно записать.
    _lifecycle = AppLifecycleListener(onPause: _save, onHide: _save);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _save() => unawaited(widget.session.save());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkRestTimeBalancer',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: WorkDayScreen(
        engine: widget.session.engine,
        clock: _clock,
        transfer: _transfer,
        onStateChanged: _save,
      ),
    );
  }
}
