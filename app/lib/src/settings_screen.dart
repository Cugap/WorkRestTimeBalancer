import 'package:flutter/material.dart';
import 'package:work_rest_core/work_rest_core.dart';

import 'clock.dart';
import 'labels.dart';

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
    this.onStateChanged,
  });

  final WorkDayEngine engine;
  final Clock clock;

  /// Вызывается после принятого изменения настроек, чтобы оболочка сохранила
  /// документ ядра.
  final VoidCallback? onStateChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<_Field, TextEditingController> _controllers = {
    for (final field in _Field.values) field: TextEditingController(),
  };

  _Field? _errorField;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _fill(widget.engine.snapshot(widget.clock.now()).settings);
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
