class CreateProductionsAndComponents < ActiveRecord::Migration
  def self.up

    # ProductComponent
    create_table :product_components do |t|
      t.column :name,           :string,   :null=>false
      t.column :product_id,     :integer,  :null=>false, :references=>:products, :on_delete=>:restrict, :on_update=>:restrict
      t.column :component_id,   :integer,  :null=>false, :references=>:products, :on_delete=>:restrict, :on_update=>:restrict
      t.column :location_id,    :integer,  :null=>false, :references=>:stock_locations, :on_delete=>:restrict, :on_update=>:restrict
      t.column :quantity,       :decimal,  :null=>false, :precision=>16, :scale=>2
      t.column :comment,        :text
      t.column :active,         :boolean,  :null=>false
      t.column :started_at,     :datetime
      t.column :stopped_at,     :datetime
      t.column :company_id,     :integer,  :null=>false, :references=>:companies, :on_delete=>:restrict, :on_update=>:restrict
      t.stamps
    end
    add_stamps_indexes :product_components

    # Productions
    create_table :productions do |t|
      t.column :product_id,     :integer,  :null=>false, :references=>:products,  :on_delete=>:restrict, :on_update=>:restrict
      t.column :quantity,       :decimal,  :null=>false, :precision=>16, :scale=>2, :default=>0.0.to_d
      t.column :location_id,    :integer,  :null=>false, :references=>:stock_locations, :on_delete=>:restrict, :on_update=>:restrict
      t.column :planned_on,     :date,     :null=>false
      t.column :moved_on,       :date,     :null=>false
      t.column :company_id,     :integer,  :null=>false, :references=>:companies, :on_delete=>:restrict, :on_update=>:restrict
      t.stamps
    end
    add_stamps_indexes :productions

    # Columns
    add_column :stock_moves,  :origin_type,    :string
    add_column :stock_moves,  :origin_id,      :integer, :references=>nil
  end

  def self.down
    remove_column :stock_moves, :origin_type
    remove_column :stock_moves, :origin_id
    drop_table :productions
    drop_table :product_components
  end
end
