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

class CustomFieldEnumerationsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin
  before_action :find_custom_field
  before_action :find_enumeration, :only => [:update, :destroy]

  accept_api_auth :index, :create, :update, :update_each, :destroy

  helper :custom_fields

  def index
    @values = @custom_field.enumerations.order(:position)
    respond_to do |format|
      format.html
      format.api
    end
  end

  def create
    @value = @custom_field.enumerations.build
    @value.attributes = enumeration_params
    if @value.save
      respond_to do |format|
        format.html {redirect_to custom_field_enumerations_path(@custom_field)}
        format.js
        format.api {render :action => 'show', :status => :created, :location => custom_field_enumeration_url(@custom_field, @value)}
      end
    else
      respond_to do |format|
        format.html {redirect_to custom_field_enumerations_path(@custom_field)}
        format.js
        format.api {render_validation_errors(@value)}
      end
    end
  end

  def update
    @value.attributes = enumeration_params
    if @value.save
      respond_to do |format|
        format.html {redirect_to custom_field_enumerations_path(@custom_field)}
        format.api {render_api_ok}
      end
    else
      respond_to do |format|
        format.html {redirect_to custom_field_enumerations_path(@custom_field)}
        format.api {render_validation_errors(@value)}
      end
    end
  end

  def update_each
    saved = CustomFieldEnumeration.update_each(@custom_field, update_each_params)
    respond_to do |format|
      if saved
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to :action => 'index'
        end
        format.api {render_api_ok}
      else
        format.html {redirect_to :action => 'index'}
        format.api {render_api_errors 'Unable to update custom field enumerations'}
      end
    end
  end

  def destroy
    reassign_to = @custom_field.enumerations.find_by_id(params[:reassign_to_id])
    if reassign_to.nil? && @value.in_use?
      if api_request?
        render_api_errors 'Unable to delete custom field enumeration'
        return
      end
      @enumerations = @custom_field.enumerations - [@value]
      render :action => 'destroy'
      return
    end
    @value.destroy(reassign_to)
    respond_to do |format|
      format.html {redirect_to custom_field_enumerations_path(@custom_field)}
      format.api {render_api_ok}
    end
  end

  private

  def find_custom_field
    @custom_field = CustomField.find(params[:custom_field_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_enumeration
    @value = @custom_field.enumerations.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def enumeration_params
    params.require(:custom_field_enumeration).permit(:name, :active, :position)
  end

  def update_each_params
    # params.require(:custom_field_enumerations).permit(:name, :active, :position) does not work here with param like this:
    # "custom_field_enumerations":{"0":{"name": ...}, "1":{"name...}}
    params.permit(:custom_field_enumerations => [:name, :active, :position]).require(:custom_field_enumerations)
  end
end
