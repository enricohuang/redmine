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

class ReactionsController < ApplicationController
  accept_api_auth :index, :create, :destroy

  before_action :check_enabled
  before_action :set_object
  before_action :authorize_viewable, :only => [:index]
  before_action :require_login_for_reactions, :except => [:index]
  before_action :authorize_reactable, :except => [:index]

  def index
    @reactions = @object.reactions.visible(User.current).preload(:user).order(:id => :desc)
    @reaction_count = @reactions.size

    respond_to do |format|
      format.api
      format.any { head :not_acceptable }
    end
  end

  def create
    @reaction = @object.reactions.find_or_create_by!(user: User.current)
    respond_to do |format|
      format.js
      format.api { render :action => 'show', :status => :created }
    end
  end

  def destroy
    respond_to do |format|
      format.js do
        reaction = @object.reactions.by(User.current).find_by(id: params[:id])
        reaction&.destroy
      end
      format.api do
        reaction = @object.reactions.by(User.current).find_by(id: params[:id])
        if reaction
          reaction.destroy
          render_api_ok
        else
          render_api_errors(['Reaction not found'])
        end
      end
    end
  end

  private

  def check_enabled
    render_403 unless Setting.reactions_enabled?
  end

  def set_object
    object_type = params[:object_type]

    unless Redmine::Reaction::REACTABLE_TYPES.include?(object_type)
      render_api_errors(['Invalid object type']) and return if api_request?
      render_403
      return
    end

    @object = object_type.constantize.find(params[:object_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_reactable
    render_403 unless Redmine::Reaction.editable?(@object, User.current)
  end

  def authorize_viewable
    render_403 unless Redmine::Reaction.visible?(@object, User.current)
  end

  def require_login_for_reactions
    return true if User.current.logged?

    if api_request?
      head :unauthorized
      return false
    end

    require_login
  end
end
