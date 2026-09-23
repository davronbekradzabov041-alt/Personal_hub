import 'search_provider.dart';
import 'search_result.dart';

/// Агрегатор глобального поиска.
///
/// Держит список зарегистрированных SearchProvider и опрашивает
/// их все параллельно. UI (search_screen.dart) работает только
/// с этим сервисом и не знает, сколько источников за ним стоит —
/// сейчас один (тестовые данные ядра), в будущем добавятся модули.
class GlobalSearchService {
  GlobalSearchService();

  final List<SearchProvider> _providers = [];

  void registerProvider(SearchProvider provider) {
    _providers.add(provider);
  }

  /// Убирает ранее зарегистрированный источник. Нужен для
  /// ModuleApi.unregisterSearchProvider (Этап 7) — модуль,
  /// который отключают или удаляют, не должен оставаться в
  /// результатах поиска.
  void unregisterProvider(SearchProvider provider) {
    _providers.remove(provider);
  }

  /// Число сейчас зарегистрированных источников. Только для тестов
  /// и отладки (Этап 10 — проверить, что модуль register/unregister
  /// действительно меняет состояние сервиса) — бизнес-логика не
  /// должна на это полагаться.
  int get providerCount => _providers.length;

  Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final resultsPerProvider = await Future.wait(
      _providers.map((provider) => provider.search(trimmed)),
    );

    return resultsPerProvider.expand((results) => results).toList();
  }
}
