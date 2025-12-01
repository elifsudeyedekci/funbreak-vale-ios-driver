import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({Key? key}) : super(key: key);

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _earningsData = {};
  bool _isLoading = true;
  String _selectedPeriod = 'daily';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0); // 0 = Günlük
    _selectedPeriod = 'daily'; // Default günlük
    _loadEarningsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEarningsData() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString('driver_id') ?? '0';
      
      final response = await http.post(
        Uri.parse('https://admin.funbreakvale.com/api/get_driver_earnings_report.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': driverId,
          'period': _selectedPeriod,
          'include_rides': true, // Yolculukları da getir!
          'include_breakdown': true, // Detay bilgileri de getir!
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            // SAFE NULL CHECK!
            _earningsData = data is Map<String, dynamic> ? data : {};
            _isLoading = false;
          });
          
          print('✅ Kazanç verileri yüklendi: ${_earningsData.keys}');
        } else {
          throw Exception(data['message'] ?? 'Veri yüklenemedi');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kazanç Analizi'),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.black, // 🔥 AKTİF TAB SİYAH YAZI
          unselectedLabelColor: Colors.black54, // 🔥 PASİF TAB GRİ
          indicator: BoxDecoration(
            color: Colors.yellow, // 🔥 AKTİF TAB ARKA PLAN SARI!
            borderRadius: BorderRadius.circular(8),
          ),
          indicatorPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.normal,
            fontSize: 14,
          ),
          tabs: const [
            Tab(text: 'Günlük'),
            Tab(text: 'Haftalık'),
            Tab(text: 'Aylık'),
          ],
          onTap: (index) {
            final newPeriod = ['daily', 'weekly', 'monthly'][index];
            // ANINDA SARI YAP - setState ile tab değiştir
            if (_selectedPeriod != newPeriod) {
              setState(() {
                _selectedPeriod = newPeriod;
                // Tab controller'ı anında güncelle
                _tabController.index = index;
              });
              // API çağrısını arka planda yap (UI hemen güncellenir)
              _loadEarningsData();
            }
          },
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadEarningsData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Toplam Kazanç Kartı
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  
                  // Komisyon Detayları
                  _buildCommissionCard(),
                  const SizedBox(height: 16),
                  
                  // Yolculuk İstatistikleri
                  _buildRideStatsCard(),
                  const SizedBox(height: 16),
                  
                  // Günlük Kazanç Listesi
                  _buildEarningsListCard(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSummaryCard() {
    final totalEarnings = _earningsData['total_earnings']?.toDouble() ?? 0.0;
    final totalRides = _earningsData['total_rides']?.toInt() ?? 0;
    final averagePerRide = totalRides > 0 ? totalEarnings / totalRides : 0.0;

    return Card(
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet, size: 48, color: Colors.black), // 🔥 $ İKONU KALDIRILDI
            const SizedBox(height: 8),
            Text(
              '₺${totalEarnings.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            Text(
              'Toplam Kazanç (${_getPeriodText()})',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Yolculuk', totalRides.toString(), Icons.directions_car),
                _buildStatItem('Ortalama', '₺${averagePerRide.toStringAsFixed(0)}', Icons.analytics),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionCard() {
    final totalRevenue = _earningsData['total_revenue']?.toDouble() ?? _earningsData['gross_earnings']?.toDouble() ?? 0.0;
    final totalCommission = _earningsData['total_commission']?.toDouble() ?? 0.0;
    final netEarnings = _earningsData['total_earnings']?.toDouble() ?? 0.0;
    final commissionRate = _earningsData['commission_rate']?.toDouble() ?? 30.0; // Panel'den geliyor

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: Color(0xFFFFD700)),
                const SizedBox(width: 8),
                const Text(
                  'Komisyon Detayları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCommissionRow('Toplam Gelir', totalRevenue, Colors.blue),
            _buildCommissionRow('Komisyon (%30)', totalCommission, Colors.red),
            const Divider(),
            _buildCommissionRow('Net Kazancınız', netEarnings, Colors.green, isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildRideStatsCard() {
    // SAFE ACCESS
    final ridesData = _earningsData['rides'] ?? _earningsData['ride_details'];
    final rides = (ridesData is List) ? ridesData : [];
    final avgRating = _earningsData['average_rating']?.toDouble() ?? 0.0;
    final totalDistance = _earningsData['total_distance']?.toDouble() ?? 0.0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Color(0xFFFFD700)),
                const SizedBox(width: 8),
                const Text(
                  'Yolculuk İstatistikleri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox('Toplam Mesafe', '${totalDistance.toStringAsFixed(1)} km', Icons.route),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox('Ortalama Puan', avgRating.toStringAsFixed(1), Icons.star),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsListCard() {
    // SAFE ACCESS - null hatası önleme
    final ridesData = _earningsData['rides'] ?? _earningsData['ride_details'];
    final rides = (ridesData is List) ? ridesData : [];
    
    if (rides.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'Bu dönemde yolculuk bulunmamaktadır',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list, color: Color(0xFFFFD700)),
                const SizedBox(width: 8),
                const Text(
                  'Yolculuk Detayları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...rides.map((ride) => _buildRideItem(ride)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.black, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildCommissionRow(String label, double amount, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFFFD700)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRideItem(Map<String, dynamic> ride) {
    // Backend'den gelen net_earning'i DOĞRUDAN kullan!
    final totalPrice = (ride['final_price'] ?? ride['estimated_price'] ?? 0).toDouble();
    
    // Backend net_earning gönderiyor - ÖNCE BUNU KONTROL ET!
    double netEarnings;
    if (ride['net_earning'] != null) {
      netEarnings = double.tryParse(ride['net_earning'].toString()) ?? 0.0;
      debugPrint('✅ Backend net_earning kullanılıyor: ₺$netEarnings');
    } else {
      // Fallback: Backend commission göndermişse kullan
      final commission = (ride['commission'] ?? 0).toDouble();
      netEarnings = totalPrice - commission;
      debugPrint('⚠️ Fallback hesaplama: ₺$totalPrice - ₺$commission = ₺$netEarnings');
    }
    
    final distance = (ride['total_distance'] ?? 0).toDouble();
    final createdAt = ride['created_at'] ?? '';
    final status = ride['status']?.toString() ?? '';
    final isCancelled = status == 'cancelled';
    
    // Komisyon tutarını hesapla (gösterim için)
    final commission = totalPrice - netEarnings;
    final commissionRate = totalPrice > 0 ? (commission / totalPrice * 100) : 30.0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car, color: Colors.black, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₺${netEarnings.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isCancelled ? Colors.red : Colors.green,
                      ),
                    ),
                    Text(
                      isCancelled 
                        ? '0.0 km (İptal) • $createdAt'
                        : '${distance.toStringAsFixed(1)} km • $createdAt',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 🔥 KAZANÇ DETAYI - BACKEND'DEN GELEN TÜM DETAYLAR
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              children: [
                // TABAN ÜCRET
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Taban Ücret:',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                    Text(
                      '₺${(ride['initial_estimated_price'] ?? ride['estimated_price'] ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                  ],
                ),
                // BEKLEME ÜCRETİ (Backend'den gelen waiting_fee_amount)
                if (ride['waiting_fee_amount'] != null && (double.tryParse(ride['waiting_fee_amount'].toString()) ?? 0.0) > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Bekleme Ücreti:',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      Text(
                        '+₺${(double.tryParse(ride['waiting_fee_amount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                // İNDİRİM (varsa)
                if (ride['discount_amount'] != null && (double.tryParse(ride['discount_amount'].toString()) ?? 0.0) > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'İndirim:',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      Text(
                        '-₺${(double.tryParse(ride['discount_amount'].toString()) ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                // ✅ ÖZEL KONUM ÜCRETİ (Komisyonsuz - %100 sürücüye!)
                if (ride['location_extra_fee'] != null && (double.tryParse(ride['location_extra_fee'].toString()) ?? 0.0) > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.blue[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Özel Konum (Komisyonsuz):',
                              style: TextStyle(fontSize: 11, color: Colors.blue[700], fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Text(
                          '+₺${(double.tryParse(ride['location_extra_fee'].toString()) ?? 0.0).toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 11, color: Colors.blue[700], fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 12, thickness: 1),
                // ✅ İPTAL DURUMU UYARISI
                if (isCancelled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cancel, color: Colors.red[700], size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Yolculuk iptal edildi. İptal ücreti alındı.',
                            style: TextStyle(fontSize: 11, color: Colors.red[900], fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                // BRÜT ÜCRET (final_price = taban + bekleme - indirim)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isCancelled ? 'İptal Ücreti:' : 'Brüt Ücret:',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '₺${totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                // KOMİSYON
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Komisyon (%${commissionRate.toStringAsFixed(0)}):',
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                    Text(
                      '-₺${commission.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ],
                ),
                const Divider(height: 12, thickness: 1),
                // ALDIĞINIZ TUTAR (Net Kazanç)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Aldığınız Tutar:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text(
                      '₺${netEarnings.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getPeriodText() {
    switch (_selectedPeriod) {
      case 'daily':
        return 'Bugün';
      case 'weekly':
        return 'Bu Hafta';
      case 'monthly':
        return 'Bu Ay';
      default:
        return '';
    }
  }
}
