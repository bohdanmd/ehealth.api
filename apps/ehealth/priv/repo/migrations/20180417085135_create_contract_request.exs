defmodule EHealth.Repo.Migrations.CreateContractRequest do
  @moduledoc false

  use Ecto.Migration

  def change do
    create table(:contract_requests, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:legal_entity_id, :uuid, null: false)
      add(:contractor_id, :uuid, null: false)
      add(:contractor_base, :string, null: false)
      add(:contractor_payment_details, :map, null: false)
      add(:rmsp_amount, :integer, null: false)
      add(:external_contractor_flag, :boolean)
      add(:external_contractors, {:array, :map})
      add(:employee_divisions, {:array, :map}, null: false)
      add(:start_date, :naive_datetime, null: false)
      add(:end_date, :naive_datetime, null: false)
      add(:nhs_signer_id, :uuid, null: false)
      add(:nhs_signer_base, :string)
      add(:issue_city, :string)
      add(:status, :string, null: false)
      add(:status_reason, :string)
      add(:price, :float)
      add(:contract_number, :string)
      add(:contract_id, :uuid)
      add(:printout_content, :string)
      add(:id_form, :string, null: false)
      add(:inserted_by, :uuid, null: false)
      add(:updated_by, :uuid, null: false)

      timestamps()
    end
  end
end
