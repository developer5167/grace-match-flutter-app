/// Compares app versions the way the store listing uses them.
///
/// Accepts `1.0.1` or `1.0.1+2`. Missing segments count as 0.
int compareAppVersions(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  for (var i = 0; i < 4; i++) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _parts(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [0, 0, 0, 0];
  final plus = trimmed.split('+');
  final core = plus[0]
      .split('.')
      .map((piece) => int.tryParse(piece) ?? 0)
      .toList();
  while (core.length < 3) {
    core.add(0);
  }
  final build = plus.length > 1 ? int.tryParse(plus[1]) ?? 0 : 0;
  return [core[0], core[1], core[2], build];
}
