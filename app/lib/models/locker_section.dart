class LockerSection {
  final String name;
  final String typeCode;
  final int reservedCount;
  final int availableCount;
  final int lockerCount;

  const LockerSection({
    required this.name,
    required this.typeCode,
    required this.reservedCount,
    required this.availableCount,
    required this.lockerCount,
  });

  factory LockerSection.fromJson(Map<String, dynamic> json) {
    return LockerSection(
      name: json['typename'] as String? ?? '',
      typeCode: json['type'] as String? ?? '',
      reservedCount: (json['reserved'] as num?)?.toInt() ?? 0,
      availableCount: (json['available'] as num?)?.toInt() ?? 0,
      lockerCount: (json['lockercount'] as num?)?.toInt() ?? 0,
    );
  }
}
