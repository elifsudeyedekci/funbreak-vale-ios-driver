import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PricingProvider with ChangeNotifier {
  Map<String, double> _pricingRates = {
    'base_fare': 10.0,
    'per_km': 2.5,
    'per_minute': 0.5,
    'night_multiplier': 1.2,
    'waiting_fee_per_minute': 1.0,
  };

  Map<String, double> get pricingRates => _pricingRates;
  
  // Eksik getter'lar
  double get baseFare => _pricingRates['base_fare'] ?? 10.0;
  double get perKm => _pricingRates['per_km'] ?? 2.5;
  double get perMinute => _pricingRates['per_minute'] ?? 0.5;
  double get nightMultiplier => _pricingRates['night_multiplier'] ?? 1.2;
  double get waitingFeePerMinute => _pricingRates['waiting_fee_per_minute'] ?? 1.0;

  Future<void> loadPricing() async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.funbreakvale.com/api/pricing.php'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          _pricingRates = Map<String, double>.from(data['pricing']);
          notifyListeners();
        }
      }
    } catch (e) {
      print('Fiyatlandırma yüklenemedi: $e');
    }
  }

  double calculatePrice(double distanceInKm) {
    double baseFare = _pricingRates['base_fare'] ?? 10.0;
    double perKm = _pricingRates['per_km'] ?? 2.5;
    
    double totalPrice = baseFare + (distanceInKm * perKm);
    
    // Gece ücreti kontrolü (22:00 - 06:00 arası)
    DateTime now = DateTime.now();
    int hour = now.hour;
    if (hour >= 22 || hour < 6) {
      double nightMultiplier = _pricingRates['night_multiplier'] ?? 1.2;
      totalPrice *= nightMultiplier;
    }
    
    return totalPrice;
  }

  double calculateWaitingFee(int waitingMinutes) {
    double waitingFeePerMinute = _pricingRates['waiting_fee_per_minute'] ?? 1.0;
    return waitingMinutes * waitingFeePerMinute;
  }
} 