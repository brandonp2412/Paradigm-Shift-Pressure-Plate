import 'package:flutter_test/flutter_test.dart';
import 'package:floorsense_app/models/available_locker.dart';
import 'package:floorsense_app/services/locker_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

AvailableLocker locker(int cid, String section) => AvailableLocker(
      bankCid: cid,
      bankName: 'Bank $cid',
      sectionName: section,
      typeCode: 'adhoc',
      availableCount: 2,
      lockerCount: 5,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('available lockers round-trip', () {
    test('returns null when nothing cached', () async {
      expect(await LockerCache.readAvailableLockers(), isNull);
    });

    test('saves and reads back the list', () async {
      await LockerCache.saveAvailableLockers([locker(1, 'A'), locker(2, 'B')]);
      final read = await LockerCache.readAvailableLockers();
      expect(read, isNotNull);
      expect(read!.length, 2);
      expect(read[0].bankCid, 1);
      expect(read[0].sectionName, 'A');
      expect(read[1].bankName, 'Bank 2');
      expect(read[1].availableCount, 2);
    });
  });

  group('locker names round-trip', () {
    test('saves and reads back the map', () async {
      await LockerCache.saveLockerNames({
        12: ['L034', 'L035'],
        99: ['L100'],
      });
      final read = await LockerCache.readLockerNames();
      expect(read, isNotNull);
      expect(read![12], ['L034', 'L035']);
      expect(read[99], ['L100']);
    });
  });

  group('lockerNamesStale (TTL)', () {
    test('stale when nothing cached', () async {
      expect(await LockerCache.lockerNamesStale(), isTrue);
    });

    test('fresh immediately after saving', () async {
      await LockerCache.saveLockerNames({1: ['L1']});
      expect(await LockerCache.lockerNamesStale(), isFalse);
    });
  });
}
