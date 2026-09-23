import 'package:flutter/material.dart';
import '../../core/design/design_system.dart';

/// Переиспользуемый виджет «пустого» экрана/раздела.
///
/// Используется главным экраном (пока нет модулей) и любыми
/// заглушками на будущее. Когда появятся реальные модули
/// (Этап 3), каждый модуль будет решать сам, что показывать
/// вместо этого виджета.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return AppComponents.emptyState(
      context: context,
      icon: icon,
      title: title,
      subtitle: subtitle,
      action: action,
    );
  }
}
