# frozen_string_literal: true

class Host < ApplicationRecord
  include OrganizationMember
  include Linkable
  include Tagable
  include Attachable
  include Host::Ransackers

  has_paper_trail

  validates :name, length: { in: 3..200, allow_blank: true }
  validates :name, uniqueness: { scope: :organization_id }
  validates :ip, uniqueness: true
  validates :organization_id, numericality: { only_integer: true }

  belongs_to :organization
  has_many :host_services, dependent: :destroy
  #
  # for use with RecordTemplate, Link and etc
  def show_full_name
    result = [ip]
    result << name if name.present?
    result.join(' ')
  end
end
