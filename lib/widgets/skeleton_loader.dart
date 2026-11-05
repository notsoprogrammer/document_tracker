import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmering placeholder block. Use to build up skeleton layouts that
/// mirror the real content's shape (a bar for text, a circle for an icon).
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: borderRadius == null && width == height
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: borderRadius ??
            (width == height ? null : BorderRadius.circular(6)),
      ),
    );
  }
}

/// Wraps skeleton content in a shimmer sweep. Wrap one of these around a
/// whole list/section rather than each row, so the sweep animates in sync.
class ShimmerWrap extends StatelessWidget {
  final Widget child;

  const ShimmerWrap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: child,
    );
  }
}

/// Skeleton placeholder for a single document list row (matches the
/// leading-icon + title + subtitle shape used across the document screens).
class DocumentRowSkeleton extends StatelessWidget {
  const DocumentRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox.circle(size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 13, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                SkeletonBox(width: double.infinity, height: 11, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                SkeletonBox(width: 90, height: 18, borderRadius: BorderRadius.circular(4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-list skeleton: a shimmering stack of [DocumentRowSkeleton]s with
/// dividers, matching the real ListView.separated used by the document
/// screens. Drop this in wherever a screen currently shows a
/// CircularProgressIndicator while its document list loads.
class DocumentListSkeleton extends StatelessWidget {
  final int itemCount;

  const DocumentListSkeleton({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 4),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
        itemBuilder: (_, _) => const DocumentRowSkeleton(),
      ),
    );
  }
}
