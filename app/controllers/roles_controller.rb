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

class RolesController < ApplicationController
  layout 'admin'
  self.main_menu = false

  before_action :require_admin, :except => [:index, :show]
  before_action :require_admin_or_api_request, :only => [:index, :show]
  before_action :find_role, :only => [:show, :edit, :update, :destroy]
  accept_api_auth :index, :show, :create, :update, :destroy, :permissions, :update_permissions

  include RolesHelper

  require_sudo_mode :create, :update, :destroy

  def index
    respond_to do |format|
      format.html do
        @roles = Role.sorted.to_a
        render :layout => false if request.xhr?
      end
      format.api do
        @roles =
          if params[:include_builtin].present? && User.current.admin?
            Role.sorted.to_a
          else
            Role.givable.to_a
          end
      end
    end
  end

  def show
    respond_to do |format|
      format.api
    end
  end

  def new
    # Prefills the form with 'Non member' role permissions by default
    @role = Role.new
    @role.safe_attributes = params[:role] || {:permissions => Role.non_member.permissions}
    if params[:copy].present? && @copy_from = Role.find_by_id(params[:copy])
      @role.copy_from(@copy_from)
    end
    @roles = Role.sorted.to_a
  end

  def create
    @role = Role.new
    @role.safe_attributes = params[:role]
    if request.post? && @role.save
      # workflow copy
      if params[:copy_workflow_from].present? && (copy_from = Role.find_by_id(params[:copy_workflow_from]))
        @role.copy_workflow_rules(copy_from)
      end
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_create)
          redirect_to roles_path
        end
        format.api {render :action => 'show', :status => :created, :location => role_url(@role)}
      end
    else
      respond_to do |format|
        format.html do
          @roles = Role.sorted.to_a
          render :action => 'new'
        end
        format.api {render_validation_errors(@role)}
      end
    end
  end

  def edit
  end

  def update
    @role.safe_attributes = params[:role]
    if @role.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to roles_path(:page => params[:page])
        end
        format.js {head :ok}
        format.api {render_api_ok}
      end
    else
      respond_to do |format|
        format.html {render :action => 'edit'}
        format.js   {head :unprocessable_content}
        format.api  {render_validation_errors(@role)}
      end
    end
  end

  def destroy
    @role.destroy
    respond_to do |format|
      format.html {redirect_to roles_path}
      format.api {render_api_ok}
    end
  rescue
    if api_request?
      render_api_errors l(:error_can_not_remove_role)
      return
    end

    flash.now[:error] = l(:error_can_not_remove_role)

    if @role.members.present?
      projects = Project.joins(members: :member_roles).where(member_roles: { role_id: @role.id }).distinct.sorted
      links = projects.map do |p|
        view_context.link_to(p, settings_project_path(p, tab: 'members'))
      end.join(', ')
      flash.now[:error] += l(:error_can_not_remove_role_reason_members_html, projects: links)
    end
    @roles = Role.sorted.to_a
    render :index
  end

  def permissions
    scope = Role.sorted
    if params[:ids].present?
      scope = scope.where(:id => params[:ids])
    end
    @roles = scope.to_a
    @permissions = Redmine::AccessControl.permissions.reject(&:public?)
    respond_to do |format|
      format.html
      format.csv do
        send_data(permissions_to_csv(@roles, @permissions), :type => 'text/csv; header=present', :filename => 'permissions.csv')
      end
      format.api
    end
  end

  def update_permissions
    unless params[:permissions].present?
      respond_to do |format|
        format.html {redirect_to roles_path}
        format.api {render_api_errors 'permissions is required'}
      end
      return
    end

    @roles = Role.where(:id => params[:permissions].keys)
    @roles.each do |role|
      role.permissions = params[:permissions][role.id.to_s]
      role.save
    end
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_update)
        redirect_to roles_path
      end
      format.api {render_api_ok}
    end
  end

  private

  def find_role
    @role = Role.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
