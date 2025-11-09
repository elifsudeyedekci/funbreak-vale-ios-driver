import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final double size;
  final Color filledColor;
  final Color emptyColor;
  final bool showRating;

  const StarRating({
    Key? key,
    required this.rating,
    this.size = 16.0,
    this.filledColor = const Color(0xFFFFD700),
    this.emptyColor = const Color(0xFFDDDDDD),
    this.showRating = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (index) {
          if (index < fullStars) {
            return Icon(
              Icons.star,
              size: size,
              color: filledColor,
            );
          } else if (index == fullStars && hasHalfStar) {
            return Icon(
              Icons.star_half,
              size: size,
              color: filledColor,
            );
          } else {
            return Icon(
              Icons.star_border,
              size: size,
              color: emptyColor,
            );
          }
        }),
        if (showRating) ...[
          const SizedBox(width: 5),
          Text(
            '(${rating.toStringAsFixed(1)})',
            style: TextStyle(
              fontSize: size * 0.75,
              color: Colors.grey[600],
            ),
          ),
        ],
      ],
    );
  }
} 