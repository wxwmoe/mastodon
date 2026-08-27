#!/bin/bash
set -e

grep -Fqx "  throttle('throttle_media_proxy', limit: 30, period: 10.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "    req.throttleable_remote_ip if req.path.start_with?('/media_proxy')" src/config/initializers/rack_attack.rb
sed -i "/^  throttle('throttle_media_proxy', limit: 30, period: 10\.minutes) do |req|$/,/^  end$/c\  throttle('throttle_media_proxy_authenticated', limit: 600, period: 10.minutes) do |req|\n    (req.authenticated_user_id || req.warden_user_id) if req.path.start_with?('/media_proxy')\n  end\n\n  throttle('throttle_media_proxy_unauthenticated', limit: 30, period: 1.hour) do |req|\n    req.throttleable_remote_ip if req.path.start_with?('/media_proxy') \&\& !req.authenticated_user_id \&\& !req.warden_user_id\n  end" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_media_proxy_authenticated', limit: 600, period: 10.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "    (req.authenticated_user_id || req.warden_user_id) if req.path.start_with?('/media_proxy')" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_media_proxy_unauthenticated', limit: 30, period: 1.hour) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "    req.throttleable_remote_ip if req.path.start_with?('/media_proxy') && !req.authenticated_user_id && !req.warden_user_id" src/config/initializers/rack_attack.rb
