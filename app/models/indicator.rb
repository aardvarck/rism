class Indicator < ApplicationRecord
  require 'resolv'

  include OrganizationAssociated
  include Linkable
  include Tagable
  include Attachable
  include Indicator::Ransackers

  INDICATOR_KINDS = [
    {kind: :other, pattern: /^\s*other:\s*(.{1,500})$/, check_prefix: true},
    {kind: :network, pattern: /^\s*(#{Resolv::IPv4::Regex})\s*$/},
    {kind: :email_adress, pattern: /^\s*([\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+)\s*$/i, check_prefix: true},
    {kind: :email_theme, pattern: /^\s*email_theme:\s*(.{1,500})$/, check_prefix: true},
    {kind: :email_content, pattern: /^\s*email_content:\s*(.{1,500})$/, check_prefix: true},
    {kind: :url, pattern: /\s*url:\s*(#{URI.regexp})/, check_prefix: true},
    {kind: :domain, pattern: /^\s*domain:\s*((((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)*(xn--)?([a-z0-9\-]{1,61}|[a-z0-9-]{1,30}\.[a-z]{2,}))$/, check_prefix: true},
    {kind: :md5, pattern: /^\s*([a-f0-9]{32})\s*$/},
    {kind: :sha256, pattern: /^\s*([a-f0-9]{64})\s*$/},
    {kind: :sha512, pattern: /^\s*([a-f0-9]{128})\s*$/},
    {kind: :filename, pattern: /^\s*filename:\s*(.{1,500})$/, check_prefix: true},
    {kind: :filesize, pattern: /^\s*filesize:\s*(.{1,500})$/, check_prefix: true},
    {kind: :process, pattern: /^\s*process:\s*(.{1,500})$/, check_prefix: true},
    {kind: :account, pattern: /^\s*account:\s*(.{1,500})$/, check_prefix: true},
  ]

  attr_accessor :indicators_list

  enum trust_level: %i[
                       unknown
                       low
                       high
                      ]

  enum ioc_kind: INDICATOR_KINDS.map { |i| i[:kind] }

  validate :check_content_format

  validates :investigation_id, numericality: { only_integer: true }
  validates :user_id, numericality: { only_integer: true }
  validates :ioc_kind, inclusion: { in: Indicator.ioc_kinds.keys}
  validates :content, presence: true
  validates :trust_level, inclusion: { in: Indicator.trust_levels.keys}
  validates :content, uniqueness: { scope: :investigation_id }

  #serialize :enrichment, Hash

  belongs_to :investigation
  belongs_to :user
  has_one :organization, through: :investigation

  def self.human_attribute_ioc_kinds
    Hash[Indicator.ioc_kinds.map { |k,v| [v, Indicator.human_enum_name(:ioc_kind, k)] }]
  end

  def self.human_attribute_trust_levels
    Hash[Indicator.trust_levels.map { |k,v| [v, Indicator.human_enum_name(:trust_level, k)] }]
  end

  def self.cast_indicator(string)
    result = INDICATOR_KINDS.each do |i|
      break {content: $1, ioc_kind: i[:kind]} if i[:pattern] =~ string
    end
    if result.is_a? Hash
      return result
    else
      return {}
    end
  end

  # TODO: translate error message
  def check_content_format
    ioc_kind_description = INDICATOR_KINDS.find { |i| i[:kind] == ioc_kind.to_sym }
    content_with_prefix= if ioc_kind_description.fetch(:check_prefix, false)
      "#{ioc_kind}:#{content}"
    else
      content
    end
    casted_indicator = Indicator.cast_indicator(content_with_prefix)
    return if casted_indicator[:ioc_kind] == ioc_kind.to_sym
    errors.add(:content, 'wrong format')
  end
end
