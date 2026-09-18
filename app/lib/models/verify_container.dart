class SSOConfiguration {
  final String clientid;
  final String provider;
  final String name;
  final String url;
  final String issuer;
  final List<String>? scopes;

  const SSOConfiguration({
    required this.clientid,
    required this.provider,
    required this.name,
    required this.url,
    required this.issuer,
    this.scopes,
  });

  factory SSOConfiguration.fromJson(Map<String, dynamic> json) {
    return SSOConfiguration(
      clientid: json['clientid'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      issuer: json['issuer'] as String? ?? '',
      scopes: (json['scopes'] as List?)?.cast<String>(),
    );
  }
}

class MSALConfiguration {
  final String clientid;
  final String provider;
  final String name;
  final String authority;
  final String issuer;
  final List<String>? scopes;

  const MSALConfiguration({
    required this.clientid,
    required this.provider,
    required this.name,
    required this.authority,
    required this.issuer,
    this.scopes,
  });

  factory MSALConfiguration.fromJson(Map<String, dynamic> json) {
    return MSALConfiguration(
      clientid: json['clientid'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      name: json['name'] as String? ?? '',
      authority: json['authority'] as String? ?? '',
      issuer: json['issuer'] as String? ?? '',
      scopes: (json['scopes'] as List?)?.cast<String>(),
    );
  }
}

class VerifyContainer {
  final bool result;
  final String? message;
  final List<String> methods; // e.g. ["password"], ["sso"], etc.
  final SSOConfiguration? ssoConfiguration;
  final MSALConfiguration? msalConfiguration;

  const VerifyContainer({
    required this.result,
    this.message,
    this.methods = const [],
    this.ssoConfiguration,
    this.msalConfiguration,
  });

  bool get isSSO => ssoConfiguration != null || msalConfiguration != null;
  bool get isPassword => methods.contains('password');

  factory VerifyContainer.fromJson(Map<String, dynamic> json) {
    return VerifyContainer(
      result: json['result'] as bool? ?? false,
      message: json['message'] as String?,
      methods: (json['methods'] as List?)?.cast<String>() ?? [],
      ssoConfiguration: json['oidc'] != null
          ? SSOConfiguration.fromJson(json['oidc'] as Map<String, dynamic>)
          : null,
      msalConfiguration: json['msal'] != null
          ? MSALConfiguration.fromJson(json['msal'] as Map<String, dynamic>)
          : null,
    );
  }
}
