class AddManageLabelsPermissionToRoles < ActiveRecord::Migration[8.1]
  # Grants the fork-added :manage_labels permission to any role that already
  # has :manage_categories — its closest sibling (managing project-scoped
  # metadata for issues). Without this migration, sites upgrading from
  # upstream Redmine end up with no role that can manage labels via the UI;
  # only admin users can do so.
  def up
    Role.find_each do |r|
      r.add_permission!(:manage_labels) if r.permissions.include?(:manage_categories)
    end
  end

  def down
    Role.find_each do |r|
      r.remove_permission!(:manage_labels)
    end
  end
end
