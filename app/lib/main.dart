import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'src/work_day_screen.dart';

void main() => runApp(WorkRestApp());

class WorkRestApp extends StatelessWidget {
  WorkRestApp({super.key, WorkDayEngine? engine, this.clock = DateTime.now})
    : engine = engine ?? WorkDayEngine();

  final WorkDayEngine engine;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorkRestTimeBalancer',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: WorkDayScreen(engine: engine, clock: clock),
    );
  }
}
