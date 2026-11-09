import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:work_rest_core/work_rest_core.dart';
import 'package:work_rest_time_balancer/src/preferences_document_store.dart';

DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 3, 4, hour, minute);

void main() {
  setUp(() {
    // Настоящее устройство в тестах не нужно: хранилище платформы подменяется
    // памятным, а адаптер работает ровно так же.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('адаптер возвращает записанный документ целиком', () async {
    final engine = WorkDayEngine(
      settings: RhythmSettings.defaults.copyWith(soundEnabled: false),
    );
    engine.startWorkDay(_at(9));
    final document = engine.document().toJsonString();

    await SharedPreferencesDocumentStore().write(document);

    expect(await SharedPreferencesDocumentStore().read(), document);
  });

  test('без сохранённого документа адаптер отдаёт null', () async {
    expect(await SharedPreferencesDocumentStore().read(), isNull);
  });

  test('записанный документ разбирается ядром после перезапуска', () async {
    final engine = WorkDayEngine();
    engine.startWorkDay(_at(9));
    engine.snapshot(_at(9, 10));

    await SharedPreferencesDocumentStore().write(
      engine.document().toJsonString(),
    );

    final payload = await SharedPreferencesDocumentStore().read();
    final restored = PersistedDocument.fromJsonString(payload!);

    expect(restored.day, isNotNull);
    expect(restored.day!.phase, WorkDayPhase.running);
    expect(restored.journal, [WorkDayEvent.started(_at(9))]);
    expect(restored.settings, RhythmSettings.defaults);
  });

  test(
    'документ под нестандартным ключом не пересекается с основным',
    () async {
      final store = SharedPreferencesDocumentStore();
      final other = SharedPreferencesDocumentStore(
        key: '${SharedPreferencesDocumentStore.defaultKey}.export',
      );

      await store.write('основной');
      await other.write('перенос');

      expect(await store.read(), 'основной');
      expect(await other.read(), 'перенос');
    },
  );
}
