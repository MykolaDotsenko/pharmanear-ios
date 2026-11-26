"""Lays the UI test screenshots side by side in one small JPEG, for reviewers who cannot download artifacts.

Usage: contact-sheet.py <exported attachments dir> [<start screens dir>] <output.jpg>
Needs Pillow. CI runs it only when a manual run asks for it (the log_screenshots input).
"""

import json
import sys
from pathlib import Path

from PIL import Image

# Screens in reading order, by the name each UI test gives its screenshot.
WANTED = ["Turku results", "Map preview", "Radar"]
WIDTH = 200


def attachments(folder: Path) -> dict[str, Path]:
    found = {}
    for test in json.loads((folder / "manifest.json").read_text()):
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            for wanted in WANTED:
                if name.startswith(wanted + "_") and wanted not in found:
                    found[wanted] = folder / item["exportedFileName"]
    return found


def main() -> None:
    *sources, output = sys.argv[1:]
    found = attachments(Path(sources[0]))
    images = [found[name] for name in WANTED if name in found]
    if len(sources) > 1:
        images += sorted(Path(sources[1]).glob("iphone-dark.png"))
    tiles = []
    for path in images:
        image = Image.open(path).convert("RGB")
        tiles.append(image.resize((WIDTH, round(image.height * WIDTH / image.width)), Image.LANCZOS))
    if not tiles:
        sys.exit("No screenshots found")
    sheet = Image.new("RGB", (WIDTH * len(tiles) + 8 * (len(tiles) - 1), max(t.height for t in tiles)), "white")
    for index, tile in enumerate(tiles):
        sheet.paste(tile, (index * (WIDTH + 8), 0))
    sheet.save(output, quality=50, optimize=True)
    print(f"{len(tiles)} screens: {', '.join(p.stem for p in images)}")


if __name__ == "__main__":
    main()
