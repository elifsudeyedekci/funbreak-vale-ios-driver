import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../home/driver_home_screen.dart';

/// SÜRÜCÜ YASAL SÖZLEŞME ONAY EKRANI
/// İlk giriş yapan sürücülere gösterilir
/// 4 sözleşme onayı gerekli:
/// 1. Vale Kullanım Koşulları Sözleşmesi
/// 2. KVKK Aydınlatma Metni
/// 3. Özel Nitelikli Kişisel Verilerin İşlenmesine Dair Açık Rıza Beyanı
/// 4. Açık Rıza Beyanı
class DriverLegalConsentScreen extends StatefulWidget {
  const DriverLegalConsentScreen({Key? key}) : super(key: key);

  @override
  State<DriverLegalConsentScreen> createState() => _DriverLegalConsentScreenState();
}

class _DriverLegalConsentScreenState extends State<DriverLegalConsentScreen> {
  bool _isLoading = false;
  bool _usageTermsAccepted = false;
  bool _kvkkAccepted = false;
  bool _specialDataAccepted = false;
  bool _openConsentAccepted = false;
  
  // Sözleşme okuma durumları
  bool _usageTermsRead = false;
  bool _kvkkRead = false;
  bool _specialDataRead = false;
  bool _openConsentRead = false;

