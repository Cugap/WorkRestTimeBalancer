import 'package:work_rest_core/work_rest_core.dart';

/// Файловый порт в тестах: системные диалоги не открываются, файл живёт в
/// памяти.
final class FakeFileGateway implements DocumentFileGateway {
  FakeFileGateway({this.picked, this.saveSucceeds = true});

  /// Что вернёт выбор файла; null — пользователь отменил выбор.
  String? picked;

  /// false — пользователь отменил сохранение.
  bool saveSucceeds;

  final List<String> saved = <String>[];
  int picks = 0;

  @override
  Future<bool> save(String contents, {required String suggestedName}) async {
    saved.add(contents);
    return saveSucceeds;
  }

  @override
  Future<String?> pick() async {
    picks++;
    return picked;
  }
}
