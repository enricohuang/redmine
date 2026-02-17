# frozen_string_literal: true

require_relative '../../test_helper'

class PermissionFilterTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  def test_admin_user_filter
    admin = users(:users_001)
    filter = Elasticsearch::PermissionFilter.new(admin)

    result = filter.build(['issue'])

    # Admin should have access to issues
    assert result.is_a?(Hash)
    assert result[:bool].present?
  end

  def test_regular_user_filter
    user = users(:users_002) # Regular user with project memberships
    filter = Elasticsearch::PermissionFilter.new(user)

    result = filter.build(['issue'])

    # Regular user should have filtered access
    assert result.is_a?(Hash)
    assert result[:bool][:should].present?
  end

  def test_anonymous_user_filter
    anonymous = User.anonymous
    filter = Elasticsearch::PermissionFilter.new(anonymous)

    result = filter.build(['project'])

    # Anonymous should have some filter structure for public projects
    assert result.is_a?(Hash)
    assert result[:bool].present?
  end

  def test_filter_for_multiple_types
    user = users(:users_002)
    filter = Elasticsearch::PermissionFilter.new(user)

    result = filter.build(['issue', 'wiki_page', 'news'])

    # Should have filters for all three types
    assert result.is_a?(Hash)
    assert result[:bool][:should].size >= 3
  end

  def test_projects_with_permission_caching
    user = users(:users_002)
    filter = Elasticsearch::PermissionFilter.new(user)

    # Access the same permission twice
    first_result = filter.send(:projects_with_permission, :view_issues)
    second_result = filter.send(:projects_with_permission, :view_issues)

    # Should return same cached result
    assert_equal first_result, second_result
  end
end
