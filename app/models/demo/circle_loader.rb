# Loads a demo circle payload through the model layer, the circle-space
# counterpart of Demo::SiteLoader: Circle.create_with_owner for the bucket,
# then Record.originate under Current.with_bucket for the board messages (with
# threaded comments), the check-in Pulse, and its Beats — so tenancy stamping,
# membership caps, and the versioned-record invariants all hold. Users are
# referenced by email and must already exist (load the site payloads first).
#
#   rails "demo:circle[../demo/circle.json]"
class Demo::CircleLoader
  class Error < StandardError; end

  def self.load(payload)
    new(payload).load
  end

  def initialize(payload)
    @payload = payload.deep_symbolize_keys
  end

  def load
    raise Error, "Circle #{@payload[:name].inspect} already exists — refusing to double-load" if Circle.exists?(name: @payload[:name])

    ApplicationRecord.transaction do
      create_circle
      Current.with_bucket(@circle) do
        create_messages
        create_pulse
      end
    end
    @circle
  end

  private
    def create_circle
      owner = user_for(@payload[:owner])
      @circle = Circle.create_with_owner(name: @payload[:name], owner: owner,
        description: @payload[:description], charter: @payload[:charter])
      raise Error, "Circle invalid: #{@circle.errors.full_messages.to_sentence}" unless @circle.persisted?

      Array(@payload[:members]).each do |email|
        @circle.circle_memberships.create!(user: user_for(email), role: "member")
      end
    end

    def create_messages
      Array(@payload[:messages]).each do |entry|
        message = Message.new(title: entry[:title], creator: user_for(entry[:author]),
          event: :created, status: "published",
          published_at: entry[:published_at] ? Time.zone.parse(entry[:published_at]) : Time.current)
        message.content = entry[:body]
        record = Record.originate(message)

        Array(entry[:comments]).each do |reply|
          comment = Comment.new(content: reply[:body], creator: user_for(reply[:author]))
          Record.originate(comment, parent: record)
        end
      end
    end

    def create_pulse
      entry = @payload[:pulse] or return
      hour, minute = entry.fetch(:ask_at, "09:00").split(":").map(&:to_i)
      pulse = Pulse.new(question: entry[:question], description: entry[:description],
        cadence: entry.fetch(:cadence, "weekly"),
        days_of_week: 1 << weekday(entry.fetch(:day, "Monday")),
        ask_at_minutes: hour * 60 + minute, active: true,
        creator: user_for(entry.fetch(:creator, @payload[:owner])), event: :created)
      record = Record.originate(pulse)
      pulse.subscribe(User.where(id: @circle.members.ids))

      Array(entry[:beats]).each do |beat_entry|
        beat = Beat.new(content: beat_entry[:body], asked_on: Date.parse(beat_entry[:asked_on]),
          word_count: beat_entry[:word_count], creator: user_for(beat_entry[:author]))
        Record.originate(beat, parent: record)
      end

      # The asks already "happened" (the beats say so); stamp the latest
      # occurrence the way Pulse#ask! would, without re-mailing anybody.
      last = Array(entry[:beats]).map { |b| Date.parse(b[:asked_on]) }.max
      pulse.update_column(:last_asked_on, last) if last
    end

    def user_for(email)
      (@users ||= {})[email] ||= User.with_email_address(email) ||
        raise(Error, "No user with email #{email.inspect} — load the site payloads first")
    end

    def weekday(name)
      Pulse::WEEKDAYS.index(name) || raise(Error, "Unknown weekday #{name.inspect}")
    end
end
