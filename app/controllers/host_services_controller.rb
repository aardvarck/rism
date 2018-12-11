# frozen_string_literal: true

class HostServicesController < ApplicationController
  include RecordOfOrganization

  def autocomplete_service_name
    authorize model
    scope = if current_user.admin_editor?
              HostService
            elsif current_user.can_read_model_index? Organization
              HostService
            else
              HostService.where(
                organization_id: current_user.allowed_organizations_ids
              )
            end

    term = params[:term]
    records = scope.select(:id, :name, :port, :protocol)
                   .where(
                     'name ILIKE ? OR port::text LIKE ?',
                     "%#{term}%", "#{term}%"
                   )
                   .order(:port)
    result = records.map do |record|
               {
                 id: record.id,
                 port: record.port,
                 protocol: record.port,
                 value: record.show_full_name
               }
             end
    render json: result
  end

  private

  def model
    HostService
  end

  def records(scope)
    scope = scope
      .select('host_services.*')
      .select('scan_results.state')
      .select('scan_results.id AS scan_result_id')
      .joins(join_host)
      .joins(join_scan_result)
    scope = policy_scope(scope)
    @q = scope.ransack(params[:q])
    @q.sorts = default_sort if @q.sorts.empty?
    @q.result
      .includes(records_includes)
      .page(params[:page])
  end

  def join_host
    <<~SQL
      LEFT JOIN hosts
        ON host_services.host_id = hosts.id
    SQL
  end

  def join_scan_result
    <<~SQL
      LEFT JOIN scan_results
      ON scan_results.ip = hosts.ip
      AND scan_results.port = host_services.port
      AND scan_results.protocol = host_services.protocol
      AND scan_results.id IN
      (SELECT
       scan_results.id
       FROM scan_results
        INNER JOIN (
          SELECT
            scan_results.ip,
            MAX(scan_results.job_start)
            AS max_time
          FROM scan_results
          GROUP BY scan_results.ip
        )m
        ON scan_results.ip = m.ip
        AND scan_results.job_start = m.max_time
      )
    SQL
  end

  def default_sort
    'port desc'
  end

  def records_includes
    %i[organization host]
  end

  def preset_record
    return if params.blank?
    if params[:ip].present?
      host = Host.where(ip: params[:ip])&.first
      @record.host_id = host&.id
      @record.organization_id = host&.organization_id
    end
    @record.host_id = params[:host_id] if params[:host_id].present?
    @record.organization_id = params[:organization_id] if params[:organization_id].present?
    @record.port = params[:port_number] if params[:port_number].present?
    @record.protocol = params[:protocol_name] if params[:protocol_name].present?
    @record.vulnerable = params[:vulnerable] if params[:vulnerable].present?
    @record.vuln_description = params[:vuln_description] if params[:vuln_description].present?
    if params[:service].present?
      name = [params[:service]]
      name << @organization.name if @organization.present?
      @record.name = name.join(' ')
    end
  end
end
