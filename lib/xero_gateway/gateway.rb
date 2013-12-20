module XeroGateway

  class Gateway
    include Http
    include Dates

    attr_accessor :client, :xero_url, :logger

    extend Forwardable
    def_delegators :client, :request_token, :access_token, :authorize_from_request, :authorize_from_access, :authorization_expires_at

    #
    # The consumer key and secret here correspond to those provided
    # to you by Xero inside the API Previewer.
    def initialize(consumer_key, consumer_secret, options = {})
      @xero_url = options[:xero_url] || "https://api.xero.com/api.xro/2.0"
      @client   = OAuth.new(consumer_key, consumer_secret, options)
    end

    #
    # Retrieve all contacts from Xero
    #
    # Usage : get_contacts(:order => :name)
    #         get_contacts(:modified_since => Time)
    #
    # Note  : modified_since is in UTC format (i.e. Brisbane is UTC+10)
    def get_contacts(options = {})
      request_params = {}

      if !options[:updated_after].nil?
        warn '[warning] :updated_after is depracated in XeroGateway#get_contacts.  Use :modified_since'
        options[:modified_since] = options.delete(:updated_after)
      end

      request_params[:ContactID]     = options[:contact_id] if options[:contact_id]
      request_params[:ContactNumber] = options[:contact_number] if options[:contact_number]
      request_params[:OrderBy]       = options[:order] if options[:order]
      request_params[:ModifiedAfter] = options[:modified_since] if options[:modified_since]
      request_params[:where]         = options[:where] if options[:where]

      response_xml = http_get(@client, "#{@xero_url}/Contacts", request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/contacts'})
    end

    # Retrieve a contact from Xero
    # Usage get_contact_by_id(contact_id)
    def get_contact_by_id(contact_id)
      get_contact(contact_id)
    end

    # Retrieve a contact from Xero
    # Usage get_contact_by_id(contact_id)
    def get_contact_by_number(contact_number)
      get_contact(nil, contact_number)
    end

    # Factory method for building new Contact objects associated with this gateway.
    def build_contact(contact = {})
      case contact
        when Contact then   contact.gateway = self
        when Hash then      contact = Contact.new(contact.merge({:gateway => self}))
      end
      contact
    end

    #
    # Creates a contact in Xero
    #
    # Usage :
    #
    # contact = XeroGateway::Contact.new(:name => "THE NAME OF THE CONTACT #{Time.now.to_i}")
    # contact.email = "whoever@something.com"
    # contact.phone.number = "12345"
    # contact.address.line_1 = "LINE 1 OF THE ADDRESS"
    # contact.address.line_2 = "LINE 2 OF THE ADDRESS"
    # contact.address.line_3 = "LINE 3 OF THE ADDRESS"
    # contact.address.line_4 = "LINE 4 OF THE ADDRESS"
    # contact.address.city = "WELLINGTON"
    # contact.address.region = "WELLINGTON"
    # contact.address.country = "NEW ZEALAND"
    # contact.address.post_code = "6021"
    #
    # create_contact(contact)
    def create_contact(contact)
      save_contact(contact)
    end

    #
    # Updates an existing Xero contact
    #
    # Usage :
    #
    # contact = xero_gateway.get_contact(some_contact_id)
    # contact.email = "a_new_email_ddress"
    #
    # xero_gateway.update_contact(contact)
    def update_contact(contact)
      raise "contact_id or contact_number is required for updating contacts" if contact.contact_id.nil? and contact.contact_number.nil?
      save_contact(contact)
    end

    #
    # Updates an array of contacts in a single API operation.
    #
    # Usage :
    #  contacts = [XeroGateway::Contact.new(:name => 'Joe Bloggs'), XeroGateway::Contact.new(:name => 'Jane Doe')]
    #  result = gateway.update_contacts(contacts)
    #
    # Will update contacts with matching contact_id, contact_number or name or create if they don't exist.
    #
    def update_contacts(contacts)
      b = Builder::XmlMarkup.new
      request_xml = b.Contacts {
        contacts.each do | contact |
          contact.to_xml(b)
        end
      }

      response_xml = http_post(@client, "#{@xero_url}/Contacts", request_xml, {})

      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => 'POST/contacts'})
      response.contacts.each_with_index do | response_contact, index |
        contacts[index].contact_id = response_contact.contact_id if response_contact && response_contact.contact_id
      end
      response
    end

    # Retrieves all invoices from Xero
    #
    # Usage : get_invoices
    #         get_invoices(:invoice_id => " 297c2dc5-cc47-4afd-8ec8-74990b8761e9")
    #
    # Note  : modified_since is in UTC format (i.e. Brisbane is UTC+10)
    def get_invoices(options = {})

      request_params = {}

      request_params[:InvoiceID]     = options[:invoice_id] if options[:invoice_id]
      request_params[:InvoiceNumber] = options[:invoice_number] if options[:invoice_number]
      request_params[:OrderBy]       = options[:order] if options[:order]
      request_params[:ModifiedAfter] = options[:modified_since] if options[:modified_since]

      request_params[:where]         = options[:where] if options[:where]

      response_xml = http_get(@client, "#{@xero_url}/Invoices", request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/Invoices'})
    end

    # Retrieves a single invoice
    #
    # Usage : get_invoice("297c2dc5-cc47-4afd-8ec8-74990b8761e9") # By ID
    #         get_invoice("OIT-12345") # By number
    def get_invoice(invoice_id_or_number)
      request_params = {}

      url  = "#{@xero_url}/Invoices/#{URI.escape(invoice_id_or_number)}"

      response_xml = http_get(@client, url, request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/Invoice'})
    end

    # Factory method for building new Invoice objects associated with this gateway.
    def build_invoice(invoice = {})
      case invoice
        when Invoice then     invoice.gateway = self
        when Hash then        invoice = Invoice.new(invoice.merge(:gateway => self))
      end
      invoice
    end

    # Creates an invoice in Xero based on an invoice object.
    #
    # Invoice and line item totals are calculated automatically.
    #
    # Usage :
    #
    #    invoice = XeroGateway::Invoice.new({
    #      :invoice_type => "ACCREC",
    #      :due_date => 1.month.from_now,
    #      :invoice_number => "YOUR INVOICE NUMBER",
    #      :reference => "YOUR REFERENCE (NOT NECESSARILY UNIQUE!)",
    #      :line_amount_types => "Inclusive"
    #    })
    #    invoice.contact = XeroGateway::Contact.new(:name => "THE NAME OF THE CONTACT")
    #    invoice.contact.phone.number = "12345"
    #    invoice.contact.address.line_1 = "LINE 1 OF THE ADDRESS"
    #    invoice.line_items << XeroGateway::LineItem.new(
    #      :description => "THE DESCRIPTION OF THE LINE ITEM",
    #      :unit_amount => 100,
    #      :tax_amount => 12.5,
    #      :tracking_category => "THE TRACKING CATEGORY FOR THE LINE ITEM",
    #      :tracking_option => "THE TRACKING OPTION FOR THE LINE ITEM"
    #    )
    #
    #    create_invoice(invoice)
    def create_invoice(invoice)
      save_invoice(invoice)
    end

    #
    # Updates an existing Xero invoice
    #
    # Usage :
    #
    # invoice = xero_gateway.get_invoice(some_invoice_id)
    # invoice.due_date = Date.today
    #
    # xero_gateway.update_invoice(invoice)

    def update_invoice(invoice)
      raise "invoice_id is required for updating invoices" if invoice.invoice_id.nil?
      save_invoice(invoice)
    end

    #
    # Creates an array of invoices with a single API request.
    #
    # Usage :
    #  invoices = [XeroGateway::Invoice.new(...), XeroGateway::Invoice.new(...)]
    #  result = gateway.create_invoices(invoices)
    #
    def create_invoices(invoices)
      b = Builder::XmlMarkup.new
      request_xml = b.Invoices {
        invoices.each do | invoice |
          invoice.to_xml(b)
        end
      }

      response_xml = http_put(@client, "#{@xero_url}/Invoices", request_xml, {})

      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => 'PUT/invoices'})
      response.invoices.each_with_index do | response_invoice, index |
        invoices[index].invoice_id = response_invoice.invoice_id if response_invoice && response_invoice.invoice_id
      end
      response
    end

    # Retrieves all credit_notes from Xero
    #
    # Usage : get_credit_notes
    #         get_credit_notes(:credit_note_id => " 297c2dc5-cc47-4afd-8ec8-74990b8761e9")
    #
    # Note  : modified_since is in UTC format (i.e. Brisbane is UTC+10)
    def get_credit_notes(options = {})

      request_params = {}

      request_params[:CreditNoteID]     = options[:credit_note_id] if options[:credit_note_id]
      request_params[:CreditNoteNumber] = options[:credit_note_number] if options[:credit_note_number]
      request_params[:OrderBy]       = options[:order] if options[:order]
      request_params[:ModifiedAfter] = options[:modified_since] if options[:modified_since]

      request_params[:where]         = options[:where] if options[:where]

      response_xml = http_get(@client, "#{@xero_url}/CreditNotes", request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/CreditNotes'})
    end

    # Retrieves a single credit_note
    #
    # Usage : get_credit_note("297c2dc5-cc47-4afd-8ec8-74990b8761e9") # By ID
    #         get_credit_note("OIT-12345") # By number
    def get_credit_note(credit_note_id_or_number)
      request_params = {}

      url  = "#{@xero_url}/CreditNotes/#{URI.escape(credit_note_id_or_number)}"

      response_xml = http_get(@client, url, request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/CreditNote'})
    end

    # Factory method for building new CreditNote objects associated with this gateway.
    def build_credit_note(credit_note = {})
      case credit_note
        when CreditNote then     credit_note.gateway = self
        when Hash then        credit_note = CreditNote.new(credit_note.merge(:gateway => self))
      end
      credit_note
    end

    # Creates an credit_note in Xero based on an credit_note object.
    #
    # CreditNote and line item totals are calculated automatically.
    #
    # Usage :
    #
    #    credit_note = XeroGateway::CreditNote.new({
    #      :credit_note_type => "ACCREC",
    #      :due_date => 1.month.from_now,
    #      :credit_note_number => "YOUR CREDIT_NOTE NUMBER",
    #      :reference => "YOUR REFERENCE (NOT NECESSARILY UNIQUE!)",
    #      :line_amount_types => "Inclusive"
    #    })
    #    credit_note.contact = XeroGateway::Contact.new(:name => "THE NAME OF THE CONTACT")
    #    credit_note.contact.phone.number = "12345"
    #    credit_note.contact.address.line_1 = "LINE 1 OF THE ADDRESS"
    #    credit_note.line_items << XeroGateway::LineItem.new(
    #      :description => "THE DESCRIPTION OF THE LINE ITEM",
    #      :unit_amount => 100,
    #      :tax_amount => 12.5,
    #      :tracking_category => "THE TRACKING CATEGORY FOR THE LINE ITEM",
    #      :tracking_option => "THE TRACKING OPTION FOR THE LINE ITEM"
    #    )
    #
    #    create_credit_note(credit_note)
    def create_credit_note(credit_note)
      request_xml = credit_note.to_xml
      response_xml = http_put(@client, "#{@xero_url}/CreditNotes", request_xml)
      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => 'PUT/credit_note'})

      # Xero returns credit_notes inside an <CreditNotes> tag, even though there's only ever
      # one for this request
      response.response_item = response.credit_notes.first

      if response.success? && response.credit_note && response.credit_note.credit_note_id
        credit_note.credit_note_id = response.credit_note.credit_note_id
      end

      response
    end

    #
    # Creates an array of credit_notes with a single API request.
    #
    # Usage :
    #  credit_notes = [XeroGateway::CreditNote.new(...), XeroGateway::CreditNote.new(...)]
    #  result = gateway.create_credit_notes(credit_notes)
    #
    def create_credit_notes(credit_notes)
      b = Builder::XmlMarkup.new
      request_xml = b.CreditNotes {
        credit_notes.each do | credit_note |
          credit_note.to_xml(b)
        end
      }

      response_xml = http_put(@client, "#{@xero_url}/CreditNotes", request_xml, {})

      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => 'PUT/credit_notes'})
      response.credit_notes.each_with_index do | response_credit_note, index |
        credit_notes[index].credit_note_id = response_credit_note.credit_note_id if response_credit_note && response_credit_note.credit_note_id
      end
      response
    end

    #
    # Gets all accounts for a specific organization in Xero.
    #
    def get_accounts
      response_xml = http_get(@client, "#{xero_url}/Accounts")
      parse_response(response_xml, {}, {:request_signature => 'GET/accounts'})
    end

    #
    # Returns a XeroGateway::AccountsList object that makes working with
    # the Xero list of accounts easier and allows caching the results.
    #
    def get_accounts_list(load_on_init = true)
      AccountsList.new(self, load_on_init)
    end

    #
    # Gets all tracking categories for a specific organization in Xero.
    #
    def get_tracking_categories
      response_xml = http_get(@client, "#{xero_url}/TrackingCategories")

      parse_response(response_xml, {}, {:request_signature => 'GET/TrackingCategories'})
    end

    #
    # Gets Organisation details
    #
    def get_organisation
      response_xml = http_get(@client, "#{xero_url}/Organisation")
      parse_response(response_xml, {}, {:request_signature => 'GET/organisation'})
    end

    #
    # Gets all currencies for a specific organisation in Xero
    #
    def get_currencies
      response_xml = http_get(@client, "#{xero_url}/Currencies")
      parse_response(response_xml, {}, {:request_signature => 'GET/currencies'})
    end

    #
    # Gets all Tax Rates for a specific organisation in Xero
    #
    def get_tax_rates(options = {})
      options.merge!(:request_signature => 'GET/tax_rates')
      response_xml = http_get(@client, "#{xero_url}/TaxRates")
      parse_response(response_xml, {}, options)
    end

    private

    def get_contact(contact_id = nil, contact_number = nil)
      request_params = contact_id ? { :contactID => contact_id } : { :contactNumber => contact_number }
      response_xml = http_get(@client, "#{@xero_url}/Contacts/#{URI.escape(contact_id||contact_number)}", request_params)

      parse_response(response_xml, {:request_params => request_params}, {:request_signature => 'GET/contact'})
    end

    # Create or update a contact record based on if it has a contact_id or contact_number.
    def save_contact(contact)
      request_xml = contact.to_xml

      response_xml = nil
      create_or_save = nil
      if contact.contact_id.nil? && contact.contact_number.nil?
        # Create new contact record.
        response_xml = http_put(@client, "#{@xero_url}/Contacts", request_xml, {})
        create_or_save = :create
      else
        # Update existing contact record.
        response_xml = http_post(@client, "#{@xero_url}/Contacts", request_xml, {})
        create_or_save = :save
      end

      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => "#{create_or_save == :create ? 'PUT' : 'POST'}/contact"})
      contact.contact_id = response.contact.contact_id if response.contact && response.contact.contact_id
      response
    end

    # Create or update an invoice record based on if it has an invoice_id.
    def save_invoice(invoice)
      request_xml = invoice.to_xml

      response_xml = nil
      create_or_save = nil
      if invoice.invoice_id.nil?
        # Create new invoice record.
        response_xml = http_put(@client, "#{@xero_url}/Invoices", request_xml, {})
        create_or_save = :create
      else
        # Update existing invoice record.
        response_xml = http_post(@client, "#{@xero_url}/Invoices", request_xml, {})
        create_or_save = :save
      end

      response = parse_response(response_xml, {:request_xml => request_xml}, {:request_signature => "#{create_or_save == :create ? 'PUT' : 'POST'}/invoice"})

      # Xero returns invoices inside an <Invoices> tag, even though there's only ever
      # one for this request
      response.response_item = response.invoices.first

      if response.success? && response.invoice && response.invoice.invoice_id
        invoice.invoice_id = response.invoice.invoice_id
      end

      response
    end

    def parse_response(raw_response, request = {}, options = {})

      response = XeroGateway::Response.new

      doc = REXML::Document.new(raw_response, :ignore_whitespace_nodes => :all)

      # check for responses we don't understand
      raise UnparseableResponse.new(doc.root.name) unless doc.root.name == "Response"

      response_element = REXML::XPath.first(doc, "/Response")

      response_element.children.reject { |e| e.is_a? REXML::Text }.each do |element|
        case(element.name)
          when "ID" then response.response_id = element.text
          when "Status" then response.status = element.text
          when "ProviderName" then response.provider = element.text
          when "DateTimeUTC" then response.date_time = element.text
          when "Contact" then response.response_item = Contact.from_xml(element, self)
          when "Invoice" then response.response_item = Invoice.from_xml(element, self, {:line_items_downloaded => options[:request_signature] != "GET/Invoices"})
          when "Contacts" then element.children.each {|child| response.response_item << Contact.from_xml(child, self) }
          when "Invoices" then element.children.each {|child| response.response_item << Invoice.from_xml(child, self, {:line_items_downloaded => options[:request_signature] != "GET/Invoices"}) }
          when "CreditNotes" then element.children.each {|child| response.response_item << CreditNote.from_xml(child, self, {:line_items_downloaded => options[:request_signature] != "GET/CreditNotes"}) }
          when "Accounts" then element.children.each {|child| response.response_item << Account.from_xml(child) }
          when "TaxRates" then element.children.each {|child| response.response_item << TaxRate.from_xml(child, options) }
          when "Currencies" then element.children.each {|child| response.response_item << Currency.from_xml(child) }
          when "Organisations" then response.response_item = Organisation.from_xml(element.children.first) # Xero only returns the Authorized Organisation
          when "TrackingCategories" then element.children.each {|child| response.response_item << TrackingCategory.from_xml(child) }
          when "Errors" then element.children.each { |error| parse_error(error, response) }
        end
      end if response_element

      # If a single result is returned don't put it in an array
      if response.response_item.is_a?(Array) && response.response_item.size == 1
        response.response_item = response.response_item.first
      end

      response.request_params = request[:request_params]
      response.request_xml    = request[:request_xml]
      response.response_xml   = raw_response
      response
    end

    def parse_error(error_element, response)
      response.errors << Error.new(
          :description => REXML::XPath.first(error_element, "Description").text,
          :date_time => REXML::XPath.first(error_element, "//DateTime").text,
          :type => REXML::XPath.first(error_element, "//ExceptionType").text,
          :message => REXML::XPath.first(error_element, "//Message").text
      )
    end
  end
end
