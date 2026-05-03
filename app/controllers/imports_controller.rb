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

require 'csv'

class ImportsController < ApplicationController
  before_action :find_import, :only => [:show, :settings, :mapping, :run]
  before_action :authorize_import

  layout :import_layout

  helper :issues
  helper :queries

  accept_api_auth :create, :show, :settings, :mapping, :run

  def new
    @import = import_type.new
  end

  def create
    @import = import_type.new
    @import.user = User.current
    @import.file = params[:file]
    @import.set_default_settings(:project_id => params[:project_id])

    if @import.save
      respond_to do |format|
        format.html {redirect_to import_settings_path(@import)}
        format.api do
          prepare_import_api_response
          render :action => 'show', :status => :created, :location => import_url(@import.id)
        end
      end
    else
      respond_to do |format|
        format.html {render :action => 'new'}
        format.api {render_validation_errors(@import)}
      end
    end
  end

  def show
    respond_to do |format|
      format.html
      format.api {prepare_import_api_response}
    end
  end

  def settings
    if import_update_request?
      @import.parse_file
      if @import.total_items == 0
        respond_to do |format|
          format.html {flash.now[:error] = l(:error_no_data_in_file)}
          format.api {render_api_errors l(:error_no_data_in_file)}
        end
      else
        respond_to do |format|
          format.html {redirect_to import_mapping_path(@import)}
          format.api do
            prepare_import_api_response
            render :action => 'show'
          end
        end
      end
      return
    end

    respond_to do |format|
      format.html
      format.api {prepare_import_api_response}
    end
  rescue CSV::MalformedCSVError, EncodingError => e
    message = import_file_error_message(e)
    respond_to do |format|
      format.html {flash.now[:error] = message}
      format.api {render_api_errors message}
    end
  rescue SystemCallError => e
    message = import_file_error_message(e)
    respond_to do |format|
      format.html {flash.now[:error] = message}
      format.api {render_api_errors message}
    end
  end

  def mapping
    @custom_fields = @import.mappable_custom_fields

    if request.get?
      auto_map_fields
      @import.save! if api_request?
      respond_to do |format|
        format.html
        format.api do
          prepare_import_api_response
          render :action => 'show'
        end
      end
    elsif import_update_request?
      respond_to do |format|
        format.html do
          if params[:previous]
            redirect_to import_settings_path(@import)
          else
            redirect_to import_run_path(@import)
          end
        end
        format.js # updates mapping form on project or tracker change
        format.api do
          prepare_import_api_response
          render :action => 'show'
        end
      end
    end
  end

  def run
    if request.post?
      @current = @import.run(
        :max_items => max_items_per_request,
        :max_time => 10.seconds
      )
      respond_to do |format|
        format.html do
          if @import.finished?
            redirect_to import_path(@import)
          else
            redirect_to import_run_path(@import)
          end
        end
        format.js
        format.api do
          prepare_import_api_response
          render :action => 'show'
        end
      end
      return
    end

    respond_to do |format|
      format.html
      format.api {prepare_import_api_response}
    end
  end

  def current_menu(project)
    if import_layout == 'admin'
      nil
    else
      :application_menu
    end
  end

  private

  def find_import
    @import = find_current_user_import
    if @import.nil?
      render_404
      return
    elsif @import.finished? && action_name != 'show'
      if api_request?
        prepare_import_api_response
        render :action => 'show'
      else
        redirect_to import_path(@import)
      end
      return
    end
    update_from_params if import_update_request?
  end

  def find_current_user_import
    scope = Import.where(:user_id => User.current.id)
    if api_request? && /\A\d+\z/.match?(params[:id].to_s)
      scope.find_by(:id => params[:id]) || scope.find_by(:filename => params[:id])
    else
      scope.find_by(:filename => params[:id])
    end
  end

  def update_from_params
    import_settings = params[:import_settings] || params[:settings]
    if import_settings.present?
      @import.settings ||= {}
      @import.settings.merge!(import_settings.to_unsafe_hash)
      @import.save!
    end
  end

  def import_update_request?
    request.post? || request.put? || request.patch?
  end

  def max_items_per_request
    5
  end

  def import_layout
    import_type && import_type.layout || 'base'
  end

  def menu_items
    menu_item = import_type ? import_type.menu_item : nil
    {self.controller_name.to_sym => {:actions => {}, :default => menu_item}}
  end

  def authorize_import
    return render_404 unless import_type
    return render_403 unless import_type.authorized?(User.current)
  end

  def import_type
    return @import_type if defined? @import_type

    @import_type =
      if @import
        @import.class
      else
        type =
          begin
            Object.const_get(params[:type])
          rescue
            nil
          end
        type && type < Import ? type : nil
      end
  end

  def prepare_import_api_response
    @import_state = import_state
    @processed_count = @import.items.count
    @saved_count = @import.saved_items.count
    @unsaved_count = @import.unsaved_items.count
    @import_headers = []
    @import_sample_rows = []
    @import_preview_error = nil

    if @import.file_exists?
      begin
        @import_headers = @import.headers
        @import_sample_rows = @import.first_rows
      rescue CSV::MalformedCSVError, EncodingError, SystemCallError => e
        @import_preview_error = import_file_error_message(e)
      end
    end
  end

  def import_state
    return 'finished' if @import.finished?
    return 'running' if @import.items.exists?
    return 'empty' if @import.total_items == 0
    return 'mapped' if mapped_import?
    return 'settings_validated' if @import.total_items.present?

    'uploaded'
  end

  def mapped_import?
    mapping = @import.mapping
    mapping.present? && (mapping.keys.map(&:to_s) - ['project_id']).present?
  end

  def import_file_error_message(exception)
    if exception.is_a?(CSV::MalformedCSVError) && !exception.message.include?('Invalid byte sequence')
      l(:error_invalid_csv_file_or_settings, exception.message)
    elsif exception.is_a?(EncodingError) || exception.is_a?(CSV::MalformedCSVError)
      l(:error_invalid_file_encoding, :encoding => ERB::Util.h(@import.settings['encoding']))
    else
      l(:error_can_not_read_import_file)
    end
  end

  def auto_map_fields
    # Try to auto map fields only when settings['enconding'] is present
    # otherwhise, the import fails for non UTF-8 files because the headers
    # cannot be retrieved (Invalid byte sequence in UTF-8)
    return if @import.settings['encoding'].blank?

    mappings = @import.settings['mapping'] ||= {}
    headers = @import.headers.map{|header| header&.downcase}

    # Core fields
    import_type::AUTO_MAPPABLE_FIELDS.each do |field_nm, label_nm|
      next if mappings.include?(field_nm)

      index = headers.index(field_nm) || headers.index(l(label_nm).downcase)
      if index
        mappings[field_nm] = index
      end
    end

    # Custom fields
    @custom_fields.each do |field|
      field_nm = "cf_#{field.id}"
      next if mappings.include?(field_nm)

      index = headers.index(field_nm) || headers.index(field.name.downcase)
      if index
        mappings[field_nm] = index
      end
    end
    mappings
  end
end
