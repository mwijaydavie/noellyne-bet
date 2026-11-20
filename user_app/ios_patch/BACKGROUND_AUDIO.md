# iOS background audio (media_kit path)

The Android player is native Media3 with `PlaybackAudioService`; iOS uses
`media_kit` inside `lib/screens/ios_player_page.dart`, so it needs the standard
iOS audio-session setup instead.

## 1. `ios/Runner/Info.plist`

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## 2. `ios/Runner/AppDelegate.swift`

```swift
import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      // Playback category keeps the live commentary running when the screen
      // locks or the app is backgrounded (the 🎧 audio-only mode).
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.mixWithOthers, .allowAirPlay, .allowBluetoothA2DP]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("Noellyne audio session unavailable: \(error)")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

## 3. Flutter side

`media_kit` keeps decoding as long as the process is alive and the session is
active. When the 🎧 mode is on, `IOSPlayerPage` should:

- keep the `Player` instance alive (do not `dispose()` on route pop),
- hide `VideoController`'s surface (set the video widget to `SizedBox.shrink()`)
  and show the audio stage instead,
- release the player only when the user leaves audio mode or taps Stop.

`UIBackgroundModes: audio` is the App Store requirement; the `AVAudioSession`
category above is what actually keeps sound flowing.
