import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // FIREBASE IMPORT!
import 'package:http/http.dart' as http; // HTTP IMPORT!
import 'dart:convert'; // JSON IMPORT!
import '../providers/admin_api_provider.dart';

class DriverNotificationsBottomSheet extends StatefulWidget {
  const DriverNotificationsBottomSheet({Key? key}) : super(key: key);

  @override
  State<DriverNotificationsBottomSheet> createState() => _DriverNotificationsBottomSheetState();
}

class _DriverNotificationsBottomSheetState extends State<DriverNotificationsBottomSheet> {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    
    // FIREBASE MESAJ DİNLEME - UI REFRESH İÇİN!
    _setupFirebaseListener();
  }
  
  // FIREBASE MESSAGE LISTENER - UI REFRESH!
  void _setupFirebaseListener() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('🔔 DriverNotifications Widget: Firebase message alındı');
        print('   🏷️ Type: ${message.data['type'] ?? 'bilinmeyen'}');
        
        // Duyuru tipindeyse UI'yı refresh et
        if (message.data['type'] == 'announcement') {
          print('🔄 DUYURU WIDGET REFRESH başlatılıyor...');
          
          // 2 saniye bekle (database'e kayıt tamamlansın)
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              print('🔄 Duyurular listesi yenileniyor...');
              _loadData(); // Widget'ı yenile!
            }
          });
        }
      });
      
      print('✅ DriverNotifications Firebase listener kuruldu');
    } catch (e) {
      print('❌ Firebase listener setup hatası: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      if (!mounted) return;
      
      // ŞOFÖR DUYURULARINI ÇEK - PROVIDER'DAN AL!
      final adminApi = Provider.of<AdminApiProvider>(context, listen: false);
      
      print('🔔 AdminApiProvider başarıyla alındı: ${adminApi.runtimeType}');
      
      print('🔔 Şoför duyuruları ve push notifications yükleniyor...');
      
      // 1. Şoför duyurularını çek (driver_announcements tablosundan)
      final announcements = await adminApi.getDriverAnnouncements();
      
      // 2. Push notifications'ları çek (sadece şoför hedefli olanlar)
      List<Map<String, dynamic>> pushNotifications = [];
      try {
        final pushResponse = await http.get(
          Uri.parse('https://admin.funbreakvale.com/api/get_push_notifications.php?target=drivers'),
          headers: {'Content-Type': 'application/json'},
        );
        
        if (pushResponse.statusCode == 200) {
          final pushData = json.decode(pushResponse.body);
          if (pushData['success'] == true) {
            pushNotifications = List<Map<String, dynamic>>.from(pushData['notifications'] ?? []);
            print('📢 Push notifications (şoför): ${pushNotifications.length} adet');
          }
        }
      } catch (e) {
        print('⚠️ Push notifications çekme hatası: $e');
      }
      
      if (mounted) {
        setState(() {
          // 1. Şoför duyurularını ekle
          List<Map<String, dynamic>> allNotifications = announcements.map((announcement) => {
            'title': announcement['title'],
            'content': announcement['subtitle'], // subtitle -> content mapping
            'created_at': announcement['date'],
            'id': announcement['id'],
            'is_active': 1,
            'type': 'şoför_duyurusu', // Tip belirt
          }).toList();
          
          // 2. Push notifications'ları da ekle
          for (var push in pushNotifications) {
            allNotifications.add({
              'title': push['title'] ?? '',
              'content': push['message'] ?? '',
              'created_at': push['created_at'] ?? '',
              'id': 'push_${push['id']}', // Push ID'lerini ayır
              'is_active': 1,
              'type': 'push_notification', // Tip belirt
            });
          }
          
          // Tarihe göre sırala (en yeni önce)
          allNotifications.sort((a, b) {
            DateTime dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
            DateTime dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
            return dateB.compareTo(dateA);
          });
          
          _announcements = allNotifications;
          _isLoading = false;
          
          print('✅ Şoför tüm bildirimler yüklendi:');
          print('   📢 Şoför Duyuru: ${announcements.length} adet');
          print('   📧 Push Notification: ${pushNotifications.length} adet');
          print('   📊 Toplam: ${_announcements.length} adet');
        });
      }
    } catch (e) {
      print('❌ Şoför bildirim yükleme hatası: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Bildirimler',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                // SADECE DUYURULAR HEADER
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.campaign, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      const Text(
                        'Şoför Duyuruları', 
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_announcements.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_announcements.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Content - SADECE DUYURULAR!
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFD700),
                    ),
                  )
                : _buildAnnouncementsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsTab() {
    if (_announcements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.campaign,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Henüz duyuru bulunmuyor',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        return _buildNotificationCard(_announcements[index]);
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showFullNotificationDialog(item), // TIKLANABİLİR!
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      item['type'] == 'push_notification' ? Icons.notifications : Icons.campaign,
                      color: const Color(0xFFFFD700),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['title'] ?? 'Başlık',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: item['type'] == 'push_notification' 
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item['type'] == 'push_notification' ? 'Push' : 'Duyuru',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: item['type'] == 'push_notification' 
                                      ? Colors.blue[700] 
                                      : Colors.orange[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['content'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📖 Tam okumak için tıklayın',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item['created_at'] != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Tarih: ${item['created_at']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // TAM BİLDİRİM DETAY GÖSTER - TIKLANABİLİR!
  void _showFullNotificationDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      item['type'] == 'push_notification' ? Icons.notifications : Icons.campaign,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item['title'] ?? 'Bildirim Detayı',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['content'] ?? 'İçerik bulunamadı.',
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item['type'] == 'push_notification' ? Icons.push_pin : Icons.campaign,
                              color: Colors.grey[600],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tür: ${item['type'] == 'push_notification' ? 'Push Notification' : 'Şoför Duyurusu'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item['created_at'] != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                color: Colors.grey[600],
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tarih: ${item['created_at']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Close button
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Kapat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
}