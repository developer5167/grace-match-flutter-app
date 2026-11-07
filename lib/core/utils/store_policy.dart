import 'package:flutter/foundation.dart';

/// App Store guideline 3.1.1: the iOS app may not sell plans, show their prices,
/// or point members to another place to buy them. Like Spotify, iOS only shows
/// the plan a member already has; buying happens on Android or the website.
bool get canSellPlansHere =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;
