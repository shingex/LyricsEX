source: https://github.com/amll-dev/applemusic-like-lyrics

# AMLL Original Theme

This folder contains the removable, third-party comparison theme that embeds a
compiled Web bundle built from `amll-dev/applemusic-like-lyrics`.

Removal checklist:

1. Remove `LyricsWindowTheme.amllOriginalSource`.
2. Remove the theme card in `PreferenceLyricsWindowThemeViewController`.
3. Remove `AMLLOriginalLyricsWebView` and its call sites in `LyricsHUDViewController`.
4. Remove this `ThirdParty/AMLLOriginalTheme` folder and the Xcode resource/source
   references.

