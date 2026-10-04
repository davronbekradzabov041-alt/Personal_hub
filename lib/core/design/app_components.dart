import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import 'app_spacing.dart';
import 'app_animations.dart';

/// Переиспользуемые UI-компоненты Personal Hub.
///
/// Все компоненты используют токены Design System и не содержат
/// хардкодных цветов/отступов.
class AppComponents {
  AppComponents._();

  // =========================================================================
  // AppCard — базовая карточка
  // =========================================================================
  static Widget card({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? elevation,
    Color? color,
    BorderRadius? borderRadius,
    VoidCallback? onTap,
  }) {
    final cardWidget = Card(
      elevation: elevation ?? AppSpacing.elevation1,
      margin: margin ?? EdgeInsets.zero,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? AppRadii.md,
      ),
      child: Padding(
        padding: padding ?? AppInsets.cardPadding,
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? AppRadii.md,
        child: cardWidget,
      );
    }
    return cardWidget;
  }

  // =========================================================================
  // AppButton — единые кнопки
  // =========================================================================
  static Widget filledButton({
    required VoidCallback? onPressed,
    required Widget child,
    bool isLoading = false,
    IconData? leadingIcon,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  foregroundColor ?? Colors.white,
                ),
              ),
            )
          : (leadingIcon != null ? Icon(leadingIcon, size: 18) : const SizedBox.shrink()),
      label: child,
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          height: 1.43,
        ),
      ),
    );
  }

  static Widget outlinedButton({
    required VoidCallback? onPressed,
    required Widget child,
    bool isLoading = false,
    IconData? leadingIcon,
  }) {
    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: leadingIcon != null ? Icon(leadingIcon, size: 18) : const SizedBox.shrink(),
      label: child,
    );
  }

  static Widget textButton({
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: leadingIcon != null ? Icon(leadingIcon, size: 18) : const SizedBox.shrink(),
      label: child,
    );
  }

  // =========================================================================
  // AppTextField — единое текстовое поле
  // =========================================================================
  static Widget textField({
    required TextEditingController controller,
    String? labelText,
    String? hintText,
    String? helperText,
    String? errorText,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? prefixIcon,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    VoidCallback? onTap,
    int? maxLines = 1,
    int? minLines,
    bool enabled = true,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onTap: onTap,
      maxLines: maxLines,
      minLines: minLines,
      enabled: enabled,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  // =========================================================================
  // AppStatusChip — чип статуса модуля
  // =========================================================================
  static Widget statusChip({
    required BuildContext context,
    required ModuleStatus status,
    String? label,
  }) {
    final color = AppColors.statusColor(context, status);
    final onColor = AppColors.statusOnColor(context, status);

    return Chip(
      label: Text(
        label ?? _defaultLabel(status),
        style: AppTypography.chipLabel.copyWith(color: onColor),
      ),
      backgroundColor: color,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      shape: RoundedRectangleBorder(borderRadius: AppRadii.full),
    );
  }

  static String _defaultLabel(ModuleStatus status) {
    switch (status) {
      case ModuleStatus.installed:
        return 'Установлен';
      case ModuleStatus.enabled:
        return 'Включён';
      case ModuleStatus.disabled:
        return 'Выключен';
      case ModuleStatus.uninstalled:
        return 'Удалён';
      case ModuleStatus.updateAvailable:
        return 'Обновление';
    }
  }

  // =========================================================================
  // AppListTile — единый элемент списка
  // =========================================================================
  static Widget listTile({
    required BuildContext context,
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
    bool selected = false,
    Color? selectedColor,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: trailing,
      onTap: onTap,
      selected: selected,
      selectedTileColor: selectedColor ?? theme.colorScheme.primaryContainer,
      contentPadding: contentPadding ?? AppInsets.listItemPadding,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sm),
      tileColor: Colors.transparent,
    );
  }

  // =========================================================================
  // AppSectionHeader — заголовок секции
  // =========================================================================
  static Widget sectionHeader({
    required BuildContext context,
    required String title,
    String? subtitle,
    Widget? action,
    int? count,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (count != null)
            Padding(
              padding: EdgeInsets.only(left: AppSpacing.sm),
              child: Chip(
                label: Text(
                  '$count',
                  style: AppTypography.chipLabel.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                backgroundColor: theme.colorScheme.primaryContainer,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              ),
            ),
          if (action != null) action,
        ],
      ),
    );
  }

  // =========================================================================
  // AppEmptyState — пустое состояние
  // =========================================================================
  static Widget emptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppInsets.xl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: AppSpacing.lg),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // AppDialog — диалог
  // =========================================================================

  /// Показывает стандартный диалог приложения.
  ///
  /// Кнопки в [actions] получают `context` вызывающего кода. Это ловушка:
  /// `Navigator.of(context)` в таком callback закрывает не dialog, а
  /// маршрут под ним (например, экран, открывший диалог). Для кнопок,
  /// которые сами закрывают диалог, используйте [actionsBuilder] — он
  /// выполняется внутри builder'а [showDialog] и получает именно тот
  /// `BuildContext`, который принадлежит dialog route.
  static Future<T?> showAppDialog<T>({
    required BuildContext context,
    required Widget title,
    required Widget content,
    List<Widget>? actions,
    List<Widget> Function(BuildContext dialogContext)? actionsBuilder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => AlertDialog(
        title: title,
        content: content,
        actions: actionsBuilder != null
            ? actionsBuilder(dialogContext)
            : actions,
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: EdgeInsets.only(
          right: AppSpacing.md,
          bottom: AppSpacing.md,
        ),
      ),
    );
  }

  // =========================================================================
  // AppBottomSheet — bottom sheet
  // =========================================================================
  static Future<T?> showBottomSheet<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool isScrollControlled = true,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Padding(
                padding: AppInsets.md,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Loading / Error states
  // =========================================================================

  static Widget errorState({
    required BuildContext context,
    required String message,
    VoidCallback? onRetry,
    String retryLabel = 'Повторить',
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppInsets.xl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: onRetry,
                child: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void showSnackBar({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
    Color? backgroundColor,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        backgroundColor: backgroundColor,
      ),
    );
  }

  // =========================================================================
  // Hero — главный экранный блок (primary wash, no card)
  // =========================================================================
  static Widget hero({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? backgroundColor,
    BorderRadius? borderRadius,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: padding ?? AppInsets.space8,
      decoration: BoxDecoration(
        color: backgroundColor ?? (isDark
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.12)),
        borderRadius: borderRadius ?? AppRadii.heroTop(context),
      ),
      child: child,
    );
  }

  // =========================================================================
  // FeatureCard — интерактивный блок для модулей (без цветной левой полосы)
  // =========================================================================
  static Widget featureCard({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? accentColor,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentColor ?? AppColors.getModuleAccent('default');
    
    return AnimatedContainer(
      duration: AppAnimations.getDuration(context, AppSpacing.durationStandard),
      curve: Curves.easeInOut,
      padding: padding ?? AppInsets.cardPaddingMedium,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadii.featureCard(context),
        border: Border.all(
          color: selected
              ? accent
              : (onTap != null
                  ? theme.colorScheme.outlineVariant
                  : Colors.transparent),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.15 : 0.1),
            blurRadius: selected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.featureCard(context),
        child: child,
      ),
    );
  }

  // =========================================================================
  // InteractiveTile — общий интерактивный тайл (surface + shadow, без border)
  // =========================================================================
  static Widget interactiveTile({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return AnimatedContainer(
      duration: AppAnimations.getDuration(context, AppSpacing.durationStandard),
      curve: Curves.easeInOut,
      padding: padding ?? AppInsets.cardPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: borderRadius ?? AppRadii.md,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.15 : 0.1),
            blurRadius: selected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? AppRadii.md,
        child: child,
      ),
    );
  }

  // =========================================================================
  // InlinePanel — плоский контейнер с border для метаданных
  // =========================================================================
  static Widget inlinePanel({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      padding: padding ?? AppInsets.cardPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius ?? AppRadii.md,
        border: Border.all(
          color: theme.colorScheme.outline,
          width: AppBorders.thin,
        ),
      ),
      child: child,
    );
  }

  // =========================================================================
  // OutlineSurface — bordered surface для настроек/фильтров
  // =========================================================================
  static Widget outlineSurface({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    bool focused = false,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: padding ?? AppInsets.cardPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: borderRadius ?? AppRadii.md,
        border: Border.all(
          color: focused
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: focused ? AppBorders.medium : AppBorders.thin,
        ),
      ),
      child: child,
    );
  }

  // =========================================================================
  // Chip — общий чип
  // =========================================================================
  static Widget chip({
    required BuildContext context,
    required String label,
    IconData? leadingIcon,
    VoidCallback? onTap,
    VoidCallback? onDeleted,
    Color? backgroundColor,
    Color? textColor,
    bool selected = false,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.full,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: backgroundColor ?? (selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest),
          borderRadius: AppRadii.full,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? AppBorders.medium : AppBorders.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 16, color: textColor ?? theme.colorScheme.onSurfaceVariant),
              SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: AppTypography.chipLabel.copyWith(
                color: textColor ?? (selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (onDeleted != null) ...[
              SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: onDeleted,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: textColor ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // AppListItem — элемент списка (inline, no card)
  // =========================================================================
  static Widget listItem({
    required BuildContext context,
    required Widget title,
    Widget? subtitle,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
    bool selected = false,
    bool divider = true,
  }) {
    final theme = Theme.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: AppInsets.listItemPadding,
            child: Row(
              children: [
                if (leading != null) ...[
                  leading,
                  SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
        if (divider)
          Divider(
            height: 1,
            thickness: AppBorders.hairline,
            color: theme.colorScheme.outlineVariant,
            indent: leading != null ? 72 : 16,
          ),
      ],
    );
  }

  // =========================================================================
  // LoadingIndicator — с ограничением высоты
  // =========================================================================
  static Widget loadingIndicator({
    Color? color,
    double size = 24,
    double? maxHeight,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight ?? double.infinity,
          maxWidth: double.infinity,
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: color != null
                ? AlwaysStoppedAnimation<Color>(color)
                : null,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // ErrorState / Dialog / BottomSheet / SnackBar — используют ThemeData
  // =========================================================================
  // (уже реализованы выше: errorState, showAppDialog, showBottomSheet, showSnackBar)
}