import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({Key? key}) : super(key: key);

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();
  File? _profileImage;
  String? _currentPhotoUrl; // Panelden gelen mevcut foto URL
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  void _loadDriverData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _nameController.text = authProvider.driverName ?? '';
    _phoneController.text = authProvider.driverPhone ?? '';
    _emailController.text = authProvider.userEmail ?? '';
    _licenseController.text = 'B'; // Ehliyet türü
    
    // MEVCUT FOTOĞRAFI PANELDEN ÇEK!
    await _loadCurrentPhoto();
  }
  
  Future<void> _loadCurrentPhoto() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      if (driverId != null) {
        print('📸 Sürücü fotoğrafı yükleniyor - ID: $driverId');
        
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/get_driver_photo.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'driver_id': driverId}),
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['success'] == true && data['photo_url'] != null) {
            setState(() {
              _currentPhotoUrl = data['photo_url'];
            });
            
            // AuthProvider'ı da güncelle - kalıcı yapmak için
            authProvider.updateDriverPhoto(data['photo_url']);
            
            print('✅ Sürücü fotoğrafı yüklendi: ${data['photo_url']}');
          } else {
            print('⚠️ Sürücü fotoğrafı bulunamadı');
          }
        }
      }
    } catch (e) {
      print('❌ Fotoğraf yükleme hatası: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      // 1. RESİM SEÇ
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 90,
      );
      
      if (image == null) return;
      
      // 2. FOTOĞRAFI HAZIRLA - KARE ŞEKLINDE CROP OLMADAN DA GÜZEL!
      setState(() {
        _profileImage = File(image.path);
      });
      
      print('✅ Fotoğraf seçildi - otomatik yükleniyor!');
      
      // OTOMATIK UPLOAD!
      await _uploadProfilePhoto();
      
    } catch (e) {
      print('❌ Resim seçme/kırpma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resim işleme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _uploadProfilePhoto() async {
    if (_profileImage == null) return;
    
    setState(() {
      _isUploading = true;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      if (driverId == null) {
        throw Exception('Sürücü ID bulunamadı');
      }
      
      print('📤 Profil fotoğrafı yükleniyor - Driver ID: $driverId');
      
      // Multipart request oluştur
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://admin.funbreakvale.com/api/upload_driver_photo.php'),
      );
      
      // Dosyayı ekle
      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          _profileImage!.path,
        ),
      );
      
      // Driver ID ekle
      request.fields['driver_id'] = driverId.toString();
      
      // İsteği gönder
      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseData);
        
        if (data['success'] == true) {
          final photoUrl = data['photo_url'];
          
          setState(() {
            _currentPhotoUrl = photoUrl;
            _profileImage = null; // Yüklendikten sonra temizle
          });
          
          // AuthProvider'da güncelle - kalıcı olsun!
          authProvider.updateDriverPhoto(photoUrl);
          
          // SharedPreferences'a da kaydet
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('driver_photo_url', photoUrl);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profil fotoğrafı başarıyla güncellendi!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
          
          print('✅ Profil fotoğrafı başarıyla yüklendi: $photoUrl');
          
        } else {
          throw Exception(data['message'] ?? 'Fotoğraf yükleme başarısız');
        }
      } else {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }
      
    } catch (e) {
      print('❌ Fotoğraf yükleme hatası: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Fotoğraf yüklenemedi: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Şoför Profili',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profil Fotoğrafı
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFD700),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _profileImage != null
                          ? Image.file(
                              _profileImage!,
                              fit: BoxFit.cover,
                              width: 120,
                              height: 120,
                            )
                          : _currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty
                              ? FadeInImage.assetNetwork(
                                  placeholder: 'assets/images/profile_placeholder.png', // Placeholder
                                  image: _currentPhotoUrl!,
                                  fit: BoxFit.cover,
                                  width: 120,
                                  height: 120,
                                  imageErrorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: const Color(0xFFFFD700),
                                      child: const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: const Color(0xFFFFD700),
                                  child: const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _isUploading ? null : _pickImage, // Yüklenirken devre dışı
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _isUploading ? Colors.grey : const Color(0xFFFFD700),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Kişisel Bilgiler
            _buildReadOnlyProfileField(
              'Tam İsim',
              _nameController.text,
              Icons.person_outline,
            ),
            
            const SizedBox(height: 16),
            
            _buildReadOnlyProfileField(
              'Telefon',
              _phoneController.text,
              Icons.phone_outlined,
            ),
            
            const SizedBox(height: 16),
            
            _buildReadOnlyProfileField(
              'E-posta',
              _emailController.text,
              Icons.email_outlined,
            ),
            
            const SizedBox(height: 16),
            
            _buildReadOnlyProfileField(
              'Ehliyet Türü',
              _licenseController.text,
              Icons.credit_card_outlined,
            ),
            
            const SizedBox(height: 24),
            
            // Şoför Durumu
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Şoför Durumu',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Onaylanmış Şoför',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // Kaydet Butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  shadowColor: const Color(0xFFFFD700).withOpacity(0.3),
                ),
                child: const Text(
                  'Profili Kaydet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
          prefixIcon: Container(
            padding: const EdgeInsets.all(12),
            child: Icon(
              icon,
              color: const Color(0xFFFFD700),
              size: 24,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    // Profil kaydetme işlemi
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profil başarıyla güncellendi!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildReadOnlyProfileField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFFD700),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? 'Belirtilmemiş' : value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.lock,
            size: 16,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _licenseController.dispose();
    super.dispose();
  }
}
