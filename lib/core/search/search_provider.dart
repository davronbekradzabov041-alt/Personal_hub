import 'search_result.dart';

/// Контракт источника данных для глобального поиска.
///
/// Сейчас есть только один источник — тестовые данные ядра
/// (CoreTestItemSearchProvider). Когда появятся настоящие
/// модули, каждый сможет зарегистрировать свой SearchProvider
/// в GlobalSearchService, и поиск начнёт находить их данные
/// без единого изменения в UI экрана поиска.
abstract class SearchProvider {
  /// Возвращает результаты, соответствующие запросу.
  /// Пустая строка должна возвращать пустой список.
  Future<List<SearchResult>> search(String query);
}
