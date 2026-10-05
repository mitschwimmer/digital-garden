"""Small, version-checked fixes for the pinned WebUI 0.11.4 source."""
from pathlib import Path
import sys


def replace(path, before, after, count=1):
    source = path.read_text()
    if source.count(before) != count:
        raise SystemExit("Pinned WebUI source changed; review patch: " + str(path))
    path.write_text(source.replace(before, after))


def patch(root):
    oauth = root / "backend/open_webui/utils/oauth.py"
    # Native OAuth role management must apply to first and sole users too.
    replace(oauth, "if user and user_count == 1:",
            "if not auth_config.ENABLE_OAUTH_ROLE_MANAGEMENT and user and user_count == 1:")
    replace(oauth, "if not user and user_count == 0:",
            "if not auth_config.ENABLE_OAUTH_ROLE_MANAGEMENT and not user and user_count == 0:")
    replace(oauth, "if await Users.get_num_users(db=db) == 1:",
            "if not auth_config.ENABLE_OAUTH_ROLE_MANAGEMENT and await Users.get_num_users(db=db) == 1:")
    replace(oauth, "if access_token is not None and not oauth_roles and oauth_allowed_roles",
            "if not oauth_roles and oauth_allowed_roles")
    # The upstream CLI does not expose an access-log switch; callback URLs contain codes.
    replace(root / "backend/open_webui/__init__.py", "forwarded_allow_ips='*',",
            "forwarded_allow_ips='*', access_log=False,", count=2)


if __name__ == "__main__":
    patch(Path(sys.argv[1]))
