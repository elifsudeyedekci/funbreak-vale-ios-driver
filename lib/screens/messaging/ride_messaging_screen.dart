import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 SERVICES IMPORT!
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

class RideMessagingScreen extends StatefulWidget {
  final int rideId;
  final String customerName;
  final String customerPhone;
  
  const RideMessagingScreen({
    Key? key,
    required this.rideId,
    required this.customerName,
    required this.customerPhone,
  }) : super(key: key);

  @override
  State<RideMessagingScreen> createState() => _RideMessagingScreenState();
}

class _RideMessagingScreenState extends State<RideMessagingScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _messageRefreshTimer;
  late StreamSubscription<RemoteMessage> _firebaseSubscription;

  @override
  void initState() {
    super.initState();
    
    // 🔥 CONTROLLER DEBUG - HER KARAKTER GİRİŞİNDE LOGLA!
    _messageController.addListener(() {
      print('🔍 ŞOFÖR CONTROLLER İÇERİK: "${_messageController.text}"');
      print('🔍 UZUNLUK: ${_messageController.text.length}');
      print('🔍 BYTES: ${_messageController.text.codeUnits}');
    });
    
    _loadMessages();
    _setupMessageRefresh();
    _setupFirebaseListener();
  }

  @override
  void dispose() {
    _messageRefreshTimer?.cancel();
    _firebaseSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupMessageRefresh() {
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _loadMessages(silent: true);
    });
  }

  void _setupFirebaseListener() {
    _firebaseSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('💬 [ŞOFÖR] Firebase mesaj alındı: ${message.data['type']}');
      
      if (message.data['type'] == 'ride_message' && 
          message.data['ride_id'] == widget.rideId.toString()) {
        print('✅ [ŞOFÖR] Yolculuk mesajı - UI güncelleniyor');
        _loadMessages(silent: true);
        
        // Ekranda bildirim göster
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.message, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '💬 Müşteriden yeni mesaj: ${message.notification?.body ?? "Mesaj alındı"}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFFFD700),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? '0';
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_ride_messages.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': widget.rideId,
          'driver_id': driverId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _messages = List<Map<String, dynamic>>.from(data['messages']);
            _isLoading = false;
          });
          
          if (_messages.isNotEmpty) {
            Future.delayed(const Duration(milliseconds: 100), () {
              _scrollToBottom();
            });
          }
        }
      }
    } catch (e) {
      if (!silent) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesajlar yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? '0';
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/send_ride_message.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': widget.rideId,
          'sender_id': driverId,
          'sender_type': 'driver',
          'message': messageText,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _messageController.clear();
          _loadMessages(silent: true);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesaj gönderildi'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        } else {
          throw Exception(data['message'] ?? 'Mesaj gönderilemedi');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesaj gönderme hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.customerName),
            Text(
              'Müşteri • ${widget.customerPhone}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: () => _loadMessages(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Mesaj listesi
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageItem(_messages[index]);
                    },
                  ),
          ),
          
          // Mesaj gönderme alanı
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz mesaj bulunmamaktadır',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Müşterinizle mesajlaşmaya başlayın',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> message) {
    final isFromDriver = message['sender_type'] == 'driver';
    final messageText = message['message'] ?? '';
    final timestamp = message['created_at'] ?? '';
    final isRead = message['is_read'] == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isFromDriver 
          ? MainAxisAlignment.end 
          : MainAxisAlignment.start,
        children: [
          if (!isFromDriver) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isFromDriver 
                  ? const Color(0xFFFFD700)
                  : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isFromDriver ? 16 : 4),
                  bottomRight: Radius.circular(isFromDriver ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    messageText,
                    style: TextStyle(
                      fontSize: 16,
                      color: isFromDriver ? Colors.black : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: isFromDriver 
                            ? Colors.black54 
                            : Colors.grey[600],
                        ),
                      ),
                      if (isFromDriver) ...[
                        const SizedBox(width: 4),
                        Icon(
                          isRead ? Icons.done_all : Icons.done,
                          size: 14,
                          color: isRead ? Colors.blue : Colors.black54,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          if (isFromDriver) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFFD700),
              child: const Icon(Icons.person, color: Colors.black, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextFormField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'ŞOFÖR TEST: ş ğ ü ı ö ç yazın...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFD700),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.send,
                      color: Colors.black,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Dün';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
