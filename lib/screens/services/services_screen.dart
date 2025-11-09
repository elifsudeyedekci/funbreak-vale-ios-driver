import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../providers/driver_ride_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/ride.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({Key? key}) : super(key: key);

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  double _totalEarnings = 0.0;
  int _totalRides = 0;
  DateTime? _startDate;
  DateTime? _endDate;
  
  // YENİ KAZANÇ RAPORU ÖZELLİKLERİ
  List<Map<String, dynamic>> _detailedRides = [];
  bool _isLoadingDetails = false;
  String _selectedPeriod = 'today'; // VARSAYILAN: BUGÜN (Açılışta günlük başlasın)
  Map<String, dynamic> _earningsBreakdown = {};

  @override
  void initState() {
    super.initState();
    _loadEarningsData();
  }

  Future<void> _loadEarningsData() async {
    setState(() {
      _isLoadingDetails = true;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final driverId = authProvider.currentUser?['id'];
      
      print('🔍 [GEÇMİŞ YOLCULUKLAR] Driver ID: $driverId');
      print('🔍 [GEÇMİŞ YOLCULUKLAR] Period: $_selectedPeriod');
      
      if (driverId != null) {
        final requestBody = {
          'driver_id': driverId,
          'period': _selectedPeriod,
          'start_date': _startDate?.toIso8601String(),
          'end_date': _endDate?.toIso8601String(),
          'include_rides': true,
          'include_breakdown': true,
        };
        
        print('📤 [GEÇMİŞ YOLCULUKLAR] Request Body: ${jsonEncode(requestBody)}');
        
        // DETAYLI KAZANÇ RAPORU API'Sİ
        final response = await http.post(
          Uri.parse('https://admin.funbreakvale.com/api/get_driver_earnings_report.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        );
        
        print('📥 [GEÇMİŞ YOLCULUKLAR] Status Code: ${response.statusCode}');
        print('📥 [GEÇMİŞ YOLCULUKLAR] Response: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('✅ [GEÇMİŞ YOLCULUKLAR] Success: ${data['success']}');
          print('✅ [GEÇMİŞ YOLCULUKLAR] Total Rides: ${data['total_rides']}');
          print('✅ [GEÇMİŞ YOLCULUKLAR] Total Earnings: ${data['total_earnings']}');
          print('✅ [GEÇMİŞ YOLCULUKLAR] Rides Count: ${data['rides']?.length ?? 0}');
          
          if (data['success'] == true) {
            setState(() {
              _totalEarnings = double.tryParse(data['total_earnings']?.toString() ?? '0') ?? 0.0;
              _totalRides = int.tryParse(data['total_rides']?.toString() ?? '0') ?? 0;
              _detailedRides = List<Map<String, dynamic>>.from(data['rides'] ?? []);
              _earningsBreakdown = data['breakdown'] ?? {};
            });
            print('✅ [GEÇMİŞ YOLCULUKLAR] setState tamamlandı - _detailedRides count: ${_detailedRides.length}');
          } else {
            print('❌ [GEÇMİŞ YOLCULUKLAR] Success = false');
          }
        } else {
          print('❌ [GEÇMİŞ YOLCULUKLAR] HTTP Error: ${response.statusCode}');
        }
      } else {
        print('❌ [GEÇMİŞ YOLCULUKLAR] Driver ID NULL!');
      }
    } catch (e) {
      print('❌ [GEÇMİŞ YOLCULUKLAR] Exception: $e');
      print('❌ [GEÇMİŞ YOLCULUKLAR] StackTrace: ${StackTrace.current}');
    } finally {
      setState(() {
        _isLoadingDetails = false;
      });
      print('🏁 [GEÇMİŞ YOLCULUKLAR] Loading tamamlandı');
    }
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Kazanç Raporu Filtresi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // PERİOD SEÇİMİ
              const Text('Dönem Seçimi', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _buildPeriodChip('today', 'Bugün', setModalState),
                  _buildPeriodChip('week', 'Bu Hafta', setModalState),
                  _buildPeriodChip('month', 'Bu Ay', setModalState),
                  _buildPeriodChip('custom', 'Özel', setModalState),
                ],
              ),
            
            if (_selectedPeriod == 'custom') ...[
              const SizedBox(height: 16),
              const Divider(),
              const Text('Özel Tarih Aralığı', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(_startDate == null ? 'Başlangıç Tarihi Seç' : '${_startDate!.day}.${_startDate!.month}.${_startDate!.year}'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now().subtract(const Duration(days: 30)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setModalState(() {
                      _startDate = date;
                    });
                    setState(() {
                      _startDate = date;
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(_endDate == null ? 'Bitiş Tarihi Seç' : '${_endDate!.day}.${_endDate!.month}.${_endDate!.year}'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: _startDate ?? DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setModalState(() {
                      _endDate = date;
                    });
                    setState(() {
                      _endDate = date;
                    });
                  }
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _startDate = null;
                _endDate = null;
                _selectedPeriod = 'today';
              });
              Navigator.pop(context);
              _loadEarningsData();
            },
            child: const Text('Sıfırla'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadEarningsData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.white,
            ),
            child: const Text('Rapor Al'),
          ),
        ],
        ),
      ),
    );
  }
  
  Widget _buildPeriodChip(String period, String title, StateSetter setModalState) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        // Hem modal'ı hem de ana ekranı güncelle (ANLIK SARI!)
        setModalState(() {
          _selectedPeriod = period;
          if (period != 'custom') {
            _startDate = null;
            _endDate = null;
          }
        });
        setState(() {
          _selectedPeriod = period;
          if (period != 'custom') {
            _startDate = null;
            _endDate = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey[300]!,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Geçmiş Yolculuklar',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFD700),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showDateFilterDialog,
            icon: const Icon(
              Icons.date_range,
              color: Color(0xFFFFD700),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEarningsData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SEÇİLİ DÖNEM GÖSTERGESİ
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Rapor Dönemi: ${_getPeriodText()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // KAZANÇ BREAKDOWN
              if (_earningsBreakdown.isNotEmpty) _buildEarningsBreakdown(),
              
              // Kazanç Özeti
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFC107)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getPeriodText()} NET Kazancınız',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '(Komisyon düştükten sonra)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₺${_totalEarnings.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.directions_car, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '$_totalRides Yolculuk',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // DETAYLI YOLCULUK LİSTESİ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Detaylı Yolculuk Listesi',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '${_detailedRides.length} Yolculuk',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              if (_isLoadingDetails)
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  ),
                )
              else if (_detailedRides.isEmpty)
                _buildEmptyState()
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _detailedRides.length,
                  itemBuilder: (context, index) {
                    final ride = _detailedRides[index];
                    return _buildDetailedRideCard(ride);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _getPeriodText() {
    switch (_selectedPeriod) {
      case 'today':
        return 'Bugün';
      case 'week':
        return 'Bu Hafta';
      case 'month':
        return 'Bu Ay';
      case 'custom':
        if (_startDate != null && _endDate != null) {
          return '${_startDate!.day}.${_startDate!.month}.${_startDate!.year} - ${_endDate!.day}.${_endDate!.month}.${_endDate!.year}';
        }
        return 'Özel Tarih';
      default:
        return 'Bugün';
    }
  }
  
  Widget _buildEarningsBreakdown() {
    final baseFare = double.tryParse(_earningsBreakdown['base_fare']?.toString() ?? '0') ?? 0.0;
    final waitingFee = double.tryParse(_earningsBreakdown['waiting_fee']?.toString() ?? '0') ?? 0.0;
    final specialFee = double.tryParse(_earningsBreakdown['special_location_fee']?.toString() ?? '0') ?? 0.0;
    final commission = double.tryParse(_earningsBreakdown['commission']?.toString() ?? '0') ?? 0.0;
    
    // 🎁 İndirim bilgilerini al
    final discountCode = _earningsBreakdown['discount_code']?.toString() ?? '';
    final discountAmount = double.tryParse(_earningsBreakdown['discount_amount']?.toString() ?? '0') ?? 0.0;
    final hasDiscount = discountCode.isNotEmpty && discountAmount > 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.indigo[50]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_lira, color: Color(0xFFFFD700), size: 22),
              SizedBox(width: 8),
              Text(
                'Kazanç Detay Analizi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildBreakdownRow('🚗 Temel Yolculuk Ücretleri', baseFare, Colors.green),
          if (waitingFee > 0) _buildBreakdownRow('⏰ Bekleme Ücretleri', waitingFee, Colors.orange),
          if (specialFee > 0) _buildBreakdownRow('🏢 Özel Konum Ücretleri', specialFee, Colors.purple),
          
          // 🎁 İndirim varsa göster
          if (hasDiscount) ...[
            const Divider(thickness: 1, color: Colors.grey),
            _buildBreakdownRow('Ara Toplam', _totalEarnings + commission + discountAmount, Colors.grey),
            _buildBreakdownRow(
              '🎁 İndirim ($discountCode)',
              discountAmount,
              Colors.orange,
              isNegative: true,
            ),
          ],
          
          _buildBreakdownRow('💸 Komisyon Kesintisi (-30%)', commission, Colors.red, isNegative: true),
          
          const Divider(thickness: 2, color: Color(0xFFFFD700)),
          
          _buildBreakdownRow('💎 Net Kazanç', _totalEarnings, const Color(0xFFFFD700), isBold: true),
        ],
      ),
    );
  }
  
  Widget _buildBreakdownRow(String title, double amount, Color color, {bool isNegative = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            '${isNegative ? '-' : ''}₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailedRideCard(Map<String, dynamic> ride) {
    final rideDate = DateTime.tryParse(ride['created_at'] ?? '') ?? DateTime.now();
    final estimatedPrice = double.tryParse(ride['estimated_price']?.toString() ?? '0') ?? 0.0;
    final finalPrice = double.tryParse(ride['final_price']?.toString() ?? '0') ?? 0.0;
    final actualPrice = finalPrice > 0 ? finalPrice : estimatedPrice;
    
    // 🎁 İndirim bilgisi
    final discountCode = ride['discount_code']?.toString() ?? '';
    final discountAmount = double.tryParse(ride['discount_amount']?.toString() ?? '0') ?? 0.0;
    final hasDiscount = discountCode.isNotEmpty && discountAmount > 0;
    final originalPrice = hasDiscount ? actualPrice + discountAmount : actualPrice;
    
    // 🔍 DEBUG
    if (ride['id'].toString() == '487' || ride['id'].toString() == '488') {
      print('🎁 SÜRÜCÜ GEÇMİŞ #${ride['id']}: discount_code=$discountCode, discount_amount=$discountAmount, hasDiscount=$hasDiscount');
    }
    
    // Backend'den gelen net_earning'i kullan! (komisyon settings'den dinamik)
    final netEarnings = ride['net_earning'] != null 
        ? (double.tryParse(ride['net_earning'].toString()) ?? (actualPrice * 0.70))
        : (actualPrice * 0.70); // Fallback: %30 komisyon
    
    final distance = double.tryParse(ride['total_distance']?.toString() ?? '0') ?? 0.0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showRideDetailModal(ride),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - Tarih ve Kazanç
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_taxi, color: Color(0xFFFFD700), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${rideDate.day}.${rideDate.month}.${rideDate.year} ${rideDate.hour.toString().padLeft(2, '0')}:${rideDate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          'Toplam: ₺${originalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          'İndirim: -₺${discountAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Kom.%30: -₺${(actualPrice * 0.30).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      Text(
                        '₺${netEarnings.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                      Text(
                        'Net Kazanç',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Rota Bilgileri
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 30,
                        color: Colors.grey[300],
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride['pickup_address']?.toString() ?? 'Alış konumu',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          ride['destination_address']?.toString() ?? 'Varış konumu',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Alt Bilgiler
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '📏 ${distance > 0 ? '${distance.toStringAsFixed(1)} km' : 'Mesafe bilinmiyor'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '⏱️ ${ride['trip_duration'] ?? 'Süre bilinmiyor'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '👤 ${ride['customer_name'] ?? 'Müşteri'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showRideDetailModal(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Yolculuk Detayları',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              
              const Divider(),
              
              // Navigasyon geçmişi ve kazanç detayları burada gösterilecek
              _buildDetailSection('🗺️ Navigasyon Bilgileri', [
                'Rota: ${ride['pickup_address']} → ${ride['destination_address']}',
                'Mesafe: ${ride['total_distance'] ?? 'Bilinmiyor'} km',
                'Süre: ${ride['trip_duration'] ?? 'Bilinmiyor'}',
              ]),
              
              _buildDetailSection('₺ Kazanç Detayları', () {
                final estimatedPrice = double.tryParse(ride['estimated_price']?.toString() ?? '0') ?? 0.0;
                final finalPrice = double.tryParse(ride['final_price']?.toString() ?? '0') ?? 0.0;
                final discountCode = ride['discount_code']?.toString() ?? '';
                final discountAmount = double.tryParse(ride['discount_amount']?.toString() ?? '0') ?? 0.0;
                final hasDiscount = discountCode.isNotEmpty && discountAmount > 0;
                final commission = finalPrice * 0.30;
                final netEarning = finalPrice * 0.70;
                
                List<String> items = [
                  'Brüt Ücret: ₺${estimatedPrice.toStringAsFixed(2)}',
                ];
                
                if (hasDiscount) {
                  items.add('🎁 İndirim ($discountCode): -₺${discountAmount.toStringAsFixed(2)}');
                }
                
                items.add('Komisyon (-30%): -₺${commission.toStringAsFixed(2)}');
                items.add('Net Kazanç: ₺${netEarning.toStringAsFixed(2)}');
                
                return items;
              }()),
              
              _buildDetailSection('👤 Müşteri Bilgileri', [
                'Müşteri: ${ride['customer_name'] ?? 'Belirtilmemiş'}',
                'Değerlendirme: ${ride['rating'] != null ? '⭐ ${ride['rating']}' : 'Değerlendirilmemiş'}',
              ]),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailSection(String title, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFD700),
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              item,
              style: const TextStyle(fontSize: 14),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
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
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.history,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz tamamlanmış yolculuk yok',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'İlk yolculuğunuzu tamamladığınızda burada görünecek',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideCard(Ride ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Yolculuk #${ride.id}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD700),
                ),
              ),
              Text(
                '₺${ride.estimatedPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ride.pickupAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ride.destinationAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(ride.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Tamamlandı',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    
    return '${date.day} ${months[date.month - 1]} ${date.year} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

