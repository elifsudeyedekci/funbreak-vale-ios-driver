import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 SERVICES IMPORT!
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:geolocator/geolocator.dart'; // 🔥 KONUM PAYLAŞIMI!
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // 🔥 HARITA AÇMAK İÇİN!

// ŞOFÖR MESAJLAŞMA EKRANI - MÜŞTERI İLE KARŞILIKLI!
class RideChatScreen extends StatefulWidget {
  final String rideId;
  final String customerName;
  final bool isDriver;

  const RideChatScreen({
    Key? key,
    required this.rideId,
    required this.customerName,
    required this.isDriver,
  }) : super(key: key);

  @override
  State<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends State<RideChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isRecording = false;
  
  bool _isSyncing = false;
  DateTime? _lastSyncedAt;
  String get _cacheKey => 'ride_chat_${widget.rideId}';
  
  // GERÇEK SES KAYDI İÇİN - FLUTTER SOUND!
  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _messagePollingTimer;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    _loadCachedMessages();
    _loadChatHistory();
    _startRealTimeMessaging(); // GERÇEK ZAMANLI SİSTEM!
  }
  
  Future<void> _initializeAudio() async {
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    
    await _audioRecorder!.openRecorder();
    await _audioPlayer!.openPlayer();
    
    print('🎤 ŞOFÖR Ses kayıt sistemi başlatıldı');
  }

  Future<void> _loadCachedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached == null || cached.isEmpty) {
        return;
      }

      final decoded = jsonDecode(cached);
      if (decoded is! List) {
        return;
      }

      final List<Map<String, dynamic>> cachedMessages = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _messages
          ..clear()
          ..addAll(cachedMessages.map((msg) => {
                ...msg,
                'timestamp': DateTime.tryParse(msg['timestamp']?.toString() ?? '') ?? DateTime.now(),
              }));
      });

      print('💾 ŞOFÖR: Yerel mesaj cache yüklendi (${_messages.length})');
    } catch (e) {
      print('❌ ŞOFÖR: Yerel mesaj cache okuma hatası: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    if (_isSyncing) {
      return;
    }

    print('💬 ŞOFÖR Chat geçmişi yükleniyor - Ride: ${widget.rideId}');
    _isSyncing = true;

    try {
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_ride_messages.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': widget.rideId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['messages'] != null) {
          final apiMessages = List<Map<String, dynamic>>.from(data['messages']);

          final merged = <Map<String, dynamic>>[];
          for (final apiMessage in apiMessages) {
            merged.add({
              'id': apiMessage['id'].toString(),
              'message': apiMessage['message_content'] ?? '',
              'sender_type': apiMessage['sender_type'] ?? 'customer',
              'timestamp': DateTime.tryParse(apiMessage['created_at'] ?? '') ?? DateTime.now(),
              'type': apiMessage['message_type'] ?? 'text',
              'audioPath': apiMessage['file_path'],
              'duration': apiMessage['duration']?.toString() ?? '0',
            });
          }

          // 🔥 GÜÇLÜ DUPLICATE KONTROLÜ - ID + MESSAGE CONTENT + TIMESTAMP
          final existingSignatures = _messages.map((m) {
            final msgContent = m['message']?.toString() ?? '';
            final msgTime = (m['timestamp'] as DateTime).millisecondsSinceEpoch ~/ 1000; // Saniye hassasiyeti
            return '${msgContent}_$msgTime';
          }).toSet();
          
          merged.removeWhere((msg) {
            final msgContent = msg['message']?.toString() ?? '';
            final msgTime = (msg['timestamp'] as DateTime).millisecondsSinceEpoch ~/ 1000;
            final signature = '${msgContent}_$msgTime';
            return existingSignatures.contains(signature);
          });

          if (merged.isNotEmpty) {
            setState(() {
              _messages
                ..addAll(merged)
                ..sort((a, b) {
                  final at = a['timestamp'] as DateTime;
                  final bt = b['timestamp'] as DateTime;
                  return at.compareTo(bt);
                });
            });

            print('🔍 ŞOFÖR: Yeni mesajlar eklendi → ${merged.length} adet');
          }

          await _persistMessages();
          _lastSyncedAt = DateTime.now();

          print('✅ ŞOFÖR Chat güncellendi: toplam ${_messages.length} mesaj');
        }
      } else {
        print('❌ ŞOFÖR Chat HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ŞOFÖR Chat geçmişi yüklenirken hata: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _persistMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = jsonEncode(_messages
          .map((msg) => {
                ...msg,
                'timestamp': (msg['timestamp'] as DateTime).toIso8601String(),
              })
          .toList());
      await prefs.setString(_cacheKey, serialized);
      print('💾 ŞOFÖR: Mesajlar cache kaydedildi (${_messages.length})');
    } catch (e) {
      print('❌ ŞOFÖR: Mesaj cache yazma hatası: $e');
    }
  }
  
  // GERÇEK ZAMANLI MESAJ SİSTEMİ
  void _startRealTimeMessaging() {
    _messagePollingTimer?.cancel();
    _messagePollingTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _loadChatHistory();
    });
    print('🔄 ŞOFÖR Gerçek zamanlı mesajlaşma başlatıldı');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFD700),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(
                widget.isDriver ? Icons.person : Icons.local_taxi,
                color: const Color(0xFFFFD700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isDriver ? widget.customerName : 'Şoför',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Yolculuk Mesajlaşması',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Mesajlar listesi
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          
          // Mesaj gönderme alanı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Fotoğraf gönder (Kamera + Galeri)
                IconButton(
                  onPressed: _sendPhoto,
                  icon: const Icon(Icons.add_photo_alternate, color: Color(0xFFFFD700)),
                  tooltip: 'Fotoğraf gönder',
                ),
                
                // 🔥 Konum paylaş
                IconButton(
                  onPressed: _sendLocation,
                  icon: const Icon(Icons.location_on, color: Color(0xFFFFD700)),
                ),
                
                // Sesli mesaj
                IconButton(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: _isRecording ? Colors.red : const Color(0xFFFFD700),
                  ),
                ),
                
                // Metin mesaj alanı
                Expanded(
                  child: TextFormField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Türkçe karakter test: ş ğ ü ı ö ç',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                
                // Gönder butonu
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Color(0xFFFFD700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    // ŞOFÖR: widget.isDriver = true, yani ben 'driver'ım
    final myType = widget.isDriver ? 'driver' : 'customer';
    final isMe = message['sender_type'] == myType;
    final messageTime = message['timestamp'] as DateTime;
    
    print('🔍 ŞOFÖR Bubble: sender_type=${message['sender_type']}, myType=$myType, isMe=$isMe');
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFFFD700) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(5),
            bottomRight: isMe ? const Radius.circular(5) : const Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mesaj içeriği
            if (message['type'] == 'audio')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _playAudio(message['audioPath']),
                    icon: Icon(
                      Icons.play_circle_fill,
                      color: isMe ? Colors.white : const Color(0xFFFFD700),
                      size: 32,
                    ),
                  ),
                  Text(
                    message['duration'] ?? '0:00',
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              )
            else if (message['type'] == 'image')
              GestureDetector(
                onTap: () => _showFullScreenImage(message['message']),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImageWidget(message['message']),
                  ),
                ),
              )
            else if (message['type'] == 'location')
              // 🔥 KONUM MESAJI - WhatsApp Tarzı Harita Uygulaması Seçici
              GestureDetector(
                onTap: () async {
                  try {
                    // Konum bilgisini parse et
                    double? lat;
                    double? lng;
                    String locationName = 'Konum';
                    
                    // JSON formatında mı?
                    if (message['message'].toString().startsWith('{')) {
                      final locationData = json.decode(message['message']);
                      lat = locationData['latitude'];
                      lng = locationData['longitude'];
                      locationName = locationData['name'] ?? 'Konum';
                    } else {
                      // Eski format: message içinden lat/lng al
                      lat = message['latitude'];
                      lng = message['longitude'];
                      locationName = message['locationName'] ?? 'Konum';
                    }
                    
                    if (lat == null || lng == null) {
                      print('❌ ŞOFÖR Konum bilgisi eksik');
                      return;
                    }
                    
                    // Kullanıcıya harita uygulaması seçtir
                    final app = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Row(
                          children: [
                            Icon(Icons.map, color: Color(0xFFFFD700)),
                            SizedBox(width: 12),
                            Text('Haritada Aç'),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: Image.asset(
                                'assets/icons/google_maps.png',
                                width: 32,
                                height: 32,
                                errorBuilder: (_, __, ___) => const Icon(Icons.map, color: Colors.green),
                              ),
                              title: const Text('Google Maps'),
                              onTap: () => Navigator.pop(context, 'google'),
                            ),
                            ListTile(
                              leading: Image.asset(
                                'assets/icons/yandex_maps.png',
                                width: 32,
                                height: 32,
                                errorBuilder: (_, __, ___) => const Icon(Icons.map, color: Colors.red),
                              ),
                              title: const Text('Yandex Maps'),
                              onTap: () => Navigator.pop(context, 'yandex'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('İptal'),
                          ),
                        ],
                      ),
                    );
                    
                    if (app == null) return;
                    
                    String mapUrl;
                    if (app == 'google') {
                      // Google Maps URI
                      mapUrl = Platform.isIOS
                          ? 'comgooglemaps://?q=$lat,$lng'
                          : 'geo:$lat,$lng?q=$lat,$lng($locationName)';
                    } else {
                      // Yandex Maps URI
                      mapUrl = 'yandexmaps://maps.yandex.com/?ll=$lng,$lat&z=16';
                    }
                    
                    print('🗺️ ŞOFÖR Harita açılıyor: $mapUrl');
                    
                    final uri = Uri.parse(mapUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      // Uygulama yoksa web tarayıcıda aç
                      final webUrl = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
                      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                    }
                    
                  } catch (e) {
                    print('❌ ŞOFÖR Harita açma hatası: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Harita açılamadı: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isMe ? Colors.white : const Color(0xFFFFD700)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isMe ? const Color(0xFFFFD700) : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📍 Konum Paylaşıldı',
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Haritada görüntülemek için tıklayın',
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              )
            else
              Text(
                message['message'],
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : Colors.black87,
                ),
              ),
            
            const SizedBox(height: 4),
            
            Text(
              '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      // Önce UI'ye ekle
      setState(() {
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'message': text,
          'sender_type': widget.isDriver ? 'driver' : 'customer',
          'timestamp': DateTime.now(),
          'type': 'text',
          'synced': false,
        });
      });
      _messageController.clear();
      _scrollToBottom();
      await _persistMessages();
      
      // API'ye gönder
      await _sendMessageToAPI(text, 'text');
      print('💬 ŞOFÖR Mesaj gönderildi: $text');
    }
  }

  Future<void> _sendPhoto() async {
    try {
      // Önce kullanıcıya kamera veya galeri seçeneği sun
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Fotoğraf Gönder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFFFD700)),
                title: const Text('Kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFFFFD700)),
                title: const Text('Galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
          ],
        ),
      );
      
      if (source == null) return;
      
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        print('📸 ŞOFÖR Fotoğraf seçildi: ${image.path}');
        
        // 🔥 DUPLICATE KONTROL - Aynı dosya adı son 5 saniyede gönderilmiş mi?
        final fileName = image.path.split('/').last;
        final now = DateTime.now();
        final recentImageMessages = _messages.where((msg) {
          if (msg['type'] != 'image') return false;
          final msgTime = msg['timestamp'] as DateTime;
          final msgPath = msg['message'] as String;
          return now.difference(msgTime).inSeconds < 5 && msgPath.contains(fileName);
        }).toList();
        
        if (recentImageMessages.isNotEmpty) {
          print('⚠️ ŞOFÖR Duplicate fotoğraf gönderimi engellendi: $fileName');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Bu fotoğraf zaten gönderildi'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        
        setState(() {
          _messages.add({
            'id': tempId,
            'message': image.path,
            'sender_type': widget.isDriver ? 'driver' : 'customer',
            'timestamp': DateTime.now(),
            'type': 'image',
            'synced': false,
          });
        });
        await _persistMessages();
        _scrollToBottom();

        // 🔥 RESMİ SUNUCUYA UPLOAD ET
        String? uploadedImageUrl;
        try {
          uploadedImageUrl = await _uploadImage(image.path, int.parse(widget.rideId));
          if (uploadedImageUrl != null) {
            print('✅ ŞOFÖR Resim sunucuya yüklendi: $uploadedImageUrl');
            // Mesajı güncelle - artık URL kullan
            setState(() {
              _messages.last['message'] = uploadedImageUrl;
            });
            await _persistMessages();
          } else {
            print('⚠️ ŞOFÖR Resim sunucuya yüklenemedi, local path kullanılacak');
          }
        } catch (uploadError) {
          print('❌ ŞOFÖR Upload hatası: $uploadError');
        }

        // API'ye gönder - upload edilen URL veya local path
        await _sendMessageToAPI(uploadedImageUrl ?? image.path, 'image');
        print('📸 ŞOFÖR Fotoğraf API gönderildi');
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Fotoğraf gönderildi'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ ŞOFÖR Fotoğraf hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Fotoğraf gönderilemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 🔥 KONUM PAYLAŞIMI - Mevcut veya Arama ile Seçim
  Future<void> _sendLocation() async {
    try {
      // Kullanıcıya seçenek sun
      final locationChoice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Color(0xFFFFD700)),
              SizedBox(width: 12),
              Text('Konum Paylaş'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.my_location, color: Colors.blue),
                title: const Text('Mevcut Konumum'),
                subtitle: const Text('Bulunduğum yeri paylaş'),
                onTap: () => Navigator.pop(context, 'current'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.search, color: Colors.green),
                title: const Text('Konum Ara'),
                subtitle: const Text('Adres yazarak konum seç'),
                onTap: () => Navigator.pop(context, 'search'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
          ],
        ),
      );
      
      if (locationChoice == null) return;
      
      double? latitude;
      double? longitude;
      String? locationName;
      
      if (locationChoice == 'current') {
        // MEVCUT KONUM
        final permission = await Permission.location.request();
        if (permission != PermissionStatus.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Konum izni gerekli!')),
          );
          return;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Konum alınıyor...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
        
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        
        latitude = position.latitude;
        longitude = position.longitude;
        locationName = 'Mevcut Konum';
        
      } else if (locationChoice == 'search') {
        // KONUM ARAMA
        final result = await _showLocationSearchDialog();
        if (result == null) return;
        
        latitude = result['latitude'];
        longitude = result['longitude'];
        locationName = result['name'];
      }
      
      if (latitude == null || longitude == null) return;
      
      // ✅ FIX: Konum bilgisini detaylı olarak kaydet
      final locationData = {
        'name': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'url': 'https://www.google.com/maps?q=$latitude,$longitude',
      };
      
      // Mesaj içeriği: JSON formatında tüm bilgi
      final locationMessage = json.encode(locationData);
      
      print('📍 ŞOFÖR Konum paylaşılıyor: $locationName ($latitude, $longitude)');
      
      setState(() {
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'message': locationMessage, // JSON formatında
          'sender_type': widget.isDriver ? 'driver' : 'customer',
          'timestamp': DateTime.now(),
          'type': 'location',
          'latitude': latitude,
          'longitude': longitude,
          'locationName': locationName, // Ekstra alan
          'synced': false,
        });
      });
      await _persistMessages();
      _scrollToBottom();
      
      await _sendMessageToAPI(locationMessage, 'location');
      print('📍 ŞOFÖR Konum paylaşıldı!');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Konum paylaşıldı'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      
    } catch (e) {
      print('❌ ŞOFÖR Konum paylaşma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Konum alınamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 🔍 KONUM ARAMA DIALOG
  Future<Map<String, dynamic>?> _showLocationSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Konum Ara'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Arama kutusu
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Adres veya yer adı...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD700)),
                      suffixIcon: isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12.0),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setDialogState(() {
                                  searchResults.clear();
                                });
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      
                      setDialogState(() {
                        isSearching = true;
                        searchResults.clear();
                      });
                      
                      final results = await _searchLocation(value);
                      
                      setDialogState(() {
                        isSearching = false;
                        searchResults = results;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Sonuçlar listesi
                  if (searchResults.isNotEmpty)
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final result = searchResults[index];
                          return ListTile(
                            leading: const Icon(Icons.place, color: Colors.red),
                            title: Text(result['name']),
                            subtitle: Text(result['address'] ?? ''),
                            onTap: () => Navigator.pop(context, result),
                          );
                        },
                      ),
                    )
                  else if (!isSearching && searchController.text.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Sonuç bulunamadı',
                        style: TextStyle(color: Colors.grey),
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
            ],
          );
        },
      ),
    );
  }
  
  // 🌍 KONUM ARAMA API (Google Places)
  Future<List<Map<String, dynamic>>> _searchLocation(String query) async {
    try {
      const apiKey = 'AIzaSyC_j9KEoNv7-mRMj2m6uh5NeGsqWe0Phlw'; // Google Maps API Key
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json?query=$query&key=$apiKey&language=tr&region=TR',
      );
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      print('📡 ŞOFÖR Konum arama API response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('📋 ŞOFÖR API status: ${data['status']}');
        
        // ✅ FIX: data['status'] kontrolü - OK olmalı
        if (data['status'] == 'OK' && data['results'] != null) {
          final List results = data['results'];
          
          print('✅ ŞOFÖR ${results.length} konum bulundu');
          
          return results.take(5).map((place) {
            return {
              'name': place['name'] ?? 'İsimsiz Konum',
              'address': place['formatted_address'] ?? '',
              'latitude': place['geometry']['location']['lat'],
              'longitude': place['geometry']['location']['lng'],
            };
          }).toList();
        } else {
          // API status OK değil (ZERO_RESULTS, OVER_QUERY_LIMIT, etc.)
          print('⚠️ ŞOFÖR Konum bulunamadı - API status: ${data['status']}');
          return [];
        }
      } else {
        print('❌ ŞOFÖR Konum arama HTTP hatası: ${response.statusCode}');
        return [];
      }
      
    } catch (e) {
      print('❌ ŞOFÖR Konum arama hatası: $e');
      return [];
    }
  }
  
  Future<void> _sendMessageToAPI(String message, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = int.tryParse(prefs.getString('driver_id') ?? '0') ?? 0;
      final rideId = int.tryParse(widget.rideId) ?? 0;

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/send_ride_message.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'sender_type': widget.isDriver ? 'driver' : 'customer',
          'sender_id': driverId,
          'message_type': type,
          'message_content': type == 'text' ? message : null,
          'file_path': type != 'text' ? message : null,
          'duration': type == 'audio' ? 5 : 0,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final messageId = data['message_id']?.toString();
          if (messageId != null) {
            final index = _messages.indexWhere((msg) => msg['id'] == messageId);
            if (index >= 0) {
              setState(() {
                _messages[index]['synced'] = true;
              });
              await _persistMessages();
            }
          }
          print('✅ ŞOFÖR: Mesaj API\'ye gönderildi (${data['message_id']})');
        } else {
          print('❌ ŞOFÖR: API hatası: ${data['message']}');
        }
      } else {
        print('❌ ŞOFÖR: HTTP hatası: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ŞOFÖR: Mesaj gönderme hatası: $e');
    }
  }

  // 🔥 RESIM UPLOAD FONKSİYONU
  Future<String?> _uploadImage(String imagePath, int rideId) async {
    try {
      print('📤 ŞOFÖR Resim sunucuya yükleniyor: $imagePath');
      
      // Dosyayı oku
      final File imageFile = File(imagePath);
      if (!imageFile.existsSync()) {
        print('❌ ŞOFÖR Resim dosyası bulunamadı: $imagePath');
        return null;
      }
      
      // Base64'e çevir
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);
      
      print('📊 ŞOFÖR Resim boyutu: ${imageBytes.length} bytes');
      
      // API'ye gönder
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/upload_ride_image.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ride_id': rideId,
          'image': base64Image,
          'sender_type': 'driver',
        }),
      ).timeout(const Duration(seconds: 30)); // Upload için daha uzun timeout
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final imageUrl = data['image_url'];
          print('✅ ŞOFÖR Resim upload başarılı: $imageUrl');
          return imageUrl;
        } else {
          print('❌ ŞOFÖR Upload API hatası: ${data['message']}');
          return null;
        }
      } else {
        print('❌ ŞOFÖR Upload HTTP hatası: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ ŞOFÖR Resim upload hatası: $e');
      return null;
    }
  }

  Future<void> _startRecording() async {
    try {
      final permission = await Permission.microphone.request();
      if (permission != PermissionStatus.granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Mikrofon izni gerekli!')),
        );
        return;
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${directory.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      
      _currentRecordingPath = '${audioDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder!.startRecorder(
        toFile: _currentRecordingPath!,
        codec: Codec.aacMP4,
      );
      
      setState(() {
        _isRecording = true;
        _recordingStartTime = DateTime.now();
      });
      
      print('🎤 ŞOFÖR GERÇEK SES KAYDI BAŞLATILDI: $_currentRecordingPath');
    } catch (e) {
      print('❌ ŞOFÖR Ses kayıt başlatma hatası: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _currentRecordingPath == null) return;
    
    try {
      await _audioRecorder!.stopRecorder();
      
      final recordingDuration = _recordingStartTime != null 
        ? DateTime.now().difference(_recordingStartTime!).inSeconds
        : 0;
      
      setState(() {
        _isRecording = false;
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'message': 'Sesli mesaj (${recordingDuration}s)',
          'sender_type': widget.isDriver ? 'driver' : 'customer',
          'timestamp': DateTime.now(),
          'type': 'audio',
          'duration': '0:${recordingDuration.toString().padLeft(2, '0')}',
          'audioPath': _currentRecordingPath,
          'synced': false,
        });
      });
      await _persistMessages();
      
      await _sendAudioMessage(_currentRecordingPath!, recordingDuration);
      _scrollToBottom();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎤 ŞOFÖR ${recordingDuration}s sesli mesaj gönderildi!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('❌ ŞOFÖR Ses kayıt durdurma hatası: $e');
      setState(() => _isRecording = false);
    }
  }
  
  Future<void> _sendAudioMessage(String filePath, int duration) async {
    // API'ye ses dosyası gönder (base64 encode vs)
    await _sendMessageToAPI(filePath, 'audio');
  }
  
  // 🔥 IMAGE WIDGET BUILDER - URL veya LOCAL FILE
  Widget _buildImageWidget(String imagePath) {
    print('🖼️ ŞOFÖR Image path: $imagePath');
    
    // HTTP/HTTPS URL ise network'ten yükle
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: const Color(0xFFFFD700),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          print('❌ ŞOFÖR Network image error: $error');
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text('Fotoğraf yüklenemedi', style: TextStyle(fontSize: 12)),
              ],
            ),
          );
        },
      );
    } 
    // Local file ise
    else {
      final file = File(imagePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            print('❌ ŞOFÖR File image error: $error');
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 40, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Fotoğraf yüklenemedi', style: TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        );
      } else {
        print('❌ ŞOFÖR File not exists: $imagePath');
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text('Fotoğraf bulunamadı', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      }
    }
  }
  
  Future<void> _playAudio(String? audioPath) async {
    if (audioPath == null) return;
    
    try {
      await _audioPlayer!.startPlayer(fromURI: audioPath);
      print('🔊 ŞOFÖR Ses oynatılıyor: $audioPath');
    } catch (e) {
      print('❌ ŞOFÖR Ses oynatma hatası: $e');
    }
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messages.isNotEmpty && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _showFullScreenImage(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: imagePath.startsWith('http')
                  ? Image.network(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, size: 80, color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Fotoğraf yüklenemedi',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        );
                      },
                    )
                  : File(imagePath).existsSync()
                      ? Image.file(
                          File(imagePath),
                          fit: BoxFit.contain,
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, size: 80, color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Fotoğraf bulunamadı',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ],
                        ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    _messagePollingTimer?.cancel();
    super.dispose();
  }
}