import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../profile/driver_profile_screen.dart';
import '../../services/dynamic_contact_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../home/driver_home_screen.dart';
import '../services/services_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'Türkçe';
  String? _supportPhone;
  String? _supportEmail;
  String? _whatsappNumber;
  String? _driverName;
  String? _driverIban;
  String? _localProfileImagePath; // YEREL PROFİL FOTOĞRAFI
  String? _backendProfilePhotoUrl; // BACKEND PROFİL FOTOĞRAFI
  final TextEditingController _ibanController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadContactInfo();
    _loadDriverInfo();
    _loadProfilePhoto(); // PROFİL FOTOĞRAFI YÜKLE
  }
  
  // PROFİL FOTOĞRAFI KAYNAĞINI BELİRLE
  ImageProvider? _getProfileImage() {
    // Öncelik: 1. Backend URL, 2. Yerel dosya
    if (_backendProfilePhotoUrl != null && _backendProfilePhotoUrl!.isNotEmpty) {
      return NetworkImage(_backendProfilePhotoUrl!);
    }
    if (_localProfileImagePath != null && _localProfileImagePath!.isNotEmpty) {
      final file = File(_localProfileImagePath!);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }
  
  // PROFİL FOTOĞRAFINI YEREL + BACKEND'DEN YÜKLE
  Future<void> _loadProfilePhoto() async {
    try {
      // 1. Önce yerel yedekten kontrol et
      final directory = await getApplicationDocumentsDirectory();
      final localPath = '${directory.path}/driver_profile_image.jpg';
      final localFile = File(localPath);
      
      if (await localFile.exists()) {
        debugPrint('✅ SÜRÜCÜ AYARLAR: Yerel profil fotoğrafı bulundu');
        if (mounted) {
          setState(() {
            _localProfileImagePath = localPath;
          });
        }
      }
      
      // 2. Backend'den de çekmeyi dene
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      if (driverId != null) {
        debugPrint('📸 SÜRÜCÜ AYARLAR: Backend\'den fotoğraf çekiliyor - ID: $driverId');
        
        final response = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/get_driver_photo.php?driver_id=$driverId'),
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['photo_url'] != null && data['photo_url'].toString().isNotEmpty) {
            debugPrint('✅ SÜRÜCÜ AYARLAR: Backend fotoğrafı alındı: ${data['photo_url']}');
            if (mounted) {
              setState(() {
                _backendProfilePhotoUrl = data['photo_url'];
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ SÜRÜCÜ AYARLAR: Profil fotoğrafı yükleme hatası: $e');
    }
  }
  
  @override
  void dispose() {
    _ibanController.dispose();
    super.dispose();
  }
  
  Future<void> _loadDriverInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      debugPrint('🔍 IBAN - Driver ID: $driverId');
      
      if (driverId != null) {
        final response = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/get_driver_profile.php?driver_id=$driverId'),
        ).timeout(const Duration(seconds: 10));
        
        debugPrint('📥 IBAN - Response status: ${response.statusCode}');
        debugPrint('📥 IBAN - Response: ${response.body}');
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          debugPrint('✅ IBAN - API Success: ${data['success']}');
          
          if (data['success'] == true) {
            final name = data['name']?.toString() ?? '';
            final surname = data['surname']?.toString() ?? '';
            
            // surname boşsa name'de zaten tam ad var
            final fullName = surname.isEmpty ? name : '$name $surname'.trim();
            
            debugPrint('✅ IBAN - İsim: $fullName');
            debugPrint('✅ IBAN - IBAN: ${data['iban']}');
            
            if (mounted) {
              setState(() {
                _driverName = fullName.isNotEmpty ? fullName : 'Sürücü';
                _driverIban = data['iban']?.toString() ?? '';
                _ibanController.text = _driverIban ?? '';
              });
              
              debugPrint('✅ setState tamamlandı - Name: $_driverName, IBAN: $_driverIban');
            }
          } else {
            debugPrint('❌ API success=false: ${data['message']}');
          }
        } else {
          debugPrint('❌ HTTP Error: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('❌ Sürücü bilgileri yüklenemedi: $e');
    }
  }
  
  Future<void> _loadContactInfo() async {
    try {
      await DynamicContactService.getSystemSettings();
      
      setState(() {
        _supportPhone = DynamicContactService.getSupportPhone();
        _supportEmail = DynamicContactService.getSupportEmail();
        _whatsappNumber = DynamicContactService.getWhatsAppNumber();
      });
    } catch (e) {
      debugPrint('Destek bilgileri yüklenemedi: $e');
    }
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('driver_language') ?? 'Türkçe';
    });
  }

  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_language', _selectedLanguage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // GERİ BUTONU KALDIRILDI
        title: const Text('Ayarlar'),
        centerTitle: true,
      ),
      // ALT BAR
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        elevation: 8,
        currentIndex: 2, // Ayarlar seçili
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
            );
          } else if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ServicesScreen()),
            );
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFFD700),
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Geçmiş Yolculuklar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Ayarlar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileSection(context),
          const SizedBox(height: 20),
          _buildSettingsSection(context),
          const SizedBox(height: 20),
          _buildSupportSection(context),
          const SizedBox(height: 20),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // PROFiL FOTO - YEREL VEYA BACKEND'DEN GÖSTER
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFFFFD700),
                backgroundImage: _getProfileImage(),
                child: _getProfileImage() == null
                    ? const Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              
              // GERÇEK ŞOFÖR ADI
              Text(
                authProvider.currentUser != null 
                    ? '${authProvider.currentUser!['name'] ?? 'Şoför'} ${authProvider.currentUser!['surname'] ?? ''}'
                    : 'Şoför Adı Yükleniyor...',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              
              // GERÇEK EMAIL ADRESİ
              Text(
                authProvider.currentUser?['email'] ?? 'E-posta yükleniyor...',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // EHLİYET TÜRÜ - PANELDEN ÇEKİLECEK!
              FutureBuilder<String>(
                future: _getDriverLicenseTypeFromPanel(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Ehliyet: ${snapshot.data}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    );
                  }
                  return const Text(
                    'Ehliyet: Yükleniyor...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              // ŞOFÖR DEĞERLENDİRME - TIKLANABILIR YILDIZ!
              GestureDetector(
                onTap: () => _showDriverRatings(),
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _getDriverRatingsFromPanel(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      final rating = snapshot.data!['average_rating'] ?? 0.0;
                      final totalRatings = snapshot.data!['total_ratings'] ?? 0;
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...List.generate(5, (index) => Icon(
                              index < rating ? Icons.star : Icons.star_border,
                              color: const Color(0xFFFFD700),
                              size: 16,
                            )),
                            const SizedBox(width: 6),
                            Text(
                              '${rating.toStringAsFixed(1)} ($totalRatings)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.touch_app, size: 12, color: Colors.green),
                          ],
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: const Text(
                        '⭐ Değerlendirme yükleniyor...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // ŞOFÖR DEĞERLENDİRMELERİNİ PANELDEN ÇEK!
  Future<Map<String, dynamic>> _getDriverRatingsFromPanel() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      if (driverId == null) {
        return {'average_rating': 0.0, 'total_ratings': 0};
      }
      
      print('⭐ Şoför değerlendirmeleri çekiliyor: Sürücü ID $driverId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_driver_ratings.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'include_comments': false, // Sadece özet bilgi
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final averageRating = double.tryParse(data['average_rating']?.toString() ?? '0') ?? 0.0;
          final totalRatings = int.tryParse(data['total_ratings']?.toString() ?? '0') ?? 0;
          
          print('✅ Şoför değerlendirmeleri alındı: ${averageRating}/5.0 ($totalRatings değerlendirme)');
          return {
            'average_rating': averageRating,
            'total_ratings': totalRatings,
          };
        }
      }
      
      print('⚠️ Şoför değerlendirmeleri alınamadı - varsayılan: 0.0');
      return {'average_rating': 0.0, 'total_ratings': 0};
      
    } catch (e) {
      print('❌ Şoför rating çekme hatası: $e');
      return {'average_rating': 0.0, 'total_ratings': 0};
    }
  }
  
  // ŞOFÖR DEĞERLENDİRME DETAYLARINI GÖSTER - YORUMLAR DAHİL!
  void _showDriverRatings() async {
    print('⭐ Şoför değerlendirme detayları açılıyor...');
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      if (driverId == null) return;
      
      // Detaylı rating verilerini çek
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_driver_ratings.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'include_comments': true,
          'include_details': true,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          _showRatingModal(data);
        } else {
          _showNoRatingsDialog();
        }
      } else {
        _showNoRatingsDialog();
      }
    } catch (e) {
      print('❌ Rating detayları yükleme hatası: $e');
      _showNoRatingsDialog();
    }
  }
  
  void _showRatingModal(Map<String, dynamic> data) {
    final averageRating = double.tryParse(data['average_rating']?.toString() ?? '0') ?? 0.0;
    final totalRatings = int.tryParse(data['total_ratings']?.toString() ?? '0') ?? 0;
    final comments = List<Map<String, dynamic>>.from(data['comments'] ?? []);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD700),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Müşteri Değerlendirmelerim',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${averageRating.toStringAsFixed(1)}/5.0 • $totalRatings Değerlendirme',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // Rating breakdown
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (index) {
                  final stars = 5 - index;
                  final count = data['rating_breakdown']?[stars.toString()] ?? 0;
                  return Column(
                    children: [
                      Row(
                        children: [
                          Text('$stars', style: const TextStyle(fontSize: 12)),
                          const Icon(Icons.star, color: Color(0xFFFFD700), size: 12),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            
            const Divider(),
            
            // Yorumlar listesi
            Expanded(
              child: comments.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.comment_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Henüz yorum yok',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return _buildCommentCard(comment);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCommentCard(Map<String, dynamic> comment) {
    final rating = int.tryParse(comment['rating']?.toString() ?? '5') ?? 5;
    final customerName = comment['customer_name']?.toString() ?? 'Müşteri';
    final commentText = comment['comment']?.toString() ?? '';
    final rideDate = comment['ride_date']?.toString() ?? '';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFFFD700),
                      child: Text(
                        customerName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    ...List.generate(rating, (index) => const Icon(
                      Icons.star,
                      color: Color(0xFFFFD700),
                      size: 16,
                    )),
                    ...List.generate(5 - rating, (index) => const Icon(
                      Icons.star_border,
                      color: Colors.grey,
                      size: 16,
                    )),
                  ],
                ),
              ],
            ),
            
            if (commentText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                commentText,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            
            if (rideDate.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rideDate,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  void _showNoRatingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.star_outline, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('Müşteri Değerlendirmeleri'),
          ],
        ),
        content: const Text('Henüz müşterilerden değerlendirme almadınız. İlk yolculuğunuzu tamamladıktan sonra buradan görebileceksiniz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
  
  // EHLİYET TÜRÜNÜ PANELDEN ÇEK - YENİ FONKSİYON!
  Future<String> _getDriverLicenseTypeFromPanel() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      if (driverId == null) {
        return 'B'; // Varsayılan
      }
      
      print('📊 Panel den ehliyet turu cekiliyor: Surucu ID $driverId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_driver_details.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'fields': ['license_type', 'license_types'] // Her iki field de kontrol
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['driver'] != null) {
          final licenseType = data['driver']['license_type'] ?? 
                            data['driver']['license_types'] ?? 'B';
          print('✅ Panel den ehliyet turu alindi: $licenseType');
          return licenseType;
        }
      }
      
      print('⚠️ Panel den ehliyet turu alinamadi - varsayilan: B');
      return 'B';
      
    } catch (e) {
      print('❌ Ehliyet türü çekme hatası: $e');
      return 'B'; // Varsayılan
    }
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingTile(
            icon: Icons.person_outline,
            title: 'Profil Bilgileri',
            subtitle: 'Kişisel bilgilerinizi düzenleyin',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverProfileScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _buildSettingTile(
            icon: Icons.account_balance,
            title: 'IBAN Bilgileri',
            subtitle: 'Ödeme alacağınız banka hesabı',
            onTap: () => _showIbanDialog(),
          ),
          const Divider(height: 1),
          _buildSettingTile(
            icon: Icons.lock,
            title: 'Şifre Değiştir',
            subtitle: 'Giriş şifrenizi değiştirin',
            onTap: () => _showChangePasswordDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // DUYURULAR KALDIRILDI - BİLDİRİMLER WİDGET'INDA VAR!
          _buildSettingTile(
            icon: Icons.help,
            title: 'Yardım',
            subtitle: 'Sık sorulan sorular - Şoför desteği',
            onTap: () => _showHelpDialog(),
          ),
          const Divider(height: 1),
          _buildSettingTile(
            icon: Icons.support_agent,
            title: 'Şoför Desteği',
            subtitle: 'İletişim Bilgileri',
            onTap: () => _showSupportDialog(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFFFFD700), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.grey,
        ),
      ),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16) : null),
      onTap: onTap,
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Dil Seçimi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            RadioListTile<String>(
              title: const Text('Türkçe'),
              value: 'Türkçe',
              groupValue: _selectedLanguage,
              onChanged: (value) {
                setState(() {
                  _selectedLanguage = value!;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFFFD700),
            ),
            RadioListTile<String>(
              title: const Text('English'),
              value: 'English',
              groupValue: _selectedLanguage,
              onChanged: (value) {
                setState(() {
                  _selectedLanguage = value!;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              activeColor: const Color(0xFFFFD700),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showSecurityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Güvenlik Ayarları'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Şifre Değiştir'),
              onTap: () {
                Navigator.pop(context);
                _showChangePasswordDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Biyometrik Giriş'),
              trailing: Switch(
                value: false,
                onChanged: (value) {},
                activeColor: const Color(0xFFFFD700),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  void _showIbanDialog() {
    // IBAN sahibi adı sürücü adından gelir (değiştirilemez)
    final ibanOwnerName = _driverName ?? 'Yükleniyor...';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.account_balance, color: Color(0xFFFFD700)),
            const SizedBox(width: 8),
            const Text('IBAN Bilgileri'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IBAN Sahibi Adı (Değiştirilemez)
              const Text(
                'IBAN Sahibi',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 20, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ibanOwnerName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.lock, size: 16, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // IBAN Numarası (Düzenlenebilir)
              const Text(
                'IBAN Numarası',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanController,
                decoration: InputDecoration(
                  hintText: 'TR00 0000 0000 0000 0000 0000 00',
                  prefixIcon: const Icon(Icons.credit_card, color: Color(0xFFFFD700)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFFFD700), width: 2),
                  ),
                ),
                maxLength: 32,
                textCapitalization: TextCapitalization.characters,
              ),
              
              // Bilgilendirme
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ödemeleriniz bu IBAN\'a yapılacaktır. IBAN sahibi adı profil bilgilerinizden otomatik alınmaktadır.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => _saveIban(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _saveIban() async {
    final iban = _ibanController.text.trim().toUpperCase();
    
    if (iban.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('IBAN numarası boş olamaz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // TR kontrolü
    if (!iban.startsWith('TR')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('IBAN TR ile başlamalıdır'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      if (driverId == null) {
        throw Exception('Sürücü ID bulunamadı');
      }
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_driver_iban.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'iban': iban,
          'iban_owner_name': _driverName,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _driverIban = iban;
          });
          
          Navigator.pop(context);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('IBAN bilgileri başarıyla kaydedildi'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(data['message'] ?? 'Kayıt başarısız');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Şifre Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mevcut Şifre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre Tekrar',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              currentPasswordController.dispose();
              newPasswordController.dispose();
              confirmPasswordController.dispose();
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => _changePassword(
              currentPasswordController.text,
              newPasswordController.text,
              confirmPasswordController.text,
              currentPasswordController,
              newPasswordController,
              confirmPasswordController,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Değiştir'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
    TextEditingController currentController,
    TextEditingController newController,
    TextEditingController confirmController,
  ) async {
    // Validasyon
    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tüm alanları doldurunuz'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeni şifreler eşleşmiyor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeni şifre en az 6 karakter olmalıdır'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? prefs.getString('admin_user_id');
      
      if (driverId == null) {
        throw Exception('Sürücü ID bulunamadı');
      }
      
      debugPrint('🔐 Şifre değiştirme - Driver ID: $driverId');
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/update_driver_password.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('📥 Şifre API Response: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Navigator.pop(context);
          
          // Controller'ları temizle
          currentController.dispose();
          newController.dispose();
          confirmController.dispose();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Şifre başarıyla değiştirildi'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception(data['message'] ?? 'Şifre değiştirilemedi');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Şifre değiştirme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showHelpDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Şoför Yardım Merkezi',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildHelpItem(
              'Nasıl çevrimiçi olurum?',
              'Ana sayfada "Çevrimdışı" butonuna tıklayın. Çevrimiçi olduğunuzda sistem size otomatik olarak yolculuk talepleri gönderecektir. Konum izninizi açık tutmanız önemlidir.',
            ),
            _buildHelpItem(
              'Yolculuk nasıl kabul edilir?',
              'Yeni talep geldiğinde ekranınızda popup açılır. "KABUL ET" butonuna basarak yolculuğu kabul edebilirsiniz. 30 saniye içinde karar vermeniz gerekmektedir.',
            ),
            _buildHelpItem(
              'Kazancım nasıl hesaplanır?',
              'Brüt ücret = Mesafe + Bekleme ücreti + Saatlik paket\nKomisyon = Brüt × 30%\nNet Kazancınız = Brüt - Komisyon\n\nÖrnek: ₺3,000 yolculuk → %30 komisyon (₺900) → Net kazancınız ₺2,100',
            ),
            _buildHelpItem(
              'Bekleme ücreti nasıl işler?',
              'Müşteri arabasını bekletirse:\n• İlk 15 dakika: Ücretsiz\n• 16-30 dakika: +₺200 (brüt)\n• 31-45 dakika: +₺400 (brüt)\n\nBekleme ücreti toplam fiyata eklenir ve %30 komisyon tüm tutardan kesilir.',
            ),
            _buildHelpItem(
              'Saatlik paket nedir?',
              'Normal yolculuk 2 saati geçerse otomatik saatlik pakete dönüşür:\n• 0-4 saat: ₺3,000\n• 4-8 saat: ₺4,500\n• 8-12 saat: ₺6,000\n• 12+ saat: Devam eden paketler\n\nSaatlik pakette KM ve bekleme ÜCRETSİZ!',
            ),
            _buildHelpItem(
              'Köprü arama nedir?',
              'Müşteri ile görüşmeniz gerektiğinde "Ara" butonuna basın. Şirket hattımız (0216 606 45 10) sizi otomatik olarak müşteri ile bağlar. Numaranız gizli kalır.',
            ),
            _buildHelpItem(
              'Puanlama sistemi nasıl çalışır?',
              'Her yolculuk sonunda müşteriler sizi 1-5 yıldız arasında değerlendirir. Ortalama puanınız 4.5\'in üzerinde olmalıdır. Düşük puanlar hesabınızın askıya alınmasına sebep olabilir.',
            ),
            _buildHelpItem(
              'Ödemeler ne zaman yapılır?',
              'Kazançlarınız her hafta Pazartesi ile Çarşamba günü arasında banka hesabınıza otomatik olarak aktarılır. Panel\'den IBAN bilgilerinizi güncel tutmanız önemlidir.',
            ),
            const Divider(height: 32),
            const Text(
              'İletişim Kanalları',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildContactButton(
                  icon: Icons.phone,
                  label: 'Telefon',
                  color: Colors.green,
                  onTap: () async {
                    final phone = _supportPhone ?? '0533 448 82 53';
                    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
                    await launchUrl(uri);
                  },
                ),
                _buildContactButton(
                  icon: Icons.mail,
                  label: 'E-posta',
                  color: Colors.blue,
                  onTap: () async {
                    final email = _supportEmail ?? 'destek@funbreakvale.com';
                    final uri = Uri.parse('mailto:$email');
                    await launchUrl(uri);
                  },
                ),
                _buildContactButton(
                  icon: Icons.message,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () async {
                    final whatsapp = _whatsappNumber ?? '0533 448 82 53';
                    String cleanNumber = whatsapp.replaceAll(' ', '');
                    if (cleanNumber.startsWith('0')) {
                      cleanNumber = '90${cleanNumber.substring(1)}';
                    }
                    final uri = Uri.parse('https://wa.me/$cleanNumber');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(String title, String content) {
    return ListTile(
      leading: const Icon(Icons.help_outline, color: Color(0xFFFFD700)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.info, color: Color(0xFFFFD700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Anladım',
                  style: TextStyle(color: Color(0xFFFFD700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // DUYURULAR EKRANI - PANEL ENTEGRE!
  void _showAnnouncementsScreen() async {
    print('📢 Şoför duyuruları açılıyor - panel entegrasyonu');
    
    try {
      // Panel'den şoför duyurularını çek
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/get_driver_announcements.php'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      List<Map<String, dynamic>> announcements = [];
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['announcements'] != null) {
          announcements = List<Map<String, dynamic>>.from(data['announcements']);
        }
      }
      
      // Duyuru ekranını göster
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'Şoför Duyuruları',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              // Duyuru listesi
              Expanded(
                child: announcements.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Henüz duyuru bulunmuyor',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: announcements.length,
                        itemBuilder: (context, index) {
                          final announcement = announcements[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFFFD700),
                                child: Icon(Icons.campaign, color: Colors.white),
                              ),
                              title: Text(
                                announcement['title'] ?? 'Duyuru',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(announcement['content'] ?? ''),
                                  const SizedBox(height: 4),
                                  Text(
                                    announcement['created_at'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
      
    } catch (e) {
      print('❌ Duyuru yükleme hatası: $e');
      
      // Hata durumunda basit dialog göster
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Duyurular'),
          content: const Text('Duyurular şu anda yüklenemiyor. Daha sonra tekrar deneyin.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    }
  }

  void _showSupportDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Şoför Desteği',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone, color: Colors.green),
              ),
              title: const Text('Acil Destek Hattı'),
              subtitle: Text(DynamicContactService.getSupportPhone()),
              onTap: () => _callSupport(DynamicContactService.getSupportPhone()),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.email, color: Colors.blue),
              ),
              title: const Text('E-posta Desteği'),
              subtitle: Text(DynamicContactService.getSupportEmail()),
              onTap: () => _emailSupport(DynamicContactService.getSupportEmail()),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.message, color: Colors.green),
              ),
              title: const Text('WhatsApp Desteği'),
              subtitle: Text(DynamicContactService.getWhatsAppNumber()),
              onTap: () => _whatsappSupport(DynamicContactService.getWhatsAppNumber()),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_taxi,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'FunBreak Vale Şoför',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Versiyon 1.0.0',
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Profesyonel şoför uygulaması',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Container(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              await authProvider.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Çıkış Yap',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  void _callSupport(String phoneNumber) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Aranıyor: $phoneNumber'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'TAMAM',
          onPressed: () {},
          textColor: Colors.white,
        ),
      ),
    );
    // TODO: url_launcher ile telefon açma implementasyonu
  }

  void _emailSupport(String email) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('E-posta açılıyor: $email'),
        backgroundColor: Colors.blue,
        action: SnackBarAction(
          label: 'TAMAM',
          onPressed: () {},
          textColor: Colors.white,
        ),
      ),
    );
    // TODO: url_launcher ile email açma implementasyonu
  }

  void _whatsappSupport(String phoneNumber) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('WhatsApp açılıyor: $phoneNumber'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'TAMAM',
          onPressed: () {},
          textColor: Colors.white,
        ),
      ),
    );
    // TODO: url_launcher ile WhatsApp açma implementasyonu
  }
}
