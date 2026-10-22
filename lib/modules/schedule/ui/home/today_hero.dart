import 'package:flutter/material.dart';
import '../../../../core/design/design_system.dart';
import '../../models/schedule_event.dart';
import '../../schedule_repository.dart';

/// Today Hero — показывает живое состояние дня в реальном времени.
///
/// Состояния:
/// - Сейчас идёт событие → «ИДЁТ СЕЙЧАС»
/// - Есть свободное окно → «СВОБОДНО • осталось XX мин»
/// - День завершён → «ВСЕ ДЕЛА ЗАВЕРШЕНЫ»
class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.events,
    required this.daySummary,
    required this.onNavigateToSchedule,
  });

  final List<ScheduleEvent> events;
  final ScheduleDaySummary daySummary;
  final VoidCallback onNavigateToSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    // Находим текущее событие
    ScheduleEvent? currentEvent;
    for (final event in events) {
      if (event.startMinutes <= currentMinutes && event.endMinutes > currentMinutes) {
        currentEvent = event;
        break;
      }
    }

    // Находим ближайшее будущее событие
    ScheduleEvent? nextEvent;
    for (final event in events) {
      if (event.startMinutes > currentMinutes) {
        nextEvent = event;
        break;
      }
    }

    String statusTitle;
    String statusSubtitle;
    Color statusColor;
    IconData statusIcon;

    if (currentEvent != null) {
      // Сейчас идёт событие
      final remaining = currentEvent.endMinutes - currentMinutes;
      statusTitle = 'Идёт сейчас';
      statusSubtitle = 'Осталось ${_formatMinutes(remaining)} до конца';
      statusColor = theme.colorScheme.error;
      statusIcon = Icons.play_circle_filled;
    } else if (nextEvent != null) {
      // Есть свободное окно до следующего события
      final freeMinutes = nextEvent.startMinutes - currentMinutes;
      statusTitle = 'Свободно';
      statusSubtitle = 'До следующего дела ${_formatMinutes(freeMinutes)}';
      statusColor = theme.colorScheme.tertiary;
      statusIcon = Icons.pause_circle_filled;
    } else if (events.isNotEmpty) {
      // День завершён
      statusTitle = 'Все дела завершены';
      statusSubtitle = 'Хороший отдых!';
      statusColor = theme.colorScheme.outline;
      statusIcon = Icons.check_circle_outline;
    } else {
      // Пустой день
      statusTitle = 'Свободный день';
      statusSubtitle = 'Ничего не запланировано';
      statusColor = theme.colorScheme.outline;
      statusIcon = Icons.event_available_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadii.featureCard(context),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        // Боковые отступы — адаптивный стандарт экрана (Stage 11): было
        // 32 со всех сторон, поэтому Главная была вдвое шире остальных
        // экранов. Верх/низ остаются 32: это внутренний воздух
        // hero-блока, а не отступ от края экрана.
        padding: EdgeInsets.only(
          top: AppSpacing.space7,
          bottom: AppSpacing.space7,
          left: AppInsets.screen(context).left,
          right: AppInsets.screen(context).right,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Дата
            Text(
              _formatDate(now),
              style: theme.textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: AppSpacing.space3),
            // Статус дня. Wrap, а не Row: подписи теперь в обычном
            // регистре и длиннее, чем были капсом («Все дела завершены»),
            // и жёсткий Row сжимал чип до «ВСЕ ДЕЛ…» или ронял overflow.
            // Здесь чип занимает свою ширину, а подпись переносится
            // ниже, если ширины не хватает.
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(
                  title: statusTitle,
                  color: statusColor,
                  icon: statusIcon,
                ),
                Text(
                  statusSubtitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            SizedBox(height: AppSpacing.space4),
            // Метрики дня — один ряд из трёх равных карточек.
            //
            // Показываем только когда есть хотя бы одно событие.
            // Без событий метрики показывали бы нули («0 мин», «24 ч», «0»),
            // что выглядит как пустые карточки.
            //
            // Без IntrinsicHeight и без stretch по высоте: карточки живут
            // внутри ListView (бесконечная высота), а «равная высота»
            // через такой механизм уже роняла раскладку с «BoxConstraints
            // forces an infinite height». Высота теперь определяется
            // содержимым: значения одной длины, поэтому карточки совпадают,
            // и ряд остаётся ровным.
            //
            // Зазор 10 dp: в шкале [AppSpacing] нет токена на 10 (space2=8,
            // space3=12), поэтому он задан литералом с этой пометкой.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MetricChip(
                    label: 'Занято',
                    value: events.isEmpty ? '—' : _formatDuration(daySummary.totalBusy),
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricChip(
                    label: 'Свободно',
                    value: events.isEmpty ? '—' : _formatDuration(daySummary.totalFree),
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricChip(
                    label: 'Событий',
                    value: events.isEmpty ? '0' : events.length.toString(),
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.space4),
            // CTA к расписанию: на всю ширину контента, высота 48 dp,
            // иконка и текст по центру.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: AppComponents.filledButton(
                onPressed: onNavigateToSchedule,
                leadingIcon: Icons.chevron_right,
                child: const Text('Открыть расписание'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0) return '${minutes} мин';
    if (minutes == 0) return '$hours ч';
    return '$hours ч $minutes мин';
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes мин';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours ч';
    return '$hours ч $mins мин';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.title,
    required this.color,
    required this.icon,
  });

  final String title;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadiiValues.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: AppSpacing.xs),
          // Обычный регистр, полный текст, прижатый к иконке: чип сам
          // занимает столько, сколько нужно, и не режет подпись.
          //
          // Ограничение по ширине обязательно: `mainAxisSize: min` внутри
          // чипа при длинном заголовке даёт неограниченную ширину, и
          // Row переполняется на 98 px. `Flexible` + ellipsis сохраняют
          // поведение «не режет, пока хватает места» и убирают overflow.
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Внутренние отступы задаёт САМА карточка, своим параметром padding.
    //
    // Раньше здесь был ещё и свой `Padding` внутри child — итого
    // 20 (padding по умолчанию у featureCard) + 16 + 16 = 52 dp пустоты
    // вокруг двух строк. На карточке шириной ~100 dp под текст оставалось
    // ~28 dp, и подписи («Занято», «Свободно», «Событий») схлопывались в
    // ширину 0 — текст в блоках на «Главной» просто исчезал.
    //
    // Значение сверху (headlineSmall/bold), подпись снизу (labelMedium);
    // обе строки — по одной строке, значение ещё и через FittedBox, чтобы
    // «12 ч 30 мин» на 360 dp умещался масштабированием, а не обрезкой.
    return AppComponents.featureCard(
      context: context,
      accentColor: color,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 1,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}