import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'clock.dart';
import 'labels.dart';
import 'notifications/reminder_status.dart';
import 'rest_screen.dart';
import 'settings_screen.dart';

/// Главный экран: показывает снимок ядра и отправляет команды.
class WorkDayScreen extends StatefulWidget {
  const WorkDayScreen({
    super.key,
    required this.engine,
    required this.clock,
    required this.transfer,
    this.onStateChanged,
    this.reminderStatus,
  });

  final WorkDayEngine engine;
  final Clock clock;

  /// Экспорт и импорт документа; экран настроек открывает их оттуда.
  final DocumentTransfer transfer;

  /// Вызывается после каждого принятого изменения состояния: оболочка
  /// сохраняет документ ядра. Экран о хранилище ничего не знает.
  final VoidCallback? onStateChanged;

  /// Источник состояния разрешений напоминаний: экран настроек показывает его
  /// как есть. Null — платформа без напоминаний.
  final ReminderStatusSource? reminderStatus;

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
    _snapshot = widget.engine.snapshot(widget.clock.now());
    _seenEvents = _snapshot.events.length;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  /// Сколько событий журнала уже сохранено: тик, дописавший событие, просит
  /// оболочку сохранить документ.
  late int _seenEvents;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    final snapshot = widget.engine.snapshot(widget.clock.now());
    if (snapshot.events.length != _seenEvents) {
      _seenEvents = snapshot.events.length;
      widget.onStateChanged?.call();
    }
    setState(() => _snapshot = snapshot);
  }

  void _dispatchCommand(WorkDayCommand command) {
    final now = widget.clock.now();
    final result = switch (command) {
      WorkDayCommand.start => widget.engine.startWorkDay(now),
      WorkDayCommand.pause => widget.engine.pause(now),
      WorkDayCommand.resume => widget.engine.resume(now),
      WorkDayCommand.finish => widget.engine.finishWorkDay(now),
      WorkDayCommand.startRest => widget.engine.startRest(now),
      WorkDayCommand.finishRest => widget.engine.finishRest(now),
      WorkDayCommand.skipRest => widget.engine.skipRest(now),
      WorkDayCommand.postponeRest => widget.engine.postponeRest(now),
      WorkDayCommand.startMeal => widget.engine.startMeal(now),
    };

    setState(() {
      _rejection = switch (result) {
        WorkDayCommandAccepted() => null,
        WorkDayCommandRejected(:final reason) => reason,
      };
      _snapshot = widget.engine.snapshot(now);
      _seenEvents = _snapshot.events.length;
    });
    if (result is WorkDayCommandAccepted) {
      widget.onStateChanged?.call();
    }
  }

  Future<void> _openRestScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RestScreen(
          engine: widget.engine,
          clock: widget.clock,
          onStateChanged: widget.onStateChanged,
        ),
      ),
    );
    if (mounted) {
      _refresh();
    }
  }

  Future<void> _openSettingsScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          engine: widget.engine,
          clock: widget.clock,
          transfer: widget.transfer,
          onStateChanged: widget.onStateChanged,
          reminderStatus: widget.reminderStatus,
        ),
      ),
    );
    if (mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Рабочий день'),
        actions: [
          IconButton(
            key: const ValueKey('open-settings-screen'),
            tooltip: 'Настройки',
            icon: const Icon(Icons.tune),
            onPressed: _openSettingsScreen,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phaseTitle(snapshot.phase),
                  key: ValueKey('phase-${snapshot.phase.name}'),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                if (snapshot.restKind != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    restKindLabel(snapshot.restKind!),
                    key: const ValueKey('rest-kind'),
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                if (snapshot.remainingRest != null) ...[
                  Text(
                    formatClock(snapshot.remainingRest!),
                    key: const ValueKey('rest-countdown'),
                    style: theme.textTheme.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                if (snapshot.untilNextRest != null) ...[
                  Text(
                    'До следующего отдыха: '
                    '${formatClock(snapshot.untilNextRest!)}',
                    key: const ValueKey('next-rest-countdown'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                ],
                if (snapshot.phase == WorkDayPhase.restOffered) ...[
                  Text(
                    snapshot.remainingPostponements == 0
                        ? 'Отложить отдых больше нельзя'
                        : 'Можно отложить ещё: '
                              '${snapshot.remainingPostponements}',
                    key: const ValueKey('postponements-left'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'До конца рабочего окна: '
                  '${formatHoursMinutes(snapshot.remainingInWorkWindow)}',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Отработано: '
                  '${formatHoursMinutes(snapshot.worked)}',
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
                        key: ValueKey('command-${command.name}'),
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
                if (snapshot.phase == WorkDayPhase.restOffered ||
                    snapshot.phase == WorkDayPhase.resting) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('open-rest-screen'),
                    onPressed: _openRestScreen,
                    icon: const Icon(Icons.self_improvement),
                    label: const Text('Экран отдыха'),
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
