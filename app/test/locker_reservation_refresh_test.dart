import 'package:flutter_test/flutter_test.dart';
import 'package:floorsense_app/models/auth_payload.dart';
import 'package:floorsense_app/models/locker_reservation.dart';
import 'package:floorsense_app/services/auth_service.dart';

LockerReservation reservation(String key, String resid) => LockerReservation(
  resid: resid,
  cid: 1,
  key: key,
  restype: 'fixed',
  created: 1,
  start: 1,
  finish: 2,
  closed: true,
  active: 1,
  released: 0,
  pin: '',
  device: 'floorsense',
);

void main() {
  test('reservation refresh replaces the auth snapshot locker', () {
    final payload = AuthPayload(
      hasLockers: true,
      hasDesks: false,
      reservations: [reservation('L036', 'old')],
      uid: 'user',
    );

    final refreshed = payload.copyWith(
      reservations: [reservation('L113', 'new')],
    );

    expect(refreshed.reservations.single.key, 'L113');
    expect(refreshed.hasLockers, isTrue);
    expect(refreshed.uid, 'user');
  });

  test('reserved and released events trigger a locker reservation refresh', () {
    expect(
      isLockerReservationChangeEvent({'type': 'event', 'code': 33}),
      isTrue,
    );
    expect(
      isLockerReservationChangeEvent({'type': 'event', 'code': 34}),
      isTrue,
    );
    expect(
      isLockerReservationChangeEvent({'type': 'event', 'code': 18}),
      isFalse,
    );
    expect(
      isLockerReservationChangeEvent({'type': 'response', 'code': 33}),
      isFalse,
    );
  });
}
