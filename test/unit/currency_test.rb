# frozen_string_literal: true

require_relative "../test_helper"

module CheckTimeline
  class CurrencyTest < Minitest::Test

    # -------------------------------------------------------------------------
    # format_currency (instance method via include)
    # -------------------------------------------------------------------------

    class Formatter
      include CheckTimeline::Currency
      public :format_currency
    end

    def setup
      @fmt = Formatter.new
    end

    def test_formats_gbp_pence_to_pounds
      assert_equal "£12.00", @fmt.format_currency(1200, "GBP")
    end

    def test_formats_usd_cents_to_dollars
      assert_equal "$10.99", @fmt.format_currency(1099, "USD")
    end

    def test_formats_eur
      assert_equal "€2.50", @fmt.format_currency(250, "EUR")
    end

    def test_formats_zero_value
      assert_equal "£0.00", @fmt.format_currency(0, "GBP")
    end

    def test_formats_negative_value
      assert_equal "-£2.50", @fmt.format_currency(-250, "GBP")
    end

    def test_formats_nil_as_na
      assert_equal "n/a", @fmt.format_currency(nil, "GBP")
    end

    def test_formats_zero_decimal_currency_jpy_without_decimal_places
      assert_equal "¥500", @fmt.format_currency(500, "JPY")
    end

    def test_formats_zero_decimal_currency_cny_without_decimal_places
      assert_equal "¥1000", @fmt.format_currency(1000, "CNY")
    end

    def test_formats_unknown_currency_code_as_prefix
      assert_equal "XYZ 4.00", @fmt.format_currency(400, "XYZ")
    end

    def test_formats_negative_unknown_currency
      assert_equal "-XYZ 4.00", @fmt.format_currency(-400, "XYZ")
    end

    def test_formats_chf_with_symbol
      assert_equal "CHF 8.00", @fmt.format_currency(800, "CHF")
    end

    def test_formats_large_value
      assert_equal "£1000.00", @fmt.format_currency(100_000, "GBP")
    end

    def test_formats_one_cent
      assert_equal "£0.01", @fmt.format_currency(1, "GBP")
    end

    def test_currency_code_is_case_insensitive
      assert_equal "£5.00", @fmt.format_currency(500, "gbp")
    end

    # -------------------------------------------------------------------------
    # Currency.format — class-level convenience method
    # -------------------------------------------------------------------------

    def test_class_format_method_delegates_correctly
      assert_equal "£4.00", CheckTimeline::Currency.format(400, "GBP")
    end

    def test_class_format_method_handles_nil
      assert_equal "n/a", CheckTimeline::Currency.format(nil, "GBP")
    end

    def test_class_format_negative
      assert_equal "-$1.50", CheckTimeline::Currency.format(-150, "USD")
    end

    # -------------------------------------------------------------------------
    # Currency.symbol
    # -------------------------------------------------------------------------

    def test_symbol_gbp
      assert_equal "£", CheckTimeline::Currency.symbol("GBP")
    end

    def test_symbol_usd
      assert_equal "$", CheckTimeline::Currency.symbol("USD")
    end

    def test_symbol_eur
      assert_equal "€", CheckTimeline::Currency.symbol("EUR")
    end

    def test_symbol_unknown_code_returns_code_with_trailing_space
      assert_equal "FOO ", CheckTimeline::Currency.symbol("FOO")
    end

    def test_symbol_is_case_insensitive
      assert_equal "£", CheckTimeline::Currency.symbol("gbp")
    end
  end
end
