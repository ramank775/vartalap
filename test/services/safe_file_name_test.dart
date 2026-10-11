import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/services/asset_cache.dart';

void main() {
  test('a sender-chosen file name cannot leave the hand-off folder', () {
    expect(safeFileName('report.pdf'), 'report.pdf');
    expect(safeFileName('../../shared_prefs/x.xml'), 'x.xml');
    expect(safeFileName(r'..\..\evil.txt'), 'evil.txt');
    expect(safeFileName('..'), 'attachment');
    expect(safeFileName('dir/'), 'attachment');
    expect(safeFileName(''), 'attachment');
  });
}
