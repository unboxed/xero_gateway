require File.join(File.dirname(__FILE__), '../test_helper.rb')

class TaxRateTest < Test::Unit::TestCase

  # Tests that a tax rate can be converted into XML that Xero can understand, and then converted back to a tax rate
  def test_build_and_parse_xml
    tax_rate = create_test_tax_rate

    # Generate the XML message
    tax_rate_as_xml = tax_rate.to_xml

    # Parse the XML message and retrieve the account element
    tax_rate_element = parse_tax_rate(tax_rate_as_xml)

    # Build a new account from the XML
    result_tax_rate = XeroGateway::TaxRate.from_xml(tax_rate_element)

    # Check the account details
    assert_equal tax_rate, result_tax_rate
  end

  private

  def parse_tax_rate(xml)
    REXML::XPath.first(REXML::Document.new(xml), "/TaxRate")
  end

  def tax_rate_params
    {:name                     => "GST on Expenses",
     :tax_type                 => "INPUT",
     :can_apply_to_assets      => true,
     :can_apply_to_equity      => true,
     :can_apply_to_expenses    => true,
     :can_apply_to_liabilities => true,
     :can_apply_to_revenue     => false,
     :display_tax_rate         => 12.500,
     :effective_rate           => 12.500,
     :status                   => "PENDING"}
  end

  def create_test_tax_rate(params=tax_rate_params)
    XeroGateway::TaxRate.new(params)
  end
end
