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

class WorkflowsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  before_action :find_trackers_roles_and_statuses_for_edit, only: [:edit, :update, :permissions, :update_permissions]

  before_action :require_admin
  accept_api_auth :index, :transitions, :update_transitions, :permissions, :update_permissions, :duplicate

  def index
    @roles = Role.sorted.select(&:consider_workflow?)
    @trackers = Tracker.sorted
    @workflow_counts = WorkflowTransition.group(:tracker_id, :role_id).count
  end

  def edit
    if @trackers && @roles && @statuses.any?
      workflows = WorkflowTransition.
        where(:role_id => @roles.map(&:id), :tracker_id => @trackers.map(&:id)).
        preload(:old_status, :new_status)
      @workflows = {}
      @workflows['always'] = workflows.select {|w| !w.author && !w.assignee}
      @workflows['author'] = workflows.select {|w| w.author}
      @workflows['assignee'] = workflows.select {|w| w.assignee}
    end
  end

  def transitions
    @trackers = api_workflow_trackers
    @roles = api_workflow_roles
    @transitions = WorkflowTransition.
      where(:tracker_id => @trackers.map(&:id), :role_id => @roles.map(&:id)).
      order(:tracker_id, :role_id, :old_status_id, :new_status_id, :author, :assignee).
      to_a

    respond_to do |format|
      format.api
      format.html {redirect_to edit_workflows_path}
    end
  end

  def update_transitions
    unless api_request?
      render_404
      return
    end

    rows = Array.wrap(params[:transitions])
    tracker_ids = api_workflow_scope_ids(:tracker_id, rows)
    role_ids = api_workflow_scope_ids(:role_id, rows)

    if tracker_ids.blank? || role_ids.blank?
      render_api_errors 'tracker_id and role_id scope is required'
      return
    end

    missing = missing_workflow_references(tracker_ids, role_ids, rows, :new_status_id)
    if missing.present?
      render_api_errors missing
      return
    end

    WorkflowTransition.transaction do
      WorkflowTransition.where(:tracker_id => tracker_ids, :role_id => role_ids).delete_all
      rows.each do |row|
        WorkflowTransition.create!(
          :tracker_id => row[:tracker_id],
          :role_id => row[:role_id],
          :old_status_id => row[:old_status_id].to_i,
          :new_status_id => row[:new_status_id],
          :author => ActiveRecord::Type::Boolean.new.cast(row[:author]),
          :assignee => ActiveRecord::Type::Boolean.new.cast(row[:assignee])
        )
      end
    end

    render_api_ok
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors e.record
  end

  def update
    if @roles && @trackers && params[:transitions]
      transitions = params[:transitions].deep_dup
      transitions.each_value do |transitions_by_new_status|
        transitions_by_new_status.each_value do |transition_by_rule|
          transition_by_rule.reject! {|rule, transition| transition == 'no_change'}
        end
      end
      WorkflowTransition.replace_transitions(@trackers, @roles, transitions)
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to_referer_or edit_workflows_path
  end

  def permissions
    if api_request?
      @trackers = api_workflow_trackers
      @roles = api_workflow_roles
      @workflow_permissions = WorkflowPermission.
        where(:tracker_id => @trackers.map(&:id), :role_id => @roles.map(&:id)).
        order(:tracker_id, :role_id, :old_status_id, :field_name, :rule).
        to_a
      respond_to do |format|
        format.api
      end
      return
    end

    if @roles && @trackers
      @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
        [field, l("field_#{field.delete_suffix('_id')}")]
      end
      @custom_fields = @trackers.map(&:custom_fields).flatten.uniq.sort
      @permissions = WorkflowPermission.rules_by_status_id(@trackers, @roles)
      @statuses.each {|status| @permissions[status.id] ||= {}}
    end
  end

  def update_permissions
    if api_request?
      update_api_permissions
      return
    end

    if @roles && @trackers && params[:permissions]
      permissions = params[:permissions].deep_dup
      permissions.each_value do |rule_by_status_id|
        rule_by_status_id.reject! {|status_id, rule| rule == 'no_change'}
      end
      WorkflowPermission.replace_permissions(@trackers, @roles, permissions)
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to_referer_or permissions_workflows_path
  end

  def copy
    find_sources_and_targets
  end

  def duplicate
    find_sources_and_targets
    if params[:source_tracker_id].blank? || params[:source_role_id].blank? ||
      (@source_tracker.nil? && @source_role.nil?)
      if api_request?
        render_api_errors l(:error_workflow_copy_source)
        return
      end
      flash.now[:error] = l(:error_workflow_copy_source)
      render :copy
    elsif @target_trackers.blank? || @target_roles.blank?
      if api_request?
        render_api_errors l(:error_workflow_copy_target)
        return
      end
      flash.now[:error] = l(:error_workflow_copy_target)
      render :copy
    else
      WorkflowRule.copy(@source_tracker, @source_role, @target_trackers, @target_roles)
      if api_request?
        render_api_ok
        return
      end
      flash[:notice] = l(:notice_successful_update)
      redirect_to copy_workflows_path(
        :source_tracker_id => @source_tracker,
        :source_role_id => @source_role
      )
    end
  end

  private

  def update_api_permissions
    rows = Array.wrap(params[:permissions])
    tracker_ids = api_workflow_scope_ids(:tracker_id, rows)
    role_ids = api_workflow_scope_ids(:role_id, rows)

    if tracker_ids.blank? || role_ids.blank?
      render_api_errors 'tracker_id and role_id scope is required'
      return
    end

    missing = missing_workflow_references(tracker_ids, role_ids, rows, :old_status_id)
    if missing.present?
      render_api_errors missing
      return
    end

    WorkflowPermission.transaction do
      WorkflowPermission.where(:tracker_id => tracker_ids, :role_id => role_ids).delete_all
      rows.each do |row|
        WorkflowPermission.create!(
          :tracker_id => row[:tracker_id],
          :role_id => row[:role_id],
          :old_status_id => row[:old_status_id],
          :field_name => row[:field_name],
          :rule => row[:rule]
        )
      end
    end

    render_api_ok
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors e.record
  end

  def api_workflow_trackers
    ids = api_workflow_param_ids(:tracker_id)
    ids.present? ? Tracker.where(:id => ids).sorted.to_a : Tracker.sorted.to_a
  end

  def api_workflow_roles
    ids = api_workflow_param_ids(:role_id)
    if ids.present?
      Role.where(:id => ids).sorted.to_a
    else
      Role.sorted.select(&:consider_workflow?)
    end
  end

  def api_workflow_scope_ids(key, rows)
    ids = api_workflow_param_ids(key)
    ids = rows.filter_map {|row| row[key].presence}.map(&:to_i).uniq if ids.blank?
    ids
  end

  def api_workflow_param_ids(key)
    value = params[key] || params[:"#{key}s"]
    ids = Array.wrap(value).flat_map {|item| item.to_s.split(',')}.reject(&:blank?)
    return [] if ids == ['all']

    ids.map(&:to_i).reject(&:zero?).uniq
  end

  def missing_workflow_references(tracker_ids, role_ids, rows, status_key)
    messages = []
    found_tracker_ids = Tracker.where(:id => tracker_ids).pluck(:id)
    found_role_ids = Role.where(:id => role_ids).pluck(:id)
    status_ids = rows.filter_map {|row| row[status_key].to_i if row[status_key].present?}.uniq
    status_ids |= rows.filter_map {|row| row[:old_status_id].to_i if row[:old_status_id].present?}.uniq
    status_ids.delete(0)
    found_status_ids = IssueStatus.where(:id => status_ids).pluck(:id)

    messages << "Unknown tracker_id: #{(tracker_ids - found_tracker_ids).join(', ')}" unless (tracker_ids - found_tracker_ids).empty?
    messages << "Unknown role_id: #{(role_ids - found_role_ids).join(', ')}" unless (role_ids - found_role_ids).empty?
    messages << "Unknown status_id: #{(status_ids - found_status_ids).join(', ')}" unless (status_ids - found_status_ids).empty?
    messages
  end

  def find_sources_and_targets
    @roles = Role.sorted.select(&:consider_workflow?)
    @trackers = Tracker.sorted
    if params[:source_tracker_id].blank? || params[:source_tracker_id] == 'any'
      @source_tracker = nil
    else
      @source_tracker = Tracker.find_by_id(params[:source_tracker_id].to_i)
    end
    if params[:source_role_id].blank? || params[:source_role_id] == 'any'
      @source_role = nil
    else
      @source_role = Role.find_by_id(params[:source_role_id].to_i)
    end
    @target_trackers =
      if params[:target_tracker_ids].blank?
        nil
      else
        Tracker.where(:id => params[:target_tracker_ids]).to_a
      end
    @target_roles =
      if params[:target_role_ids].blank?
        nil
      else
        Role.where(:id => params[:target_role_ids]).to_a
      end
  end

  def find_trackers_roles_and_statuses_for_edit
    find_roles
    find_trackers
    find_statuses
  end

  def find_roles
    ids = Array.wrap(params[:role_id])
    if ids == ['all']
      @roles = Role.sorted.select(&:consider_workflow?)
    elsif ids.present?
      @roles = Role.where(:id => ids).to_a
    end
    @roles = nil if @roles.blank?
  end

  def find_trackers
    ids = Array.wrap(params[:tracker_id])
    if ids == ['all']
      @trackers = Tracker.sorted.to_a
    elsif ids.present?
      @trackers = Tracker.where(:id => ids).to_a
    end
    @trackers = nil if @trackers.blank?
  end

  def find_statuses
    @used_statuses_only = (params[:used_statuses_only] == '0' ? false : true)
    if @trackers && @used_statuses_only
      role_ids = Role.all.select(&:consider_workflow?).map(&:id)
      status_ids = WorkflowTransition.where(
        :tracker_id => @trackers.map(&:id), :role_id => role_ids
      ).where(
        'old_status_id <> new_status_id'
      ).distinct.pluck(:old_status_id, :new_status_id).flatten.uniq
      @statuses = IssueStatus.where(:id => status_ids).sorted.to_a.presence
    end
    @statuses ||= IssueStatus.sorted.to_a
  end
end
