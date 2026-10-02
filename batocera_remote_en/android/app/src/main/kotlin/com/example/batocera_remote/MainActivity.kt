package com.example.batocera_remote

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.foclabroc.batocera_remote/audio"
        private const val SAMPLE_RATE = 44100
    }

    // ── Effets des mini-jeux (SoundPool : faible latence, plusieurs à la fois) ──
    private var soundPool: SoundPool? = null
    private val sfxIds = HashMap<String, Int>()

    // ── Musique de fond (assets/game/game_music.ogg, en boucle) ────────────────
    private var musicPlayer: MediaPlayer? = null
    private var musicReady = false
    private var musicIndex = -1
    private var musicWanted = false   // la musique doit jouer (hors app en pause)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initSfx()

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
                "sfx"          -> { playSfx(call.argument<String>("name") ?: ""); result.success(null) }
                "musicStart"   -> { musicStart(call.argument<Int>("track") ?: 0); result.success(null) }
                "musicStop"    -> { musicStop(); result.success(null) }
                "musicPause"   -> { musicWanted = false; pauseTrack(); result.success(null) }
                "musicResume"  -> { musicWanted = musicPlayer != null; resumeTrack(); result.success(null) }
                else           -> result.notImplemented()
            }
        }
    }

    // L'app passe en arrière-plan : on coupe la musique, puis on la reprend
    override fun onPause() {
        super.onPause()
        pauseTrack()
    }

    override fun onResume() {
        super.onResume()
        if (musicWanted) resumeTrack()
    }

    override fun onDestroy() {
        musicStop()
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }

    // ── Effets sonores ────────────────────────────────────────────────────────

    /** Génère les effets en WAV dans le cache puis les charge dans un SoundPool. */
    private fun initSfx() {
        if (soundPool != null) return
        val pool = SoundPool.Builder()
            .setMaxStreams(8)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
        soundPool = pool
        Thread {
            try {
                for ((name, samples) in ChipSynth.allSfx()) {
                    val f = File(cacheDir, "sfx_$name.wav")
                    writeWav(f, samples, ChipSynth.SFX_RATE)
                    sfxIds[name] = pool.load(f.absolutePath, 1)
                }
            } catch (_: Exception) {}
        }.start()
    }

    private fun playSfx(name: String) {
        val id = sfxIds[name] ?: return
        soundPool?.play(id, 1f, 1f, 1, 0, 1f)
    }

    private fun writeWav(file: File, samples: ShortArray, rate: Int) {
        val dataLen = samples.size * 2
        val buf = ByteBuffer.allocate(44 + dataLen).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray()); buf.putInt(36 + dataLen); buf.put("WAVE".toByteArray())
        buf.put("fmt ".toByteArray()); buf.putInt(16); buf.putShort(1); buf.putShort(1)
        buf.putInt(rate); buf.putInt(rate * 2); buf.putShort(2); buf.putShort(16)
        buf.put("data".toByteArray()); buf.putInt(dataLen)
        for (s in samples) buf.putShort(s)
        FileOutputStream(file).use { it.write(buf.array()) }
    }

    // ── Musique ───────────────────────────────────────────────────────────────

    // Morceaux disponibles (index envoyé par Dart)
    private val musicFiles = listOf(
        "assets/game/game_music.ogg",    // 0 : Disco Funk
        "assets/game/game_music_2.ogg",  // 1 : Shop
        "assets/game/game_music_3.ogg",  // 2 : Good Morning
        "assets/game/game_music_4.ogg",  // 3 : 8-bit Retro
        "assets/game/game_music_5.ogg",  // 4 : Mountain
        "assets/game/game_music_6.ogg",  // 5 : Video Game
        "assets/game/game_music_7.ogg",  // 6 : Pixel Fight
    )

    /** Lance le morceau [index] en boucle (reprend s'il est déjà chargé). */
    private fun musicStart(index: Int) {
        val i = index.coerceIn(0, musicFiles.size - 1)
        if (musicPlayer != null && musicIndex == i) {
            musicWanted = true
            resumeTrack()
            return
        }
        musicStop()
        musicWanted = true
        musicIndex = i
        try {
            val key = FlutterInjector.instance().flutterLoader()
                .getLookupKeyForAsset(musicFiles[i])
            val afd = assets.openFd(key)
            val p = MediaPlayer()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            p.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            p.isLooping = true
            p.setVolume(0.6f, 0.6f)
            p.setOnPreparedListener {
                musicReady = true
                if (musicWanted && musicPlayer === it && !isFinishing) it.start()
            }
            musicReady = false
            musicPlayer = p
            p.prepareAsync()
        } catch (_: Exception) {
            musicStop()
        }
    }

    private fun musicStop() {
        musicWanted = false
        musicReady = false
        musicIndex = -1
        musicPlayer?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        musicPlayer = null
    }

    private fun pauseTrack() {
        try { if (musicReady && musicPlayer?.isPlaying == true) musicPlayer?.pause() } catch (_: Exception) {}
    }

    private fun resumeTrack() {
        try { if (musicReady && musicPlayer?.isPlaying == false) musicPlayer?.start() } catch (_: Exception) {}
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

// ═══════════════════════════════════════════════════════════════════════════════
// Synthé « chiptune » : effets des mini-jeux (générés, aucun fichier audio).
// ═══════════════════════════════════════════════════════════════════════════════
object ChipSynth {
    const val SFX_RATE = 22050

    private const val SINE = 0
    private const val SQUARE = 1
    private const val TRIANGLE = 2
    private const val NOISE = 3

    private fun midi(n: Int): Double = 440.0 * 2.0.pow((n - 69) / 12.0)

    /**
     * Note avec glissando de [f0] à [f1] Hz, enveloppe attaque courte puis
     * décroissance. [duty] = rapport cyclique du carré (0.125 / 0.25 / 0.5).
     */
    private fun tone(
        f0: Double, f1: Double, ms: Int, amp: Double, wave: Int,
        duty: Double = 0.5, decay: Double = 3.0, vibrato: Double = 0.0, rate: Int = SFX_RATE,
    ): FloatArray {
        val n = (rate * ms / 1000.0).toInt()
        val out = FloatArray(n)
        val attack = max(1, (rate * 0.003).toInt())
        var phase = 0.0
        var noise = 0f
        var seed = 12345
        for (i in 0 until n) {
            val p = i.toDouble() / n
            var f = f0 + (f1 - f0) * p
            if (vibrato > 0) f *= 1.0 + 0.04 * sin(2 * PI * vibrato * i / rate)
            phase += f / rate
            val ph = phase - floor(phase)
            val v = when (wave) {
                SQUARE -> if (ph < duty) 1.0 else -1.0
                TRIANGLE -> 4.0 * abs(ph - 0.5) - 1.0
                NOISE -> {
                    // bruit « échantillonné » à la fréquence f (grain rétro)
                    if (ph < f / rate) {
                        seed = seed * 1103515245 + 12345
                        noise = ((seed shr 16) and 0x7FFF) / 16384f - 1f
                    }
                    noise.toDouble()
                }
                else -> sin(2 * PI * ph)
            }
            val env = (if (i < attack) i.toDouble() / attack else 1.0) * exp(-decay * p) * (1.0 - p * p * p)
            out[i] = (v * amp * env).toFloat()
        }
        return out
    }

    private fun seq(vararg parts: FloatArray): FloatArray {
        val out = FloatArray(parts.sumOf { it.size })
        var o = 0
        for (p in parts) { p.copyInto(out, o); o += p.size }
        return out
    }

    private fun mix(a: FloatArray, b: FloatArray): FloatArray {
        val out = FloatArray(max(a.size, b.size))
        for (i in out.indices) out[i] = (if (i < a.size) a[i] else 0f) + (if (i < b.size) b[i] else 0f)
        return out
    }

    private fun gap(ms: Int) = FloatArray((SFX_RATE * ms / 1000.0).toInt())

    private fun pcm(x: FloatArray): ShortArray =
        ShortArray(x.size) { i -> (x[i].coerceIn(-1f, 1f) * Short.MAX_VALUE).toInt().toShort() }

    private fun arp(notes: IntArray, ms: Int, amp: Double, wave: Int, duty: Double = 0.25): FloatArray =
        seq(*notes.map { tone(midi(it), midi(it), ms, amp, wave, duty, decay = 1.5) }.toTypedArray())

    /** Tous les effets, par nom (appelés depuis Dart via QuizAudio.sfx). */
    fun allSfx(): Map<String, ShortArray> = mapOf(
        // Saut normal : petit « bip » montant, discret (très fréquent)
        "jump" to pcm(tone(330.0, 660.0, 90, 0.22, SQUARE, 0.25, decay = 4.0)),
        // Ressort : « boing » avec vibrato
        "spring" to pcm(tone(180.0, 820.0, 300, 0.35, TRIANGLE, decay = 2.0, vibrato = 28.0)),
        // Pièce : deux notes aiguës
        "coin" to pcm(seq(tone(midi(83), midi(83), 55, 0.25, SQUARE, 0.5, decay = 0.5),
                          tone(midi(88), midi(88), 170, 0.25, SQUARE, 0.5, decay = 3.0))),
        // Bug écrasé : « splotch » descendant + bruit
        "stomp" to pcm(mix(tone(700.0, 140.0, 130, 0.30, SQUARE, 0.5, decay = 3.0),
                           tone(3000.0, 800.0, 90, 0.18, NOISE, decay = 5.0))),
        // Turbo : arpège très rapide qui monte
        "powerup" to pcm(arp(intArrayOf(60, 64, 67, 72, 76, 79, 84, 88), 45, 0.25, SQUARE)),
        // Bouclier ramassé : scintillement
        "shield" to pcm(seq(tone(500.0, 1400.0, 160, 0.28, TRIANGLE, decay = 1.5),
                            tone(midi(88), midi(88), 120, 0.2, TRIANGLE, decay = 3.0))),
        // Bouclier qui encaisse un coup
        "hurt" to pcm(mix(tone(400.0, 120.0, 220, 0.30, SQUARE, 0.125, decay = 2.5),
                          tone(2000.0, 300.0, 160, 0.20, NOISE, decay = 4.0))),
        // Cartouche fissurée qui se casse : craquement
        "break" to pcm(mix(tone(1800.0, 400.0, 160, 0.30, NOISE, decay = 4.0),
                           tone(220.0, 90.0, 120, 0.18, SQUARE, 0.5, decay = 4.0))),
        // Logo de console : petite mélodie brillante
        "logo" to pcm(arp(intArrayOf(79, 84, 88, 91), 70, 0.22, TRIANGLE)),
        // Nouveau décor : mini fanfare
        "tier" to pcm(seq(arp(intArrayOf(67, 72, 76), 90, 0.22, SQUARE, 0.5),
                          tone(midi(79), midi(79), 260, 0.24, SQUARE, 0.5, decay = 2.0))),
        // Continue : relance montante
        "continue" to pcm(seq(arp(intArrayOf(60, 67, 72, 76, 79), 70, 0.24, SQUARE, 0.5),
                              gap(20), tone(midi(84), midi(84), 260, 0.24, SQUARE, 0.5, decay = 2.0))),
    )

}
