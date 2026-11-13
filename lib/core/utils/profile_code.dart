/// Short public profile ID, e.g. "GM-5786407D": the first 8 hex digits of the
/// member's id. Members can quote it, and search by it in Seen profiles.
/// Matches the server's profileCode().
String profileCode(Object? userId) {
  final id = userId?.toString() ?? '';
  if (id.length < 8) return '';
  return 'GM-${id.substring(0, 8).toUpperCase()}';
}
