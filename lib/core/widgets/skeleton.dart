import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Placeholder shapes shown while a screen's first load is in flight, in
/// place of a bare spinner. Each shape is a solid block; [Skeleton] paints the
/// shimmer over all of them at once.

/// Shimmer over [child]. Still when the system asks for reduced motion.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceElevated,
      highlightColor: AppColors.surfaceHighest,
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: child,
    );
  }
}

/// A single block. Pass [circle] for an avatar.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.circle = false,
  });

  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Any opaque colour: the shimmer replaces it.
        color: AppColors.surfaceElevated,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// A round avatar placeholder of [size] points.
class SkeletonAvatar extends StatelessWidget {
  const SkeletonAvatar({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Skeleton(child: SkeletonBox(width: size, height: size, circle: true));
}

/// One list row: avatar and two lines of text.
class _SkeletonRowShape extends StatelessWidget {
  const _SkeletonRowShape({this.avatarSize = 56});

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SkeletonBox(width: avatarSize, height: avatarSize, circle: true),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FractionallySizedBox(
                widthFactor: 0.55,
                child: SkeletonBox(height: 14),
              ),
              SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: 0.85,
                child: SkeletonBox(height: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single list row placeholder.
class SkeletonListRow extends StatelessWidget {
  const SkeletonListRow({super.key, this.avatarSize = 56});

  final double avatarSize;

  @override
  Widget build(BuildContext context) =>
      Skeleton(child: _SkeletonRowShape(avatarSize: avatarSize));
}

/// A non-scrolling column of list rows, sized to the space it is given.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.rows = 7,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 0),
    this.spacing = 20,
    this.avatarSize = 56,
  });

  final int rows;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) SizedBox(height: spacing),
              _SkeletonRowShape(avatarSize: avatarSize),
            ],
          ],
        ),
      ),
    );
  }
}

/// The Discover card placeholder: a full card with name and meta lines.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.radius = 28});

  final double radius;

  @override
  Widget build(BuildContext context) {
    // The card itself is a still, darker panel; the photo area and text lines
    // shimmer on it. (Shimmer paints every opaque pixel, so a shape cut out
    // of a shimmering card would shimmer too.)
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.surfaceElevated),
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Skeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(child: SkeletonBox(width: 96, height: 96, circle: true)),
              ),
              FractionallySizedBox(
                widthFactor: 0.5,
                child: SkeletonBox(height: 22),
              ),
              SizedBox(height: 10),
              FractionallySizedBox(
                widthFactor: 0.7,
                child: SkeletonBox(height: 12),
              ),
              SizedBox(height: 16),
              SkeletonBox(width: double.infinity, height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// A profile page placeholder: a tall photo (or, with [roundAvatar], a
/// centred avatar), a title and a few text lines.
class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({
    super.key,
    this.headerHeight = 360,
    this.roundAvatar = false,
  });

  final double headerHeight;
  final bool roundAvatar;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (roundAvatar)
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 40,
                ),
                child: const Center(
                  child: SkeletonBox(width: 116, height: 116, circle: true),
                ),
              )
            else
              SkeletonBox(
                width: double.infinity,
                height: headerHeight,
                radius: 0,
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.55,
                    child: SkeletonBox(height: 26),
                  ),
                  SizedBox(height: 12),
                  FractionallySizedBox(
                    widthFactor: 0.4,
                    child: SkeletonBox(height: 14),
                  ),
                  SizedBox(height: 28),
                  SkeletonBox(width: double.infinity, height: 90, radius: 16),
                  SizedBox(height: 16),
                  SkeletonBox(width: double.infinity, height: 90, radius: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat bubbles, alternating sides, newest at the bottom.
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key, this.bubbles = 8});

  final int bubbles;

  static const _widths = [0.55, 0.4, 0.65, 0.35, 0.5, 0.6, 0.3, 0.45];

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            for (var i = 0; i < bubbles; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: i.isEven
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: _widths[i % _widths.length],
                    child: const SkeletonBox(height: 40, radius: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
