"""Protect localization when executable SQL is preceded by explanatory comments.

The query builder adds CTE documentation for maintainers. That prose must not
cause the localizer to emit two WITH clauses or lose recursive dependency walks.
Full SQL execution is covered separately by verify_database.py.
"""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "dashboard/tools"))
from english_locale import english_sql


class QueryBuildTests(unittest.TestCase):
    def test_leading_comments_keep_one_recursive_with(self):
        for header in ("-- Explain the snapshot.\n", "/* Document the dependency walk. */\n", "\n-- First\n-- Second\n"):
            original = header + "WITH RECURSIVE p AS (SELECT ci_id FROM dcmon.ci) SELECT * FROM p"
            result = english_sql(original)
            self.assertTrue(result.startswith(header + "WITH RECURSIVE localized_ci AS MATERIALIZED"))
            self.assertEqual(result.count("WITH "), 1)
            self.assertIn(",\np AS (SELECT ci_id FROM localized_ci)", result)


if __name__ == "__main__":
    unittest.main()
