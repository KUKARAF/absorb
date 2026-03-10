import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'scoped_prefs.dart';

/// Android AudioEffect equalizer bands and presets via platform channels.
/// Falls back gracefully on unsupported devices.
class EqualizerService extends ChangeNotifier {
  static final EqualizerService _instance = EqualizerService._();
  factory EqualizerService() => _instance;
  EqualizerService._();

  static const _channel = MethodChannel('com.absorb.equalizer');

  // ── State ──
  bool _available = false;
  bool _enabled = false;
  String _activePreset = 'flat';
  List<double> _bandLevels = []; // dB values per band
  List<int> _bandFrequencies = []; // center frequencies (Hz)
  double _minLevel = -15.0;
  double _maxLevel = 15.0;
  double _bassBoost = 0.0; // 0.0–1.0
  double _virtualizer = 0.0; // 0.0–1.0
  double _loudnessGain = 0.0; // 0.0–1.0
  bool _mono = false;

  // Built-in presets (EQ curve shapes)
  static const Map<String, List<double>> presets = {
    'flat': [0, 0, 0, 0, 0],
    'voice boost': [2, 4, 5, 3, 1],
    'bass boost': [5, 3, 0, -1, -2],
    'treble boost': [-2, -1, 0, 3, 5],
    'podcast': [3, 5, 4, 2, 0],
    'audiobook': [1, 3, 5, 4, 2],
    'reduce noise': [-3, -1, 0, -1, -3],
    'loudness': [4, 2, 0, 2, 4],
  };

  // Getters
  bool get available => _available;
  bool get enabled => _enabled;
  String get activePreset => _activePreset;
  List<double> get bandLevels => List.unmodifiable(_bandLevels);
  List<int> get bandFrequencies => List.unmodifiable(_bandFrequencies);
  double get minLevel => _minLevel;
  double get maxLevel => _maxLevel;
  double get bassBoost => _bassBoost;
  double get virtualizer => _virtualizer;
  double get loudnessGain => _loudnessGain;
  bool get mono => _mono;

  /// Initialize — try to connect to platform EQ, fall back to software presets.
  Future<void> init() async {
    await _loadSettings();

    try {
      final result = await _channel.invokeMethod('init');
      if (result is Map) {
        _available = true;
        _bandFrequencies = List<int>.from(result['frequencies'] ?? []);
        _minLevel = (result['minLevel'] as num?)?.toDouble() ?? -15.0;
        _maxLevel = (result['maxLevel'] as num?)?.toDouble() ?? 15.0;
        final numBands = _bandFrequencies.length;
        if (_bandLevels.length != numBands) {
          _bandLevels = List.filled(numBands, 0.0);
        }
        debugPrint('[EQ] Platform EQ available: ${_bandFrequencies.length} bands');
        if (_enabled) _applyCurrentSettings();
      }
    } on MissingPluginException {
      debugPrint('[EQ] Platform channel not available — using software presets');
      _setupSoftwareFallback();
    } on PlatformException catch (e) {
      debugPrint('[EQ] Platform EQ error: $e — using software presets');
      _setupSoftwareFallback();
    } catch (e) {
      debugPrint('[EQ] Unexpected error: $e — using software presets');
      _setupSoftwareFallback();
    }
    notifyListeners();
  }

  void _setupSoftwareFallback() {
    _available = true; // We still expose the UI, just software-side
    _bandFrequencies = [60, 230, 910, 3600, 14000];
    _minLevel = -15.0;
    _maxLevel = 15.0;
    if (_bandLevels.length != 5) {
      _bandLevels = List.filled(5, 0.0);
    }
  }

