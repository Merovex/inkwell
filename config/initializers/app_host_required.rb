# Production is multi-tenant, full stop. Without APP_HOST, AccountHost falls
# back to its legacy single-tenant mode and quietly serves every request as
# the first account — every site's visitors would see one site, and every
# admin would be in the wrong account. So a production boot without it fails
# loudly instead: the deploy's health check never passes and the previous
# container keeps serving.
#
# The image build is exempt — assets:precompile boots production with
# SECRET_KEY_BASE_DUMMY and no runtime env. Dev and test keep the fallback.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank? && Rails.configuration.x.app_host.blank?
  raise "APP_HOST is not set. Production requires it (config/deploy.yml env.clear): " \
        "without it every request is served as Account.first."
end
