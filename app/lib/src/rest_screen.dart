import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'clock.dart';
import 'labels.dart';

/// Полноэкранный экран отдыха. Всё, что он показывает, берётся из снимка ядра:
/// таймером владеет ядро, поэтому закрытие экрана отдых не прерывает.
class RestScreen extends StatefulWidget {
  const RestScreen({super.key, required this.engine, required this.clock});

  final WorkDayEngine engine;
  final Clock clock;

  @override
  State<RestScreen> createState() => _RestScreenState();
}

class _RestScreenState extends State<RestScreen> {
  late WorkDaySnapshot _snapshot;
  RejectionReason? _rejection;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.engine.snapshot(widget.clock.now());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static bool _isRestPhase(WorkDayPhase phase) =>
      phase == WorkDayPhase.resting || phase == WorkDayPhase.restOffered;

  void _refresh() {
    final snapshot = widget.engine.snapshot(widget.clock.now());
    if (!mounted) {
      return;
    }
    if (!_isRestPhase(snapshot.phase)) {
      // Отдых закончился — экрану нечего показывать, возвращаемся к работе.
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _snapshot = snapshot);
  }

  void _dispatchCommand(WorkDayCommand command) {
    final now = widget.clock.now();
    final result = switch (command) {
      WorkDayCommand.startRest => widget.engine.startRest(now),
      WorkDayCommand.finishRest => widget.engine.finishRest(now),
      WorkDayCommand.skipRest => widget.engine.skipRest(now),
      WorkDayCommand.postponeRest => widget.engine.postponeRest(now),
      WorkDayCommand.startMeal => widget.engine.startMeal(now),
      WorkDayCommand.pause => widget.engine.pause(now),
      WorkDayCommand.resume => widget.engine.resume(now),
      WorkDayCommand.finish => widget.engine.finishWorkDay(now),
      WorkDayCommand.start => widget.engine.startWorkDay(now),
    };

    final snapshot = widget.engine.snapshot(now);
    if (!_isRestPhase(snapshot.phase)) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _rejection = switch (result) {
        WorkDayCommandAccepted() => null,
        WorkDayCommandRejected(:final reason) => reason,
      };
      _snapshot = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final resting = snapshot.phase == WorkDayPhase.resting;
    final restKind = snapshot.restKind;

    return Scaffold(
      appBar: AppBar(
        title: Text(resting ? 'Отдых' : 'Пора отдохнуть'),
        leading: IconButton(
          key: const ValueKey('rest-screen-close'),
          icon: const Icon(Icons.close),
          tooltip: 'Закрыть',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (restKind != null) ...[
                  Text(
                    restKindLabel(restKind),
                    key: const ValueKey('rest-screen-kind'),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (!resting && snapshot.restDuration != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Длительность: '
                      '${formatHoursMinutes(snapshot.restDuration!)}',
                      key: const ValueKey('rest-screen-duration'),
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (resting) ...[
                  Text(
                    formatClock(snapshot.remainingRest ?? Duration.zero),
                    key: const ValueKey('rest-screen-countdown'),
                    style: theme.textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  for (final (index, exercise) in snapshot.exercises.indexed)
                    _ExerciseCard(index: index, exercise: exercise),
                  const SizedBox(height: 32),
                  FilledButton(
                    key: const ValueKey('rest-command-finishRest'),
                    onPressed: () =>
                        _dispatchCommand(WorkDayCommand.finishRest),
                    child: const Text('Закончить сейчас'),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final command in snapshot.availableCommands)
                        if (command == WorkDayCommand.startRest ||
                            command == WorkDayCommand.skipRest)
                          FilledButton(
                            key: ValueKey('rest-command-${command.name}'),
                            onPressed: () => _dispatchCommand(command),
                            child: Text(
                              commandLabel(
                                command,
                                snapshot.phase,
                                restKind: snapshot.restKind,
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
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
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.index, required this.exercise});

  final int index;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      key: ValueKey('exercise-${exercise.id}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise.name,
              key: ValueKey('exercise-name-$index'),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              exercise.description,
              key: ValueKey('exercise-description-$index'),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${exerciseCategoryLabel(exercise.category)} · '
              '${formatExerciseDuration(exercise.duration)}',
              key: ValueKey('exercise-duration-$index'),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}