  /// Toggle EQ on/off.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (_enabled) {
      _applyCurrentSettings();
    } else {
      _resetPlatform();
    }
    await _saveSettings();
    notifyListeners();
  }

  /// Apply a named preset.
  Future<void> applyPreset(String name) async {
    final curve = presets[name];
    if (curve == null) return;

    _activePreset = name;

    // Scale preset values to our band count and level range
    final numBands = _bandLevels.length;
    for (int i = 0; i < numBands; i++) {
      final presetIdx = (i * curve.length / numBands).floor().clamp(0, curve.length - 1);
      _bandLevels[i] = curve[presetIdx].clamp(_minLevel, _maxLevel);
    }

    if (_enabled) _applyCurrentSettings();
    await _saveSettings();
    notifyListeners();
  }

  /// Set a single band level.
  Future<void> setBandLevel(int bandIndex, double level) async {
    if (bandIndex < 0 || bandIndex >= _bandLevels.length) return;
    _bandLevels[bandIndex] = level.clamp(_minLevel, _maxLevel);
    _activePreset = 'custom';
    if (_enabled) _applyBand(bandIndex, _bandLevels[bandIndex]);
    await _saveSettings();
    notifyListeners();
  }

  /// Set bass boost (0.0–1.0).
  Future<void> setBassBoost(double value) async {
    _bassBoost = value.clamp(0.0, 1.0);
    if (_enabled) {
      try {
        await _channel.invokeMethod('setBassBoost', {'strength': (_bassBoost * 1000).round()});
      } catch (_) {}
    }
    await _saveSettings();
    notifyListeners();
  }

  /// Set virtualizer / surround (0.0–1.0).
  Future<void> setVirtualizer(double value) async {
    _virtualizer = value.clamp(0.0, 1.0);
    if (_enabled) {
      try {
        await _channel.invokeMethod('setVirtualizer', {'strength': (_virtualizer * 1000).round()});
      } catch (_) {}
    }
    await _saveSettings();
    notifyListeners();
  }

  /// Toggle mono audio mixing.
  Future<void> setMono(bool value) async {
    _mono = value;
    try {
      await _channel.invokeMethod('setMono', {'enabled': _mono});
    } catch (_) {}
    await _saveSettings();
    notifyListeners();
  }

  /// Set loudness enhancer gain (0.0–1.0).
  Future<void> setLoudnessGain(double value) async {
    _loudnessGain = value.clamp(0.0, 1.0);
    if (_enabled) {
      try {
        await _channel.invokeMethod('setLoudness', {'gain': (_loudnessGain * 1500).round()});
      } catch (_) {}
    }
    await _saveSettings();
    notifyListeners();
  }

  /// Reset everything to flat/off.
  Future<void> resetAll() async {
    _activePreset = 'flat';
    _bandLevels = List.filled(_bandLevels.length, 0.0);
    _bassBoost = 0.0;
    _virtualizer = 0.0;
    _loudnessGain = 0.0;
    _mono = false;
    if (_enabled) {
      _applyCurrentSettings();
    }
    await _saveSettings();
    notifyListeners();
  }

  /// Attach effects to an ExoPlayer audio session.
  /// Call this whenever the audio session ID changes (new playback).
  Future<void> attachToSession(int sessionId) async {
    if (sessionId <= 0) return;
    try {
      await _channel.invokeMethod('attachSession', {'sessionId': sessionId});
      debugPrint('[EQ] Attached to audio session $sessionId');
      if (_enabled) _applyCurrentSettings();
    } catch (e) {
      debugPrint('[EQ] attachSession failed: $e');
    }
  }

  // ── Platform communication ──

  Future<void> _applyCurrentSettings() async {
    for (int i = 0; i < _bandLevels.length; i++) {
      _applyBand(i, _bandLevels[i]);
    }
    try {
      await _channel.invokeMethod('setBassBoost', {'strength': (_bassBoost * 1000).round()});
      await _channel.invokeMethod('setVirtualizer', {'strength': (_virtualizer * 1000).round()});
      await _channel.invokeMethod('setLoudness', {'gain': (_loudnessGain * 1500).round()});
      await _channel.invokeMethod('setEnabled', {'enabled': _enabled});
      await _channel.invokeMethod('setMono', {'enabled': _mono});
    } catch (_) {}
  }

  Future<void> _applyBand(int index, double level) async {
    try {
      await _channel.invokeMethod('setBand', {
        'band': index,
        'level': (level * 100).round(), // millibels
      });
    } catch (_) {}
  }

  Future<void> _resetPlatform() async {
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': false});
      await _channel.invokeMethod('setMono', {'enabled': _mono});
    } catch (_) {}
  }

  // ── Persistence ──

  Future<void> _loadSettings() async {
    _enabled = await ScopedPrefs.getBool('eq_enabled') ?? false;
    _activePreset = await ScopedPrefs.getString('eq_preset') ?? 'flat';
    _bassBoost = await ScopedPrefs.getDouble('eq_bassBoost') ?? 0.0;
    _virtualizer = await ScopedPrefs.getDouble('eq_virtualizer') ?? 0.0;
    _loudnessGain = await ScopedPrefs.getDouble('eq_loudnessGain') ?? 0.0;
    _mono = await ScopedPrefs.getBool('eq_mono') ?? false;

    final bandStr = await ScopedPrefs.getString('eq_bands');
    if (bandStr != null) {
      _bandLevels = bandStr.split(',')
          .map((s) => double.tryParse(s) ?? 0.0)
          .toList();
    }
  }

  Future<void> _saveSettings() async {
    await ScopedPrefs.setBool('eq_enabled', _enabled);
    await ScopedPrefs.setString('eq_preset', _activePreset);
    await ScopedPrefs.setDouble('eq_bassBoost', _bassBoost);
    await ScopedPrefs.setDouble('eq_virtualizer', _virtualizer);
    await ScopedPrefs.setDouble('eq_loudnessGain', _loudnessGain);
    await ScopedPrefs.setBool('eq_mono', _mono);
    await ScopedPrefs.setString('eq_bands', _bandLevels.map((l) => l.toStringAsFixed(1)).join(','));
  }

  /// Formatted frequency label.
  String freqLabel(int hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k';
    return '${hz}Hz';
  }
}
