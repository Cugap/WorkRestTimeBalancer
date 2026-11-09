import 'document_file_gateway.dart';
import 'persisted_document.dart';
import 'work_day_engine.dart';

/// Итог экспорта. Отмена ничего не меняет и не пишет событий.
sealed class ExportOutcome {
  const ExportOutcome();
}

/// Файл записан на диск.
final class ExportSaved extends ExportOutcome {
  const ExportSaved();
}

/// Пользователь закрыл диалог сохранения, ничего не произошло.
final class ExportCancelled extends ExportOutcome {
  const ExportCancelled();
}

/// Итог выбора файла для импорта. Только [ImportRead] даёт документ, который
/// можно применить; остальные варианты текущие данные не меняют.
sealed class ImportOutcome {
  const ImportOutcome();
}

/// Пользователь закрыл диалог выбора файла.
final class ImportCancelled extends ImportOutcome {
  const ImportCancelled();
}

/// Файл выбран и разобран, но к текущим данным ещё ничего не применено:
/// оболочка спрашивает подтверждение и только потом зовёт
/// [DocumentTransfer.applyImport].
final class ImportRead extends ImportOutcome {
  const ImportRead(this.document);

  final PersistedDocument document;
}

/// Файл не подошёл: чужая версия формата или повреждение. Текущие данные не
/// тронуты.
final class ImportRejected extends ImportOutcome {
  const ImportRejected(this.rejection, this.message);

  final DocumentRejection rejection;
  final String message;
}

/// Перенос документа между устройствами: единственное место, где решается, что
/// попадает в файл экспорта и что применяется из файла импорта.
///
/// Экспорт кладёт в файл только настройки и журнал событий — это и есть предмет
/// переноса по спецификации; состояние текущего рабочего дня остаётся на
/// устройстве. Импорт читает файл целиком и применяет из него те же настройки и
/// журнал, не трогая идущий рабочий день.
final class DocumentTransfer {
  DocumentTransfer({required this.engine, required this.gateway});

  /// Имя файла, которое диалог сохранения предлагает по умолчанию.
  static const String fileName = 'work-rest-backup.json';

  final WorkDayEngine engine;
  final DocumentFileGateway gateway;

  /// Сохранить настройки и журнал событий в файл.
  ///
  /// Событие экспорта пишется в журнал устройства только после того, как файл
  /// действительно сохранён: отменённое сохранение не оставляет следа.
  Future<ExportOutcome> export(DateTime now) async {
    final document = engine.document().withDay(null);
    final saved = await gateway.save(
      document.toJsonString(),
      suggestedName: fileName,
    );
    if (!saved) {
      return const ExportCancelled();
    }
    engine.recordExport(now);
    return const ExportSaved();
  }

  /// Прочитать файл, выбранный пользователем, и проверить его.
  ///
  /// Ничего не применяет: оболочка показывает подтверждение и лишь после него
  /// вызывает [applyImport]. Чужой формат и повреждение возвращаются отказом с
  /// понятным сообщением, текущие данные при этом не меняются.
  Future<ImportOutcome> selectImport() async {
    final payload = await gateway.pick();
    if (payload == null) {
      return const ImportCancelled();
    }
    try {
      return ImportRead(PersistedDocument.fromJsonString(payload));
    } on DocumentFormatException catch (error) {
      return ImportRejected(error.reason, error.message);
    }
  }

  /// Применить импортированный документ: настройки и журнал заменяются,
  /// идущий рабочий день, идущий отдых и показанное предложение остаются.
  /// Вызывается только после явного подтверждения пользователя.
  void applyImport(DateTime now, PersistedDocument imported) {
    engine.applyImportedDocument(now, imported);
  }
}
