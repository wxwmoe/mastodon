#!/bin/bash
set -e

grep -Fqx "  MAX_OPTIONS      = 4" src/app/validators/poll_options_validator.rb
sed -i "s|^  MAX_OPTIONS      = 4$|  MAX_OPTIONS      = 16|" src/app/validators/poll_options_validator.rb
grep -Fqx "  MAX_OPTIONS      = 16" src/app/validators/poll_options_validator.rb
