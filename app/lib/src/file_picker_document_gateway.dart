import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Файловый порт поверх `file_picker`.
///
/// Диалог сохранения получает байты сам и возвращает `Uri` (null — отмена),
/// поэтому путь к файлу нигде не нужен: на Android это SAF, на iOS — временная
/// копия, на Windows — обычный файл. Диалог выбора отдаёт `PlatformFile`,
/// который читается здесь целиком.
final class FilePickerDocumentGateway implements DocumentFileGateway {
  const FilePickerDocumentGateway();

  @override
  Future<bool> save(String contents, {required String suggestedName}) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: utf8.encode(contents),
      mimeType: 'application/json',
      dialogTitle: 'Экспорт данных',
    );
    return uri != null;
  }

  @override
  Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Импорт данных',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) {
      return null;
    }
    // allowMalformed: нечитаемый как UTF-8 файл доходит до разбора и получает
    // понятный отказ «документ повреждён» вместо падения адаптера.
    return const Utf8Decoder(allowMalformed: true).convert(
      await file.readAsBytes(),
    );
  }
}
