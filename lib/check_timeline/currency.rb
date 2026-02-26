# frozen_string_literal: true

module CheckTimeline
  # Shared currency formatting helpers used throughout the application.
  #
  # Include this module in any class or module that needs to format monetary
  # values. A standalone .format class method is also available for callers
  # that cannot easily include the module.
  #
  # All monetary values in this application are stored in cents (Integer).
  # Negative values represent debits, refunds, or discounts.
  #
  # Usage (module included):
  #   include CheckTimeline::Currency
  #   format_currency(400, "GBP")   # => "£4.00"
  #   format_currency(-150, "USD")  # => "-$1.50"
  #   format_currency(nil, "EUR")   # => "n/a"
  #
  # Usage (class method):
  #   CheckTimeline::Currency.format(400, "GBP")  # => "£4.00"
  module Currency

    # Maps ISO 4217 currency codes to their display symbols.
    # Extend this table as new currencies are encountered.
    SYMBOLS = {
      "GBP" => "£",
      "USD" => "$",
      "CAD" => "CA$",
      "AUD" => "A$",
      "NZD" => "NZ$",
      "EUR" => "€",
      "CHF" => "CHF ",
      "SEK" => "kr ",
      "NOK" => "kr ",
      "DKK" => "kr ",
      "JPY" => "¥",
      "CNY" => "¥",
      "HKD" => "HK$",
      "SGD" => "S$",
      "AED" => "AED ",
      "SAR" => "SAR ",
      "INR" => "₹",
      "MXN" => "MX$",
      "BRL" => "R$",
      "ZAR" => "R ",
    }.freeze

    # Currencies where the minor unit is zero (no decimal places needed).
    ZERO_DECIMAL = %w[JPY CNY].freeze

    # -------------------------------------------------------------------------
    # Instance method — available to any class that includes this module
    # -------------------------------------------------------------------------

    # Format an integer cent value as a human-readable currency string.
    #
    #   cents    - Integer amount in the minor unit (cents, pence, etc.)
    #              Negative values are prefixed with a minus sign.
    #              nil returns the string "n/a".
    #   currency - ISO 4217 currency code String, e.g. "GBP", "USD".
    #              Case-insensitive. Unknown codes are shown as a prefix.
    #
    # Examples:
    #   format_currency(400,   "GBP")  # => "£4.00"
    #   format_currency(1099,  "USD")  # => "$10.99"
    #   format_currency(-250,  "EUR")  # => "-€2.50"
    #   format_currency(500,   "JPY")  # => "¥500"
    #   format_currency(0,     "GBP")  # => "£0.00"
    #   format_currency(nil,   "GBP")  # => "n/a"
    #   format_currency(1000,  "XYZ")  # => "XYZ 10.00"
    def format_currency(cents, currency)
      return "n/a" if cents.nil?

      code   = currency.to_s.strip.upcase
      symbol = SYMBOLS.fetch(code, "#{code} ")
      amount = cents.to_i
      sign   = amount.negative? ? "-" : ""
      value  = ZERO_DECIMAL.include?(code) ? amount.abs.to_s : "%.2f" % (amount.abs / 100.0)

      "#{sign}#{symbol}#{value}"
    end

    # -------------------------------------------------------------------------
    # Class-level convenience method
    # -------------------------------------------------------------------------

    # Delegates to an instance of a lightweight formatter so callers that
    # cannot include the module can still use it.
    #
    #   CheckTimeline::Currency.format(400, "GBP")  # => "£4.00"
    def self.format(cents, currency)
      FORMATTER.format_currency(cents, currency)
    end

    # Returns just the symbol string for a given currency code.
    #
    #   CheckTimeline::Currency.symbol("GBP")  # => "£"
    #   CheckTimeline::Currency.symbol("XYZ")  # => "XYZ "
    def self.symbol(currency)
      SYMBOLS.fetch(currency.to_s.strip.upcase, "#{currency.to_s.strip.upcase} ")
    end

    # Lightweight singleton used by the .format class method above.
    FORMATTER = Class.new { include Currency }.new
    private_constant :FORMATTER
  end
end
