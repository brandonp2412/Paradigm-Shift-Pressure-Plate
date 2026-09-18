class Bank {
  final String id;
  final int cid;
  final String name;
  final String prefix;
  final bool hasLockers;
  final bool hasDesks;
  final bool isOnline;
  final String mode;
  final String? altLocation1;
  final String? altLocation2;
  final String location1;
  final String? location2;
  final String? location3;
  final String? location4;
  final String? location5;

  const Bank({
    required this.id,
    required this.cid,
    required this.name,
    required this.prefix,
    required this.hasLockers,
    required this.hasDesks,
    required this.isOnline,
    required this.mode,
    this.altLocation1,
    this.altLocation2,
    this.location1 = '',
    this.location2,
    this.location3,
    this.location4,
    this.location5,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      id: json['id'] as String? ?? '',
      cid: (json['cid'] as num).toInt(),
      name: json['name'] as String? ?? '',
      prefix: json['prefix'] as String? ?? '',
      hasLockers: json['lockers'] as bool? ?? true,
      hasDesks: json['desks'] as bool? ?? false,
      isOnline: json['online'] as bool? ?? false,
      mode: json['mode'] as String? ?? '',
      altLocation1: json['altlocation1'] as String?,
      altLocation2: json['altlocation2'] as String?,
      location1: json['location1'] as String? ?? '',
      location2: json['location2'] as String?,
      location3: json['location3'] as String?,
      location4: json['location4'] as String?,
      location5: json['location5'] as String?,
    );
  }
}
