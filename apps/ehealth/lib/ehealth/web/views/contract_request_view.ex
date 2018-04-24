defmodule EHealth.Web.ContractRequestView do
  @moduledoc false

  use EHealth.Web, :view

  def render("show.json", %{contract_request: contract_request}) do
    Map.take(contract_request, ~w(
      id
      contractor_legal_entity_id
      contractor_owner_id
      contractor_base
      contractor_payment_details
      contractor_rmsp_amount
      external_contractor_flag
      external_contractors
      contractor_employee_divisions
      nhs_legal_entity_id
      nhs_signer_base
      nhs_contract_price
      nhs_payment_method
      start_date
      end_date
      id_form
      issue_city
      status
      contract_number
      inserted_at
      inserted_by
      updated_at
      updated_by
    )a)
  end
end
