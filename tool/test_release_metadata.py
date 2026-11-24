"""验证内部版本分配和交付文件名，不调用平台构建。"""

import tempfile
import unittest
from pathlib import Path

from release_metadata import artifact_name, reserve


class ReleaseMetadataTest(unittest.TestCase):
    def test_reserve_keeps_version_and_increments_number(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text("name: reader_mobile\nversion: 1.2.3+9\n",
                               encoding="utf-8")
            self.assertEqual(reserve(pubspec), ("1.2.3", 10))
            self.assertEqual(reserve(pubspec), ("1.2.3", 11))
            self.assertEqual(pubspec.read_text(encoding="utf-8"),
                             "name: reader_mobile\nversion: 1.2.3+11\n")

    def test_busy_reservation_does_not_modify_version(self):
        with tempfile.TemporaryDirectory() as directory:
            pubspec = Path(directory) / "pubspec.yaml"
            pubspec.write_text("version: 1.0.0+1\n", encoding="utf-8")
            pubspec.with_name(".release-version.lock").touch()
            with self.assertRaises(RuntimeError):
                reserve(pubspec)
            self.assertEqual(pubspec.read_text(encoding="utf-8"),
                             "version: 1.0.0+1\n")

    def test_both_platforms_share_reserved_number(self):
        self.assertEqual(artifact_name("arm64", "1.0.0", 2),
                         "阅微 Extend arm64 v1.0.0（2）.apk")
        self.assertEqual(artifact_name("winx64", "1.0.0", 2),
                         "阅微 Extend winx64 v1.0.0（2）.zip")


if __name__ == "__main__":
    unittest.main()
