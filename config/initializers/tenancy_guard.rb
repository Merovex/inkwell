# The retrofit tripwire (ADR 0017): in development and test, a SELECT that
# reads a tenanted table with no tenancy anchor raises at the call site.
# Deliberately crude — it catches the honest mistakes, which is most of them.
#
# A query passes when it carries any of: an account_id predicate, a records
# pk/parent_id predicate (lookups descending from an already-scoped row), or
# a record_id predicate (recordable tables pinned to specific records) — or
# when a deliberate sweep declares itself via
# Current.allowing_unscoped_tenancy { ... }.
#
# Scaffolding, not architecture: delete after the audit has soaked clean
# (the permanent artifact is test/integration/tenant_isolation_test.rb).
if Rails.env.local?
  module TenancyGuard
    TENANTED = /(?:FROM|JOIN)\s+"(?:records|missives)"/
    ANCHORED = /account_id|"records"\."id"|parent_id|record_id|"missives"\."id"/

    def self.check(payload)
      return if payload[:name] == "SCHEMA"

      sql = payload[:sql].to_s
      return unless sql.start_with?("SELECT") && sql.match?(TENANTED)
      return if sql.match?(ANCHORED)
      return if Current.allow_unscoped_tenancy
      return if issued_by_test_code?

      raise "Tenancy guard: unscoped query on a tenanted table:\n  #{sql}\n" \
            "Start the query from Current.account (ADR 0017), or wrap a " \
            "deliberate cross-account sweep in Current.allowing_unscoped_tenancy."
    end

    # Queries issued directly from a test file (assert_difference counters,
    # fixture sweeps) aren't audit targets — only app code is. A query whose
    # nearest app-or-test frame is under test/ gets a pass; anything reached
    # through app/ is checked no matter who triggered the request.
    def self.issued_by_test_code?
      frame = caller.find { |line| line.include?("/app/") || line.include?("/test/") }
      frame&.include?("/test/")
    end
  end

  ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    TenancyGuard.check(args.last)
  end
end
