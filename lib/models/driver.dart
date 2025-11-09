import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Driver {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? licensePlate;
  final String? vehicleInfo;
  final double rating;
  final int totalRides;
  final bool isOnline;
  final bool isActive;
  final LatLng? currentLocation;
  final DateTime createdAt;
  final DateTime? lastUpdated;

  Driver({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    this.licensePlate,
    this.vehicleInfo,
    required this.rating,
    required this.totalRides,
    required this.isOnline,
    required this.isActive,
    this.currentLocation,
    required this.createdAt,
    this.lastUpdated,
  });

  factory Driver.fromMap(Map<String, dynamic> map, String id) {
    return Driver(
      id: id,
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      licensePlate: map['licensePlate'],
      vehicleInfo: map['vehicleInfo'],
      rating: (map['rating'] ?? 0.0).toDouble(),
      totalRides: map['totalRides'] ?? 0,
      isOnline: map['isOnline'] ?? false,
      isActive: map['isActive'] ?? true,
      currentLocation: map['currentLocation'] != null
          ? LatLng(
              map['currentLocation']['latitude'],
              map['currentLocation']['longitude'],
            )
          : null,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      lastUpdated: map['lastUpdated'] != null
          ? (map['lastUpdated'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'licensePlate': licensePlate,
      'vehicleInfo': vehicleInfo,
      'rating': rating,
      'totalRides': totalRides,
      'isOnline': isOnline,
      'isActive': isActive,
      'currentLocation': currentLocation != null
          ? {
              'latitude': currentLocation!.latitude,
              'longitude': currentLocation!.longitude,
            }
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
    };
  }

  Driver copyWith({
    String? id,
    String? fullName,
    String? email,
    String? phone,
    String? licensePlate,
    String? vehicleInfo,
    double? rating,
    int? totalRides,
    bool? isOnline,
    bool? isActive,
    LatLng? currentLocation,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return Driver(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      licensePlate: licensePlate ?? this.licensePlate,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
      rating: rating ?? this.rating,
      totalRides: totalRides ?? this.totalRides,
      isOnline: isOnline ?? this.isOnline,
      isActive: isActive ?? this.isActive,
      currentLocation: currentLocation ?? this.currentLocation,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
} 