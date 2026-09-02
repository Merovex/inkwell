# Boost routes resolve from the record's bucket, like CommentsHelper does for
# comments — the boost partials stay bucket-agnostic.
module BoostsHelper
  def boosts_path_for(record)
    if record.bucket.is_a?(Circle)
      circle_record_boosts_path(record.bucket, record)
    else
      admin_record_boosts_path(record)
    end
  end

  def boost_path_for(boost)
    if boost.record.bucket.is_a?(Circle)
      circle_boost_path(boost.record.bucket, boost)
    else
      admin_boost_path(boost)
    end
  end
end
