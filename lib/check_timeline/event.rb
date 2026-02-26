# frozen_string_literal: true

require "dry-struct"
require "dry-types"
require_relative "currency"

module CheckTimeline
  module Types
    include Dry.Types()
  end

  # Canonical event model. Every data source must produce a collection of these.
  #
  # Fields:
  #   id          - deterministic or random identifier (used for deduplication)
  #   timestamp   - when this event occurred (used for timeline sorting)
  #   source      - which system produced the event  e.g. :checks_api, :raygun
  #   category    - broad grouping               e.g. :check, :payment, :exception
  #   event_type  - fine-grained label            e.g. "check.created", "payment.captured"
  #   title       - short human-readable summary  e.g. "Check Created"
  #   description - optional longer explanation
  #   severity    - :info | :warning | :error | :critical  (drives colour coding)
  #   amount      - optional monetary value in cents (for check/payment events)
  #   currency    - ISO 4217 currency code, defaults to "GBP"
  #   metadata    - arbitrary extra key/value pairs from the raw payload
  class Event < Dry::Struct
    include Currency
    module Types
      include Dry.Types()
    end

    SEVERITIES   = %i[info warning error critical].freeze
    CATEGORIES   = %i[check payment exception version unknown].freeze
    SOURCE_ICONS = {
      checks_api:  "💳",
      raygun:      "🐛",
      paper_trail: "📋",
      unknown:     "❓"
    }.freeze

    attribute :id,          Types::String
    attribute :timestamp,   Types::JSON::DateTime
    attribute :source,      Types::Coercible::Symbol
    attribute :category,    Types::Coercible::Symbol.default(:unknown)
    attribute :event_type,  Types::String
    attribute :title,       Types::String
    attribute :description, Types::String.optional.default(nil)
    attribute :severity,    Types::Coercible::Symbol.default(:info)
    attribute :amount,      Types::Coercible::Integer.optional.default(nil)
    attribute :currency,    Types::String.default("GBP")
    attribute :metadata,    Types::Hash.default({}.freeze)

    # Formatted amount using the event's own currency code, e.g. "£4.00"
    def formatted_amount
      return nil if amount.nil?

      format_currency(amount, currency)
    end

    def source_icon
      SOURCE_ICONS.fetch(source, SOURCE_ICONS[:unknown])
    end

    def error?
      %i[error critical].include?(severity)
    end

    def <=>(other)
      timestamp <=> other.timestamp
    end

    include Comparable
  end
end
