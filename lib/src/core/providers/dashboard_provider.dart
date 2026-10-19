import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mobile_api_service.dart';
import '../data/dashboard_model.dart';

class DashboardState {
 final bool isLoading;
 final DashboardData? data;
 final String? error;
 final String selectedPeriod;

 const DashboardState({
 this.isLoading = false,
 this.data,
 this.error,
 this.selectedPeriod = 'today',
 });

 DashboardState copyWith({
 bool? isLoading,
 DashboardData? data,
 String? error,
 String? selectedPeriod,
 }) {
 return DashboardState(
 isLoading: isLoading ?? this.isLoading,
 data: data ?? this.data,
 error: error ?? this.error,
 selectedPeriod: selectedPeriod ?? this.selectedPeriod,
 );
 }
}

class DashboardNotifier extends Notifier<AsyncValue<DashboardData?>> {
  MobileApiService get _mobileApi => ref.read(mobileApiProvider);
  String _selectedPeriod = 'today';

  @override
  AsyncValue<DashboardData?> build() {
    return const AsyncValue.data(null);
  }

  Future<void> loadDashboard(String period) async {
    _selectedPeriod = period;
    state = const AsyncValue.loading();
    try {
      final data = await _mobileApi.getStaffDashboard(period: period);
      state = AsyncValue.data(data);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await loadDashboard(_selectedPeriod);
  }
}

final dashboardProvider = NotifierProvider<DashboardNotifier, AsyncValue<DashboardData?>>(() {
  return DashboardNotifier();
});
