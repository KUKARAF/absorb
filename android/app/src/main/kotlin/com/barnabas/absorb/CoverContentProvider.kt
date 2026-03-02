package com.barnabas.absorb

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * ContentProvider that serves cover images to Android Auto.
 *
 * Android Auto cannot load HTTP or file:// URIs directly — it requires
 * content:// URIs.  This provider maps:
 *   content://com.barnabas.absorb.covers/cover/<itemId>
 *
 * Lookup order:
 *   1. Locally downloaded cover (item's download directory)
 *   2. Cached cover fetched from the ABS server (cacheDir/aa_covers/)
 *   3. Fetch from server on-demand → cache → serve
 */
class CoverContentProvider : ContentProvider() {

    companion object {
        const val AUTHORITY = "com.barnabas.absorb.covers"
        private const val TAG = "CoverProvider"

        fun buildCoverUri(itemId: String): Uri {
            return Uri.parse("content://$AUTHORITY/cover/$itemId")
        }
    }

    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val itemId = extractItemId(uri) ?: return null
        val context = context ?: return null
        val coverFile = findCoverFile(context, itemId)
        if (coverFile != null) {
            return ParcelFileDescriptor.open(coverFile, ParcelFileDescriptor.MODE_READ_ONLY)
        }

        // Not available locally — try fetching from the server and caching
        val cached = fetchAndCache(context, itemId) ?: return null
        return ParcelFileDescriptor.open(cached, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "image/jpeg"

    override fun getStreamTypes(uri: Uri, mimeTypeFilter: String): Array<String>? {
        if (mimeTypeFilter == "*/*" ||
            mimeTypeFilter == "image/*" ||
            mimeTypeFilter == "image/jpeg") {
            return arrayOf("image/jpeg")
        }
        return null
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val itemId = extractItemId(uri) ?: return null
        val context = context ?: return null
        val coverFile = findCoverFile(context, itemId)
            ?: fetchAndCache(context, itemId)
            ?: return null

        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(cols.map { it }.toTypedArray())
        val row = cols.map { col ->
            when (col) {
                OpenableColumns.DISPLAY_NAME -> "cover.jpg"
                OpenableColumns.SIZE -> coverFile.length()
                else -> null
            }
        }.toTypedArray()
        cursor.addRow(row)
        return cursor
    }

    // ── Server fetch + cache ──

    private fun fetchAndCache(context: android.content.Context, itemId: String): File? {
        try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", android.content.Context.MODE_PRIVATE
            )
            val serverUrl = prefs.getString("flutter.server_url", null)
            val token = prefs.getString("flutter.token", null)
            if (serverUrl.isNullOrEmpty() || token.isNullOrEmpty()) {
                Log.w(TAG, "No server_url or token in prefs — cannot fetch cover")
                return null
            }

            val cleanUrl = serverUrl.trimEnd('/')
            val fetchUrl = "$cleanUrl/api/items/$itemId/cover?width=400&token=$token"

            val cacheDir = File(context.cacheDir, "aa_covers")
            if (!cacheDir.exists()) cacheDir.mkdirs()
            val cacheFile = File(cacheDir, "$itemId.jpg")

            val connection = URL(fetchUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.instanceFollowRedirects = true

            try {
                if (connection.responseCode != 200) {
                    Log.w(TAG, "Cover fetch failed: HTTP ${connection.responseCode} for $itemId")
                    return null
                }
                connection.inputStream.use { input ->
                    cacheFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            } finally {
                connection.disconnect()
            }

            if (cacheFile.exists() && cacheFile.length() > 0) {
                Log.d(TAG, "Cached cover for $itemId (${cacheFile.length()} bytes)")
                return cacheFile
            }
            cacheFile.delete()
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Error fetching cover for $itemId", e)
            return null
        }
    }

    // ── Helpers ──

    private fun extractItemId(uri: Uri): String? {
        val segments = uri.pathSegments
        // Expected: /cover/<itemId>
        if (segments.size != 2 || segments[0] != "cover") return null
        val itemId = segments[1]
        // Sanitize — only allow alphanumeric, hyphens, underscores
        if (!itemId.matches(Regex("^[a-zA-Z0-9_\\-]+$"))) return null
        return itemId
    }

    private fun findCoverFile(context: android.content.Context, itemId: String): File? {
        // Check custom download path first (stored in SharedPreferences)
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val customPath = prefs.getString("flutter.custom_download_path", null)

        if (customPath != null && customPath.isNotEmpty()) {
            val file = File("$customPath/$itemId/cover.jpg")
            if (file.exists() && file.canRead()) return file
        }

        // Default: app documents directory
        val docsDir = context.filesDir?.parentFile?.let { File(it, "app_flutter/downloads") }
        if (docsDir != null) {
            val file = File("$docsDir/$itemId/cover.jpg")
            if (file.exists() && file.canRead()) return file
        }

        // Also try getExternalFilesDir path
        val extDir = context.getExternalFilesDir(null)
        if (extDir != null) {
            val file = File("${extDir.parent}/app_flutter/downloads/$itemId/cover.jpg")
            if (file.exists() && file.canRead()) return file
        }

        // Check the server-fetch cache
        val cacheFile = File(context.cacheDir, "aa_covers/$itemId.jpg")
        if (cacheFile.exists() && cacheFile.length() > 0) return cacheFile

        return null
    }

    // Not used — read-only provider
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, s: String?, sa: Array<out String>?): Int = 0
    override fun delete(uri: Uri, s: String?, sa: Array<out String>?): Int = 0
}
