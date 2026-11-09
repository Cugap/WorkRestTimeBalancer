import 'package:shared_preferences/shared_preferences.dart';
import 'package:work_rest_core/work_rest_core.dart';

/// Адаптер порта хранения ядра поверх локальных настроек платформы.
///
/// Документ лежит одной строкой: ядро сериализует его само, адаптер ничего не
/// разбирает и никаких сетевых вызовов не делает.
final class SharedPreferencesDocumentStore implements LocalDocumentStore {
  SharedPreferencesDocumentStore({
    SharedPreferencesAsync? preferences,
    this.key = defaultKey,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  /// Ключ, под которым документ лежит в локальных настройках устройства.
  static const String defaultKey = 'work_rest_document';

  final SharedPreferencesAsync _preferences;
  final String key;

  @override
  Future<String?> read() => _preferences.getString(key);

  @override
  Future<void> write(String document) => _preferences.setString(key, document);
}
