import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import 'auth_provider.dart';
import 'dashboard_provider.dart';
import 'tables_provider.dart';
import '../../features/pos/application/pos_provider.dart';
import '../../features/waiter/application/waiter_provider.dart';
import '../../features/kitchen/application/kitchen_provider.dart';
import '../../features/preparation/application/prep_provider.dart';

class ShiftStatus {
  final bool isOnShift;
  final bool isSilentMode;
  final String scheduleType;
  final Map<String, dynamic>? activeShift;
  final Map<String, dynamic>? weeklySchedule;
  final String currentTime;
  final int dayOfWeek;
  final bool isOpen;
  final String shiftDate;
  final String? shiftStart;
  final String? shiftEnd;
  final int? secondsUntilShiftEnd;
  final Map<String, dynamic>? workingHours;

  const ShiftStatus({
    this.isOnShift = true,
    this.isSilentMode = false,
    this.scheduleType = 'default',
    this.activeShift,
    this.weeklySchedule,
    this.currentTime = '',
    this.dayOfWeek = 0,
    this.isOpen = true,
    this.shiftDate = '',
    this.shiftStart,
    this.shiftEnd,
    this.secondsUntilShiftEnd,
    this.workingHours,
  });

  ShiftStatus copyWith({
    bool? isOnShift,
    bool? isSilentMode,
    String? scheduleType,
    Map<String, dynamic>? activeShift,
    Map<String, dynamic>? weeklySchedule,
    String? currentTime,
    int? dayOfWeek,
    bool? isOpen,
    String? shiftDate,
    String? shiftStart,
    String? shiftEnd,
    int? secondsUntilShiftEnd,
    Map<String, dynamic>? workingHours,
  }) {
    return ShiftStatus(
      isOnShift: isOnShift ?? this.isOnShift,
      isSilentMode: isSilentMode ?? this.isSilentMode,
      scheduleType: scheduleType ?? this.scheduleType,
      activeShift: activeShift ?? this.activeShift,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      currentTime: currentTime ?? this.currentTime,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      isOpen: isOpen ?? this.isOpen,
      shiftDate: shiftDate ?? this.shiftDate,
      shiftStart: shiftStart ?? this.shiftStart,
      shiftEnd: shiftEnd ?? this.shiftEnd,
      secondsUntilShiftEnd: secondsUntilShiftEnd ?? this.secondsUntilShiftEnd,
      workingHours: workingHours ?? this.workingHours,
    );
  }
}

class ShiftNotifier extends StateNotifier<ShiftStatus> {
  final Ref _ref;
  final ApiClient _api;
  Timer? _shiftEndTimer;
  Timer? _periodicCheckTimer;

  ShiftNotifier(this._ref, this._api) : super(const ShiftStatus()) {
    checkShiftStatus();
    _startPeriodicChecks();
  }

  void _startPeriodicChecks() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      checkShiftStatus();
    });
  }

  void _scheduleShiftEndRefresh(int seconds) {
    _shiftEndTimer?.cancel();
    if (seconds <= 0) return;
    _shiftEndTimer = Timer(Duration(seconds: seconds + 2), () async {
      await checkShiftStatus();
      _refreshOperationalData();
    });
  }

  void _refreshOperationalData() {
    try {
      _ref.invalidate(posTablesProvider);
      _ref.invalidate(waiterZonesProvider);
      _ref.invalidate(kitchenOrdersProvider);
      _ref.invalidate(prepOrdersProvider);
      _ref.invalidate(tablesProvider);
      _ref.invalidate(dashboardProvider);
    } catch (e) {
      debugPrint('[ShiftNotifier] Error invalidating operational data: $e');
    }
  }

  @override
  void dispose() {
    _shiftEndTimer?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> checkShiftStatus() async {
    try {
      final response = await _api.get('/staff/shift-status');
      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>? ?? {};
        final isOnShift = data['is_on_shift'] == true;
        final silentMode = data['silent_mode'] == true;
        final secondsUntilEnd = int.tryParse('${data['seconds_until_shift_end']}');

        if (secondsUntilEnd != null && secondsUntilEnd > 0) {
          _scheduleShiftEndRefresh(secondsUntilEnd);
        }

        state = ShiftStatus(
          isOnShift: isOnShift,
          isSilentMode: silentMode,
          scheduleType: data['schedule_type']?.toString() ?? 'default',
          activeShift: data['active_shift'] is Map ? Map<String, dynamic>.from(data['active_shift']) : null,
          weeklySchedule: data['weekly_schedule'] is Map ? Map<String, dynamic>.from(data['weekly_schedule']) : null,
          currentTime: data['current_time']?.toString() ?? '',
          dayOfWeek: int.tryParse('${data['day_of_week'] ?? 0}') ?? 0,
          isOpen: data['is_open'] != false,
          shiftDate: data['shift_date']?.toString() ?? '',
          shiftStart: data['shift_start']?.toString(),
          shiftEnd: data['shift_end']?.toString(),
          secondsUntilShiftEnd: secondsUntilEnd,
          workingHours: data['working_hours'] is Map ? Map<String, dynamic>.from(data['working_hours']) : null,
        );
      }
    } catch (e) {
      debugPrint('[ShiftNotifier] Failed to check shift status: $e');
      // If endpoint error, keep default on-shift to not block operational staff
    }
  }

  void toggleSilentMode() {
    state = state.copyWith(isSilentMode: !state.isSilentMode);
  }
}

final shiftProvider = StateNotifierProvider<ShiftNotifier, ShiftStatus>((ref) {
  // Trigger refresh on auth state change
  ref.watch(authProvider);
  return ShiftNotifier(ref, ref.watch(apiClientProvider));
});
