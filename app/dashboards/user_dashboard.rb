require "administrate/base_dashboard"
require_relative "../fields/password_field"

class UserDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    username: Field::String,
    email: Field::String,
    first_name: Field::String,
    last_name: Field::String,
    admin: Field::Boolean,
    password: PasswordField,
    password_confirmation: PasswordField,
    last_login_at: Field::DateTime,
    failed_login_attempts: Field::Number,
    locked_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    username
    email
    admin
    last_login_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    username
    email
    first_name
    last_name
    admin
    last_login_at
    failed_login_attempts
    locked_at
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    username
    email
    first_name
    last_name
    password
    password_confirmation
    admin
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {
    admin: ->(resources) { resources.where(admin: true) },
    locked: ->(resources) { resources.where.not(locked_at: nil) },
    active: ->(resources) { resources.where(locked_at: nil) }
  }.freeze

  # Overwrite this method to customize how users are displayed
  # across all pages of the admin dashboard.
  #
  def display_resource(user)
    user.display_name
  end
end
