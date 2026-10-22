/// Экран ошибки запуска.
library startup_error_screen;

import 'package:flutter/material.dart';
import '../../core/design/design_system.dart';

/// Показывается, когда инициализация приложения не удалась.
///
/// Раньше любая ошибка до `runApp()` (например, не открывшийся Isar)
/// означала чёрный экран: `main()` падал, а показывать было нечего.
/// Теперь пользователь видит, что произошло, и может сообщить о
/// проблеме вместо молчаливого «ничего не работает».
///
/// Технические детали намеренно не показываются: строка с ошибкой
/// может содержать путь к файлу базы. Диагностика остаётся в debug-логе
/// (см. main.dart).
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, this.onRetry});

  /// Повторная попытка запуска. Необязателен: в release можно просто
  /// перезапустить приложение.
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              // Единый адаптивный стандарт отступа экрана (Stage 11):
              // раньше здесь был литерал 24 — четвёртый разные боковой
              // отступ в приложении наряду с 16, 20 и 32.
              padding: AppInsets.screenBody(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Не удалось запустить приложение',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Данные не были изменены. Перезапустите приложение. '
                      'Если ошибка повторяется — сообщите о ней разработчику.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => onRetry!(),
                        child: const Text('Повторить запуск'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
