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

class Label < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :project
  has_many :issue_labels, dependent: :destroy
  has_many :issues, through: :issue_labels

  validates_presence_of :name, :project
  validates_uniqueness_of :name, scope: [:project_id], case_sensitive: true
  validates_length_of :name, maximum: 64
  validates_format_of :color, with: /\A#[0-9A-Fa-f]{6}\z/

  safe_attributes 'name', 'color'

  # Calculate contrasting text color based on background luminance
  # Returns white for dark backgrounds, black for light backgrounds
  def text_color
    r = color[1..2].to_i(16)
    g = color[3..4].to_i(16)
    b = color[5..6].to_i(16)
    luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    luminance > 0.5 ? '#000000' : '#FFFFFF'
  end

  def to_s
    name
  end
end
