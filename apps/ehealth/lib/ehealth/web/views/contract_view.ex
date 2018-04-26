defmodule EHealth.Web.ContractView do
  @moduledoc false

  use EHealth.Web, :view

  def render("show.json", %{contract: contract}) do
    # add next fields
    # contractor_legal_entity _id >> PRM.legal_entities
    # contractor_owner _id >> PRM.employee
    # nhs_legal_entity _id >> PRM.legal_entities
    # contractor_employee_divisions >> IL.contract_request.contractor_employee_divisions
    # nhs_contract_price >> IL.contract_request.nhs_contract_price

    Map.take(contract, ~w(
      id
      start_date
      end_date
      status
      contractor_legal_entity_id
      contractor_owner_id
      contractor_base
      contractor_payment_details
      contractor_rmsp_amount
      external_contractor_flag
      external_contractors
      nhs_legal_entity_id
      nhs_signer_id
      nhs_payment_method
      nhs_signer_base
      nhs_payment_details
      issue_city
      price
      contract_number
      is_suspended
      contract_request_id
    ))
  end
end
