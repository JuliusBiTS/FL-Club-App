import 'package:flc_core/flc_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content warnings are saved trimmed, blanks dropped, and round-trip through the model', () {
    final EventDraft d = EventDraft(title: 'Test', startsAt: DateTime(2027, 1, 1, 19))
      ..contentWarnings = <String>['  May include distressing footage ', '', 'Contains flashing images'];

    final Map<String, dynamic> row = d.toEventRow(forStatus: 'draft');
    expect(row['content_warnings'], <String>['May include distressing footage', 'Contains flashing images']);

    final EventModel model = EventModel.fromJson(<String, dynamic>{
      'id': '1',
      'slug': 's',
      'title': 'T',
      'starts_at': '2027-01-01T19:00:00Z',
      'content_warnings': <String>['Flashing images'],
    });
    expect(model.contentWarnings, <String>['Flashing images']);
    expect(EventDraft.fromModel(model, const <TicketTypeModel>[]).contentWarnings, <String>['Flashing images']);
  });

  test('an older row with no content_warnings reads as none', () {
    final EventModel model = EventModel.fromJson(<String, dynamic>{
      'id': '1',
      'slug': 's',
      'title': 'T',
      'starts_at': '2027-01-01T19:00:00Z',
    });
    expect(model.contentWarnings, isEmpty);
  });

  test('too many, or over-long, warnings are refused', () {
    final EventDraft tooMany = EventDraft(title: 'T', startsAt: DateTime(2027, 1, 1, 19))
      ..contentWarnings = List<String>.generate(kMaxContentWarnings + 1, (int i) => 'w$i');
    expect(tooMany.validate(publishing: false).errors.any((String e) => e.contains('content warnings')), isTrue);

    final EventDraft tooLong = EventDraft(title: 'T', startsAt: DateTime(2027, 1, 1, 19))
      ..contentWarnings = <String>['x' * (kMaxContentWarningLength + 1)];
    expect(tooLong.validate(publishing: false).errors.any((String e) => e.contains('content warning')), isTrue);
  });
}
