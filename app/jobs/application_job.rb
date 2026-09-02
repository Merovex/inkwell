class ApplicationJob < ActiveJob::Base
  # Every job carries the enqueuing request's account context (ADR 0017/0018).
  prepend AccountTenanted

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
