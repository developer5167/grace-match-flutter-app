import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// Physical pixels for something drawn [logical] points wide. Network images
/// are decoded at this size instead of the original's (often 3000px+), which
/// is most of their memory and decode time.
int decodePx(BuildContext context, double logical) =>
    (logical * MediaQuery.devicePixelRatioOf(context)).round();

/// Decode width for a [BoxFit.cover] image in a [width] x [height] box.
///
/// Uses the longer side so a landscape photo in a tall box is not decoded
/// narrower than the height it gets scaled to. Never upscales: the image
/// cache clamps to the source size.
int coverDecodePx(BuildContext context, double width, double height) =>
    decodePx(context, math.max(width, height));

/// A network avatar decoded at the size it is drawn ([logicalSize] points).
ImageProvider avatarImage(
  BuildContext context,
  String url,
  double logicalSize,
) => ResizeImage(
  CachedNetworkImageProvider(url),
  width: decodePx(context, logicalSize),
  policy: ResizeImagePolicy.fit,
);

/// The 200px thumbnail at [thumbKey] when the server sent one, otherwise the
/// original at [key]. Null and empty strings both count as missing.
String? thumbOr(Map<dynamic, dynamic> m, String thumbKey, String key) {
  final thumb = m[thumbKey]?.toString();
  if (thumb != null && thumb.isNotEmpty) return thumb;
  final original = m[key]?.toString();
  if (original != null && original.isNotEmpty) return original;
  return null;
}
