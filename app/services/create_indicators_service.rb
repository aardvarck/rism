class CreateIndicatorsService
  def self.call(*args, &block)
    new(*args, &block).execute
  end

  def initialize(text, investigation_id, current_user, contexts, enrich = false)
    @enrich = enrich
    @text = text
    @investigation_id = investigation_id
    @user_id = current_user
    @contexts = contexts.reject { |i| i.blank? }
  end

  def execute
    @text.split("\n")
         .select do |string|
           next if string.blank?
           string unless create_indicator(string)
          end
  end

  private

  def create_indicator(string)
    string = clean_string(string)
    indicator_params = Indicator.cast_indicator(string)
    return unless indicator_params.fetch(:content_format, false)
    if @contexts.blank?
      indicator_params[:indicator_context_ids] = indicator_context_ids(
        indicator_params[:indicator_context_ids]
      )
    else
      ids = IndicatorContext.pluck(:id)
      contexts = @contexts.map(&:to_i).select { |id| ids.include? id }
      indicator_params[:indicator_context_ids] = contexts
    end
    indicator_params.merge!(
      investigation_id: @investigation_id,
      current_user: @user_id,
      trust_level: :not_set,
      purpose: :for_detect,
      enrichment: {}
    )
    indicator = Indicator.new(indicator_params)
    current_user = User.find(@user_id)
    indicator.current_user = current_user
    indicator.skip_format_validation = true
    indicator.save
    enrich(indicator) if @enrich == '1'
    SetReadableLogService.call(indicator, current_user)
  end

  def enrich(indicator)
    unless Indicator::Enrichments.format_supported?(indicator.content_format, 'virus_total')
      return
    end
    IndicatorEnrichmentJob.perform_later(
      'free_virus_total_search',
      indicator.id,
      'virus_total'
    )
  end

  def indicator_context_ids(codenames)
    return if codenames.blank?
    codenames.split(',').map(&:strip)
                        .each_with_object([]) do |codename, ids|
      indicator_context = IndicatorContext.find_by(codename: codename)
      next if indicator_context.blank?
      ids << IndicatorContext.find_by(codename: codename).id
    end
  end

  def clean_string(string)
    string.strip
      .gsub('[.]', '.')
  end
end
