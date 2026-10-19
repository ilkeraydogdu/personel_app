import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/business/data/table_model.dart';
import '../services/mobile_api_service.dart';

class TablesState {
 final bool isLoading;
 final List<ZoneModel> zones;
 final String? error;

 const TablesState({
 this.isLoading = false,
 this.zones = const [],
 this.error,
 });

 TablesState copyWith({
 bool? isLoading,
 List<ZoneModel>? zones,
 String? error,
 }) {
 return TablesState(
 isLoading: isLoading ?? this.isLoading,
 zones: zones ?? this.zones,
 error: error ?? this.error,
 );
 }
}

class TablesNotifier extends Notifier<TablesState> {
  MobileApiService get _mobileApi => ref.read(mobileApiProvider);

  @override
  TablesState build() {
    Future.microtask(_loadTables);
    return const TablesState();
  }

  Future<void> _loadTables() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final zones = await _mobileApi.getTables();
      state = state.copyWith(isLoading: false, zones: zones);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> refresh() async => _loadTables();
}

final tablesProvider = NotifierProvider<TablesNotifier, TablesState>(() {
  return TablesNotifier();
});
