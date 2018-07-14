class Schedule < ApplicationRecord
  include OrganizationAssociated

  validates :job_id, uniqueness: { scope: :job_type }
  validates :job_id, presence: true
  validates :job_type, presence: true

  validate :check_minutes
  validate :check_hours
  validate :check_week_days
  validate :check_months
  validate :check_month_days

  belongs_to :job, polymorphic: true

  has_one :organization, through: :job

  after_save :update_sidekiq_cron_schedule

  #delegate :organization, to: :job

  def organization_id
    job.organization_id
  end

  def show_crontab_line
    return crontab_line if crontab_line.present?
    # TODO: think and if you wants do it with postgres function
    result = []
    %i[minutes hours month_days months week_days].each do |arr|
      result << array_to_crontab_symbol(self.send(arr))
    end
    return nil if result.all? { |value| value == '*' }
    result.join(' ')
  end

  private

  def update_sidekiq_cron_schedule
    cron_job_name = "#{job_type}_#{job_id}"
    # if show_crontab_line = nil (m,h,md,m,wd = * * * * * and crontab_line is empty)
    unless show_crontab_line
      destroy_sidekiq_cron_schedule(cron_job_name)
      return
    end
    Sidekiq::Cron::Job.create(
      name: cron_job_name,
      cron: show_crontab_line,
      class: job.worker,
      queue: job.job_queue('scheduled_scan'),
      args: [job.id, job.job_queue('scheduled_scan')]
    )
  end

  def destroy_sidekiq_cron_schedule(cron_job_name)
    cron_job = Sidekiq::Cron::Job.find(cron_job_name)
    return unless cron_job
    cron_job.destroy
  end

  def array_to_crontab_symbol(arr)
    arr.present? ? arr.sort.join(',') : '*'
  end

  def check_minutes
    return if check_array(minutes, 0..59)
    errors.add(:minutes, :invalid)
  end

  def check_hours
    return if check_array(hours, 0..23)
    errors.add(:hours, :invalid)
  end

  def check_week_days
    return if check_array(week_days, 0..6)
    errors.add(:week_days, :invalid)
  end

  def check_months
    return if check_array(months, 1..12)
    errors.add(:months, :invalid)
  end

  def check_month_days
    return if check_array(month_days, 1..31)
    errors.add(:month_days, :invalid)
  end

  def check_array(array, range)
    array.is_a?(Array) && array.all?{|value| (range).include?(value)}
  end
end
