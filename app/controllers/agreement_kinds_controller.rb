class AgreementKindsController < ApplicationController
  include DefaultActions

  private
  def get_model
    AgreementKind
  end
end
