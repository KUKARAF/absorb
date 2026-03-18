// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'A B S O R B';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get remove => 'Remove';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get search => 'Search';

  @override
  String get apply => 'Apply';

  @override
  String get enable => 'Enable';

  @override
  String get clear => 'Clear';

  @override
  String get off => 'Off';

  @override
  String get disabled => 'Disabled';

  @override
  String get later => 'Later';

  @override
  String get gotIt => 'Got it';

  @override
  String get preview => 'Preview';

  @override
  String get or => 'or';

  @override
  String get file => 'File';

  @override
  String get more => 'More';

  @override
  String get unknown => 'Unknown';

  @override
  String get untitled => 'Untitled';

  @override
  String get noThanks => 'No Thanks';

  @override
  String get stay => 'Stay';

  @override
  String get homeTitle => 'Home';

  @override
  String get continueListening => 'Continue Listening';

  @override
  String get continueSeries => 'Continue Series';

  @override
  String get recentlyAdded => 'Recently Added';

  @override
  String get listenAgain => 'Listen Again';

  @override
  String get discover => 'Discover';

  @override
  String get newEpisodes => 'New Episodes';

  @override
  String get downloads => 'Downloads';

  @override
  String get noDownloadedBooks => 'No downloaded books';

  @override
  String get yourLibraryIsEmpty => 'Your library is empty';

  @override
  String get downloadBooksWhileOnline =>
      'Download books while online to listen offline';

  @override
  String get customizeHome => 'Customize Home';

  @override
  String get dragToReorderTapEye => 'Drag to reorder, tap eye to show/hide';

  @override
  String get loginTagline => 'Start Absorbing';

  @override
  String get loginConnectToServer => 'Connect to your server';

  @override
  String get loginServerAddress => 'Server address';

  @override
  String get loginServerHint => 'my.server.com';

  @override
  String get loginServerHelper => 'IP:port works too (e.g. 192.168.1.5:13378)';

  @override
  String get loginCouldNotReachServer => 'Could not reach server';

  @override
  String get loginAdvanced => 'Advanced';

  @override
  String get loginCustomHttpHeaders => 'Custom HTTP Headers';

  @override
  String get loginCustomHeadersDescription =>
      'For Cloudflare tunnels or reverse proxies that require extra headers. Add headers before entering your server URL.';

  @override
  String get loginHeaderName => 'Header name';

  @override
  String get loginHeaderValue => 'Value';

  @override
  String get loginAddHeader => 'Add Header';

  @override
  String get loginSelfSignedCertificates => 'Self-signed Certificates';

  @override
  String get loginTrustAllCertificates =>
      'Trust all certificates (for self-signed / custom CA setups)';

  @override
  String get loginWaitingForSso => 'Waiting for SSO...';

  @override
  String get loginRedirectUri => 'Redirect URI: audiobookshelf://oauth';

  @override
  String get loginOrSignInManually => 'or sign in manually';

  @override
  String get loginUsername => 'Username';

  @override
  String get loginUsernameRequired => 'Please enter your username';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get loginFailed => 'Login failed';

  @override
  String get loginSsoFailed => 'SSO login failed or was cancelled';

  @override
  String get loginSsoAuthFailed =>
      'SSO authentication failed. Please try again.';

  @override
  String get loginRestoreFromBackup => 'Restore from backup';

  @override
  String get loginInvalidBackupFile => 'Invalid backup file';

  @override
  String get loginRestoreBackupTitle => 'Restore backup?';

  @override
  String loginRestoreBackupWithAccounts(int count) {
    return 'This will restore all settings and $count saved account(s). You\'ll be signed in automatically.';
  }

  @override
  String get loginRestoreBackupNoAccounts =>
      'This will restore all settings. No accounts were included in this backup.';

  @override
  String get loginRestore => 'Restore';

  @override
  String loginRestoredAndSignedIn(String username) {
    return 'Restored settings and signed in as $username';
  }

  @override
  String get loginSessionExpired =>
      'Settings restored. Session expired - sign in to continue.';

  @override
  String get loginSettingsRestored => 'Settings restored';

  @override
  String loginRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get loginSavedAccounts => 'saved accounts';

  @override
  String get libraryTitle => 'Library';

  @override
  String get librarySearchBooksHint => 'Search books, series, and authors...';

  @override
  String get librarySearchShowsHint => 'Search shows and episodes...';

  @override
  String get libraryTabLibrary => 'Library';

  @override
  String get libraryTabSeries => 'Series';

  @override
  String get libraryTabAuthors => 'Authors';

  @override
  String get libraryNoBooks => 'No books found';

  @override
  String get libraryNoBooksInProgress => 'No books in progress';

  @override
  String get libraryNoFinishedBooks => 'No finished books';

  @override
  String get libraryAllBooksStarted => 'All books have been started';

  @override
  String get libraryNoDownloadedBooks => 'No downloaded books';

  @override
  String get libraryNoSeriesFound => 'No series found';

  @override
  String get libraryNoBooksWithEbooks => 'No books with eBooks';

  @override
  String libraryNoBooksInGenre(String genre) {
    return 'No books in \"$genre\"';
  }

  @override
  String get libraryClearFilter => 'Clear filter';

  @override
  String get libraryNoAuthorsFound => 'No authors found';

  @override
  String get libraryNoResults => 'No results found';

  @override
  String get librarySearchBooks => 'Books';

  @override
  String get librarySearchShows => 'Shows';

  @override
  String get librarySearchEpisodes => 'Episodes';

  @override
  String get librarySearchSeries => 'Series';

  @override
  String get librarySearchAuthors => 'Authors';

  @override
  String librarySeriesCount(int count) {
    return '$count series';
  }

  @override
  String libraryAuthorsCount(int count) {
    return '$count authors';
  }

  @override
  String libraryBooksCount(int loaded, int total) {
    return '$loaded/$total books';
  }

  @override
  String get sort => 'Sort';

  @override
  String get filter => 'Filter';

  @override
  String get filterActive => 'Filter ●';

  @override
  String get name => 'Name';

  @override
  String get title => 'Title';

  @override
  String get author => 'Author';

  @override
  String get dateAdded => 'Date Added';

  @override
  String get numberOfBooks => 'Number of Books';

  @override
  String get publishedYear => 'Published Year';

  @override
  String get duration => 'Duration';

  @override
  String get random => 'Random';

  @override
  String get collapseSeries => 'Collapse Series';

  @override
  String get inProgress => 'In Progress';

  @override
  String get filterFinished => 'Finished';

  @override
  String get notStarted => 'Not Started';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get hasEbook => 'Has eBook';

  @override
  String get genre => 'Genre';

  @override
  String get clearFilter => 'Clear Filter';

  @override
  String get noGenresFound => 'No genres found';

  @override
  String get asc => 'ASC';

  @override
  String get desc => 'DESC';

  @override
  String get absorbingTitle => 'Absorbing';

  @override
  String get absorbingStop => 'Stop';

  @override
  String get absorbingManageQueue => 'Manage Queue';

  @override
  String get absorbingDone => 'Done';

  @override
  String get absorbingNoDownloadedEpisodes => 'No downloaded episodes';

  @override
  String get absorbingNoDownloadedBooks => 'No downloaded books';

  @override
  String get absorbingNothingPlayingYet => 'Nothing playing yet';

  @override
  String get absorbingNothingAbsorbingYet => 'Nothing absorbing yet';

  @override
  String get absorbingDownloadEpisodesToListen =>
      'Download episodes to listen offline';

  @override
  String get absorbingDownloadBooksToListen =>
      'Download books to listen offline';

  @override
  String get absorbingStartEpisodeFromShows =>
      'Start an episode from the Shows tab';

  @override
  String get absorbingStartBookFromLibrary =>
      'Start a book from the Library tab';

  @override
  String get carModeTitle => 'Car Mode';

  @override
  String get carModeNoBookLoaded => 'No book loaded';

  @override
  String get carModeBookLabel => 'Book';

  @override
  String get carModeChapterLabel => 'Chapter';

  @override
  String get carModeBookmarkDefault => 'Bookmark';

  @override
  String get carModeBookmarkAdded => 'Bookmark added';

  @override
  String get downloadsTitle => 'Downloads';

  @override
  String get downloadsCancelSelection => 'Cancel selection';

  @override
  String get downloadsSelect => 'Select';

  @override
  String get downloadsNoDownloads => 'No downloads';

  @override
  String get downloadsDownloading => 'Downloading';

  @override
  String get downloadsQueued => 'Queued';

  @override
  String get downloadsCompleted => 'Completed';

  @override
  String get downloadsWaiting => 'Waiting...';

  @override
  String get downloadsCancel => 'Cancel';

  @override
  String get downloadsDelete => 'Delete';

  @override
  String downloadsDeleteCount(int count) {
    return 'Delete $count download(s)?';
  }

  @override
  String get downloadsDeleteContent =>
      'Downloaded files will be removed from this device.';

  @override
  String downloadsDeletedCount(int count) {
    return 'Deleted $count download(s)';
  }

  @override
  String get downloadsRemoveTitle => 'Remove download?';

  @override
  String downloadsRemoveContent(String title) {
    return 'Delete \"$title\" from this device?';
  }

  @override
  String downloadsRemovedTitle(String title) {
    return '\"$title\" removed';
  }

  @override
  String downloadsSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get bookmarksTitle => 'All Bookmarks';

  @override
  String get bookmarksCancelSelection => 'Cancel selection';

  @override
  String get bookmarksSortedByNewest => 'Sorted by newest';

  @override
  String get bookmarksSortedByPosition => 'Sorted by position';

  @override
  String get bookmarksSelect => 'Select';

  @override
  String get bookmarksNoBookmarks => 'No bookmarks yet';

  @override
  String bookmarksDeleteCount(int count) {
    return 'Delete $count bookmark(s)?';
  }

  @override
  String get bookmarksDeleteContent => 'This cannot be undone.';

  @override
  String bookmarksDeletedCount(int count) {
    return 'Deleted $count bookmark(s)';
  }

  @override
  String get bookmarksJumpTitle => 'Jump to bookmark?';

  @override
  String bookmarksJumpContent(String title, String position, String bookTitle) {
    return '\"$title\" at $position\nin $bookTitle';
  }

  @override
  String get bookmarksJump => 'Jump';

  @override
  String get bookmarksNotConnected => 'Not connected to server';

  @override
  String get bookmarksCouldNotLoad => 'Could not load book';

  @override
  String bookmarksSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get statsTitle => 'Your Stats';

  @override
  String get statsCouldNotLoad => 'Couldn\'t load stats';

  @override
  String get statsTotalListeningTime => 'TOTAL LISTENING TIME';

  @override
  String get statsHoursUnit => 'h';

  @override
  String get statsMinutesUnit => 'm';

  @override
  String statsDaysOfAudio(String days) {
    return 'That\'s $days days of audio';
  }

  @override
  String statsHoursOfAudio(String hours) {
    return 'That\'s $hours hours of audio';
  }

  @override
  String get statsToday => 'Today';

  @override
  String get statsThisWeek => 'This Week';

  @override
  String get statsThisMonth => 'This Month';

  @override
  String get statsActivity => 'Activity';

  @override
  String get statsCurrentStreak => 'Current Streak';

  @override
  String get statsBestStreak => 'Best Streak';

  @override
  String get statsFinished => 'Finished';

  @override
  String get statsDaysActive => 'Days Active';

  @override
  String get statsDailyAverage => 'Daily Average';

  @override
  String get statsLast7Days => 'Last 7 Days';

  @override
  String get statsMostListened => 'Most Listened';

  @override
  String get statsRecentSessions => 'Recent Sessions';

  @override
  String get appShellHomeTab => 'Home';

  @override
  String get appShellLibraryTab => 'Library';

  @override
  String get appShellAbsorbingTab => 'Absorbing';

  @override
  String get appShellStatsTab => 'Stats';

  @override
  String get appShellSettingsTab => 'Settings';

  @override
  String get appShellPressBackToExit => 'Press back again to exit';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get themeLabel => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeOled => 'OLED';

  @override
  String get themeLight => 'Light';

  @override
  String get themeAuto => 'Auto';

  @override
  String get colorSourceLabel => 'Color source';

  @override
  String get colorSourceCoverDescription =>
      'App colors follow the currently playing book cover';

  @override
  String get colorSourceWallpaperDescription =>
      'App colors follow your system wallpaper';

  @override
  String get colorSourceWallpaper => 'Wallpaper';

  @override
  String get colorSourceNowPlaying => 'Now Playing';

  @override
  String get startScreenLabel => 'Start screen';

  @override
  String get startScreenSubtitle => 'Which tab to open when the app launches';

  @override
  String get startScreenHome => 'Home';

  @override
  String get startScreenLibrary => 'Library';

  @override
  String get startScreenAbsorb => 'Absorb';

  @override
  String get startScreenStats => 'Stats';

  @override
  String get disablePageFade => 'Disable page fade';

  @override
  String get disablePageFadeOnSubtitle => 'Pages switch instantly';

  @override
  String get disablePageFadeOffSubtitle => 'Pages fade when switching tabs';

  @override
  String get rectangleBookCovers => 'Rectangle book covers';

  @override
  String get rectangleBookCoversOnSubtitle =>
      'Covers display in 2:3 book proportion';

  @override
  String get rectangleBookCoversOffSubtitle => 'Covers are square';

  @override
  String get sectionAbsorbingCards => 'Absorbing Cards';

  @override
  String get fullScreenPlayer => 'Full screen player';

  @override
  String get fullScreenPlayerOnSubtitle =>
      'On - books open in full screen when played';

  @override
  String get fullScreenPlayerOffSubtitle => 'Off - play within card view';

  @override
  String get fullBookScrubber => 'Full book scrubber';

  @override
  String get fullBookScrubberOnSubtitle =>
      'On - seekable slider across entire book';

  @override
  String get fullBookScrubberOffSubtitle => 'Off - progress bar only';

  @override
  String get speedAdjustedTime => 'Speed-adjusted time';

  @override
  String get speedAdjustedTimeOnSubtitle =>
      'On - remaining time reflects playback speed';

  @override
  String get speedAdjustedTimeOffSubtitle => 'Off - showing raw audio duration';

  @override
  String get buttonLayout => 'Button layout';

  @override
  String get buttonLayoutSubtitle =>
      'How action buttons are arranged on the card';

  @override
  String get whenAbsorbed => 'When absorbed';

  @override
  String get whenAbsorbedInfoTitle => 'When Absorbed';

  @override
  String get whenAbsorbedInfoContent =>
      'Controls what happens to an absorbing card when you finish a book or episode.\n\nShow Overlay: A completion overlay appears on the card, letting you choose what to do next.\n\nAuto-release: The finished card is automatically removed from your Absorbing screen.';

  @override
  String get whenAbsorbedSubtitle =>
      'What happens to the absorbing card when a book or episode finishes';

  @override
  String get whenAbsorbedShowOverlay => 'Show Overlay';

  @override
  String get whenAbsorbedAutoRelease => 'Auto-release';

  @override
  String get mergeLibraries => 'Merge libraries';

  @override
  String get mergeLibrariesInfoTitle => 'Merge Libraries';

  @override
  String get mergeLibrariesInfoContent =>
      'When enabled, the Absorbing screen shows all your in-progress books and podcasts from every library in a single view. When disabled, only items from the library you currently have selected are shown.';

  @override
  String get mergeLibrariesOnSubtitle =>
      'Absorbing page shows items from all libraries';

  @override
  String get mergeLibrariesOffSubtitle =>
      'Absorbing page shows current library only';

  @override
  String get queueMode => 'Queue mode';

  @override
  String get queueModeInfoTitle => 'Queue Mode';

  @override
  String get queueModeInfoOff => 'Off';

  @override
  String get queueModeInfoOffDesc =>
      'Playback stops when the current book or episode finishes.';

  @override
  String get queueModeInfoManual => 'Manual Queue';

  @override
  String get queueModeInfoManualDesc =>
      'Your absorbing cards act as a playlist. When one finishes, the next non-finished card auto-plays. Add items with the \"Add to Absorbing\" button on a book or episode and reorder from the absorbing screen.';

  @override
  String get queueModeInfoAutoAbsorb => 'Auto Absorb';

  @override
  String get queueModeInfoAutoAbsorbDesc =>
      'Automatically absorbs the next book in a series or the next episode in a podcast show.';

  @override
  String get queueModeOff => 'Off';

  @override
  String get queueModeManual => 'Manual';

  @override
  String get queueModeAuto => 'Auto';

  @override
  String get queueModeBooks => 'Books';

  @override
  String get queueModePodcasts => 'Podcasts';

  @override
  String get autoDownloadQueue => 'Auto-download queue';

  @override
  String autoDownloadQueueOnSubtitle(int count) {
    return 'Keep next $count items downloaded';
  }

  @override
  String get autoDownloadQueueOffSubtitle => 'Off - manual downloads only';

  @override
  String get sectionPlayback => 'Playback';

  @override
  String get defaultSpeed => 'Default speed';

  @override
  String get defaultSpeedSubtitle =>
      'New books start at this speed - each book remembers its own';

  @override
  String get skipBack => 'Skip back';

  @override
  String get skipForward => 'Skip forward';

  @override
  String get chapterProgressInNotification =>
      'Chapter progress in notification';

  @override
  String get chapterProgressOnSubtitle =>
      'On - lockscreen shows chapter progress';

  @override
  String get chapterProgressOffSubtitle =>
      'Off - lockscreen shows full book progress';

  @override
  String get autoRewindOnResume => 'Auto-rewind on resume';

  @override
  String autoRewindOnSubtitle(String min, String max) {
    return 'On - ${min}s to ${max}s based on pause length';
  }

  @override
  String get autoRewindOffSubtitle => 'Off';

  @override
  String get rewindRange => 'Rewind range';

  @override
  String get rewindAfterPausedFor => 'Rewind after paused for';

  @override
  String get rewindAnyPause => 'Any pause';

  @override
  String get rewindAlwaysLabel => 'Always';

  @override
  String get rewindAlwaysDescription =>
      'Rewinds every time you resume, even after quick interruptions';

  @override
  String rewindAfterDescription(String seconds) {
    return 'Only rewinds if paused for $seconds+ seconds';
  }

  @override
  String get chapterBarrier => 'Chapter barrier';

  @override
  String get chapterBarrierSubtitle =>
      'Don\'t rewind past the start of the current chapter';

  @override
  String get rewindInstant => 'Instant';

  @override
  String rewindPause(String duration) {
    return '$duration pause';
  }

  @override
  String get rewindNoRewind => 'no rewind';

  @override
  String rewindSeconds(String seconds) {
    return '${seconds}s rewind';
  }

  @override
  String get sectionSleepTimer => 'Sleep Timer';

  @override
  String get sleep => 'Sleep';

  @override
  String get sleepTimer => 'Sleep Timer';

  @override
  String get shakeDuringSleepTimer => 'Shake during sleep timer';

  @override
  String get shakeOff => 'Off';

  @override
  String get shakeAddTime => 'Add Time';

  @override
  String get shakeReset => 'Reset';

  @override
  String get shakeAdds => 'Shake adds';

  @override
  String shakeAddsValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get resetTimerOnPause => 'Reset timer on pause';

  @override
  String get resetTimerOnPauseOnSubtitle =>
      'Timer restarts from full duration when you resume';

  @override
  String get resetTimerOnPauseOffSubtitle =>
      'Timer continues from where it left off';

  @override
  String get fadeVolumeBeforeSleep => 'Fade volume before sleep';

  @override
  String get fadeVolumeOnSubtitle =>
      'Gradually lowers volume during the last 30 seconds';

  @override
  String get fadeVolumeOffSubtitle =>
      'Playback stops immediately when timer ends';

  @override
  String get autoSleepTimer => 'Auto sleep timer';

  @override
  String autoSleepTimerOnSubtitle(String start, String end, int duration) {
    return '$start - $end - $duration min';
  }

  @override
  String get autoSleepTimerOffSubtitle =>
      'Automatically start a sleep timer during a time window';

  @override
  String get windowStart => 'Window start';

  @override
  String get windowEnd => 'Window end';

  @override
  String get timerDuration => 'Timer duration';

  @override
  String get timer => 'Timer';

  @override
  String get endOfChapter => 'End of Chapter';

  @override
  String startMinTimer(int minutes) {
    return 'Start $minutes min timer';
  }

  @override
  String sleepAfterChapters(int count, String label) {
    return 'Sleep after $count $label';
  }

  @override
  String get addMoreTime => 'Add more time';

  @override
  String get cancelTimer => 'Cancel timer';

  @override
  String chaptersLeftCount(int count) {
    return '$count ch left';
  }

  @override
  String get sectionDownloadsAndStorage => 'Downloads & Storage';

  @override
  String get downloadOverWifiOnly => 'Download over Wi-Fi only';

  @override
  String get downloadOverWifiOnSubtitle =>
      'On - mobile data blocked for downloads';

  @override
  String get downloadOverWifiOffSubtitle => 'Off - downloads on any connection';

  @override
  String get autoDownloadOnWifi => 'Auto download on Wi-Fi';

  @override
  String get autoDownloadOnWifiInfoTitle => 'Auto Download on Wi-Fi';

  @override
  String get autoDownloadOnWifiInfoContent =>
      'When you start streaming a book over Wi-Fi, it will automatically begin downloading the full book in the background. This way you\'ll have it available offline without having to manually start the download.';

  @override
  String get autoDownloadOnWifiOnSubtitle =>
      'Books download in the background when you start streaming on Wi-Fi';

  @override
  String get autoDownloadOnWifiOffSubtitle => 'Off';

  @override
  String get concurrentDownloads => 'Concurrent downloads';

  @override
  String get autoDownload => 'Auto-download';

  @override
  String get autoDownloadSubtitle =>
      'Enable per series or podcast from their detail pages';

  @override
  String get keepNext => 'Keep next';

  @override
  String get keepNextInfoTitle => 'Keep Next';

  @override
  String get keepNextInfoContent =>
      'The number of items to keep downloaded, including the one you\'re currently listening to. For example, \"Keep next 3\" means the current book plus the next 2 in the series or podcast will stay downloaded.';

  @override
  String get deleteAbsorbedDownloads => 'Delete absorbed downloads';

  @override
  String get deleteAbsorbedDownloadsInfoTitle => 'Delete Absorbed Downloads';

  @override
  String get deleteAbsorbedDownloadsInfoContent =>
      'When enabled, downloaded books or episodes are automatically deleted from your device after you finish listening to them. This helps free up storage space as you work through your library.';

  @override
  String get deleteAbsorbedOnSubtitle =>
      'Finished items are removed to save space';

  @override
  String get deleteAbsorbedOffSubtitle => 'Off - finished downloads kept';

  @override
  String get downloadLocation => 'Download location';

  @override
  String get storageUsed => 'Storage used';

  @override
  String storageUsedByDownloads(String size) {
    return '$size used by downloads';
  }

  @override
  String storageFreeOfTotal(String free, String total) {
    return '$free free of $total';
  }

  @override
  String get manageDownloads => 'Manage downloads';

  @override
  String get streamingCache => 'Streaming cache';

  @override
  String get streamingCacheInfoTitle => 'Streaming Cache';

  @override
  String get streamingCacheInfoContent =>
      'Caches streamed audio to disk so it doesn\'t need to be re-downloaded if you seek back or re-listen to sections. The cache is automatically managed - oldest files are removed when the size limit is reached. This is separate from fully downloaded books.';

  @override
  String get streamingCacheOff => 'Off';

  @override
  String get streamingCacheOffSubtitle =>
      'Off - audio is streamed without caching';

  @override
  String streamingCacheOnSubtitle(int size) {
    return '$size MB - recently streamed audio is cached to disk';
  }

  @override
  String get clearCache => 'Clear cache';

  @override
  String get streamingCacheCleared => 'Streaming cache cleared';

  @override
  String get sectionLibrary => 'Library';

  @override
  String get hideEbookOnlyTitles => 'Hide eBook-only titles';

  @override
  String get hideEbookOnlyOnSubtitle => 'Books with no audio files are hidden';

  @override
  String get hideEbookOnlyOffSubtitle => 'Off - all library items shown';

  @override
  String get showGoodreadsButton => 'Show Goodreads button';

  @override
  String get showGoodreadsOnSubtitle =>
      'Book detail sheet shows a link to Goodreads';

  @override
  String get showGoodreadsOffSubtitle => 'Off - Goodreads button hidden';

  @override
  String get sectionPermissions => 'Permissions';

  @override
  String get notifications => 'Notifications';

  @override
  String get notificationsSubtitle =>
      'For download progress and playback controls';

  @override
  String get notificationsAlreadyEnabled => 'Notifications already enabled';

  @override
  String get unrestrictedBattery => 'Unrestricted battery';

  @override
  String get unrestrictedBatterySubtitle =>
      'Prevents Android from killing background playback';

  @override
  String get batteryAlreadyUnrestricted => 'Battery already unrestricted';

  @override
  String get sectionIssuesAndSupport => 'Issues & Support';

  @override
  String get bugsAndFeatureRequests => 'Bugs & Feature Requests';

  @override
  String get bugsAndFeatureRequestsSubtitle => 'Open an issue on GitHub';

  @override
  String get joinDiscord => 'Join Discord';

  @override
  String get joinDiscordSubtitle => 'Community, support, and updates';

  @override
  String get contact => 'Contact';

  @override
  String get contactSubtitle => 'Send device info via email';

  @override
  String get enableLogging => 'Enable logging';

  @override
  String get enableLoggingOnSubtitle =>
      'On - logs saved to file (restart to apply)';

  @override
  String get enableLoggingOffSubtitle => 'Off - no logs captured';

  @override
  String get loggingEnabledSnackbar =>
      'Logging enabled - restart app to start capturing';

  @override
  String get loggingDisabledSnackbar =>
      'Logging disabled - restart app to stop capturing';

  @override
  String get sendLogs => 'Send logs';

  @override
  String get sendLogsSubtitle => 'Share log file as attachment';

  @override
  String failedToShare(String error) {
    return 'Failed to share: $error';
  }

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get sectionAdvanced => 'Advanced';

  @override
  String get localServer => 'Local server';

  @override
  String get localServerInfoTitle => 'Local Server';

  @override
  String get localServerInfoContent =>
      'If you run your Audiobookshelf server at home, you can set a local/LAN URL here. Absorb will automatically switch to the faster local connection when it detects you\'re on your home network, and fall back to your remote URL when you\'re away.';

  @override
  String get localServerOnConnectedSubtitle => 'Connected via local server';

  @override
  String get localServerOnRemoteSubtitle => 'Enabled - using remote server';

  @override
  String get localServerOffSubtitle =>
      'Auto-switch to a LAN server on your home WiFi';

  @override
  String get localServerUrlLabel => 'Local server URL';

  @override
  String get localServerUrlHint => 'http://192.168.1.100:13378';

  @override
  String get localServerUrlSetSnackbar =>
      'Local server URL set - will connect automatically when on your home network';

  @override
  String get disableAudioFocus => 'Disable audio focus';

  @override
  String get disableAudioFocusInfoTitle => 'Audio Focus';

  @override
  String get disableAudioFocusInfoContent =>
      'By default, Android gives audio \"focus\" to one app at a time - when Absorb plays, other audio (music, videos) will pause. Disabling audio focus lets Absorb play alongside other apps. Phone calls will still pause playback regardless of this setting.';

  @override
  String get disableAudioFocusOnSubtitle =>
      'On - plays alongside other audio (still pauses for calls)';

  @override
  String get disableAudioFocusOffSubtitle =>
      'Off - other audio pauses when Absorb plays';

  @override
  String get restartRequired => 'Restart Required';

  @override
  String get restartRequiredContent =>
      'Audio focus change requires a full restart to take effect. Close the app now?';

  @override
  String get closeApp => 'Close App';

  @override
  String get trustAllCertificates => 'Trust all certificates';

  @override
  String get trustAllCertificatesInfoTitle => 'Self-signed Certificates';

  @override
  String get trustAllCertificatesInfoContent =>
      'Enable this if your Audiobookshelf server uses a self-signed certificate or a custom root CA. When enabled, Absorb will skip TLS certificate verification for all connections. Only enable this if you trust your network.';

  @override
  String get trustAllCertificatesOnSubtitle =>
      'On - accepting all certificates';

  @override
  String get trustAllCertificatesOffSubtitle =>
      'Off - only trusted certificates accepted';

  @override
  String get supportTheDev => 'Support the Dev';

  @override
  String get buyMeACoffee => 'Buy me a coffee';

  @override
  String appVersionFormat(String version) {
    return 'Absorb v$version';
  }

  @override
  String appVersionWithServerFormat(String version, String serverVersion) {
    return 'Absorb v$version  -  Server $serverVersion';
  }

  @override
  String get backupAndRestore => 'Backup & Restore';

  @override
  String get backupAndRestoreSubtitle =>
      'Save or restore all your settings to a file';

  @override
  String get backUp => 'Back up';

  @override
  String get restore => 'Restore';

  @override
  String get allBookmarks => 'All Bookmarks';

  @override
  String get allBookmarksSubtitle => 'View bookmarks across all books';

  @override
  String get switchAccount => 'Switch Account';

  @override
  String get addAccount => 'Add Account';

  @override
  String get logOut => 'Log out';

  @override
  String get includeLoginInfoTitle => 'Include login info?';

  @override
  String get includeLoginInfoContent =>
      'Would you like to include login credentials for all your saved accounts in the backup?\n\nThis makes it easy to restore on a new device, but the file will contain your auth tokens.';

  @override
  String get noSettingsOnly => 'No, settings only';

  @override
  String get yesIncludeAccounts => 'Yes, include accounts';

  @override
  String get backupSavedWithAccounts => 'Backup saved (with accounts)';

  @override
  String get backupSavedSettingsOnly => 'Backup saved (settings only)';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get restoreBackupTitle => 'Restore backup?';

  @override
  String get restoreBackupContent =>
      'This will replace all your current settings with the backup values.';

  @override
  String fromAbsorbVersion(String version) {
    return 'From Absorb v$version';
  }

  @override
  String restoreAccountsChip(int count) {
    return '$count account(s)';
  }

  @override
  String restoreBookmarksChip(int count) {
    return 'Bookmarks for $count book(s)';
  }

  @override
  String get restoreCustomHeadersChip => 'Custom headers';

  @override
  String get invalidBackupFile => 'Invalid backup file';

  @override
  String get settingsRestoredSuccessfully => 'Settings restored successfully';

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get logOutTitle => 'Log out?';

  @override
  String get logOutContent =>
      'This will sign you out. Your downloads will stay on this device.';

  @override
  String get signOut => 'Sign Out';

  @override
  String get removeAccountTitle => 'Remove Account?';

  @override
  String removeAccountContent(String username, String server) {
    return 'Remove $username on $server from saved accounts?\n\nYou can always add it back later by signing in again.';
  }

  @override
  String get switchAccountTitle => 'Switch Account?';

  @override
  String switchAccountContent(String username, String server) {
    return 'Switch to $username on $server?\n\nYour current playback will be stopped and the app will reload with the other account\'s data.';
  }

  @override
  String get switchButton => 'Switch';

  @override
  String get downloadLocationSheetTitle => 'Download Location';

  @override
  String get downloadLocationSheetSubtitle =>
      'Choose where audiobooks are saved';

  @override
  String get currentLocation => 'Current location';

  @override
  String get existingDownloadsWarning =>
      'Existing downloads stay in their current location. Only new downloads use the new path.';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get chooseDownloadFolder => 'Choose download folder';

  @override
  String get storagePermissionDenied =>
      'Storage permission permanently denied - enable it in app settings';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get storagePermissionRequired =>
      'Storage permission is required for custom download locations';

  @override
  String get cannotWriteToFolder =>
      'Cannot write to that folder - choose another location or grant file access in system settings';

  @override
  String downloadLocationSetTo(String label) {
    return 'Download location set to $label';
  }

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get resetToDefaultStorage => 'Reset to default storage';

  @override
  String get tipsAndHiddenFeatures => 'Tips & Hidden Features';

  @override
  String get tipsSubtitle => 'Get the most out of Absorb';

  @override
  String get adminTitle => 'Server Admin';

  @override
  String get adminServer => 'Server';

  @override
  String get adminVersion => 'Version';

  @override
  String get adminUsers => 'Users';

  @override
  String get adminOnline => 'Online';

  @override
  String get adminBackup => 'Backup';

  @override
  String get adminPurgeCache => 'Purge Cache';

  @override
  String get adminManage => 'Manage';

  @override
  String adminUsersSubtitle(int userCount, int onlineCount) {
    return '$userCount accounts - $onlineCount online';
  }

  @override
  String get adminPodcasts => 'Podcasts';

  @override
  String get adminPodcastsSubtitle => 'Search, add & manage shows';

  @override
  String get adminScan => 'Scan';

  @override
  String get adminScanning => 'Scanning...';

  @override
  String get adminMatchAll => 'Match All';

  @override
  String get adminMatching => 'Matching...';

  @override
  String get adminMatchAllTitle => 'Match All Items?';

  @override
  String adminMatchAllContent(String name) {
    return 'Match metadata for all items in $name? This can take a while.';
  }

  @override
  String adminScanStarted(String name) {
    return 'Scan started for $name';
  }

  @override
  String get adminBackupCreated => 'Backup created';

  @override
  String get adminBackupFailed => 'Backup failed';

  @override
  String get adminCachePurged => 'Cache purged';

  @override
  String narratedBy(String narrator) {
    return 'Narrated by $narrator';
  }

  @override
  String get onAudible => 'on Audible';

  @override
  String percentComplete(String percent) {
    return '$percent% complete';
  }

  @override
  String get absorbing => 'Absorbing...';

  @override
  String get absorbAgain => 'Absorb Again';

  @override
  String get absorb => 'Absorb';

  @override
  String get ebookOnlyNoAudio => 'eBook Only - No Audio';

  @override
  String get fullyAbsorbed => 'Fully Absorbed';

  @override
  String get fullyAbsorbAction => 'Fully Absorb';

  @override
  String get removeFromAbsorbing => 'Remove from Absorbing';

  @override
  String get addToAbsorbing => 'Add to Absorbing';

  @override
  String get removedFromAbsorbing => 'Removed from Absorbing';

  @override
  String get addedToAbsorbing => 'Added to Absorbing';

  @override
  String get addToPlaylist => 'Add to Playlist';

  @override
  String get addToCollection => 'Add to Collection';

  @override
  String get downloadEbook => 'Download eBook';

  @override
  String get downloadEbookAgain => 'Download eBook Again';

  @override
  String get resetProgress => 'Reset Progress';

  @override
  String get lookupLocalMetadata => 'Lookup Local Metadata';

  @override
  String get reLookupLocalMetadata => 'Re-Lookup Local Metadata';

  @override
  String get clearLocalMetadata => 'Clear Local Metadata';

  @override
  String get searchOnGoodreads => 'Search on Goodreads';

  @override
  String get editServerDetails => 'Edit Server Details';

  @override
  String get aboutSection => 'About';

  @override
  String chaptersCount(int count) {
    return 'Chapters ($count)';
  }

  @override
  String get chapters => 'Chapters';

  @override
  String get failedToLoad => 'Failed to load';

  @override
  String startedDate(String date) {
    return 'Started $date';
  }

  @override
  String finishedDate(String date) {
    return 'Finished $date';
  }

  @override
  String andCountMore(int count) {
    return 'and $count more';
  }

  @override
  String get markAsFullyAbsorbedQuestion => 'Mark as Fully Absorbed?';

  @override
  String get markAsFullyAbsorbedContent =>
      'This will set your progress to 100% and stop playback if this book is playing.';

  @override
  String get markedAsFinishedNiceWork => 'Marked as finished - nice work!';

  @override
  String get failedToUpdateCheckConnection =>
      'Failed to update - check your connection';

  @override
  String get markAsNotFinishedQuestion => 'Mark as Not Finished?';

  @override
  String get markAsNotFinishedContent =>
      'This will clear the finished status but keep your current position.';

  @override
  String get unmark => 'Unmark';

  @override
  String get markedAsNotFinishedBackAtIt =>
      'Marked as not finished - back at it!';

  @override
  String get resetProgressQuestion => 'Reset Progress?';

  @override
  String get resetProgressContent =>
      'This will erase all progress for this book and set it back to the beginning. This can\'t be undone.';

  @override
  String get progressResetFreshStart => 'Progress reset - fresh start!';

  @override
  String get clearLocalMetadataQuestion => 'Clear Local Metadata?';

  @override
  String get clearLocalMetadataContent =>
      'This will remove the locally stored metadata and revert to whatever the server has.';

  @override
  String get localMetadataCleared => 'Local metadata cleared';

  @override
  String get saveEbook => 'Save eBook';

  @override
  String get noEbookFileFound => 'No ebook file found';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String bookmarksWithCount(int count) {
    return 'Bookmarks ($count)';
  }

  @override
  String get playbackSpeed => 'Playback Speed';

  @override
  String get noBookmarksYet => 'No bookmarks yet';

  @override
  String get longPressBookmarkHint =>
      'Long-press the bookmark button to quick save';

  @override
  String get addBookmark => 'Add Bookmark';

  @override
  String get editBookmark => 'Edit Bookmark';

  @override
  String get titleLabel => 'Title';

  @override
  String get noteOptionalLabel => 'Note (optional)';

  @override
  String get editLayout => 'Edit Layout';

  @override
  String get inMenu => 'In menu';

  @override
  String get bookmarkAdded => 'Bookmark added';

  @override
  String get startPlayingSomethingFirst => 'Start playing something first';

  @override
  String get playbackHistory => 'Playback History';

  @override
  String get clearHistoryTooltip => 'Clear history';

  @override
  String get tapEventToJump => 'Tap an event to jump to that position';

  @override
  String get noHistoryYet => 'No history yet';

  @override
  String jumpedToPosition(String position) {
    return 'Jumped to $position';
  }

  @override
  String booksInSeriesCount(int count) {
    return '$count books in this series';
  }

  @override
  String bookNumber(String number) {
    return 'Book $number';
  }

  @override
  String downloadRemainingCount(int count) {
    return 'Download Remaining ($count)';
  }

  @override
  String get downloadAll => 'Download All';

  @override
  String get markAllNotFinished => 'Mark All Not Finished';

  @override
  String get markAllFinished => 'Mark All Finished';

  @override
  String get markAllNotFinishedQuestion => 'Mark All Not Finished?';

  @override
  String get fullyAbsorbSeries => 'Fully Absorb Series?';

  @override
  String get turnAutoDownloadOff => 'Turn Auto-Download Off';

  @override
  String get turnAutoDownloadOn => 'Turn Auto-Download On';

  @override
  String get autoDownloadThisSeries => 'Auto-Download This Series?';

  @override
  String get autoDownloadSeriesContent =>
      'Automatically download the next books as you listen.';

  @override
  String get standalone => 'Standalone';

  @override
  String get episodes => 'Episodes';

  @override
  String get noEpisodesFound => 'No episodes found';

  @override
  String get markFinished => 'Mark Finished';

  @override
  String get markUnfinished => 'Mark Unfinished';

  @override
  String get allEpisodes => 'All Episodes';

  @override
  String get aboutThisEpisode => 'About This Episode';

  @override
  String get reversePlayOrder => 'Reverse play order';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get autoDownloadThisPodcast => 'Auto-Download This Podcast?';

  @override
  String get autoDownloadPodcastContent =>
      'Automatically download the next episodes as you listen.';

  @override
  String get download => 'Download';

  @override
  String get deleteDownload => 'Delete Download';

  @override
  String get casting => 'Casting';

  @override
  String get castingTo => 'Casting to';

  @override
  String get editDetails => 'Edit Details';

  @override
  String get quickMatch => 'Quick Match';

  @override
  String get custom => 'Custom';

  @override
  String get authorOptionalLabel => 'Author (optional)';

  @override
  String get noResultsFound =>
      'No results found.\nTry adjusting your search or provider.';

  @override
  String get searchForMetadataAbove => 'Search for metadata above';

  @override
  String get applyThisMatch => 'Apply This Match?';

  @override
  String get metadataUpdated => 'Metadata updated';

  @override
  String get failedToUpdateMetadata => 'Failed to update metadata';

  @override
  String get subtitleLabel => 'Subtitle';

  @override
  String get authorLabel => 'Author';

  @override
  String get narratorLabel => 'Narrator';

  @override
  String get seriesLabel => 'Series';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get publisherLabel => 'Publisher';

  @override
  String get yearLabel => 'Year';

  @override
  String get languageLabel => 'Language';

  @override
  String get genresLabel => 'Genres';

  @override
  String get commaSeparated => 'Comma separated';

  @override
  String get asinLabel => 'ASIN';

  @override
  String get isbnLabel => 'ISBN';

  @override
  String get coverImage => 'Cover Image';

  @override
  String get coverUrlLabel => 'Cover URL';

  @override
  String get coverUrlHint => 'https://...';

  @override
  String get localMetadata => 'Local Metadata';

  @override
  String get overrideLocalDisplay => 'Override local display';

  @override
  String get metadataSavedLocally => 'Metadata saved locally';

  @override
  String get notes => 'Notes';

  @override
  String get newNote => 'New Note';

  @override
  String get editNote => 'Edit Note';

  @override
  String get noNotesYet => 'No notes yet';

  @override
  String get markdownIsSupported => 'Markdown is supported';

  @override
  String get markdownMd => 'Markdown (.md)';

  @override
  String get keepsFormattingIntact => 'Keeps formatting intact';

  @override
  String get plainTextTxt => 'Plain Text (.txt)';

  @override
  String get simpleTextNoFormatting => 'Simple text, no formatting';

  @override
  String get untitledNote => 'Untitled note';

  @override
  String get titleHint => 'Title';

  @override
  String get noteBodyHint => 'Write your note... (supports markdown)';

  @override
  String get nothingToPreview => 'Nothing to preview';

  @override
  String get audioEnhancements => 'Audio Enhancements';

  @override
  String get presets => 'PRESETS';

  @override
  String get equalizer => 'EQUALIZER';

  @override
  String get effects => 'EFFECTS';

  @override
  String get bassBoost => 'Bass Boost';

  @override
  String get surround => 'Surround';

  @override
  String get loudness => 'Loudness';

  @override
  String get monoAudio => 'Mono Audio';

  @override
  String get resetAll => 'Reset All';

  @override
  String get collectionNotFound => 'Collection not found';

  @override
  String get deleteCollection => 'Delete Collection';

  @override
  String get deleteCollectionContent =>
      'Are you sure you want to delete this collection?';

  @override
  String get playlistNotFound => 'Playlist not found';

  @override
  String get deletePlaylist => 'Delete Playlist';

  @override
  String get deletePlaylistContent =>
      'Are you sure you want to delete this playlist?';

  @override
  String get newPlaylist => 'New Playlist';

  @override
  String get playlistNameHint => 'Playlist name';

  @override
  String addedToName(String name) {
    return 'Added to \"$name\"';
  }

  @override
  String get failedToAdd => 'Failed to add';

  @override
  String get newCollection => 'New Collection';

  @override
  String get collectionNameHint => 'Collection name';

  @override
  String get castToDevice => 'Cast to Device';

  @override
  String get searchingForCastDevices => 'Searching for Cast devices...';

  @override
  String get castDevice => 'Cast Device';

  @override
  String get stopCasting => 'Stop Casting';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get audioOutput => 'Audio Output';

  @override
  String get noOutputDevicesFound => 'No output devices found';

  @override
  String get welcomeToAbsorb => 'Welcome to Absorb';

  @override
  String get welcomeOverview => 'Here\'s a quick overview of how things work.';

  @override
  String get welcomeHomeTitle => 'Home';

  @override
  String get welcomeHomeBody =>
      'Your personalized shelves from Audiobookshelf - continue listening, discover new titles, and browse your playlists and collections. Use the edit button in the top right to customize which sections appear and their order.';

  @override
  String get welcomeLibraryTitle => 'Library';

  @override
  String get welcomeLibraryBody =>
      'Browse your full library with tabs for books, series, and authors. Tap the active tab to open sort and filter options.';

  @override
  String get welcomeAbsorbingTitle => 'Absorbing';

  @override
  String get welcomeAbsorbingBody =>
      'Your active listening queue. Books you start playing automatically appear here as swipeable cards with full playback controls.';

  @override
  String get welcomeQueueModesTitle => 'Queue modes';

  @override
  String get welcomeQueueModeOff => 'Off - playback stops when a book finishes';

  @override
  String get welcomeQueueModeManual =>
      'Manual - auto-plays the next card in your queue';

  @override
  String get welcomeQueueModeAuto =>
      'Auto Absorb - automatically finds and plays the next book in a series';

  @override
  String get welcomeManagingQueueTitle => 'Managing your queue';

  @override
  String get welcomeManagingReorder =>
      'Tap the reorder icon to drag cards into your preferred order or swipe to remove';

  @override
  String get welcomeManagingAdd =>
      'Add books manually from any book\'s detail sheet';

  @override
  String get welcomeManagingFinish =>
      'When a book finishes, choose to listen again, remove it, or let it auto-release';

  @override
  String get welcomeMergeLibrariesTitle => 'Merge libraries';

  @override
  String get welcomeMergeLibrariesBody =>
      'Enable in Settings to show all your libraries together in one queue';

  @override
  String get welcomeDownloadsTitle => 'Downloads & Offline';

  @override
  String get welcomeDownloadsBody =>
      'Download books for offline listening. Toggle offline mode with the airplane icon on the Absorbing screen. Your progress syncs back to the server automatically when you reconnect.';

  @override
  String get welcomeSettingsTitle => 'Settings';

  @override
  String get welcomeSettingsBody =>
      'Configure queue behavior, sleep timers, playback speed, local server connections, and more.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get showMore => 'Show more';

  @override
  String get showLess => 'Show less';

  @override
  String get readMore => 'Read more';

  @override
  String get removeDownloadQuestion => 'Remove download?';

  @override
  String get removeDownloadContent => 'This will be removed from your device.';

  @override
  String get downloadRemoved => 'Download removed';

  @override
  String get finished => 'Finished';

  @override
  String get saved => 'Saved';

  @override
  String get selectLibrary => 'Select Library';

  @override
  String get switchLibraryTooltip => 'Switch library';

  @override
  String get noBooksFound => 'No books found';

  @override
  String get userFallback => 'User';

  @override
  String get rootAdmin => 'Root Admin';

  @override
  String get admin => 'Admin';

  @override
  String get serverAdmin => 'Server Admin';

  @override
  String get serverAdminSubtitle => 'Manage users, libraries & server settings';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get audible => 'Audible';

  @override
  String get iTunes => 'iTunes';

  @override
  String get openLibrary => 'Open Library';
}
