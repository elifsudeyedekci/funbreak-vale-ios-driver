import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/driver_numeric_id.dart';

/// Panelde üyelik `inactive` / `suspended` iken uygulamanın tamamını bloklar.
class DriverMembershipGuard extends StatefulWidget {
  const DriverMembershipGuard({super.key, required this.child});

  final Widget child;

  @override
  State<DriverMembershipGuard> createState() => _DriverMembershipGuardState();
}

class _DriverMembershipGuardState extends State<DriverMembershipGuard> with WidgetsBindingObserver {
  static const _prefsKey = 'driver_membership_status';
  static const _profileUrl = 'https://admin.funbreakvale.com/api/get_driver_profile.php';
  static const _supportPhoneDisplay = '0533 448 82 53';
  static final Uri _supportTelUri = Uri(scheme: 'tel', path: '+905334488253');

  bool _ready = false;
  bool _blocked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      final s = p.getString(_prefsKey);
      if (!mounted) return;
      setState(() {
        _blocked = s != null && s != 'active';
        _ready = true;
      });
      _refreshFromServer();
    });
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _refreshFromServer());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromServer();
    }
  }

  Future<void> _refreshFromServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = readDriverNumericUserId(prefs);
      if (id <= 0) return;
      final r = await http.get(Uri.parse('$_profileUrl?driver_id=$id')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final decoded = jsonDecode(r.body);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      if (data['success'] != true) return;
      final status = (data['status'] ?? 'active').toString().toLowerCase().trim();
      await prefs.setString(_prefsKey, status);
      if (!mounted) return;
      setState(() {
        _blocked = status != 'active';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _callSupport() async {
    if (await canLaunchUrl(_supportTelUri)) {
      await launchUrl(_supportTelUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
    }

    if (_blocked) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFD700), size: 72),
                  const SizedBox(height: 24),
                  const Text(
                    'Üyeliğiniz pasife alınmıştır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Müşteri hizmetleriyle iletişime geçiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  SelectableText(
                    _supportPhoneDisplay,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _callSupport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.phone),
                      label: const Text('Hemen ara', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
