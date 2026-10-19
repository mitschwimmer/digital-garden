"""Guard the credential boundary and client environment of the Pi launcher."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import urlsplit


SOURCE = Path(__file__).resolve().parents[1] / "operations/agent_session.py"
spec = importlib.util.spec_from_file_location("agent_session", SOURCE)
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.token = root / "token"
        self.token.write_text("av_sess_test_session\n")
        self.token.chmod(0o640)
        self.ca = root / "ca.pem"
        self.ca.write_text("test bundle")
        self.config = dict(caReady=True, tokenFile=str(self.token), caBundle=str(self.ca),
                           proxyHost="10.203.0.1", proxyPort=14322, vault="pi")

    def test_refuses_launch_until_ca_is_deployed(self):
        self.config["caReady"] = False
        with self.assertRaisesRegex(ValueError, "reviewed vault"):
            session.session_environment(self.config, {})

    def test_overrides_proxy_bypass_and_unifies_client_trust(self):
        env = session.session_environment(self.config, {
            "http_proxy": "http://old.invalid", "NO_PROXY": "*", "no_proxy": "*",
            "GH_TOKEN": "old-token", "PATH": "/bin",
        })
        proxy = urlsplit(env["HTTPS_PROXY"])
        self.assertEqual((proxy.hostname, proxy.port, proxy.username, proxy.password),
                         ("10.203.0.1", 14322, "av_sess_test_session", "pi"))
        self.assertEqual(env["HTTP_PROXY"], env["http_proxy"])
        self.assertEqual(env["HTTPS_PROXY"], env["https_proxy"])
        self.assertEqual(env["NO_PROXY"], "localhost,127.0.0.1")
        self.assertEqual(env["no_proxy"], env["NO_PROXY"])
        for key in ("SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS", "GIT_SSL_CAINFO",
                    "NPM_CONFIG_CAFILE", "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE"):
            self.assertEqual(env[key], str(self.ca))
        self.assertEqual(env["GH_TOKEN"], "__github_pat__")
        self.assertEqual(env["PATH"], "/bin")

    def test_refuses_world_readable_or_missing_tokens(self):
        self.token.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "other users"):
            session.session_environment(self.config, {})
        self.token.unlink()
        with self.assertRaises(FileNotFoundError):
            session.session_environment(self.config, {})

    def test_rejects_invalid_tokens_without_echoing_them(self):
        for token in ("", "av_agt_private", "av_sess_secret\ninjected", "malformed-secret"):
            self.token.write_text(token)
            with self.assertRaises(ValueError) as error:
                session.session_environment(self.config, {})
            if token:
                self.assertNotIn(token, str(error.exception))

    def test_executes_child_with_proxy_env_without_token_in_arguments(self):
        config_file = Path(self.tmp.name) / "config.json"
        config_file.write_text(json.dumps(self.config))
        # Real exec verifies arguments and environment; do not emit the proxy URL.
        code = ("import os,sys; "
                "assert os.environ['GH_TOKEN']=='__github_pat__'; "
                "assert os.environ['https_proxy']==os.environ['HTTPS_PROXY']; "
                "assert 'av_sess_test_session' not in repr(sys.argv); print('ready')")
        result = subprocess.run([sys.executable, str(SOURCE), str(config_file),
                                 "/unused/pi", "--", sys.executable, "-c", code],
                                check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout.strip(), "ready")
        self.assertNotIn("av_sess_test_session", result.stdout + result.stderr)

    def test_forwards_pi_arguments_to_the_default_executable(self):
        config_file = Path(self.tmp.name) / "config.json"
        config_file.write_text(json.dumps(self.config))
        result = subprocess.run([sys.executable, str(SOURCE), str(config_file),
                                 sys.executable, "-c", "print('pi arguments work')"],
                                check=True, text=True, capture_output=True)
        self.assertEqual(result.stdout.strip(), "pi arguments work")


if __name__ == "__main__":
    unittest.main()
