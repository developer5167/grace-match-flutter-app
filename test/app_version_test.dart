import 'package:flutter_test/flutter_test.dart';
import 'package:grace_match/core/utils/app_version.dart';

void main() {
  test('older builds sit below the latest version', () {
    expect(compareAppVersions('1.0.0', '1.0.1'), lessThan(0));
    expect(compareAppVersions('1.0.1', '1.0.1'), 0);
    expect(compareAppVersions('1.2.0', '1.1.9'), greaterThan(0));
    expect(compareAppVersions('1.0.0+1', '1.0.0+2'), lessThan(0));
  });
}
