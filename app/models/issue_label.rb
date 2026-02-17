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

class IssueLabel < ApplicationRecord
  belongs_to :issue
  belongs_to :label

  validates_uniqueness_of :label_id, scope: [:issue_id]
  validate :label_belongs_to_issue_project

  private

  def label_belongs_to_issue_project
    if label && issue && label.project_id != issue.project_id
      errors.add(:label, :invalid)
    end
  end
end
