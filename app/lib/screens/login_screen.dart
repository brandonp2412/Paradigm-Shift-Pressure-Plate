import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'site_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showPassword = false;
  String? _savedCodeVerifier;
  String? _savedState;
  String? _savedClientId;
  String? _savedTokenEndpoint;
  String? _savedRedirectUri;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FloorSense Login')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Consumer<AuthService>(
              builder: (context, auth, _) {
                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_outline, size: 64),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (v) =>
                            v?.isEmpty == true ? 'Enter your email' : null,
                      ),
                      const SizedBox(height: 16),
                      if (_showPassword)
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                          validator: (v) =>
                              v?.isEmpty == true ? 'Enter your password' : null,
                          onFieldSubmitted: (_) => _onContinue(auth),
                        ),
                      if (auth.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            auth.errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : () => _onContinue(auth),
                        child: _loading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                auth.state == AuthState.ssoLogin
                                    ? 'Sign in with SSO'
                                    : 'Continue',
                              ),
                      ),
                      if (auth.state == AuthState.ssoLogin)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'Your organization uses single sign-on (${auth.verifyResult?.ssoConfiguration?.name ?? auth.verifyResult?.msalConfiguration?.name ?? "SSO"})',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onContinue(AuthService auth) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final email = _emailController.text.trim();

    if (auth.state == AuthState.initial) {
      await auth.validateUsername(email);
      setState(() {
        _loading = false;
        _showPassword = auth.state == AuthState.passwordLogin;
      });
      if (auth.state == AuthState.ssoLogin) {
        _startSSO(auth, email);
      }
    } else if (auth.state == AuthState.passwordLogin && _showPassword) {
      final ok = await auth.loginPassword(email, _passwordController.text);
      setState(() => _loading = false);
      if (ok) {
        _goToSiteSelection(auth, email, _passwordController.text);
      }
    }
  }

  Future<void> _startSSO(AuthService auth, String email) async {
    setState(() => _loading = true);
    final ssoConfig = auth.verifyResult?.ssoConfiguration;
    final msalConfig = auth.verifyResult?.msalConfiguration;

    String configUrl;
    String clientId;
    List<String> scopes;

    if (ssoConfig != null) {
      configUrl = ssoConfig.url;
      clientId = ssoConfig.clientid;
      scopes = ssoConfig.scopes ?? ['openid', 'email', 'profile'];
    } else if (msalConfig != null) {
      configUrl = msalConfig.authority;
      clientId = msalConfig.clientid;
      scopes = msalConfig.scopes ?? ['openid', 'email', 'profile'];
    } else {
      setState(() => _loading = false);
      return;
    }

    // The provider only issues a refresh_token when offline_access is
    // requested, and an id_token requires openid. Ensure both are present
    // regardless of what the server-provided config lists — without the
    // refresh token the session can't survive past the ~1h access-token TTL.
    scopes = {...scopes, 'openid', 'offline_access'}.toList();

    String? authorizationEndpoint;
    String? tokenEndpoint;
    try {
      final discoveryUrl = '$configUrl/.well-known/openid-configuration';
      final resp = await http.get(Uri.parse(discoveryUrl));
      if (resp.statusCode == 200) {
        final discovery = jsonDecode(resp.body) as Map<String, dynamic>;
        authorizationEndpoint = discovery['authorization_endpoint'] as String?;
        tokenEndpoint = discovery['token_endpoint'] as String?;
      }
    } catch (_) {}

    if (!mounted) return;

    if (authorizationEndpoint == null) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to discover OIDC provider'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = false);

    final codeVerifier = generateCodeVerifier();
    final codeChallenge = generateCodeChallenge(codeVerifier);
    final state = generateState();
    final redirectUri = 'https://api.smartalock.com/oidc/callback';

    final authUrl = Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        if (email.isNotEmpty) 'login_hint': email,
      },
    );

    _savedCodeVerifier = codeVerifier;
    _savedState = state;
    _savedClientId = clientId;
    _savedTokenEndpoint = tokenEndpoint;
    _savedRedirectUri = redirectUri;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SSOWebViewScreen(
          authUrl: authUrl.toString(),
          redirectUriPrefix: redirectUri,
          onCodeReceived: (code, returnedState) async {
            if (returnedState != _savedState) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('SSO state mismatch. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
            setState(() => _loading = true);
            try {
              final api = ApiService();
              String accessToken;
              String idToken;
              String? refreshToken;

              try {
                final tokenResp = await api.exchangeOidcToken(
                  email,
                  code,
                  _savedCodeVerifier!,
                  _savedRedirectUri!,
                  returnedState,
                );
                accessToken = tokenResp['access_token'] as String;
                idToken = tokenResp['id_token'] as String;
                refreshToken = tokenResp['refresh_token'] as String?;
              } catch (e) {
                if (_savedTokenEndpoint == null) rethrow;
                final directResp = await _exchangeDirectly(
                  code,
                  _savedCodeVerifier!,
                  _savedRedirectUri!,
                  _savedClientId!,
                  _savedTokenEndpoint!,
                );
                accessToken = directResp['access_token'] as String;
                idToken = directResp['id_token'] as String;
                refreshToken = directResp['refresh_token'] as String?;
              }

              final ok = await auth.loginSSO(
                email,
                accessToken,
                idToken,
                refreshToken: refreshToken,
                tokenEndpoint: _savedTokenEndpoint,
                clientId: _savedClientId,
              );
              if (!mounted) return;
              setState(() => _loading = false);
              if (ok) {
                _goToSiteSelectionSSO(auth, email, accessToken, idToken);
              }
            } catch (e) {
              if (!mounted) return;
              setState(() => _loading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('SSO token exchange failed: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _goToSiteSelection(AuthService auth, String email, String password) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            SiteSelectionScreen(email: email, password: password, isSSO: false),
      ),
    );
  }

  void _goToSiteSelectionSSO(
    AuthService auth,
    String email,
    String accessToken,
    String idToken,
  ) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SiteSelectionScreen(
          email: email,
          accessToken: accessToken,
          idToken: idToken,
          isSSO: true,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _exchangeDirectly(
    String code,
    String codeVerifier,
    String redirectUri,
    String clientId,
    String tokenEndpoint,
  ) async {
    final resp = await http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        'code_verifier': codeVerifier,
      },
    );
    if (resp.statusCode != 200) {
      final preview = resp.body.length > 300
          ? '${resp.body.substring(0, 300)}...'
          : resp.body;
      throw ApiException(
        'Direct token exchange returned HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
        body: preview,
      );
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}

class _SSOWebViewScreen extends StatefulWidget {
  final String authUrl;
  final String redirectUriPrefix;
  final void Function(String code, String state) onCodeReceived;

  const _SSOWebViewScreen({
    required this.authUrl,
    required this.redirectUriPrefix,
    required this.onCodeReceived,
  });

  @override
  State<_SSOWebViewScreen> createState() => _SSOWebViewScreenState();
}

class _SSOWebViewScreenState extends State<_SSOWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (url.startsWith(widget.redirectUriPrefix)) {
              final uri = Uri.parse(url);
              final code = uri.queryParameters['code'];
              final state = uri.queryParameters['state'];
              if (code != null && state != null) {
                Navigator.of(context).pop();
                widget.onCodeReceived(code, state);
              }
            }
          },
          onPageFinished: (_) {
            setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
