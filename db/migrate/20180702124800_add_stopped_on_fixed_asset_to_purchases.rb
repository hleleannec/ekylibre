class AddStoppedOnFixedAssetToPurchases < ActiveRecord::Migration[4.2]
  def up
    add_column :purchase_items, :fixed_asset_stopped_on, :date, default: nil
  end

  def down
    remove_column :purchase_items, :fixed_asset_stopped_on
  end
end
