# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative '../../../test_helper'

class ThemesTest < Redmine::IntegrationTest
  def setup
    @theme = Redmine::Themes::Theme.new(Rails.root.join('test/fixtures/themes/foo_theme'))
    Redmine::Themes.rescan
  end

  def teardown
    Setting.ui_theme = ''
  end

  def test_no_installed_themes
    # With alternate/classic removed, no production themes should be found
    themes = Redmine::Themes.themes
    assert_kind_of Array, themes
  end

  def test_without_theme
    Setting.ui_theme = ''
    get '/'

    assert_response :success
  end

  def test_old_theme_compatibility
    Rails.application.config.assets.redmine_extension_paths << @theme.asset_paths
    Setting.ui_theme = @theme.id
    Rails.application.assets.load_path.clear_cache

    asset = Rails.application.assets.load_path.find('themes/foo_theme/application.css')
    get "/assets/#{asset.digested_path}"

    assert_response :success
  end

  def test_body_css_class_with_spaces_in_theme_name
    @theme.instance_variable_set(:@name, 'Foo bar baz')
    # Temporarily add the theme to the list
    Redmine::Themes.themes << @theme
    Setting.ui_theme = @theme.id
    get '/'

    assert_response :success
    assert_select 'body[class~="theme-Foo_bar_baz"]'
  ensure
    Redmine::Themes.themes.delete(@theme)
  end
end
