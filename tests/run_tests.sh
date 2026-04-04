#!/usr/bin/env bash
# Run all tests or a specific test file
# Usage: ./tests/run_tests.sh [test_file]
set -e

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_FILE="${1:-$TESTS_DIR}"

nvim --headless -u "$TESTS_DIR/minimal_init.lua" \
  -c "PlenaryBustedDirectory $TEST_FILE { minimal_init = '$TESTS_DIR/minimal_init.lua' }"
