import 'dart:async';

import 'package:flutter/services.dart';

/// Communicates the current state of the audio player.
enum AudioPlayerState {
  /// Player is stopped. No file is loaded to the player. Calling [resume] or
  /// [pause] will result in exception.
  STOPPED,

  /// Currently playing a file. The user can [pause], [resume] or [stop] the
  /// playback.
  PLAYING,

  /// Paused. The user can [resume] the playback without providing the URL.
  PAUSED,

  /// The playback has been completed. This state is the same as [STOPPED],
  /// however we differentiate it because some clients might want to know when
  /// the playback is done versus when the user has stopped the playback.
  COMPLETED,
}

class EqualizerPreset {
  int index;
  String name;

  EqualizerPreset.fromMap(Map<dynamic, dynamic> map) {
    this.index = map['index'];
    this.name = map['name'];
  }
}

class EqualizerBand {
  int index;
  int centerFrequency;
  int lowerFrequency;
  int upperFrequency;

  EqualizerBand.fromMap(Map<dynamic, dynamic> map) {
    this.index = map['index'];
    this.centerFrequency = map['centerFrequency'];
    this.lowerFrequency = map['lowerFrequency'];
    this.upperFrequency = map['upperFrequency'];
  }
}

class EqualizerConfig {
  int numOfPresets;
  int minEQLevel;
  int maxEQLevel;
  List<EqualizerPreset> presets;
  List<EqualizerBand> bands;

  EqualizerConfig.fromMap(Map<String, dynamic> map) {
    this.numOfPresets = map['numOfPresets'];
    this.minEQLevel = map['minEQLevel'];
    this.maxEQLevel = map['maxEQLevel'];
    this.presets = map['presets'].map<EqualizerPreset>((rawPreset) {
      return EqualizerPreset.fromMap(rawPreset);
    }).toList();
    this.bands = map['bands'].map<EqualizerBand>((rawBand) {
      return EqualizerBand.fromMap(rawBand);
    }).toList();
  }
}

const MethodChannel _channel = const MethodChannel('bz.rxla.flutter/audio');

/// A plugin for controlling the on device audio player.
///
/// Due to the async nature of the native APIs, this plugin delegates all control
/// methods to native without informing the caller of the state changes that happen
/// as a result of these calls. The state changes are communicated via the
/// [onPlayerStateChanged] stream instead so clients are expected to subscribe
/// to this.
class AudioPlayer {
  final StreamController<AudioPlayerState> _playerStateController =
      new StreamController.broadcast();

  final StreamController<Duration> _positionController =
      new StreamController.broadcast();

  AudioPlayerState _state = AudioPlayerState.STOPPED;
  Duration _duration = const Duration();

  AudioPlayer() {
    _channel.setMethodCallHandler(_audioPlayerStateChange);
  }

  /// Play a given url.
  Future<void> play(String url, {bool isLocal: false}) async =>
      await _channel.invokeMethod('play', {'url': url, 'isLocal': isLocal});

  /// Pause the currently playing stream.
  Future<void> pause() async => await _channel.invokeMethod('pause');

  /// Stop the currently playing stream.
  Future<void> stop() async => await _channel.invokeMethod('stop');

  /// Mute sound.
  Future<void> mute(bool muted) async =>
      await _channel.invokeMethod('mute', muted);

  /// Seek to a specific position in the audio stream.
  Future<void> seek(double seconds) async =>
      await _channel.invokeMethod('seek', seconds);

  /// Stream for subscribing to player state change events.
  Stream<AudioPlayerState> get onPlayerStateChanged =>
      _playerStateController.stream;

  /// Reports what the player is currently doing.
  AudioPlayerState get state => _state;

  /// Reports the duration of the current media being played. It might return
  /// 0 if we have not determined the length of the media yet. It is best to
  /// call this from a state listener when the state has become
  /// [AudioPlayerState.PLAYING].
  Duration get duration => _duration;

  /// Stream for subscribing to audio position change events. Roughly fires
  /// every 200 milliseconds. Will continously update the position of the
  /// playback if the status is [AudioPlayerState.PLAYING].
  Stream<Duration> get onAudioPositionChanged => _positionController.stream;

  Future<EqualizerConfig> getEqualizerConfig() async {
    var methodResponse = await _channel.invokeMethod('getEqualizerConfig');

    return EqualizerConfig.fromMap(Map<String, dynamic>.from(methodResponse));
  }

  Future<void> _audioPlayerStateChange(MethodCall call) async {
    switch (call.method) {
      case "audio.onCurrentPosition":
        assert(_state == AudioPlayerState.PLAYING);
        _positionController.add(new Duration(milliseconds: call.arguments));
        break;
      case "audio.onStart":
        _state = AudioPlayerState.PLAYING;
        _playerStateController.add(AudioPlayerState.PLAYING);
        _duration = new Duration(milliseconds: call.arguments);
        break;
      case "audio.onPause":
        _state = AudioPlayerState.PAUSED;
        _playerStateController.add(AudioPlayerState.PAUSED);
        break;
      case "audio.onStop":
        _state = AudioPlayerState.STOPPED;
        _playerStateController.add(AudioPlayerState.STOPPED);
        break;
      case "audio.onComplete":
        _state = AudioPlayerState.COMPLETED;
        _playerStateController.add(AudioPlayerState.COMPLETED);
        break;
      case "audio.onError":
        // If there's an error, we assume the player has stopped.
        _state = AudioPlayerState.STOPPED;
        _playerStateController.addError(call.arguments);
        // TODO: Handle error arguments here. It is not useful to pass this
        // to the client since each platform creates different error string
        // formats so we can't expect client to parse these.
        break;
      default:
        throw new ArgumentError('Unknown method ${call.method} ');
    }
  }
}
