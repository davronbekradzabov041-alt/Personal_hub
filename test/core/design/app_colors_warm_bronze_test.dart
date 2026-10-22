/// Тесты палитры Warm Bronze / Raw Tactile (Stage 11).
///
/// Фиксируют согласованные цвета как контракт: значения проверяются
/// по ARGB, а контраст — по коэффициенту WCAG. Без этого дизайн
/// «поплыл» бы при случайной правке токенов, и никто бы не заметил,
/// пока пользователь не пожалуется на нечитаемый текст.
library app_colors_warm_bronze_test;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_hub/core/design/app_colors.dart';

/// Относительная яркость по WCAG 2.1.
double _luminance(Color color) {
  double channel(double value) {
    final c = value / 255.0;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = channel(color.r * 255);
  final g = channel(color.g * 255);
  final b = channel(color.b * 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Коэффициент контраста WCAG между двумя цветами.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Тёмная тема — Warm Bronze / Raw Tactile', () {
    const dark = AppColors.darkColorScheme;

    test('фон и поверхности соответствуют спецификации', () {
      expect(AppColors.canvasDark, const Color(0xFF0E0E0E));
      expect(AppColors.surfaceBaseDark, const Color(0xFF181716));
      expect(AppColors.surfaceElevatedDark, const Color(0xFF21201D));
      expect(AppColors.textPrimaryDark, const Color(0xFFF4F2ED));
      expect(dark.primary, const Color(0xFFD89B51));
    });

    test('поверхности образуют ступень по яркости', () {
      // Фон темнее базовой поверхности, та темнее приподнятой:
      // иначе ступеньей не будет и UI станет плоским.
      expect(
        _luminance(AppColors.canvasDark),
        lessThan(_luminance(AppColors.surfaceBaseDark)),
      );
      expect(
        _luminance(AppColors.surfaceBaseDark),
        lessThan(_luminance(AppColors.surfaceElevatedDark)),
      );
    });

    test('ColorScheme использует те же токены', () {
      expect(dark.brightness, Brightness.dark);
      expect(dark.surface, AppColors.surfaceBaseDark);
      expect(dark.surfaceContainerHighest, AppColors.surfaceElevatedDark);
      expect(dark.onSurface, AppColors.textPrimaryDark);
    });

    test('контраст основного текста на фоне — не ниже 4.5:1', () {
      expect(
        _contrast(dark.onSurface, AppColors.canvasDark),
        greaterThanOrEqualTo(4.5),
        reason: 'основной текст должен читаться на фоне',
      );
      expect(
        _contrast(dark.onSurface, AppColors.surfaceBaseDark),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.onSurface, AppColors.surfaceElevatedDark),
        greaterThanOrEqualTo(4.5),
        reason: 'и на приподнятой поверхности карточек',
      );
    });

    test('контраст вторичного текста — не ниже 3:1', () {
      expect(
        _contrast(dark.onSurfaceVariant, AppColors.surfaceElevatedDark),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('контраст текста на бронзовой кнопке — не ниже 4.5:1', () {
      expect(
        _contrast(dark.onPrimary, dark.primary),
        greaterThanOrEqualTo(4.5),
        reason: 'текст на бронзовой заливке должен читаться',
      );
    });

    test('бронзовый акцент различим на фоне и поверхностях', () {
      for (final background in <Color>[
        AppColors.canvasDark,
        AppColors.surfaceBaseDark,
        AppColors.surfaceElevatedDark,
      ]) {
        expect(
          _contrast(dark.primary, background),
          greaterThanOrEqualTo(3.0),
          reason: 'акцент должен быть виден как выделение/рамка',
        );
      }
    });

    test('нет неоновых цветов: насыщенность бронзы умеренная', () {
      // «Неон» = очень высокая относительная яркость акцента или
      // близкая к 1.0 насыщенность. Бронза #D89B51 — тёплый, матовый.
      expect(_luminance(dark.primary), lessThan(0.45));
      expect(_luminance(dark.primary), greaterThan(0.20));
    });
  });

  group('Светлая тема — тёплый холст', () {
    const light = AppColors.lightColorScheme;

    test('контраст основного текста — не ниже 4.5:1', () {
      expect(
        _contrast(light.onSurface, AppColors.canvasLight),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(light.onSurface, AppColors.surfaceBaseLight),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(light.onSurface, AppColors.surfaceElevatedLight),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('текст на затемнённой бронзовой кнопке читается', () {
      expect(
        _contrast(light.onPrimary, light.primary),
        greaterThanOrEqualTo(4.5),
        reason: 'в светлой теме primary затемнён именно ради белого текста',
      );
    });

    test('акцент виден на светлых поверхностях', () {
      expect(
        _contrast(light.primary, AppColors.canvasLight),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('Акценты модулей', () {
    test('все акценты — тёплые, без холодных «v2» значений', () {
      // Прежняя палитра v2: #D97706, #0D9488, #475569, #059669, #E11D48,
      // #7C3AED, #2563EB. Ни один из этих цветов акцентом быть не должен.
      final retired = <int>{
        0xFFD97706,
        0xFF0D9488,
        0xFF475569,
        0xFF059669,
        0xFFE11D48,
        0xFF7C3AED,
        0xFF2563EB,
      };
      for (final accent in AppColors.curatedAccents) {
        final argb = accent.toARGB32();
        expect(retired.contains(argb), isFalse,
            reason: 'акцент ${argb.toRadixString(16)} '
                'из палитры v2 не должен использоваться');
      }
    });

    test('schedule и accounts получают бронзовые акценты', () {
      final schedule = AppColors.getModuleAccent('schedule');
      final accounts = AppColors.getModuleAccent('accounts');
      expect(schedule, const Color(0xFFD89B51));
      expect(accounts, const Color(0xFFB7AE9E));
    });

    test('неизвестный модуль получает бронзовый fallback', () {
      expect(AppColors.getModuleAccent('unknown'), const Color(0xFFD89B51));
    });
  });
}
