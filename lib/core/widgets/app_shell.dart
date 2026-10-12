import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_haptics.dart';

/// Main bottom navigation shell — premium frosted glass style
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int get _selectedIndex {
    try {
      final location = GoRouterState.of(context).uri.path;
      if (location.startsWith('/discover')) return 0;
      if (location.startsWith('/interests')) return 1;
      if (location.startsWith('/chat')) return 2;
      if (location.startsWith('/activity')) return 3;
      if (location.startsWith('/profile')) return 4;
    } catch (_) {}
    return 0;
  }

  static const _tabs = [
    _NavTab(path: '/discover', icon: Icons.explore_rounded, label: 'Discover'),
    _NavTab(path: '/interests', icon: Icons.favorite_rounded, label: 'Interests'),
    _NavTab(path: '/chat', icon: Icons.chat_bubble_rounded, label: 'Chat'),
    _NavTab(path: '/activity', icon: Icons.notifications_rounded, label: 'Activity'),
    _NavTab(path: '/profile', icon: Icons.person_rounded, label: 'Profile'),
  ];

  void _onTabSelected(int index) {
    if (_selectedIndex == index) return;
    AppHaptics.selection();
    context.go(_tabs[index].path);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _onTabSelected(0);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: widget.child,
        bottomNavigationBar: _PremiumNavBar(
          selectedIndex: _selectedIndex,
          tabs: _tabs,
          onTabSelected: _onTabSelected,
        ),
      ),
    );
  }
}

class _NavTab {
  final String path;
  final IconData icon;
  final String label;
  const _NavTab({required this.path, required this.icon, required this.label});
}

class _PremiumNavBar extends StatelessWidget {
  final int selectedIndex;
  final List<_NavTab> tabs;
  final ValueChanged<int> onTabSelected;

  const _PremiumNavBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withAlpha(230),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.goldMild, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withAlpha(28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isSelected = i == selectedIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTabSelected(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey(isSelected),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.elasticOut,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: isSelected ? AppColors.goldenGradient : null,
                            color: isSelected ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            tabs[i].icon,
                            color: isSelected
                                ? AppColors.textOnGold
                                : AppColors.textTertiary,
                            size: isSelected ? 24 : 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: isSelected
                              ? AppTextStyles.labelSmall
                                  .copyWith(color: AppColors.gold)
                              : AppTextStyles.labelSmall,
                          child: Text(tabs[i].label),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
