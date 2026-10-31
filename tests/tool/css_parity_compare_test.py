"""CSS 对照行顶归一：字体盒应还原为 CSS 行盒，而不是扩大容差。"""
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'css_compare', ROOT / 'tool/css_parity/compare.py'
)
compare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compare)


class BrowserLineBoxTest(unittest.TestCase):
    def test_oversized_font_box_is_centered_back_into_line_box(self):
        line = {'x': 18, 'y': 116, 'w': 308, 'h': 31, 'baseline': 141}
        self.assertEqual(compare.browser_line_box_y(line, 24), 119.5)

    def test_font_box_within_line_height_keeps_browser_y(self):
        line = {'x': 18, 'y': 116, 'w': 308, 'h': 24, 'baseline': 141}
        self.assertEqual(compare.browser_line_box_y(line, 24), 116)

    def test_normalization_does_not_hide_a_real_line_top_offset(self):
        browser = [{'x': 18, 'y': 116, 'w': 308, 'h': 31, 'baseline': 141}]
        engine = [{'x': 18, 'y': 122, 'w': 308, 'h': 24}]
        self.assertEqual(
            compare.compare_lines(
                browser,
                engine,
                1.5,
                normalize_font_box_y=True,
            ),
            ['第1行 y: 浏览器 119.5 / 引擎 122'],
        )


class AtomicInlineBoxLinesTest(unittest.TestCase):
    def test_parent_with_atomic_inline_box_can_have_no_browser_lines(self):
        self.assertTrue(
            compare.browser_omits_atomic_inline_box_lines(
                {'hasInlineBox': True},
                [],
            )
        )

    def test_browser_lines_are_compared_when_available(self):
        self.assertFalse(
            compare.browser_omits_atomic_inline_box_lines(
                {'hasInlineBox': True},
                [{'y': 10}],
            )
        )

    def test_plain_block_without_lines_still_reports_mismatch(self):
        self.assertFalse(
            compare.browser_omits_atomic_inline_box_lines(
                {'hasInlineBox': False},
                [],
            )
        )


if __name__ == '__main__':
    unittest.main()
