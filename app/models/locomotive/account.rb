require 'digest'

module Locomotive
  class Account

    include Locomotive::Mongoid::Document

    devise *Locomotive.config.devise_modules

    ## attributes ##
    field :name
    field :locale, :default => Locomotive.config.default_locale.to_s or 'en'
    field :switch_site_token

    ## validations ##
    validates_presence_of :name

    ## associations ##

    ## callbacks ##
    before_destroy :remove_memberships!

    ## methods ##

    def sites
      @sites ||= Site.where({ 'memberships.account_id' => self._id })
    end

    def reset_switch_site_token!
      self.switch_site_token = SecureRandom.base64(8).gsub("/", "_").gsub(/=+$/, "")
      self.save
    end

    def self.find_using_switch_site_token(token, age = 1.minute)
      return if token.blank?
      self.where(:switch_site_token => token, :updated_at.gt => age.ago.utc).first
    end

    def self.find_using_switch_site_token!(token, age = 1.minute)
      self.find_using_switch_site_token(token, age) || raise(::Mongoid::Errors::DocumentNotFound.new(self, token))
    end

    # Create the API token which will be passed to all the requests to the Locomotive API.
    # It requires the credentials of an account with admin role.
    # If an error occurs (invalid account, ...etc), this method raises an exception that has
    # to be caught somewhere.
    #
    # @param [ Site ] site The site where the authentication request is made
    # @param [ String ] email The email of the account
    # @param [ String ] password The password of the account
    #
    # @return [ String ] The API token
    #
    def self.create_api_token(site, email, password)
      raise 'The request must contain the user email and password.' if email.blank? or password.blank?

      account = self.where(:email => email.downcase).first

      raise 'Invalid email or password.' if account.nil?

      account.ensure_authentication_token!

      if not account.valid_password?(password) # TODO: check admin roles
        raise 'Invalid email or password.'
      end

      account.authentication_token
    end

    # Logout the user responding to the token passed in parameter from the API.
    # An exception is raised if no account corresponds to the token.
    #
    # @param [ String ] token The API token created by the create_api_token method.
    #
    # @return [ String ] The API token
    #
    def self.invalidate_api_token(token)
      account = self.where(:authentication_token => token).first

      raise 'Invalid token.' if account.nil?

      account.reset_authentication_token!

      token
    end

    def devise_mailer
      Locomotive::DeviseMailer
    end

    def as_json(options = {})
      Locomotive::AccountPresenter.new(self, options).as_json
    end

    protected

    def password_required?
      !persisted? || !password.blank? || !password_confirmation.blank?
    end

    def remove_memberships!
      self.sites.each do |site|
        membership = site.memberships.where(:account_id => self._id).first

        if site.admin_memberships.size == 1 && membership.admin?
          raise I18n.t('errors.messages.needs_admin_account')
        else
          membership.destroy
        end
      end
    end

  end
end
