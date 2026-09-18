import 'package:flutter_test/flutter_test.dart';
import 'package:floorsense_app/services/background_service.dart';

/// Builds a getLockerStatus-shaped payload: { info: { types: [ ... ] } }.
/// Each entry mirrors LockerSection.fromJson's expected keys.
Map<String, dynamic> status(List<Map<String, dynamic>> types) => {
      'info': {'types': types},
    };

Map<String, dynamic> section({
  String type = 'S',
  int available = 0,
  int reserved = 0,
  int lockercount = 0,
}) =>
    {
      'typename': 'Section $type',
      'type': type,
      'available': available,
      'reserved': reserved,
      'lockercount': lockercount,
    };

void main() {
  group('availableCount', () {
    test('sums available across sections', () {
      final s = status([
        section(type: 'S', available: 2),
        section(type: 'M', available: 0),
        section(type: 'L', available: 3),
      ]);
      expect(BackgroundWatch.availableCount(s), 5);
    });

    test('returns 0 when no sections have free lockers', () {
      final s = status([section(available: 0), section(available: 0)]);
      expect(BackgroundWatch.availableCount(s), 0);
    });

    test('returns 0 for malformed / missing info', () {
      expect(BackgroundWatch.availableCount(<String, dynamic>{}), 0);
      expect(BackgroundWatch.availableCount({'info': 'nope'}), 0);
      expect(BackgroundWatch.availableCount({'info': <String, dynamic>{}}), 0);
      expect(
        BackgroundWatch.availableCount({
          'info': {'types': 'nope'}
        }),
        0,
      );
    });

    test('treats missing available key as 0', () {
      final s = {
        'info': {
          'types': [
            {'type': 'S'} // no 'available'
          ]
        }
      };
      expect(BackgroundWatch.availableCount(s), 0);
    });
  });

  group('becameAvailable (notify only on transition)', () {
    test('fires when a bank goes from no-free to free', () {
      expect(BackgroundWatch.becameAvailable(false, true), isTrue);
    });

    test('fires on first-ever run (no previous state)', () {
      expect(BackgroundWatch.becameAvailable(null, true), isTrue);
    });

    test('stays silent while a bank remains free', () {
      expect(BackgroundWatch.becameAvailable(true, true), isFalse);
    });

    test('stays silent when no locker is free', () {
      expect(BackgroundWatch.becameAvailable(false, false), isFalse);
      expect(BackgroundWatch.becameAvailable(true, false), isFalse);
      expect(BackgroundWatch.becameAvailable(null, false), isFalse);
    });
  });
}
