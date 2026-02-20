# Offline Model Runtime (Windows)

This folder contains scripts to build a bundled offline runtime used by `OfflineModel` provider.

The build script downloads:

- Python embeddable runtime
- `argostranslate`
- zh->en and en->zh model packages

Then it outputs `windows/dist/offline-runtime`, which is packed into the Windows installer.
