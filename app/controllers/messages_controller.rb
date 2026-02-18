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

class MessagesController < ApplicationController
  menu_item :boards
  default_search_scope :messages
  before_action :find_board, :only => [:index, :new, :create, :preview]
  before_action :find_attachments, :only => [:preview]
  before_action :find_message, :except => [:index, :new, :create, :preview]
  before_action :authorize, :except => [:preview, :edit, :destroy]
  accept_api_auth :index, :show, :create, :update, :destroy, :reply

  helper :boards
  helper :watchers
  helper :attachments
  include AttachmentsHelper
  include Redmine::QuoteReply::Builder

  REPLIES_PER_PAGE = 25 unless const_defined?(:REPLIES_PER_PAGE)

  # List topics in a board
  def index
    @offset, @limit = api_offset_and_limit
    @topic_count = @board.topics.count
    @topics = @board.topics.
      reorder(:sticky => :desc, :id => :desc).
      includes(:author, :last_reply => :author).
      limit(@limit).
      offset(@offset).
      to_a
  end

  # Show a topic and its replies
  def show
    respond_to do |format|
      format.html do
        page = params[:page]
        # Find the page of the requested reply
        if params[:r] && page.nil?
          offset = @topic.children.where("#{Message.table_name}.id < ?", params[:r].to_i).count
          page = 1 + offset / REPLIES_PER_PAGE
        end

        @reply_count = @topic.children.count
        @reply_pages = Paginator.new @reply_count, REPLIES_PER_PAGE, page
        @replies =  @topic.children.
          includes(:author, :attachments, {:board => :project}).
          reorder("#{Message.table_name}.created_on ASC, #{Message.table_name}.id ASC").
          limit(@reply_pages.per_page).
          offset(@reply_pages.offset).
          to_a

        Message.preload_reaction_details(@replies)

        @reply = Message.new(:subject => "RE: #{@message.subject}")
        render :action => "show", :layout => false if request.xhr?
      end
      format.api
    end
  end

  # Create a new topic
  def new
    @message = Message.new
    @message.author = User.current
    @message.board = @board
    @message.safe_attributes = params[:message]
    if request.post?
      @message.save_attachments(params[:attachments])
      if @message.save
        call_hook(:controller_messages_new_after_save, {:params => params, :message => @message})
        render_attachment_warning_if_needed(@message)
        flash[:notice] = l(:notice_successful_create)
        redirect_to board_message_path(@board, @message)
      end
    end
  end

  # Create a new topic via API
  def create
    @message = Message.new
    @message.author = User.current
    @message.board = @board
    @message.safe_attributes = params[:message]
    @message.save_attachments(params[:attachments] || (params[:message] && params[:message][:uploads]))
    if @message.save
      call_hook(:controller_messages_new_after_save, {:params => params, :message => @message})
      respond_to do |format|
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.api { render_validation_errors(@message) }
      end
    end
  end

  # Reply to a topic
  def reply
    @reply = Message.new
    @reply.author = User.current
    @reply.board = @board
    @reply.safe_attributes = params[:reply] || params[:message]
    @reply.save_attachments(params[:attachments] || (params[:message] && params[:message][:uploads]))
    @topic.children << @reply
    if @reply.new_record?
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_to board_message_path(@board, @topic, :r => @reply)
        end
        format.api { render_validation_errors(@reply) }
      end
    else
      call_hook(:controller_messages_reply_after_save, {:params => params, :message => @reply})
      respond_to do |format|
        format.html do
          render_attachment_warning_if_needed(@reply)
          flash[:notice] = l(:notice_successful_update)
          redirect_to board_message_path(@board, @topic, :r => @reply)
        end
        format.api { render_api_ok }
      end
    end
  end

  # Edit a message
  def edit
    (render_403; return false) unless @message.editable_by?(User.current)
    @message.safe_attributes = params[:message]
    if request.post?
      @message.save_attachments(params[:attachments])
      if @message.save
        render_attachment_warning_if_needed(@message)
        flash[:notice] = l(:notice_successful_update)
        @message.reload
        redirect_to board_message_path(@message.board, @message.root, :r => (@message.parent_id && @message.id))
      end
    end
  end

  # Update a message via API
  def update
    (render_403; return false) unless @message.editable_by?(User.current)
    @message.safe_attributes = params[:message]
    @message.save_attachments(params[:attachments] || (params[:message] && params[:message][:uploads]))
    if @message.save
      respond_to do |format|
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.api { render_validation_errors(@message) }
      end
    end
  end

  # Delete a message
  def destroy
    (render_403; return false) unless @message.destroyable_by?(User.current)
    r = @message.to_param
    @message.destroy
    respond_to do |format|
      format.html do
        flash[:notice] = l(:notice_successful_delete)
        if @message.parent
          redirect_to board_message_path(@board, @message.parent, :r => r)
        else
          redirect_to project_board_path(@project, @board)
        end
      end
      format.api { render_api_ok }
    end
  end

  def quote
    @subject = @message.subject
    @subject = "RE: #{@subject}" unless @subject.starts_with?('RE:')

    @content = if @message.root == @message
                 quote_root_message(@message, partial_quote: params[:quote])
               else
                 quote_message(@message, partial_quote: params[:quote])
               end

    respond_to do |format|
      format.html { render_404 }
      format.js
    end
  end

  def preview
    message = @board.messages.find_by_id(params[:id])
    @text = params[:text] || nil
    @previewed = message
    render :partial => 'common/preview'
  end

  private

  def find_message
    if params[:board_id]
      return unless find_board

      @message = @board.messages.includes(:parent).find(params[:id])
    else
      # When accessing messages directly via /messages/:id
      @message = Message.includes(:parent, :board => :project).find(params[:id])
      @board = @message.board
      @project = @board.project
    end
    @topic = @message.root
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_board
    @board = Board.includes(:project).find(params[:board_id])
    @project = @board.project
  rescue ActiveRecord::RecordNotFound
    render_404
    nil
  end
end
