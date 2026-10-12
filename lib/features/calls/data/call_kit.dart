import 'package:dio/dio.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/app_storage.dart';

/// The phone's own call UI: the full-screen ringing screen on the lock screen,
/// the ringing notification with Accept and Decline, the ringtone, and the
/// "ongoing call" notification that keeps the call alive in the background.
///
/// Everything here is safe to call from a background isolate — the push
/// handler runs in one when the app is closed — so it touches secure storage
/// and plain Dio only, never Hive or the service locator.
class CallKit {
  CallKit._();

  /// The call data a push or socket event carries, normalised.
  static IncomingCallData? parse(Map<String, dynamic> data) {
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return null;
    final name = data['caller_name']?.toString();
    return IncomingCallData(
      callId: callId,
      conversationId: data['conversation_id']?.toString() ?? '',
      callerName: (name == null || name.isEmpty) ? 'Someone' : name,
      callerPhoto: data['caller_photo']?.toString() ?? '',
      isVideo: data['is_video']?.toString() != 'false' && data['is_video'] != false,
      shownAt: int.tryParse(data['ts']?.toString() ?? ''),
      outgoing: data['outgoing']?.toString() == 'true',
    );
  }

  static bool isIncoming(Map<String, dynamic> data) =>
      data['kind']?.toString() == 'incoming_call' || data['type']?.toString() == 'incoming_call';

  static bool isCancelled(Map<String, dynamic> data) =>
      data['kind']?.toString() == 'call_cancelled' || data['type']?.toString() == 'call_cancelled';

