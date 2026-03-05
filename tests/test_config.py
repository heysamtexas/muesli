import os
import json
import tempfile
from unittest.mock import patch
import config


class TestConfig:
    def setup_method(self):
        self._tmpdir = tempfile.mkdtemp()
        self._original_dir = config.CONFIG_DIR
        self._original_path = config.CONFIG_PATH
        config.CONFIG_DIR = self._tmpdir
        config.CONFIG_PATH = os.path.join(self._tmpdir, "config.json")

    def teardown_method(self):
        config.CONFIG_DIR = self._original_dir
        config.CONFIG_PATH = self._original_path

    def test_load_returns_defaults_when_no_file(self):
        cfg = config.load()
        assert cfg == config.DEFAULTS

    def test_save_and_load_roundtrip(self):
        cfg = config.load()
        cfg["hotkey"] = "ctrl+shift+space"
        config.save(cfg)

        loaded = config.load()
        assert loaded["hotkey"] == "ctrl+shift+space"
        # Other defaults preserved
        assert loaded["whisper_model"] == config.DEFAULTS["whisper_model"]

    def test_save_creates_directory(self):
        new_dir = os.path.join(self._tmpdir, "subdir")
        config.CONFIG_DIR = new_dir
        config.CONFIG_PATH = os.path.join(new_dir, "config.json")
        config.save({"test": True})
        assert os.path.exists(config.CONFIG_PATH)
