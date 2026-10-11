import '../../../core/constants/app_constants.dart';
import '../../../core/network/dio_client.dart';

class ReviewActionItem {
  final String? id;
  final String actionType;
  final String status;
  final String title;
  final String hint;
  final String route;
  final String source;

  const ReviewActionItem({
    required this.id,
    required this.actionType,
    required this.status,
    required this.title,
    required this.hint,
    required this.route,
    required this.source,
  });

  bool get isOpen => status == 'open';

  factory ReviewActionItem.fromJson(Map<String, dynamic> j) => ReviewActionItem(
        id: j['id']?.toString(),
        actionType: j['action_type']?.toString() ?? '',
        status: j['status']?.toString() ?? 'open',
        title: j['title']?.toString() ?? 'Update needed',
        hint: j['hint']?.toString() ?? '',
        route: j['route']?.toString() ?? '/onboarding',
        source: j['source']?.toString() ?? 'requested',
      );
}

class ReviewInbox {
  final String? reviewStatus;
  final String? reviewNote;
  final List<ReviewActionItem> actions;
  final bool resubmitted;
  final int photoCount;

  const ReviewInbox({
    required this.reviewStatus,
    required this.reviewNote,
    required this.actions,
    this.resubmitted = false,
    this.photoCount = 0,
  });

  List<ReviewActionItem> get open => actions.where((a) => a.isOpen).toList();

  factory ReviewInbox.fromJson(Map<String, dynamic> j) => ReviewInbox(
        reviewStatus: j['review_status']?.toString(),
        reviewNote: j['review_note']?.toString(),
        actions: (j['actions'] as List? ?? [])
            .whereType<Map>()
            .map((e) => ReviewActionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        resubmitted: j['resubmitted'] == true,
        photoCount: (j['photo_count'] as num?)?.toInt() ??
            (j['usable_photos'] as num?)?.toInt() ??
            0,
      );
}

class ReviewRepository {
  final _dio = DioClient.instance;

  Future<ReviewInbox> fetch() async {
    final res = await _dio.get(ApiEndpoints.reviewActions);
    return ReviewInbox.fromJson(
      Map<String, dynamic>.from(res.data['data'] ?? {}),
    );
  }

  Future<ReviewInbox> submit(String actionType) async {
    final res = await _dio.post(
      ApiEndpoints.reviewSubmit,
      data: {'action_type': actionType},
    );
    return ReviewInbox.fromJson(
      Map<String, dynamic>.from(res.data['data'] ?? {}),
    );
  }

  Future<ReviewInbox> submitAll() async {
    final res = await _dio.post(ApiEndpoints.reviewSubmitAll);
    return ReviewInbox.fromJson(
      Map<String, dynamic>.from(res.data['data'] ?? {}),
    );
  }

  String errorMessage(Object e) {
    try {
      final data = (e as dynamic).response?.data;
      if (data is Map && data['message'] != null) return data['message'].toString();
    } catch (_) {}
    return 'Could not send that back. Please try again.';
  }
}
