import 'package:dio/dio.dart';
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
    photoCount:
        (j['photo_count'] as num?)?.toInt() ??
        (j['usable_photos'] as num?)?.toInt() ??
        0,
  );
}

/// One section of the automatic profile check.
class VerifySection {
  final String key;
  final String title;
  final String status; // passed | failed | review | recommended
  final String? message;
  final List<({String field, String message})> issues;
  final String route;
  final bool optional;

  const VerifySection({
    required this.key,
    required this.title,
    required this.status,
    required this.message,
    required this.issues,
    required this.route,
    required this.optional,
  });

  factory VerifySection.fromJson(Map<String, dynamic> j) => VerifySection(
    key: j['key']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    status: j['status']?.toString() ?? 'review',
    message: j['message']?.toString(),
    issues: (j['issues'] as List? ?? [])
        .whereType<Map>()
        .map(
          (i) => (
            field: i['field']?.toString() ?? '',
            message: i['message']?.toString() ?? '',
          ),
        )
        .toList(),
    route: j['route']?.toString() ?? '/onboarding',
    optional: j['optional'] == true,
  );
}

class VerifyResult {
  final String reviewStatus;
  final bool approved;
  final List<VerifySection> sections;

  const VerifyResult({
    required this.reviewStatus,
    required this.approved,
    required this.sections,
  });

  factory VerifyResult.fromJson(Map<String, dynamic> j) => VerifyResult(
    reviewStatus: j['review_status']?.toString() ?? 'pending',
    approved: j['approved'] == true,
    sections: (j['sections'] as List? ?? [])
        .whereType<Map>()
        .map((e) => VerifySection.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class ReviewRepository {
  final _dio = DioClient.instance;

  /// Run the automatic checks now (only changed sections are checked again).
  Future<VerifyResult> verify() async {
    final res = await _dio.post(
      ApiEndpoints.reviewVerify,
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return VerifyResult.fromJson(
      Map<String, dynamic>.from(res.data['data'] ?? {}),
    );
  }

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
      if (data is Map && data['message'] != null)
        return data['message'].toString();
    } catch (_) {}
    return 'Could not send that back. Please try again.';
  }
}
