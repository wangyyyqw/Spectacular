"""覆盖矩阵跨过两位数编号时，仍按用例编号排序。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'css_coverage', ROOT / 'tool/css_parity/coverage.py'
)
coverage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(coverage)


class CoverageOrderingTest(unittest.TestCase):
    def test_case_ids_use_numeric_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for case_id in ('100', '11', '99'):
                (root / f'{case_id}-sample.json').write_text('{}', encoding='utf-8')
            self.assertEqual(
                [case['id'] for case in coverage.load_cases(root)],
                ['11', '99', '100'],
            )


if __name__ == '__main__':
    unittest.main()
