class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  #
  # :registerable is deliberately absent. This is an internal admin console and
  # AdminController admits any signed-in user, so public sign-up at
  # /users/sign_up handed full admin to anyone. Staff accounts are created by
  # an existing admin under /admin/users.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  def has_permission_set?(set_name)
    permission_sets.include?(set_name)
  end

  def add_permission_set(set_name)
    self.permission_sets = (permission_sets + [ set_name ]).uniq
    save
  end

  def remove_permission_set(set_name)
    self.permission_sets = permission_sets - [ set_name ]
    save
  end
end
