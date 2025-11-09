import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/driver_ride_provider.dart';
import 'driver_status_card.dart';

class DriverToggleSection extends StatelessWidget {
  const DriverToggleSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<DriverRideProvider>(
      builder: (context, driverProvider, _) {
        final bool isOnline = driverProvider.isOnline;

        return Column(
          children: [
            const SizedBox(height: 16),
            Center(
              child: DriverStatusCard(
                isOnline: isOnline,
                onToggle: driverProvider.toggleOnlineStatus,
              ),
            ),
            if (!isOnline) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Çevrimiçi olursanız sistem tarafından otomatik olarak size bir müşteri atanacaktır.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.orange[800],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
