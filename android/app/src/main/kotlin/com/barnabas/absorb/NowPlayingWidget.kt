package com.barnabas.absorb

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class NowPlayingWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private fun roundBitmap(bitmap: Bitmap, radiusDp: Float, context: Context): Bitmap {
            val density = context.resources.displayMetrics.density
            val radiusPx = radiusDp * density
            val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(output)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val rect = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
            canvas.drawRoundRect(rect, radiusPx, radiusPx, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            canvas.drawBitmap(bitmap, 0f, 0f, paint)
            return output
        }

        private fun blurredBackground(source: Bitmap, radiusDp: Float, context: Context): Bitmap {
            // Crop center band to ~2:1 aspect ratio (zoomed-in center, no stretching)
            val srcW = source.width
            val srcH = source.height
            val cropH = (srcW / 2).coerceAtMost(srcH)
            val cropY = (srcH - cropH) / 2
            val cropped = Bitmap.createBitmap(source, 0, cropY, srcW, cropH)

            // Scale down to tiny size then back up = cheap blur
            val small = Bitmap.createScaledBitmap(cropped, 16, 8, true)
            val blurred = Bitmap.createScaledBitmap(small, 400, 200, true)

            // Darken so white text stays readable
            val output = blurred.copy(Bitmap.Config.ARGB_8888, true)
            val canvas = Canvas(output)
            val paint = Paint()
            paint.color = 0xAA000000.toInt() // ~67% black overlay
            canvas.drawRect(0f, 0f, 400f, 200f, paint)

            return output
        }

        private fun mediaButtonPendingIntent(
            context: Context,
            keyCode: Int,
            requestCode: Int
        ): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(
                    context,
                    "com.ryanheise.audioservice.MediaButtonReceiver"
                )
                putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                )
            }
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.now_playing_widget)

            val title = widgetData.getString("widget_title", null)
            val author = widgetData.getString("widget_author", null)
            val isPlaying = widgetData.getBoolean("widget_is_playing", false)
            val progress = widgetData.getInt("widget_progress", 0)
            val coverPath = widgetData.getString("widget_cover_path", null)

            if (!title.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(R.id.widget_author, author ?: "")
                views.setProgressBar(R.id.widget_progress, 1000, progress, false)
                views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                views.setViewVisibility(R.id.widget_controls, View.VISIBLE)

                if (isPlaying) {
                    views.setImageViewResource(R.id.widget_play_pause, R.drawable.ic_widget_pause)
                } else {
                    views.setImageViewResource(R.id.widget_play_pause, R.drawable.ic_widget_play)
                }

                // Cover art from file (rounded corners + blurred background)
                if (coverPath != null) {
                    val file = File(coverPath)
                    if (file.exists()) {
                        val options = BitmapFactory.Options().apply { inSampleSize = 2 }
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath, options)
                        if (bitmap != null) {
                            views.setImageViewBitmap(R.id.widget_cover, roundBitmap(bitmap, 16f, context))
                            views.setImageViewBitmap(R.id.widget_bg_blur, blurredBackground(bitmap, 24f, context))
                            views.setViewVisibility(R.id.widget_bg_blur, View.VISIBLE)
                        } else {
                            views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                            views.setViewVisibility(R.id.widget_bg_blur, View.GONE)
                        }
                    } else {
                        views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                        views.setViewVisibility(R.id.widget_bg_blur, View.GONE)
                    }
                } else {
                    views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                    views.setViewVisibility(R.id.widget_bg_blur, View.GONE)
                }
            } else {
                // Idle state
                views.setTextViewText(R.id.widget_title, "Absorb")
                views.setTextViewText(R.id.widget_author, "Not playing")
                views.setProgressBar(R.id.widget_progress, 1000, 0, false)
                views.setViewVisibility(R.id.widget_progress, View.INVISIBLE)
                views.setViewVisibility(R.id.widget_controls, View.GONE)
                views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                views.setViewVisibility(R.id.widget_bg_blur, View.GONE)
            }

            // Tap widget body to bring existing app to front
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            // Playback controls via MediaSession (same as notification/headphone buttons)
            views.setOnClickPendingIntent(
                R.id.widget_skip_back,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_REWIND, 2)
            )
            views.setOnClickPendingIntent(
                R.id.widget_play_pause,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 1)
            )
            views.setOnClickPendingIntent(
                R.id.widget_skip_forward,
                mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, 3)
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
