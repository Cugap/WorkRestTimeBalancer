import 'package:work_rest_core/work_rest_core.dart';

/// Хранилище документа в памяти: тесты не трогают устройство.
final class FakeDocumentStore implements LocalDocumentStore {
  FakeDocumentStore([this.document]);

  String? document;
  int writes = 0;

  @override
  Future<String?> read() async => document;

  @override
  Future<void> write(String document) async {
    writes++;
    this.document = document;
  }
}
