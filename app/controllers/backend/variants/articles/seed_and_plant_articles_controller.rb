module Backend
  module Variants
    module Articles
      class SeedAndPlantArticlesController < Backend::Variants::ArticleVariantsController
        importable_from_lexicon :master_variants, model_name: "Variants::Articles::#{controller_name.classify}".constantize,
                                                  primary_key: :reference_name,
                                                  filters: { of_families: :article, of_sub_families: :seed_and_plant }
      end
    end
  end
end
