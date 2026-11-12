import 'dart:async';

import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'clock.dart';
import 'desktop/desktop_shell.dart';
import 'labels.dart';
import 'notifications/reminder_status.dart';

/// Поля экрана настроек. Ключи устойчивы: тесты ищут поля по ним, а не по
/// текстам.
enum _Field {
  workStart('work-start'),
  workEnd('work-end'),
  shortRestInterval('short-rest-interval'),
  shortRestDuration('short-rest-duration'),
  longRestInterval('long-rest-interval'),
  longRestDuration('long-rest-duration'),
  mealStart('meal-start'),
  mealDuration('meal-duration');

  const _Field(this.key);

  final String key;
}

/// Экран настроек. Показывает значения из снимка ядра и отправляет изменённые
/// обратно в движок: диапазоны и тексты отказов — правила ядра, экран их не
/// повторяет и сам ничего не вычисляет.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.engine,
    required this.clock,
    required this.transfer,
    this.onStateChanged,
    this.reminderStatus,
    this.desktop,
  });

  final WorkDayEngine engine;
  final Clock clock;

  /// Экспорт и импорт документа: ядро решает, что попадает в файл, экран лишь
  /// спрашивает подтверждение и показывает причину отказа.
  final DocumentTransfer transfer;

  /// Вызывается после принятого изменения настроек, чтобы оболочка сохранила
  /// документ ядра.
  final VoidCallback? onStateChanged;

  /// Разрешения напоминаний на платформе. Null — платформа без напоминаний:
  /// переключатели остаются, а строки о разрешениях нет.
  final ReminderStatusSource? reminderStatus;

  /// Возможности Windows: трей и автозапуск. Null или не Windows — строк про
  /// трей нет: на других платформах таких настроек не существует.
  final DesktopPreferences? desktop;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<_Field, TextEditingController> _controllers = {
    for (final field in _Field.values) field: TextEditingController(),
  };

  _Field? _errorField;
  String? _errorText;
  String? _transferError;
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _minimizeToTray = true;
  bool _launchAtStartup = false;
  String? _desktopError;
  ReminderStatus? _reminderStatus;

  @override
  void initState() {
    super.initState();
    final settings = widget.engine.snapshot(widget.clock.now()).settings;
    _fill(settings);
    _notificationsEnabled = settings.notificationsEnabled;
    _soundEnabled = settings.soundEnabled;
    _minimizeToTray = settings.minimizeToTray;
    _launchAtStartup = settings.launchAtStartup;
    unawaited(_refreshReminderStatus());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(RhythmSettings settings) {
    _controllers[_Field.workStart]!.text = settings.workStart.toString();
    _controllers[_Field.workEnd]!.text = settings.workEnd.toString();
    _controllers[_Field.shortRestInterval]!.text = _minutesText(
      settings.shortRestInterval,
    );
    _controllers[_Field.shortRestDuration]!.text = _minutesText(
      settings.shortRestDuration,
    );
    _controllers[_Field.longRestInterval]!.text = _minutesText(
      settings.longRestInterval,
    );
    _controllers[_Field.longRestDuration]!.text = _minutesText(
      settings.longRestDuration,
    );
    _controllers[_Field.mealStart]!.text = settings.mealStart.toString();
    _controllers[_Field.mealDuration]!.text = _minutesText(
      settings.mealDuration,
    );
  }

  String _text(_Field field) => _controllers[field]!.text;

  void _save() {
    final workStart = _parseClockTime(_text(_Field.workStart));
    if (workStart == null) {
      return _reportFormat(_Field.workStart);
    }
    final workEnd = _parseClockTime(_text(_Field.workEnd));
    if (workEnd == null) {
      return _reportFormat(_Field.workEnd);
    }
    final shortRestInterval = _parseMinutes(_text(_Field.shortRestInterval));
    if (shortRestInterval == null) {
      return _reportFormat(_Field.shortRestInterval);
    }
    final shortRestDuration = _parseMinutes(_text(_Field.shortRestDuration));
    if (shortRestDuration == null) {
      return _reportFormat(_Field.shortRestDuration);
    }
    final longRestInterval = _parseMinutes(_text(_Field.longRestInterval));
    if (longRestInterval == null) {
      return _reportFormat(_Field.longRestInterval);
    }
    final longRestDuration = _parseMinutes(_text(_Field.longRestDuration));
    if (longRestDuration == null) {
      return _reportFormat(_Field.longRestDuration);
    }
    final mealStart = _parseClockTime(_text(_Field.mealStart));
    if (mealStart == null) {
      return _reportFormat(_Field.mealStart);
    }
    final mealDuration = _parseMinutes(_text(_Field.mealDuration));
    if (mealDuration == null) {
      return _reportFormat(_Field.mealDuration);
    }

    final now = widget.clock.now();
    final current = widget.engine.snapshot(now).settings;
    final candidate = RhythmSettings(
      workStart: workStart,
      workEnd: workEnd,
      shortRestInterval: shortRestInterval,
      shortRestDuration: shortRestDuration,
      longRestInterval: longRestInterval,
      longRestDuration: longRestDuration,
      mealStart: mealStart,
      mealDuration: mealDuration,
      notificationsEnabled: current.notificationsEnabled,
      soundEnabled: current.soundEnabled,
    );

    setState(() {
      _errorField = null;
      _errorText = null;
    });
    switch (widget.engine.updateSettings(now, candidate)) {
      case WorkDayCommandAccepted():
        widget.onStateChanged?.call();
        Navigator.of(context).pop();
      case WorkDayCommandRejected(:final reason):
        setState(() {
          _errorField = _fieldFor(reason);
          _errorText = rejectionText(reason);
        });
    }
  }

  void _reset() {
    final now = widget.clock.now();
    switch (widget.engine.resetSettings(now)) {
      case WorkDayCommandAccepted():
        widget.onStateChanged?.call();
        Navigator.of(context).pop();
      case WorkDayCommandRejected(:final reason):
        setState(() {
          _errorField = null;
          _errorText = rejectionText(reason);
        });
    }
  }

  void _reportFormat(_Field field) {
    setState(() {
      _errorField = field;
      _errorText = 'Проверьте формат значения';
    });
  }

  Future<void> _export() async {
    final outcome = await widget.transfer.export(widget.clock.now());
    if (!mounted || outcome is! ExportSaved) {
      return;
    }
    setState(() => _transferError = null);
    // Событие экспорта уже в журнале — сохраняем его на устройстве.
    widget.onStateChanged?.call();
  }

  Future<void> _import() async {
    final selection = await widget.transfer.selectImport();
    if (!mounted) {
      return;
    }
    switch (selection) {
      case ImportCancelled():
        return;
      case ImportRejected(:final message):
        setState(() => _transferError = message);
        return;
      case ImportRead(:final document):
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('import-confirmation'),
            title: const Text('Импорт данных'),
            content: Text(
              'Заменить настройки и журнал событий данными из файла? '
              'В файле событий: ${document.journal.length}. '
              'Идущий рабочий день, отдых и предложение отдыха не изменятся.',
            ),
            actions: [
              TextButton(
                key: const ValueKey('import-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const ValueKey('import-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Заменить'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) {
          return;
        }
        widget.transfer.applyImport(widget.clock.now(), document);
        _fill(widget.engine.snapshot(widget.clock.now()).settings);
        setState(() => _transferError = null);
        widget.onStateChanged?.call();
    }
  }

  /// Переключатели напоминаний действуют сразу, не дожидаясь «Сохранить»:
  /// ядро перепланирует напоминания в тот же момент.
  void _setNotificationsEnabled(bool value) {
    _applyImmediately(
      (settings) => settings.copyWith(notificationsEnabled: value),
      () => _notificationsEnabled = value,
    );
  }

  void _setSoundEnabled(bool value) {
    _applyImmediately(
      (settings) => settings.copyWith(soundEnabled: value),
      () => _soundEnabled = value,
    );
  }

  /// Трей и автозапуск: настройка живёт в ядре, а оболочка применяет её сразу.
  /// Если система не дала применить (например, автозапуск запрещён политикой),
  /// экран говорит об этом честно, а настройка остаётся прежней.
  Future<void> _setMinimizeToTray(bool value) async {
    final applied = await widget.desktop!.setCloseToTray(value);
    if (!mounted) {
      return;
    }
    if (!applied) {
      setState(() => _desktopError = 'Не удалось изменить поведение окна');
      return;
    }
    setState(() => _desktopError = null);
    _applyImmediately(
      (settings) => settings.copyWith(minimizeToTray: value),
      () => _minimizeToTray = value,
    );
  }

  Future<void> _setLaunchAtStartup(bool value) async {
    final applied = await widget.desktop!.setLaunchAtStartup(value);
    if (!mounted) {
      return;
    }
    if (!applied) {
      setState(
        () => _desktopError = value
            ? 'Система не разрешила автозапуск'
            : 'Система не разрешила отключить автозапуск',
      );
      return;
    }
    setState(() => _desktopError = null);
    _applyImmediately(
      (settings) => settings.copyWith(launchAtStartup: value),
      () => _launchAtStartup = value,
    );
  }

  void _applyImmediately(
    RhythmSettings Function(RhythmSettings current) change,
    void Function() applyLocal,
  ) {
    final now = widget.clock.now();
    final current = widget.engine.snapshot(now).settings;
    switch (widget.engine.updateSettings(now, change(current))) {
      case WorkDayCommandAccepted():
        setState(() {
          applyLocal();
          _errorField = null;
          _errorText = null;
        });
        widget.onStateChanged?.call();
      case WorkDayCommandRejected(:final reason):
        setState(() {
          _errorField = null;
          _errorText = rejectionText(reason);
        });
    }
  }

  Future<void> _refreshReminderStatus() async {
    final source = widget.reminderStatus;
    if (source == null) {
      return;
    }
    final status = await source.read();
    if (!mounted) {
      return;
    }
    setState(() => _reminderStatus = status);
  }

  Future<void> _requestExactAlarms() async {
    final source = widget.reminderStatus;
    if (source == null) {
      return;
    }
    final status = await source.requestExactAlarms();
    if (!mounted) {
      return;
    }
    setState(() => _reminderStatus = status);
  }

  _Field? _fieldFor(RejectionReason reason) => switch (reason) {
    RejectionReason.workWindowStartNotBeforeEnd => _Field.workStart,
    RejectionReason.shortRestIntervalOutOfRange => _Field.shortRestInterval,
    RejectionReason.shortRestDurationOutOfRange => _Field.shortRestDuration,
    RejectionReason.longRestIntervalOutOfRange => _Field.longRestInterval,
    RejectionReason.longRestDurationOutOfRange => _Field.longRestDuration,
    RejectionReason.mealDurationNotPositive => _Field.mealDuration,
    RejectionReason.mealNotInsideWorkWindow => _Field.mealStart,
    _ => null,
  };

  String _label(_Field field) => switch (field) {
    _Field.workStart => 'Начало рабочего окна',
    _Field.workEnd => 'Конец рабочего окна',
    _Field.shortRestInterval => 'Короткий отдых, интервал',
    _Field.shortRestDuration => 'Короткий отдых, длительность',
    _Field.longRestInterval => 'Длинный отдых, интервал',
    _Field.longRestDuration => 'Длинный отдых, длительность',
    _Field.mealStart => 'Обед, время',
    _Field.mealDuration => 'Обед, длительность',
  };

  String _hint(_Field field) => switch (field) {
    _Field.workStart || _Field.workEnd || _Field.mealStart => 'ЧЧ:ММ',
    _Field.shortRestInterval => '20–30 мин',
    _Field.shortRestDuration => '20 с – 5 мин',
    _Field.longRestInterval => '60–120 мин',
    _Field.longRestDuration => '5–15 мин',
    _Field.mealDuration => 'мин',
  };

  String _minutesText(Duration duration) {
    final seconds = duration.inSeconds;
    if (seconds % Duration.secondsPerMinute == 0) {
      return '${seconds ~/ Duration.secondsPerMinute}';
    }
    final minutes = seconds / Duration.secondsPerMinute;
    return minutes
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  ClockTime? _parseClockTime(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return ClockTime(hour, minute);
  }

  Duration? _parseMinutes(String text) {
    final minutes = double.tryParse(text.trim().replaceAll(',', '.'));
    if (minutes == null || !minutes.isFinite || minutes.abs() > 1e6) {
      return null;
    }
    return Duration(
      milliseconds: (minutes * Duration.millisecondsPerMinute).round(),
    );
  }

  /// Строки о разрешениях напоминаний: экран честно показывает, что точные
  /// напоминания недоступны, и даёт попросить разрешение.
  List<Widget> _reminderStatusChildren(ThemeData theme) {
    final status = _reminderStatus;
    if (widget.reminderStatus == null || status == null) {
      return const <Widget>[];
    }
    return [
      if (status.exactAlarmsApplicable)
        Text(
          status.exactAlarms
              ? 'Напоминания точные: система будит приложение в назначенную минуту'
              : 'Напоминания неточные: нет разрешения на точные будильники, '
                    'система может задержать их на несколько минут',
          key: const ValueKey('settings-exact-alarms'),
          style: theme.textTheme.bodyMedium,
        ),
      if (!status.notificationsAllowed) ...[
        const SizedBox(height: 4),
        Text(
          'Уведомления приложения запрещены в системе',
          key: const ValueKey('settings-notifications-blocked'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      if (status.exactAlarmsApplicable && !status.exactAlarms) ...[
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('settings-request-exact-alarms'),
            onPressed: _requestExactAlarms,
            child: const Text('Разрешить точные напоминания'),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  key: const ValueKey('settings-notifications'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Напоминания'),
                  subtitle: const Text('Уведомление, когда пора отдохнуть'),
                  value: _notificationsEnabled,
                  onChanged: _setNotificationsEnabled,
                ),
                SwitchListTile(
                  key: const ValueKey('settings-sound'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Звук напоминаний'),
                  subtitle: const Text('Выключенный звук не мешает окружающим'),
                  value: _soundEnabled,
                  onChanged: _setSoundEnabled,
                ),
                ..._reminderStatusChildren(theme),
                if (widget.desktop?.isSupported ?? false) ...[
                  const Divider(),
                  SwitchListTile(
                    key: const ValueKey('settings-minimize-to-tray'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Сворачивать в трей'),
                    subtitle: const Text(
                      'Закрытие окна прячет приложение в трей: ритм и '
                      'напоминания продолжаются',
                    ),
                    value: _minimizeToTray,
                    onChanged: _setMinimizeToTray,
                  ),
                  SwitchListTile(
                    key: const ValueKey('settings-launch-at-startup'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Запускать вместе с системой'),
                    subtitle: const Text(
                      'Приложение стартует автоматически при входе в Windows',
                    ),
                    value: _launchAtStartup,
                    onChanged: _setLaunchAtStartup,
                  ),
                  if (_desktopError != null)
                    Text(
                      _desktopError!,
                      key: const ValueKey('settings-desktop-error'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                for (final field in _Field.values) ...[
                  TextField(
                    key: ValueKey('settings-${field.key}'),
                    controller: _controllers[field],
                    decoration: InputDecoration(
                      labelText: _label(field),
                      helperText: _hint(field),
                    ),
                  ),
                  if (_errorField == field) ...[
                    const SizedBox(height: 4),
                    Text(
                      _errorText!,
                      key: ValueKey('settings-error-${field.key}'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
                if (_errorField == null && _errorText != null) ...[
                  Text(
                    _errorText!,
                    key: const ValueKey('settings-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  key: const ValueKey('settings-save'),
                  onPressed: _save,
                  child: const Text('Сохранить'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey('settings-defaults'),
                  onPressed: _reset,
                  child: const Text('По умолчанию'),
                ),
                const SizedBox(height: 24),
                Text('Данные', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('settings-export'),
                  onPressed: _export,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Экспорт в файл'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('settings-import'),
                  onPressed: _import,
                  icon: const Icon(Icons.download),
                  label: const Text('Импорт из файла'),
                ),
                if (_transferError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _transferError!,
                    key: const ValueKey('settings-transfer-error'),
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
