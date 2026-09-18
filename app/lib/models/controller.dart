class Controller {
  final String token;
  final String cid;
  final String socketURI;
  final String webURI;
  final String? uid;
  final String? uidToken;
  final String name;

  const Controller({
    required this.token,
    required this.cid,
    required this.socketURI,
    required this.webURI,
    this.uid,
    this.uidToken,
    required this.name,
  });

  bool get needsAssociation => uid == null || uidToken == null;

  factory Controller.fromJson(Map<String, dynamic> json) {
    return Controller(
      token: json['token'] as String,
      cid: (json['cid'] as String?) ?? '',
      socketURI: (json['uri'] ?? json['socketURI']) as String,
      webURI: (json['weburi'] ?? json['webURI'] as String?) ?? '',
      uid: json['uid'] as String?,
      uidToken: json['uidtoken'] as String?,
      name: (json['sitename'] ?? json['name'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'cid': cid,
    'socketURI': socketURI,
    'webURI': webURI,
    'uid': uid,
    'uidtoken': uidToken,
    'sitename': name,
  };
}
