import 'bank.dart';
import 'locker_reservation.dart';

class AuthPayload {
  final bool hasLockers;
  final bool hasDesks;
  final List<LockerReservation> reservations;
  final List<Bank> banks;
  final String? uid;

  const AuthPayload({
    required this.hasLockers,
    required this.hasDesks,
    this.reservations = const [],
    this.banks = const [],
    this.uid,
  });

  AuthPayload copyWith({List<LockerReservation>? reservations}) {
    return AuthPayload(
      hasLockers: hasLockers,
      hasDesks: hasDesks,
      reservations: reservations ?? this.reservations,
      banks: banks,
      uid: uid,
    );
  }

  factory AuthPayload.fromJson(Map<String, dynamic> json) {
    return AuthPayload(
      hasLockers: json['lockers'] as bool? ?? false,
      hasDesks: json['desks'] as bool? ?? false,
      reservations:
          (json['res'] as List?)
              ?.map(
                (e) => LockerReservation.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      banks:
          (json['bk'] as List?)
              ?.map((e) => Bank.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      uid: json['uid'] as String?,
    );
  }
}
