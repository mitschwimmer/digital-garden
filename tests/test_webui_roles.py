"""Exercise the patched upstream role method without importing the entire application."""
import ast
import asyncio
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest


class Forbidden(Exception):
    pass


class RolesTest(unittest.TestCase):
    def test_first_and_sole_users_follow_idp_groups(self):
        patch_path, source_path = sys.argv[1:3]
        spec = importlib.util.spec_from_file_location("webui_patch", patch_path)
        patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patch)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["backend/open_webui/utils/oauth.py", "backend/open_webui/__init__.py"]:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(Path(source_path) / name, target)
            patch.patch(root)
            tree = ast.parse((root / "backend/open_webui/utils/oauth.py").read_text())
            method = next(node for node in ast.walk(tree)
                          if isinstance(node, ast.AsyncFunctionDef) and node.name == "get_user_role")
            config = SimpleNamespace(ENABLE_OAUTH_ROLE_MANAGEMENT=True,
                                     DEFAULT_USER_ROLE="pending", OAUTH_ROLES_CLAIM="groups",
                                     OAUTH_ALLOWED_ROLES=["ai-users", "admins"], OAUTH_ADMIN_ROLES=["admins"])
            count = 0

            async def runtime_config():
                return config

            async def num_users():
                return count

            globals_ = {"get_oauth_runtime_config": runtime_config,
                        "Users": SimpleNamespace(get_num_users=num_users),
                        "_get_roles_claim": lambda data, name: data.get(name),
                        "HTTPException": lambda *args, **kwargs: Forbidden(),
                        "status": SimpleNamespace(HTTP_403_FORBIDDEN=403),
                        "ERROR_MESSAGES": SimpleNamespace(ACCESS_PROHIBITED="forbidden"),
                        "OAUTH_ROLES_SEPARATOR": ",",
                        "log": SimpleNamespace(debug=lambda *args: None, warning=lambda *args: None)}
            exec(compile(ast.fix_missing_locations(ast.Module(body=[method], type_ignores=[])),
                         "upstream-role-method", "exec"), globals_)

            def role(user, groups):
                return asyncio.run(globals_["get_user_role"](None, user, {"groups": groups}))

            self.assertEqual(role(None, ["ai-users"]), "user")
            self.assertEqual(role(None, ["admins"]), "admin")
            for groups in [[], ["unrelated"]]:
                with self.assertRaises(Forbidden):
                    role(None, groups)
            count = 1
            existing = SimpleNamespace(role="admin")
            self.assertEqual(role(existing, ["ai-users"]), "user")
            with self.assertRaises(Forbidden):
                role(existing, [])
            with self.assertRaises(SystemExit):
                patch.patch(root)  # Version guard must reject applying twice.


if __name__ == "__main__":
    # Retain positional paths for the test, without treating them as unittest names.
    unittest.main(argv=[sys.argv[0]])
