class RenameDomainAdminRoleToRoot < ActiveRecord::Migration[8.2]
  def up
    execute "UPDATE users SET role = 'root' WHERE role = 'domain_admin'"
  end

  def down
    execute "UPDATE users SET role = 'domain_admin' WHERE role = 'root'"
  end
end
