package io.veil.mobile

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * veil/file_open: opens one decrypted file in the app the user has for it.
 *
 * The viewer starts in a task of its own (NEW_TASK and MULTIPLE_TASK, never
 * SINGLE_TOP), so Veil's task never holds the plaintext: Veil is hidden, it
 * locks, and coming back to it from the launcher or the app switcher shows
 * the lock screen, never the file. Only a file under cache/veil_open is
 * handed over, through the app's own VeilOpenFileProvider, and the viewer
 * gets read access to that one URI. The call answers "opened" at once,
 * "noApp" when nothing can show the file, or "failed".
 */
class FileOpenChannel(private val context: Context) {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> result.success(open(call.argument<String>("path"), call.argument<String>("mimeType")))
                else -> result.notImplemented()
            }
        }
    }

    private fun open(path: String?, mimeType: String?): String {
        if (path.isNullOrEmpty() || mimeType.isNullOrEmpty()) {
            return "failed"
        }
        return try {
            val folder = File(context.cacheDir, OPEN_FOLDER).canonicalFile
            val file = File(path).canonicalFile
            if (!file.path.startsWith(folder.path + File.separator) || !file.isFile) {
                return "failed"
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.veil_open", file)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mimeType)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            context.startActivity(intent)
            "opened"
        } catch (error: ActivityNotFoundException) {
            "noApp"
        } catch (error: Exception) {
            "failed"
        }
    }

    companion object {
        private const val CHANNEL_NAME = "veil/file_open"
        private const val OPEN_FOLDER = "veil_open"
    }
}
