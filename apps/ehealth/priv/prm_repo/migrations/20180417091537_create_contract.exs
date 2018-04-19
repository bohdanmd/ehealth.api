defmodule EHealth.PRMRepo.Migrations.CreateContract do
  @moduledoc false

  use Ecto.Migration

  def change do
    create table(:contracts, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:start_date, :naive_datetime, null: false)
      add(:end_date, :naive_datetime, null: false)
      add(:status, :string, null: false)
      add(:contractor_legal_entity_id, :uuid, null: false)
      add(:contractor_id, :uuid, null: false)
      add(:contractor_base, :string, null: false)
      add(:contractor_payment_details, :map, null: false)
      add(:contractor_rmsp_amount, :integer, null: false)
      add(:external_contractor_flag, :boolean)
      add(:external_contractors, {:array, :map})
      add(:nhs_signer_id, :uuid)
      add(:nhs_signer_base, :string, null: false)
      add(:issue_city, :string, null: false)
      add(:price, :float, null: false)
      add(:contract_number, :string, null: false)
      add(:contract_request_id, :uuid, null: false)
      add(:inserted_by, :uuid, null: false)
      add(:updated_by, :uuid, null: false)

      timestamps()
    end
  end
end
