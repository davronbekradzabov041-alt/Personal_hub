import 'package:flutter/material.dart';
import '../module.dart';
import '../module_manifest.dart';

/// Мост между декларативным ModulePackage (Этап 11) и Module (Этап 7).
///
/// Отвечает на открытый вопрос, поставленный ещё на Этапе 7: `Module`
/// описывает модули со своим Dart-кодом (buildPage, lifecycle-хуки) —
/// а у внешнего пакета кода нет и не может быть (аудит Этапа 6,
/// требование безопасности Этапа 13). ExternalModuleAdapter решает
/// это не добавлением кодовыполнения, а обратным путём: строит
/// ОБЩУЮ, одинаковую для любого внешнего пакета страницу — просто
/// показывает поля манифеста. Никакой функциональности пакета это не
/// добавляет и не может добавить — у пакета её и нет.
///
/// **Architectural Rule:** External modules do not execute arbitrary
/// Dart code and do not provide arbitrary custom Flutter UI. External
/// modules are declarative packages consisting of manifest, controlled
/// capabilities, data and assets.
///
/// `ModuleRegistry.register()` всё ещё защищает от подмены: если id
/// уже занят ДРУГИМ объектом (например, настоящим встроенным
/// ExternalModuleAdapter-ом внешнего пакета того же id — или, для id
/// 'example', уже занят настоящим `ExampleModule`), регистрация
/// бросит ModuleLifecycleError (Этап 8), а не молча подменит модуль.
class ExternalModuleAdapter extends Module {
  ExternalModuleAdapter(this._manifest);
  final ModuleManifest _manifest;

  @override
  ModuleManifest get manifest => _manifest;

  @override
  IconData get icon => Icons.extension_outlined; // общая иконка — своей у пакета нет

  @override
  Widget buildPage(BuildContext context) => _ExternalModuleDetailsPage(manifest: _manifest);
}

/// Единственная, общая для ЛЮБОГО внешнего пакета страница —
/// показывает манифест как есть, ничего не выполняет.
class _ExternalModuleDetailsPage extends StatelessWidget {
  const _ExternalModuleDetailsPage({required this.manifest});
  final ModuleManifest manifest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(manifest.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Внешний модуль — у него нет собственного кода, эта '
            'страница показывает только данные манифеста.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 16),
          _Field('Версия', manifest.version),
          _Field('API', manifest.apiVersion.toString()),
          _Field('Автор', manifest.author),
          if (manifest.description.isNotEmpty)
            _Field('Описание', manifest.description),
          if (manifest.permissions.isNotEmpty)
            _Field('Разрешения',
                manifest.permissions.map((p) => p.id).join(', ')),
          if (manifest.dependencies.isNotEmpty)
            _Field('Зависимости',
                manifest.dependencies.map((d) => d.moduleId).join(', ')),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
