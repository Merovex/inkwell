# Promote the draft design to production (docs/site-designer.md): the current
# live design steps down to history, the draft goes live, and a production
# rebuild is scheduled. Modeled as a resource create — POST publishes; a
# future DELETE would roll back to the previous published version.
class Admin::Designers::PublicationsController < Admin::BaseController
  def create
    Current.account.publish_design!
    head :no_content
  end
end
