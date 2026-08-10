require "test_helper"

# The /admin/users scoreboard: real customer counts, assumed unit economics on
# an annual plan ($50/yr, 30-day refund window, yearly churn).
class SaasMetricsTest < ActiveSupport::TestCase
  setup { @metrics = SaasMetrics.new }

  test "every user is a customer, paying or not" do
    assert_equal User.count, @metrics.customers
  end

  test "LTV is annual ARPU over annual churn, net of the 30-day refund" do
    # Defaults: $50/yr, 5% refunded, 30% yearly churn → (0.95 × 50) / 0.30.
    assert_in_delta 158.33, @metrics.ltv, 0.01
  end

  test "a $50/yr plan can't cover a $200 CAC — the ratio flags trouble" do
    # $158.33 LTV / $200 CAC ≈ 0.79 : 1, well under the 3:1 floor.
    assert_in_delta 0.79, @metrics.ltv_cac_ratio, 0.01
    assert_not @metrics.healthy?
  end

  test "a low enough CAC clears the playbook's 3:1 floor" do
    Rails.configuration.x.saas.acquisition_cost = 40.0
    assert_operator @metrics.ltv_cac_ratio, :>=, SaasMetrics::HEALTHY_LTV_CAC
    assert @metrics.healthy?
  ensure
    Rails.configuration.x.saas.acquisition_cost = 200.0
  end

  test "zero churn leaves LTV undefined instead of dividing by zero" do
    Rails.configuration.x.saas.annual_churn = 0.0
    assert_nil @metrics.ltv
    assert_nil @metrics.ltv_cac_ratio
    assert_not @metrics.healthy?
  ensure
    Rails.configuration.x.saas.annual_churn = 0.30
  end
end
