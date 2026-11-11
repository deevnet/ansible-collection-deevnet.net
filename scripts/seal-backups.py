#!/usr/bin/env python3
"""Seal staged device backups into the inventory, vault-encrypted.

The backup roles leave each device's backup, in plaintext, in the staging
directory, named after its inventory host:

  <host>.xml   opnsense_backup: the router's config.xml
  <host>.cfg   omada_backup: the Omada controller's settings backup

For each one this script:

  1. encrypts it with the inventory's vault password, to
     <inventory>/backups/<site>/<host>/<name>.vault, and
  2. deletes the plaintext once the ciphertext is written and decrypts back to
     the same bytes.

The password is asked for once, and is checked against a vault.yml committed
on the inventory's origin/main before anything is encrypted: a mistyped
password would otherwise produce a backup nobody can open, found out only on
the day it is needed. The check decrypts in memory and prints nothing of it.

Vault encryption is salted, so the same plaintext never encrypts to the same
file. A backup whose settings match the one already in the inventory is
therefore not rewritten: a run that changed nothing leaves nothing to commit.
For a router, the <revision> stamp OPNsense writes on every save is not a
setting and is left out of that comparison.

Nothing is committed. Inventory changes go through a pull request, so the
script ends by printing the paths to add.

Usage: seal-backups.py --stage DIR --inventory DIR --site SITE
"""

import argparse
import getpass
import os
import re
import subprocess
import sys
from pathlib import Path

from ansible.errors import AnsibleError
from ansible.parsing.vault import VaultLib, VaultSecret

# OPNsense stamps every save with a <revision> block (time, user, description),
# so two saves of the same configuration differ there. It says when the file was
# written, not what the router does, so it is left out of the comparison.
_REVISION = re.compile(rb"<revision>.*?</revision>", re.DOTALL)


def _opnsense_settings(b: bytes) -> bytes:
    return _REVISION.sub(b"", b)


# Staged suffix -> (file name in the inventory, check the plaintext must pass,
# what it is, what of it is compared with the committed backup)
KINDS = {
    ".xml": ("config.xml.vault", lambda b: b"<opnsense>" in b, "an OPNsense configuration", _opnsense_settings),
    ".cfg": ("omada-backup.cfg.vault", lambda b: len(b) > 0, "a non-empty Omada backup", lambda b: b),
}


def committed_vault_file(inventory: Path) -> tuple[str, bytes]:
    """Return the path and contents of one vault.yml on origin/main."""
    names = subprocess.run(
        ["git", "-C", str(inventory), "ls-tree", "-r", "--name-only", "origin/main"],
        check=True, capture_output=True, text=True,
    ).stdout.split()
    for name in names:
        if name.endswith("vault.yml"):
            blob = subprocess.run(
                ["git", "-C", str(inventory), "show", f"origin/main:{name}"],
                check=True, capture_output=True,
            ).stdout
            if blob.startswith(b"$ANSIBLE_VAULT"):
                return name, blob
    sys.exit(f"No encrypted vault.yml on origin/main in {inventory} to check the password against.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--site", required=True)
    args = parser.parse_args()

    staged = sorted(p for p in args.stage.glob("*") if p.suffix in KINDS) if args.stage.is_dir() else []
    if not staged:
        print(f"Nothing staged in {args.stage}; no backup to seal.")
        return 0

    print("Staged backups: " + ", ".join(p.name for p in staged))
    check_name, check_blob = committed_vault_file(args.inventory)
    # The play asked for the vault password already; this second prompt is easy to
    # miss at the end of a long run, so say what it is for.
    print("\nSealing the backups above into the inventory. The play is done; this needs the vault password again.")
    password = getpass.getpass("Inventory vault password (to seal): ").encode()
    vault = VaultLib([("default", VaultSecret(password))])
    try:
        vault.decrypt(check_blob)
    except AnsibleError:
        print(
            f"That password does not open origin/main:{check_name}. Nothing was encrypted; "
            f"the plaintext stays in {args.stage} - run `make seal-backups` to try again.",
            file=sys.stderr,
        )
        return 1

    written, failed = [], 0
    for src in staged:
        dest_name, valid, what, settings = KINDS[src.suffix]
        plaintext = src.read_bytes()
        if not valid(plaintext):
            print(f"{src} is not {what}; left in place, not sealed.", file=sys.stderr)
            failed += 1
            continue
        dest = args.inventory / "backups" / args.site / src.stem / dest_name
        if dest.exists():
            try:
                unchanged = settings(vault.decrypt(dest.read_bytes())) == settings(plaintext)
            except AnsibleError:
                unchanged = False
            if unchanged:
                src.unlink()
                print(f"{src.stem}: unchanged since {dest}; nothing to commit.")
                continue
        ciphertext = vault.encrypt(plaintext)
        if vault.decrypt(ciphertext) != plaintext:
            print(f"{src} did not decrypt back to itself; left in place, not sealed.", file=sys.stderr)
            failed += 1
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name(dest.name + ".tmp")
        tmp.write_bytes(ciphertext)
        os.replace(tmp, dest)
        src.unlink()
        written.append(dest)
        print(f"Sealed {src.name} -> {dest}")

    if written:
        rel = " ".join(str(p.relative_to(args.inventory)) for p in written)
        print(
            "\nCommit it through a pull request, on a branch from main:\n"
            f"  cd {args.inventory} && git add {rel}"
        )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
