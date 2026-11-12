"""用小尺寸夹具检查生成归档、章节、PNG 与可重复性。"""

import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
import zlib


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "build_performance_epub", ROOT / "tool/build_performance_epub.py"
)
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class PerformanceEpubTest(unittest.TestCase):
    def test_archive_resources_and_single_long_chapter_are_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "small.epub"
            size = generator.build_epub(output, 3, 2, 8, 42)
            self.assertEqual(size, output.stat().st_size)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.infolist()[0].filename, "mimetype")
                self.assertEqual(archive.infolist()[0].compress_type, zipfile.ZIP_STORED)
                self.assertEqual(archive.read("mimetype"), b"application/epub+zip")
                self.check_documents(archive)
                for index in range(2):
                    self.check_png(archive.read(f"OEBPS/images/texture-{index:03d}.png"))

    def check_documents(self, archive):
        container = ET.fromstring(archive.read("META-INF/container.xml"))
        opf_path = next(node.attrib["full-path"] for node in container.iter()
                        if node.tag.endswith("}rootfile"))
        package = ET.fromstring(archive.read(opf_path))
        items = {node.attrib["id"]: node.attrib["href"]
                 for node in package.iter() if node.tag.endswith("}item")}
        for href in items.values():
            self.assertIn("OEBPS/" + href, archive.namelist())
        spine = [items[node.attrib["idref"]] for node in package.iter()
                 if node.tag.endswith("}itemref")]
        self.assertEqual(spine, ["cover.xhtml", "chapter.xhtml"])
        chapter = ET.fromstring(archive.read("OEBPS/chapter.xhtml"))
        sections = list(chapter.iter("{http://www.w3.org/1999/xhtml}section"))
        self.assertEqual(len(sections), 3)
        self.assertEqual([node.attrib["id"] for node in sections],
                         ["section-1", "section-2", "section-3"])
        paragraphs = ["".join(node.itertext()) for node in chapter.iter(
            "{http://www.w3.org/1999/xhtml}p") if not node.attrib]
        self.assertEqual(len(set(paragraphs)), 6)
        for node in chapter.iter("{http://www.w3.org/1999/xhtml}img"):
            self.assertIn("OEBPS/" + node.attrib["src"], archive.namelist())
        self.assertIn(b"break-before: page", archive.read("OEBPS/styles.css"))

    def check_png(self, data):
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        position, image_data = 8, bytearray()
        while position < len(data):
            length = struct.unpack(">I", data[position:position + 4])[0]
            kind = data[position + 4:position + 8]
            payload = data[position + 8:position + 8 + length]
            checksum = struct.unpack(">I", data[position + 8 + length:position + 12 + length])[0]
            self.assertEqual(checksum, zlib.crc32(kind + payload) & 0xffffffff)
            if kind == b"IHDR":
                self.assertEqual(struct.unpack(">IIBBBBB", payload), (8, 8, 8, 2, 0, 0, 0))
            if kind == b"IDAT":
                image_data.extend(payload)
            position += length + 12
        pixels = zlib.decompress(image_data)
        self.assertEqual(len(pixels), 8 * (1 + 8 * 3))
        self.assertEqual(pixels[::25], bytes(8))

    def test_same_parameters_produce_identical_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            files = [Path(directory) / f"sample-{index}.epub" for index in range(3)]
            for index, seed in enumerate((42, 42, 43)):
                generator.build_epub(files[index], 3, 2, 8, seed)
            self.assertEqual(files[0].read_bytes(), files[1].read_bytes())
            self.assertNotEqual(files[0].read_bytes(), files[2].read_bytes())

    def test_nonpositive_dimensions_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "invalid.epub"
            for dimensions in ((0, 2, 8), (3, 0, 8), (3, 2, 0)):
                with self.subTest(dimensions=dimensions), self.assertRaises(ValueError):
                    generator.build_epub(output, *dimensions)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
