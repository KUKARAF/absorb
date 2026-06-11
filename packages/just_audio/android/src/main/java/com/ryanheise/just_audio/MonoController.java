package com.ryanheise.just_audio;

/**
 * Static bridge so external code (e.g. MainActivity) can toggle mono
 * without directly importing AudioPlayer (which causes classpath issues).
 */
public class MonoController {
    public interface Callback {
        void setMonoEnabled(boolean enabled);
    }

    private static volatile Callback sCallback;

    public static void register(Callback callback) {
        sCallback = callback;
    }

    public static void setMonoEnabled(boolean enabled) {
        Callback cb = sCallback;
        if (cb != null) cb.setMonoEnabled(enabled);
    }
}
