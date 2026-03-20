package com.barnabas.absorb

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.just_audio.MonoController
import com.ryanheise.just_audio.OutputDeviceController
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val TAG = "AbsorbEQ"
    private val CHANNEL = "com.absorb.equalizer"

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var currentSessionId: Int = 0
    private var selectedOutputDeviceId: Int? = null  // user's manual override
    private var eqLoudnessGainMb: Int = 0  // extra gain from EQ loudness slider

    companion object {
        // Always-on base volume boost (3 dB) to match loudness of other media apps
        private const val BASE_BOOST_MB = 300
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "isBluetoothAudioConnected" -> {
                        result.success(isBluetoothAudioConnected())
                    }
                    "init" -> handleInit(result)
                    "attachSession" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        handleAttachSession(sessionId, result)
                    }
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        handleSetEnabled(enabled, result)
                    }
                    "setBand" -> {
                        val band = call.argument<Int>("band") ?: 0
                        val level = call.argument<Int>("level") ?: 0
                        handleSetBand(band, level, result)
                    }
                    "setBassBoost" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        handleSetBassBoost(strength, result)
                    }
                    "setVirtualizer" -> {
                        val strength = call.argument<Int>("strength") ?: 0
                        handleSetVirtualizer(strength, result)
                    }
                    "setLoudness" -> {
                        val gain = call.argument<Int>("gain") ?: 0
                        handleSetLoudness(gain, result)
                    }
                    "setMono" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        MonoController.setMonoEnabled(enabled)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        Log.d(TAG, "EQ method channel registered")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.absorb.audio_output")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAudioOutputDevices" -> {
                        result.success(getAudioOutputDevices())
                    }
                    "setAudioOutputDevice" -> {
                        val id = call.argument<Int>("id") ?: 0
                        result.success(setAudioOutputDevice(id))
                    }
                    "resetAudioOutput" -> {
                        result.success(resetAudioOutput())
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.absorb.storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceStorage" -> {
                        try {
                            val stat = StatFs(Environment.getDataDirectory().path)
                            result.success(mapOf(
                                "totalBytes" to stat.totalBytes,
                                "availableBytes" to stat.availableBytes
                            ))
                        } catch (e: Exception) {
                            result.error("STORAGE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInit(result: MethodChannel.Result) {
        try {
            val tempEq = Equalizer(0, 0)
            val numBands = tempEq.numberOfBands.toInt()
            val frequencies = mutableListOf<Int>()
            for (i in 0 until numBands) {
                frequencies.add(tempEq.getCenterFreq(i.toShort()) / 1000)
            }
            val bandRange = tempEq.bandLevelRange
            val minLevel = bandRange[0] / 100.0
            val maxLevel = bandRange[1] / 100.0
            tempEq.release()

            Log.d(TAG, "init: $numBands bands, frequencies=$frequencies, range=[$minLevel, $maxLevel]dB")
            result.success(mapOf(
                "bands" to numBands,
                "frequencies" to frequencies,
                "minLevel" to minLevel,
                "maxLevel" to maxLevel
            ))
        } catch (e: Exception) {
            Log.e(TAG, "init failed: ${e.message}")
            result.error("EQ_INIT_ERROR", e.message, null)
        }
    }

    private fun handleAttachSession(sessionId: Int, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "attachSession: $sessionId (previous: $currentSessionId)")
            if (sessionId != currentSessionId) {
                releaseEffects()
            }
            currentSessionId = sessionId

            if (sessionId == 0) {
                result.success(true)
                return
            }

            equalizer = Equalizer(0, sessionId).apply { enabled = false }
            bassBoost = try {
                BassBoost(0, sessionId).apply { enabled = false }
            } catch (e: Exception) {
                Log.w(TAG, "BassBoost not supported: ${e.message}"); null
            }
            virtualizer = try {
                Virtualizer(0, sessionId).apply { enabled = false }
            } catch (e: Exception) {
                Log.w(TAG, "Virtualizer not supported: ${e.message}"); null
            }
            loudnessEnhancer = try {
                LoudnessEnhancer(sessionId).apply {
                    setTargetGain(BASE_BOOST_MB + eqLoudnessGainMb)
                    enabled = true
                }
            } catch (e: Exception) {
                Log.w(TAG, "LoudnessEnhancer not supported: ${e.message}"); null
            }

            Log.d(TAG, "Effects attached to session $sessionId")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "attachSession failed: ${e.message}")
            result.error("EQ_ATTACH_ERROR", e.message, null)
        }
    }

    private fun handleSetEnabled(enabled: Boolean, result: MethodChannel.Result) {
        try {
            equalizer?.enabled = enabled
            bassBoost?.enabled = enabled
            virtualizer?.enabled = enabled
            // LoudnessEnhancer is always on (base boost); only EQ loudness gain changes
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
    }

    private fun handleSetBand(band: Int, level: Int, result: MethodChannel.Result) {
        try {
            equalizer?.setBandLevel(band.toShort(), level.toShort())
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
    }

    private fun handleSetBassBoost(strength: Int, result: MethodChannel.Result) {
        try {
            bassBoost?.setStrength(strength.toShort().coerceIn(0, 1000))
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
    }

    private fun handleSetVirtualizer(strength: Int, result: MethodChannel.Result) {
        try {
            virtualizer?.setStrength(strength.toShort().coerceIn(0, 1000))
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
    }

    private fun handleSetLoudness(gain: Int, result: MethodChannel.Result) {
        try {
            eqLoudnessGainMb = gain
            loudnessEnhancer?.setTargetGain(BASE_BOOST_MB + gain)
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
    }

    private fun getAudioOutputDevices(): List<Map<String, Any>> {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .filter { isMediaOutputDevice(it.type) }

        // If user has manually selected a device, use that; otherwise fall back to priority
        val manualId = selectedOutputDeviceId
        val hasManualSelection = manualId != null && devices.any { it.id == manualId }

        // Determine active output by priority: wired > BT A2DP > USB > speaker
        val activeTypes: Set<Int> = when {
            devices.any { it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET } ->
                setOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET)
            devices.any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP } ->
                setOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
            devices.any { it.type == AudioDeviceInfo.TYPE_USB_DEVICE || it.type == AudioDeviceInfo.TYPE_USB_HEADSET } ->
                setOf(AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET)
            else -> setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        }

        // Deduplicate: prefer A2DP over SCO for same product name
        val seen = mutableSetOf<String>()
        return devices
            .sortedBy { if (it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) 0 else 1 }
            .filter { device ->
                val key = device.productName?.toString()?.takeIf { it.isNotBlank() } ?: device.id.toString()
                seen.add(key)
            }
            .map { device ->
                val typeName = getOutputTypeName(device.type)
                val name = device.productName?.toString()?.takeIf { it.isNotBlank() }
                    ?: getOutputTypeLabel(device.type)
                val isActive = if (hasManualSelection) device.id == manualId
                               else device.type in activeTypes
                mapOf(
                    "id" to device.id,
                    "name" to name,
                    "typeName" to typeName,
                    "isActive" to isActive
                )
            }
    }

    private fun isMediaOutputDevice(type: Int): Boolean {
        return type in listOf(
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
    }

    private fun getOutputTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
            else -> "unknown"
        }
    }

    private fun getOutputTypeLabel(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "This Phone"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Audio"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
            else -> "Audio Device"
        }
    }

    private fun setAudioOutputDevice(deviceId: Int): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            val target = devices.firstOrNull { it.id == deviceId }
            OutputDeviceController.setPreferredOutputDevice(target)
            selectedOutputDeviceId = deviceId
            return true
        }
        return false
    }

    private fun resetAudioOutput(): Boolean {
        OutputDeviceController.setPreferredOutputDevice(null)
        selectedOutputDeviceId = null
        return true
    }

    private fun releaseEffects() {
        try { equalizer?.release() } catch (_: Exception) {}
        try { bassBoost?.release() } catch (_: Exception) {}
        try { virtualizer?.release() } catch (_: Exception) {}
        try { loudnessEnhancer?.release() } catch (_: Exception) {}
        equalizer = null
        bassBoost = null
        virtualizer = null
        loudnessEnhancer = null
        eqLoudnessGainMb = 0
    }

    private fun isBluetoothAudioConnected(): Boolean {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            return devices.any {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
        }
        @Suppress("DEPRECATION")
        return am.isBluetoothA2dpOn || am.isBluetoothScoOn
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }

}
