# Common Simplified Chinese font coverage

ManusCC0 Regular, Medium and Bold stay primary. The glyph fallback `assets/template/fonts/ManusGameSC-Common.woff2` is a **992,160-byte WOFF2**, with a hard maximum of **1,000,000 bytes**. It covers **6,547 Unicode codepoints**: all 3,500 first-level and 3,000 second-level characters in the 2013 Table of General Standard Chinese Characters, plus 47 shipped UI/name/symbol characters. This targets common Simplified Chinese. Rare names, every CJK extension, Traditional Chinese, other scripts and emoji are not guaranteed.

The derivative is named ManusGameSC Common and retains Noto's SIL Open Font License. The full upstream authoring face must never enter the runtime export. System fallback is disabled; the small Web loader fonts and their source subsets remain separate and unchanged.

Run `python3 tools/sync_cjk_font.py --check` to verify the exact approved bytes, size ceiling, pinned character repertoire, license and all three font chains. Restore from the approved WOFF2 with `--source /path/to/ManusGameSC-Common.woff2`. The tool rejects oversized or different fonts. Extend the shared approved repertoire only through its central build/size validation; do not regenerate it from one game's UI text alone.
