#!/bin/bash
set -e

grep -Fqx "  MAX_CHARS = 500" src/app/validators/status_length_validator.rb
sed -i "s|^  MAX_CHARS = 500$|  MAX_CHARS = 20000|" src/app/validators/status_length_validator.rb
grep -Fqx "  MAX_CHARS = 20000" src/app/validators/status_length_validator.rb
