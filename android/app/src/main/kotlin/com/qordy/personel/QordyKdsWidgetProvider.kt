package com.qordy.personel

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class QordyKdsWidgetProvider : HomeWidgetProvider() {
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

            val views = RemoteViews(context.packageName, R.layout.qordy_kds_widget).apply {
                val preparing = widgetData.getString("kds_preparing", "0") ?: "0"
                val urgent = widgetData.getString("kds_urgent", "0") ?: "0"
                val ready = widgetData.getString("kds_ready", "0") ?: "0"
                val syncTime = widgetData.getString("kds_sync_time", "Canlı • Şimdi") ?: "Canlı • Şimdi"

                setTextViewText(R.id.kds_widget_preparing, preparing)
                setTextViewText(R.id.kds_widget_urgent, urgent)
                setTextViewText(R.id.kds_widget_ready, ready)
                setTextViewText(R.id.kds_widget_sync_time, syncTime)
                setOnClickPendingIntent(R.id.widget_kds_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
