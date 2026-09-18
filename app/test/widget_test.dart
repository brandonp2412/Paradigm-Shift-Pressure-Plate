import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floorsense_app/main.dart';
import 'package:floorsense_app/models/locker_section.dart';

void main() {
  testWidgets('App without a saved session shows login', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const FloorSenseApp());
    await tester.pumpAndSettle();

    expect(find.text('FloorSense Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  test('LockerSection parses availability from API json', () {
    final section = LockerSection.fromJson(const {
      'typename': 'Small',
      'type': 'S',
      'reserved': 2,
      'available': 3,
      'lockercount': 5,
    });
    expect(section.name, 'Small');
    expect(section.typeCode, 'S');
    expect(section.availableCount, 3);
    expect(section.lockerCount, 5);
  });
}
