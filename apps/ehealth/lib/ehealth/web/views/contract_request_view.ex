defmodule EHealth.Web.ContractRequestView do
  @moduledoc false

  use EHealth.Web, :view

  def render("index.json", %{contract_requests: contract_requests}) do
    render_many(contract_requests, __MODULE__, "list_contract_request.json")
  end

  def render("list_contract_request.json", %{contract_request: contract_request}) do
    Map.take(contract_request, ~w(
      id
      contractor_legal_entity_id
      contractor_owner_id
      contractor_base
      status
      status_reason
      nhs_signer_id
      nhs_legal_entity_id
      nhs_signer_base
      issue_city
      nhs_contract_price
      contract_number
      contract_id
      start_date
      end_date
    )a)
  end

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
