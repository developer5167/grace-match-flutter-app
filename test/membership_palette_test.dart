import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/theme/app_colors.dart';
import 'package:grace_match/core/theme/membership_palette.dart';

void main() {
  tearDown(() {
    MembershipTheme.instance.reset();
  });

  test('unknown and bronze keep the house gold', () {
    expect(MembershipPalette.parse(null), MembershipTier.bronze);
    expect(MembershipPalette.parse('bronze'), MembershipTier.bronze);
    expect(MembershipPalette.bronze.metal, const Color(0xFFC9A96E));
    expect(AppColors.gold, MembershipPalette.bronze.metal);
  });

  test('each paid plan has its own metal, still on the same dark on-metal', () {
    expect(MembershipPalette.of('silver').metal, isNot(MembershipPalette.bronze.metal));
    expect(MembershipPalette.of('gold').metal, isNot(MembershipPalette.bronze.metal));
    expect(MembershipPalette.of('platinum').metal, isNot(MembershipPalette.of('silver').metal));
    expect(MembershipPalette.of('GOLD').tier, MembershipTier.gold);
    for (final p in [
      MembershipPalette.bronze,
      MembershipPalette.silver,
      MembershipPalette.gold,
      MembershipPalette.platinum,
    ]) {
      expect(p.onMetal, const Color(0xFF0A0A0F));
      expect(p.gradient.colors.length, greaterThanOrEqualTo(2));
    }
  });

  test('applying a plan recolors AppColors.gold', () {
    MembershipTheme.instance.apply('platinum', persist: false);
    expect(AppColors.gold, MembershipPalette.platinum.metal);
    expect(AppColors.goldLight, MembershipPalette.platinum.metalLight);
    MembershipTheme.instance.applyFrom({'plan_name': 'silver'}, persist: false);
    expect(AppColors.gold, MembershipPalette.silver.metal);
  });
}
