# The SaaS scoreboard behind /admin/users: the metrics the playbook says decide
# a subscription business's fate — ARPU, churn, refunds, and LTV:CAC. Customer
# counts are real (every user counts, paying or not); the revenue side runs on
# assumed unit economics (config.x.saas) until billing exists, so the model is
# visible now and fills in for real once customers pay. A PORO, not a table — it
# computes, it doesn't persist.
#
# The plan is ANNUAL: $50/year, no monthly, with the provider's 30-day refund
# window. So churn here is yearly (non-renewal), and refunds are a slice of new
# sales clawed back inside 30 days — CAC spent on them is wasted. When billing
# lands, arpu/churn/refund_rate become measured (real ARR, real non-renewals,
# real refunds) — this is the one seam to swap; the view won't change.
class SaasMetrics
  # The playbook's floor: a customer must be worth at least 3× what they cost to
  # acquire. Below it, the LTV:CAC stat flags trouble.
  HEALTHY_LTV_CAC = 3

  # Real counts — every user is a customer-to-be, paying or not.
  def customers = User.count
  def sites = Account.count
  def new_this_month = User.where(created_at: Time.current.beginning_of_month..).count
  def this_month = Time.current.strftime("%B")

  # Assumed unit economics — levers the founder sets, not measurements.
  def arpu = config.annual_price          # per year
  def churn_rate = config.annual_churn    # yearly non-renewal
  def refund_rate = config.refund_rate    # clawed back inside the 30-day window
  def cac = config.acquisition_cost

  # If every customer paid the annual price. Real ARR arrives with billing.
  def projected_arr = customers * arpu

  # A kept customer pays ARPU each year until they churn, so their average
  # lifetime is 1/churn years; the 30-day refund means a slice never sticks, so
  # net it out. Undefined at zero churn (a customer who never leaves).
  def ltv
    return nil if churn_rate.zero?

    (1 - refund_rate) * arpu / churn_rate
  end

  # The ratio the playbook lives by: lifetime value earned per dollar spent
  # acquiring a customer (CAC is spent even on the ones who refund).
  def ltv_cac_ratio
    return nil if ltv.nil? || cac.zero?

    ltv / cac
  end

  def healthy? = ltv_cac_ratio.present? && ltv_cac_ratio >= HEALTHY_LTV_CAC

  # The CAC where the ratio hits each mark — what the verdict points at. Break
  # even is 1:1 (CAC == LTV); healthy is the 3:1 floor (LTV ÷ 3).
  def break_even_cac = ltv
  def healthy_cac = ltv && ltv / HEALTHY_LTV_CAC

  private
    def config = Rails.configuration.x.saas
end
