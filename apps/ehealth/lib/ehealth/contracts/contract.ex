defmodule EHealth.Contracts.Contract do
  @moduledoc false

  use Ecto.Schema
  alias Ecto.UUID

  @status_pending "PENDING_VERIFICATION"
  @status_verified "VERIFIED"

  def status(:pending), do: @status_pending
  def status(:verified), do: @status_verified

  schema "contracts" do
    field(:start_date, :naive_datetime)
    field(:end_date, :naive_datetime)
    field(:status, :string)
    field(:legal_entity_id, UUID)
    field(:contractor_id, UUID)
    field(:contractor_base, :string)
    field(:contractor_payment_details, :map)
    field(:rmsp_amount, :integer)
    field(:external_contractor_flag, :boolean)
    field(:external_contractors, {:array, :map})
    field(:nhs_signer_id, UUID)
    field(:nhs_signer_base, :string)
    field(:issue_city, :string)
    field(:price, :float)
    field(:contract_number, :string)
    field(:contract_request_id, UUID)
    field(:inserted_by, UUID)
    field(:updated_by, UUID)

    timestamps()
  end
end
