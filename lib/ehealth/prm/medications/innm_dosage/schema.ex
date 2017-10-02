defmodule EHealth.PRM.Medications.INNMDosage.Schema do
  @moduledoc false
  use Ecto.Schema
  alias EHealth.PRM.Medications.Medication.Ingredient, as: MedicationIngredient
  alias EHealth.PRM.Medications.INNMDosage.Ingredient, as: INNMDosageIngredient

  @medication_type "INNMDosage"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "medications" do
    field :name, :string
    field :form, :string
    field :type, :string
    field :is_active, :boolean, default: true
    field :inserted_by, Ecto.UUID
    field :updated_by, Ecto.UUID

    has_many :ingredients, INNMDosageIngredient, foreign_key: :parent_id
    has_many :ingredients_medication, MedicationIngredient, foreign_key: :medication_child_id

    timestamps()
  end

  def type, do: @medication_type
end
