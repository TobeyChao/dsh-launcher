#!/usr/bin/env python3
"""Export both platforms' icons from the checked-in PNG masters.

Requires Python 3.9+ and Pillow: python3 -m pip install Pillow
Only resamples/encodes the artwork; never redraws or regenerates the design.
"""
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / 'assets/icons'
MAC_ICONS = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
ICO_SIZES = [(s, s) for s in (16, 24, 32, 48, 64, 128, 256)]


def load_master(name):
    with Image.open(ROOT / 'assets/branding' / name) as source:
        if source.width != source.height or source.width < 1024:
            raise ValueError(f'{name}: expected a square master of at least 1024px')
        if source.mode != 'RGBA' or source.getchannel('A').getextrema() != (0, 255):
            raise ValueError(f'{name}: expected artwork with transparent margins')
        return source.copy()


def save_png(source, path, size):
    source.resize((size, size), Image.Resampling.LANCZOS).save(path, optimize=True)


def main():
    app = load_master('app_icon_source.png')
    tray = load_master('tray_icon_source.png')
    ICONS.mkdir(parents=True, exist_ok=True)
    save_png(app, ICONS / 'app_icon.png', 256)
    save_png(app, ICONS / 'tray_icon.png', 256)
    # macOS uses only the alpha silhouette, tinted by the system in light/dark mode.
    save_png(tray, ICONS / 'tray_icon_template.png', 44)
    app.save(ICONS / 'tray_icon.ico', format='ICO', sizes=ICO_SIZES)
    shutil.copyfile(ICONS / 'tray_icon.ico',
                    ROOT / 'windows/runner/resources/app_icon.ico')
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(app, MAC_ICONS / f'app_icon_{size}.png', size)
    print('Exported Windows ICO, macOS AppIcon, UI and tray icons.')


if __name__ == '__main__':
    main()
