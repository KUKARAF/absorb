# Absorb

[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/BarnabasApps)

A modern audiobookshelf client with a card-based player experience.

## Screenshots

<p align="center">
  <img src="screenshots/absorbing.png" width="200">
  &nbsp;
  <img src="screenshots/library.png" width="200">
  &nbsp;
  <img src="screenshots/details.png" width="200">
</p>
<p align="center">
  <img src="screenshots/fullScreen.png" width="200">
  &nbsp;
  <img src="screenshots/stats.png" width="200">
</p>

## Features

- **Card-based player** — full-screen "Absorbing" cards replace the traditional player screen
- **Audiobookshelf integration** — connects to your self-hosted audiobookshelf server
- **Offline playback** — download books for listening without a connection
- **Podcast support** — chaptered podcasts with rich HTML descriptions
- **Backup & restore** — export all settings to a `.absorb` file and import on any device, with optional account credentials for seamless device migration
- **Multi-account** — sign into multiple servers and switch between them
- **Sleep timer** with visual fill bar countdown, auto-sleep scheduling, and shake-to-reset
- **Playback speed** control with fine-grained slider and per-book speed memory
- **Auto-rewind** — configurable rewind after pausing based on how long you were away
- **Equalizer** — built-in audio EQ with bands and presets
- **Bookmarks** — save and jump to moments in any book
- **Chapter navigation** with dual progress bars (book + chapter)
- **Search & filtering** — full-text search, filter by progress/genre/series, multiple sort modes
- **Audible ratings** — see star ratings from Audible on your books
- **Auto-play next** — automatically continue to the next book in a series or next podcast episode
- **Android Auto** — browse and listen from your car
- **Chromecast** — cast playback to Google Cast devices
- **Material You** theming with dynamic color support
- **Custom headers** — add custom HTTP headers for reverse proxy setups
- **OIDC/SSO login** — OpenID Connect support alongside standard auth
- **Server admin** — manage users, backups, and podcasts from the app
- **Listening stats** — track your listening history

## Install

[![Get it on GitHub](https://img.shields.io/badge/Get_it_on-GitHub-blue?style=for-the-badge&logo=github)](../../releases)
[![Get it on Obtainium](https://img.shields.io/badge/Get_it_on-Obtainium-teal?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0iTTEyIDJMMiAyMmgyMEwxMiAyeiIgZmlsbD0id2hpdGUiLz48L3N2Zz4=)](https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/pounat/absorb)

Absorb is also in **closed testing on Google Play**. If you'd like access, reach out or request an invite.

## Android Auto

Absorb supports Android Auto for browsing and listening from your car. To use it, you'll need to enable unknown sources in Android Auto:

> 1. Open **Android Auto** settings on your phone
> 2. Tap **Version** at the bottom repeatedly to enable Developer mode
> 3. Tap the three-dot menu (top right) and select **Developer settings**
> 4. Enable **Unknown sources**
>
> This is required because Absorb is not distributed through Google Play's production track.

## iOS TestFlight

Absorb is now available on iOS via [TestFlight](https://testflight.apple.com/join/GgUbDbve). Core functionality works, but some features are still Android-only or in progress.

### Working
If any of these aren't working as expected, please [open an issue](../../issues).

- [x] Library browsing, search, filtering, sorting
- [x] Streaming and offline playback
- [x] Downloads (app sandbox storage)
- [x] Podcast support
- [x] Sleep timer, bookmarks, chapter navigation
- [x] Playback speed with per-book memory
- [x] Auto-rewind after pause
- [x] Bluetooth media controls (play/pause, skip, rewind)
- [x] Background audio
- [x] Lock screen / Control Center controls
- [x] Multi-account and server switching
- [x] Backup & restore
- [x] Dynamic theming
- [x] OIDC/SSO login
- [x] Custom headers
- [x] Listening stats
- [x] Auto-pause on Bluetooth disconnect

### Not yet available on iOS
- [ ] Equalizer
- [ ] Chromecast
- [ ] CarPlay (Android Auto equivalent)
- [ ] Home screen / Lock Screen widgets
- [ ] Audio output device switcher
- [ ] Custom download location (iOS sandbox only)

## Requirements

- An [audiobookshelf](https://www.audiobookshelf.org/) server (self-hosted)
- Android 7.0+ / iOS 16+
