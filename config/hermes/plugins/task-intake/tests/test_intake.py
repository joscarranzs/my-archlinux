"""Tests for the task-intake tool. Run: python3 -m unittest discover -s tests

The board is a throwaway SQLite file in a sandbox home: a suite run must never
touch the real ~/.hermes/kanban.db.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent

# Sandbox before any host import: kanban_db_path() falls back to
# <HERMES_HOME>/kanban/current when the env pin is missing.
SANDBOX = Path(tempfile.mkdtemp(prefix="task-intake-test-"))
os.environ["HERMES_HOME"] = str(SANDBOX)
os.environ["HERMES_KANBAN_DB"] = str(SANDBOX / "board" / "kanban.db")

AGENT_ROOT = Path(os.environ.get("HERMES_AGENT_ROOT") or (Path.home() / ".hermes" / "hermes-agent"))
if str(AGENT_ROOT) not in sys.path:
    sys.path.insert(0, str(AGENT_ROOT))

_spec = importlib.util.spec_from_file_location("task_intake", PLUGIN / "__init__.py")
assert _spec is not None and _spec.loader is not None
intake = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(intake)


class MatcherTest(unittest.TestCase):
    def test_accents_and_case_fold_to_the_same_title(self):
        self.assertEqual(intake.normalize("Corregir el límite de CARACTERES"),
                         intake.normalize("corregir el limite de caracteres"))
        self.assertGreaterEqual(intake.score("Corregir el límite de caracteres", None,
                                             "Corregir el limite de caracteres", None), 1.0)

    def test_stopwords_are_dropped(self):
        self.assertEqual(intake.tokens("el valor de la tarea"), {"valor", "tarea"})

    def test_reworded_intent_still_scores(self):
        s = intake.score("Subir el límite de caracteres del título",
                         "el campo corta en 50 y el contador resta desde 30",
                         "Corregir el error del valor límite de caracteres",
                         "El contador se pone negativo al pasar el límite del título")
        self.assertGreaterEqual(s, intake.CANDIDATE_THRESHOLD)
        self.assertLess(s, intake.DUP_THRESHOLD)

    def test_unrelated_titles_do_not_match(self):
        s = intake.score("Rediseñar la UI del panel de IA", None,
                         "Configurar el TTS de Nous", None)
        self.assertLess(s, intake.CANDIDATE_THRESHOLD)


class BoardTest(unittest.TestCase):
    def setUp(self):
        from hermes_cli import kanban_db_connect as kbc
        from hermes_cli import kanban_db as kb

        path = Path(os.environ["HERMES_KANBAN_DB"])
        if path.exists():
            path.unlink()
        with kbc.connect_closing() as conn:
            self.created = [
                kb.create_task(conn, title="Rediseñar la UI/UX del panel de IA",
                               body="Repensar el panel: jerarquía y estados", created_by="test"),
                kb.create_task(conn, title="Corregir el error del valor límite de caracteres",
                               body="El contador se pone negativo al pasar el límite del título",
                               created_by="test"),
            ]
            kb.add_comment(conn, self.created[1], "test", "reproducido")
            # done cards leave the open set and must not block a re-file
            kb.create_task(conn, title="Tarea ya hecha", body="x", created_by="test")
        ids = [row["id"] for row in self._rows()]
        done = [i for i in ids if i not in self.created][0]
        with kbc.connect_closing() as conn:
            conn.execute("UPDATE tasks SET status='done' WHERE id=?", (done,))
            conn.commit()

    def _rows(self):
        from hermes_cli import kanban_db_connect as kbc

        with kbc.connect_closing() as conn:
            return conn.execute("SELECT id FROM tasks").fetchall()

    # --- open

    def test_open_reads_both_lanes_compactly(self):
        out = intake._handle({"action": "open"})
        self.assertTrue(out.startswith("open 2 (2 new, 0 progress)"), out)
        self.assertIn("Rediseñar la UI/UX del panel de IA", out)
        self.assertNotIn("Tarea ya hecha", out)  # done is not open
        self.assertNotIn("|", out)  # no body unless asked

    def test_open_with_body_and_lane_filter(self):
        out = intake._handle({"action": "open", "with_body": True, "lane": "new", "limit": 1})
        self.assertEqual(len(out.splitlines()), 2, out)
        self.assertIn("|", out)

    def test_open_on_empty_board_says_so(self):
        from hermes_cli import kanban_db_connect as kbc

        with kbc.connect_closing() as conn:
            conn.execute("UPDATE tasks SET status='done'")
            conn.commit()
        self.assertTrue(intake._handle({"action": "open"}).strip().startswith("open 0"), 
                        intake._handle({"action": "open"}))

    # --- file

    def test_files_a_new_card_and_says_it_is_pending(self):
        out = intake._handle({"action": "file", "title": "Añadir atajo de teclado al buscador",
                              "body": "Ctrl+K abre el buscador de sesiones"})
        self.assertTrue(out.startswith('CREATED t_'), out)
        self.assertIn("unassigned", out)
        self.assertIn("Añadir atajo de teclado al buscador", intake._handle({"action": "open"}))

    def test_same_title_creates_nothing(self):
        out = intake._handle({"action": "file",
                              "title": "Corregir el error del valor límite de caracteres",
                              "body": "otra descripción distinta"})
        self.assertTrue(out.startswith("DUPLICATE t_"), out)
        self.assertIn("nothing created", out)
        self.assertEqual(len(intake._handle({"action": "open"}).splitlines()), 3)

    def test_reworded_intent_is_a_candidate_not_a_duplicate(self):
        out = intake._handle({"action": "file",
                              "title": "Arreglar el límite de caracteres del título",
                              "body": "El contador resta desde un número viejo y se pone negativo"})
        self.assertTrue(out.startswith("CANDIDATES"), out)
        self.assertIn("force=true", out)
        self.assertEqual(len(intake._handle({"action": "open"}).splitlines()), 3)

    def test_force_creates_despite_a_candidate(self):
        out = intake._handle({"action": "file", "force": True,
                              "title": "Arreglar el límite de caracteres del título",
                              "body": "El contador resta desde un número viejo y se pone negativo"})
        self.assertTrue(out.startswith("CREATED t_"), out)

    def test_done_cards_do_not_block_a_refile(self):
        out = intake._handle({"action": "file", "title": "Tarea ya hecha", "body": "x"})
        self.assertTrue(out.startswith("CREATED t_"), out)

    def test_title_over_the_panel_limit_is_refused(self):
        out = intake._handle({"action": "file", "title": "x" * (intake.TITLE_LIMIT + 1), "body": "ok"})
        self.assertTrue(out.startswith("ERROR title must be 1-80"), out)

    def test_body_over_the_panel_limit_is_refused(self):
        out = intake._handle({"action": "file", "title": "Título válido",
                              "body": "y" * (intake.BODY_LIMIT + 1)})
        self.assertTrue(out.startswith("ERROR body must be 1-200"), out)

    def test_missing_body_is_refused(self):
        out = intake._handle({"action": "file", "title": "Sin cuerpo"})
        self.assertTrue(out.startswith("ERROR body"), out)

    # --- category axis

    def _category_of(self, task_id):
        from hermes_cli import kanban_db_connect as kbc

        with kbc.connect_closing() as conn:
            return conn.execute("SELECT category FROM tasks WHERE id = ?", (task_id,)).fetchone()[0]

    def test_category_lands_on_the_created_row(self):
        out = intake._handle({"action": "file", "title": "Categorizar la bandeja de entrada",
                              "body": "Cada card lleva C# y P#", "category": "C2", "priority": 3})
        self.assertTrue(out.startswith("CREATED t_"), out)
        self.assertIn("C2", out)
        task_id = out.split()[1]
        self.assertEqual(self._category_of(task_id), 2)
        self.assertIn("C2 P3", intake._handle({"action": "open"}))

    def test_category_accepts_a_bare_number(self):
        out = intake._handle({"action": "file", "title": "Numero suelto de categoria",
                              "body": "c2 y 2 valen lo mismo", "category": 2})
        self.assertRegex(out, r"^CREATED t_[0-9a-f]+ C2 ")

    def test_category_is_unclassified_when_omitted(self):
        out = intake._handle({"action": "file", "title": "Sin categoria explicita",
                              "body": "cae en C0"})
        self.assertRegex(out, r"^CREATED t_[0-9a-f]+ C0 ")
        self.assertEqual(self._category_of(out.split()[1]), 0)

    def test_category_outside_the_axis_is_refused(self):
        out = intake._handle({"action": "file", "title": "Categoria invalida",
                              "body": "C9 no existe", "category": "C9"})
        self.assertTrue(out.startswith("ERROR category must be C0..C4"), out)
        self.assertNotIn("Categoria invalida", intake._handle({"action": "open"}))

    def test_open_orders_by_category_then_priority(self):
        # Titles far enough apart that the dedupe cannot see them as one intent.
        intake._handle({"action": "file", "title": "Archivar capturas viejas", "body": "c4 p0",
                        "category": "C4"})
        intake._handle({"action": "file", "title": "Revisar el arranque del compositor", "body": "c1 p2",
                        "category": "C1", "priority": 2})
        intake._handle({"action": "file", "title": "Mapear atajos del buscador", "body": "c1 p1",
                        "category": "C1", "priority": 1})
        lines = intake._handle({"action": "open"}).splitlines()[1:]
        # "id status assignee C# P# title" -- title is the sixth field, and it
        # may contain spaces of its own.
        titles = [line.split(" ", 5)[5] for line in lines]
        first = titles.index("Mapear atajos del buscador")
        second = titles.index("Revisar el arranque del compositor")
        optional = titles.index("Archivar capturas viejas")
        self.assertLess(first, second, titles)   # same C1: P1 before P2
        self.assertLess(second, optional, titles)  # C1 before C4

    def test_unknown_action(self):
        self.assertIn("ERROR action", intake._handle({"action": "borrar"}))


class RegistrationTest(unittest.TestCase):
    def test_register_exposes_one_tool(self):
        calls = {}

        class Ctx:
            def register_tool(self, **kw):
                calls.update(kw)
                return None

        intake.register(Ctx())
        self.assertEqual(calls["name"], "task_intake")
        self.assertEqual(calls["toolset"], "task_intake")
        self.assertIs(calls["handler"], intake._handle)
        self.assertEqual(calls["schema"]["parameters"]["required"], ["action"])


if __name__ == "__main__":
    unittest.main()
