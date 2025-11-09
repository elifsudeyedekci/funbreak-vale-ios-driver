import 'package:cloud_firestore/cloud_firestore.dart';

class PricingPackage {
  final String id;
  final String name;
  final String type; // 'distance' or 'hourly'
  final double basePrice;
  final double perKmRate;
  final double perHourRate;
  final double commissionRate;
  final bool isActive;
  final DateTime createdAt;

  PricingPackage({
    required this.id,
    required this.name,
    required this.type,
    required this.basePrice,
    required this.perKmRate,
    required this.perHourRate,
    required this.commissionRate,
    required this.isActive,
    required this.createdAt,
  });

  factory PricingPackage.fromMap(Map<String, dynamic> map) {
    return PricingPackage(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'distance',
      basePrice: (map['basePrice'] ?? 0.0).toDouble(),
      perKmRate: (map['perKmRate'] ?? 0.0).toDouble(),
      perHourRate: (map['perHourRate'] ?? 0.0).toDouble(),
      commissionRate: (map['commissionRate'] ?? 0.0).toDouble(),
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'basePrice': basePrice,
      'perKmRate': perKmRate,
      'perHourRate': perHourRate,
      'commissionRate': commissionRate,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class WaitingFeeSettings {
  final double freeMinutes;
  final double feePer15Minutes;
  final bool isActive;

  WaitingFeeSettings({
    required this.freeMinutes,
    required this.feePer15Minutes,
    required this.isActive,
  });

  factory WaitingFeeSettings.fromMap(Map<String, dynamic> map) {
    return WaitingFeeSettings(
      freeMinutes: (map['freeMinutes'] ?? 15.0).toDouble(),
      feePer15Minutes: (map['feePer15Minutes'] ?? 100.0).toDouble(),
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'freeMinutes': freeMinutes,
      'feePer15Minutes': feePer15Minutes,
      'isActive': isActive,
    };
  }
}

class NightPackageSettings {
  final int minHoursForNightPackage;
  final double nightPackageMultiplier;
  final bool isActive;

  NightPackageSettings({
    required this.minHoursForNightPackage,
    required this.nightPackageMultiplier,
    required this.isActive,
  });

  factory NightPackageSettings.fromMap(Map<String, dynamic> map) {
    return NightPackageSettings(
      minHoursForNightPackage: map['minHoursForNightPackage'] ?? 2,
      nightPackageMultiplier: (map['nightPackageMultiplier'] ?? 1.5).toDouble(),
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'minHoursForNightPackage': minHoursForNightPackage,
      'nightPackageMultiplier': nightPackageMultiplier,
      'isActive': isActive,
    };
  }
} 