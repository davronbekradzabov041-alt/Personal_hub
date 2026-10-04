import 'package:flutter/material.dart';
import '../../core/modules/module.dart';
import '../../core/modules/module_api.dart';
import '../../core/modules/module_lifecycle_error.dart';
import '../../core/modules/module_manager_scope.dart';
import '../../core/modules/module_manifest.dart';
import '../../core/modules/module_permission.dart';
import '../../core/modules/module_state.dart';
import '../../core/modules/module_state_persistence.dart';
import '../../core/modules/module_state_persistence_scope.dart';
import '../../core/modules/module_storage.dart';
import '../../core/search/search_provider.dart';
import '../../core/search/search_result.dart';
import '../../core/design/design_system.dart';

/// Демонстрационный модуль — единственный настоящий модуль на Этапе 10.
///
/// Не Расписание/Финансы/и т.д. — они по-прежнему запрещены. Его
/// единственная цель — быть эталоном того, что система модулей
/// работает целиком: регистрация (ModuleRegistry, Этап 7), жизненный
/// цикл (ModuleManager, Этап 8), персистентность (Этап 9), а теперь
/// и собственное хранилище + собственный SearchProvider + страница,
/// которая сама управляет своим install/enable/disable/uninstall —
/// без какого-либо Module Store UI.
///
/// `extends Module` (не `implements`) — чтобы не переопределять
/// пустые lifecycle-хуки, которые не нужны (onInstall/onUninstall
/// используются по умолчанию, кроме защитной очистки в onUninstall).
class ExampleModule extends Module {
  static const ModuleManifest _manifest = ModuleManifest(
    id: 'example',
    name: 'Модуль-пример',
    version: '0.1.0',
    apiVersion: kCoreModuleApiVersion,
    author: 'Personal Hub',
    description: 'Эталонный модуль: показывает install/enable/disable/'
        'uninstall, собственные настройки и регистрацию в поиске.',
    // Без этого разрешения registerSearchProvider() в onEnable ниже
    // бросил бы ModuleLifecycleError — проверка разрешений из Этапа 8
    // здесь наконец на что-то реально влияет.
    permissions: [ModulePermission.coreSearch],
  );

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined;

  @override
  int get order => 999; // Всегда внизу меню

  _ExampleSearchProvider? _searchProvider;

  @override
  Future<void> onEnable(ModuleApi api) async {
    final provider = _ExampleSearchProvider(api.storage);
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
    // Защитный дубль: по правилам ModuleManager до uninstall модуль
    // обязательно проходит через disable(), так что провайдера здесь
    // уже быть не должно — но если когда-нибудь появится другой путь
    // к uninstall, лишняя проверка ничего не стоит.
    final provider = _searchProvider;
    if (provider != null) {
      api.unregisterSearchProvider(provider);
      _searchProvider = null;
    }
  }

  @override
  Widget buildPage(BuildContext context) => _ExampleModulePage(module: this);
}

/// Источник поиска модуля-примера — ищет по заметке, сохранённой
/// через собственное хранилище модуля (ModuleStorage, Этап 9).
class _ExampleSearchProvider implements SearchProvider {
  _ExampleSearchProvider(this._storage);
  final ModuleStorage _storage;

  @override
  Future<List<SearchResult>> search(String query) async {
    final note = await _storage.getString('note');
    if (note == null || note.isEmpty) return const [];
    if (!note.toLowerCase().contains(query.toLowerCase())) return const [];
    return [
      SearchResult(
        title: 'Модуль-пример',
        subtitle: note,
        icon: Icons.extension_outlined,
      ),
    ];
  }
}

/// Страница модуля-примера.
///
/// Сама управляет своим жизненным циклом (кнопки Установить/Включить/
/// Выключить/Удалить в зависимости от текущего состояния) и своими
/// настройками (заметка, сохраняемая через ModuleApi.storage) — без
/// отдельного глобального Module Store UI, который на этом этапе
/// запрещён.
class _ExampleModulePage extends StatefulWidget {
  const _ExampleModulePage({required this.module});
  final ExampleModule module;

