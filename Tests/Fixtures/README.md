# CLI Test Fixtures

These directories back the scenarios in `scripts/test-cli.sh`. File *contents*
are irrelevant — only names matter. Each scenario copies a fixture to a fresh
temp directory, invokes `macrename`, and asserts on the resulting filenames.

Do not edit filenames here without updating the expected output in the script.
