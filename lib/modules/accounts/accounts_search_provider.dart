import 'package:flutter/material.dart';

import '../../core/search/search_provider.dart';
import '../../core/search/search_result.dart';
import 'account_repository.dart';
import 'category_repository.dart';
import 'game_repository.dart';

/// Источник поиска Accounts — по аккаунтам, играм и категориям.
///
/// Регистрируется в onEnable, отписывается в onDisable.
/// Читает через репозитории, а не напрямую через ModuleStorage.
class AccountsSearchProvider implements SearchProvider {
  AccountsSearchProvider(
    this._accountRepository,
    this._gameRepository,
    this._categoryRepository,
  );

  final AccountRepository _accountRepository;
  final GameRepository _gameRepository;
  final CategoryRepository _categoryRepository;

  @override
  Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final lowerQuery = trimmed.toLowerCase();

    // Читаем все данные — три последовательных чтения одного хранилища
    // дают согласованный снимок.
    final accounts = await _accountRepository.getAll();
    final games = await _gameRepository.getAll();
    final categories = await _categoryRepository.getAll();

    final categoryById = {for (final c in categories) c.id: c};

    final results = <SearchResult>[];

    // Поиск по аккаунтам
    for (final account in accounts) {
      if (account.name.toLowerCase().contains(lowerQuery) ||
          account.type.label.toLowerCase().contains(lowerQuery) ||
          account.note.toLowerCase().contains(lowerQuery)) {
        results.add(SearchResult(
          title: account.name,
          subtitle: 'Аккаунт · ${account.type.label}',
          icon: Icons.account_circle_outlined,
        ));
      }
    }

    // Поиск по играм
    for (final game in games) {
      final categoryNames = game.categoryIds
          .map((id) => categoryById[id]?.name)
          .whereType<String>()
          .join(', ');

      final matchesTitle = game.title.toLowerCase().contains(lowerQuery);
      final matchesPlatform = game.platform.label.toLowerCase().contains(lowerQuery);
      final matchesStatus = game.status.label.toLowerCase().contains(lowerQuery);
      final matchesNote = game.note.toLowerCase().contains(lowerQuery);
      final matchesCategory = categoryNames.toLowerCase().contains(lowerQuery);

      if (matchesTitle || matchesPlatform || matchesStatus || matchesNote || matchesCategory) {
        final subtitleParts = <String>[
          'Игра',
          game.platform.label,
          game.status.label,
        ];
        if (game.region != null) subtitleParts.add(game.region!);
        if (categoryNames.isNotEmpty) subtitleParts.add(categoryNames);

        results.add(SearchResult(
          title: game.title,
          subtitle: subtitleParts.join(' · '),
          icon: Icons.videogame_asset_outlined,
        ));
      }
    }

    // Поиск по категориям
    for (final category in categories) {
      if (category.name.toLowerCase().contains(lowerQuery)) {
        results.add(SearchResult(
          title: category.name,
          subtitle: 'Категория',
          icon: Icons.category_outlined,
        ));
      }
    }

    return results;
  }
}