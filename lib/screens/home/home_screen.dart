import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../../providers/auth_provider.dart';
import '../../providers/ride_provider.dart';
import '../../providers/pricing_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/waiting_time_provider.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/notifications_bottom_sheet.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng _currentLocation = const LatLng(41.0082, 28.9784);
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = 'Konumunuzu seçin';
  String _destinationAddress = 'Nereye gitmek istiyorsunuz?';
  bool _isLoading = false;
  bool _showTimeSelection = false;
  DateTime _selectedDateTime = DateTime.now();
  String _selectedTimeOption = 'Hemen';
  double? _estimatedPrice;
  bool _mapLoading = true;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  final TextEditingController _searchController = TextEditingController();
  List<String> _locationSuggestions = [];
  
  static const String _darkMapStyle = '''
  [
    {
      "elementType": "geometry",
      "stylers": [{"color": "#212121"}]
    },
    {
      "elementType": "labels.icon",
      "stylers": [{"visibility": "off"}]
    },
    {
      "elementType": "labels.text.fill",
      "stylers": [{"color": "#757575"}]
    },
    {
      "elementType": "labels.text.stroke",
      "stylers": [{"color": "#212121"}]
    }
  ]
  ''';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _getCurrentLocation();
    _loadPricingData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: themeProvider.isDarkMode ? Colors.black : const Color(0xFFF8F9FA),
      body: Stack(
        children: [
          // Modern Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: themeProvider.isDarkMode 
                      ? [Colors.grey[900]!, Colors.grey[800]!]
                      : [Colors.white, const Color(0xFFFAFAFA)],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
          ),
        ],
      ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                      Text(
                        'FunBreak Vale',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFFFD700),
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Premium vale hizmeti',
                        style: TextStyle(
                          fontSize: 14,
                          color: themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
          ),
        ],
      ),
                  Row(
              children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () => _showNotificationsDialog(),
                          icon: const Icon(
                            Icons.notifications_rounded,
                            color: Color(0xFFFFD700),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _navigateToProfile(),
                        child: Container(
                          width: 48,
                          height: 48,
                  decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                      color: Colors.white,
                            size: 24,
                    ),
                  ),
                ),
              ],
            ),
                ],
              ),
            ),
          ),
          
          // Modern Harita
          Positioned(
            top: 140,
            left: 16,
            right: 16,
            bottom: 380,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: GoogleMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                    setState(() {
                      _mapLoading = false;
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentLocation,
                    zoom: 15,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  style: themeProvider.isDarkMode ? _darkMapStyle : null,
                  markers: {
                    if (_pickupLocation != null)
                      Marker(
                        markerId: const MarkerId('pickup'),
                        position: _pickupLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      ),
                    if (_destinationLocation != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: _destinationLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                  },
                ),
              ),
            ),
          ),
          
          // Bottom Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
                decoration: BoxDecoration(
                color: themeProvider.isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, -8),
                  ),
                ],
                ),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                  children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Location Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: themeProvider.isDarkMode ? Colors.grey[800] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: themeProvider.isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                            ),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () => _showPickupLocationDialog(),
                                child: Row(
              children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                                                                  Text(
                                          languageProvider.getTranslatedText('where_from'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                          Text(
                                            _pickupAddress,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: themeProvider.isDarkMode ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            languageProvider.getTranslatedText('select_from_map'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: const Color(0xFFFFD700),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                  ),
                ),
              ],
            ),
                              ),
                              const Divider(height: 24),
                              InkWell(
                                onTap: () => _showLocationSearchDialog(),
                                child: Row(
              children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Nereye',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                    Text(
                                            _destinationAddress,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _destinationAddress == 'Nereye gitmek istiyorsunuz?' 
                                                  ? Colors.grey[500]
                                                  : (themeProvider.isDarkMode ? Colors.white : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                                            'Haritadan seç',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: const Color(0xFFFFD700),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                  ),
                ),
              ],
            ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Price Display
                        if (_estimatedPrice != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                                const Text(
                                  'Tahmini Fiyat',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                  ),
                ),
                Text(
                                  '₺${_estimatedPrice!.toStringAsFixed(2)}',
                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                  ),
                ),
              ],
            ),
              ),
                        
                        if (_estimatedPrice != null) const SizedBox(height: 20),
                        
                        // Time Selection
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                              _buildModernTimeOption('Hemen'),
                              const SizedBox(width: 12),
                              _buildModernTimeOption('1 Saat'),
                              const SizedBox(width: 12),
                              _buildModernTimeOption('2 Saat'),
                              const SizedBox(width: 12),
                              _buildModernTimeOption('3 Saat'),
                              const SizedBox(width: 12),
                              _buildModernTimeOption('4 Saat'),
                              const SizedBox(width: 12),
                              _buildModernTimeOption('Özel Saat'),
                            ],
                          ),
                        ),
                        
              const SizedBox(height: 24),
            
                        // Call Vale Button
            SizedBox(
              width: double.infinity,
                          height: 60,
              child: ElevatedButton(
                            onPressed: _isLoading ? null : _requestVale,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 12,
                              shadowColor: const Color(0xFFFFD700).withOpacity(0.4),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.directions_car_rounded, size: 28),
                                      const SizedBox(width: 12),
                                      Text(
                                        languageProvider.getTranslatedText('call_vale'),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
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
          
          // Floating Location Button
          Positioned(
            right: 20,
            bottom: 400,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: themeProvider.isDarkMode ? Colors.grey[800] : Colors.white,
              onPressed: _getCurrentLocation,
              child: Icon(
                Icons.my_location_rounded,
                color: const Color(0xFFFFD700),
              ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildModernTimeOption(String option) {
    final isSelected = _selectedTimeOption == option;
    return InkWell(
      onTap: () {
        if (option == 'Özel Saat') {
          _showTimePicker();
        } else {
          setState(() {
            _selectedTimeOption = option;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          option,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Notification Dialog with Tabs
  void _showNotificationsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NotificationsBottomSheet(),
    );
  }
  
  Widget _buildNotificationCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Pickup Location Dialog
  void _showPickupLocationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
              children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Nereden',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
                Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location, color: Color(0xFFFFD700)),
                    title: const Text('Mevcut Konumum'),
                    onTap: () {
                      Navigator.pop(context);
                      _getCurrentLocation();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.map, color: Color(0xFFFFD700)),
                    title: const Text('Haritadan Seç'),
                    onTap: () {
                      Navigator.pop(context);
                      _showMapLocationPicker(true);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Location Search Dialog
  void _showLocationSearchDialog() {
    _searchController.clear();
    _locationSuggestions = [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomState) => Container(
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
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
          children: [
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Konum ara...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) async {
                        if (value.length > 2) {
                          await _generateLocationSuggestions(value);
                          setBottomState(() {});
                        } else {
                          setBottomState(() {
                            _locationSuggestions = [];
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.map, color: Color(0xFFFFD700)),
                      title: const Text('Haritadan Seç'),
                      onTap: () {
                        Navigator.pop(context);
                        _showMapLocationPicker(false);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _locationSuggestions.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFFFFD700)),
                      title: Text(_locationSuggestions[index]),
                      onTap: () async {
              Navigator.pop(context);
                        setState(() {
                          _destinationAddress = _locationSuggestions[index];
                        });
                        
                        // Adres için koordinat al
                        try {
                          List<Location> locations = await locationFromAddress(_locationSuggestions[index]);
                          if (locations.isNotEmpty) {
                            setState(() {
                              _destinationLocation = LatLng(locations.first.latitude, locations.first.longitude);
                            });
                            await _calculatePrice();
                          }
                        } catch (e) {
                          print('Koordinat alınamadı: $e');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _generateLocationSuggestions(String query) async {
    if (query.length < 3) return;
    
    try {
      const String apiKey = 'AIzaSyAAeSrC4jKD8NfwpVziSyuE4zJnaq4Ok5A';
      final String url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$apiKey&language=tr&components=country:tr';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List;
        
        setState(() {
          _locationSuggestions = predictions
              .map((prediction) => prediction['description'] as String)
              .take(6)
              .toList();
        });
      } else {
        // Fallback to basic suggestions
        setState(() {
          _locationSuggestions = [
            '$query, İstanbul',
            '$query Mahallesi, İstanbul',
            '$query Caddesi, İstanbul',
            '$query Sokak, İstanbul',
            '$query Metro, İstanbul',
            '$query AVM, İstanbul',
          ];
        });
      }
    } catch (e) {
      // Fallback to basic suggestions
      setState(() {
        _locationSuggestions = [
          '$query, İstanbul',
          '$query Mahallesi, İstanbul',
          '$query Caddesi, İstanbul',
          '$query Sokak, İstanbul',
          '$query Metro, İstanbul',
          '$query AVM, İstanbul',
        ];
      });
    }
  }

  // Time Picker
  void _showTimePicker() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFFD700),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFFFFD700),
              ),
            ),
            child: child!,
          );
        },
      );
      
      if (time != null) {
        setState(() {
          _selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          final months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 
                         'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
          _selectedTimeOption = '${date.day} ${months[date.month - 1]} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        });
      }
    }
  }

  void _showMapLocationPicker(bool isPickup) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialLocation: isPickup ? _pickupLocation : _destinationLocation,
          onLocationSelected: (location, address) {
    setState(() {
              if (isPickup) {
                _pickupLocation = location;
                _pickupAddress = address;
              } else {
                _destinationLocation = location;
                _destinationAddress = address;
                _calculatePrice();
              }
            });
          },
        ),
      ),
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileScreen(),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _pickupLocation = _currentLocation;
      });
      
      // Mevcut konum için gerçek adres al
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude
        );
        
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          setState(() {
            _pickupAddress = '${place.street ?? ''} ${place.subLocality ?? ''} ${place.locality ?? 'İstanbul'}'.trim();
          });
        } else {
          setState(() {
            _pickupAddress = 'Mevcut konumunuz';
          });
        }
      } catch (e) {
        setState(() {
          _pickupAddress = 'Mevcut konumunuz';
        });
      }
    } catch (e) {
      print('Konum alınamadı: $e');
      setState(() {
        _pickupAddress = 'Konum alınamadı';
      });
    }
  }

  Future<void> _calculatePrice() async {
    if (_pickupLocation != null && _destinationLocation != null) {
      final pricingProvider = Provider.of<PricingProvider>(context, listen: false);
      
      try {
        final price = await pricingProvider.calculateAIPrice(
          pickup: _pickupLocation!,
          destination: _destinationLocation!,
          serviceType: 'vale',
          time: _selectedDateTime,
        );
        
        setState(() {
          _estimatedPrice = price;
        });
      } catch (e) {
        // Fallback fiyat
        setState(() {
          _estimatedPrice = 50.0 + (_calculateDistance(_pickupLocation!, _destinationLocation!) * 10.0);
        });
      }
    }
  }

  // Mesafe hesaplama helper
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    
    double dLat = _degreesToRadians(point2.latitude - point1.latitude);
    double dLon = _degreesToRadians(point2.longitude - point1.longitude);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(point1.latitude)) * 
        cos(_degreesToRadians(point2.latitude)) *
        sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  Future<void> _loadPricingData() async {
    final pricingProvider = Provider.of<PricingProvider>(context, listen: false);
    final waitingProvider = Provider.of<WaitingTimeProvider>(context, listen: false);
    
    await pricingProvider.loadPricing();
    await waitingProvider.loadWaitingSettings();
  }

  Future<void> _requestVale() async {
    if (_destinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen hedef konum seçin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Vale başarıyla çağrıldı!'),
        backgroundColor: Colors.green,
      ),
    );
  }
} 