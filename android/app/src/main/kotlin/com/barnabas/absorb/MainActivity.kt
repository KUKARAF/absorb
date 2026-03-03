package com.barnabas.absorb

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    else -> result.notImplemented()
                }
            }
        Log.d(TAG, "EQ method channel registered")

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

            equalizer = Equalizer(0, sessionId).apply { enabled = true }
            bassBoost = try {
                BassBoost(0, sessionId).apply { enabled = true }
            } catch (e: Exception) {
                Log.w(TAG, "BassBoost not supported: ${e.message}"); null
            }
            virtualizer = try {
                Virtualizer(0, sessionId).apply { enabled = true }
            } catch (e: Exception) {
                Log.w(TAG, "Virtualizer not supported: ${e.message}"); null
            }
            loudnessEnhancer = try {
                LoudnessEnhancer(sessionId).apply { enabled = true }
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
            loudnessEnhancer?.enabled = enabled
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
            loudnessEnhancer?.setTargetGain(gain)
            result.success(true)
        } catch (e: Exception) {
            result.error("EQ_ERROR", e.message, null)
        }
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
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
