import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

/// SÜRÜCÜ SÖZLEŞME GÜNCELLEME EKRANI
/// 
/// Sürücülerin kabul etmediği veya eski versiyonunu kabul ettiği
/// sözleşmeleri gösterir ve onay alır.

class DriverContractUpdateScreen extends StatefulWidget {
  final int driverId;
  final List<Map<String, dynamic>> pendingContracts;
  final VoidCallback onAllAccepted;

  const DriverContractUpdateScreen({
    Key? key,
    required this.driverId,
    required this.pendingContracts,
    required this.onAllAccepted,
  }) : super(key: key);

  @override
  State<DriverContractUpdateScreen> createState() => _DriverContractUpdateScreenState();
}

class _DriverContractUpdateScreenState extends State<DriverContractUpdateScreen> {
  final Map<String, bool> _acceptedContracts = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    for (var contract in widget.pendingContracts) {
      _acceptedContracts[contract['type']] = false;
    }
  }

  bool get _allAccepted => _acceptedContracts.values.every((v) => v);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showExitWarning();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'Sözleşme Güncelleme',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: _showExitWarning,
              child: const Text('Çıkış', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        body: Column(
          children: [
            // Progress Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Güncellenmiş Vale Sözleşmeleri',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      Text(
                        '${_acceptedContracts.values.where((v) => v).length}/${widget.pendingContracts.length}',
                        style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _acceptedContracts.values.where((v) => v).length / widget.pendingContracts.length,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  ),
                ],
              ),
            ),

            // Bilgi Banner
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vale sözleşmelerimiz güncellenmiştir. Devam etmek için yeni sözleşmeleri okumanız ve kabul etmeniz zorunludur.',
                      style: TextStyle(color: Colors.amber[200], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            // Sözleşme Listesi
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.pendingContracts.length,
                itemBuilder: (context, index) {
                  final contract = widget.pendingContracts[index];
                  final isAccepted = _acceptedContracts[contract['type']] ?? false;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isAccepted 
                            ? Colors.green.withOpacity(0.2)
                            : const Color(0xFFFFD700).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isAccepted ? Icons.check_circle : Icons.gavel,
                          color: isAccepted ? Colors.green : const Color(0xFFFFD700),
                        ),
                      ),
                      title: Text(
                        contract['title'] ?? 'Sözleşme',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            'Versiyon: ${contract['latest_version']}',
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                          if (contract['accepted_version'] != '0.0')
                            Text(
                              'Önceki: ${contract['accepted_version']}',
                              style: TextStyle(color: Colors.orange[300], fontSize: 11),
                            ),
                        ],
                      ),
                      trailing: isAccepted
                        ? const Icon(Icons.check, color: Colors.green)
                        : ElevatedButton(
                            onPressed: () => _showContractDialog(contract),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Oku'),
                          ),
                      onTap: () => _showContractDialog(contract),
                    ),
                  );
                },
              ),
            ),

            // Alt Buton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _allAccepted && !_isLoading ? _submitAllContracts : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _allAccepted 
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
                      : Text(
                          _allAccepted 
                            ? 'Devam Et' 
                            : 'Tüm Sözleşmeleri Kabul Edin',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContractDialog(Map<String, dynamic> contract) {
    final type = contract['type'] as String;
    final title = contract['title'] as String;
    final content = _getContractContent(type);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: MediaQuery.of(context).size.width * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Başlık
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Versiyon: ${contract['latest_version']}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // İçerik
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              // Butonlar
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Kapat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _acceptedContracts[type] = true;
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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

  void _showExitWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 12),
            Text('Dikkat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Sözleşmeleri kabul etmeden vale uygulamasını kullanamazsınız.\n\nÇıkmak istediğinize emin misiniz?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              exit(0);
            },
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitAllContracts() async {
    if (!_allAccepted) return;

    setState(() => _isLoading = true);

    try {
      final deviceInfo = await _collectDeviceInfo();
      
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      } catch (e) {
        print('⚠️ Konum alınamadı: $e');
      }

      for (var contract in widget.pendingContracts) {
        final type = contract['type'] as String;
        final version = contract['latest_version'] as String;
        final title = contract['title'] as String;

        print('📝 VALE SÖZLEŞME LOG: $type v$version');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/log_legal_consent.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': widget.driverId,
            'user_type': 'driver',
            'consent_type': type,
            'consent_text': _getContractContent(type),
            'consent_summary': title,
            'consent_version': version,
            'ip_address': deviceInfo['ip_address'],
            'user_agent': deviceInfo['user_agent'],
            'device_fingerprint': deviceInfo['device_fingerprint'],
            'platform': deviceInfo['platform'],
            'os_version': deviceInfo['os_version'],
            'app_version': deviceInfo['app_version'],
            'latitude': position?.latitude,
            'longitude': position?.longitude,
            'location_accuracy': position?.accuracy,
            'language': 'tr',
          }),
        ).timeout(const Duration(seconds: 10));

        final apiData = jsonDecode(response.body);
        if (apiData['success'] == true) {
          print('✅ Vale sözleşme $type v$version loglandı');
        } else {
          print('❌ Vale sözleşme $type log hatası: ${apiData['message']}');
        }
      }

      // SharedPreferences'a kaydet (eski sistem ile uyumluluk)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_consents_accepted', true);
      await prefs.setString('driver_consents_version', '2.0');
      await prefs.setString('driver_consents_date', DateTime.now().toIso8601String());

      print('✅ TÜM VALE SÖZLEŞMELERİ ONAYLANDI!');

      widget.onAllAccepted();

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
      'app_version': '2.0.0',
      'device_fingerprint': fingerprint,
      'user_agent': 'FunBreak Vale Driver/$platform ${Platform.operatingSystemVersion}',
      'ip_address': 'auto',
    };
  }

  String _getContractContent(String type) {
    switch (type) {
      case 'vale_usage_agreement':
        return _getUsageAgreementText();
      case 'kvkk_vale':
        return _getKVKKText();
      case 'special_data_consent':
        return _getSpecialDataText();
      case 'open_consent':
        return _getOpenConsentText();
      default:
        return 'Sözleşme içeriği yüklenemedi.';
    }
  }

  String _getUsageAgreementText() {
    return '''FUNBREAK VALE
VALE (SÜRÜCÜ) KULLANIM KOŞULLARI SÖZLEŞMESİ

Versiyon: 2.0 | Tarih: 28 Kasım 2025

1. TARAFLAR
İşbu Sözleşme, Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") ile FunBreak Vale mobil uygulaması üzerinden vale hizmeti veren bağımsız sürücü ("Vale") arasındadır.

2. HİZMET TANIMI
Vale, FunBreak Vale platformu üzerinden gelen talepleri kabul ederek, müşterilerin araçlarını belirlenen noktadan alıp istenen konuma götüren profesyonel vale ve özel şoför hizmeti sunacaktır.

3. VALE'NİN YÜKÜMLÜLÜKLERİ

3.1. Zorunlu Belgeler:
• T.C. Kimlik Kartı
• B sınıfı sürücü belgesi (en az 3 yıl)
• Sağlık raporu
• Adli sicil kaydı (temiz)
• Ceza puanı belgesi (70 altında)
• IBAN bilgisi
• İkametgah belgesi

3.2. Davranış Kuralları:
• Profesyonel ve nazik davranış
• Trafik kurallarına tam uyum
• Müşteri bilgilerinin gizliliği
• Alkol ve uyuşturucu yasağı
• Araç içi sigara yasağı
• Temiz ve düzgün giyim

4. KOMİSYON VE ÖDEME

4.1. Komisyon Oranları:
• Standart komisyon: %30 (FunBreak Vale alır)
• Vale payı: %70

4.2. Ödeme Takvimi:
• Haftalık ödeme (Her Pazartesi)
• IBAN'a transfer

4.3. Özel Konum Ücreti:
• Özel konum ücreti KOMİSYONSUZ olarak Vale'ye ödenir (%100)

5. İPTAL KOŞULLARI
• Yolcu 45 dakikadan önce iptal: Ücretsiz
• Yolcu 45 dakikadan az kala iptal: ₺1.500 (%70 Vale, %30 FunBreak)
• Vale kabul sonrası iptal: Kötüye kullanımda hesap askıya alınabilir

6. PERFORMANS DEĞERLENDİRME
• Minimum yıldız: 3.5
• 3.5 altına düşen hesaplar incelemeye alınır
• Sürekli düşük puan sonlandırma sebebidir

7. GİZLİLİK
• Müşteri bilgileri gizlidir
• 2 yıl rekabet yasağı

8. SÖZLEŞMENİN FESHİ
Taraflardan herhangi biri 7 gün önceden yazılı bildirimle sözleşmeyi feshedebilir.

9. YETKİLİ MAHKEME
İstanbul (Çağlayan) Mahkemeleri yetkilidir.''';
  }

  String _getKVKKText() {
    return '''FUNBREAK VALE
VALELER İÇİN KİŞİSEL VERİLERİN KORUNMASI AYDINLATMA METNİ

Versiyon: 2.0 | Tarih: 28 Kasım 2025

VERİ SORUMLUSU:
FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Adres: Armağanevler Mah. Ortanca Sk. No: 69/22 Ümraniye/İstanbul

A. İŞLENEN KİŞİSEL VERİ KATEGORİLERİ

1. Kimlik Bilgileri: Ad, soyad, T.C. kimlik numarası, doğum tarihi
2. İletişim Bilgileri: Telefon, e-posta, adres
3. Finansal Bilgiler: IBAN, ödeme geçmişi, kazanç raporları
4. Müşteri İşlem/Yolculuk Bilgileri: Yolculuk geçmişi, tamamlanan işler
5. Araç Bilgileri: Kullandığı araç bilgileri
6. Performans Verileri: Puanlama, yorum, tamamlama oranı
7. Sağlık Verileri (ÖZEL): Sağlık raporu
8. Adli Sicil (ÖZEL): Sabıka kaydı
9. Görsel/İşitsel (ÖZEL): Profil fotoğrafı
10. Lokasyon (HASSAS): Canlı GPS konum
11. Cihaz/Teknik: IP adresi, cihaz kimliği
12. Mesajlaşma: Uygulama içi mesajlar

B. İŞLEME AMAÇLARI
• Vale hizmetinin yürütülmesi
• Yolculuk eşleştirmesi
• Ödeme işlemleri
• Performans değerlendirme
• Güvenlik kontrolleri
• Yasal yükümlülükler

C. AKTARIM
• Yolcular ile (sınırlı bilgi)
• Ödeme kuruluşları ile
• Yasal merciler ile

D. HAKLARINIZ (KVKK m.11)
• Bilgi alma, düzeltme, silme, itiraz hakları
• Başvuru: info@funbreakvale.com''';
  }

  String _getSpecialDataText() {
    return '''ÖZEL NİTELİKLİ KİŞİSEL VERİLERİN İŞLENMESİNE İLİŞKİN AÇIK RIZA BEYANI

Versiyon: 2.0 | Tarih: 28 Kasım 2025

Ben, aşağıda belirtilen özel nitelikli kişisel verilerimin FunBreak Vale tarafından işlenmesine açık rızam ile onay veriyorum:

1. SAĞLIK VERİLERİ
• Sağlık raporu
• Fiziksel yeterlilik durumu
Amaç: Sürüş yeterliliğinin değerlendirilmesi

2. ADLİ SİCİL VERİLERİ
• Sabıka kaydı
• Ceza puanı
Amaç: Güvenlik değerlendirmesi

3. GÖRSEL VERİLER
• Profil fotoğrafı
• Ehliyet fotoğrafı
Amaç: Kimlik doğrulama

4. LOKASYON VERİLERİ
• Anlık GPS konumu
• Rota bilgisi
Amaç: Yolculuk takibi ve güvenlik

Bu verilerin işlenmesine açık rızam ile onay veriyorum.

Veri Sorumlusu:
FunBreak Global Teknoloji Limited Şirketi
info@funbreakvale.com''';
  }

  String _getOpenConsentText() {
    return '''AÇIK RIZA BEYANI

Versiyon: 2.0 | Tarih: 28 Kasım 2025

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ'ne ("FunBreak Vale"),

6698 sayılı Kişisel Verilerin Korunması Kanunu kapsamında:

1. Kişisel verilerimin vale hizmeti sürecinde işlenmesine,
2. Özel nitelikli kişisel verilerimin (sağlık raporu, adli sicil, lokasyon) işlenmesine,
3. Verilerimin hizmet kalitesi ve güvenlik amacıyla işlenmesine,
4. Gerekli durumlarda yurt içi ve yurt dışında bulunan iş ortakları ile paylaşılmasına,
5. KVKK Aydınlatma Metni'ni okuduğumu ve anladığımı,

açık rızam ile onay veriyorum.

Bu onayımı dilediğim zaman info@funbreakvale.com adresine yazılı başvuru ile geri alabileceğimi biliyorum.

FunBreak Global Teknoloji Limited Şirketi
Armağanevler Mah. Ortanca Sk. No: 69/22 Ümraniye/İstanbul
Mersis No: 0388195898700001''';
  }
}

