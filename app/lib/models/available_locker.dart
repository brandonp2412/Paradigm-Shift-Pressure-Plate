class AvailableLocker {
  final int bankCid;
  final String bankName;
  final String sectionName;
  final String typeCode;
  final int availableCount;
  final int lockerCount;

  const AvailableLocker({
    required this.bankCid,
    required this.bankName,
    required this.sectionName,
    required this.typeCode,
    required this.availableCount,
    required this.lockerCount,
  });

  Map<String, dynamic> toJson() => {
    'bankCid': bankCid,
    'bankName': bankName,
    'sectionName': sectionName,
    'typeCode': typeCode,
    'availableCount': availableCount,
    'lockerCount': lockerCount,
  };

  factory AvailableLocker.fromJson(Map<String, dynamic> json) {
    return AvailableLocker(
      bankCid: (json['bankCid'] as num).toInt(),
      bankName: json['bankName'] as String? ?? '',
      sectionName: json['sectionName'] as String? ?? '',
      typeCode: json['typeCode'] as String? ?? '',
      availableCount: (json['availableCount'] as num?)?.toInt() ?? 0,
      lockerCount: (json['lockerCount'] as num?)?.toInt() ?? 0,
    );
  }
}
