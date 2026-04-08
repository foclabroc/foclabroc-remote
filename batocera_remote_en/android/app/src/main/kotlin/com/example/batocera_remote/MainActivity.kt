package com.example.batocera_remote

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.foclabroc.batocera_remote/audio"
        private const val SAMPLE_RATE = 44100
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playCorrect"  -> { playAsync { correctSound() };  result.success(null) }
                "playWrong"    -> { playAsync { wrongSound() };    result.success(null) }
                "playTimeout"  -> { playAsync { timeoutSound() };  result.success(null) }
                "playWin"      -> { playAsync { winSound() };      result.success(null) }
                "playLose"     -> { playAsync { loseSound() };     result.success(null) }
                "playTick"     -> { playAsync { tickSound() };     result.success(null) }
                else           -> result.notImplemented()
            }
        }
    }

    // ── Lecture asynchrone (ne bloque pas le thread UI) ──────────────────────

    private fun playAsync(generator: () -> ShortArray) {
        Thread {
            try {
                val samples = generator()
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(samples.size * 2)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                track.write(samples, 0, samples.size)
                track.play()
                // Attend la fin de lecture puis libère
                val durationMs = (samples.size.toLong() * 1000L / SAMPLE_RATE)
                Thread.sleep(durationMs + 50)
                track.stop()
                track.release()
            } catch (_: Exception) {}
        }.start()
    }

    // ── Générateur de forme d'onde ────────────────────────────────────────────

    private fun sine(freq: Double, durationMs: Int, amplitude: Double = 0.6): ShortArray {
        val n = (SAMPLE_RATE * durationMs / 1000.0).toInt()
        return ShortArray(n) { i ->
            val t = i.toDouble() / SAMPLE_RATE
            // Enveloppe ADSR simple : attaque 5ms, release 20ms
            val attackSamples  = (SAMPLE_RATE * 0.005).toInt()
            val releaseSamples = (SAMPLE_RATE * 0.020).toInt()
            val env = when {
                i < attackSamples  -> i.toDouble() / attackSamples
                i > n - releaseSamples -> (n - i).toDouble() / releaseSamples
                else -> 1.0
            }
            (sin(2.0 * PI * freq * t) * amplitude * env * Short.MAX_VALUE).toInt().toShort()
        }
    }

    private fun concat(vararg arrays: ShortArray): ShortArray {
        val total = arrays.sumOf { it.size }
        val result = ShortArray(total)
        var offset = 0
        for (arr in arrays) { arr.copyInto(result, offset); offset += arr.size }
        return result
    }

    private fun silence(ms: Int) = ShortArray((SAMPLE_RATE * ms / 1000.0).toInt())

    // ── Sons ──────────────────────────────────────────────────────────────────

    // ✅ Bonne réponse : deux notes montantes rapides (do-mi)
    private fun correctSound(): ShortArray = concat(
        sine(523.25, 80, 0.55),   // C5
        silence(20),
        sine(659.25, 120, 0.55),  // E5
    )

    // ❌ Mauvaise réponse : note grave descendante (buzz)
    private fun wrongSound(): ShortArray {
        val n = (SAMPLE_RATE * 0.25).toInt()
        return ShortArray(n) { i ->
            val t = i.toDouble() / SAMPLE_RATE
            // Descend de 220Hz à 100Hz avec légère distorsion
            val freq = 220.0 - 480.0 * (i.toDouble() / n)
            val env = (n - i).toDouble() / n
            val raw = sin(2.0 * PI * freq * t)
            // Soft clip pour l'effet "buzz"
            val clipped = if (raw > 0.6) 0.6 + (raw - 0.6) * 0.3 else if (raw < -0.6) -0.6 + (raw + 0.6) * 0.3 else raw
            (clipped * 0.65 * env * Short.MAX_VALUE).toInt().toShort()
        }
    }

    // ⏱ Timeout : note courte grave
    private fun timeoutSound(): ShortArray = concat(
        sine(311.13, 60, 0.4),  // Eb4
        silence(30),
        sine(261.63, 150, 0.35), // C4
    )

    // 🏆 Victoire (score élevé) : fanfare montante
    private fun winSound(): ShortArray = concat(
        sine(523.25, 100, 0.5),  // C5
        silence(15),
        sine(659.25, 100, 0.5),  // E5
        silence(15),
        sine(783.99, 100, 0.5),  // G5
        silence(15),
        sine(1046.5, 220, 0.55), // C6
    )

    // 💀 Défaite (score faible) : descente triste
    private fun loseSound(): ShortArray = concat(
        sine(392.00, 120, 0.45), // G4
        silence(20),
        sine(349.23, 120, 0.45), // F4
        silence(20),
        sine(311.13, 120, 0.45), // Eb4
        silence(20),
        sine(261.63, 250, 0.40), // C4
    )

    // ⚡ Tick timer (dernières secondes) : bip sec et court
    private fun tickSound(): ShortArray = sine(880.0, 40, 0.3) // A5 court
}