  static CallKitParams params(
    IncomingCallData call, {
    bool outgoing = false,
    bool ongoing = false,
  }) {
    final photo = call.callerPhoto.startsWith('http') ? call.callerPhoto : null;
    final status = outgoing ? 'Calling…' : 'Ongoing call';
    return CallKitParams(
      id: call.callId,
      nameCaller: call.callerName,
      appName: 'GraceMatch',
      avatar: photo,
      handle: ongoing
          ? status
          : (call.isVideo ? 'GraceMatch video call' : 'GraceMatch voice call'),
      type: call.isVideo ? 1 : 0,
      // Ringing times out with the server. An ongoing call must not.
      duration: ongoing ? 6 * 60 * 60 * 1000 : 50000,
      // The server sends the missed-call notification, with the chat to open.
      missedCallNotification: const NotificationParams(
        showNotification: false,
        isShowCallback: false,
      ),
      callingNotification: NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: status,
        callbackText: 'Hang up',
      ),
      extra: call.toMap(),
      android: AndroidParams(
        // CallStyle.forOngoingCall is dropped on Android 14 unless Telecom
        // owns the call. Incoming ringing still uses the custom CallStyle.
        isCustomNotification: !ongoing,
        isShowLogo: false,
        isShowCallID: ongoing,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0E0D12',
        backgroundUrl: photo,
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
        isShowFullLockedScreen: true,
        isImportant: true,
        textAccept: 'Accept',
        textDecline: 'Decline',
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        includesCallsInRecents: false,
        ringtonePath: 'system_ringtone_default',
        configureAudioSession: true,
        audioSessionMode: call.isVideo ? 'videoChat' : 'voiceChat',
      ),
    );
  }

  /// Ring, unless this call is already ringing — the socket and the push both
  /// announce every call, and a second show restarts the ringtone.
  static Future<void> ring(IncomingCallData call) async {
    if (await isKnown(call.callId)) return;
    final stamped = call.copyWith(shownAt: DateTime.now().millisecondsSinceEpoch);
    await FlutterCallkitIncoming.showCallkitIncoming(params(stamped));
  }

  static Future<bool> isKnown(String callId) async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls.any((c) => c.id == callId);
    } catch (_) {
      return false;
    }
  }

  /// The caller gave up, or another of the member's phones answered. Never
  /// touches a call this phone has itself answered.
  static Future<void> dismissIfRinging(String callId) async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls.any((c) => c.id == callId && c.isAccepted)) return;
    } catch (_) {}
    await dismiss(callId);
  }

  /// Stop ringing without reporting a decline: the call ended elsewhere.
  static Future<void> dismiss(String callId) async {
    try {
      await FlutterCallkitIncoming.hideCallkitIncoming(CallKitParams(id: callId));
    } catch (_) {}
  }

  /// Ring an outgoing or answered call as "ongoing". On Android this starts
  /// the foreground service that keeps the microphone and camera running
  /// while the member uses the rest of the app or locks the phone.
  static Future<void> markOngoing(IncomingCallData call, {required bool outgoing}) async {
    if (call.callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.startCall(
        params(call, outgoing: outgoing, ongoing: true),
      );
    } catch (_) {}
  }

  static Future<void> markConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (_) {}
  }

  /// End the phone-side call: stops the ongoing notification and service.
  static Future<void> end(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }

  /// A call answered from the lock screen while the app was not running.
  /// The plugin records it as accepted before launching the app.
  static Future<IncomingCallData?> takeAcceptedOnLaunch() async {
    List<CallKitParams> calls;
    try {
      calls = await FlutterCallkitIncoming.activeCalls();
    } catch (_) {
      return null;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    IncomingCallData? found;
    for (final c in calls) {
      final extra = c.extra;
      final data = extra == null ? null : parse(Map<String, dynamic>.from(extra));
      final fresh = data?.shownAt != null && now - data!.shownAt! < 90 * 1000;
      if (!c.isAccepted) {
        // Still ringing: the member opened the app from the launcher instead
        // of answering. Ending it here would decline it for them.
        if (!fresh) await dismiss(c.id);
        continue;
      }
      if (data != null && fresh && !data.outgoing && found == null) {
        found = data;
      } else {
        // Left over from a call the app never finished — a crash, a force
        // stop. Its ongoing notification would otherwise sit there forever.
        await end(c.id);
      }
    }
    return found;
  }

  /// Decline over HTTP. The Decline button on a lock screen fires with no app
  /// running and no socket to send it on.
  static Future<void> rejectOverHttp(String callId) => _post('/calls/$callId/reject');

  static Future<void> endOverHttp(String callId) => _post('/calls/$callId/end');

  static Future<void> _post(String path) async {
    final dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    Future<Response<dynamic>> send(String token) => dio.post(
          path,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
    final token = await AppStorage.getAccessToken();
    if (token == null) return;
    try {
      await send(token);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) return;
      final refresh = await AppStorage.getRefreshToken();
      if (refresh == null) return;
      try {
        final r = await dio.post(ApiEndpoints.refreshToken, data: {'refresh_token': refresh});
        final data = r.data['data'] as Map<String, dynamic>;
        await AppStorage.saveTokens(
          accessToken: data['access_token'] as String,
          refreshToken: data['refresh_token'] as String,
        );
        await send(data['access_token'] as String);
      } catch (_) {}
    } catch (_) {}
  }
}

class IncomingCallData {
  final String callId;
  final String conversationId;
  final String callerName;
  final String callerPhoto;
  final bool isVideo;
  final int? shownAt;
  final bool outgoing;

  const IncomingCallData({
    required this.callId,
    required this.conversationId,
    required this.callerName,
    this.callerPhoto = '',
    required this.isVideo,
    this.shownAt,
    this.outgoing = false,
  });

  IncomingCallData copyWith({int? shownAt, bool? outgoing}) => IncomingCallData(
        callId: callId,
        conversationId: conversationId,
        callerName: callerName,
        callerPhoto: callerPhoto,
        isVideo: isVideo,
        shownAt: shownAt ?? this.shownAt,
        outgoing: outgoing ?? this.outgoing,
      );

  Map<String, dynamic> toMap() => {
        'call_id': callId,
        'conversation_id': conversationId,
        'caller_name': callerName,
        'caller_photo': callerPhoto,
        'is_video': isVideo ? 'true' : 'false',
        if (shownAt != null) 'ts': shownAt.toString(),
        'outgoing': outgoing ? 'true' : 'false',
      };
}
