#!/usr/bin/env python3
"""Seal staged router backups into the inventory, vault-encrypted.

The opnsense_backup role leaves each router's config.xml, in plaintext, at
<stage>/<inventory_hostname>.xml. For each one this script:

  1. encrypts it with the inventory's vault password, to
     <inventory>/backups/<site>/<inventory_hostname>/config.xml.vault, and
  2. deletes the plaintext once the ciphertext is written and decrypts back to
     the same bytes.

The password is asked for once, and is checked against a vault.yml committed
on the inventory's origin/main before anything is encrypted: a mistyped
password would otherwise produce a backup nobody can open, found out only on
the day it is needed. The check decrypts in memory and prints nothing of it.

Nothing is committed. Inventory changes go through a pull request, so the
script ends by printing the path to add.

Usage: vault-router-backup.py --stage DIR --inventory DIR --site SITE
"""

import argparse
import getpass
import os
import subprocess
import sys
from pathlib import Path

from ansible.errors import AnsibleError
from ansible.parsing.vault import VaultLib, VaultSecret


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

    staged = sorted(args.stage.glob("*.xml")) if args.stage.is_dir() else []
    if not staged:
        print(f"Nothing staged in {args.stage}; no router backup to seal.")
        return 0

    print("Staged router backups: " + ", ".join(p.stem for p in staged))
    check_name, check_blob = committed_vault_file(args.inventory)
    password = getpass.getpass("Inventory vault password: ").encode()
    vault = VaultLib([("default", VaultSecret(password))])
    try:
        vault.decrypt(check_blob)
    except AnsibleError:
        print(
            f"That password does not open origin/main:{check_name}. Nothing was encrypted; "
            f"the plaintext stays in {args.stage} - run `make seal-router-backup` to try again.",
            file=sys.stderr,
        )
        return 1

    written = []
    for src in staged:
        plaintext = src.read_bytes()
        if b"<opnsense>" not in plaintext:
            print(f"{src} is not an OPNsense configuration; left in place, not sealed.", file=sys.stderr)
            continue
        ciphertext = vault.encrypt(plaintext)
        if vault.decrypt(ciphertext) != plaintext:
            print(f"{src} did not decrypt back to itself; left in place, not sealed.", file=sys.stderr)
            continue
        dest = args.inventory / "backups" / args.site / src.stem / "config.xml.vault"
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(".vault.tmp")
        tmp.write_bytes(ciphertext)
        os.replace(tmp, dest)
        src.unlink()
        written.append(dest)
        print(f"Sealed {src.stem} -> {dest}")

    if written:
        rel = " ".join(str(p.relative_to(args.inventory)) for p in written)
        print(
            "\nCommit it through a pull request, on a branch from main:\n"
            f"  cd {args.inventory} && git add {rel}"
        )
    return 0 if len(written) == len(staged) else 1


if __name__ == "__main__":
    sys.exit(main())
