#!/bin/bash
set -e

target="src/config/initializers/zzz_rate_limit_tiers.rb"
test ! -e "$target"

# 核对上游基数和窗口
grep -Fqx "  throttle('throttle_authenticated_api', limit: 1_500, period: 5.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_per_token_api', limit: 300, period: 5.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_authenticated_paging', limit: 300, period: 15.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_api_delete', limit: 30, period: 30.minutes) do |req|" src/config/initializers/rack_attack.rb
grep -Fqx "  throttle('throttle_media_proxy', limit: 30, period: 10.minutes) do |req|" src/config/initializers/rack_attack.rb

# 核对复用的辅助方法和常量
grep -Fqx "    def authenticated_user_id" src/config/initializers/rack_attack.rb
grep -Fqx "    def authenticated_token_id" src/config/initializers/rack_attack.rb
grep -Fqx "    def warden_user_id" src/config/initializers/rack_attack.rb
grep -Fqx "    def paging_request?" src/config/initializers/rack_attack.rb
grep -Fq "API_DELETE_REBLOG_REGEX =" src/config/initializers/rack_attack.rb
grep -Fq "API_DELETE_STATUS_REGEX =" src/config/initializers/rack_attack.rb

cat > "$target" <<'RUBY'
# frozen_string_literal: true

# 按注册年限逐年放宽用户访问限速：上限 = 上游基数 x 倍数
# 倍数 = min(1 + 斜率 x 注册年限, 封顶)，版主/管理员按满年限算
#
#   曲线 A  1 + 1x年限，封顶 x10（满 9 年）  用户总闸
#   曲线 B  1 + 2x年限，封顶 x20（满 10 年） 单令牌 / 分页 / 删嘟
#   曲线 C  1 + 4x年限，封顶 x40（满 10 年） 媒体代理
#
# initializer 按字母序加载，zzz_ 保证跑在 rack_attack.rb 之后，同名 throttle 直接被替换
# authenticated_user_id / authenticated_token_id / warden_user_id / paging_request? / api_request? 和 API_DELETE_*_REGEX 都是 rack_attack.rb 里定义好的
# throttle_api_media 只管 POST /api/v1/media（上传），未登录的几条 API/分页、注册登录密码组、以及未登录的 media_proxy，全部保持上游原值
class Rack::Attack
  class Request
    STAFF_ACCOUNT_YEARS = 10

    def rate_limit_user_id
      authenticated_user_id || warden_user_id
    end

    def rate_limit_years
      return @rate_limit_years if defined?(@rate_limit_years)

      user_id = rate_limit_user_id

      @rate_limit_years = user_id && Rails.cache.fetch("rate_limit_years:#{user_id}", expires_in: 1.hour) do
        user = User.find_by(id: user_id)

        if user.nil?
          0
        elsif user.role.can?(*UserRole::Flags::CATEGORIES[:moderation])
          STAFF_ACCOUNT_YEARS
        else
          ((Time.now.utc - user.created_at) / 1.year.to_i).floor
        end
      end
    end

    def rate_limit_tier(slope, cap)
      [1 + (slope * rate_limit_years.to_i), cap].min
    end

    def media_proxy_request?
      path.start_with?('/media_proxy')
    end
  end

  throttle('throttle_authenticated_api', limit: ->(req) { 1_500 * req.rate_limit_tier(1, 10) }, period: 5.minutes) do |req|
    req.authenticated_user_id if req.api_request?
  end

  throttle('throttle_per_token_api', limit: ->(req) { 300 * req.rate_limit_tier(2, 20) }, period: 5.minutes) do |req|
    req.authenticated_token_id if req.api_request?
  end

  throttle('throttle_authenticated_paging', limit: ->(req) { 300 * req.rate_limit_tier(2, 20) }, period: 15.minutes) do |req|
    req.authenticated_user_id if req.paging_request?
  end

  throttle('throttle_api_delete', limit: ->(req) { 30 * req.rate_limit_tier(2, 20) }, period: 30.minutes) do |req|
    req.authenticated_user_id if (req.post? && req.path.match?(API_DELETE_REBLOG_REGEX)) || (req.delete? && req.path.match?(API_DELETE_STATUS_REGEX))
  end

  throttle('throttle_media_proxy_authenticated', limit: ->(req) { 30 * req.rate_limit_tier(4, 40) }, period: 10.minutes) do |req|
    req.rate_limit_user_id if req.media_proxy_request?
  end

  throttle('throttle_media_proxy', limit: 30, period: 10.minutes) do |req|
    req.throttleable_remote_ip if req.media_proxy_request? && req.rate_limit_user_id.nil?
  end
end
RUBY

for name in throttle_authenticated_api throttle_per_token_api throttle_authenticated_paging throttle_api_delete throttle_media_proxy_authenticated throttle_media_proxy; do
  grep -Fq "throttle('${name}'" "$target"
done
