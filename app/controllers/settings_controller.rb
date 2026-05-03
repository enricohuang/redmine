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

class SettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :plugins, :only => :plugin

  helper :queries

  before_action :require_admin

  accept_api_auth :index, :edit, :plugin

  require_sudo_mode :index, :edit, :plugin

  SENSITIVE_SETTING_NAMES = %w[
    sys_api_key
    attachment_indexer_api_key
    mail_handler_api_key
  ].freeze

  def index
    respond_to do |format|
      format.html do
        edit
        render :action => 'edit'
      end
      format.api do
        build_settings_api_response
      end
    end
  end

  def edit
    if request.post? || request.patch? || request.put?
      settings = params[:settings] ? params[:settings].to_unsafe_hash : {}
      errors = Setting.set_all_from_params(settings)
      respond_to do |format|
        if errors.blank?
          format.html do
            flash[:notice] = l(:notice_successful_update)
            redirect_to settings_path(:tab => params[:tab])
          end
          format.api {render_api_ok}
        else
          format.html do
            @setting_errors = errors
            prepare_settings_form
            render :action => 'edit'
          end
          format.api {render_api_errors setting_error_messages(errors)}
        end
      end
      return
    end

    prepare_settings_form
    respond_to do |format|
      format.html
      format.api do
        build_settings_api_response
        render :action => 'index'
      end
    end
  end

  def prepare_settings_form
    @notifiables = Redmine::Notifiable.all
    @options = {}
    user_format = User::USER_FORMATS.collect{|key, value| [key, value[:setting_order]]}.sort_by{|f| f[1]}
    @options[:user_format] = user_format.collect{|f| [User.current.name(f[0]), f[0].to_s]}
    @deliveries = ActionMailer::Base.perform_deliveries

    @guessed_host_and_path = request.host_with_port.dup
    @guessed_host_and_path << ("/#{Redmine::Utils.relative_url_root.delete_prefix('/')}") unless Redmine::Utils.relative_url_root.blank?

    @commit_update_keywords = Setting.commit_update_keywords.dup
    @commit_update_keywords = [{}] unless @commit_update_keywords.is_a?(Array) && @commit_update_keywords.any?

    Redmine::Themes.rescan
  end

  def plugin
    @plugin = Redmine::Plugin.find(params[:id])
    unless @plugin.configurable?
      render_404
      return
    end

    if request.post? || request.patch? || request.put?
      setting = params[:settings] ? params[:settings].permit!.to_h : {}
      Setting.send :"plugin_#{@plugin.id}=", setting
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to plugin_settings_path(@plugin)
        end
        format.api {render_api_ok}
      end
    else
      @partial = @plugin.settings[:partial]
      @settings = Setting.send :"plugin_#{@plugin.id}"
      @plugin_settings = plugin_settings_api_response(@settings)
      respond_to do |format|
        format.html
        format.api
      end
    end
  rescue Redmine::PluginNotFound
    render_404
  end

  private

  def build_settings_api_response
    @settings = Setting.available_settings.keys.sort.map do |name|
      options = Setting.available_settings[name] || {}
      sensitive = sensitive_setting?(name)
      value = Setting[name]
      {
        :name => name,
        :value => sensitive ? nil : value,
        :has_value => value.present?,
        :sensitive => sensitive,
        :format => options['format'],
        :serialized => !!options['serialized'],
        :security_notifications => !!options['security_notifications']
      }
    end
  end

  def sensitive_setting?(name)
    SENSITIVE_SETTING_NAMES.include?(name.to_s)
  end

  def setting_error_messages(errors)
    errors.map do |attribute, message|
      "#{attribute} #{message}"
    end
  end

  def plugin_settings_api_response(settings)
    settings.to_h.sort.map do |key, value|
      sensitive = sensitive_plugin_setting?(key)
      {
        :name => key.to_s,
        :value => sensitive ? nil : mask_plugin_setting_value(value),
        :has_value => value.present?,
        :sensitive => sensitive
      }
    end
  end

  def mask_plugin_setting_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, child_value), result|
        result[key] =
          if sensitive_plugin_setting?(key)
            nil
          else
            mask_plugin_setting_value(child_value)
          end
      end
    when Array
      value.map {|child_value| mask_plugin_setting_value(child_value)}
    else
      value
    end
  end

  def sensitive_plugin_setting?(name)
    name.to_s.match?(/password|secret|token|api[_-]?key/i)
  end
end
