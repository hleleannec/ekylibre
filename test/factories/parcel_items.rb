FactoryGirl.define do
  factory :parcel_item do
    association :parcel, factory: :parcel
    association :source_product, factory: :product
    unit_pretax_amount {rand(1..100)}
    association :variant, factory: :product_nature_variant

    factory :outgoing_parcel_item do
      association :parcel, factory: :outgoing_parcel
      association :source_product, factory: :product
      unit_pretax_amount {rand(1..100)}
      association :variant, factory: :product_nature_variant
    end
  end
end
