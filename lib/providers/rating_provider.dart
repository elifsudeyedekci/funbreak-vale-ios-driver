import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RatingProvider extends ChangeNotifier {
  static const String baseUrl = 'https://admin.funbreakvale.com/api';
  
  Map<String, double> _driverRatings = {};
  Map<String, int> _driverRatingCounts = {};
  bool _isLoading = false;
  
  // Getters
  Map<String, double> get driverRatings => _driverRatings;
  Map<String, int> get driverRatingCounts => _driverRatingCounts;
  bool get isLoading => _isLoading;

  // Şoför puanlaması yap
  Future<bool> rateDriver({
    required String rideId,
    required String driverId,
    required String customerId,
    required double rating,
    String? comment,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await http.post(
        Uri.parse('$baseUrl/rate_driver.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ride_id': rideId,
          'driver_id': driverId,
          'customer_id': customerId,
          'rating': rating,
          'comment': comment,
          'rated_at': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Şoför puanını güncelle
          await _updateDriverRating(driverId);
          _isLoading = false;
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('Puanlama hatası: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Şoför puanını güncelle
  Future<void> _updateDriverRating(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_driver_rating.php?driver_id=$driverId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _driverRatings[driverId] = double.parse(data['average_rating'].toString());
          _driverRatingCounts[driverId] = int.parse(data['rating_count'].toString());
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Şoför puanı güncelleme hatası: $e');
    }
  }

  // Şoför puanını getir
  Future<Map<String, dynamic>> getDriverRating(String driverId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/get_driver_rating.php?driver_id=$driverId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'average_rating': double.parse(data['average_rating'].toString()),
            'rating_count': int.parse(data['rating_count'].toString()),
            'comments': List<Map<String, dynamic>>.from(data['comments'] ?? []),
          };
        }
      }
    } catch (e) {
      debugPrint('Şoför puanı getirme hatası: $e');
    }

    return {
      'average_rating': 0.0,
      'rating_count': 0,
      'comments': [],
    };
  }
}