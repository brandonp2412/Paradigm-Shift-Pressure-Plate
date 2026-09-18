import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/site.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class SiteSelectionScreen extends StatefulWidget {
  final String email;
  final String password;
  final String? accessToken;
  final String? idToken;
  final bool isSSO;

  const SiteSelectionScreen({
    super.key,
    required this.email,
    this.password = '',
    this.accessToken,
    this.idToken,
    required this.isSSO,
  });

  @override
  State<SiteSelectionScreen> createState() => _SiteSelectionScreenState();
}

class _SiteSelectionScreenState extends State<SiteSelectionScreen> {
  List<Site>? _sites;
  bool _loading = true;
  String? _error;
  int? _selectedIndex;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSites());
  }

  Future<void> _loadSites() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    try {
      final sites = await auth.api.getSiteList();
      if (mounted) {
        setState(() {
          _sites = sites;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loginToSite() async {
    if (_selectedIndex == null || _sites == null) return;
    setState(() => _loggingIn = true);
    final auth = context.read<AuthService>();
    final site = _sites![_selectedIndex!];

    bool ok;
    if (widget.isSSO) {
      ok = await auth.ssoLoginToSite(
        widget.email,
        widget.accessToken!,
        widget.idToken!,
        site.sitekey,
      );
    } else {
      ok = await auth.loginToSiteWithPassword(
        widget.email,
        widget.password,
        site.sitekey,
      );
    }

    if (!mounted) return;
    setState(() => _loggingIn = false);

    if (ok) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = auth.errorMessage ?? 'Failed to login to site');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Site')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _loadSites();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _sites!.isEmpty
            ? const Center(child: Text('No sites available'))
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _sites!.length,
                      itemBuilder: (context, index) {
                        final site = _sites![index];
                        return ListTile(
                          leading: Icon(
                            _selectedIndex == index
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(site.name),
                          subtitle: Text(site.sitekey),
                          onTap: () => setState(() => _selectedIndex = index),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _selectedIndex != null && !_loggingIn
                            ? _loginToSite
                            : null,
                        child: _loggingIn
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
                            : const Text('Connect to Site'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
