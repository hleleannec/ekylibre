require 'test_helper'

module Backend
  class CampaignsControllerTest < Ekylibre::Testing::ApplicationControllerTestCase::WithFixtures
    # TODO: Re-activate #close test
    test_restfully_all_actions except: %i[open current close show_by_name]

    test 'open action in post mode' do
      post :open, params: { locale: @locale, activity_id: activities(:activities_001).id, id: campaigns(:campaigns_001).id }
      assert_redirected_to backend_campaign_path(campaigns(:campaigns_001))
    end

    test 'current action in get mode' do
      get :current, params: { locale: @locale }
      assert_redirected_to backend_campaign_path(@user.current_campaign)
    end
  end
end
