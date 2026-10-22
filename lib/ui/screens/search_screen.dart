import 'package:flutter/material.dart';
import '../../core/search/search_result.dart';
import '../../core/search/search_scope.dart';
import '../../core/design/design_system.dart';

/// Экран глобального поиска.
///
/// Пока ищет только по тестовым данным ядра (CoreTestItem) —
/// единственный зарегистрированный SearchProvider. Экран об
/// этом не знает: он просто вызывает GlobalSearchService.search()
/// и рисует список SearchResult. Когда появятся модули со своими
/// провайдерами, этот файл менять не придётся.
/// AppBar предоставляется AppShell (Search доступен через Top Context Bar).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<SearchResult> _results = [];
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final service = SearchScope.of(context);
    final results = await service.search(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = query.trim().isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search field - moved from AppBar to body
          Padding(
            padding: AppInsets.screenBody(context),
            child: AppComponents.textField(
              controller: _controller,
              hintText: 'Поиск…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        _runSearch('');
                      },
                    )
                  : null,
              onChanged: _runSearch,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return AppComponents.emptyState(
        context: context,
        icon: Icons.search_outlined,
        title: 'Начните поиск',
        subtitle: 'Поиск идёт по тестовым данным ядра. Реальные модули добавят свои данные в поиск позже.',
      );
    }

    if (_results.isEmpty) {
      return AppComponents.emptyState(
        context: context,
        icon: Icons.search_off_outlined,
        title: 'Ничего не найдено',
        subtitle: 'Попробуйте изменить запрос',
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return AppComponents.listTile(
          context: context,
          leading: Icon(result.icon),
          title: Text(result.title),
          subtitle: result.subtitle != null ? Text(result.subtitle!) : null,
          onTap: result.onTap,
        );
      },
    );
  }
}