  @override
  State<_ExampleModulePage> createState() => _ExampleModulePageState();
}

class _ExampleModulePageState extends State<_ExampleModulePage> {
  final _noteController = TextEditingController();
  bool _noteLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_noteLoadStarted) return;
    _noteLoadStarted = true;

    final manager = ModuleManagerScope.of(context);
    final api = manager.apiFor(widget.module.id);
    api.storage.getString('note').then((value) {
      if (mounted && value != null) {
        setState(() => _noteController.text = value);
      }
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Запускает lifecycle-действие и показывает ModuleLifecycleError
  /// снэкбаром вместо того, чтобы уронить необработанное исключение
  /// в консоль — полезно именно потому, что это эталонный модуль.
  ///
  /// Действие доводится до записи состояния через
  /// [ModuleStatePersistence.runAndFlush]: возвращаться «успехом» до
  /// того, как состояние легло в хранилище, нельзя — процесс можно
  /// завершить в промежутке, и модуль воскреснет.
  Future<void> _run(Future<void> Function() action) async {
    try {
      final persistence = ModuleStatePersistenceScope.of(context);
      await persistence.runAndFlush(action);
    } catch (error) {
      if (!mounted) return;
      final message = error is ModuleLifecycleError
          ? error.reason
          : error is ModuleStatePersistenceException
              ? error.reason
              : error.toString();
      AppComponents.showSnackBar(context: context, message: message);
    }
  }

  String _stateLabel(ModuleState? state) {
    switch (state) {
      case null:
        return 'не установлен';
      case ModuleState.installed:
        return 'установлен';
      case ModuleState.enabled:
        return 'включён';
      case ModuleState.disabled:
        return 'выключен';
      case ModuleState.uninstalled:
        return 'удалён';
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ModuleManagerScope.of(context);
    final id = widget.module.id;
    final api = manager.apiFor(id);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final state = manager.stateOf(id);

        return Scaffold(
          appBar: AppBar(title: Text(widget.module.title)),
          body: ListView(
            padding: AppInsets.md,
            children: [
              AppComponents.sectionHeader(
                context: context,
                title: 'Состояние модуля',
                subtitle: _stateLabel(state),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Версия ${widget.module.manifest.version} · '
                'API ${widget.module.manifest.apiVersion}',
                style: AppTypography.cardMetadata.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (state == null || state == ModuleState.uninstalled)
                    AppComponents.filledButton(
                      onPressed: () => _run(() => manager.install(id)),
                      child: const Text('Установить'),
                    ),
                  if (state == ModuleState.installed ||
                      state == ModuleState.disabled)
                    AppComponents.filledButton(
                      onPressed: () => _run(() => manager.enable(id)),
                      child: const Text('Включить'),
                    ),
                  if (state == ModuleState.enabled)
                    AppComponents.outlinedButton(
                      onPressed: () => _run(() => manager.disable(id)),
                      child: const Text('Выключить'),
                    ),
                  if (state == ModuleState.installed ||
                      state == ModuleState.disabled)
                    AppComponents.textButton(
                      onPressed: () => _run(() => manager.uninstall(id)),
                      child: const Text('Удалить'),
                    ),
                ],
              ),
              SizedBox(height: AppSpacing.xl),
              Divider(),
              SizedBox(height: AppSpacing.xl),
              AppComponents.sectionHeader(
                context: context,
                title: 'Собственные настройки модуля',
              ),
              SizedBox(height: AppSpacing.md),
              AppComponents.textField(
                controller: _noteController,
                labelText: 'Заметка (хранится через ModuleStorage)',
              ),
              SizedBox(height: AppSpacing.md),
              AppComponents.filledButton(
                onPressed: () {
                  api.storage.setString('note', _noteController.text);
                  AppComponents.showSnackBar(
                    context: context,
                    message: 'Сохранено',
                  );
                },
                leadingIcon: Icons.save_outlined,
                child: const Text('Сохранить'),
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Эта заметка находится через глобальный поиск, пока '
                'модуль включён — попробуйте выключить его и поискать '
                'снова.',
                style: AppTypography.cardMetadata.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
