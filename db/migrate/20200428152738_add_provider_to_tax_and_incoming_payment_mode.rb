class AddProviderToTaxAndIncomingPaymentMode < ActiveRecord::Migration[4.2]
  def change
    %i[incoming_payment_modes taxes].each { |name| add_provider_to(name) }
  end

  def add_provider_to(table_name)
    add_column table_name, :provider, :jsonb

    reversible do |dir|
      dir.up do
        query("CREATE INDEX #{table_name.to_s.singularize}_provider_index ON #{table_name} USING gin ((provider -> 'vendor'), (provider -> 'name'), (provider -> 'id'))")
      end
      dir.down do
        query("DROP INDEX #{table_name.to_s.singularize}_provider_index")
      end
    end
  end
end
