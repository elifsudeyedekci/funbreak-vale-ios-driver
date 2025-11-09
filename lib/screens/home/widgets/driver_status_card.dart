import 'package:flutter/material.dart';

class DriverStatusCard extends StatelessWidget {
  const DriverStatusCard({
    super.key,
    required this.isOnline,
    required this.onToggle,
  });

  final bool isOnline;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isActive = isOnline;
    final theme = Theme.of(context);
    final Color background = isActive ? const Color(0xFFFFD700) : Colors.grey.shade300;
    final Color border = isActive ? const Color(0xFFFFD700) : Colors.grey.shade400;
    final Color textColor = isActive ? Colors.white : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: border, width: 2),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD700).withOpacity(0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.wifi : Icons.wifi_off,
            color: textColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isActive ? 'Çevrimiçi' : 'Çevrimdışı',
            style: theme.textTheme.titleMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: isActive,
            onChanged: (_) => onToggle(),
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withOpacity(0.3),
            inactiveThumbColor: Colors.grey.shade600,
            inactiveTrackColor: Colors.grey.shade400,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
