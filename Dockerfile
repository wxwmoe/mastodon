FROM tootsuite/mastodon:v4.1.4

COPY --chown=991:991 ./icons /opt/mastodon/app/javascript/icons
COPY --chown=991:991 ./images /opt/mastodon/app/javascript/images

RUN echo "修改字数上限" \
  && sed -i "s|MAX_CHARS = 500|MAX_CHARS = 20000|" /opt/mastodon/app/validators/status_length_validator.rb \
  && sed -i "s|length(fulltext) > 500|length(fulltext) > 20000|" /opt/mastodon/app/javascript/mastodon/features/compose/components/compose_form.js \
  && sed -i "s|CharacterCounter max={500}|CharacterCounter max={20000}|" /opt/mastodon/app/javascript/mastodon/features/compose/components/compose_form.js \
  && echo "修改媒体上限" \
  && sed -i "s|MAX_IMAGE_PIXELS = 2073600|MAX_IMAGE_PIXELS = 9999999|" /opt/mastodon/app/javascript/mastodon/utils/resize_image.js \
  && sed -i "s|pixels: 2_073_600|pixels: 9_999_999|" /opt/mastodon/app/models/media_attachment.rb \
  && sed -i "s|IMAGE_LIMIT = 10|IMAGE_LIMIT = 80|" /opt/mastodon/app/models/media_attachment.rb \
  && sed -i "s|VIDEO_LIMIT = 40|VIDEO_LIMIT = 100|" /opt/mastodon/app/models/media_attachment.rb \
  && echo "修改投票上限" \
  && sed -i "s|options.size >= 4|options.size >= 16|" /opt/mastodon/app/javascript/mastodon/features/compose/components/poll_form.js \
  && sed -i "s|MAX_OPTIONS      = 4|MAX_OPTIONS      = 16|" /opt/mastodon/app/validators/poll_validator.rb \
  && echo "加入 No-More-Sidebar-in-Mastodon-4.0 样式" \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-no-more-sidebar \
  && wget -nv https://raw.githubusercontent.com/AkazaRenn/No-More-Sidebar-in-Mastodon-4.0/main/css/bottombar.css -O /opt/mastodon/app/javascript/styles/mastodon-no-more-sidebar/bottombar.scss \
  && echo -e "@import 'application';\n@import 'mastodon-no-more-sidebar/bottombar';" > /opt/mastodon/app/javascript/styles/mastodon-dark.scss \
  && echo -e "@import 'mastodon-no-more-sidebar/bottombar';" >> /opt/mastodon/app/javascript/styles/contrast.scss \
  && echo -e "@import 'mastodon-no-more-sidebar/bottombar';" >> /opt/mastodon/app/javascript/styles/mastodon-light.scss \
  && sed -i "s|application|mastodon-dark|" /opt/mastodon/config/themes.yml \
  && echo "加入 Mastodon (Sakura) 主题" \
  && sed -i "s|#6364FF|#f596aa|" /opt/mastodon/app/views/layouts/application.html.haml \
  && sed -i "s|#191b22|#fedfe1|" /opt/mastodon/app/views/layouts/application.html.haml \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-sakura \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light/diff.scss /opt/mastodon/app/javascript/styles/mastodon-sakura/diff.scss \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light/variables.scss /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#9baec8|#b5495b|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#d9e1e8|#fedfe1|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#6364ff|#f596aa|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#858afa|#eb7a77|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#b0c0cf|#feeeed|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#9bcbed|#f8c3cd|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light.scss /opt/mastodon/app/javascript/styles/mastodon-sakura.scss \
  && sed -i "s|light|sakura|" /opt/mastodon/app/javascript/styles/mastodon-sakura.scss \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon (Sakura)' /opt/mastodon/config/locales/en.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-CN.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-TW.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-HK.yml \
  && echo -e "mastodon-sakura: styles/mastodon-sakura.scss" >> /opt/mastodon/config/themes.yml \
  && echo "加入 Mastodon Bird UI 主题" \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-bird-ui \
  && wget -nv https://raw.githubusercontent.com/ronilaukkarinen/mastodon-bird-ui/mastodon-4.1.2-stable/layout-single-column.css -O /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && wget -nv https://raw.githubusercontent.com/ronilaukkarinen/mastodon-bird-ui/mastodon-4.1.2-stable/layout-multiple-columns.css -O /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && sed -i 's/theme-contrast/theme-mastodon-bird-ui-contrast/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && sed -i 's/theme-mastodon-light/theme-mastodon-bird-ui-light/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && sed -i 's/theme-contrast/theme-mastodon-bird-ui-contrast/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && sed -i 's/theme-mastodon-light/theme-mastodon-bird-ui-light/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && echo -e "@import 'application';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-dark.scss \
  && echo -e "@import 'mastodon-light/variables';\n@import 'application';\n@import 'mastodon-light/diff';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-light.scss \
  && echo -e "@import 'contrast/variables';\n@import 'application';\n@import 'contrast/diff';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-contrast.scss \
  && echo -e "mastodon-bird-ui-dark: styles/mastodon-bird-ui-dark.scss\nmastodon-bird-ui-contrast: styles/mastodon-bird-ui-contrast.scss\nmastodon-bird-ui-light: styles/mastodon-bird-ui-light.scss" >> /opt/mastodon/config/themes.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI (Dark)\n    mastodon-bird-ui-contrast: Mastodon Bird UI (High contrast)\n    mastodon-bird-ui-light: Mastodon Bird UI (Light)' /opt/mastodon/config/locales/en.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI（暗色主题）\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高对比度）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色主题）' /opt/mastodon/config/locales/zh-CN.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI（深色）\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高對比）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色）' /opt/mastodon/config/locales/zh-TW.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高對比）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色主題）' /opt/mastodon/config/locales/zh-HK.yml \
  && echo "加入 Mastodon Bird UI (Sakura) 主题" \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura \
  && cp /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && cp /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/light/sakura/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/light/sakura/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "/logo: url/a\  --logo: url\('data:image/png;base64,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'\);" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "/logo: url('data:image\/svg/d" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/595aff/f596aa/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/9388a6/828282/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/8c8dff/f4a7b9/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/e5e1ed/f7e6e7/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/17bf63/86C166/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/9588a6/0b1013/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/e6e1ed/fedfe1/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-single-column.scss \
  && sed -i "s/595aff/f596aa/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/9388a6/828282/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/8c8dff/f4a7b9/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/e5e1ed/f7e6e7/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/17bf63/86C166/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/9588a6/0b1013/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && sed -i "s/e6e1ed/fedfe1/g" /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura/layout-multiple-columns.scss \
  && echo -e "@import 'mastodon-sakura/variables';\n@import 'application';\n@import 'mastodon-sakura/diff';\n@import 'mastodon-bird-ui-sakura/layout-single-column.scss';\n@import 'mastodon-bird-ui-sakura/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-sakura.scss \
  && sed -i '/mastodon-sakura/a\    mastodon-bird-ui-sakura: Mastodon Bird UI (Sakura)' /opt/mastodon/config/locales/en.yml \
  && sed -i '/mastodon-sakura/a\    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' /opt/mastodon/config/locales/zh-CN.yml \
  && sed -i '/mastodon-sakura/a\    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' /opt/mastodon/config/locales/zh-TW.yml \
  && sed -i '/mastodon-sakura/a\    mastodon-bird-ui-sakura: Mastodon Bird UI · 桜' /opt/mastodon/config/locales/zh-HK.yml \
  && echo -e "mastodon-bird-ui-sakura: styles/mastodon-bird-ui-sakura.scss" >> /opt/mastodon/config/themes.yml \
  && echo "全文搜索中文优化" \
  && sed -i "s|whitespace|ik_max_word|" /opt/mastodon/app/chewy/accounts_index.rb \
  && sed -i "s|analyzer: {|char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },\n    analyzer: {|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|uax_url_email|ik_max_word|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|        ),|        ),\n        char_filter: %w(tsconvert),|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|analysis: {|analysis: {\n    char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },|" /opt/mastodon/app/chewy/tags_index.rb \
  && sed -i "s|keyword',|ik_max_word',\n        char_filter: %w(tsconvert),|" /opt/mastodon/app/chewy/tags_index.rb \
  && echo "修改版本项目地址" \
  && sed -i "/def suffix/{n;s|''|'~wxw'|}" /opt/mastodon/lib/mastodon/version.rb \
  && sed -i "s|mastodon/mastodon|wxwmoe/mastodon|" /opt/mastodon/lib/mastodon/version.rb \
  && echo "重新编译资源文件" \
  && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile \
  && yarn cache clean
