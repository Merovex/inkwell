require "test_helper"

# The /admin/users scoreboard: real customer counts, assumed unit economics on
# an annual plan ($50/yr, 30-day refund window, 6% target yearly churn).
class SaasMetricsTest < ActiveSupport::TestCase
  setup { @metrics = SaasMetrics.new }

  test "every user is a customer, paying or not" do
    assert_equal User.count, @metrics.customers
  end

  test "LTV is annual ARPU over annual churn, net of the 30-day refund" do
    # Defaults: $50/yr, 5% refunded, 6% yearly churn → (0.95 × 50) / 0.06.
    assert_in_delta 791.67, @metrics.ltv, 0.01
  end

  test "at the 6% churn target the plan clears the playbook's 3:1 floor" do
    # $791.67 LTV / $200 CAC ≈ 3.96 : 1.
    assert_in_delta 3.96, @metrics.ltv_cac_ratio, 0.01
    assert @metrics.healthy?
  end

  test "break-even and healthy CAC mark where the ratio hits 1:1 and 3:1" do
    assert_in_delta @metrics.ltv, @metrics.break_even_cac, 0.01              # 1:1 when CAC == LTV
    assert_in_delta @metrics.ltv / SaasMetrics::HEALTHY_LTV_CAC, @metrics.healthy_cac, 0.01
  end

  test "a CAC that outruns lifetime value trips the health flag" do
    Rails.configuration.x.saas.acquisition_cost = 400.0
    assert_operator @metrics.ltv_cac_ratio, :<, SaasMetrics::HEALTHY_LTV_CAC
    assert_not @metrics.healthy?
  ensure
    Rails.configuration.x.saas.acquisition_cost = 200.0
  end

  test "zero churn leaves LTV undefined instead of dividing by zero" do
    Rails.configuration.x.saas.annual_churn = 0.0
    assert_nil @metrics.ltv
    assert_nil @metrics.ltv_cac_ratio
    assert_not @metrics.healthy?
  ensure
    Rails.configuration.x.saas.annual_churn = 0.06
  end
end
