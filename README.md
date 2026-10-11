# AirNRG Neo
> CDs, Archived!

macOS app + CLI to split your Nero `.nrg` Audio-CD images (Thuy Nga / Le Quyen discs)
into per-track `.wav` files (44.1 kHz / 16-bit / stereo).

## Why not nrg2iso?

These discs are DAO Audio-CD (`NER5` + `CUEX`/`DAOX`/`AFNM`), raw 2352-byte sectors.
`nrg2iso` only handles data tracks and fails on these. This tool slices the PCM
directly using the `CUEX` LBAs and `AFNM` filenames, verified bit-identical vs
reference Python extractor.

## Use the app

1. Run `./build-app.sh` (requires Xcode in /Applications — SwiftUI macros don't
   build with CommandLineTools-only toolchain).
2. Drag `NRGExtractor.app` to `/Applications`.
3. Open it, drag `.nrg` files onto the window (or onto its Dock icon).
4. Output: `<discname>_wav/` next to each `.nrg`, e.g.
   `TNCD302-VoToi-ManhQuynh_wav/01. Vo Toi.wav`.

## Use the CLI

```bash
.build/out/Products/Release/nrg2wav input.nrg [output_dir]
# all discs:
for f in ~/Downloads/*/*.nrg; do .build/out/Products/Release/nrg2wav "$f"; done
```

## Convert WAV → FLAC

```bash
brew install ffmpeg
for f in *_wav/*.wav; do ffmpeg -i "$f" -c:a flac "${f%.wav}.flac"; done
```

## Layout

- `Sources/NRGCore/NRGExtractor.swift` — parser + extractor (shared)
- `Sources/nrg2wav/main.swift` — CLI
- `Sources/NRGExtractorApp/NRGExtractorApp.swift` — SwiftUI drag-drop UI
- `Info.plist`, `build-app.sh`
