import '../constants/app_constants.dart';
import '../network/dio_client.dart';
import 'membership_palette.dart';

/// Pulls the live plan from bootstrap and recolors the app.
Future<void> syncMembershipTheme() async {
  try {
    final resp = await DioClient.instance.get(ApiEndpoints.appBootstrap);
    final data = resp.data['data'];
    if (data is Map) {
      MembershipTheme.instance.applyFrom(data['subscription']);
    }
  } catch (_) {
    // Palette stays at the last known plan. Launch must not fail on this.
  }
}
