# Hebrew PDF Text Extractor

A native macOS app that extracts text from PDFs (and a growing list of other document formats)
with extraction logic specifically tuned for Hebrew, lets you review/edit/split the result, and
exports it as UTF-8 `.txt`, an image, or several other document formats — see
[Supported formats](#supported-formats) below.

## Requirements

- macOS 14 (Sonoma) or later, to run the app
- Xcode 16 or later, to build it
- **Internet access the first time you build**, so Xcode can resolve the SwiftyTesseract Swift
  Package dependency (see below) — a ~219MB download.

## Building & running

1. Open `HebrewPDFExtractor.xcodeproj` in Xcode.
2. Select the **HebrewPDFExtractor** scheme (already selected by default).
3. Press **⌘R** to build and run.

The project is unsigned/local-only (no App Sandbox, no provisioning profile needed) — Xcode will
sign it "to run locally" automatically. It is not configured for App Store distribution.

Before shipping or sharing the app, change `PRODUCT_BUNDLE_IDENTIFIER` (currently
`com.example.HebrewPDFExtractor`) in the target's Build Settings to your own reverse-DNS
identifier.

## Using the app

1. **Add files** via the toolbar button, or drag-and-drop them anywhere in the window (the whole
   window is a drop target, with a highlighted overlay while dragging) — any mix of supported
   formats can go in the same batch, auto-detected by extension. Each row in the sidebar list has
   its own **✕** remove button (or right-click → Remove).
2. Optionally set **Max characters per line** (0 = no wrapping).
3. Click **Extract Text** to process every file in the list. Clicking it again always fully
   reprocesses everything (e.g. to pick up a changed max-chars setting or a different OCR choice)
   — it'll warn first if doing so would discard edits you've made in the preview.
   - For a PDF page with no extractable text (a scanned image), you'll be asked whether to run OCR
     on it, skip it, or flag it — and whether that choice should apply just to that page, the rest
     of that PDF, or the rest of the run. No other format triggers this; they're just read/parsed.
4. Select a file in the sidebar to preview its extracted text. The preview is a real editable text
   view:
   - **Edit directly** — changes are session-only (used for export, never written back to the
     source file on disk).
   - **⌘F to find** text within the preview (AppKit's standard inline find bar).
   - **Right-click → "Add Split Point Here"** to mark a point to divide the file at — add as many
     as you want, anywhere. A bar appears at the bottom showing how many segments that makes, with
     buttons to export all of them as separate `.txt` or `.jpg` files in one folder.
5. Click **Export…** and choose a format — asked fresh every time you export:
   - **Separate `.txt` file per source**, or **one combined `.txt` file** (the combine option only
     appears once 2+ files are completed — with just one, "combined" would be redundant).
   - **Extracted text as image (`.jpg`, one per source file)** — renders the corrected/imported
     text as a flat, right-to-left image via CoreText, e.g. for sharing a page of text visually.
   - **Original PDF pages as image (`.jpg`, one per page)** — rasterizes the source PDF itself,
     independent of the text-extraction pipeline. Hidden whenever the batch contains anything
     that isn't a PDF, since it has no meaning for plain text.
   - **Other Format…** — a third option opening the full list: PDF, PNG, RTF, Word (`.docx`),
     OpenDocument Text (`.odt`), HTML, and EPUB. See [Supported formats](#supported-formats).

   Every export remembers the last folder you saved to and defaults there next time — you can
   still pick somewhere else for any individual export, which just updates what's remembered.

## Supported formats

| | Import | Export |
|---|---|---|
| PDF | ✅ (text layer + OCR for scanned pages) | ✅ (text as image only — original pages export is separate) |
| Plain text (`.txt`) | ✅ (UTF-8, Windows-1255, ISO-8859-8) | ✅ |
| Rich Text (`.rtf`, `.rtfd`) | ✅ | ✅ (`.rtf`) |
| Word (`.doc`, `.docx`) | ✅ | ✅ (`.docx`) |
| OpenDocument Text (`.odt`) | ✅ | ✅ |
| HTML (`.html`, `.htm`) | ✅ | ✅ |
| EPUB | ✅ | ✅ |
| Image (`.jpg`/`.jpeg`, `.png`, `.tiff`/`.tif`, `.heic`) | ✅ (always OCR'd — see below) | ✅ (`.jpg`/`.png` only) |

RTF, DOC/DOCX, ODT, and HTML all go through `NSAttributedString`'s native AppKit readers/writers —
no third-party dependency, and verified directly (round-tripped real Hebrew RTL text through each,
inspected the actual file structure) that AppKit reads and writes all four correctly, including
right-to-left paragraph direction (e.g. `<w:bidi/>` in a `.docx`'s internal XML). EPUB is hand-built
rather than via a library: it's just a specifically-structured zip archive, and macOS ships
`/usr/bin/zip`/`/usr/bin/unzip`, so
**[`EPUBImporter`](HebrewPDFExtractor/Import/EPUBImporter.swift)**/
**[`EPUBExporter`](HebrewPDFExtractor/Export/EPUBExporter.swift)** shell out to those rather than
bundling a zip-reading library.

**Standalone image files** (a photo or scan, not a PDF page) always run straight through
**[`OCREngine`](HebrewPDFExtractor/Extraction/OCREngine.swift)** — a raster image has no text layer
to check first, so unlike a PDF page there's no "does this already have extractable text"
question, and no scanned-page skip/flag prompt either. Verified end-to-end (through the real
`ExtractionCoordinator`, not just the OCR engine in isolation) against both `.jpg` and `.png`
versions of the same synthetic Hebrew image — both recognized correctly. A later report that
dropping a `.jpg` "didn't work" prompted re-checking every image format specifically: all four
(`.jpg`/`.jpeg`, `.png`, `.tiff`/`.tif`, `.heic`) go through the exact same code path in
`ImageFileImporter`/`ExtractionCoordinator` — none is special-cased — and each was independently
round-tripped (write → drop-equivalent load via `CGImageSourceCreateWithURL`, matching what
`ImageFileImporter.loadCGImage` does) through a CLI harness with no failures, so the original issue
wasn't JPEG-specific and isn't expected to recur for any of the other three formats either.

**MOBI was considered and deliberately left out.** A real library exists (`libmobi`, with Swift
wrappers), but three things argued against it: its "write" support is documented as modifying an
*already-loaded* MOBI document rather than authoring a new one from plain text (not clearly the
right tool for export); it's LGPL-3.0, a meaningfully bigger distribution/licensing obligation than
Tesseract's Apache 2.0; and both available Swift wrappers have very little visible real-world
adoption to trust for correctness. If you actually need MOBI, ask — it's a deliberate scope
decision, not an oversight, and can be revisited.

## Importing a `.txt` file directly

Add a `.txt` file the same way as a PDF (drop zone or file picker) and it's routed to
**[`TextFileImporter`](HebrewPDFExtractor/Import/TextFileImporter.swift)** instead of the PDF/OCR
pipeline — it never goes through `PDFTextExtractor`, `LineReconstructor`, `ColumnDetector`, or
`OCREngine` at all.

- **Encoding**: tries UTF-8 first; if that fails to decode, falls back to Windows-1255 (the more
  common legacy Hebrew Windows encoding) and then ISO-8859-8. Both legacy encodings are `CFStringEncoding`
  constants that Swift doesn't expose as named `String.Encoding` members (and, unexpectedly,
  doesn't even import the symbolic C constants `kCFStringEncodingWindowsHebrew`/
  `kCFStringEncodingISOLatinHebrew` from `CFStringEncodingExt.h` at all) — worked around by using
  the constants' raw hex values directly, bridged via `CFStringConvertEncodingToNSStringEncoding`.
  Verified by round-tripping a real Hebrew string through actual Windows-1255-encoded bytes before
  relying on it.
- **Blank lines**: multiple consecutive blank lines in the source collapse to a single blank line.
- **Bidi correctness**: a plain text file has none of the visual-vs-logical ordering ambiguity a
  PDF's content stream can have — its bytes decode straight to Unicode codepoints in whatever order
  they were saved, which for any normally-authored Hebrew `.txt` file is already correct logical
  order. Rendering relies purely on CoreText/AppKit's own Unicode Bidi Algorithm implementation —
  the *exact same* mechanism `TextImageRenderer` already uses for the PDF→image export path (it
  never trusted PDFKit's ordering for its own drawing), so there's no behavioral difference between
  the two paths for mixed Hebrew/English/number lines or explicit bidi control characters
  (LRM/RLM/etc.) — both are standard inputs to the same algorithm.
- **No renderer changes were needed at all**: `TextImageRenderer.renderImage(for text: String, ...)`
  and `LineWrapper.wrap(_ text: String, ...)` already operated on a plain `String` with zero
  dependency on PDFKit-derived per-line bounding-box data, so a `.txt` file's decoded content is
  handed to them completely unmodified from the PDF path's usage.

## How the Hebrew-specific logic works

An earlier version of this extractor tried to fix RTL ordering by pairing
`PDFPage.characterBounds(at:)` with the same index into `PDFPage.string`, assuming both walk the
page's characters in the same order. Testing that against synthetic RTL PDFs (rendered, then
verified pixel-by-pixel) disproved it: `characterBounds(at:)` turned out to be indexed in raw
content-stream/drawing order, while `.string` already reflects PDFKit's *own* bidi-aware logical
reconstruction — a different permutation of the same characters. Pairing them by shared index
silently associated the wrong text with the wrong position, corrupting otherwise-correct
extractions rather than fixing anything.

The app instead uses `PDFSelection`, which is self-consistent by construction (a selection's
`.string` always matches what's actually within its `.bounds`):

- **[`LineReconstructor`](HebrewPDFExtractor/Extraction/LineReconstructor.swift)** — takes a
  selection over the whole page and calls `selectionsByLine()` to get one selection per visual
  line, each with reliable logically-ordered text and a bounding box. Niqqud, cantillation marks,
  and final-form letters are never touched individually — PDFKit's own reconstruction already
  handles them correctly, and this code only reads the resulting text, never edits it.
- **[`ColumnDetector`](HebrewPDFExtractor/Extraction/ColumnDetector.swift)** — what PDFKit does
  *not* get right is line **order**: `selectionsByLine()` returns lines in left-to-right column
  order regardless of script, which is backwards for a Hebrew multi-column layout. This looks for
  a vertical whitespace "gutter" wide enough and consistent enough down the page to be a real
  column break (not just an incidental short-line gap), then orders columns right-to-left and
  each column's lines top-to-bottom, re-deriving correct reading order purely from geometry.

Scanned/image-only pages go through a different path:
**[`OCREngine`](HebrewPDFExtractor/Extraction/OCREngine.swift)** renders the page to an image and
recognizes text with **Tesseract**, via the [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract)
Swift package, using bundled Hebrew + English trained data (`heb.traineddata` and `eng.traineddata`,
sourced from `HebrewPDFExtractor/tessdata/` in the project). SwiftyTesseract's default data source
expects those files at `Resources/tessdata/` in the app bundle, but this project's file-system-
synchronized group flattens loose resource files to the `Resources` root instead of preserving a
`tessdata` folder reference — confirmed by inspecting the built `.app`'s `Contents/Resources`
directly — so `OCREngine` supplies its own `LanguageModelDataSource` pointing at
`Bundle.main.resourceURL` directly rather than fighting that.

Apple's **Vision** framework was tried first, since it's the platform-preferred choice and was
what got asked for originally — but testing showed it cannot recognize Hebrew at all. A synthetic
PDF page containing a rasterized image of real Hebrew text ("שלום וברכה", so genuinely no text
layer, exactly the scanned-page scenario) was run through Vision's `VNRecognizeTextRequest`, and
`VNRecognizeTextRequest.supportedRecognitionLanguages()` was queried directly across every revision
Vision supports on this system:

| Input | Languages tried | Vision's output |
|---|---|---|
| "Invoice Number 4521" (English) | any | "Invoice Number 4521" — correct |
| "חשבונית מספר" (Hebrew) | `he`, `en-US`, even `ar-SA` | "UATICU UOGL" / "UnCICIL GOGL" — confident-looking, entirely wrong |

`he` (Hebrew) isn't in Vision's supported-language list at all, on any of its 3 revisions, on this
system — and critically, setting it doesn't error or return empty, it silently produces
plausible-looking wrong text. That's a worse failure mode than an error would be, and unacceptable
for an app whose whole purpose is Hebrew, so Tesseract replaces it. Tesseract's own page-
segmentation/reading-order handling is trusted directly for OCR output — unlike the text-layer
path above, there's no separate column-reordering pass on it.

**Third-party dependency note**: [SwiftyTesseract](https://github.com/SwiftyTesseract/SwiftyTesseract)
is archived/unmaintained upstream (its own README now recommends Vision instead — which is what
prompted trying Vision first here, before finding it doesn't support Hebrew). It still builds and
works today via its prebuilt `libtesseract` xcframework, pinned to the last tagged release (4.0.1).
Tesseract and its trained-data files are licensed Apache License 2.0. Bundling this pushes the
built app from ~1.4MB to roughly 26MB. **Building this project requires internet access the first
time**, so Xcode/SwiftPM can resolve and download the package (a ~219MB `xcframework` download).

This was verified against a synthetic scanned-page PDF (a rasterized image of real Hebrew text,
genuinely no text layer) via an isolated command-line harness — Tesseract correctly recognized
"שלום וברכה" from the image, an exact match, versus Vision's "ALIO ITLCU" on the same input.

**Niqqud (vowel points) significantly degrade OCR accuracy — root-caused directly, not just
observed.** A user reported "not so good" and slow results after exporting a Siddur segment as a
`.jpg` and re-importing it. Isolating the variables one at a time (font, image resolution, JPEG
compression, text length) found no effect from any of them — clean synthetic text without niqqud
OCR'd perfectly every time, at any resolution. Adding niqqud back in reproduced the exact failure
immediately: OCR that's perfect on plain Hebrew degrades to confidently-wrong Latin-alphabet
fragments once vowel points are present, because Tesseract's Hebrew model is trained mostly on
unpointed text — and niqqud is exactly what liturgical/biblical Hebrew (a Siddur, a Tanach) is
usually full of. Two concrete improvements followed from that diagnosis, both since bundled:
- **Switched the bundled trained data from `tessdata_fast` to `tessdata_best`** (Hebrew 3.7MB,
  English 15.4MB, up from 940KB/4.1MB) — meaningfully better on niqqud (e.g. correctly recognized
  the divine name יְהֹוָה where `fast` turned it into gibberish), though still not perfect.
- **`OCREngine` now upscales any image whose smaller dimension is under ~1200px by 2× before
  recognition** (plain `CGContext` interpolation — no genuine new detail, just resampling). This
  specifically matters for the reported scenario: this app's own "extracted text as image" export
  is sized for on-screen viewing (a modest resolution), so re-importing that exact file for OCR
  was feeding Tesseract a lower-resolution image than a real scan/photo typically is. Verified this
  helps even with pure interpolation, not just genuine higher-resolution re-rendering — before
  upscaling, one test sentence came back full of Latin garbage; after, only one word out of the
  whole sentence was still wrong.
- Combined, a real niqqud-heavy test sentence went from unreadable garbage throughout to only one
  garbled word, the rest correctly recognized as real Hebrew (with minor vowel-point placement
  imperfections a human could quickly fix).

**This is a real speed/accuracy tradeoff, made without asking first — flagging it here rather than
silently deciding.** `tessdata_best` is slower to run than `tessdata_fast` (roughly matching timing
was observed either way in testing, ~0.8–0.9s for a single short line — bigger for a full page),
and instance-caching (below) turned out not to be the dominant time cost, so accuracy came at some
real speed cost. Given quality was the more clearly broken thing, this seemed like the right
default — if OCR speed matters more to you than niqqud accuracy, `tessdata_fast` is a one-line
change in `heb.traineddata`/`eng.traineddata`.

**Also fixed while investigating: `OCREngine` was creating a brand-new `Tesseract` instance
(reloading trained data) on every single OCR call**, rather than once per app session — now cached
via a `lazy var`. This is a real, legitimate inefficiency fix, though testing showed it wasn't
actually the dominant factor in the reported slowness (repeated calls with the cached instance
timed about the same as the first) — the per-recognition computation itself, which scales with
trained-data size and image content, is the bigger cost. Not tested against a real-world scanned
photo/document (varying fonts, real scan quality, skew) — only synthetic renders — which would be
worth trying if you have one.

**[`LineWrapper`](HebrewPDFExtractor/Bidi/LineWrapper.swift)** applies the user's max-characters-
per-line setting once, at extraction/import time (not at export time — an earlier version wrapped
only at export to avoid a conflict with in-preview editing, but that conflict turned out to be
solved more directly by Extract always fully reprocessing and confirming before discarding edits;
wrapping at extraction time means the preview actually shows what you'll get, which editing then
happens on directly). Wraps only at whitespace. Maqaf (־, U+05BE) joins two Hebrew words with no
surrounding whitespace, so word-boundary wrapping already keeps a maqaf-joined compound intact
without any special-case handling.

**Further niqqud OCR investigation, and the "Hebrew-only OCR" toggle.** After the `tessdata_best` +
upscaling fixes above, three more angles were tested via the same isolated CLI-harness methodology:
- **Page segmentation mode (PSM) tuning** (`TessBaseAPISetPageSegMode` via the raw libtesseract C
  API — SwiftyTesseract's `Tesseract.Variable` doesn't expose PSM directly): no improvement.
  `PSM_SINGLE_BLOCK` matched the default `PSM_AUTO` exactly; `PSM_SPARSE_TEXT` was worse.
- **Character-set restriction** (`Tesseract.Variable.disallowlist`, blocking Latin letters + digits
  via `tessedit_char_blacklist`): this measurably helped. Default recognition on a niqqud-heavy test
  sentence hallucinated the digits "720" in place of a real word (מֶלֶךְ); blocking Latin/digits
  eliminated that specific failure. But this is a real tradeoff, not a strict improvement: this app
  also does English OCR, and a document with genuine English words or page/verse numbers would have
  that content forced into a wrong Hebrew-only reading if the restriction were always on.
- **Auto-detecting when it's safe to restrict** (run permissive OCR first, apply the restriction
  only if no Latin/digits appear in the result) was tried and rejected: the hallucination this is
  meant to fix is exactly what fools the detector. In testing, a pure-Hebrew sentence with zero
  English content had one niqqud-confused word misread as Latin garbage ("RYT"), which the detector
  read as "this page has real English" — skipping the restriction on precisely the page that needed
  it. A related idea (bump upscaling further when mixed content is detected) also didn't hold up:
  the earlier "3x/4x scale helps" result came from re-rendering text as a sharper vector at higher
  native resolution, not from interpolating an already-rasterized low-res image bigger — which is
  all the real OCR pipeline can actually do, and under that more realistic test, bumping scale
  further made output worse, not better.

Given no reliable *automatic* signal exists, character-set restriction is now a manual, explicit
per-run choice instead: the **"Hebrew-only OCR" toggle** in the sidebar (off by default). Turning it
on applies the digit/Latin blacklist described above for every OCR call in that run (both scanned
PDF pages and standalone image imports) — meaningfully cleaner recognition for a document you know
is pure Hebrew, at the cost of mangling any genuine English word or number if the document turns out
not to be. Leave it off for anything with mixed-language content, page numbers, or verse numbers.

**[`TextImageRenderer`](HebrewPDFExtractor/Export/TextImageRenderer.swift)** (used for both the
`.jpg`/`.png` and `.pdf` exports) initially only set `baseWritingDirection = .rightToLeft` on the
CoreText paragraph style, which correctly reverses word/character order *within* a line but leaves
the paragraph block itself left-aligned — so exported images read with each line's words in
correct Hebrew order, but the whole block flush against the left margin like an LTR layout. Fixed
by also explicitly setting `alignment = .right`; verified by rendering before/after and comparing
line start positions directly.

**Text direction is per paragraph, not forced.** The preview and the image/PDF exports pick each
paragraph's direction from its first strong letter (`TextDirection`), so Hebrew paragraphs are
right-to-left/right-aligned and English paragraphs left-to-right/left-aligned. Forcing
right-to-left on everything (an earlier fix for the preview, which a plain-text `NSTextView` otherwise
lays out left-aligned) wrongly right-aligned English. A paragraph with no letters at all (blank,
digits only) defaults to right-to-left. Verified with a mixed Hebrew/English sample in both the
renderer and the preview text view; pure-Hebrew output is pixel-identical to before.

**Exports never overwrite existing files.** Every export (`.txt`, `.jpg`, `.png`, PDF, Word/RTF/ODT/
HTML, EPUB, split segments and auto-split image parts) picks a free name: `name.ext`, else
`name (2).ext`, `name (3).ext`, … (`TextExporter.uniqueURL`). Previously exporting could silently
replace a file — including your original source: "Save as .txt" on a `.txt` offers the source's own
folder first and used the same filename, and two sources sharing a name (`book.pdf` + `book.txt`)
overwrote each other within one export. Verified with the debug driver: repeated exports of two
same-named sources produced four distinct files, and exporting a `.txt` into its own folder left the
original byte-identical. The one exception is "One combined .txt file", which uses the standard macOS
save panel and so already asks before replacing.

**"Plain punctuation in .txt (for MP3 players)" option.** A cheap MP3 player (Getco Zed5) showed the
apostrophe in `'s`/`'d` as Chinese characters. The curly apostrophe (’) is three bytes in UTF-8, and a
reader that assumes a legacy Chinese encoding (GBK) decodes those bytes as CJK; plain ASCII is the
same bytes in every encoding. This is the likely cause, inferred rather than confirmed on the device.
The Export menu now has a checkbox (remembered across launches) that, for `.txt` exports (separate,
combined and split segments), turns curly apostrophes/quotes (’ ‘ “ ”), dashes (– —), ellipsis (…),
bullets, non-breaking/thin spaces and zero-width characters into plain keyboard equivalents
(`PlainPunctuation`). Hebrew letters, niqqud, maqaf, geresh and gershayim are left alone. Verified
byte-for-byte via the debug driver (`plainpunct on|off`). Hebrew *encoding* on the device (which
legacy codepage it expects) is a separate question and is not handled.

**Long-text image/PDF export bug: CoreText reverses every line of a long block of Hebrew.** Exporting
a long text (e.g. a whole Siddur segment) as `.jpg`/`.png`/`.pdf` produced images where every line's
letters were spelled backwards (still right-aligned), even though the preview and `.txt` export were
correct. Rendering successively longer prefixes of the same text through `TextImageRenderer` showed
the flip starts somewhere between ~10,100 and ~10,300 characters — the *whole* block flips, including
its first lines, not just the later text. `TextImageRenderer` therefore now lays text out in
independent pieces of at most ~2,500 characters (split only at line breaks, see `chunks(of:)`),
stacked for images and flowed page-to-page for PDFs. Verified by comparing the top of a 60,000- and
120,000-character render against a known-correct short render, in a CLI harness and inside the real
app process (see "Debug hook" below). Not diagnosed: *why* CoreText does this at that size.

**JPEG can't be taller than 65,535 pixels — now warned about, with an optional auto-split.** A
segment long enough to render taller than that (the whole Siddur is ~115,000px at this width) used
to make the JPEG write fail silently, leaving an empty file. Both JPEG exports (the main Export menu
and "Export Segments as .jpg") now estimate the height first; if it won't fit, a dialog asks whether
to **split automatically** into numbered images (`name (1 of 2).jpg`, …, split only between
line-break-aligned pieces) or **skip** that file. Adding your own split points is still the way to
choose where it divides. Any JPEG write that fails is reported instead of ignored.

**Debug driver (Catan-style).** Launch with `HEBREW_DEBUG_DRIVER=<scratch dir>` and the real app
runs normally but also writes `status.txt` (documents, settings, preview text, exports, log) and
`snapshot.png` (the window's own rendering) into that folder about twice a second, and executes
commands written one per line to `command.txt`. All in-process: no Accessibility/Screen Recording
permission. Exports go to `<dir>/exports` (never your remembered export folder) and never show
dialogs (oversize JPEGs auto-split). Inert unless the variable is set. See
`HebrewPDFExtractor/DebugDriver.swift`.

```bash
D=/some/scratch/dir; mkdir -p "$D"
open -g -n --env HEBREW_DEBUG_DRIVER="$D" HebrewPDFExtractor.app   # -g: don't steal focus; -n: separate instance
echo "add /path/to/file.txt
extract
select 0
split 200
exportsegmentsjpg" > "$D/command.txt"
```

Commands: `add <path>`, `select <i>`, `extract`, `hebrewonly on|off`, `maxchars <n>`, `split <afterLine>`,
`exportjpg`, `exportsegmentsjpg`, `exportsegmentstxt`, `exportpdf`, `shot`, `quit`. Known gap: the
frosted-glass sidebar renders blank in `snapshot.png` (AppKit's offscreen capture can't draw it) —
its information is in `status.txt` instead. Clicking/typing/right-clicking aren't simulated; the
commands call the same model code the buttons do. Quit with the `quit` command (`pkill -x
HebrewPDFExtractor` also works) before relaunching after a rebuild, or the old process keeps running.

## Known limitations

- **Per-line text ordering is only as correct as PDFKit's own `PDFSelection` reconstruction.** For
  PDFs whose content stream never encoded correct Unicode/bidi information in the first place (some
  older or non-Apple PDF producers), PDFKit has no ground truth to reconstruct from, and this app
  has no independent way to fix that — it corrects line/column *order*, not what's inside a line.
- **Line/column detection is heuristic**, based on clustering line bounding boxes. Unusual layouts
  (rotated text, very tight line spacing, decorative/artistic typesetting) may be grouped
  incorrectly.
- **Password-protected PDFs**: the app attempts to unlock with an empty password (works for
  permissions-only restrictions) but does not prompt you to enter a password — an owner/user
  password-protected PDF will be reported as failed rather than prompting for credentials.
- **A single word/compound longer than the max-characters-per-line limit** is left on its own line
  rather than broken, since the app never breaks mid-word.
- **OCR is significantly less reliable on niqqud (vowel-pointed) Hebrew than on plain Hebrew** —
  root-caused directly (see above): Tesseract's Hebrew model is trained mostly on unpointed text.
  `tessdata_best` plus automatic upscaling of low-resolution images meaningfully improve this, but
  don't fully solve it — treat OCR output on liturgical/biblical (niqqud-heavy) text as a rough
  draft that needs manual review, not a reliable transcription. Plain (unpointed) Hebrew OCRs
  reliably.
- Tesseract generally needs reasonably clean, unskewed scans for good results; it does not perform
  its own deskew/binarization preprocessing here.
- **SwiftyTesseract is archived/unmaintained upstream.** It still works, but won't receive further
  updates from its author — see the "Third-party dependency note" above.
- **The "extracted text as image" export** renders one image per source file, sized to fit all of
  that file's text (however long); it does not paginate to match a source PDF's original page
  breaks.
- **Legacy encoding fallback for `.txt` import is a fixed try-order (Windows-1255, then
  ISO-8859-8), not true encoding detection.** A file that happens to decode "successfully" as the
  wrong legacy encoding (rare, but possible for very short files) would silently produce garbled
  text rather than an error, since any successful decode is accepted as final.
- **Blank-line collapsing in `.txt` import is unconditional** — there's no setting to preserve
  original spacing exactly, unlike the PDF path's line reconstruction which isn't touched this way.
- **Editing is session-only.** Changes made in the preview are used for export but never written
  back to the original source file on disk — reprocessing (Extract again, or remove-and-re-add)
  discards them, with a confirmation dialog warning you first.
- **Split points are literal marker text (`⟦✂ SPLIT HERE ✂⟧`), inserted directly into the editable
  content** — this is what makes them survive further edits with no separate position-tracking
  needed, but it also means a source document that happens to already contain that exact string
  would be mis-split. Vanishingly unlikely in practice, but not impossible.
- **EPUB import/export only handles the text**, not images, CSS styling, or multi-chapter
  structure beyond reading order — import concatenates all spine chapters' text in order; export
  produces one single-chapter EPUB per source file.
- **Rich-document formats (RTF/DOC/DOCX/ODT/HTML) preserve only plain text**, not the original
  formatting (fonts, bold/italic, tables, images) — consistent with this app's actual purpose
  (correct Hebrew text extraction), but worth knowing if you expected formatting to carry over.
- **MOBI is not supported**, a deliberate decision — see [Supported formats](#supported-formats)
  for the reasoning (LGPL licensing, uncertain write-from-scratch support, unproven Swift wrappers).
