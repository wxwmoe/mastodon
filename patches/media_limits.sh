#!/bin/bash
set -e

grep -Fqx "      pixels: 8_294_400, # 3840x2160px" src/app/models/media_attachment.rb
sed -i "s|^      pixels: 8_294_400, # 3840x2160px$|      pixels: 9_999_999, # 3840x2160px|" src/app/models/media_attachment.rb
grep -Fqx "      pixels: 9_999_999, # 3840x2160px" src/app/models/media_attachment.rb
grep -Fqx "  IMAGE_LIMIT = 16.megabytes" src/app/models/media_attachment.rb
sed -i "s|^  IMAGE_LIMIT = 16.megabytes$|  IMAGE_LIMIT = 99.megabytes|" src/app/models/media_attachment.rb
grep -Fqx "  IMAGE_LIMIT = 99.megabytes" src/app/models/media_attachment.rb
