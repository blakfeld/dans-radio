class User < ApplicationRecord
  has_secure_password

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, presence: true,
                       uniqueness: { case_sensitive: false },
                       length: { minimum: 3, maximum: 30 }
  validates :password, length: { minimum: 6 }, allow_nil: true

  # Callbacks
  before_save :downcase_email_and_username

  # Constants
  MAX_FAILED_LOGIN_ATTEMPTS = 5
  LOCK_TIME_DURATION = 30.minutes

  # Scopes
  scope :admins, -> { where(admin: true) }
  scope :active, -> { where(locked_at: nil) }
  scope :locked, -> { where.not(locked_at: nil) }

  # Instance Methods
  def full_name
    return username if first_name.blank? && last_name.blank?
    "#{first_name} #{last_name}".strip
  end

  def display_name
    full_name.presence || username
  end

  def locked?
    locked_at.present? && locked_at > LOCK_TIME_DURATION.ago
  end

  def unlock!
    update(locked_at: nil, failed_login_attempts: 0)
  end

  def lock!
    update(locked_at: Time.current)
  end

  def record_failed_login!
    self.failed_login_attempts += 1
    if failed_login_attempts >= MAX_FAILED_LOGIN_ATTEMPTS
      lock!
    else
      save
    end
  end

  def record_successful_login!
    update(
      last_login_at: Time.current,
      failed_login_attempts: 0,
      locked_at: nil
    )
  end

  def generate_remember_token!
    self.remember_token = SecureRandom.urlsafe_base64(32)
    self.remember_token_expires_at = 30.days.from_now
    save!
    remember_token
  end

  def clear_remember_token!
    update(remember_token: nil, remember_token_expires_at: nil)
  end

  def valid_remember_token?(token)
    return false if remember_token.blank? || token.blank?
    return false if remember_token_expires_at.blank? || remember_token_expires_at < Time.current

    ActiveSupport::SecurityUtils.secure_compare(remember_token, token)
  end

  # Class Methods
  def self.authenticate(login, password)
    user = find_by(email: login.downcase) || find_by(username: login.downcase)
    return nil unless user

    if user.locked?
      return nil
    end

    if user.authenticate(password)
      user.record_successful_login!
      user
    else
      user.record_failed_login!
      nil
    end
  end

  def self.find_by_remember_token(token)
    return nil if token.blank?
    user = find_by(remember_token: token)
    return nil unless user&.valid_remember_token?(token)
    user
  end

  private

  def downcase_email_and_username
    self.email = email&.downcase
    self.username = username&.downcase
  end
end
