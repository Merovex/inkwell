# An Installment now shelves a book inside any ordered container — a Series or
# a Collection — so its container side is a plain Record reference rather than a
# series-specific column. The join was already Record-to-Record; only the name
# was series-specific.
class GeneralizeInstallmentContainer < ActiveRecord::Migration[8.2]
  def change
    rename_column :installments, :series_record_id, :container_record_id
    rename_index :installments,
      "index_installments_on_series_record_id_and_book_record_id",
      "index_installments_on_container_record_id_and_book_record_id"
    rename_index :installments,
      "index_installments_on_series_record_id_and_position",
      "index_installments_on_container_record_id_and_position"
  end
end
