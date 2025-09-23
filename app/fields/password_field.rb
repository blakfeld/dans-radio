require "administrate/field/base"

class PasswordField < Administrate::Field::Base
  def to_s
    ""  # Never display password values
  end
end
