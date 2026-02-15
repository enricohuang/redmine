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

class WebhooksController < ApplicationController
  self.main_menu = false

  before_action :require_login
  before_action :check_enabled
  before_action :authorize

  before_action :find_webhook, only: [:show, :edit, :update, :destroy]

  accept_api_auth :index, :show, :create, :update, :destroy

  require_sudo_mode :create, :update, :destroy

  def index
    @webhook_count = webhooks.count
    @offset, @limit = api_offset_and_limit
    @webhooks = webhooks.order(:url).limit(@limit).offset(@offset)

    respond_to do |format|
      format.html { @webhooks = webhooks.order(:url) }
      format.api
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to edit_webhook_path(@webhook) }
      format.api
    end
  end

  def new
    @webhook = Webhook.new
  end

  def edit
  end

  def create
    @webhook = webhooks.build
    @webhook.safe_attributes = params[:webhook]
    if @webhook.save
      respond_to do |format|
        format.html { redirect_to webhooks_path }
        format.api { render :action => 'show', :status => :created, :location => webhook_url(@webhook) }
      end
    else
      respond_to do |format|
        format.html { render :new }
        format.api { render_validation_errors(@webhook) }
      end
    end
  end

  def update
    @webhook.safe_attributes = params[:webhook]
    if @webhook.save
      respond_to do |format|
        format.html { redirect_to webhooks_path }
        format.api { render_api_ok }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.api { render_validation_errors(@webhook) }
      end
    end
  end

  def destroy
    @webhook.destroy
    respond_to do |format|
      format.html { redirect_to webhooks_path }
      format.api { render_api_ok }
    end
  end

  private

  def find_webhook
    @webhook = webhooks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def webhooks
    User.current.webhooks
  end

  def authorize
    deny_access unless User.current.allowed_to?(:use_webhooks, nil, global: true)
  end

  def check_enabled
    render_403 unless Webhook.enabled?
  end
end
