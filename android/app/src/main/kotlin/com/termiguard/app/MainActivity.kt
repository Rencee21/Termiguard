package com.termiguard.app

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Adds a MethodChannel used by lib/services/web_download_io.dart to
/// save the "Export Labeled Scan (CSV)" files into the public
/// MediaStore Downloads/Termiguard folder on Android 10+ (API 29+), and
/// to open/share them afterwards. No storage permission is needed for
/// any of this - MediaStore.Downloads handles that for apps targeting
/// scoped storage.
class MainActivity : FlutterActivity() {
    private val channelName = "com.termiguard.app/csv_export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        val subfolder = call.argument<String>("subfolder") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: "text/csv"

                        if (fileName == null || bytes == null) {
                            result.error("BAD_ARGS", "fileName and bytes are required", null)
                            return@setMethodCallHandler
                        }
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error(
                                "UNSUPPORTED_SDK",
                                "MediaStore Downloads needs Android 10 (API 29)+",
                                null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(fileName, bytes, subfolder, mimeType).toString())
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    "openUri" -> {
                        val uriString = call.argument<String>("uri")
                        val mimeType = call.argument<String>("mimeType") ?: "text/csv"
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse(uriString), mimeType)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: ActivityNotFoundException) {
                            result.error("NO_VIEWER", "No app found to open this file", null)
                        }
                    }

                    "shareUri" -> {
                        val uriString = call.argument<String>("uri")
                        val mimeType = call.argument<String>("mimeType") ?: "text/csv"
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        val sendIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, Uri.parse(uriString))
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(sendIntent, null))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(
        fileName: String,
        bytes: ByteArray,
        subfolder: String,
        mimeType: String
    ): Uri {
        val relativePath = if (subfolder.isNotEmpty()) {
            "${Environment.DIRECTORY_DOWNLOADS}/$subfolder"
        } else {
            Environment.DIRECTORY_DOWNLOADS
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
        }

        val itemUri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore refused to create $fileName")

        contentResolver.openOutputStream(itemUri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("Could not open output stream for $fileName")

        return itemUri
    }
}
