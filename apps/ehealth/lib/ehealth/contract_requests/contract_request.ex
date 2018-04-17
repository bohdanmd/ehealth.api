defmodule EHealth.Contracts.ContractRequest do
  @moduledoc false

  use Ecto.Schema
  alias Ecto.UUID

  @status_new "NEW"
  @status_declined "DECLINED"
  @status_approved "APPROVED"
  @status_signed "SIGNED"

  def status(:new), do: @status_new
  def status(:declined), do: @status_declined
  def status(:approved), do: @status_approved
  def status(:signed), do: @status_signed

  schema "contract_requests" do
    field(:legal_entity_id, UUID)
    field(:contractor_id, UUID)
    field(:contractor_base, :string)
    field(:contractor_payment_details, :map)
    field(:rmsp_amount, :integer)
    field(:external_contractor_flag, :boolean)
    field(:external_contractors, {:array, :map})
    field(:employee_divisions, {:array, :map})
    field(:start_date, :naive_datetime)
    field(:end_date, :naive_datetime)
    field(:nhs_signer_id, UUID)
    field(:nhs_signer_base, :string)
    field(:issue_city, :string)
    field(:status, :string)
    field(:status_reason, :string)
    field(:price, :float)
    field(:contract_number, :string)
    field(:contract_id, UUID)
    field(:printout_content, :string)
    field(:id_form, :string)
    field(:inserted_by, UUID)
    field(:updated_by, UUID)

    timestamps()
  end
end
