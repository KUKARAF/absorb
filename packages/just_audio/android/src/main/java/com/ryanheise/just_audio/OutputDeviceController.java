package com.ryanheise.just_audio;

import android.media.AudioDeviceInfo;

/**
 * Static bridge so external code (e.g. MainActivity) can set the preferred
 * audio output device without directly importing AudioPlayer (which causes
 * classpath issues with media3 types).
 */
public class OutputDeviceController {
    public interface Callback {
        void setPreferredAudioDevice(AudioDeviceInfo device);
    }

    private static volatile Callback sCallback;

    public static void register(Callback callback) {
        sCallback = callback;
    }

    public static void setPreferredOutputDevice(AudioDeviceInfo device) {
        Callback cb = sCallback;
        if (cb != null) cb.setPreferredAudioDevice(device);
    }
}
