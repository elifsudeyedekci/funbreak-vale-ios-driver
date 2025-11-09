import 'package:flutter/material.dart';
import '../../services/ride_persistence_service.dart';
import '../home/driver_home_screen.dart';
import '../earnings/earnings_screen.dart';
import '../settings/settings_screen.dart'; // PROFİL YERİNE SETTİNGS!
import '../ride/modern_active_ride_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DriverHomeScreen(),
    const EarningsScreen(),
    const SettingsScreen(), // PROFİL YERİNE SETTİNGS!
  ];

  @override
  void initState() {
    super.initState();
    
    // ŞOFÖR ANA SAYFA YERİNE AKTİF YOLCULUK KONTROL! ✅
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkForActiveDriverRideInMainScreen();
      });
    });
  }
  
  // ŞOFÖR GÜÇLÜ PERSİSTENCE SİSTEMİ - YOLCULUK BİTENE KADAR KAYBOLMASIN!
  Future<void> _checkForActiveDriverRideInMainScreen() async {
    try {
      print('🔍 ŞOFÖR: Persistence kontrol başlıyor...');
      
      // SharedPreferences'tan direkt kontrol et - DOĞRU KEY!
      final prefs = await SharedPreferences.getInstance();
      final driverActiveRide = prefs.getString('active_driver_ride_data'); // SERVICE İLE AYNI KEY!
      
      print('🔍 ŞOFÖR: Persistence data (active_driver_ride_data): ${driverActiveRide != null ? "VAR" : "YOK"}');
      
      if (driverActiveRide != null && driverActiveRide.isNotEmpty) {
        try {
          final rideData = jsonDecode(driverActiveRide);
          final status = rideData['status']?.toString() ?? 'accepted';
          final rideId = rideData['ride_id']?.toString() ?? '0';
          
          print('🔍 ŞOFÖR: Persistence - Status: $status, Ride ID: $rideId');
          
          // SADECE AKTİF DURUMLARDA MODERN EKRAN AÇILSIN!
          final activeStatuses = ['accepted', 'in_progress', 'driver_arrived', 'ride_started', 'waiting_customer'];
          
          if (activeStatuses.contains(status) && rideId != '0') {
            print('✅ ŞOFÖR: Aktif yolculuk bulundu - Modern ekrana geçiliyor');
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ModernDriverActiveRideScreen(
                    rideDetails: rideData,
                    waitingMinutes: rideData['waiting_minutes'] ?? 0,
                  ),
                ),
              );
              return;
            }
          } else {
            // Bitmiş yolculuk - temizle (DOĞRU KEY!)
            await prefs.remove('active_driver_ride_data');
            await prefs.remove('driver_ride_state');
            print('🗑️ ŞOFÖR: Bitmiş yolculuk persistence temizlendi');
          }
        } catch (decodeError) {
          print('❌ ŞOFÖR: Persistence JSON decode hatası: $decodeError');
          await prefs.remove('active_driver_ride_data');
          await prefs.remove('driver_ride_state');
        }
      }
      
      print('ℹ️ ŞOFÖR: Normal ana sayfa kalacak');
      
    } catch (e) {
      print('❌ ŞOFÖR: Persistence kontrol hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A2A3E),
              Color(0xFF1A1A2E),
            ],
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          currentIndex: _currentIndex,
          onTap: (index) {
            // ANA SAYFA BASILINCA AKTİF YOLCULUK KONTROL ET! ✅
            if (index == 0) { // Ana sayfa sekmesi
              _checkForActiveDriverRideInMainScreen();
            }
            
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFFD700),
          unselectedItemColor: Colors.grey[400],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              activeIcon: Icon(Icons.home),
              label: 'Ana Sayfa',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.attach_money),
              activeIcon: Icon(Icons.attach_money),
              label: 'Kazanç',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}
