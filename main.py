#!/usr/bin/env python3
"""Muesli — local meeting transcription + dictation for macOS."""

import sys
import os

# Ensure the project root is on the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import MuesliApp


def main():
    print("=" * 50)
    print("  Muesli - Local Dictation & Meeting Notes")
    print("  Hold Left Cmd to dictate")
    print("=" * 50)
    app = MuesliApp()
    app.run()


if __name__ == "__main__":
    main()
