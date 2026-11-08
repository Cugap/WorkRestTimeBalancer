import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'labels.dart';

/// Главный экран: показывает снимок ядра и отправляет команды.
class WorkDayScreen extends StatefulWidget {
  const WorkDayScreen({
    super.key,
    required this.engine,
    this.clock = DateTime.now,
  });

  final WorkDayEngine engine;
  final DateTime Function() clock;

  @override
  State<WorkDayScreen> createState() => _WorkDayScreenState();
}

class _WorkDayScreenState extends State<WorkDayScreen> {
  late WorkDaySnapshot _snapshot;
  RejectionReason? _rejection;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.engine.snapshot(widget.clock());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    final snapshot = widget.engine.snapshot(widget.clock());
    setState(() => _snapshot = snapshot);
  }

  void _run(WorkDayCommand command) {
    final now = widget.clock();
    final result = switch (command) {
      WorkDayCommand.start => widget.engine.startWorkDay(now),
      WorkDayCommand.pause => widget.engine.pause(now),
      WorkDayCommand.resume => widget.engine.resume(now),
      WorkDayCommand.finish => widget.engine.finishWorkDay(now),
    };

    setState(() {
      _rejection = switch (result) {
        WorkDayCommandAccepted() => null,
        WorkDayCommandRejected(:final reason) => reason,
      };
      _snapshot = widget.engine.snapshot(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(title: const Text('Рабочий день')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Text(
                phaseTitle(snapshot.phase),
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                'До конца рабочего окна: '
                '${formatSpan(snapshot.remainingInWorkWindow)}',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Отработано: ${formatSpan(snapshot.worked)}',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final command in snapshot.availableCommands)
                    FilledButton(
                      onPressed: () => _run(command),
                      child: Text(commandLabel(command, snapshot.phase)),
                    ),
                ],
              ),
              if (_rejection != null) ...[
                const SizedBox(height: 24),
                Text(
                  rejectionText(_rejection!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
