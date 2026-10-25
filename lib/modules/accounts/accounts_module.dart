import 'package:flutter/material.dart';
import '../../core/modules/home_section.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_api.dart';
import '../../core/modules/module_data_migration.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_permission.dart';
import 'account_repository.dart';
import 'accounts_search_provider.dart';
import 'category_repository.dart';
import 'game_repository.dart';
import 'ui/accounts_screen.dart';
import 'ui/home/accounts_home_section.dart';

/// РњРѕРґСѓР»СЊ Accounts вЂ” СѓРїСЂР°РІР»РµРЅРёРµ Р°РєРєР°СѓРЅС‚Р°РјРё РёРіСЂ Рё РїСЂРѕС„РёР»СЏРјРё.
///
/// Р­С‚Р°Рї 10.4: РїРѕР»РЅС‹Р№ UI РјРѕРґСѓР»СЏ.
class AccountsModule extends Module {
  static const ModuleManifest _manifest = ModuleManifest(
    id: 'accounts',
    name: 'Аккаунты',
    version: '0.2.0',
    apiVersion: kCoreModuleApiVersion,
    author: 'Personal Hub',
    description: 'РЈРїСЂР°РІР»РµРЅРёРµ Р°РєРєР°СѓРЅС‚Р°РјРё РёРіСЂ, РїСЂРѕС„РёР»СЏРјРё Рё РєР°С‚РµРіРѕСЂРёСЏРјРё.',
    schemaVersion: 1,
    permissions: [ModulePermission.coreSearch],
  );

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.account_circle_outlined;

  @override
  int get order => 50;

  @override
  List<ModuleDataMigration> get dataMigrations => const <ModuleDataMigration>[];

  AccountsSearchProvider? _searchProvider;

  @override
  Future<void> onInstall(ModuleApi api) async {
    // РњРёРіСЂР°С†РёСЏ (РµСЃР»Рё Р±СѓРґРµС‚) Р·Р°РїСѓСЃРєР°РµС‚СЃСЏ РїР»Р°С‚С„РѕСЂРјРѕР№ С‡РµСЂРµР· runPendingMigrations.
  }

  @override
  Future<void> onEnable(ModuleApi api) async {
    final provider = AccountsSearchProvider(
      AccountRepository(api.storage),
      GameRepository(api.storage, AccountRepository(api.storage), CategoryRepository(api.storage)),
      CategoryRepository(api.storage),
    );
    _searchProvider = provider;
    api.registerSearchProvider(provider);
  }

  @override
  Future<void> onDisable(ModuleApi api) async {
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Future<void> onUninstall(ModuleApi api) async {
    // Р—Р°С‰РёС‚РЅС‹Р№ РґСѓР±Р»СЊ.
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Widget buildPage(BuildContext context) => AccountsScreen(moduleId: id);
}


