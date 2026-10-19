import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

class PersonelWidgetSyncService {
  static const String appGroupId = 'group.com.qordy.personel';
  static const String androidKdsWidgetName = 'QordyKdsWidgetProvider';
  static const String androidWaiterWidgetName = 'QordyWaiterWidgetProvider';
  static const String iosKdsWidgetName = 'QordyKdsWidget';
  static const String iosWaiterWidgetName = 'QordyWaiterWidget';

  /// Initializes the HomeWidget plugin for iOS App Group & Android
  static Future<void> initialize() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      debugPrint('[PersonelWidgetSync] HomeWidget initialized with group $appGroupId');
    } catch (e) {
      debugPrint('[PersonelWidgetSync] Initialization error: $e');
    }
  }

  /// Syncs Kitchen (KDS) data to the native iOS WidgetKit & Android widget
  static Future<void> updateKdsWidget({
    required int preparing,
    required int urgent,
    required int ready,
  }) async {
    try {
      final now = DateFormat('HH:mm').format(DateTime.now());
      final syncLabel = 'Canlı • $now';

      await HomeWidget.saveWidgetData<String>('kds_preparing', preparing.toString());
      await HomeWidget.saveWidgetData<String>('kds_urgent', urgent.toString());
      await HomeWidget.saveWidgetData<String>('kds_ready', ready.toString());
      await HomeWidget.saveWidgetData<String>('kds_sync_time', syncLabel);

      await HomeWidget.updateWidget(
        name: iosKdsWidgetName,
        iOSName: iosKdsWidgetName,
        androidName: androidKdsWidgetName,
        qualifiedAndroidName: 'com.qordy.personel.$androidKdsWidgetName',
      );

      debugPrint('[PersonelWidgetSync] KDS Widget updated: Prep=$preparing, Urgent=$urgent, Ready=$ready at $now');
    } catch (e) {
      debugPrint('[PersonelWidgetSync] Failed to update KDS Widget: $e');
    }
  }

  /// Syncs Waiter data to the native iOS WidgetKit & Android widget
  static Future<void> updateWaiterWidget({
    required int pendingCalls,
    required int activeTables,
    String? lastEvent,
  }) async {
    try {
      final now = DateFormat('HH:mm').format(DateTime.now());
      final syncLabel = 'Canlı • $now';
      final eventText = (lastEvent != null && lastEvent.isNotEmpty)
          ? lastEvent
          : (pendingCalls > 0 ? '$pendingCalls masa çağrı bekliyor!' : 'Tüm masalar sakin ✨');

      await HomeWidget.saveWidgetData<String>('waiter_pending_calls', pendingCalls.toString());
      await HomeWidget.saveWidgetData<String>('waiter_active_tables', activeTables.toString());
      await HomeWidget.saveWidgetData<String>('waiter_last_event', eventText);
      await HomeWidget.saveWidgetData<String>('waiter_sync_time', syncLabel);

      await HomeWidget.updateWidget(
        name: iosWaiterWidgetName,
        iOSName: iosWaiterWidgetName,
        androidName: androidWaiterWidgetName,
        qualifiedAndroidName: 'com.qordy.personel.$androidWaiterWidgetName',
      );

      debugPrint('[PersonelWidgetSync] Waiter Widget updated: Calls=$pendingCalls, Tables=$activeTables at $now');
    } catch (e) {
      debugPrint('[PersonelWidgetSync] Failed to update Waiter Widget: $e');
    }
  }
}
