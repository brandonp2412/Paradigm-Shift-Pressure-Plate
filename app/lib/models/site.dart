class Site {
  final String sitekey;
  final String name;
  final String? uid;
  final String? uidToken;
  final String? cid;
  final String? socketURI;
  final String? webURI;

  const Site({
    required this.sitekey,
    required this.name,
    this.uid,
    this.uidToken,
    this.cid,
    this.socketURI,
    this.webURI,
  });

  factory Site.fromJson(Map<String, dynamic> json) {
    return Site(
      sitekey: json['sitekey'] as String,
      name: json['name'] as String? ?? '',
      uid: json['uid'] as String?,
      uidToken: json['uidtoken'] as String?,
      cid: json['cid'] as String?,
      socketURI: json['uri'] as String?,
      webURI: json['weburi'] as String?,
    );
  }
}
