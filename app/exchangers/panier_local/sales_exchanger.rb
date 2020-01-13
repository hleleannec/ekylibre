module PanierLocal
  class SalesExchanger < ActiveExchanger::Base

    NORMALIZATION_CONFIG = [
      {col: 1, name: :invoiced_at, type: :date, constraint: :not_nil},
      {col: 3, name: :journal_nature, type: :string},
      {col: 4, name: :account_number, type: :string},
      {col: 5, name: :entity_name, type: :string, constraint: :not_nil},
      {col: 6, name: :entity_code, type: :integer, constraint: :not_nil},
      {col: 7, name: :sale_reference_number, type: :string, constraint: :not_nil},
      {col: 8, name: :sale_description, type: :string},
      {col: 9, name: :sale_item_amount, type: :float, constraint: :greater_or_equal_to_zero},
      {col: 10, name: :sale_item_sens, type: :string},
      {col: 11, name: :sale_item_pretax_amount, type: :float},
      {col: 12, name: :vat_percentage, type: :float},
      {col: 13, name: :quantity, type: :integer},
    ]




    def check
      # Imports sales entries into sales to make accountancy in CSV format
      # filename example : ECRITURES.CSV
      # Columns are:
      #  0 - A: journal_entry_items_line : "1"
      #  1 - B: printed_on : "01/01/2017"
      #  2 - C: journal code : "70"
      #  3 - D: journal nature : "FACTURE"
      #  4 - E: account number : "34150000"
      #  5 - F: entity name : "AB EPLUCHES"
      #  6 - G: entity number : "133"
      #  7 - H: journal_entry number : "842"
      #  8 - I: journal_entry label : "Facture Aout 2019"
      #  9 - J: amount : '44,24'
      #  10 - K: sens : 'D'
      #  11 - L: pretax_amount : '36,87'
      #  12 - L: tax_rate : '20'
      #  13 - M: quantity : '104'


      # Ouverture et décodage: CSVReader::read(file)
      rows = ActiveExchanger::CsvReader.new.read(file)
      parser = ActiveExchanger::CsvParser.new(NORMALIZATION_CONFIG)

      data, errors = parser.normalize(rows)

      valid = errors.all?(&:empty?)

      fy_start = FinancialYear.at(Date.parse(rows.first[1].to_s))
      fy_stop = FinancialYear.at(Date.parse(rows[-1][1].to_s))

      unless fy_start && fy_stop
        w.warn 'Need a FinancialYear'
        valid = false
      end

        w.info valid.inspect.green
      valid
    end

    def import
      # Ouverture et décodage
      rows = ActiveExchanger::CsvReader.new.read(file)
      w.count = rows.size

      # create or find journal for sale nature
      journal = Journal.find_or_create_by(code: 'PALO', nature: 'sales', name: 'Panier Local')
      catalog = Catalog.find_or_create_by(code: 'PALO', currency: 'EUR', usage: 'sale', name: 'Panier Local')
      # create or find sale_nature
      sale_nature = SaleNature.find_or_create_by(name: "Vente en ligne - Panier Local", catalog_id: catalog.id, currency: 'EUR', payment_delay: '30 days', journal_id: journal.id)

      country = Preference[:country]
      variant = nil
      tax = nil
      quantity = nil
      pretax_amount = nil
      tax_amount = nil
      amount = nil

      parser = ActiveExchanger::CsvParser.new(NORMALIZATION_CONFIG)

      data, errors = parser.normalize(rows)

      sales_info = data.group_by { |d| d.sale_reference_number }

      sales_info.each { |_sale_reference_number, sale_info| sale_creation(sale_info, sale_nature) }

    end

    def sale_creation(sale_info, sale_nature)
      entity = get_or_create_entity(sale_info)
      sale = Sale.where('providers ->> ? = ?', 'panier_local', sale_info.first.sale_reference_number).first

      if sale.nil?
        client_sale_info = sale_info.select {|item| item.account_number.to_s.start_with?('411')}.first
        sale = Sale.new(
          invoiced_at: client_sale_info.invoiced_at,
          reference_number: client_sale_info.sale_reference_number,
          client: entity,
          nature: sale_nature,
          description: client_sale_info.sale_description,
          providers: {'panier_local' => client_sale_info.sale_reference_number}
          )

        tax = check_or_create_vat_account_and_amount(sale_info)

        product_account_line = sale_info.select {|i| i.account_number.to_s.start_with?('7') }.first

        if product_account_line.present?
          product_account = check_or_create_product_account(product_account_line)
          variant = ProductNatureVariant.find_by('providers ->> ? = ?', 'panier_local', product_account_line.account_number)
          unless variant
            variant = create_variant(product_account, product_account_line)
          end
          pretax_amount = create_pretax_amount(product_account_line)
          quantity = product_account_line.quantity
        end
      end

      if sale && quantity && pretax_amount && variant && tax
        unless SaleItem.where(
          sale_id: sale.id,
          quantity: quantity,
          pretax_amount: pretax_amount,
          variant_id: variant.id
        ).first
          sale.items.build(
            amount: nil,
            pretax_amount: pretax_amount,
            unit_pretax_amount: nil,
            quantity: quantity,
            tax: tax,
            variant: variant,
            compute_from: :pretax_amount
          )
        end
      end
      entity.save
      variant.save
      sale.client = entity
      sale.save
    end

    def get_or_create_entity(sale_info)
        entity = Entity.where('codes ->> ? = ?', 'panier_local', sale_info.first.entity_code.to_s)
        if entity.any?
          entity.first
        else
          account = create_entity_account(sale_info)
          create_entity(sale_info, account)
        end
    end

    def create_entity_account(sale_info)
      client_sale_info = sale_info.select {|item| item.account_number.to_s.start_with?('411')}.first
      if client_sale_info.present?
        client_number_account = client_sale_info.account_number.to_s
        acc = Account.find_or_initialize_by(number: client_number_account)#!

        attributes = {
                      name: client_sale_info.entity_name,
                      centralizing_account_name: 'clients',
                      nature: 'auxiliary'
                    }

        aux_number = client_number_account[3, client_number_account.length]

        if aux_number.match(/\A0*\z/).present?
          w.info "We can't import auxiliary number #{aux_number} with only 0. Mass change number in your file before importing"
          attributes[:auxiliary_number] = '00000A'
        else
          attributes[:auxiliary_number] = aux_number
        end
        acc.attributes = attributes
        acc
      end
    end

    def create_entity(sale_info, acc)
      client_sale_info = sale_info.select {|item| item.account_number.to_s.start_with?('411')}.first
      last_name = client_sale_info.entity_name.mb_chars.capitalize

      w.info "Create entity and link account"
      entity = Entity.new(
        nature: :organization,
        last_name: last_name,
        codes: { 'panier_local' => client_sale_info.entity_code },
        active: true,
        client: true,
        client_account_id: acc.id
      )

      entity
    end

    def check_or_create_vat_account_and_amount(sale_info)
      account_numbers = sale_info.map {|i| i.account_number }
      vat_account = account_numbers.select { |number| number.to_s.start_with?('445') }
      vat_account_info = vat_account.any? ? sale_info.select {|item| item.account_number.to_s.start_with?('445')}.first : nil
      if vat_account.any? && vat_account_info.present?
        global_pretax_amount = vat_account_info.sale_item_pretax_amount
        global_tax_amount = vat_account_info.sale_item_amount
        clean_tax_account_number = vat_account_info.account_number.to_s[0..Preference[:account_number_digits]]

        tax_account = Account.find_by(number: clean_tax_account_number)
        tax = Tax.find_by(amount: vat_account_info.vat_percentage)

        unless tax_account.present? && tax
          tax = create_tax_account(vat_account_info, clean_tax_account_number)
        end
      end
      tax
    end

    def create_tax_account(vat_account_info, clean_tax_account_number)
      tax_account = Account.find_or_create_by_number(clean_tax_account_number)
      tax = Tax.find_by(amount: vat_account_info.vat_percentage, collect_account_id: tax_account.id)

      unless tax
        tax = Tax.find_on(vat_account_info.invoiced_at.to_date, country: Preference[:country].to_sym, amount: vat_account_info.vat_percentage)
        tax.collect_account_id = tax_account.id
        tax.active = true
        tax.save!
      end
      tax
    end

    def check_or_create_product_account(product_account_line)
      clean_account_number = product_account_line.account_number.to_s[0..Preference[:account_number_digits]]
      computed_name = "Service - Vente en ligne - #{clean_account_number}"
      product_account = Account.find_or_create_by_number(clean_account_number)
    end

    def create_variant(product_account, product_account_line)
      clean_account_number = product_account_line.account_number.to_s[0..Preference[:account_number_digits]]
      computed_name = "Service - Vente en ligne - #{clean_account_number}"

      pnc = ProductNatureCategory.create_with(name: computed_name, active: true, saleable: true, product_account_id: product_account.id)
          .find_or_initialize_by(product_account_id: product_account.id, name: computed_name)

      pn = ProductNature.create_with(active: true, name: computed_name, category: pnc, variety: 'service', population_counting: 'decimal')
          .find_or_initialize_by(category: pnc, name: computed_name)

      if pn
        pn.variants.build(active: true,
                          name: computed_name,
                          providers: {'panier_local' => product_account_line.account_number},
                          unit_name: 'unity'
                         )
      end
    end

    def create_pretax_amount(product_account_line)
      if product_account_line.sale_item_sens == 'D'
        product_account_line.sale_item_amount * -1
      elsif product_account_line.sale_item_sens == 'C'
        product_account_line.sale_item_amount
      end
    end

  end
end



