require 'test_helper'

class AuthoriseApplicationTest < ActionDispatch::IntegrationTest
  setup do
    @app = create(:application, name: "MyApp")
    @user = create(:user)
  end

  context "when the user is flagged for 2SV" do
    setup do
      @user.update_attribute(:require_2sv, true)
      ignoring_spurious_error do
        visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
      end
      signin(@user)
    end

    should "not confirm the authorisation" do
      assert_response_contains("Make your account more secure")
    end

    context "when the user defers 2SV" do
      should "redirect them to the originally authorised app" do
        ignoring_spurious_error do
          click_button "Not now"
        end

        assert_redirected_to_application @app
      end
    end
  end

  should "not confirm the authorisation until the user signs in" do
    visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
    assert_response_contains("You need to sign in")
    refute Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)

    ignoring_spurious_error do
      signin(@user)
    end

    assert_redirected_to_application @app
    # check the access grant has really been created
    assert_kind_of Doorkeeper::AccessGrant, Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)
  end

  should "not confirm the authorisation if the user's passphrase has expired" do
    @user.password_changed_at = 91.days.ago
    @user.save!

    visit "/"
    signin(@user)
    ignoring_spurious_error do
      visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
    end
    assert_response_contains("Choose a new passphrase")
    refute Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)
  end

  should "not confirm the authorisation if the user has not passed 2-step verification" do
    @user.update_attribute(:otp_secret_key, ROTP::Base32.random_base32)

    visit "/"
    signin(@user)
    ignoring_spurious_error do
      visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
    end
    assert_response_contains("get your code")
    refute Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)
  end

  should "confirm the authorisation for a signed-in user" do
    visit "/"
    signin(@user)
    ignoring_spurious_error do
      visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
    end

    assert_redirected_to_application @app
    assert_kind_of Doorkeeper::AccessGrant, Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)
  end

  should "confirm the authorisation for a fully authenticated 2SV user" do
    @user.update_attribute(:otp_secret_key, ROTP::Base32.random_base32)

    visit "/"
    signin_with_2sv(@user)
    ignoring_spurious_error do
      visit "/oauth/authorize?response_type=code&client_id=#{@app.uid}&redirect_uri=#{@app.redirect_uri}"
    end

    assert_redirected_to_application @app
    assert_kind_of Doorkeeper::AccessGrant, Doorkeeper::AccessGrant.find_by(resource_owner_id: @user.id)
  end

  def assert_redirected_to_application(app)
    assert_match /^#{app.redirect_uri}/, current_url
    assert_match /\?code=/, current_url
  end

  def ignoring_spurious_error(&block)
    # During testing, requests for all domains get routed to Signon;
    # including the capybara browser being redirected to other apps.
    # The browser gets a redirect to url of the destination app.
    # This then gets routed to Signon but Signon doesn't know how to handle the route.
    # And so it raises the RoutingError
    begin
      block.call
    rescue ActionController::RoutingError
    end
  end
end
