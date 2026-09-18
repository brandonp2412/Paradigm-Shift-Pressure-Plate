class LockerReservation {
  final String resid;
  final int cid;
  final String key;
  final String restype; // "fixed", "adhoc", "advance"
  final String? bankname;
  final int? planid;
  final int created;
  final int start;
  final int finish;
  final int? lastopened;
  final bool closed;
  final int active;
  final int released;
  final String pin;
  final String device; // "floorsense", "vecos"

  const LockerReservation({
    required this.resid,
    required this.cid,
    required this.key,
    required this.restype,
    this.bankname,
    this.planid,
    required this.created,
    required this.start,
    required this.finish,
    this.lastopened,
    required this.closed,
    required this.active,
    required this.released,
    required this.pin,
    required this.device,
  });

  factory LockerReservation.fromJson(Map<String, dynamic> json) {
    return LockerReservation(
      resid: json['resid'] as String,
      cid: (json['cid'] as num).toInt(),
      key: json['key'] as String,
      restype: json['restype'] as String? ?? 'adhoc',
      bankname: json['bankname'] as String?,
      planid: json['planid'] as int?,
      created: (json['created'] as num).toInt(),
      start: (json['start'] as num).toInt(),
      finish: (json['finish'] as num).toInt(),
      lastopened: json['lastopened'] as int?,
      closed: json['closed'] as bool? ?? false,
      active: (json['active'] as num?)?.toInt() ?? 0,
      released: (json['released'] as num?)?.toInt() ?? 0,
      pin: json['pin'] as String? ?? '',
      device: json['device'] as String? ?? 'floorsense',
    );
  }

  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(start * 1000);
  DateTime get finishDate => DateTime.fromMillisecondsSinceEpoch(finish * 1000);
  DateTime get createdDate =>
      DateTime.fromMillisecondsSinceEpoch(created * 1000);
  bool get isActive => active == 1 && released == 0;
}
