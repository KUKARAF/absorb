# Absorb

[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/BarnabasApps)

A modern audiobookshelf client for Android with a card-based player experience.

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

[<img src="https://raw.githubusercontent.com/NeoApplications/Neo-Backup/034b226cea5c1b30eb4f6a6f313e4dadcbb0ece4/badge_github.png" alt="Get it on GitHub" height="58">](../../releases)
[<img src="https://raw.githubusercontent.com/ImranR98/Obtainium/main/assets/graphics/badge_obtainium.png" alt="Get it on Obtainium" height="58">](https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/pounat/absorb)

Absorb is also in **closed testing on Google Play**. If you'd like access, reach out or request an invite.

## Android Auto

Absorb supports Android Auto for browsing and listening from your car. To use it, you'll need to enable unknown sources in Android Auto:

> 1. Open **Android Auto** settings on your phone
> 2. Tap **Version** at the bottom repeatedly to enable Developer mode
> 3. Tap the three-dot menu (top right) and select **Developer settings**
> 4. Enable **Unknown sources**
>
> This is required because Absorb is not distributed through Google Play's production track.

## Requirements

- An [audiobookshelf](https://www.audiobookshelf.org/) server (self-hosted)
- Android 7.0+
