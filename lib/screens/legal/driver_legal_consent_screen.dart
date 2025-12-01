import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

/// SÜRÜCÜ İLK GİRİŞ SÖZLEŞME ONAY EKRANI
/// 4 Zorunlu sözleşme onayı alınır:
/// 1. Vale Kullanım Koşulları
/// 2. KVKK Aydınlatma Metni
/// 3. Özel Nitelikli Kişisel Veriler Açık Rıza
/// 4. Açık Rıza Beyanı
class DriverLegalConsentScreen extends StatefulWidget {
  final int driverId;
  final String driverName;
  final VoidCallback onConsentsAccepted;

  const DriverLegalConsentScreen({
    Key? key,
    required this.driverId,
    required this.driverName,
    required this.onConsentsAccepted,
  }) : super(key: key);

  @override
  State<DriverLegalConsentScreen> createState() => _DriverLegalConsentScreenState();
}

class _DriverLegalConsentScreenState extends State<DriverLegalConsentScreen> {
  bool _usageAgreementAccepted = false;
  bool _kvkkAccepted = false;
  bool _specialDataAccepted = false;
  bool _openConsentAccepted = false;
  bool _isLoading = false;

  // TÜM SÖZLEŞMELER ONAYLANDI MI?
  bool get _allConsentsAccepted =>
      _usageAgreementAccepted &&
      _kvkkAccepted &&
      _specialDataAccepted &&
      _openConsentAccepted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('Sözleşme Onayları'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        centerTitle: true,
        automaticallyImplyLeading: false, // Geri butonu YOK - zorunlu ekran
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.gavel, color: Colors.amber, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Hoş Geldin ${widget.driverName}!',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Vale olarak hizmet verebilmek için aşağıdaki sözleşmeleri okumanız ve onaylamanız gerekmektedir.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // İLERLEME GÖSTERGES İ
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _allConsentsAccepted ? Icons.check_circle : Icons.pending,
                      color: _allConsentsAccepted ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${[_usageAgreementAccepted, _kvkkAccepted, _specialDataAccepted, _openConsentAccepted].where((e) => e).length}/4 Sözleşme Onaylandı',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 1. VALE KULLANIM KOŞULLARI
              _buildConsentCard(
                title: 'Vale Kullanım Koşulları',
                subtitle: 'FunBreak Vale platform kullanım sözleşmesi',
                icon: Icons.drive_eta,
                isAccepted: _usageAgreementAccepted,
                onTap: () => _showUsageAgreementDialog(),
                onChanged: (value) => setState(() => _usageAgreementAccepted = value ?? false),
                isRequired: true,
              ),
              const SizedBox(height: 12),

              // 2. KVKK AYDINLATMA METNİ
              _buildConsentCard(
                title: 'KVKK Aydınlatma Metni',
                subtitle: 'Kişisel verilerin işlenmesi hakkında bilgilendirme',
                icon: Icons.privacy_tip,
                isAccepted: _kvkkAccepted,
                onTap: () => _showKVKKDialog(),
                onChanged: (value) => setState(() => _kvkkAccepted = value ?? false),
                isRequired: true,
              ),
              const SizedBox(height: 12),

              // 3. ÖZEL NİTELİKLİ KİŞİSEL VERİLER
              _buildConsentCard(
                title: 'Özel Nitelikli Veriler Rızası',
                subtitle: 'Sağlık, adli sicil vb. özel verilerin işlenmesi',
                icon: Icons.security,
                isAccepted: _specialDataAccepted,
                onTap: () => _showSpecialDataDialog(),
                onChanged: (value) => setState(() => _specialDataAccepted = value ?? false),
                isRequired: true,
              ),
              const SizedBox(height: 12),

              // 4. AÇIK RIZA BEYANI
              _buildConsentCard(
                title: 'Açık Rıza Beyanı',
                subtitle: 'Genel kişisel veri işleme rızası',
                icon: Icons.verified_user,
                isAccepted: _openConsentAccepted,
                onTap: () => _showOpenConsentDialog(),
                onChanged: (value) => setState(() => _openConsentAccepted = value ?? false),
                isRequired: true,
              ),
              const SizedBox(height: 32),

              // ONAY BUTONU
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _allConsentsAccepted && !_isLoading
                      ? _submitConsents
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allConsentsAccepted
                        ? const Color(0xFFFFD700)
                        : Colors.grey[700],
                    foregroundColor: Colors.black,
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
                              _allConsentsAccepted
                                  ? Icons.check_circle
                                  : Icons.lock,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _allConsentsAccepted
                                  ? 'Sözleşmeleri Onayla ve Devam Et'
                                  : 'Tüm Sözleşmeleri Onaylayın',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // BİLGİ NOTU
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sözleşmeleri okumak için başlıklara tıklayın. Onay verdikten sonra bu ekranı bir daha görmeyeceksiniz.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isAccepted,
    required VoidCallback onTap,
    required ValueChanged<bool?> onChanged,
    required bool isRequired,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isAccepted
            ? Colors.green.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted
              ? Colors.green.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isAccepted
                        ? Colors.green.withOpacity(0.2)
                        : Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isAccepted ? Colors.green : Colors.amber,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                decoration: isAccepted
                                    ? TextDecoration.none
                                    : TextDecoration.underline,
                              ),
                            ),
                          ),
                          if (isRequired)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ZORUNLU',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  value: isAccepted,
                  onChanged: onChanged,
                  activeColor: Colors.green,
                  checkColor: Colors.white,
                  side: BorderSide(
                    color: isAccepted ? Colors.green : Colors.white54,
                    width: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // SÖZLEŞME DİALOG'LARI
  void _showUsageAgreementDialog() {
    _showContractDialog(
      title: 'Vale Kullanım Koşulları Sözleşmesi',
      content: _getUsageAgreementText(),
      onAccept: () => setState(() => _usageAgreementAccepted = true),
    );
  }

  void _showKVKKDialog() {
    _showContractDialog(
      title: 'KVKK Aydınlatma Metni',
      content: _getKVKKText(),
      onAccept: () => setState(() => _kvkkAccepted = true),
    );
  }

  void _showSpecialDataDialog() {
    _showContractDialog(
      title: 'Özel Nitelikli Kişisel Veriler Açık Rıza Beyanı',
      content: _getSpecialDataText(),
      onAccept: () => setState(() => _specialDataAccepted = true),
    );
  }

  void _showOpenConsentDialog() {
    _showContractDialog(
      title: 'Açık Rıza Beyanı',
      content: _getOpenConsentText(),
      onAccept: () => setState(() => _openConsentAccepted = true),
    );
  }

  void _showContractDialog({
    required String title,
    required String content,
    required VoidCallback onAccept,
  }) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // BAŞLIK
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel, color: Colors.black),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // İÇERİK
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              // BUTONLAR
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Kapat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          onAccept();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Okudum, Kabul Ediyorum',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // SÖZLEŞMELERİ ONAYLA VE KAYDET
  Future<void> _submitConsents() async {
    if (!_allConsentsAccepted) return;

    setState(() => _isLoading = true);

    try {
      // Cihaz bilgilerini topla
      final deviceInfo = await _collectDeviceInfo();
      
      // Konum bilgisi topla
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print('⚠️ Konum alınamadı: $e');
      }

      // Her sözleşme için ayrı log kaydet
      final consents = [
        {'type': 'vale_usage_agreement', 'text': _getUsageAgreementText(), 'summary': 'Vale Kullanım Koşulları Sözleşmesi'},
        {'type': 'kvkk_vale', 'text': _getKVKKText(), 'summary': 'KVKK Aydınlatma Metni (Valeler İçin)'},
        {'type': 'special_data_consent', 'text': _getSpecialDataText(), 'summary': 'Özel Nitelikli Veriler Açık Rıza'},
        {'type': 'open_consent', 'text': _getOpenConsentText(), 'summary': 'Açık Rıza Beyanı'},
      ];

      for (var consent in consents) {
        print('📝 VALE SÖZLEŞME LOG: ${consent['type']}');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': widget.driverId,
            'user_type': 'driver',
            'consent_type': consent['type'],
            'consent_text': consent['text'],
            'consent_summary': consent['summary'],
            'consent_version': '1.0',
            'ip_address': deviceInfo['ip_address'],
            'user_agent': deviceInfo['user_agent'],
            'device_fingerprint': deviceInfo['device_fingerprint'],
            'platform': deviceInfo['platform'],
            'os_version': deviceInfo['os_version'],
            'app_version': deviceInfo['app_version'],
            'device_model': deviceInfo['device_model'],
            'device_manufacturer': deviceInfo['device_manufacturer'],
            'latitude': position?.latitude,
            'longitude': position?.longitude,
            'location_accuracy': position?.accuracy,
            'location_timestamp': position != null ? DateTime.now().toIso8601String() : null,
            'language': 'tr',
          }),
        ).timeout(const Duration(seconds: 10));

        final apiData = jsonDecode(response.body);
        if (apiData['success'] == true) {
          print('✅ Vale sözleşme ${consent['type']} loglandı - Log ID: ${apiData['log_id']}');
        } else {
          print('❌ Vale sözleşme ${consent['type']} log hatası: ${apiData['message']}');
        }
      }

      // SharedPreferences'a kaydet - bir daha gösterme
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_consents_accepted', true);
      await prefs.setString('driver_consents_date', DateTime.now().toIso8601String());

      print('✅ VALE SÖZLEŞMELERİ TAMAMEN ONAYLANDI!');

      // Callback çağır - ana sayfaya geç
      widget.onConsentsAccepted();

    } catch (e) {
      print('❌ Sözleşme kayıt hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _collectDeviceInfo() async {
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');
    final fingerprint = DateTime.now().millisecondsSinceEpoch.toString() + 
                       '_driver_' + 
                       widget.driverId.toString();
    
    return {
      'platform': platform,
      'os_version': Platform.operatingSystemVersion,
      'app_version': '1.0.0',
      'device_model': 'auto',
      'device_manufacturer': 'auto',
      'device_fingerprint': fingerprint,
      'user_agent': 'FunBreak Vale App/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto',
    };
  }

  // SÖZLEŞME METİNLERİ
  String _getUsageAgreementText() {
    return '''FUNBREAK VALE
VALE KULLANIM KOŞULLARI SÖZLEŞMESİ

1. TARAFLAR
İşbu Mobil Uygulama Kullanım Sözleşmesi, Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") ile FunBreak Vale mobil uygulaması üzerinden yolcuları taşıyan sürücü ("Vale") arasındadır.

2. SÖZLEŞMENİN AMACI VE KONUSU
2.1. İşbu Sözleşme'nin konusu, yolcu için özel şoför ve vale bulma hizmetini sunan FunBreak Vale ile Vale arasındaki mobil uygulama ve web platformu kullanımına ilişkin hak ve yükümlülükleri belirtmektedir.
2.2. FunBreak Vale, Yolcu ile Vale arasında aracılık hizmeti sunan bir teknoloji platformudur. FunBreak Vale, Vale ile herhangi bir işçi-işveren ilişkisi kurmamakta olup, Vale bağımsız çalışan statüsünde hizmet vermektedir.

3. KAYIT VE KABUL KOŞULLARI
3.1.1. Vale adayları en az 21 yaşında olmalı, en az 3 yıl sürücülük deneyimine sahip olmalı ve herhangi bir sürücülük yetersizliği bulunmamalıdır.
3.1.2. Vale adayları kayıt esnasında aşağıdaki belgeleri FunBreak Vale'ye teslim etmeyi taahhüt eder:
- Kimlik Belgesi (T.C. Kimlik Kartı)
- Ehliyet Belgesi (B sınıfı, en az 3 yıl)
- Sağlık Raporu (son 6 ay)
- Adli Sicil Kaydı
- Ceza Puanı Bilgisi (70 üstü kabul edilmez)
- IBAN Bilgisi
- İkametgah Belgesi (son 3 ay)

4. VALE'NİN YÜKÜMLÜLÜKLERİ
4.1. Transfer taleplerini makul süre içerisinde değerlendirmek
4.2. Yolcu'nun alım noktasına belirlenen zamanda varmak
4.3. Transfer işlemini bizzat kendisi gerçekleştirmek
4.4. FunBreak Vale tarafından belirlenen ücret tarifeleri dışında ücret talep etmemek
4.5. GPS takibi aktif tutmak
4.6. Trafik kurallarına tam olarak uymak

5. KOMİSYON VE ÖDEME
5.1. Tüm yolculuklardan %30 komisyon FunBreak Vale tarafından kesilir.
5.2. Ödemeler haftalık olarak yapılır.
5.3. Her Pazartesi günü, bir önceki hafta tamamlanan yolculukların ödemesi Vale'nin IBAN'ına havale edilir.

6. İPTAL POLİTİKASI
- 45 dakika veya daha fazla kala iptal: Ücretsiz
- 45 dakikadan az kala iptal: Yolcu 1.500 TL iptal ücreti öder (%70 Vale'ye)

7. YETKİLİ MAHKEME
İşbu sözleşme hükümlerinden doğabilecek uyuşmazlıkların çözümünde İstanbul (Çağlayan) Mahkemeleri yetkilidir.

FunBreak Global Teknoloji Limited Şirketi
Mersis No: 0388195898700001
Ticaret Sicil No: 1105910
info@funbreakvale.com | www.funbreakvale.com

Versiyon: 1.0 | Tarih: 28 Kasım 2025''';
  }

  String _getKVKKText() {
    return '''FUNBREAK VALE
VALELER İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK AYDINLATMA METNİ

VERİ SORUMLUSU BİLGİLERİ
Ticaret Ünvanı: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
E-posta: info@funbreakvale.com

GİRİŞ
6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında kişisel verilerinizin işlenmesine ilişkin aydınlatma yükümlülüğümüzü yerine getirmekteyiz.

İŞLENEN KİŞİSEL VERİ KATEGORİLERİ
1. Kimlik Bilgileri: Ad, soyad, T.C. kimlik no, doğum tarihi
2. İletişim Bilgileri: Telefon, e-posta, adres
3. Finansal Bilgiler: IBAN, ödeme bilgileri
4. Müşteri İşlem Bilgileri: Yolculuk kayıtları, puanlar
5. Araç Bilgileri: Ehliyet bilgileri
6. Performans Verileri: Tamamlanan yolculuk sayısı, müşteri değerlendirmeleri
7. Sağlık Verileri (ÖZEL): Sağlık raporu
8. Adli Sicil Verileri (ÖZEL): Adli sicil kaydı
9. Lokasyon Verileri: GPS konum bilgileri, rota verileri
10. Cihaz/Teknik Veriler: IP adresi, cihaz bilgileri

İŞLEME AMAÇLARI
- Vale kaydı ve profil oluşturma
- Yolculuk eşleştirme
- Ödeme işlemleri
- Güvenlik ve doğrulama
- Yasal yükümlülükler
- Hizmet kalitesi

VERİ AKTARIMI
Kişisel verileriniz; yasal yükümlülükler, yolcu ile eşleştirme ve ödeme işlemleri kapsamında ilgili kişi ve kurumlara aktarılabilir.

HAKLARINIZ (KVKK md. 11)
- Verilerinize erişim
- Düzeltme ve silme talep etme
- İşleme itiraz etme
- Veri taşınabilirliği

İletişim: info@funbreakvale.com

Versiyon: 1.0 | Tarih: 28 Kasım 2025''';
  }

  String _getSpecialDataText() {
    return '''FUNBREAK VALE
ÖZEL NİTELİKLİ KİŞİSEL VERİLERİN İŞLENMESİNE DAİR AÇIK RIZA BEYANI

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında "özel nitelikli kişisel veri" olarak tanımlanan aşağıdaki veri kategorilerinin işlenmesine açık rızam ile onay veriyorum:

İŞLENECEK ÖZEL NİTELİKLİ VERİLER:

1. SAĞLIK VERİLERİ
- Sağlık raporu bilgileri
- Sürücülük yapabilme durumu
İşleme Amacı: Vale olarak güvenli sürüş yapabilme yeterliliğinin tespiti

2. ADLİ SİCİL VERİLERİ
- Sabıka kaydı durumu
- Ceza geçmişi bilgileri
İşleme Amacı: Yolcu güvenliğinin sağlanması

3. FİZİKSEL KONUM VERİLERİ
- GPS konum bilgileri
- Rota takip verileri
- Bekleme noktası kayıtları
- Bırakma konum bilgileri
İşleme Amacı: Yolculuk takibi, güvenlik ve hizmet kalitesi

SAKLAMA SÜRESİ
Özel nitelikli kişisel veriler, yasal saklama süreleri ve hizmet gereklilikleri çerçevesinde muhafaza edilecek olup, bu sürelerin sona ermesi veya işleme amacının ortadan kalkması halinde silinecek, yok edilecek veya anonim hale getirilecektir.

İşbu beyanı okuyarak, belirtilen özel nitelikli kişisel verilerimin işlenmesine AÇIK RIZAMLA onay veriyorum.

Versiyon: 1.0 | Tarih: 28 Kasım 2025''';
  }

  String _getOpenConsentText() {
    return '''FUNBREAK VALE
AÇIK RIZA BEYANI

6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında, FunBreak Global Teknoloji Limited Şirketi'nin ("FunBreak Vale") kişisel verilerimi işlemesine ilişkin aşağıdaki hususlarda açık rızamı veriyorum:

1. VERİ İŞLEME RIZA KAPSAMI

Aşağıdaki amaçlarla kişisel verilerimin işlenmesine onay veriyorum:
- Vale hesabımın oluşturulması ve yönetilmesi
- Yolculuk eşleştirme ve koordinasyon
- Ödeme işlemlerinin gerçekleştirilmesi
- Performans değerlendirmesi
- Güvenlik ve doğrulama işlemleri
- Yasal yükümlülüklerin yerine getirilmesi

2. VERİ AKTARIM RIZASI

Kişisel verilerimin aşağıdaki taraflara aktarılmasına onay veriyorum:
- Yolculuk eşleşmesi için Yolculara (sınırlı bilgi)
- Ödeme işlemleri için bankalar ve ödeme kuruluşları
- Yasal zorunluluklar için yetkili kamu kurum ve kuruluşları
- Hizmet sağlayıcılar (SMS, e-posta servisleri)

3. RIZA GERİ ÇEKİLMESİ

Bu rızamı dilediğim zaman info@funbreakvale.com adresine yazılı başvuru ile geri çekebileceğimi biliyorum.

4. BİLGİLENDİRME

KVKK Aydınlatma Metni'ni okudum, anladım ve kişisel verilerimin belirtilen amaçlar ve kapsamda işlenmesine AÇIK RIZAMLA onay veriyorum.

Versiyon: 1.0 | Tarih: 28 Kasım 2025''';
  }
}

