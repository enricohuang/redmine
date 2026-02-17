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

class LabelsController < ApplicationController
  self.model_object = Label

  # Colors for inline label creation (GitHub-inspired palette)
  INLINE_COLORS = %w[
    #0075ca #e4e669 #008672 #d73a4a #cfd3d7
    #a2eeef #7057ff #e99695 #f9d0c4 #0e8a16
    #c5def5 #bfdadc #d4c5f9 #006b75 #b60205
    #fbca04 #5319e7 #1d76db #cc317c #0052cc
  ].freeze

  menu_item :settings
  before_action :find_model_object, except: [:index, :new, :create, :create_inline]
  before_action :find_project_from_association, except: [:index, :new, :create, :create_inline]
  before_action :find_project_by_project_id, only: [:index, :new, :create, :create_inline]
  before_action :authorize, except: [:create_inline]
  before_action :authorize_create_inline, only: [:create_inline]

  accept_api_auth :index, :show, :create, :update, :destroy

  def index
    respond_to do |format|
      format.html { redirect_to_settings_in_projects }
      format.api do
        @labels = @project.labels.order(:name)
      end
    end
  end

  def show
    respond_to do |format|
      format.api
    end
  end

  def new
    @label = @project.labels.build
    @label.safe_attributes = params[:label]
  end

  def create
    @label = @project.labels.build
    @label.safe_attributes = params[:label]

    respond_to do |format|
      if @label.save
        format.html do
          flash[:notice] = l(:notice_successful_create)
          redirect_to_settings_in_projects
        end
        format.api { render action: 'show', status: :created, location: label_url(@label) }
      else
        format.html { render action: 'new' }
        format.api { render_validation_errors(@label) }
      end
    end
  end

  def create_inline
    name = params[:name].to_s.strip
    color = INLINE_COLORS.sample

    @label = @project.labels.build(name: name, color: color)

    if @label.save
      render json: {
        id: @label.id,
        name: @label.name,
        color: @label.color,
        text_color: @label.text_color
      }, status: :created
    else
      render json: {errors: @label.errors.full_messages}, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @label.safe_attributes = params[:label]

    respond_to do |format|
      if @label.save
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to_settings_in_projects
        end
        format.api { render_api_ok }
      else
        format.html { render action: 'edit' }
        format.api { render_validation_errors(@label) }
      end
    end
  end

  def destroy
    @label.destroy

    respond_to do |format|
      format.html { redirect_to_settings_in_projects }
      format.api { render_api_ok }
    end
  end

  private

  def authorize_create_inline
    unless User.current.allowed_to?(:edit_issues, @project) ||
           User.current.allowed_to?(:manage_labels, @project)
      deny_access
    end
  end

  def redirect_to_settings_in_projects
    redirect_to settings_project_path(@project, tab: 'labels')
  end

  def find_model_object
    super
    @label = @object
  end
end
