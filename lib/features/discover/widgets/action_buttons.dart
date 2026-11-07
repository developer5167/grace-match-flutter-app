import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_haptics.dart';

class DiscoverActionButtons extends StatelessWidget {
  final VoidCallback? onPass;
  final VoidCallback? onInterest;
  final VoidCallback? onSuperInterest;

  const DiscoverActionButtons({
    super.key,
    this.onPass,
    this.onInterest,
    this.onSuperInterest,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child:
          Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pass button
                  _ActionButton(
                    icon: Icons.close_rounded,
                    color: AppColors.error,
                    size: 52,
                    onTap: onPass,
                  ),
                  const SizedBox(width: 16),

                  // Super Interest (star) — premium feature
                  _ActionButton(
                    icon: Icons.star_rounded,
                    color: AppColors.cross,
                    size: 44,
                    onTap: onSuperInterest,
                  ),
                  const SizedBox(width: 16),

                  // Interest / Like button
                  _ActionButton(
                    icon: Icons.favorite_rounded,
                    color: AppColors.blessing,
                    size: 52,
                    onTap: onInterest,
                  ),
                ],
              )
              .animate()
              .slideY(begin: 0.3, duration: 500.ms, curve: Curves.easeOutCubic)
              .fadeIn(),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (widget.onTap == null) return;
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = widget.size + 20;

    return GestureDetector(
      onTap: _onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceElevated,
            border: Border.all(color: widget.color.withAlpha(80), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha(40),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: widget.color,
            size: widget.size * 0.55,
          ),
        ),
      ),
    );
  }
}
