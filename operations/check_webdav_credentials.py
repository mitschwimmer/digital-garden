"""Reject missing or shared WebDAV passwords before the listener starts.

Reads systemd's runtime environment only; never prints credential values.
"""

import os


VARIABLES = (
    "WEBDAV_HENNER_PASSWORD",
    "WEBDAV_CLAUDI_PASSWORD",
    "WEBDAV_ELMO_PASSWORD",
)


def validate(environment):
    passwords = [environment.get(name, "") for name in VARIABLES]
    if not all(password.strip() for password in passwords):
        raise ValueError("All three WebDAV passwords must be set and nonempty.")
    if len(set(passwords)) != len(VARIABLES):
        raise ValueError("Each WebDAV account must have a distinct password.")


if __name__ == "__main__":
    try:
        validate(os.environ)
    except ValueError as error:
        raise SystemExit(str(error)) from None
