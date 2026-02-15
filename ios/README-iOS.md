# Triple Space Translator iOS (Keyboard Extension MVP)

## What this MVP does

- Provides a custom iOS keyboard extension.
- In supported input boxes, when this keyboard is active:
  - press `space` 3 times within `0.5s`
  - Chinese text before cursor is translated to English
  - translated English replaces the current input content before cursor

## Project path

- Xcode project:
  - `ios/TripleSpaceTranslatorIOS/TripleSpaceTranslatorIOS.xcodeproj`
- Host app target:
  - `TripleSpaceHostApp`
- Keyboard extension target:
  - `TripleSpaceKeyboardExtension`

## Run on iPhone

1. Open `ios/TripleSpaceTranslatorIOS/TripleSpaceTranslatorIOS.xcodeproj` in Xcode.
2. Build and run `TripleSpaceHostApp` on your iPhone.
3. On iPhone, go to:
   - `Settings > General > Keyboard > Keyboards > Add New Keyboard...`
   - add `Triple Space Translator`
4. Enter this keyboard and enable `Allow Full Access`.
5. In ChatGPT/Claude/Grok/Gemini/WeChat input box, switch to this keyboard and test triple-space.

## Notes

- This feature only works while this custom keyboard is active.
- iOS may block third-party keyboards in some secure/sensitive fields.
- The current implementation translates the context before cursor and replaces that context.
- Translation uses Apple's `Translation.framework`.
