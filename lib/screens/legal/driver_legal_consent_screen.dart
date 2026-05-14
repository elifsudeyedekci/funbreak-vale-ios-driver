import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import '../../services/legal_consent_log_service.dart';
import '../../utils/driver_numeric_id.dart';

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
    // ZORUNLU ONAY: Geri tuşu engellendi, sürücü onaylamadan ekrandan çıkamaz.
    return WillPopScope(
      onWillPop: () async {
        _showExitWarning();
        return false; // geri tuşunu engelle
      },
      child: Scaffold(
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
      ), // Scaffold kapanışı
    ); // WillPopScope kapanışı
  }

  /// Sürücü onay vermeden çıkmaya çalışırsa uyarı göster.
  /// "Çıkış Yap" seçerse uygulamadan tamamen çıkar (KVKK gereği zorunlu onay).
  void _showExitWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('Dikkat', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Sözleşmeleri onaylamadan vale uygulamasını kullanamazsınız.\n\nÇıkmak istediğinize emin misiniz?',
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
      final prefs = await SharedPreferences.getInstance();
      var userId = widget.driverId > 0 ? widget.driverId : readDriverNumericUserId(prefs);
      if (userId <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Oturum kimliği bulunamadı. Lütfen çıkış yapıp tekrar giriş yapın.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final deviceInfo = LegalConsentLogService.buildDeviceInfo(
        userId: userId,
        isDriver: true,
      );
      
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

      // 🔥 TÜM SÖZLEŞMELERİN BAŞARIYLA KAYDEDİLDİĞİNİ TAKİP ET
      int successCount = 0;
      int failCount = 0;
      List<String> failedConsents = [];
      
      for (var consent in consents) {
        print('📝 VALE SÖZLEŞME LOG: ${consent['type']}');
        
        try {
          final apiData = await LegalConsentLogService.postLegalConsent(
            userId: userId,
            userType: 'driver',
            consentType: consent['type'] as String,
            consentText: consent['text'] as String,
            consentSummary: consent['summary'] as String,
            consentVersion: '4.0',
            deviceInfo: deviceInfo,
            position: position,
          );

          if (apiData['success'] == true) {
            print('✅ Vale sözleşme ${consent['type']} loglandı - Log ID: ${apiData['log_id']}');
            successCount++;
          } else {
            print('❌ Vale sözleşme ${consent['type']} log hatası: ${apiData['message'] ?? 'Bilinmeyen hata'}');
            failCount++;
            failedConsents.add(consent['type'] as String);
          }
        } catch (e) {
          print('❌ Vale sözleşme ${consent['type']} exception: $e');
          failCount++;
          failedConsents.add(consent['type'] as String);
        }
      }
      
      // En az 1 sözleşme kaydedildiyse devam et; aksi halde hata göster
      if (successCount == 0) {
        throw Exception(
          'Hiçbir sözleşme kaydedilemedi (${failedConsents.join(', ')}). '
          'Bağlantı yavaşsa süre dolmuş olabilir; bir süre sonra tekrar deneyin. '
          'Sorun sürerse yönetimle iletişime geçin.',
        );
      }

      if (failCount > 0) {
        print('⚠️ Kısmi başarı: $successCount kaydedildi, $failCount başarısız (${failedConsents.join(', ')})');
        // Arka planda sessizce yeniden dene (kullanıcı tarafı bloklanmaz)
        _retryFailedConsentsInBackground(userId, failedConsents, consents, deviceInfo, position);
      }

      print('✅ $successCount/${consents.length} SÖZLEŞME KAYDEDİLDİ - devam ediliyor');

      // SharedPreferences'a kaydet - bir daha gösterme
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

  /// Başarısız sözleşme kayıtlarını arka planda yeniden dener
  /// (Kullanıcı engellenmesin - ana sayfaya geçer, biz arka planda halletmeye devam ederiz)
  Future<void> _retryFailedConsentsInBackground(
    int userId,
    List<String> failedTypes,
    List<Map<String, dynamic>> consents,
    Map<String, dynamic> deviceInfo,
    Position? position,
  ) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      await Future.delayed(Duration(seconds: 5 * attempt));
      if (failedTypes.isEmpty) return;
      final stillFailed = <String>[];

      for (final type in List<String>.from(failedTypes)) {
        final consent = consents.firstWhere(
          (c) => c['type'] == type,
          orElse: () => <String, dynamic>{},
        );
        if (consent.isEmpty) continue;
        try {
          final apiData = await LegalConsentLogService.postLegalConsent(
            userId: userId,
            userType: 'driver',
            consentType: consent['type'] as String,
            consentText: consent['text'] as String,
            consentSummary: consent['summary'] as String,
            consentVersion: '4.0',
            deviceInfo: deviceInfo,
            position: position,
          );
          if (apiData['success'] == true) {
            print('🔁 [BG retry $attempt] $type başarılı');
          } else {
            stillFailed.add(type);
          }
        } catch (_) {
          stillFailed.add(type);
        }
      }
      failedTypes = stillFailed;
    }
    if (failedTypes.isNotEmpty) {
      print('⚠️ [BG retry] hala başarısız sözleşmeler: ${failedTypes.join(", ")}');
    }
  }

  // SÖZLEŞME METİNLERİ
  String _getUsageAgreementText() {
    return '''FUNBREAK VALE
VALE KULLANIM KOŞULLARI SÖZLEŞMESİ

═══════════════════════════════════════════════════════════════════════════════

1. TARAFLAR

İşbu Mobil Uygulama Kullanım Sözleşmesi (Bundan böyle "Sözleşme" olarak anılacaktır.) Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul adresinde mukim, 0388195898700001 Mersis numaralı FUNBREAK GLOBAL TEKNOLOJI LIMITED SIRKETI (Bundan böyle "FunBreak Vale" veya "Şirket" olarak anılacaktır.) ile FunBreak Vale mobil uygulaması üzerinden yolcuları taşıyan sürücü (Bundan böyle "Vale" olarak anılacaktır) arasındadır.

═══════════════════════════════════════════════════════════════════════════════

2. SÖZLEŞMENİN AMACI VE KONUSU

2.1. İşbu Sözleşme'nin konusu, yolcu için özel şoför ve vale bulma hizmetini sunan FunBreak Vale ile Vale arasındaki mobil uygulama ("Mobil Uygulama") ve web platformu kullanımına ilişkin hak ve yükümlülükleri belirtmektedir.

2.2. FunBreak Vale, Yolcu ile Vale arasında aracılık hizmeti sunan bir teknoloji platformudur. FunBreak Vale, Vale ile herhangi bir işçi-işveren ilişkisi kurmamakta olup, Vale bağımsız çalışan statüsünde hizmet vermektedir.

═══════════════════════════════════════════════════════════════════════════════

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

───────────────────────────────────────────────────────────────────────────────

3.2. Başvurunun Kabul Edilmesi

3.2.1. Vale adayının başvurusunun kabulü tamamen FunBreak Vale'nin takdirindedir. Vale ve Vale adayları, kayıt formunu doldururken şahsi bilgileri hakkında doğru, kesin, güncel bilgiler vereceklerini kabul, beyan ve taahhüt eder. FunBreak Vale, kendisine iletilen bilgilerin eksik/yanlış olduğunu tespit ederse kaydı kabul etmeyebilir, dondurabilir veya silebilir.

3.2.2. FunBreak Vale'nin başvuruyu kabul etmesi, Vale ile FunBreak Vale arasında işçi-işveren, ücretli çalışan-işveren veya benzeri bir hukuki ilişki doğurmayacak, FunBreak Vale sadece uygulamanın platformlarını kullanma izni vermektedir.

3.2.3. Vale adayının, FunBreak Vale tarafından başvurusunun kabul edilmesi, bu kaydın hiçbir şekilde silinmeyeceği sonucu doğurmaz. Vale sözleşme hükümlerine, FunBreak Vale'nin belirttiği koşullara ve mevcut mevzuata uygun hareket etmekle yükümlüdür.

───────────────────────────────────────────────────────────────────────────────

3.3. Vale Profili ve Şartları

3.3.1. İşbu Sözleşme'nin tarafı olan Vale, FunBreak Vale ve üçüncü taraf web sayfalarındaki şifre ve hesap güvenliğinden kendisi sorumlu olduğunu kabul, beyan ve taahhüt eder.

3.3.2. Vale, kullanıcı adı ve kullanıcı şifrelerinin yetkili olmayan kişiler tarafından kullanılmasını önlemek ve gerekli denetimleri yapmakla yükümlüdür.

3.3.3. Vale, kendisinden kaynaklı vermiş olduğu kişisel bilgilerin FunBreak Vale tarafından saklanmasını, işlenmesini, depolanmasını kabul etmektedir.

3.3.4. Vale, kendilerine ait iletişim bilgileri ve sair verilerin FunBreak Vale tarafından ticari amaçlı faaliyetler için kullanılabileceğini kabul eder.

3.3.5. FunBreak Vale'de, Vale'ye ait kullanıcı adı, kullanıcı şifresi ile yapılan her işlem Vale tarafından yapılmış sayılır.

3.3.6. Vale, FunBreak Vale'nin kullanımında tersine mühendislik yapmayacağını kabul eder.

3.3.7. Vale, üyeliğini başka kişilerin kullanımına açamaz.

3.3.8. FunBreak Vale, verilen belgeler ve bilgilerin gerçek olmadığını tespit ederse Vale'nin uygulamaya giriş yapmasını yasaklayabilir.

3.3.9. Vale, aynı anda birden fazla cihazdan oturum açması durumunda eski oturumların sonlandırılabileceğini kabul eder.

═══════════════════════════════════════════════════════════════════════════════

4. VALE'NİN YÜKÜMLÜLÜKLERİ

4.1. FunBreak Vale'ye İlişkin Yükümlülükler

Vale, aşağıdaki hususları kabul, beyan ve taahhüt eder:

• FunBreak Vale'yi aktif bir şekilde kullanmayı, ulaşılabilir ve erişilebilir olmayı

• Kendisine gönderilen transfer taleplerini makul süre içerisinde değerlendirmeyi

• Transfer talebinin kabul edilmesi halinde en kısa zamanda Yolcu ile iletişime geçmeyi

• Yolcu'nun alım noktasına belirlenen zamanda varmayı

• Transfer aşamasında asla kendi aracını kullanmamayı, Yolcu'nun aracını kullanmayı

• Transfer işlemini bizzat kendisi gerçekleştirmeyi, başka bir sürücüye devretmemeyi

• GPS takibinin aktif olmasını sağlamayı

• FunBreak Vale tarafından belirlenen ücret tarifeleri dışında ücret talep etmemeyi

• Yolculuk süresince rota takibinin otomatik olarak kaydedileceğini kabul etmeyi

• Bekleme işlemini sistemde "Bekleme Başlat" butonuna basarak kayıt altına almayı

• Yolculuk tamamlandığında "Yolculuğu Tamamla" butonuna basmayı

• Mobil uygulamanın her zaman güncel versiyonunu kullanmayı

───────────────────────────────────────────────────────────────────────────────

4.2. Yolcu'ya Karşı Yükümlülükler

Vale, aşağıdaki hususları kabul, beyan ve taahhüt eder:

• Yolcu ile belirlenen zamanda buluşmayı ve hedeflenen konuma transfer etmeyi

• Transfer süresinde Yolcu'yu rahatsız edecek davranışlardan kaçınmayı

• Yolcu'ya karşı eylemlerinin suç unsuru oluşturmayacağını

• Yolcu'nun mahremiyet hakkına tecavüz edici girişimde bulunmayacağını

• Yolcu ile sistemdeki mesajlaşma özelliğini kullanarak iletişim kurmayı

• Yolcu'nun aracına özen göstermeyi, araç içinde sigara içmemeyi

• Trafik kurallarına tam olarak uymayı, hız sınırlarını aşmamayı

• Yolcu'nun özel eşyalarına dokunmamayı

───────────────────────────────────────────────────────────────────────────────

4.3. Kaza Sorumluluğu

4.3.1. Vale'nin transfer sürecinde kendi kusurundan dolayı kaza yapması halinde sorumluluğun Vale'de olduğunu kabul eder.

4.3.2. Vale'den kaynaklı olmayan nedenlerle kaza olması durumunda Vale'nin sorumluluktan kaçınabileceğini kabul eder.

4.3.3. Vale, kaza anında derhal FunBreak Vale'yi ve Yolcu'yu bilgilendirmeyi taahhüt eder.

4.3.4. Kaza sonrası Vale, kaza tutanağını FunBreak Vale ile paylaşmayı kabul eder.

───────────────────────────────────────────────────────────────────────────────

4.4. Ceza Sorumluluğu

4.4.1. Vale, trafik cezaları konusunda FunBreak Vale'nin herhangi bir sorumluluğu olmadığını kabul eder.

4.4.2. Transfer sırasında alınan trafik cezaları Vale'nin sorumluluğundadır.

═══════════════════════════════════════════════════════════════════════════════

5. VALE'NİN HAK VE YÜKÜMLÜLÜKLERİ

5.1. Vale, mobil uygulamada yer alan tüm sözleşme hükümlerine uygun hareket edeceğini kabul eder.

5.2. Vale, yetkisi dışında bulunan işlemlere tevessül etmeyeceğini kabul eder.

5.3. Vale, ücret ve ödeme politikasına karşı itirazda bulunmayacağını kabul eder.

5.4. Vale, hizmet kesintilerinden dolayı zararlardan sorumludur.

5.5. Vale, FunBreak Vale içindeki faaliyetlerinde ahlaka aykırı faaliyetlerde bulunmayacağını kabul eder.

5.6. Vale, sözleşme hükümlerine aykırı hareket etmesi durumunda zararları karşılamaktan sorumludur.

5.7. Vale, minimum 3.5 yıldız puanı korumayı taahhüt eder.

5.8. Vale, yolculuk ücretinden %30 komisyon kesileceğini kabul eder. Ödemeler haftalık yapılır.

═══════════════════════════════════════════════════════════════════════════════

6. FUNBREAK VALE'NİN HAK VE YÜKÜMLÜLÜKLERİ

6.1. FunBreak Vale, Vale'nin başvurularını reddetme hakkını saklı tutar.

6.2. FunBreak Vale, Vale'nin siparişlerini iptal etmekte serbesttir.

6.3. FunBreak Vale, içeriklerin hak sahibidir.

6.4. FunBreak Vale, platformu değiştirebilir.

6.5. FunBreak Vale, Sözleşme şartlarını değiştirme hakkını saklı tutar.

6.6. FunBreak Vale, Vale'lerin performansını izleme hakkına sahiptir.

6.7. FunBreak Vale, yolculukları inceleme hakkına sahiptir.

═══════════════════════════════════════════════════════════════════════════════

7. GİZLİLİK VE REKABET YASAĞI

7.1. Vale, gizli bilgileri üçüncü kişilere açıklayamaz.

7.2. Gizli Bilgiler; tüm iş, ticari, teknolojik, ekonomik bilgileri kapsar.

7.3. Vale, telif hakları konusunda tek sahipliğin FunBreak Vale olduğunu kabul eder.

7.4. Vale, Yolcu iletişim bilgilerini sistem dışında kullanmayacağını kabul eder.

7.5. Vale, FunBreak Vale ile rekabet edecek şekilde çalışmayacağını kabul eder.

═══════════════════════════════════════════════════════════════════════════════

8. KİŞİSEL VERİLERİN KORUNMASI

8.1. Vale, KVKK kapsamında kişisel verilerinin işlenebileceğini kabul eder.

8.2. Vale, kişisel verilerin korunması yükümlülüklerini yerine getirmeyi kabul eder.

8.3. Vale, verdiği verilerin KVKK çerçevesinde işleneceğini kabul eder.

8.4. Vale, paylaştığı verilere açık rıza verdiğini kabul eder.

8.5. Vale, 6698 Sayılı KVKK hükümlerine uygun hareket edeceğini kabul eder.

8.6. Vale, GPS konum ve rota verilerinin saklanacağını kabul eder.

═══════════════════════════════════════════════════════════════════════════════

9. SÖZLEŞMENİN SÜRESİ VE FESİH HAKKI

9.1. İşbu Sözleşme süresiz olarak düzenlenmiştir.

9.2. Vale, üyeliği iptal edilse dahi önceki eylemlerinden sorumludur.

9.3. 30 gün giriş yapmayan Vale tüm haklarından feragat etmiş sayılır.

9.4. Sözleşme ihlali halinde derhal fesih yapılabilir.

9.5. Vale, iptalden önce bekleyen ödemelerini talep edebilir.

9.6. Aşağıdaki durumlarda hesap kapatılabilir:
• Sahte belge sunması
• Yolcu'ya karşı suç işlemesi
• Sürekli düşük puan alması
• Mükerrer şikayet alması
• Trafik kazası yapması
• Alkollü hizmet vermesi
• Gizlilik kurallarını ihlal etmesi
• Rekabet yasağına aykırı davranması

═══════════════════════════════════════════════════════════════════════════════

10. İPTAL VE İADE POLİTİKASI

10.1. Vale Tarafından İptal:
Vale, kabul ettiği yolculuğu iptal ederse ücret alamaz.

10.2. Yolcu Tarafından İptal:
• 45 dakika veya daha fazla kala iptal: Ücretsiz
• 45 dakikadan az kala iptal: 1.500 TL iptal ücreti (%70'i Vale'ye)

10.3. Mücbir Sebepler:
Mücbir sebep halinde Vale iptal yapabilir ve yaptırıma tabi tutulmaz.

═══════════════════════════════════════════════════════════════════════════════

11. ÜCRET VE ÖDEME SİSTEMİ

11.1. Ücretlendirme Sistemi:
• 0-5 km: 1.500,00 TL
• 5-10 km: 1.700,00 TL
• 10-15 km: 1.900,00 TL
• 15-20 km: 2.100,00 TL
• 20-25 km: 2.300,00 TL
• 25-30 km: 2.500,00 TL
• 30-35 km: 2.700,00 TL
• 35-40 km: 2.900,00 TL

11.2. Bekleme Ücreti:
İlk 15 dakika ücretsiz, sonrası her 15 dk için 200 TL.

11.3. Saatlik Paket Sistemi:
• 0-4 saat: 3.000,00 TL
• 4-8 saat: 4.500,00 TL
• 8-12 saat: 6.000,00 TL

11.4. Komisyon:
Tüm yolculuklardan %30 komisyon kesilir.

11.5. Ödeme Dönemi:
Haftalık, her Pazartesi günü.

11.6. Ödeme Yöntemi:
Yolcu kart veya havale ile öder.

11.7. Fatura:
Vale fatura kesme yükümlülüğü varsa kesmekle yükümlüdür.

11.8. İndirim Kodları:
İndirim tutarı düşüldükten sonra komisyon hesaplanır.

═══════════════════════════════════════════════════════════════════════════════

12. MÜCBİR SEBEPLER VE SORUMSUZLUK BEYANLARI

12.1. Savaş, terör, deprem, yangın, sel, siber saldırı gibi durumlar mücbir sebeptir.

12.2. FunBreak Vale mücbir sebep nedeniyle yükümlülüklerini yerine getirememekten sorumlu değildir.

12.3. İnternet bağlantı sorunları ve teknik problemlerden FunBreak Vale sorumlu değildir.

12.4. Vale, gecikmelere ilişkin tazmin talebinde bulunmayacağını kabul eder.

12.5. Vale, FunBreak Vale'nin aracı platform olduğunu kabul eder.

12.6. Vale, puanlama sisteminden FunBreak Vale'yi sorumlu tutmayacağını kabul eder.

12.7. FunBreak Vale, içeriklerin doğruluğunu garanti etmez.

═══════════════════════════════════════════════════════════════════════════════

13. TELİF HAKLARI

13.1. Vale, içerik haklarını FunBreak Vale'ye vermiştir.

13.2. FunBreak Vale içerikleri izinsiz kullanılamaz.

13.3. Vale, başkasına ait içerik yüklemesinden sorumludur.

13.4. Vale, telif haklarını çiğnememeyi kabul eder.

═══════════════════════════════════════════════════════════════════════════════

14. SÖZLEŞMENİN BÜTÜNLÜĞÜ VE DEĞİŞİKLİKLER

14.1. Bir madde geçersiz olsa da diğerleri geçerliliğini korur.

14.2. FunBreak Vale sözleşme şartlarını değiştirebilir.

14.3. Vale değişiklikleri takip etmek zorundadır.

═══════════════════════════════════════════════════════════════════════════════

15. TEBLİGAT

15.1. Bildirimler e-posta ile yapılır.

15.2. Adres değişikliği 5 gün içinde bildirilmelidir.

15.3. E-posta 1 gün sonra tebliğ edilmiş sayılır.

═══════════════════════════════════════════════════════════════════════════════

16. DELİL SÖZLEŞMESİ

16.1. FunBreak Vale kayıtları delil olarak kabul edilir.

16.2. GPS ve sistem kayıtları delil niteliğindedir.

═══════════════════════════════════════════════════════════════════════════════

17. YETKİLİ MAHKEME

17.1. İstanbul (Çağlayan) Mahkemeleri yetkilidir.

17.2. Taraflar bu yetkiyi kabul eder.

═══════════════════════════════════════════════════════════════════════════════

18. SÖZLEŞME EKLERİ

18.1. Sözleşme ekleri:
1. Kişisel Verilerin Korunmasına Dair Aydınlatma Metni
2. Özel Nitelikli Kişisel Verilerin İşlenmesine Dair Açık Rıza Beyanı
3. Açık Rıza Beyanı
4. Verilerin Gizliliğine Dair Gizlilik Taahhütleri
5. Sorumluluk Beyanı
6. FunBreak Vale tarafından hazırlanan rehberler

18.2. Ekler değiştirilebilir, Vale takip etmekle yükümlüdür.

═══════════════════════════════════════════════════════════════════════════════

19. YÜRÜRLÜK

19.1. Vale, sözleşmeyi okuduğunu ve anladığını kabul eder.

19.2. Sözleşme elektronik onay ile yürürlüğe girer.

19.3. Sözleşme Türkiye Cumhuriyeti yasalarına tabidir.

═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ

Mersis: 0388195898700001
Ticaret Sicil: 1105910
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

Versiyon: 4.0''';
  }

  String _getKVKKText() {
    return '''═══════════════════════════════════════════════════════════════════════════════
FUNBREAK VALE
VALELER İÇİN KİŞİSEL VERİLERİN İŞLENMESİ VE KORUNMASINA YÖNELİK 
AYDINLATMA METNİ
═══════════════════════════════════════════════════════════════════════════════

FunBreak Global Teknoloji Limited Şirketi ("FunBreak Vale" veya "Şirket") olarak, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında veri sorumlusu sıfatıyla, vale olarak hizmet veren sürücülerimizin kişisel verilerinin işlenmesi hakkında aydınlatma yükümlülüğümüzü yerine getirmek amacıyla bu metni hazırladık.

═══════════════════════════════════════════════════════════════════════════════

1. VERİ SORUMLUSU

Veri Sorumlusu: FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ
Mersis No: 0388195898700001
Adres: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com

═══════════════════════════════════════════════════════════════════════════════

2. İŞLENEN KİŞİSEL VERİLER

FunBreak Vale olarak aşağıdaki kişisel verilerinizi işlemekteyiz:

2.1. Kimlik Bilgileri
• Ad, soyad
• T.C. kimlik numarası
• Doğum tarihi
• Nüfus cüzdanı/kimlik kartı fotokopisi

2.2. İletişim Bilgileri
• Cep telefonu numarası
• E-posta adresi
• İkametgah adresi

2.3. Ehliyet Bilgileri
• Ehliyet sınıfı
• Ehliyet veriliş tarihi
• Ehliyet numarası
• Ehliyet fotokopisi

2.4. Mali Bilgiler
• IBAN numarası
• Banka hesap bilgileri

2.5. Sağlık Bilgileri (Özel Nitelikli)
• Sağlık raporu (sürücülüğe engel durumu olmadığını gösterir)

2.6. Adli Sicil Bilgileri (Özel Nitelikli)
• Adli sicil kaydı
• Trafik ceza puanı bilgisi

2.7. Konum Bilgileri
• GPS konum verileri (yolculuk sırasında)
• Rota takip verileri (route tracking)
• Bekleme noktaları (waiting points)
• Bırakma konumları (dropoff location)

2.8. Performans Verileri
• Yolculuk sayısı
• Müşteri puanlamaları
• İptal oranları
• Çalışma süreleri

2.9. Cihaz ve Uygulama Bilgileri
• Cihaz kimliği (Device ID)
• IP adresi
• Uygulama versiyon bilgisi
• İşletim sistemi bilgisi

2.10. Görsel Veriler
• Profil fotoğrafı
• Araç içi fotoğraflar (gerekli hallerde)

═══════════════════════════════════════════════════════════════════════════════

3. KİŞİSEL VERİLERİN İŞLENME AMAÇLARI

Kişisel verileriniz aşağıdaki amaçlarla işlenmektedir:

3.1. Vale Hizmeti Sunumu
• Platform üzerinden vale hizmeti sunabilmeniz
• Yolcu ile eşleştirme yapılabilmesi
• Yolculuk sürecinin yönetilmesi

3.2. Kimlik Doğrulama ve Güvenlik
• Vale kimliğinin doğrulanması
• Sahtecilik ve dolandırıcılığın önlenmesi
• Platform güvenliğinin sağlanması

3.3. Yasal Yükümlülükler
• Ehliyet ve sürücülük yeterliliğinin kontrolü
• Adli sicil kaydı kontrolü
• Sağlık durumunun teyidi

3.4. Ödeme İşlemleri
• Haftalık ödeme yapılabilmesi
• Komisyon hesaplamaları
• Mali raporlama

3.5. Performans Değerlendirme
• Hizmet kalitesinin ölçülmesi
• Müşteri memnuniyetinin takibi
• Puan ortalamasının hesaplanması

3.6. Konum Takibi
• Yolculuk süresince canlı takip
• Güvenlik amaçlı konum kaydı
• Mesafe hesaplaması ve ücretlendirme

3.7. İletişim
• Bilgilendirme mesajları gönderilmesi
• Acil durum iletişimi
• Destek hizmeti sunulması

3.8. Hukuki Süreçler
• Olası uyuşmazlıklarda delil olarak kullanım
• Yasal taleplere yanıt verilmesi
• Dava ve icra süreçlerinin yürütülmesi

═══════════════════════════════════════════════════════════════════════════════

4. KİŞİSEL VERİLERİN AKTARILMASI

Kişisel verileriniz aşağıdaki taraflara aktarılabilir:

4.1. Yolculara
• Ad ve profil fotoğrafınız
• Araç bilgileri (varsa)
• Konum bilgisi (yolculuk sırasında)
• Puanlama bilgisi

4.2. İş Ortaklarına
• Ödeme işlemleri için bankalar
• SMS/bildirim servisleri
• Harita ve navigasyon servisleri (Google Maps vb.)

4.3. Resmi Kurumlara
• Emniyet Genel Müdürlüğü (yasal talep halinde)
• Mahkemeler ve icra daireleri
• Vergi daireleri
• Düzenleyici kurumlar

4.4. Hizmet Sağlayıcılarına
• Sunucu ve hosting hizmetleri
• Bulut depolama servisleri
• Analitik araçları

═══════════════════════════════════════════════════════════════════════════════

5. KİŞİSEL VERİLERİN TOPLANMA YÖNTEMİ VE HUKUKİ SEBEBİ

5.1. Toplama Yöntemleri
• Mobil uygulama üzerinden
• Web platformu üzerinden
• Fiziki başvuru formları ile
• E-posta ve telefon yoluyla
• Otomatik yollarla (GPS, cihaz bilgileri)

5.2. Hukuki Sebepler (KVKK m.5 ve m.6)

a) Açık Rıza: Özel nitelikli kişisel veriler (sağlık raporu, adli sicil)

b) Sözleşmenin İfası: Vale olarak hizmet verebilmeniz için gerekli veriler

c) Hukuki Yükümlülük: Yasal düzenlemeler gereği tutulması gereken kayıtlar

d) Meşru Menfaat: Platform güvenliği ve hizmet kalitesinin sağlanması

e) Bir Hakkın Tesisi: Hukuki uyuşmazlıklarda hak arama

═══════════════════════════════════════════════════════════════════════════════

6. KİŞİSEL VERİLERİN SAKLANMA SÜRESİ

• Aktif vale hesabı süresince
• Hesap kapatıldıktan sonra yasal saklama süreleri boyunca
• Mali kayıtlar: 10 yıl (Vergi Usul Kanunu)
• Hukuki uyuşmazlık riski olan veriler: Zamanaşımı süresince
• GPS ve rota verileri: 5 yıl
• Performans verileri: 3 yıl

═══════════════════════════════════════════════════════════════════════════════

7. KVKK KAPSAMINDA HAKLARINIZ

KVKK'nın 11. maddesi uyarınca aşağıdaki haklara sahipsiniz:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme

b) Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme

c) Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını öğrenme

d) Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü kişileri bilme

e) Kişisel verilerinizin eksik veya yanlış işlenmiş olması hâlinde bunların düzeltilmesini isteme

f) KVKK'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel verilerinizin silinmesini veya yok edilmesini isteme

g) (e) ve (f) bentleri uyarınca yapılan işlemlerin, kişisel verilerinizin aktarıldığı üçüncü kişilere bildirilmesini isteme

h) İşlenen verilerinizin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme

i) Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara uğramanız hâlinde zararın giderilmesini talep etme

═══════════════════════════════════════════════════════════════════════════════

8. BAŞVURU YÖNTEMİ

KVKK kapsamındaki taleplerinizi aşağıdaki yöntemlerle iletebilirsiniz:

• E-posta: info@funbreakvale.com (Konu: KVKK Talebi)
• Yazılı Başvuru: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
• Kayıtlı Elektronik Posta (KEP): [KEP adresi]

Başvurunuzda:
• Ad, soyad ve imza (yazılı başvurularda)
• T.C. kimlik numarası
• Tebligata esas adres veya e-posta adresi
• Talep konusu

belirtilmelidir.

Başvurular en geç 30 gün içinde ücretsiz olarak sonuçlandırılır. İşlemin ayrıca bir maliyet gerektirmesi hâlinde, Kişisel Verileri Koruma Kurulu tarafından belirlenen tarifedeki ücret alınabilir.

═══════════════════════════════════════════════════════════════════════════════

9. GÜVENLİK ÖNLEMLERİ

Kişisel verilerinizin güvenliği için:

• SSL/TLS şifreleme kullanılmaktadır
• Erişim yetkilendirme sistemleri uygulanmaktadır
• Düzenli güvenlik denetimleri yapılmaktadır
• Veri yedekleme sistemleri mevcuttur
• Çalışan eğitimleri verilmektedir

═══════════════════════════════════════════════════════════════════════════════

10. DEĞİŞİKLİKLER

Bu aydınlatma metni gerektiğinde güncellenebilir. Önemli değişiklikler uygulama üzerinden bildirilecektir.

═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ

Mersis: 0388195898700001
Ticaret Sicil: 1105910
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

═══════════════════════════════════════════════════════════════════════════════

Versiyon: 4.0''';
  }

  String _getSpecialDataText() {
    return '''═══════════════════════════════════════════════════════════════════════════════
FUNBREAK VALE
VALELERE İLİŞKİN ÖZEL NİTELİKLİ KİŞİSEL VERİLERİN İŞLENMESİNE DAİR 
AÇIK RIZA BEYANI
═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") tarafından, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında özel nitelikli kişisel verilerimin işlenmesine ilişkin aşağıdaki hususlarda bilgilendirildim ve açık rızam ile onay veriyorum.

═══════════════════════════════════════════════════════════════════════════════

1. ÖZEL NİTELİKLİ KİŞİSEL VERİ NEDİR?

KVKK'nın 6. maddesi uyarınca, kişilerin ırkı, etnik kökeni, siyasi düşüncesi, felsefi inancı, dini, mezhebi veya diğer inançları, kılık ve kıyafeti, dernek, vakıf ya da sendika üyeliği, sağlığı, cinsel hayatı, ceza mahkûmiyeti ve güvenlik tedbirleriyle ilgili verileri ile biyometrik ve genetik verileri özel nitelikli kişisel veri olarak kabul edilmektedir.

Bu veriler, nitelikleri itibarıyla daha yüksek koruma gerektirmekte olup, işlenmesi ancak açık rıza ile veya kanunda öngörülen hallerde mümkündür.

═══════════════════════════════════════════════════════════════════════════════

2. İŞLENECEK ÖZEL NİTELİKLİ KİŞİSEL VERİLERİM

FunBreak Vale platformunda vale olarak hizmet verebilmem için aşağıdaki özel nitelikli kişisel verilerimin işlenmesi gerekmektedir:

───────────────────────────────────────────────────────────────────────────────

2.1. SAĞLIK VERİLERİ

İşlenecek Veriler:
• Sağlık raporu (sürücülüğe engel durumu olmadığını gösterir)
• Sağlık durumu beyanı
• Kronik hastalık bilgisi (varsa ve sürücülüğü etkiliyorsa)

İşlenme Amacı:
• Güvenli sürüş yapabilme yeterliliğinizin tespiti
• Yolcu güvenliğinin sağlanması
• Yasal gerekliliklerin yerine getirilmesi
• Olası acil durumlarda gerekli müdahalenin yapılabilmesi

İşlenme Süresi:
• Aktif vale hesabı süresince
• Hesap kapatıldıktan sonra 5 yıl

───────────────────────────────────────────────────────────────────────────────

2.2. ADLİ SİCİL VE CEZA MAHKÛMİYETİ VERİLERİ

İşlenecek Veriler:
• Adli sicil kaydı (sabıka kaydı)
• Arşiv kaydı
• Trafik ceza puanı bilgisi

İşlenme Amacı:
• Sürücülük yapmanızı engelleyen bir mahkûmiyet olup olmadığının kontrolü
• Yolcu güvenliğinin sağlanması
• Trafik kurallarına uyum geçmişinizin değerlendirilmesi
• Platform güvenilirliğinin sağlanması

Değerlendirme Kriterleri:
• Kasten işlenen suçlardan mahkûmiyet
• Trafik suçları
• Şiddet içeren suçlar
• Cinsel suçlar
• Uyuşturucu madde suçları

İşlenme Süresi:
• Aktif vale hesabı süresince
• Hesap kapatıldıktan sonra 10 yıl (yasal yükümlülük)

═══════════════════════════════════════════════════════════════════════════════

3. ÖZEL NİTELİKLİ VERİLERİN İŞLENME ŞARTLARI

KVKK'nın 6. maddesi uyarınca, özel nitelikli kişisel verilerim ancak:

a) Açık rızam ile, veya

b) Sağlık ve cinsel hayat dışındaki özel nitelikli veriler için kanunlarda öngörülmesi halinde

işlenebilir.

FunBreak Vale, özel nitelikli kişisel verilerimi işbu Açık Rıza Beyanı kapsamında verdiğim açık rızaya dayanarak işlemektedir.

═══════════════════════════════════════════════════════════════════════════════

4. VERİLERİN AKTARILMASI

Özel nitelikli kişisel verilerim aşağıdaki taraflara aktarılabilir:

4.1. Zorunlu Aktarımlar (Yasal Yükümlülük)
• Emniyet Genel Müdürlüğü (soruşturma talepleri)
• Mahkemeler (dava süreçleri)
• Savcılıklar (soruşturma talepleri)
• Düzenleyici ve denetleyici kurumlar

4.2. Yolculara Aktarım
• Özel nitelikli verilerim yolculara AKTARILMAZ
• Sadece ad, fotoğraf ve puan bilgisi paylaşılır

4.3. İş Ortaklarına Aktarım
• Özel nitelikli verilerim iş ortaklarına AKTARILMAZ
• Sadece gerekli hallerde anonimleştirilmiş veriler kullanılabilir

═══════════════════════════════════════════════════════════════════════════════

5. VERİLERİN KORUNMASI

Özel nitelikli kişisel verilerim için alınan güvenlik önlemleri:

Teknik Önlemler:
• Şifreleme (encryption) ile saklama
• Erişim kontrolü ve yetkilendirme
• Güvenlik duvarı koruması
• Düzenli güvenlik testleri
• Log kayıtları ve izleme

İdari Önlemler:
• Sınırlı personel erişimi
• Gizlilik sözleşmeleri
• Periyodik eğitimler
• Veri işleme politikaları
• Denetim mekanizmaları

═══════════════════════════════════════════════════════════════════════════════

6. HAKLARIM

KVKK'nın 11. maddesi kapsamında özel nitelikli kişisel verilerim ile ilgili:

• Verilerimin işlenip işlenmediğini öğrenme
• İşlenmişse buna ilişkin bilgi talep etme
• İşlenme amacını öğrenme
• Aktarıldığı üçüncü kişileri bilme
• Eksik veya yanlış işlenmişse düzeltilmesini isteme
• Silinmesini veya yok edilmesini isteme
• Otomatik analiz sonucu aleyhe çıkan sonuca itiraz etme
• Kanuna aykırı işleme nedeniyle zararın giderilmesini talep etme

haklarına sahibim.

═══════════════════════════════════════════════════════════════════════════════

7. RIZANIN GERİ ALINMASI

Açık rızamı her zaman geri alma hakkına sahip olduğumu biliyorum.

Ancak, rızamı geri almam halinde:
• Vale olarak hizmet veremeyeceğimi
• Hesabımın askıya alınacağını veya kapatılacağını
• Rıza geri alınmadan önce yapılan işlemlerin hukuka uygun olduğunu

kabul ediyorum.

Rızamı geri almak için:
• E-posta: info@funbreakvale.com
• Yazılı başvuru: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul

adreslerine başvurabilirim.

═══════════════════════════════════════════════════════════════════════════════

8. BEYAN VE ONAY

İşbu Açık Rıza Beyanı'nı okuyarak;

✓ Özel nitelikli kişisel verilerimin neler olduğunu,

✓ Bu verilerin hangi amaçlarla işleneceğini,

✓ Kimlere aktarılabileceğini,

✓ Ne kadar süre saklanacağını,

✓ Haklarımın neler olduğunu,

✓ Rızamı her zaman geri alabileceğimi

anladığımı ve özel nitelikli kişisel verilerimin yukarıda belirtilen şekilde işlenmesine AÇIK RIZAMLA ONAY VERİYORUM.

═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ

Mersis: 0388195898700001
Ticaret Sicil: 1105910
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

═══════════════════════════════════════════════════════════════════════════════

Versiyon: 4.0''';
  }

  String _getOpenConsentText() {
    return '''═══════════════════════════════════════════════════════════════════════════════
FUNBREAK VALE
AÇIK RIZA BEYANI
═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ ("FunBreak Vale" veya "Şirket") tarafından, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında kişisel verilerimin işlenmesine ilişkin aşağıdaki hususlarda bilgilendirildim ve açık rızam ile onay veriyorum.

═══════════════════════════════════════════════════════════════════════════════

1. AÇIK RIZA NEDİR?

KVKK'nın 3. maddesine göre açık rıza; "belirli bir konuya ilişkin, bilgilendirilmeye dayanan ve özgür iradeyle açıklanan rıza" olarak tanımlanmaktadır.

Bu beyan ile FunBreak Vale platformunda vale olarak hizmet verebilmem için gerekli olan kişisel verilerimin işlenmesine açık rızamı vermekteyim.

═══════════════════════════════════════════════════════════════════════════════

2. İŞLENECEK KİŞİSEL VERİLERİM

Aşağıdaki kişisel verilerimin işlenmesine açık rıza veriyorum:

───────────────────────────────────────────────────────────────────────────────

2.1. KİMLİK BİLGİLERİ
• Ad, soyad
• T.C. kimlik numarası
• Doğum tarihi
• Kimlik belgesi fotokopisi

2.2. İLETİŞİM BİLGİLERİ
• Cep telefonu numarası
• E-posta adresi
• İkametgah adresi

2.3. EHLİYET BİLGİLERİ
• Ehliyet sınıfı ve numarası
• Ehliyet veriliş tarihi
• Ehliyet fotokopisi

2.4. MALİ BİLGİLER
• IBAN numarası
• Banka hesap bilgileri
• Kazanç ve ödeme bilgileri

2.5. KONUM VERİLERİ
• Anlık GPS konumu (yolculuk sırasında)
• Rota takip verileri
• Bekleme noktaları
• Bırakma konumları
• Konum geçmişi

2.6. PERFORMANS VERİLERİ
• Yolculuk istatistikleri
• Müşteri puanlamaları
• İptal oranları
• Çevrimiçi süreleri
• Kabul/red oranları

2.7. CİHAZ VE TEKNİK VERİLER
• Cihaz kimliği (Device ID)
• IP adresi
• Uygulama versiyonu
• İşletim sistemi bilgisi
• Oturum bilgileri

2.8. GÖRSEL VERİLER
• Profil fotoğrafı

═══════════════════════════════════════════════════════════════════════════════

3. VERİLERİN İŞLENME AMAÇLARI

Kişisel verilerimin aşağıdaki amaçlarla işlenmesine rıza veriyorum:

3.1. Platform Hizmetleri
• Vale olarak hizmet sunabilmem
• Yolcu eşleştirmesi yapılabilmesi
• Yolculuk süreçlerinin yönetilmesi
• Uygulama özelliklerinin kullanılabilmesi

3.2. Güvenlik ve Doğrulama
• Kimlik doğrulaması
• Hesap güvenliğinin sağlanması
• Sahtecilik önleme
• Yetkisiz erişimin engellenmesi

3.3. Ödeme İşlemleri
• Haftalık ödemelerin yapılması
• Komisyon hesaplamaları
• Mali raporlama
• Fatura işlemleri

3.4. Konum Takibi
• Canlı konum takibi (yolculuk sırasında)
• Mesafe hesaplaması
• Güvenlik amaçlı kayıt
• Hizmet kalitesi kontrolü

3.5. İletişim
• Bilgilendirme mesajları
• Kampanya ve duyurular
• Destek hizmetleri
• Acil durum bildirimleri

3.6. Analiz ve İyileştirme
• Hizmet kalitesinin ölçülmesi
• Platform geliştirme çalışmaları
• Kullanıcı deneyimi iyileştirme
• İstatistiksel analizler

3.7. Hukuki Süreçler
• Yasal yükümlülüklerin yerine getirilmesi
• Uyuşmazlık çözümü
• Delil olarak kullanım
• Resmi kurum taleplerine yanıt

═══════════════════════════════════════════════════════════════════════════════

4. VERİLERİN AKTARILMASI

Kişisel verilerimin aşağıdaki taraflara aktarılmasına rıza veriyorum:

4.1. Yolculara
• Ad ve profil fotoğrafım
• Anlık konumum (yolculuk sırasında)
• Puan ortalaması
• İletişim (köprü arama sistemi üzerinden)

4.2. İş Ortaklarına
• Ödeme işlemleri için banka/finans kuruluşları
• SMS ve bildirim servisleri
• Harita servisleri (Google Maps)
• Bulut hizmet sağlayıcıları

4.3. Resmi Kurumlara
• Mahkemeler ve icra daireleri
• Emniyet ve savcılık
• Vergi daireleri
• Düzenleyici kurumlar

═══════════════════════════════════════════════════════════════════════════════

5. VERİLERİN SAKLANMA SÜRESİ

Kişisel verilerimin aşağıdaki sürelerde saklanmasına rıza veriyorum:

• Hesap aktif olduğu sürece
• Hesap kapatıldıktan sonra:
  - Kimlik ve iletişim bilgileri: 10 yıl
  - Mali bilgiler: 10 yıl (Vergi Usul Kanunu)
  - Konum verileri: 5 yıl
  - Performans verileri: 3 yıl
  - Teknik veriler: 2 yıl

═══════════════════════════════════════════════════════════════════════════════

6. HAKLARIM

KVKK'nın 11. maddesi kapsamında aşağıdaki haklara sahip olduğumu biliyorum:

a) Kişisel verilerimin işlenip işlenmediğini öğrenme

b) Kişisel verilerim işlenmişse buna ilişkin bilgi talep etme

c) Kişisel verilerimin işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını öğrenme

d) Yurt içinde veya yurt dışında kişisel verilerimin aktarıldığı üçüncü kişileri bilme

e) Kişisel verilerimin eksik veya yanlış işlenmiş olması hâlinde bunların düzeltilmesini isteme

f) KVKK'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel verilerimin silinmesini veya yok edilmesini isteme

g) Düzeltme ve silme işlemlerinin, verilerin aktarıldığı üçüncü kişilere bildirilmesini isteme

h) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhime bir sonucun ortaya çıkmasına itiraz etme

i) Kişisel verilerimin kanuna aykırı olarak işlenmesi sebebiyle zarara uğramam hâlinde zararın giderilmesini talep etme

═══════════════════════════════════════════════════════════════════════════════

7. RIZANIN GERİ ALINMASI

Açık rızamı her zaman, herhangi bir gerekçe göstermeksizin geri alma hakkına sahip olduğumu biliyorum.

Rızamı geri almak için:
• E-posta: info@funbreakvale.com
• Yazılı başvuru: Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul

adreslerine başvurabilirim.

Rızamı geri almam halinde:
• Vale hesabımın kapatılacağını
• Platform hizmetlerinden yararlanamayacağımı
• Geri alma öncesi yapılan işlemlerin geçerliliğini koruyacağını

kabul ediyorum.

═══════════════════════════════════════════════════════════════════════════════

8. BEYAN VE ONAY

İşbu Açık Rıza Beyanı'nı okuyarak;

✓ Hangi kişisel verilerimin işleneceğini,

✓ Bu verilerin hangi amaçlarla işleneceğini,

✓ Kimlere aktarılabileceğini,

✓ Ne kadar süre saklanacağını,

✓ KVKK kapsamındaki haklarımın neler olduğunu,

✓ Rızamı her zaman geri alabileceğimi

anladığımı beyan eder, kişisel verilerimin yukarıda belirtilen şekilde işlenmesine AÇIK RIZAMLA ONAY VERİYORUM.

═══════════════════════════════════════════════════════════════════════════════

FUNBREAK GLOBAL TEKNOLOJİ LİMİTED ŞİRKETİ

Mersis: 0388195898700001
Ticaret Sicil: 1105910
Armağanevler Mah. Ortanca Sk. No: 69 İç Kapı No: 22 Ümraniye/İstanbul
Tel: 0533 448 82 53
E-posta: info@funbreakvale.com
Web: www.funbreakvale.com

═══════════════════════════════════════════════════════════════════════════════

Versiyon: 4.0''';
  }
}
