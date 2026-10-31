package com.lemonledger.lemon_ledger

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VOICE_CHANNEL = "lemon_ledger/voice"
    private val FILES_CHANNEL = "lemon_ledger/files"
    private var speechRecognizer: SpeechRecognizer? = null

    // 文件选择结果
    private var pendingFileResult: MethodChannel.Result? = null
    private val FILE_PICK_REQUEST = 0x1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 语音识别
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> {
                        val ok = SpeechRecognizer.isRecognitionAvailable(this)
                        result.success(ok)
                    }
                    "listen" -> {
                        val locale = call.argument<String>("locale") ?: "zh-CN"
                        startListening(locale, result)
                    }
                    else -> result.notImplemented()
                }
            }
        // 文件选择 (v1.5 新增: 数据恢复)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJsonFile" -> pickJsonFile(result)
                    else -> result.notImplemented()
                }
            }
    }

    // ----- 语音识别 -----
    private fun startListening(locale: String, result: MethodChannel.Result) {
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        }
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onError(error: Int) {
                result.error("STT_ERROR", "error code=$error", null)
                speechRecognizer?.destroy()
                speechRecognizer = null
            }
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = matches?.firstOrNull() ?: ""
                result.success(text)
                speechRecognizer?.destroy()
                speechRecognizer = null
            }
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        speechRecognizer?.startListening(intent)
    }

    // ----- 文件选择 (SAF) -----
    private fun pickJsonFile(result: MethodChannel.Result) {
        if (pendingFileResult != null) {
            result.error("BUSY", "已有文件选择请求在进行中", null)
            return
        }
        pendingFileResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            // 限制常见文本/JSON 类型
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "text/*"))
        }
        try {
            startActivityForResult(intent, FILE_PICK_REQUEST)
        } catch (e: Exception) {
            pendingFileResult = null
            result.error("NO_FILE_PICKER", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_PICK_REQUEST) {
            val result = pendingFileResult ?: return
            pendingFileResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                // 把 SAF content:// uri 拷到 app 私有目录, 拿真实文件路径
                try {
                    val path = copyUriToCache(uri)
                    if (path != null) {
                        result.success(path)
                    } else {
                        result.error("COPY_FAILED", "无法读取所选文件", null)
                    }
                } catch (e: Exception) {
                    result.error("COPY_FAILED", e.message, null)
                }
            } else {
                result.success(null) // 用户取消
            }
        }
    }

    /// 把 content:// uri 拷到 cache 目录, 返回真实路径
    /// SAF 的 content:// 不能直接用 File() 读
    private fun copyUriToCache(uri: Uri): String? {
        val input = contentResolver.openInputStream(uri) ?: return null
        val cacheDir = externalCacheDir ?: cacheDir
        val outFile = java.io.File(cacheDir, "import_${System.currentTimeMillis()}.json")
        input.use { ins ->
            outFile.outputStream().use { outs ->
                ins.copyTo(outs)
            }
        }
        return outFile.absolutePath
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        super.onDestroy()
    }
}
