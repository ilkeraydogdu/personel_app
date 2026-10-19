package com.qordy.personel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class QordyWaiterWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val views = RemoteViews(context.packageName, R.layout.qordy_waiter_widget).apply {
                val pendingCalls = widgetData.getString("waiter_pending_calls", "0") ?: "0"
                val activeTables = widgetData.getString("waiter_active_tables", "0") ?: "0"
                val lastEvent = widgetData.getString("waiter_last_event", "Tüm masalar sakin ✨") ?: "Tüm masalar sakin ✨"
                val syncTime = widgetData.getString("waiter_sync_time", "Canlı • Şimdi") ?: "Canlı • Şimdi"

                setTextViewText(R.id.waiter_widget_pending_calls, pendingCalls)
                setTextViewText(R.id.waiter_widget_active_tables, activeTables)
                setTextViewText(R.id.waiter_widget_last_event, "Son: $lastEvent")
                setTextViewText(R.id.waiter_widget_sync_time, syncTime)
                setOnClickPendingIntent(R.id.widget_waiter_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
