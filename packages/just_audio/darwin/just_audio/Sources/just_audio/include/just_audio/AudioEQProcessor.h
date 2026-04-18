#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Singleton that owns EQ DSP state and attaches MTAudioProcessingTap
/// to AVPlayerItems for real-time audio equalisation on iOS.
@interface AudioEQProcessor : NSObject

@property (class, readonly) AudioEQProcessor *shared;

/// Attach a processing tap to the given player item.
/// Call this after creating each AVPlayerItem (including loop duplicates).
- (void)attachTapToPlayerItem:(AVPlayerItem *)item;

/// Master EQ enable/disable.
- (void)setEnabled:(BOOL)enabled;

/// Set a single band level in millibels (e.g. -1500 to +1500 for +/-15 dB).
/// @param band  Band index 0-4.
/// @param level Level in millibels.
- (void)setBandLevel:(int)level forBand:(int)band;

/// Set bass boost strength (0-1000).
- (void)setBassBoostStrength:(int)strength;

/// Set loudness gain in millibels (added on top of output).
- (void)setLoudnessGain:(int)gainMb;

/// Enable mono downmix.
- (void)setMonoEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
