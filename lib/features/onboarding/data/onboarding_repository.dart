import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/dio_client.dart';

class OnboardingRepository {
  final Dio _dio = DioClient.instance;

  Future<void> saveStep(int step, Map<String, dynamic> data) async {
    try {
      await _dio.post(ApiEndpoints.onboardingStep(step), data: data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await _dio.get(ApiEndpoints.onboardingStatus);
      return response.data['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Upload one or more new photo files to step 8.
  /// Called when the user taps Continue on the photos step.
  Future<void> uploadPhotos(List<String> filePaths) async {
    try {
      if (filePaths.isEmpty) {
        // No new files — just advance the step (existing photos still count)
        await _dio.post(ApiEndpoints.onboardingStep(8), data: FormData());
        return;
      }

      final files = await Future.wait(
        filePaths.map((path) => MultipartFile.fromFile(
          path,
          contentType: DioMediaType('image', 'jpeg'),
        )),
      );

      final formData = FormData.fromMap({'photos': files});
      await _dio.post(ApiEndpoints.onboardingStep(8), data: formData);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete an already-uploaded photo by its DB id.
  Future<void> deletePhoto(String photoId) async {
    try {
      await _dio.delete('/onboarding/photos/$photoId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Upload the selfie verification video. Called when the user taps Continue
  /// on step 9.
  ///
  /// Two things here were wrong and are worth keeping right:
  ///
  ///  * It must go to `/trust/video-selfie`, not `/trust/verify-identity`.
  ///    The latter accepts a single IMAGE on a field named `id_proof`, so
  ///    posting a video on a field named `video` made multer reject the
  ///    request outright with "Unexpected field" — every single time.
  ///
  ///  * The part needs an explicit Content-Type. `MultipartFile.fromFile`
  ///    sends `application/octet-stream` by default, which the server's video
  ///    filter refused. The server now also falls back to the extension, but
  ///    sending the correct type is the actual fix rather than the safety net.
  Future<void> submitIdentityVerification(String videoFilePath) async {
    try {
      final file = File(videoFilePath);
      if (!await file.exists()) {
        throw 'The recording could not be found. Please record it again.';
      }

      final extension = p.extension(videoFilePath).replaceFirst('.', '').toLowerCase();
      final subtype = switch (extension) {
        'mov' || 'qt' => 'quicktime',
        'm4v' => 'x-m4v',
        '3gp' => '3gpp',
        'mkv' => 'x-matroska',
        '' => 'mp4',
        _ => extension,
      };

      final formData = FormData.fromMap({
        'video': await MultipartFile.fromFile(
          videoFilePath,
          filename: p.basename(videoFilePath),
          contentType: MediaType('video', subtype),
        ),
      });

      await _dio.post(ApiEndpoints.videoSelfie, data: formData);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        if (data['errors'] != null && data['errors'] is List) {
          final errors = data['errors'] as List;
          if (errors.isNotEmpty) {
            return errors.map((err) => '• ${err['message']}').join('\n');
          }
        }
        return data['message'] ?? 'An error occurred';
      }
    }
    return 'Network error. Please try again.';
  }
}
