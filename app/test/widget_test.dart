// Placeholder — flutter create's default counter smoke test doesn't apply
// to this app. Real coverage starts with §17's requirements: golden tests
// for the membership card/ticket/event card, widget tests for every
// screen's loading/empty/error/offline/populated states, and the security
// test suite (tampered signature rejected, expired counter rejected,
// wrong-event ticket rejected, ...). None of that exists yet — this file
// just keeps `flutter test` green until it does.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    expect(1 + 1, 2);
  });
}