  bool get _allAccepted => 
      _usageTermsAccepted && _kvkkAccepted && _specialDataAccepted && _openConsentAccepted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(Icons.gavel, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text(
              'Sözleşme Onayları',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Bilgilendirme Banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFFFD700), size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hoş Geldiniz, Vale!',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Platformumuzu kullanmaya başlamadan önce aşağıdaki sözleşmeleri okumanız ve onaylamanız gerekmektedir.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Sözleşme Listesi
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // 1. Vale Kullanım Koşulları
                    _buildContractCard(
                      title: 'Vale Kullanım Koşulları Sözleşmesi',
                      subtitle: '19 Madde • Zorunlu',
                      icon: Icons.description,
                      isAccepted: _usageTermsAccepted,
                      isRead: _usageTermsRead,
                      onTap: () => _showContractDialog(
                        'Vale Kullanım Koşulları Sözleşmesi',
                        _getUsageTermsText(),
                        () {
                          setState(() {
                            _usageTermsRead = true;
                          });
                        },
                      ),
                      onAcceptChanged: _usageTermsRead ? (value) {
                        setState(() {
                          _usageTermsAccepted = value ?? false;
                        });
                      } : null,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 2. KVKK Aydınlatma Metni
                    _buildContractCard(
                      title: 'KVKK Aydınlatma Metni',
                      subtitle: 'Kişisel Verilerin Korunması • Zorunlu',
                      icon: Icons.security,
                      isAccepted: _kvkkAccepted,
                      isRead: _kvkkRead,
                      onTap: () => _showContractDialog(
                        'KVKK Aydınlatma Metni',
                        _getKVKKText(),
                        () {
                          setState(() {
                            _kvkkRead = true;
                          });
                        },
                      ),
                      onAcceptChanged: _kvkkRead ? (value) {
                        setState(() {
                          _kvkkAccepted = value ?? false;
                        });
                      } : null,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 3. Özel Nitelikli Kişisel Veriler
                    _buildContractCard(
                      title: 'Özel Nitelikli Kişisel Veriler Açık Rıza',
                      subtitle: 'Sağlık, Adli Sicil, Görsel Veriler • Zorunlu',
                      icon: Icons.fingerprint,
                      isAccepted: _specialDataAccepted,
                      isRead: _specialDataRead,
                      onTap: () => _showContractDialog(
                        'Özel Nitelikli Kişisel Verilerin İşlenmesine Dair Açık Rıza Beyanı',
                        _getSpecialDataText(),
                        () {
                          setState(() {
                            _specialDataRead = true;
                          });
                        },
                      ),
                      onAcceptChanged: _specialDataRead ? (value) {
                        setState(() {
                          _specialDataAccepted = value ?? false;
                        });
                      } : null,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 4. Açık Rıza Beyanı
                    _buildContractCard(
                      title: 'Açık Rıza Beyanı',
                      subtitle: 'Genel Veri İşleme Onayı • Zorunlu',
                      icon: Icons.verified_user,
                      isAccepted: _openConsentAccepted,
                      isRead: _openConsentRead,
                      onTap: () => _showContractDialog(
                        'Açık Rıza Beyanı',
                        _getOpenConsentText(),
                        () {
                          setState(() {
                            _openConsentRead = true;
                          });
                        },
                      ),
                      onAcceptChanged: _openConsentRead ? (value) {
                        setState(() {
                          _openConsentAccepted = value ?? false;
                        });
                      } : null,
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Uyarı
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sözleşmeleri okumadan onaylayamazsınız. Her sözleşmeye tıklayarak okuyun.',
                              style: TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 100), // Buton için boşluk
                  ],
                ),
              ),
              
              // Onay Butonu
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_allAccepted && !_isLoading) ? _submitConsents : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _allAccepted 
                            ? const Color(0xFFFFD700) 
                            : Colors.grey[700],
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.grey[800],
                        disabledForegroundColor: Colors.grey[500],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _allAccepted ? Icons.check_circle : Icons.lock,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _allAccepted 
                                      ? 'Sözleşmeleri Onayla ve Devam Et' 
                                      : 'Tüm Sözleşmeleri Okuyun ve Onaylayın',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContractCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isAccepted,
    required bool isRead,
    required VoidCallback onTap,
    required ValueChanged<bool?>? onAcceptChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted 
              ? const Color(0xFF4CAF50) 
              : isRead 
                  ? const Color(0xFFFFD700).withOpacity(0.5)
                  : Colors.grey.withOpacity(0.3),
          width: isAccepted ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Sözleşme Başlığı - Tıklanabilir
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAccepted 
                          ? const Color(0xFF4CAF50).withOpacity(0.2)
                          : const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: isAccepted 
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFFD700),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                            if (isRead) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Okundu',
                                  style: TextStyle(
                                    color: Color(0xFF4CAF50),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFFFD700),
                  ),
                ],
              ),
            ),
          ),
          
          // Onay Checkbox
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isAccepted,
                    onChanged: onAcceptChanged,
                    activeColor: const Color(0xFF4CAF50),
                    checkColor: Colors.white,
                    side: BorderSide(
                      color: isRead ? const Color(0xFFFFD700) : Colors.grey,
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isRead 
                        ? 'Okudum, anladım ve kabul ediyorum'
                        : 'Önce sözleşmeyi okuyun',
                    style: TextStyle(
                      color: isRead ? Colors.white : Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showContractDialog(String title, String content, VoidCallback onRead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, color: Color(0xFFFFD700)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              
              // Okudum Butonu
              Container(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      onRead();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Okudum, Anladım',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitConsents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? '0';
      
      // Konum al
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        print('⚠️ Konum alınamadı: $e');
      }
      
      // Cihaz bilgisi al
      final deviceInfo = DeviceInfoPlugin();
      String deviceModel = 'Unknown';
      String osVersion = 'Unknown';
      String deviceId = 'Unknown';
      
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
          osVersion = 'Android ${androidInfo.version.release}';
          deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceModel = iosInfo.model;
          osVersion = 'iOS ${iosInfo.systemVersion}';
          deviceId = iosInfo.identifierForVendor ?? 'Unknown';
        }
      } catch (e) {
        print('⚠️ Cihaz bilgisi alınamadı: $e');
      }
      
      // 4 sözleşme için log gönder
      final contracts = [
        {'type': 'driver_usage_terms', 'text': _getUsageTermsText()},
        {'type': 'driver_kvkk', 'text': _getKVKKText()},
        {'type': 'driver_special_data_consent', 'text': _getSpecialDataText()},
        {'type': 'driver_open_consent', 'text': _getOpenConsentText()},
      ];
      
      for (final contract in contracts) {
        try {
          final response = await http.post(
            Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': int.parse(driverId),
              'user_type': 'driver',
              'consent_type': contract['type'],
              'consent_text': contract['text'],
              'consent_version': '1.0',
              'latitude': position?.latitude,
              'longitude': position?.longitude,
              'location_accuracy': position?.accuracy,
              'platform': Platform.isAndroid ? 'Android' : 'iOS',
              'os_version': osVersion,
              'app_version': '1.0.0',
              'device_model': deviceModel,
              'device_fingerprint': deviceId,
            }),
          ).timeout(const Duration(seconds: 15));
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true) {
              print('✅ ${contract['type']} log kaydedildi - Log ID: ${data['log_id']}');
            }
          }
        } catch (e) {
          print('❌ ${contract['type']} log hatası: $e');
        }
      }
      
      // Yerel kayıt - sözleşmeler onaylandı
      await prefs.setBool('driver_contracts_accepted', true);
      await prefs.setString('driver_contracts_accepted_date', DateTime.now().toIso8601String());
      
      // Ana sayfaya yönlendir
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
        );
      }
      
    } catch (e) {
      print('❌ Sözleşme onay hatası: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bir hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // =====================================================
  // SÖZLEŞME METİNLERİ
  // =====================================================

  String _getUsageTermsText() {
    return '''FUNBREAK VALE
VALE KULLANIM KOŞULLARI SÖZLEŞMESİ

═══════════════════════════════════════════════════

1. TARAFLAR

İşbu Mobil Uygulama Kullanım Sözleşmesi (Bundan böyle "Sözleşme" olarak anılacaktır.) Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI (Bundan böyle "FunBreak Vale" veya "Şirket" olarak anılacaktır.) ile FunBreak Vale mobil uygulaması üzerinden yolcuları taşıyan sürücü (Bundan böyle "Vale" olarak anılacaktır) arasındadır.

═══════════════════════════════════════════════════

2. SÖZLEŞMENİN AMACI VE KONUSU

2.1. İşbu Sözleşme'nin konusu, yolcu için özel şoför ve vale bulma hizmetini sunan FunBreak Vale ile Vale arasındaki mobil uygulama ("Mobil Uygulama") ve web platformu kullanımına ilişkin hak ve yükümlülükleri belirtmektedir.

2.2. FunBreak Vale, Yolcu ile Vale arasında aracılık hizmeti sunan bir teknoloji platformudur. FunBreak Vale, Vale ile herhangi bir işçi-işveren ilişkisi kurmamakta olup, Vale bağımsız çalışan statüsünde hizmet vermektedir.

═══════════════════════════════════════════════════

3. FUNBREAK VALE'NİN KULLANIMI VE TAAHHÜTLER

3.1. Kayıt ve Kabul Koşulları

3.1.1. FunBreak Vale platformu üzerinden yolcuları belirttikleri konumlara transfer ederek gelir elde etmek isteyen Vale adayları, işbu Sözleşme'yi ve FunBreak Vale'nin belirttiği şartları taşımak zorundadır.

3.1.2. Vale adayları en az 21 yaşında olmalı, en az 3 yıl sürücülük deneyimine sahip olmalı ve herhangi bir sürücülük yetersizliği bulunmamalıdır.

3.1.3. Şartları taşıdığını düşünen ve Sözleşme'yi uymayı taahhüt eden Vale adaylarının başvuruları FunBreak Vale'nin belirleyeceği şekilde web sayfası, mobil uygulama veya fiziki olarak alınır ve FunBreak Vale tarafından incelenir.

3.1.4. Vale adayları kayıt esnasında ve FunBreak Vale tarafından belirlenecek periyodlarda aşağıdaki bilgi ve belgeleri FunBreak Vale'ye teslim etmeyi taahhüt eder:

a. Kimlik Bilgisi: Vale'nin kimliğinin tespiti ve hukuki sözleşmelerin tarafı olabilmesi için T.C. Kimlik Kartı'nın veya Nüfus Cüzdanı'nın fiziki veya dijital bir nüshasının FunBreak Vale'ye teslimi gerekir.

b. Ehliyet Belgesi: FunBreak Vale'de Vale'lik yapacak olan sürücülerin Yolcu'nun sahip olduğu aracı kullanabilmesi mümkün olması gerekir. B sınıfı sürücü belgesine sahip olunması ve ehliyetin herhangi bir sınırlamadan ari olması gerekir. En az 3 yıl sürücülük deneyimi bulunmalıdır.

c. Sağlık Raporu: Güvenli sürüş deneyimi için sürücünün sağlığının yerinde olduğunu gösteren ve yetkili sağlık kuruluşundan alınmış güncel sağlık raporunun (son 6 ay içinde alınmış) FunBreak Vale'ye teslimi gerekir.

d. Adli Sicil Kaydı: Vale'nin sürücülük yapmasını engelleyen herhangi bir hak mahkumiyeti veya ceza almamış olduğunun tespiti için e-Devlet üzerinden alınmış güncel Adli Sicil Kaydı'nın (son 3 ay içinde alınmış) FunBreak Vale'ye teslimi gerekir.

e. Ceza Puanı Bilgisi: FunBreak Vale aracı platform da olsa doğru Yolcu ile doğru Vale'nin eşleşmesini önemser ve bu kapsamda ilgili transferin tüm trafik kurallarına uygun olarak gerçekleşmesini temenni eder. Bu doğrultuda e-Devlet üzerinden alınmış güncel ceza puanı bilgisinin FunBreak Vale ile paylaşılması Vale'nin seçiminde önem arz eder. Ceza puanı 70 ve üzerinde olan Vale adayları kabul edilmez.

f. Ödeme Bilgisi (IBAN): FunBreak Vale, Yolcu ile Vale arasındaki mali konulara da aracılık ettiği için Vale'nin gelen ödemeleri teslim alabilmesi için güncel, doğru ve hak mahremiyeti olmayan T.C. kimlik numarasına kayıtlı IBAN bilgisinin FunBreak Vale'ye teslimi gerekir. IBAN bilgisi Vale'nin şahsına ait olmalıdır.

g. İkametgah Belgesi: Vale'nin ikametgah adresinin tespiti için e-Devlet üzerinden alınmış güncel İkametgah Belgesi'nin (son 3 ay içinde alınmış) FunBreak Vale'ye sunulması gerekir.

h. Referans Bilgisi: Vale adayının daha önceki çalışma tecrübelerine dair referans kişi bilgileri (ad-soyad, telefon) FunBreak Vale tarafından talep edilebilir.

3.1.5. Vale, kayıt esnasında verdiği tüm bilgi ve belgelerin doğru, eksiksiz, güncel ve kendisine ait olduğunu kabul, beyan ve taahhüt eder. Sahte, yanıltıcı veya eksik bilgi verilmesi durumunda FunBreak Vale hiçbir gerekçe göstermeksizin başvuruyu reddedebilir veya mevcut hesabı kapatabilir.

═══════════════════════════════════════════════════

4. VALE'NİN YÜKÜMLÜLÜKLERİ

4.1. FunBreak Vale'ye İlişkin Yükümlülükler

Vale, aşağıdaki hususları kabul, beyan ve taahhüt eder:

4.1.1. FunBreak Vale'yi aktif bir şekilde kullanmayı, ulaşılabilir ve erişilebilir olmayı,
4.1.2. Kendisine gönderilen transfer taleplerini makul süre içerisinde değerlendirmeyi ve kabul ettiği transferleri mücbir sebepler haricinde gerçekleştirmeyi,
4.1.3. Transfer talebinin kabul edilmesi halinde en kısa zamanda Yolcu ile iletişime geçmeyi, süreç hakkında Yolcu'yu bilgilendirmeyi,
4.1.4. Yolcu'nun alım noktasına belirlenen zamanda varmayı (rezervasyonlarda) veya en kısa sürede varmayı (anında valelerde),
4.1.5. Transfer aşamasında asla kendi aracını kullanmamayı, bu durumun mevcut hizmetin hukuki statüsünü değiştireceğini ve hizmetin Vale tarafından asla kabul edilmeyeceğini. Vale, Yolcu'nun aracını kullanarak hizmeti yerine getirecektir,
4.1.6. Transfer işlemini bizzat kendisi gerçekleştirmeyi, başka bir sürücüye devretmemeyi,
4.1.7. Yolcu'nun alımında ve transfer noktasına aktarımında FunBreak Vale'yi sistemde güncel konum ile bilgilendirmeyi (GPS takibi aktif olacak),
4.1.8. FunBreak Vale tarafından belirlenen ücret tarifeleri dışında herhangi bir ücret talep etmemeyi veya bildirimde bulunmamayı,
4.1.9. FunBreak Vale tarafından alınan konumun yanlış olabileceğini ve bu kapsamda gerçek konumun FunBreak Vale sistemi ile sürekli olarak paylaşmayı (otomatik GPS tracking),
4.1.10. Yolculuk süresince rota takibinin (route tracking) ve bekleme noktalarının (waiting points) otomatik olarak kaydedileceğini ve bu bilgilerin Yolcu, FunBreak Vale ve gerekirse yetkili mercilerle paylaşılabileceğini,
4.1.11. Bekleme işlemini başlatırken sistemde "Bekleme Başlat" butonuna basarak süreci kayıt altına almayı, bekleme süresince araç ile hareket etmemeyi, bekleme bittiğinde "Bekleme Durdur" butonuna basmayı,
4.1.12. Yolculuk tamamlandığında sistem üzerinden "Yolculuğu Tamamla" butonuna basarak bırakma konumunu (dropoff location) kaydetmeyi,
4.1.13. Mobil uygulamanın her zaman güncel versiyonunu kullanmayı, güncelleme bildirimleri geldiğinde en kısa sürede uygulamayı güncellemeyi.

4.2. Yolcu'ya Karşı Yükümlülükler

Vale, aşağıdaki hususları kabul, beyan ve taahhüt eder:

4.2.1. Yolcu ile FunBreak Vale'de belirlenen zamanda buluşmayı ve hedeflenen süre içerisinde hedeflenen konuma transfer etmeyi,
4.2.2. Transfer süresinde Yolcu'yu rahatsız edecek davranışlardan kaçınmayı, Yolcu'nun alkolü, yorgun veya kötü durumda olma ihtimaline karşı gerekli sabrı ve hassasiyeti göstermeyi,
4.2.3. Yolcu'ya karşı eylemlerinin suç unsuru oluşturmayacağını, kamuya açıklanamayacağını ve uygulamada olan herhangi bir yasayı çiğnemeyeceğini,
4.2.4. Yolcu'nun mahremiyet hakkına tecavüz edici, yanlış, yanıltıcı, onur kırıcı, iftira atıcı, leke sürücü, müstehcen, kaba ya da saldırgan girişimde bulunmayacağını,
4.2.5. Yolcu ile sistemdeki mesajlaşma özelliğini kullanarak iletişim kurmayı, kişisel telefon numarasını paylaşmamayı (köprü arama sistemi üzerinden arama yapılacak),
4.2.6. Yolcu'nun aracına özen göstermeyi, araç içinde sigara içmemeyi, yeme-içme yapmamayı, aracı kirletmemeyi,
4.2.7. Trafik kurallarına tam olarak uymayı, hız sınırlarını aşmamayı, güvenli sürüş yapmayı,
4.2.8. Yolcu'nun özel eşyalarına dokunmamayı, izinsiz müdahalede bulunmamayı.

4.3. Kaza Sorumluluğu

4.3.1. Vale'nin transfer sürecinde kendi kusurundan dolayı kaza yapması halinde sorumluluğun Vale'de olduğunu, FunBreak Vale'nin herhangi bir sorumluluğunun bulunmadığını kabul eder.
4.3.2. Vale'den kaynaklı olmayan nedenlerle (üçüncü kişi kusuru, mücbir sebep vb.) kaza olması durumunda Vale'nin kazaya ilişkin sorumluluktan kaçınabileceğini, ancak ilgili kazanın FunBreak Vale ile ilişkilendirilmeyeceğini Vale tarafından kabul edilmiştir.
4.3.3. Vale, kaza anında derhal FunBreak Vale'yi ve Yolcu'yu bilgilendirmeyi, gerekli yasal prosedürleri (trafik polisi, ambulans vb.) yerine getirmeyi taahhüt eder.
4.3.4. Kaza sonrası Vale, kaza tutanağını ve ilgili belgeleri FunBreak Vale ile paylaşmayı kabul eder.

4.4. Ceza Sorumluluğu

4.4.1. Vale, trafik cezaları konusunda, cezai soruşturma gerektiren hususlarda, Vale'nin Yolcu'ya veya Yolcu'nun Vale'ye karşı davranışlarında, Vale'nin veya Yolcu'nun yasaklı madde, göçmen kaçakçılığı veya benzeri suç konularına karışması durumunda ve herhangi bir işleme ilişkin olarak aracılık hizmeti sağlayıcı olması kapsamında FunBreak Vale'nin herhangi bir sorumluluğu olmadığını ve FunBreak Vale'ye karşı hiçbir hak ve tazmin talebinde bulunmayacağını kabul, beyan ve taahhüt eder.
4.4.2. Transfer sırasında alınan trafik cezaları, Vale'nin sürüş esnasında oluşmuşsa Vale'nin sorumluluğundadır ve ceza bedelini ödemeyi taahhüt eder.

═══════════════════════════════════════════════════

5. VALE'NİN HAK VE YÜKÜMLÜLÜKLERİ

5.1. Vale, mobil uygulamada yer alan tüm sözleşme hükümlerine uygun hareket edeceğini, FunBreak Vale tarafından belirlenen usule uyacağını kabul, beyan ve taahhüt eder.

5.2. Vale, yetkisi dışında bulunan veya yerine getirme gücü olmayan işlemlere tevessül etmeyeceğini, bu tür teklif ve kabullerde bulunmayacağını ve yaptığı her işlemde dürüst, iyi niyetli ve tedbirli davranacağını, sistemi kullanırken, sistemin işleyişini engelleyici veya zorlaştırıcı şekilde davranmayacağını kabul, beyan ve taahhüt eder.

5.3. FunBreak Vale'ye kayıt olan Vale, işbu Sözleşme'de belirtilen veya güncel uygulama protokolü ile FunBreak Vale tarafından düzenlenecek genel, mobil uygulamaya özgü olan ücret ve ödeme politikasını, dönemsel kampanyaları ve komisyon oranlarını, ücret ve ödeme politikasına karşı itirazda bulunmayacaklarını ve buna bir itiraz konusu halinde getirmeyeceklerini, getirilmesi durumunda 100.000,00 TL tutarında cezai şart ödemeyi peşinen kabul, beyan ve taahhüt eder.

5.4. Vale, beklenmeyen hizmet kesintilerinden, planlara uyulamamasından, değerlendirmelerde yetkisiz erişim veya ifşasından, değerlendirmelerin bütünlüğünün bozulmasından veya benzeri durumlardan dolayı doğrudan ve dolaylı zararlardan sorumludur.

5.5. Vale, FunBreak Vale içindeki faaliyetlerinde, FunBreak Vale'nin herhangi bir bilgilendirme veya işlemlerinde yer almayacak ve itibarına aykırı, 3. kişilerin haklarını zedeleyen, ahlaka aykırı, saldırgan, müstehcen, pornografik, kişilik haklarını zedeleyen faaliyetlerde bulunmayacaklarını kabul eder.

5.6. İşbu Sözleşme'nin tarafı olan Vale, işbu Sözleşme'den doğan yükümlülüklerini ihlal etmesi veya işbu sözleşme hükümlerine aykırı hareket etmesi durumunda, FunBreak Vale'nin, Yolcu'nun veya üçüncü kişilerin doğan zararlarını doğrudan karşılamaktan sorumludur.

5.7. Vale, müşteri memnuniyeti için minimum 3.5 yıldız puanı korumayı taahhüt eder. Puan ortalaması sürekli olarak 3.5'in altına düşerse FunBreak Vale, Vale ile olan iş akdine son verme hakkını saklı tutar.

5.8. Vale, yolculuk tamamlandıktan sonra sistem üzerinden hesaplanan ücretten %30 ücret kesintisi yapılacağını, kalan tutarın haftalık dönemlerde kendisine ödeneceğini kabul eder. Ödemeler her Pazartesi günü, bir önceki hafta (Pazartesi-Pazar) tamamlanan yolculuklar için Vale'nin kayıtlı IBAN'ına havale edilir.

═══════════════════════════════════════════════════

6. FUNBREAK VALE'NİN HAK VE YÜKÜMLÜLÜKLERİ

6.1. FunBreak Vale, işbu Sözleşme'nin tarafı olan Vale'nin başvurularını reddetme hakkını saklı tutacağı gibi, herhangi bir sebeple Vale'nin daha sonrasında hesabını durdurma veya silme hakkını da saklı tutmaktadır.

6.2. FunBreak Vale, Vale'nin denetimini yapmakla sorumlu olmasa da Vale'nin siparişlerini onaylamamakta veya iptal etmekte serbesttir.

6.3. FunBreak Vale, web sayfasında ve mobil uygulamasında bulunan yazılı, görsel veya videolu içeriklerin hak sahibidir.

6.4. FunBreak Vale, web sayfasını veya mobil uygulamanın kullanım alanlarını, teknik özelliklerini, yapısını, konseptini, içeriğini değiştirebilir.

6.5. FunBreak Vale veya FunBreak Vale'nin vermiş olduğu hizmetlerle bağlantılı iştirakleri veya uygulamaları ve altyapıları üzerinde her tür kullanım ve tasarruf yetkisi FunBreak Vale'ye aittir.

6.6. FunBreak Vale, Vale'lerin performansını izleme, değerlendirme ve raporlama hakkına sahiptir.

6.7. FunBreak Vale, platformda güvenlik ve kalite standartlarını korumak amacıyla Vale'lerin yolculuklarını rastgele veya şüpheli durumlarda inceleme hakkına sahiptir.

═══════════════════════════════════════════════════

7. GİZLİLİK VE REKABET YASAĞI

7.1. Vale işbu Sözleşme çerçevesinde öğrendikleri gizli bilgileri, verileri veya belgeleri bunlara ait tüm bilgileri, verileri ve belgeleri, fikri ve sınai hakları, varlıkları ve sair her türlü maddi ve manevi nitelikte varlıkları, FunBreak Vale'nin yazılı izni olmadan üçüncü kişilere açıklayamaz, paylaşamaz ve ifşa edemez.

7.2. Vale, FunBreak Vale sistemi üzerinden edindiği Yolcu iletişim bilgilerini (telefon, e-posta vb.) sistem dışında kullanmayacağını, Yolcu'yu doğrudan veya dolaylı olarak başka bir platforma veya hizmete yönlendirmeyeceğini kabul eder.

7.3. Vale, FunBreak Vale ile rekabet edecek şekilde benzer bir platform kurma veya benzer hizmetler sunma faaliyetinde bulunmayacağını, bu Sözleşme'nin yürürlükte olduğu süre ve sona ermesinden sonraki 2 (iki) yıl boyunca FunBreak Vale ile doğrudan rekabet eden bir platformda çalışmayacağını kabul eder.

═══════════════════════════════════════════════════

8. KİŞİSEL VERİLERİN KORUNMASI

8.1. Vale, kayıt esnasında kabul ettikleri FunBreak Vale'de yer alan Kişisel Verilerin Korunması ve İşlenmesi Politikası ve KVKK Aydınlatma Metni kapsamında Kişisel Verilerinin işleneceğini kabul eder.

8.2. Vale, yolculuk sırasında kaydedilen GPS konum bilgilerinin, rota takip verilerinin (route tracking), bekleme noktası bilgilerinin (waiting points) ve bırakma konum bilgilerinin (dropoff location) FunBreak Vale tarafından saklanacağını kabul eder.

═══════════════════════════════════════════════════

9. SÖZLEŞMENİN SÜRESİ VE FESİH HAKKI

9.1. İşbu Sözleşme süresiz olarak düzenlenmiştir. FunBreak Vale e-posta yoluyla veya yazılı bir bildirimde bulunarak ve bir süre tayinine gerek olmaksızın önceden bildirmeksizin istediği zaman sözleşmeyi fesih hakkına sahiptir.

9.2. Vale, üyeliğini tek taraflı olarak iptal etse veya üyeliği FunBreak Vale tarafından durdurulsa/askıya alınsa/sonlandırılsa dahi, bu iptal işleminden önce, üyeliği sırasında gerçekleştirdiği eylemlerinden, borçlarından gerek FunBreak Vale'ye gerekse diğer üçüncü kişi, kurum ve kuruluşlara karşı şahsen sorumlu olacaktır.

9.3. Üyeliğini iptal eden veya 30 (otuz) gün boyunca FunBreak Vale'ye giriş yapmayan ve işbu sözleşmedeki yükümlülükleri yerine getiremeyen Vale tüm haklarından feragat etmiş sayılır.

═══════════════════════════════════════════════════

10. İPTAL VE İADE POLİTİKASI

10.1. Vale Tarafından İptal:
Vale, kabul ettiği bir yolculuğu iptal etmek zorunda kalırsa (mücbir sebep hariç) herhangi bir ücret tahsil edemez ve FunBreak Vale sistem üzerinde uyarı kaydı oluşturabilir.

10.2. Yolcu Tarafından İptal:
• 45 dakika veya daha fazla kala iptal: Ücretsiz iptal. Vale'ye ödeme yapılmaz.
• 45 dakikadan az kala iptal: Yolcu 1.500,00 TL iptal ücreti öder. Bu ücretin %70'i Vale'ye aktarılır, %30'u FunBreak Vale komisyonu olarak kalır.

10.3. Mücbir Sebepler:
Mücbir sebep (ciddi hastalık, kaza, doğal afet vb.) halinde Vale iptal yapabilir ve herhangi bir yaptırıma tabi tutulmaz.

═══════════════════════════════════════════════════

11. ÜCRET VE ÖDEME SİSTEMİ

11.1. Ücretlendirme Sistemi:
FunBreak Vale, mesafe bazlı sabit fiyatlandırma (distance pricing) sistemi kullanır:
• 0-5 km: 1.500,00 TL
• 5-10 km: 1.700,00 TL
• 10-15 km: 1.900,00 TL
• 15-20 km: 2.100,00 TL
• 20-25 km: 2.300,00 TL
• 25-30 km: 2.500,00 TL
• 30-35 km: 2.700,00 TL
• 35-40 km: 2.900,00 TL

11.2. Bekleme Ücreti:
İlk 15 dakika bekleme ücretsizdir. 15 dakikadan sonra her 15 dakika veya kesri için 200,00 TL bekleme ücreti uygulanır.

11.3. Saatlik Paket Sistemi:
Normal vale yolculuğu 2 (iki) saat geçerse otomatik olarak saatlik pakete dönüşür:
• 0-4 saat: 3.000,00 TL
• 4-8 saat: 4.500,00 TL
• 8-12 saat: 6.000,00 TL

11.4. Komisyon:
Tüm yolculuklardan %30 komisyon FunBreak Vale tarafından kesilir. Vale, yolculuk ücretinin %70'ini alır.

11.5. Ödeme Dönemi:
Ödemeler haftalık olarak yapılır. Her Pazartesi günü, bir önceki hafta (Pazartesi-Pazar) tamamlanan yolculukların ödemesi Vale'nin kayıtlı IBAN'ına havale edilir.

═══════════════════════════════════════════════════

12. MÜCBİR SEBEPLER VE SORUMSUZLUK BEYANLARI

12.1. FunBreak Vale'nin kontrolü ve iradesi dışında gelişen ve makul denetim gücü dışında kalan durumlar mücbir sebep olarak değerlendirilecektir.

12.2. FunBreak Vale, mücbir sebep yüzünden yükümlülüklerini tam veya zamanında yerine getirememekten dolayı sorumlu tutulmayacaktır.

═══════════════════════════════════════════════════

13. TELİF HAKLARI

13.1. Vale, FunBreak Vale'ye yüklemiş olduğu içeriklere ilişkin telif ve her nevi haklarının korunmasına dair tüm yetkileri FunBreak Vale'ye vermiştir.

13.2. FunBreak Vale'nin web sayfasında veya mobil uygulamasında yer alan bilgiler hiçbir şekilde çoğaltılamaz, yayınlanamaz, kopyalanamaz.

═══════════════════════════════════════════════════

14. SÖZLEŞMENİN BÜTÜNLÜĞÜ VE DEĞİŞİKLİKLER

14.1. İşbu Sözleşme şartlarından biri, kısmen veya tamamen geçersiz hale gelirse, sözleşmenin geri kalan maddeleri geçerliliğini korumaya devam edecektir.

14.2. FunBreak Vale çeşitli zamanlarda mobil uygulamasında ve web sayfasında sunulan hizmetleri ve işbu sözleşme şartlarını kısmen veya tamamen değiştirebilir.

═══════════════════════════════════════════════════

15. TEBLİGAT

15.1. İşbu Sözleşme ile ilgili taraflara gönderilecek olan tüm bildirimler, FunBreak Vale'nin bilinen e-posta adresi (info@funbreakvale.com) ve Vale'nin üyelik formlarında belirttiği e-posta adresi vasıtasıyla yapılacaktır.

15.2. Vale, adresi değişirse bunu 5 (beş) gün içinde yazılı olarak diğer tarafa bildireceği, aksi halde bu adrese yapılacak tebligatın geçerli sayılacağını kabul eder.

═══════════════════════════════════════════════════

16. DELİL SÖZLEŞMESİ

16.1. Vale ile FunBreak Vale arasında işbu sözleşme ve işlemlerinde çıkabilecek her türlü uyuşmazlıklarda FunBreak Vale'nin defter, kayıt ve belgeleri, mobil uygulama veya web sayfası içindeki mesajlaşma, SMS, e-posta ve bilgisayar çıktıları, veritabanı kayıtları, sistem logları yemin ve beyanlarıyla 6100 sayılı Hukuk Mahkemeleri Kanunu gereği delil olarak kabul edilecek olup, Vale bu kayıtlara itiraz edemeyeceğini kabul eder.

16.2. GPS konum kayıtları, rota takip verileri (route tracking), bekleme noktası kayıtları (waiting points), bırakma konum kayıtları (dropoff location) ve sistem timestamp'leri FunBreak Vale'nin sunucu kayıtlarında saklanır ve delil niteliğindedir.

═══════════════════════════════════════════════════

17. YETKİLİ MAHKEME VE İCRA DAİRELERİ

17.1. İşbu sözleşme hükümlerinden doğabilecek her türlü uyuşmazlıkların çözümünde İstanbul (Çağlayan) Mahkemeleri ile İcra Müdürlükleri yetkili olacaktır.

═══════════════════════════════════════════════════

18. SÖZLEŞME EKLERİNİN KABULÜ

18.1. Vale, işbu sözleşmeyi onaylamakla birlikte sözleşmenin eklerini de kabul etmeyi beyan eder:
1. Kişisel Verilerin Korunmasına Dair Aydınlatma Metni
2. Özel Nitelikli Kişisel Verilerin İşlenmesine Dair Açık Rıza Beyanı
3. Açık Rıza Beyanı
4. Verilerin Gizliliğine Dair Gizlilik Taahhütleri
5. Sorumluluk Beyanı
6. FunBreak Vale tarafından hazırlanan rehberler, kurallar ve şartlar

═══════════════════════════════════════════════════

19. YÜRÜRLÜK

19.1. Vale, işbu Sözleşme'de yer alan maddeleri daha sonra hiçbir itiraza mahal vermeyecek şekilde okuduğunu, anladığını, sözleşme koşullarına uygun davranacağını kabul, beyan ve taahhüt eder.

19.2. İşbu Sözleşme, Vale'nin mobil uygulama veya web platformu üzerinden elektronik onay vermesi veya fiziki olarak imzalaması ile yürürlüğe girer.

19.3. Sözleşme, Türkiye Cumhuriyeti yasalarına tabidir ve bu yasalara göre yorumlanacaktır.

═══════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI
Mersis No: 0388195898700001
Ticaret Sicil No: 1105910
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

═══════════════════════════════════════════════════''';
  }

  String _getKVKKText() {
    return '''FUNBREAK VALE
VALELER İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK 
AYDINLATMA METNİ

═══════════════════════════════════════════════════

VERİ SORUMLUSU BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sitesi        : www.funbreakvale.com

═══════════════════════════════════════════════════

GİRİŞ

Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul 
adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJİ 
LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") olarak işbu Aydınlatma Metni 
aracılığı ile 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") 10. madde 
kapsamında kişisel verilerinizin hangi amaçla işleneceğini; hangi amaçlarla 
kimlere aktarılacağını, toplama yöntemini ve hukuki sebebi, kişisel 
verilerinize ilişkin haklarınızı ve bu hakları nasıl kullanabileceğinizi 
bildirmekle yükümlüyüz.

═══════════════════════════════════════════════════

A. KİŞİSEL VERİLERİN KORUNMASI KANUNU ÇERÇEVESİNDE TANIMLAR

Vale / Valeler: FunBreak Vale'nin çözüm ortağı olan, platform üzerinden 
yolculara özel şoför ve vale hizmeti sunan bağımsız sürücüleri ifade eder.

Kişisel Veri: Kimliği belirli veya belirlenebilir gerçek kişiye ilişkin her 
türlü bilgiyi ifade eder.

Özel Nitelikli Kişisel Veri: Kişilerin ırkı, etnik kökeni, siyasi düşüncesi, 
felsefi inancı, dini, mezhebi veya diğer inançları, kılık ve kıyafeti, dernek, 
vakıf ya da sendika üyeliği, sağlığı, cinsel hayatı, ceza mahkûmiyeti ve 
güvenlik tedbirleriyle ilgili verileri ile biyometrik ve genetik verileri 
ifade eder.

Veri Sorumlusu: Kişisel verilerin işleme amaçlarını ve vasıtalarını 
belirleyen, veri kayıt sisteminin kurulmasından ve yönetilmesinden sorumlu 
olan gerçek veya tüzel kişiyi ifade eder.

═══════════════════════════════════════════════════

B. VERİ SORUMLUSU

FunBreak Vale, veri sorumlusu sıfatıyla gerekli tüm teknik ve idari 
tedbirleri almak suretiyle kişisel verilerinizi aşağıdaki ilkelere uygun 
olarak işler:

• Hukuka ve dürüstlük kurallarına uygun olma,
• Doğru ve gerektiğinde güncel olma,
• Belirli, açık ve meşru amaçlar için işlenme,
• İşleme amaçlarıyla bağlantılı, sınırlı ve ölçülü olma,
• İlgili mevzuatta öngörülen veya işlendikleri amaç için gerekli olan süre 
  kadar muhafaza edilme.

═══════════════════════════════════════════════════

C. İŞLENEN KİŞİSEL VERİ KATEGORİLERİ

1. KİMLİK BİLGİSİ
- T.C. Kimlik Numarası, Ad, Soyad, Doğum Tarihi ve Yeri
- Sürücü Belgesi (Ehliyet) Bilgisi, Fotoğraf

2. İLETİŞİM BİLGİSİ
- Cep Telefonu Numarası, E-posta Adresi, İkametgah Adresi

3. FİNANSAL BİLGİ
- IBAN Bilgisi, Banka Adı, Ödeme Geçmişi, Kazanç Bilgileri

4. MÜŞTERİ İŞLEM BİLGİSİ
- Yolculuk Geçmişi, Rota Takip Verileri, GPS Konum Verileri

5. PERFORMANS BİLGİSİ
- Müşteri Puanları, Kabul/İptal Oranları, Şikayet Kayıtları

6. SAĞLIK BİLGİSİ (ÖZEL NİTELİKLİ)
- Sağlık Raporu, Kronik Hastalık Bilgisi

7. ADLİ SİCİL BİLGİSİ (ÖZEL NİTELİKLİ)
- Adli Sicil Kaydı (Sabıka Kaydı)

8. TRAFİK BİLGİSİ
- Trafik Ceza Puanı, Kaza Geçmişi

9. GÖRSEL VE İŞİTSEL VERİ
- Profil Fotoğrafı, Kimlik/Ehliyet Fotoğrafı

10. LOKASYON / KONUM BİLGİSİ
- Gerçek Zamanlı GPS Konumu, Yolculuk Rotası, Konum Geçmişi

11. CİHAZ BİLGİSİ
- Cihaz Kimliği, İşletim Sistemi, IP Adresi

═══════════════════════════════════════════════════

D. KİŞİSEL VERİLERİN İŞLENME AMAÇLARI

• Vale'nin kimliğinin tespiti ve doğrulanması
• Sözleşme kurulması ve ifası
• Yolcu ile Vale eşleştirmesi
• Canlı yolculuk takibi ve güvenlik
• Ücretlendirme ve ödeme işlemleri
• Performans izleme ve değerlendirme
• Yasal yükümlülüklerin yerine getirilmesi
• Hizmet kalitesinin iyileştirilmesi

═══════════════════════════════════════════════════

E. KİŞİSEL VERİLERİN AKTARILMASI

Kişisel verileriniz, aşağıdaki amaçlarla ve alıcılara aktarılabilir:

1. YOLCULARA: Ad, Soyad, Profil Fotoğrafı, Ortalama Puan, Gerçek Zamanlı Konum
2. HİZMET SAĞLAYICILARA: Bulut sunucu, SMS servisleri, Harita servisleri
3. KAMU KURUMLARINA: Mahkemeler, Savcılıklar, Vergi Dairesi
4. YURT DIŞINA: Bulut sunucu hizmetleri (açık rıza ile)

═══════════════════════════════════════════════════

F. KİŞİSEL VERİ SAHİBİNİN HAKLARI (KVKK MADDE 11)

KVKK'nın 11. maddesi uyarınca, kişisel veri sahibi olarak aşağıdaki haklara 
sahipsiniz:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme,
b) Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme,
c) Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp 
   kullanılmadığını öğrenme,
d) Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü 
   kişileri bilme,
e) Kişisel verilerinizin eksik veya yanlış işlenmiş olması hâlinde bunların 
   düzeltilmesini isteme,
f) Kişisel verilerinizin silinmesini veya yok edilmesini isteme,
g) Yapılan işlemlerin üçüncü kişilere bildirilmesini isteme,
h) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz 
   edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme,
ı) Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara 
   uğramanız hâlinde zararın giderilmesini talep etme.

═══════════════════════════════════════════════════

G. HAKLARIN KULLANILMASI

Başvuru Adresi:
FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul

E-posta: info@funbreakvale.com
Web: www.funbreakvale.com/kvkk-basvuru

Başvurunuz en geç 30 (otuz) gün içinde değerlendirilir.

═══════════════════════════════════════════════════

H. KİŞİSEL VERİLERİN SAKLANMA SÜRESİ

- Kimlik ve İletişim Bilgileri: Sözleşme süresi + 10 yıl
- Finansal Bilgiler: 10 yıl (Vergi mevzuatı)
- Yolculuk Kayıtları: 5 yıl
- GPS/Konum Verileri: 2 yıl
- Sağlık Bilgileri: Sözleşme süresi + 5 yıl
- Adli Sicil Bilgisi: Sözleşme süresi + 3 yıl

═══════════════════════════════════════════════════

I. VERİ GÜVENLİĞİ

FunBreak Vale, kişisel verilerinizin güvenliğini sağlamak için:
• SSL/TLS şifreleme
• Güvenlik duvarı (Firewall)
• Veri yedekleme sistemleri
• Erişim loglarının tutulması
• Personel eğitimleri
• Gizlilik sözleşmeleri

═══════════════════════════════════════════════════

İLETİŞİM

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Telefon: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

İşbu Aydınlatma Metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu 
uyarınca hazırlanmıştır.

Veri Sorumlusu: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001

═══════════════════════════════════════════════════''';
  }

  String _getSpecialDataText() {
    return '''FUNBREAK VALE
VALELERE İLİŞKİN ÖZEL NİTELİKLİ KİŞİSEL VERİLERİN İŞLENMESİNE DAİR 
AÇIK RIZA BEYANI

═══════════════════════════════════════════════════

VERİ SORUMLUSU BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sitesi        : www.funbreakvale.com

═══════════════════════════════════════════════════

GİRİŞ

İşbu Özel Nitelikli Kişisel Verilerin İşlenmesine Dair Açık Rıza Beyanı ile 
Özel Nitelikli Kişisel Verileriniz, 6698 sayılı Kişisel Verilerin Korunması 
Kanunu'na ("KVKK") uygun olarak, FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ'nin 
("FunBreak Vale") meşru menfaatleri ve sözleşme gereği işlenebilir.

═══════════════════════════════════════════════════

BU KAPSAMDA İŞLENEN ÖZEL NİTELİKLİ KİŞİSEL VERİ TİPLERİ

═══════════════════════════════════════════════════

1. SAĞLIK BİLGİLERİ

İŞLENEN VERİLER:
- Sağlık Raporu Bilgileri
- Kronik Hastalık Bilgileri (varsa)
- Ameliyat Geçmişi (varsa)
- Engellilik Durumu (varsa)
- Kan Grubu Bilgisi
- İş Göremezlik Raporları (varsa)

VERİ İŞLENMESİNİN NEDENİ:
• Sürücü sağlığının ve sürüş yeterliliğinin tespiti
• Güvenli sürüş yeteneğinin değerlendirilmesi
• Yolcu güvenliğinin sağlanması
• Acil durumlarda doğru müdahale yapılabilmesi
• İş sağlığı ve güvenliği mevzuatına uyum

═══════════════════════════════════════════════════

2. ADLİ SİCİL BİLGİSİ (SABIKA KAYDI)

İŞLENEN VERİLER:
- Adli Sicil Kaydı (e-Devlet)
- Ceza Mahkumiyeti Bilgisi (varsa)
- Güvenlik Tedbirleri (varsa)

VERİ İŞLENMESİNİN NEDENİ:
• Vale güvenilirliğinin kontrolü
• Müşteri güvenliğinin sağlanması
• Platform güvenliğinin korunması
• Risk değerlendirmesi yapılması

═══════════════════════════════════════════════════

3. GÖRSEL VE İŞİTSEL VERİLER

İŞLENEN VERİLER:
- Profil Fotoğrafı
- Kimlik Fotoğrafı
- Ehliyet Fotoğrafı
- Güvenlik Kamerası Kayıtları (ofis ziyareti varsa)
- Müşteri ile Mesajlaşma Kayıtları

VERİ İŞLENMESİNİN NEDENİ:
• Kimlik doğrulama
• Profil oluşturma
• Güvenlik ve delil
• Hizmet kalitesi kontrolü

═══════════════════════════════════════════════════

4. LOKASYON / KONUM BİLGİSİ (HASSAS VERİ)

İŞLENEN VERİLER:
- Gerçek Zamanlı GPS Konumu
- Konum Geçmişi
- Rota Takip Verileri
- Bekleme Noktaları Koordinatları

VERİ İŞLENMESİNİN NEDENİ:
• Yolcu ile Vale eşleştirmesi
• Canlı yolculuk takibi
• Güvenlik ve izleme
• Mesafe bazlı ücretlendirme

═══════════════════════════════════════════════════

KİŞİSEL VERİLERİN YURT DIŞINA AKTARIMI

FunBreak Vale, kişisel verilerinizi yurt dışına aktarabilir:
• Bulut sunucu hizmetleri (AWS, Google Cloud vb.)
• Analitik araçlar (Google Analytics)
• Harita servisleri

İlgili kişinin (Vale'nin) açık rızası ile yurt dışına aktarım yapılır.

═══════════════════════════════════════════════════

AÇIK RIZA BEYANI

6698 sayılı Kişisel Verilerin Korunması Kanunu'nun 5. maddesi ve 6. maddesi 
birinci fıkrası anlamında;

□ Sağlık bilgilerimin,
□ Adli sicil kaydı bilgilerimin,
□ Görsel ve işitsel verilerimin,
□ Lokasyon/konum bilgilerimin,
□ Cihaz bilgilerimin,

işbu Aydınlatma Metni ve Özel Nitelikli Kişisel Verilerin İşlenmesine Dair 
Açık Rıza Metni'nde belirtildiği şekilde ve amaçlar doğrultusunda 
işlenmesine açık rıza veriyorum.

Kişisel verilerimin yurt dışına aktarılmasına izin veriyorum.

KVKK'nın 11. maddesi uyarınca sahip olduğum haklarımı biliyorum ve bu 
haklarımı kullanabileceğimi kabul ediyorum.

═══════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis: 0388195898700001
Ticaret Sicil: 1105910

═══════════════════════════════════════════════════''';
  }

  String _getOpenConsentText() {
    return '''FUNBREAK VALE
AÇIK RIZA BEYANI

═══════════════════════════════════════════════════

VERİ SORUMLUSU BİLGİLERİ

Ticaret Ünvanı    : FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No         : 0388195898700001
Ticaret Sicil No  : 1105910
Adres             : Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 
                    Ümraniye/İstanbul
Telefon           : 0533 448 82 53
E-posta           : info@funbreakvale.com
Web Sitesi        : www.funbreakvale.com

═══════════════════════════════════════════════════

AÇIK RIZA BEYANI

Veri sorumlusu sıfatına haiz Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı 
No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı 
FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ tarafından bilgilendirildiğimi,

"Kişisel Verilerin İşlenmesi ve Korunmasına Yönelik Aydınlatma Metni"ni ve 
"Kişisel Verilerin İşlenmesi ve Korunması Politikası"nı okuyup anladığımı 
ve özgür irademle elektronik ortamda kabul ettiğimi,

Şerh düşmediğim tüm hususları açık bir rıza ile kabul ettiğimi kabul, beyan 
ve taahhüt ederim.

6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında:

• Kişisel verilerimin işlenmesine,
• Kişisel verilerimin saklanmasına,
• Kişisel verilerimin üçüncü kişilere paylaşılmasına,
• Kişisel verilerimin yurt içinde aktarılmasına,
• Kişisel verilerimin yurt dışına aktarılmasına,
• Özel nitelikli kişisel verilerimin işlenmesine,

işbu belgede ve ilgili aydınlatma metinlerinde belirtilen amaçlar ve hukuki 
sebepler çerçevesinde açık rıza veriyorum.

KVKK'nın 11. maddesi uyarınca sahip olduğum haklarımı biliyorum ve bu 
haklarımı kullanabileceğimi kabul ediyorum.

═══════════════════════════════════════════════════

KVKK'NIN 11. MADDESİ UYARINCA HAKLARINIZ:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme,
b) Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme,
c) Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp 
   kullanılmadığını öğrenme,
d) Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü 
   kişileri bilme,
e) Kişisel verilerinizin eksik veya yanlış işlenmiş olması hâlinde bunların 
   düzeltilmesini isteme,
f) KVKK'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel 
   verilerinizin silinmesini veya yok edilmesini isteme,
g) Yapılan işlemlerin üçüncü kişilere bildirilmesini isteme,
h) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz 
   edilmesi suretiyle kişinin kendisi aleyhine bir sonucun ortaya çıkmasına 
   itiraz etme,
ı) Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara 
   uğramanız hâlinde zararın giderilmesini talep etme.

═══════════════════════════════════════════════════

RIZA GERİ ALMA

Vermiş olduğunuz rızayı geri almak isterseniz:

1. Yazılı Başvuru: Yukarıdaki adrese kimlik belgesi ile başvurabilirsiniz.
2. E-posta: info@funbreakvale.com adresine başvurabilirsiniz.
3. Mobil Uygulama: Ayarlar > KVKK > Rıza Yönetimi menüsünden işlem yapabilirsiniz.

Rıza geri alma talebi, tarafımıza ulaştığı tarihten itibaren en geç 30 (otuz) 
gün içinde değerlendirilir ve sonuçlandırılır.

═══════════════════════════════════════════════════

GÜVENLİK VE GİZLİLİK

FunBreak Vale, kişisel verilerinizin güvenliğini sağlamak için:

• SSL/TLS şifreleme kullanır
• Güvenlik duvarları ile korur
• Düzenli güvenlik güncellemeleri yapar
• Yetkilendirme ve erişim kontrolü uygular
• Veri yedekleme sistemleri kurar
• Personel eğitimleri verir
• Gizlilik sözleşmeleri imzalar

═══════════════════════════════════════════════════

YASAL DAYANAK

İşbu Açık Rıza Beyanı, aşağıdaki mevzuat çerçevesinde hazırlanmıştır:

• 6698 sayılı Kişisel Verilerin Korunması Kanunu
• Kişisel Verilerin Silinmesi, Yok Edilmesi veya Anonim Hale Getirilmesi 
  Hakkında Yönetmelik
• Aydınlatma Yükümlülüğünün Yerine Getirilmesinde Uyulacak Usul ve Esaslar 
  Hakkında Tebliğ
• Kişisel Verileri Koruma Kurulu Kararları

═══════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis: 0388195898700001
Ticaret Sicil: 1105910
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

═══════════════════════════════════════════════════''';
  }
}

