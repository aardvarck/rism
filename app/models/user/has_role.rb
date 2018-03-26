# frozen_string_literal: true

module User::HasRole
  extend ActiveSupport::Concern

  included do
    before_destroy :protect_admin

    has_many :role_members, dependent: :destroy
    has_many :roles, through: :role_members
    has_many :rights, as: :subject, dependent: :destroy
  end

  def protect_admin
    return unless id == 1
    errors.add(:base, :user_is_built_in)
    throw :abort
  end

  def admin?
    roles.any? { |role| role.id == 1 }
  end

  def admin_editor?
    roles.any? { |role| (1..2).cover? role.id }
  end

  def admin_editor_reader?
    roles.any? { |role| (1..3).cover? role.id }
  end

  # Return ids of organizations taht are allowed allowed to
  # read by user
  # (includes implicitly assigned rights for children
  # organizations)
   def allowed_organizations_ids
     roles_ids = roles.pluck(:id)
     expl_orgs_ids = Right.where(role_id: roles_ids)
                          .pluck(:organization_id)
                          .uniq
     expl_orgs_ids.each_with_object(expl_orgs_ids.dup) do |id, result|
       result.concat Organization.down_level_organizations(id)
     end.uniq
   end

  # Return ids of organizations taht are allowed allowed to
  # read by user
  # (includes implicitly assigned rights for children
  # organizations)
  # This method variant is implemented by pure SQL
  # def allowed_organizations_ids
  #   query =<<~SQL
  #     WITH RECURSIVE allowed_organizations(id) AS
  #       (
  #         SELECT organizations.id FROM organizations
  #         JOIN rights ON organizations.id = rights.organization_id
  #         WHERE rights.id IN
  #         (
  #           SELECT rights.id FROM rights
  #           WHERE rights.role_id IN
  #           (
  #             SELECT role_members.role_id FROM role_members
  #             WHERE
  #             role_members.user_id = ?
  #           )
  #         )
  #         UNION
  #         SELECT organizations.id FROM organizations
  #         JOIN allowed_organizations
  #         ON allowed_organizations.id = organizations.parent_id
  #       )
  #     SELECT allowed_organizations.id FROM allowed_organizations
  #   SQL
  #   Organization.find_by_sql([query, id]).pluck(:id)
  # end

  def can?(action, record_or_model)
    level = Right.action_to_level(action)
    case record_or_model
    when ActiveRecord::Base
      return can_access_record?(level,
                                record_or_model.class.model_name.to_s,
                                record_or_model)
    when Class
      return can_access_model?(level, record_or_model)
    when String
      return can_access_model?(level, record_or_model)
    end
  end

  private

  def can_access_model?(level, model)
    Right.where(role_id: roles)
         .where(subject_type: subject_type(model))
         .where('subject_id IS NULL')
         .where('rights.level <= ?', level)
         .present?
  end

  def can_access_record?(level, model, record)
    Right.where(role_id: roles)
         .where(organization_id: record.top_level_organizations)
         .where(subject_type: model)
         .where('subject_id = :record_id OR subject_id IS NULL',
                record_id: record.id)
         .where('rights.level <= ?', level)
         .present?
  end

  def subject_type(record_or_model)
    case record_or_model
    when ActiveRecord::Base
      record_or_model.class.model_name.to_s
    when Class
      record_or_model.to_s
    when String
      record_or_model
    end
  end
end
