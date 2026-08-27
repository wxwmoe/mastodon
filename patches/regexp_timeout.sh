#!/bin/bash
set -e

grep -Fqx "    config.load_defaults 8.1" src/config/application.rb
sed -i 's|^    config.load_defaults 8.1$|&\n\n    Regexp.timeout = 3|' src/config/application.rb
grep -Fqx "    Regexp.timeout = 3" src/config/application.rb
