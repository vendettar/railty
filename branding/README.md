# Railty brand assets

This directory holds the source-of-truth artwork for the Railty application
icon. It is an original design created for Railty and is not derived from the
Ghostty logo.

- `Railty-R-icon.svg` — vector design source for the full app icon.
- `Railty-R-icon-{16,32,64,128,256,512,1024}.png` — rendered PNG masters at
  each standard size.
- `Railty-R-mark-transparent.svg` / `Railty-R-mark-transparent-1024.png` —
  transparent R mark for use where a standalone glyph is needed.

The macOS app icon is generated from `Railty-R-icon-1024.png` into
`macos/Assets.xcassets/AppIcon.appiconset/` (all standard macOS sizes) and is
selected by `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in the Xcode project.
The `AppIconImage.imageset` entries used by the UI, About window, and Dock
plugin are the same artwork at the corresponding sizes.

To regenerate the appiconset sizes from the 1024px master:

```sh
sips -s format png -z 16 16 branding/Railty-R-icon-1024.png \
  --out macos/Assets.xcassets/AppIcon.appiconset/icon_16x16.png
# ...repeat for each size listed in AppIcon.appiconset/Contents.json
```

Railty ships only this one official built-in icon. Upstream Ghostty icon
variants and the custom-style ghost layers are not included in release builds.
