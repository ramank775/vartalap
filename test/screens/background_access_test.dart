import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/battery/background_access.dart';
import 'package:vartalap/services/push_service.dart';

void main() {
  test('asked for only when restricted: foss always, gms only without push',
      () {
    const fossRestricted = (allowed: false, direct: true);
    const gmsRestricted = (allowed: false, direct: false);

    expect(backgroundAccessWanted(null, PushState.off), isFalse,
        reason: 'not read yet, or no channel');
    expect(backgroundAccessWanted((allowed: true, direct: true), PushState.off),
        isFalse);
    expect(backgroundAccessWanted(fossRestricted, PushState.registered), isTrue,
        reason: 'no Google push to lean on');
    expect(backgroundAccessWanted(gmsRestricted, PushState.registered), isFalse,
        reason: 'FCM wakes it; Play allows the ask only without it');
    for (final state in [
      PushState.off,
      PushState.failed,
      PushState.choiceNeeded
    ]) {
      expect(backgroundAccessWanted(gmsRestricted, state), isTrue,
          reason: '$state');
    }
  });
}
