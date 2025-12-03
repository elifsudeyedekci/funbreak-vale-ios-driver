import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 SERVICES IMPORT!
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart'; // ✅ HOPARLÖR AYARI İÇİN!
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
    // ✅ Audio Session - Sesi hoparlörden çıkart (üst hoparlör değil!)
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
      print('✅ Audio session hoparlör moduna ayarlandı');
    } catch (e) {
      print('⚠️ Audio session ayarlanamadı: $e');
    }
    
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    
    await _audioRecorder!.openRecorder();
    await _audioPlayer!.openPlayer();
    
    // Ses kayıt sistemi başlatıldı
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
            final messageType = apiMessage['message_type'] ?? 'text';
            // 🔥 FIX: image ve audio için file_path ÖNCELİKLİ olmalı!
            // message_content boş string olabiliyor, bu yüzden önce file_path kontrol et
            String messageContent;
            if (messageType == 'image' || messageType == 'audio') {
              // Resim ve ses için file_path kullan (URL burada)
              messageContent = apiMessage['file_path']?.toString() ?? 
                              apiMessage['message_content']?.toString() ?? '';
            } else {
              // Text ve location için message_content kullan
              messageContent = apiMessage['message_content']?.toString() ?? 
                              apiMessage['file_path']?.toString() ?? '';
            }
            
            // Konum mesajı için lat/lng parse et
            double? lat;
            double? lng;
            String? locationName;
            
            if (messageType == 'location') {
              try {
                // JSON formatında mı kontrol et
                if (messageContent.toString().startsWith('{')) {
                  final locationData = jsonDecode(messageContent);
                  lat = (locationData['latitude'] as num?)?.toDouble();
                  lng = (locationData['longitude'] as num?)?.toDouble();
                  locationName = locationData['name']?.toString();
                } else if (messageContent.toString().contains('google.com/maps')) {
                  // URL formatında: https://www.google.com/maps?q=LAT,LNG
                  final regex = RegExp(r'q=(-?\d+\.?\d*),(-?\d+\.?\d*)');
                  final match = regex.firstMatch(messageContent);
                  if (match != null) {
                    lat = double.tryParse(match.group(1) ?? '');
                    lng = double.tryParse(match.group(2) ?? '');
                  }
                  // İsim varsa al
                  if (messageContent.contains(':')) {
                    locationName = messageContent.split(':').first.replaceAll('📍', '').trim();
                  }
                }
              } catch (e) {
                print('❌ Konum parse hatası: $e');
              }
            }
            
            merged.add({
              'id': apiMessage['id'].toString(),
              'message': messageContent,
              'sender_type': apiMessage['sender_type'] ?? 'customer',
              'timestamp': DateTime.tryParse(apiMessage['created_at'] ?? '') ?? DateTime.now(),
              'type': messageType,
              'audioPath': apiMessage['file_path'],
              'duration': apiMessage['duration']?.toString() ?? '0',
              'latitude': lat,
              'longitude': lng,
              'locationName': locationName,
            });
          }

          // 🔥 GÜÇLÜ DUPLICATE KONTROLÜ - MESSAGE CONTENT BAZLI (Timestamp olmadan!)
          // Resim URL'leri için sadece içerik kontrolü yeterli
          final existingContents = _messages.map((m) {
            return m['message']?.toString() ?? '';
          }).toSet();
          
          // Ayrıca ID bazlı kontrol
          final existingIds = _messages.map((m) => m['id']?.toString() ?? '').toSet();
          
          merged.removeWhere((msg) {
            final msgContent = msg['message']?.toString() ?? '';
            final msgId = msg['id']?.toString() ?? '';
            
            // Eğer içerik zaten varsa (resim URL'si aynıysa) - duplicate
            if (existingContents.contains(msgContent) && msgContent.isNotEmpty) {
              print('⚠️ ŞOFÖR: Duplicate engellendi (content): $msgContent');
              return true;
            }
            
            // Eğer ID zaten varsa - duplicate
            if (existingIds.contains(msgId) && msgId.isNotEmpty && !msgId.startsWith('temp_')) {
              print('⚠️ ŞOFÖR: Duplicate engellendi (id): $msgId');
              return true;
            }
            
            return false;
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
            child: _isRecording 
              // 🔥 WHATSAPP TARZI KAYIT UI
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // İptal butonu
                      IconButton(
                        onPressed: () {
                          _stopRecordingTimer();
                          _audioRecorder?.stopRecorder();
                          setState(() => _isRecording = false);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red, size: 28),
                      ),
                      // Kayıt animasyonu ve süre
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            children: [
                              // Kırmızı yanıp sönen nokta
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.3, end: 1.0),
                                duration: const Duration(milliseconds: 500),
                                builder: (context, value, child) {
                                  return Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(value),
                                      shape: BoxShape.circle,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              // Süre
                              Text(
                                _formatRecordingTime(_recordingSeconds),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              // Ses dalgası animasyonu
                              Row(
                                children: List.generate(8, (index) {
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 4.0, end: 16.0),
                                    duration: Duration(milliseconds: 300 + (index * 100)),
                                    builder: (context, value, child) {
                                      return Container(
                                        width: 3,
                                        height: value,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Gönder butonu
                      IconButton(
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.send, color: Color(0xFFFFD700), size: 28),
                      ),
                    ],
                  ),
                )
              // Normal mesaj UI
              : Row(
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
                      onPressed: _startRecording,
                      icon: const Icon(Icons.mic, color: Color(0xFFFFD700)),
                    ),
                    
                    // Metin mesaj alanı
                    Expanded(
                      child: TextFormField(
                        controller: _messageController,
                        style: TextStyle(color: Colors.black, fontSize: 16), // SİYAH YAZI
                        decoration: InputDecoration(
                          hintText: 'Mesaj yazın',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
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
            // 🔥 WHATSAPP TARZI SES MESAJI
            if (message['type'] == 'audio')
              _buildWhatsAppAudioMessage(message, isMe)
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
                    String fallbackUrl;
                    
                    if (app == 'google') {
                      // Google Maps URI
                      mapUrl = Platform.isIOS
                          ? 'comgooglemaps://?q=$lat,$lng'
                          : 'geo:$lat,$lng?q=$lat,$lng($locationName)';
                      fallbackUrl = 'https://www.google.com/maps?q=$lat,$lng';
                    } else {
                      // Yandex Maps URI - Yandex Navigator
                      mapUrl = Platform.isIOS
                          ? 'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng'
                          : 'yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng';
                      fallbackUrl = 'https://yandex.com/maps/?pt=$lng,$lat&z=16';
                    }
                    
                    print('🗺️ ŞOFÖR Harita açılıyor: $mapUrl');
                    
                    final uri = Uri.parse(mapUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      // Uygulama yoksa web tarayıcıda aç - SEÇİLEN HARİTA İÇİN!
                      final webUrl = Uri.parse(fallbackUrl);
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
                child: Builder(
                  builder: (context) {
                    // Konum bilgisini al
                    double? mapLat = message['latitude'];
                    double? mapLng = message['longitude'];
                    String mapName = message['locationName'] ?? 'Konum';
                    
                    // JSON formatında mı kontrol et
                    if ((mapLat == null || mapLng == null) && message['message'].toString().startsWith('{')) {
                      try {
                        final locationData = json.decode(message['message']);
                        mapLat = (locationData['latitude'] as num?)?.toDouble();
                        mapLng = (locationData['longitude'] as num?)?.toDouble();
                        mapName = locationData['name'] ?? 'Konum';
                      } catch (_) {}
                    }
                    
                    // URL formatında mı kontrol et
                    if ((mapLat == null || mapLng == null) && message['message'].toString().contains('google.com/maps')) {
                      try {
                        final regex = RegExp(r'q=(-?\d+\.?\d*),(-?\d+\.?\d*)');
                        final match = regex.firstMatch(message['message']);
                        if (match != null) {
                          mapLat = double.tryParse(match.group(1) ?? '');
                          mapLng = double.tryParse(match.group(2) ?? '');
                        }
                      } catch (_) {}
                    }
                    
                    final hasValidLocation = mapLat != null && mapLng != null;
                    
                    return Container(
                      width: 220,
                      decoration: BoxDecoration(
                        color: isMe ? const Color(0xFF1E3A5F) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // WhatsApp tarzı harita önizlemesi
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            child: hasValidLocation
                                ? Image.network(
                                    'https://maps.googleapis.com/maps/api/staticmap?center=$mapLat,$mapLng&zoom=15&size=300x150&markers=color:red%7C$mapLat,$mapLng&key=AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY',
                                    height: 120,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        height: 120,
                                        color: Colors.grey[300],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFFFFD700),
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 120,
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: Icon(Icons.map, size: 48, color: Colors.grey),
                                      ),
                                    ),
                                  )
                                : Container(
                                    height: 120,
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: Icon(Icons.location_on, size: 48, color: Colors.red),
                                    ),
                                  ),
                          ),
                          // Alt bilgi kısmı
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '📍 Konum',
                                        style: TextStyle(
                                          color: isMe ? Colors.white : Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'Haritada aç',
                                        style: TextStyle(
                                          color: isMe ? Colors.white70 : Colors.grey[600],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: isMe ? Colors.white54 : Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
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
        
        // 🔥 FIX: ÖNCE UPLOAD YAP, SONRA MESAJ EKLE!
        // Bu sayede duplicate oluşmaz
        
        // Yükleniyor göster
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('Fotoğraf yükleniyor...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
        
        // 🔥 RESMİ SUNUCUYA UPLOAD ET
        String? uploadedImageUrl;
        try {
          uploadedImageUrl = await _uploadImage(image.path, int.parse(widget.rideId));
        } catch (uploadError) {
          print('❌ ŞOFÖR Upload hatası: $uploadError');
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Fotoğraf yüklenemedi'), backgroundColor: Colors.red),
          );
          return;
        }
        
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (uploadedImageUrl == null || uploadedImageUrl.isEmpty) {
          print('⚠️ ŞOFÖR Resim sunucuya yüklenemedi');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Fotoğraf yüklenemedi'), backgroundColor: Colors.red),
          );
          return;
        }
        
        print('✅ ŞOFÖR Resim sunucuya yüklendi: $uploadedImageUrl');
        
        // API'ye gönder
        await _sendMessageToAPI(uploadedImageUrl, 'image');
        print('✅ ŞOFÖR: Fotoğraf API\'ye gönderildi: $uploadedImageUrl');
        
        // 🔥 FIX: Mesajı URL ile ekle (local path değil!)
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        setState(() {
          _messages.add({
            'id': tempId,
            'message': uploadedImageUrl,
            'sender_type': widget.isDriver ? 'driver' : 'customer',
            'timestamp': DateTime.now(),
            'type': 'image',
            'synced': true,
          });
        });
        await _persistMessages();
        _scrollToBottom();
        
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
        // MEVCUT KONUM - iOS İÇİN Geolocator KULLAN!
        try {
          // iOS'ta permission_handler yerine Geolocator kullan
          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (!serviceEnabled) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ Konum servisi kapalı!'), backgroundColor: Colors.red),
            );
            return;
          }
          
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('❌ Konum izni gerekli!'),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: 'Ayarlar',
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
            return;
          }
        } catch (e) {
          print('⚠️ Konum izin hatası: $e');
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
  
  // 🔍 KONUM ARAMA DIALOG - OTOMATİK ARAMA İLE
  Future<Map<String, dynamic>?> _showLocationSearchDialog() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;
    Timer? debounceTimer;
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          // 🔥 OTOMATİK ARAMA FONKSİYONU
          void performSearch(String query) async {
            if (query.trim().length < 2) {
              setDialogState(() {
                searchResults.clear();
                isSearching = false;
              });
              return;
            }
            
            setDialogState(() {
              isSearching = true;
            });
            
            final results = await _searchLocation(query);
            
            setDialogState(() {
              isSearching = false;
              searchResults = results;
            });
          }
          
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
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Adres veya yer adı yazın...',
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
                          : searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      searchResults.clear();
                                    });
                                  },
                                )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // 🔥 YAZARKEN OTOMATİK ARAMA (DEBOUNCE 500ms)
                    onChanged: (value) {
                      debounceTimer?.cancel();
                      debounceTimer = Timer(const Duration(milliseconds: 500), () {
                        performSearch(value);
                      });
                    },
                    onSubmitted: (value) {
                      debounceTimer?.cancel();
                      performSearch(value);
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
                            subtitle: Text(
                              result['address'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              debounceTimer?.cancel();
                              Navigator.pop(context, result);
                            },
                          );
                        },
                      ),
                    )
                  else if (isSearching)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Aranıyor...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else if (!isSearching && searchController.text.length >= 2)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Sonuç bulunamadı',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'En az 2 karakter yazın',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  debounceTimer?.cancel();
                  Navigator.pop(context);
                },
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
      const apiKey = 'AIzaSyAmPUh6vlin_kvFvssOyKHz5BBjp5WQMaY'; // Google Maps API Key (FunBreak Vale)
      
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

      // 🔥 Mesaj tipine göre doğru alan kullan - DUPLICATE ÖNLEME
      final Map<String, dynamic> requestBody = {
        'ride_id': rideId,
        'sender_type': widget.isDriver ? 'driver' : 'customer',
        'sender_id': driverId,
        'message_type': type,
        'duration': type == 'audio' ? 5 : 0,
      };
      
      // Text ve location mesajları message_content'e, image/audio file_path'e
      if (type == 'text' || type == 'location') {
        requestBody['message_content'] = message;
        requestBody['file_path'] = null;
      } else {
        // image veya audio
        requestBody['message_content'] = ''; // Boş string, null değil
        requestBody['file_path'] = message;
      }

      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/send_ride_message.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
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
      
      // XFile path'i File'a çevir
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        print('❌ ŞOFÖR Resim dosyası bulunamadı: $imagePath');
        
        // iOS'ta XFile path farklı olabilir, tekrar dene
        try {
          final bytes = await File(imagePath).readAsBytes();
          if (bytes.isEmpty) {
            return null;
          }
        } catch (e) {
          print('❌ Dosya okuma hatası: $e');
          return null;
        }
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
      // 🔥 iOS İÇİN DÜZGÜN MİKROFON İZNİ KONTROLÜ
      var status = await Permission.microphone.status;
      print('🎤 iOS Mikrofon izni durumu: $status');
      
      // iOS'ta ilk kez sorulacaksa veya denied ise izin iste
      if (!status.isGranted) {
        print('🎤 Mikrofon izni isteniyor...');
        status = await Permission.microphone.request();
        print('🎤 Mikrofon izni sonucu: $status');
      }
      
      // İzin verilmediyse
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          // Kalıcı olarak reddedilmiş - ayarlara yönlendir
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('❌ Mikrofon izni gerekli! Ayarlardan izin verin.'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Ayarlar',
                  textColor: Colors.white,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
        } else {
          // Normal red
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Mikrofon izni verilmedi'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        return;
      }
      
      print('✅ Mikrofon izni verildi, kayıt başlatılıyor...');
      
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
      
      // 🔥 KAYIT SÜRE TIMER'I BAŞLAT
      _startRecordingTimer();
      
      // Ses kaydı başlatıldı
    } catch (e) {
      // Ses kayıt başlatma hatası: $e
      setState(() => _isRecording = false);
    }
  }
  
  // 🔥 KAYIT SÜRE TIMER'I
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  
  void _startRecordingTimer() {
    _recordingSeconds = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingSeconds++;
      });
    });
  }
  
  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }
  
  String _formatRecordingTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _currentRecordingPath == null) return;
    
    _stopRecordingTimer();
    
    try {
      await _audioRecorder!.stopRecorder();
      
      final recordingDuration = _recordingSeconds;
      final localPath = _currentRecordingPath!;
      
      setState(() {
        _isRecording = false;
      });
      
      // 🔥 FIX: ÖNCE UPLOAD YAP, SONRA MESAJ EKLE!
      // Yükleniyor göster
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('Ses gönderiliyor...'),
            ],
          ),
          duration: Duration(seconds: 10),
        ),
      );
      
      // Upload ve API gönderimi
      final audioUrl = await _uploadAndSendAudio(localPath, recordingDuration);
      
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      if (audioUrl != null && audioUrl.isNotEmpty) {
        // 🔥 FIX: Mesajı URL ile ekle (local path değil!)
        setState(() {
          _messages.add({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'message': audioUrl,
            'sender_type': widget.isDriver ? 'driver' : 'customer',
            'timestamp': DateTime.now(),
            'type': 'audio',
            'duration': recordingDuration,
            'audioPath': audioUrl,
            'synced': true,
          });
        });
        await _persistMessages();
        _scrollToBottom();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Ses gönderildi'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Ses gönderilemedi'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      print('❌ Ses kayıt durdurma hatası: $e');
      setState(() => _isRecording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Ses gönderilemedi'), backgroundColor: Colors.red),
      );
    }
  }
  
  // 🔥 YENİ: Ses upload ve API gönderimi tek fonksiyonda
  Future<String?> _uploadAndSendAudio(String filePath, int duration) async {
    try {
      print('🎤 ŞOFÖR Ses dosyası yükleniyor: $filePath');
      
      // Dosyayı oku
      final File audioFile = File(filePath);
      if (!audioFile.existsSync()) {
        print('❌ ŞOFÖR Ses dosyası bulunamadı: $filePath');
        return null;
      }
      
      // Base64'e çevir
      final Uint8List audioBytes = await audioFile.readAsBytes();
      final String base64Audio = base64Encode(audioBytes);
      
      print('📊 ŞOFÖR Ses boyutu: ${audioBytes.length} bytes, Süre: ${duration}s');
      
      // API'ye upload et
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/upload_ride_audio.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'ride_id': int.parse(widget.rideId),
          'audio': base64Audio,
          'sender_type': 'driver',
          'duration': duration,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final audioUrl = data['audio_url'];
          print('✅ ŞOFÖR Ses upload başarılı: $audioUrl');
          
          // API'ye mesaj olarak gönder
          await _sendMessageToAPI(audioUrl, 'audio');
          print('✅ ŞOFÖR: Ses mesajı API\'ye gönderildi');
          
          return audioUrl;
        } else {
          print('❌ ŞOFÖR Ses upload API hatası: ${data['message']}');
          return null;
        }
      } else {
        print('❌ ŞOFÖR Ses upload HTTP hatası: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ ŞOFÖR Ses upload hatası: $e');
      return null;
    }
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
  
  // 🔥 WHATSAPP TARZI SES MESAJI WIDGET
  String? _currentlyPlayingId;
  double _playbackProgress = 0.0;
  
  Widget _buildWhatsAppAudioMessage(Map<String, dynamic> message, bool isMe) {
    final messageId = message['id']?.toString() ?? '';
    final isPlaying = _currentlyPlayingId == messageId;
    final duration = message['duration'] is int 
        ? message['duration'] as int 
        : int.tryParse(message['duration']?.toString() ?? '0') ?? 0;
    final durationText = '${(duration ~/ 60).toString().padLeft(2, '0')}:${(duration % 60).toString().padLeft(2, '0')}';
    
    return GestureDetector(
      onTap: () => _playAudio(message['audioPath'] ?? message['message'] ?? '', messageId),
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF1E3A5F) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Play/Pause butonu
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.black,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            // Ses dalgası ve süre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // WhatsApp tarzı ses dalgası
                  Row(
                    children: List.generate(20, (index) {
                      // Rastgele yükseklikler oluştur (ses dalgası efekti)
                      final heights = [8.0, 12.0, 6.0, 14.0, 10.0, 16.0, 8.0, 12.0, 18.0, 10.0, 
                                       14.0, 8.0, 16.0, 12.0, 6.0, 14.0, 10.0, 8.0, 12.0, 6.0];
                      final height = heights[index % heights.length];
                      final isActive = isPlaying && (index / 20) <= _playbackProgress;
                      
                      return Container(
                        width: 3,
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: isActive 
                              ? const Color(0xFFFFD700)
                              : (isMe ? Colors.white38 : Colors.grey[400]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  // Süre
                  Text(
                    durationText,
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _playAudio(String? audioPath, [String? messageId]) async {
    if (audioPath == null) return;
    
    try {
      // Aynı mesaj çalıyorsa durdur
      if (_currentlyPlayingId == messageId && messageId != null) {
        await _audioPlayer!.stopPlayer();
        setState(() {
          _currentlyPlayingId = null;
          _playbackProgress = 0.0;
        });
        return;
      }
      
      // ✅ FIX: URL veya yerel dosya kontrolü
      final isUrl = audioPath.startsWith('http://') || audioPath.startsWith('https://');
      final canPlay = isUrl || await File(audioPath).exists();
      
      if (canPlay) {
        setState(() {
          _currentlyPlayingId = messageId;
          _playbackProgress = 0.0;
        });
        
        await _audioPlayer!.startPlayer(
          fromURI: audioPath,
          whenFinished: () {
            setState(() {
              _currentlyPlayingId = null;
              _playbackProgress = 0.0;
            });
          },
        );
        
        // Progress güncelleme
        _audioPlayer!.onProgress!.listen((event) {
          if (event.duration.inMilliseconds > 0) {
            setState(() {
              _playbackProgress = event.position.inMilliseconds / event.duration.inMilliseconds;
            });
          }
        });
        
        print('🎵 Ses çalınıyor: $audioPath');
      } else {
        // Ses dosyası bulunamadı
        print('❌ Ses dosyası bulunamadı: $audioPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Ses dosyası bulunamadı')),
          );
        }
      }
    } catch (e) {
      // Ses oynatma hatası: $e
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