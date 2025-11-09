import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/ride_provider.dart';
import '../providers/pricing_provider.dart';
import '../widgets/star_rating.dart';
import '../models/ride.dart';
import '../ride/modern_active_ride_screen.dart'; // MODERN YOLCULUK EKRANI!

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Ride> _availableRides = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableRides();
    _startExpiredRequestCleanup(); // SÜRESİ DOLAN TALEP TEMİZLEME!
  }

  Future<void> _loadAvailableRides() async {
    setState(() => _isLoading = true);
    
    try {
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      await rideProvider.loadRideHistory();
      
      // Filter available rides (pending status)
      _availableRides = rideProvider.rideHistory
          .where((ride) => ride.status == 'pending')
          .toList();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yolculuklar yüklenirken hata: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FunBreak Vale Driver'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAvailableRides,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _availableRides.isEmpty
              ? const Center(
                  child: Text(
                    'Şu anda bekleyen yolculuk yok',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _availableRides.length,
                  itemBuilder: (context, index) {
                    final ride = _availableRides[index];
                    return _buildRideCard(ride);
                  },
                ),
    );
  }

  Widget _buildRideCard(Ride ride) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Yolculuk #${ride.id.substring(0, 8)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ride.statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Pickup and destination
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(ride.pickupAddress)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(ride.destinationAddress)),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Price and time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tahmini Fiyat: ${ride.estimatedPrice.toStringAsFixed(2)} ₺'),
                Text('Süre: ${ride.estimatedTime} dk'),
              ],
            ),
            
            if (ride.specialInstructions != null && ride.specialInstructions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Özel Talimat: ${ride.specialInstructions}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptRide(ride),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Kabul Et'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _viewDetails(ride),
                    child: const Text('Detaylar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRide(Ride ride) async {
    try {
      final rideProvider = Provider.of<RideProvider>(context, listen: false);
      await rideProvider.acceptRide(ride.id);
      
      // MODERN YOLCULUK EKRANINA GEÇ! ✅
      final rideDetails = {
        'ride_id': ride.id,
        'customer_id': ride.customerId,
        'customer_name': ride.customerName ?? 'Müşteri',
        'customer_phone': ride.customerPhone ?? '+90 XXX XXX XX XX',
        'pickup_address': ride.pickupAddress,
        'destination_address': ride.destinationAddress,
        'estimated_price': ride.estimatedPrice,
        'status': 'accepted',
        'ride_type': ride.rideType ?? 'standard',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ModernDriverActiveRideScreen(
            rideDetails: rideDetails,
            waitingMinutes: 0,
          ),
        ),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Yolculuk kabul edildi - Modern ekran açılıyor')),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  void _viewDetails(Ride ride) {
    // Navigate to ride details screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Yolculuk Detayları'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Müşteri ID: ${ride.customerId}'),
            Text('Alış: ${ride.pickupAddress}'),
            Text('Varış: ${ride.destinationAddress}'),
            Text('Fiyat: ${ride.estimatedPrice.toStringAsFixed(2)} ₺'),
            Text('Süre: ${ride.estimatedTime} dakika'),
            if (ride.specialInstructions != null)
              Text('Talimat: ${ride.specialInstructions}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  
  // SÜRESİ DOLAN TALEP TEMİZLEME SİSTEMİ! ✅
  void _startExpiredRequestCleanup() async {
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      await _cleanupExpiredRequests();
    });
  }
  
  Future<void> _cleanupExpiredRequests() async {
    try {
      // Sürücü ID'sini al
      final prefs = await SharedPreferences.getInstance();
      final driverId = int.tryParse(prefs.getString('driver_id') ?? '0') ?? 0;
      
      if (driverId <= 0) return;
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/cleanup_driver_expired_requests.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'timeout_seconds': 30,
        }),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['expired_count'] > 0) {
          print('🧹 [ŞOFÖR] ${data['expired_count']} süresi dolan talep temizlendi');
          
          // Listeyi yenile
          _loadAvailableRides();
        }
      }
      
    } catch (e) {
      print('⚠️ [ŞOFÖR] Expired cleanup hatası: $e');
    }
  }
} 