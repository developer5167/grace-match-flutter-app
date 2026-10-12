import 'package:flutter/material.dart';

/// Membership metal. Bronze is the house look (the current GraceMatch gold).
/// Paid tiers stay on the same charcoal ground and only change the metal.
enum MembershipTier { bronze, silver, gold, platinum }

class MembershipPalette {
  const MembershipPalette({
    required this.tier,
    required this.label,
    required this.metal,
    required this.metalLight,
    required this.metalDark,
    required this.onMetal,
    required this.gradient,
    required this.glow,
    required this.cardBorder,
  });

  final MembershipTier tier;
  final String label;
  final Color metal;
  final Color metalLight;
  final Color metalDark;
  final Color onMetal;
  final LinearGradient gradient;
  final RadialGradient glow;
  final LinearGradient cardBorder;

  Color get subtle => metal.withAlpha(0x33);
  Color get mild => metal.withAlpha(0x66);

  static MembershipTier parse(String? name) {
    switch ((name ?? '').trim().toLowerCase()) {
      case 'silver':
        return MembershipTier.silver;
      case 'gold':
        return MembershipTier.gold;
      case 'platinum':
        return MembershipTier.platinum;
      default:
        return MembershipTier.bronze;
    }
  }

  static MembershipPalette of(String? name) => forTier(parse(name));

  static MembershipPalette forTier(MembershipTier tier) {
    switch (tier) {
      case MembershipTier.bronze:
        return bronze;
      case MembershipTier.silver:
        return silver;
      case MembershipTier.gold:
        return gold;
      case MembershipTier.platinum:
        return platinum;
    }
  }

  /// Current live theme — antique warm gold on charcoal.
  static const bronze = MembershipPalette(
    tier: MembershipTier.bronze,
    label: 'Bronze',
    metal: Color(0xFFC9A96E),
    metalLight: Color(0xFFDFC08A),
    metalDark: Color(0xFF9E7A47),
    onMetal: Color(0xFF0A0A0F),
    gradient: LinearGradient(
      colors: [Color(0xFFC9A96E), Color(0xFFE8C98A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glow: RadialGradient(
      colors: [Color(0x40C9A96E), Color(0x00000000)],
      radius: 0.8,
    ),
    cardBorder: LinearGradient(
      colors: [Color(0x80C9A96E), Color(0x20C9A96E), Color(0x00C9A96E)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Cool argent with a whisper of the house gold so it still belongs here.
  static const silver = MembershipPalette(
    tier: MembershipTier.silver,
    label: 'Silver',
    metal: Color(0xFFC5CCD6),
    metalLight: Color(0xFFE8EEF4),
    metalDark: Color(0xFF8A93A3),
    onMetal: Color(0xFF0A0A0F),
    gradient: LinearGradient(
      colors: [Color(0xFF8A93A3), Color(0xFFE8EEF4), Color(0xFFC5CCD6)],
      stops: [0.0, 0.48, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glow: RadialGradient(
      colors: [Color(0x40C5CCD6), Color(0x00000000)],
      radius: 0.8,
    ),
    cardBorder: LinearGradient(
      colors: [Color(0x80C5CCD6), Color(0x20C5CCD6), Color(0x00C5CCD6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Brighter jewelry gold — same family as bronze, more luminous.
  static const gold = MembershipPalette(
    tier: MembershipTier.gold,
    label: 'Gold',
    metal: Color(0xFFE0B85C),
    metalLight: Color(0xFFF5D98A),
    metalDark: Color(0xFFB8892E),
    onMetal: Color(0xFF0A0A0F),
    gradient: LinearGradient(
      colors: [Color(0xFFB8892E), Color(0xFFF5D98A), Color(0xFFE0B85C)],
      stops: [0.0, 0.48, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glow: RadialGradient(
      colors: [Color(0x40E0B85C), Color(0x00000000)],
      radius: 0.8,
    ),
    cardBorder: LinearGradient(
      colors: [Color(0x80E0B85C), Color(0x20E0B85C), Color(0x00E0B85C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  /// Pearl white-metal with a champagne highlight.
  static const platinum = MembershipPalette(
    tier: MembershipTier.platinum,
    label: 'Platinum',
    metal: Color(0xFFD9D4C8),
    metalLight: Color(0xFFF4F1EA),
    metalDark: Color(0xFF9C9588),
    onMetal: Color(0xFF0A0A0F),
    gradient: LinearGradient(
      colors: [Color(0xFF9C9588), Color(0xFFF4F1EA), Color(0xFFD9D4C8)],
      stops: [0.0, 0.48, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    glow: RadialGradient(
      colors: [Color(0x40D9D4C8), Color(0x00000000)],
      radius: 0.8,
    ),
    cardBorder: LinearGradient(
      colors: [Color(0x80D9D4C8), Color(0x20D9D4C8), Color(0x00D9D4C8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

/// Live membership look. Screens read through [AppColors.gold] getters, so
/// the existing UI recolors when [apply] runs.
class MembershipTheme extends ChangeNotifier {
  MembershipTheme._();
  static final MembershipTheme instance = MembershipTheme._();

  MembershipPalette _palette = MembershipPalette.bronze;
  MembershipPalette get palette => _palette;
  MembershipTier get tier => _palette.tier;

  static MembershipPalette get colors => instance._palette;

  void apply(String? planName, {bool persist = true}) {
    final next = MembershipPalette.of(planName);
    if (next.tier == _palette.tier) return;
    _palette = next;
    notifyListeners();
    if (persist) _persist?.call(next.tier.name);
  }

  void applyFrom(dynamic subscription, {bool persist = true}) {
    if (subscription is Map) {
      apply(subscription['plan_name']?.toString(), persist: persist);
      return;
    }
    apply('bronze', persist: persist);
  }

  void reset() {
    apply('bronze');
  }

  /// Optional persist hook so this file does not import Hive.
  static void Function(String planName)? _persist;

  static void bindPersist(void Function(String planName) save) {
    _persist = save;
  }

  static void restore(String? planName) {
    instance.apply(planName, persist: false);
  }
}
