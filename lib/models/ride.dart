import 'package:google_maps_flutter/google_maps_flutter.dart';

class Ride {
  final String id;
  final String customerId;
  final String? customerName; // MÜŞTERİ İSMİ EKLENDİ!
  String? driverId;
  final LatLng pickupLocation;
  final LatLng destinationLocation;
  final String pickupAddress;
  final String destinationAddress;
  final String? specialInstructions;
  final String paymentMethod;
  final double estimatedPrice;
  final int estimatedTime;
  double? actualPrice;
  final int? actualTime;
  String status;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  DateTime? completedAt;
  final double? rating;
  final String? review;
  final DateTime? ratedAt;
  
  // New fields
  DateTime? waitingStartTime;
  int? waitingMinutes;
  double? waitingFee;
  final bool isNightPackage;
  final String? pricingPackageId;
  final double? commissionAmount;
  final DateTime? scheduledTime; // TALEP ZAMANI EKLE!

  Ride({
    required this.id,
    required this.customerId,
    this.customerName, // MÜŞTERİ İSMİ PARAMETER!
    this.driverId,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.pickupAddress,
    required this.destinationAddress,
    this.specialInstructions,
    required this.paymentMethod,
    required this.estimatedPrice,
    required this.estimatedTime,
    this.actualPrice,
    this.actualTime,
    required this.status,
    required this.createdAt,
    this.cancelledAt,
    this.completedAt,
    this.rating,
    this.review,
    this.ratedAt,
    this.waitingStartTime,
    this.waitingMinutes,
    this.waitingFee,
    this.isNightPackage = false,
    this.pricingPackageId,
    this.commissionAmount,
    this.scheduledTime, // SCHEDULED TIME PARAMETER EKLE!
  });

  factory Ride.fromMap(Map<String, dynamic> map, String id) {
    // Firebase GeoPoint yerine normal lat/lng kullan
    double pickupLat = 0.0, pickupLng = 0.0;
    double destLat = 0.0, destLng = 0.0;
    
    if (map['pickupLocation'] != null) {
      if (map['pickupLocation'] is Map) {
        pickupLat = (map['pickupLocation']['latitude'] ?? 0.0).toDouble();
        pickupLng = (map['pickupLocation']['longitude'] ?? 0.0).toDouble();
      }
    }
    
    if (map['destinationLocation'] != null) {
      if (map['destinationLocation'] is Map) {
        destLat = (map['destinationLocation']['latitude'] ?? 0.0).toDouble();
        destLng = (map['destinationLocation']['longitude'] ?? 0.0).toDouble();
      }
    }

    return Ride(
      id: id,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? map['customer_name'], // MÜŞTERİ İSMİ PARSE!
      driverId: map['driverId'],
      pickupLocation: LatLng(pickupLat, pickupLng),
      destinationLocation: LatLng(destLat, destLng),
      pickupAddress: map['pickupAddress'] ?? '',
      destinationAddress: map['destinationAddress'] ?? '',
      specialInstructions: map['specialInstructions'],
      paymentMethod: map['paymentMethod'] ?? 'cash',
      estimatedPrice: (map['estimatedPrice'] ?? 0.0).toDouble(),
      estimatedTime: map['estimatedTime'] ?? 0,
      actualPrice: map['actualPrice']?.toDouble(),
      actualTime: map['actualTime'],
      status: map['status'] ?? 'pending',
      createdAt: map['createdAt'] is DateTime 
          ? map['createdAt'] 
          : DateTime.now(),
      cancelledAt: map['cancelledAt'] is DateTime ? map['cancelledAt'] : null,
      completedAt: map['completedAt'] is DateTime ? map['completedAt'] : null,
      rating: map['rating']?.toDouble(),
      review: map['review'],
      ratedAt: map['ratedAt'] is DateTime ? map['ratedAt'] : null,
      waitingStartTime: map['waitingStartTime'] is DateTime ? map['waitingStartTime'] : null,
      waitingMinutes: map['waitingMinutes'],
      waitingFee: map['waitingFee']?.toDouble(),
      isNightPackage: map['isNightPackage'] ?? false,
      pricingPackageId: map['pricingPackageId'],
      commissionAmount: map['commissionAmount']?.toDouble(),
      scheduledTime: map['scheduledTime'] is DateTime ? map['scheduledTime'] : 
                    (map['scheduled_time'] != null ? DateTime.tryParse(map['scheduled_time'].toString()) : null), // SCHEDULED TIME PARSE!
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'driverId': driverId,
      'pickupLocation': {
        'latitude': pickupLocation.latitude,
        'longitude': pickupLocation.longitude,
      },
      'destinationLocation': {
        'latitude': destinationLocation.latitude,
        'longitude': destinationLocation.longitude,
      },
      'pickupAddress': pickupAddress,
      'destinationAddress': destinationAddress,
      'specialInstructions': specialInstructions,
      'paymentMethod': paymentMethod,
      'estimatedPrice': estimatedPrice,
      'estimatedTime': estimatedTime,
      'actualPrice': actualPrice,
      'actualTime': actualTime,
      'status': status,
      'createdAt': createdAt,
      'cancelledAt': cancelledAt,
      'completedAt': completedAt,
      'rating': rating,
      'review': review,
      'ratedAt': ratedAt,
      'waitingStartTime': waitingStartTime,
      'waitingMinutes': waitingMinutes,
      'waitingFee': waitingFee,
      'isNightPackage': isNightPackage,
      'pricingPackageId': pricingPackageId,
      'commissionAmount': commissionAmount,
      'scheduledTime': scheduledTime,
    };
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'accepted':
        return 'Kabul Edildi';
      case 'arrived':
        return 'Geldi';
      case 'started':
        return 'Yolculuk Başladı';
      case 'waiting':
        return 'Beklemede';
      case 'completed':
        return 'Tamamlandı';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return 'Bilinmiyor';
    }
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isStarted => status == 'started';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isWaiting => status == 'waiting';
} 