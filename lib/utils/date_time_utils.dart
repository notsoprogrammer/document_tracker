/// Utility functions for date and time handling, specifically for Philippine timezone (UTC+8)

/// Returns the current date and time in Philippine timezone (UTC+8)
DateTime getPhilippineTime() {
  final nowUtc = DateTime.now().toUtc();
  return nowUtc.add(const Duration(hours: 8));
}
