import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "webdav_credentials", Path(__file__).parents[1] / "operations/check_webdav_credentials.py"
)
credentials = importlib.util.module_from_spec(spec)
spec.loader.exec_module(credentials)


class CredentialsTests(unittest.TestCase):
    def setUp(self):
        self.environment = dict(zip(credentials.VARIABLES, ("fixture-one", "fixture-two", "fixture-three")))

    def test_distinct_credentials_accepted(self):
        credentials.validate(self.environment)

    def test_each_missing_or_blank_credential_rejected(self):
        for name in credentials.VARIABLES:
            for value in (None, "", " \t"):
                with self.subTest(name=name, value=value):
                    environment = self.environment.copy()
                    if value is None:
                        del environment[name]
                    else:
                        environment[name] = value
                    with self.assertRaises(ValueError):
                        credentials.validate(environment)

    def test_each_shared_password_pair_rejected_without_disclosure(self):
        names = credentials.VARIABLES
        for first, second in ((0, 1), (0, 2), (1, 2)):
            with self.subTest(first=first, second=second):
                environment = self.environment.copy()
                environment[names[second]] = environment[names[first]]
                with self.assertRaises(ValueError) as error:
                    credentials.validate(environment)
                for password in environment.values():
                    self.assertNotIn(password, str(error.exception))


if __name__ == "__main__":
    unittest.main()
