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

class JournalsController < ApplicationController
  before_action :find_journal, :only => [:show, :edit, :update, :diff]
  before_action :find_issue, :only => [:new, :index, :create]
  before_action :find_optional_project, :only => [:atom_index]
  before_action :require_login, :only => [:index, :show, :create]
  before_action :authorize, :only => [:new, :edit, :update, :diff]
  before_action :authorize_create, :only => [:create]
  before_action :authorize_view, :only => [:index, :show]
  accept_atom_auth :atom_index
  accept_api_auth :index, :show, :create, :update
  menu_item :issues

  helper :issues
  helper :custom_fields
  helper :queries
  helper :attachments
  include QueriesHelper

  # Atom feed for issue changes (existing functionality)
  def atom_index
    retrieve_query
    if @query.valid?
      @journals = @query.journals(:order => "#{Journal.table_name}.created_on DESC",
                                  :limit => 25)
    end
    @title = (@project ? @project.name : Setting.app_title) + ": " + (@query.new_record? ? l(:label_changes_details) : @query.name)
    render :layout => false, :content_type => 'application/atom+xml'
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # GET /issues/:issue_id/journals
  def index
    @journal_count = visible_journals.count
    @offset, @limit = api_offset_and_limit
    @journals = visible_journals.
      preload(:details).
      preload(:user => :email_address).
      preload(:updated_by).
      reorder(:id => :asc).
      limit(@limit).
      offset(@offset)

    respond_to do |format|
      format.api
    end
  end

  # GET /journals/:id
  def show
    respond_to do |format|
      format.api
    end
  end

  # POST /issues/:issue_id/journals
  def create
    @journal = @issue.init_journal(User.current)
    @journal.notify = params[:journal][:notify] != 'false' if params[:journal]&.key?(:notify)
    @journal.safe_attributes = params[:journal]

    if @journal.notes.blank?
      respond_to do |format|
        format.api { render_api_errors(l(:error_empty_journal_notes)) }
      end
      return
    end

    if @journal.save
      respond_to do |format|
        format.api { render :action => 'show', :status => :created, :location => journal_url(@journal) }
      end
    else
      respond_to do |format|
        format.api { render_validation_errors(@journal) }
      end
    end
  end

  def diff
    @issue = @journal.issue
    if params[:detail_id].present?
      @detail = @journal.details.find_by_id(params[:detail_id])
    else
      @detail = @journal.details.detect {|d| d.property == 'attr' && d.prop_key == 'description'}
    end
    unless @issue && @detail
      render_404
      return false
    end
    if @detail.property == 'cf'
      unless @detail.custom_field && @detail.custom_field.visible_by?(@issue.project, User.current)
        raise ::Unauthorized
      end
    end
    @diff = Redmine::Helpers::Diff.new(@detail.value, @detail.old_value)
  end

  def new
    @journal = Journal.visible.find(params[:journal_id]) if params[:journal_id]
    @content = if @journal
                 quote_issue_journal(@journal, indice: params[:journal_indice], partial_quote: params[:quote])
               else
                 quote_issue(@issue, partial_quote: params[:quote])
               end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def edit
    (render_403; return false) unless @journal.editable_by?(User.current)
    respond_to do |format|
      # TODO: implement non-JS journal update
      format.js
    end
  end

  def update
    (render_403; return false) unless @journal.editable_by?(User.current)
    journal_attributes = params[:journal]
    journal_attributes[:updated_by] = User.current
    @journal.safe_attributes = journal_attributes
    @journal.save
    @journal.destroy if @journal.details.empty? && @journal.notes.blank?
    call_hook(:controller_journals_edit_post, {:journal => @journal, :params => params})
    respond_to do |format|
      format.html {redirect_to issue_path(@journal.journalized)}
      format.js
      format.api { render :action => 'show' }
    end
  end

  private

  include Redmine::QuoteReply::Builder

  def find_journal
    @journal = Journal.visible.find(params[:id])
    @project = @journal.journalized.project
    @issue = @journal.issue
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def visible_journals
    @issue.journals.visible.
      where(Journal.visible_notes_condition(User.current, :project => @project))
  end

  def authorize_view
    unless @issue.nil? || User.current.allowed_to?(:view_issues, @project)
      deny_access
      return false
    end
    true
  end

  def authorize_create
    unless User.current.allowed_to?(:add_issue_notes, @project)
      deny_access
      return false
    end
    true
  end
end
