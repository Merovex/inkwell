# Defuses spreadsheet formula injection in CSV exports. Excel, Numbers, and
# Sheets execute a cell that starts with = + - or @ (or a tab/CR that hides
# one), and our CSVs carry text strangers typed — an email's local part, a
# signup source. A leading apostrophe makes the cell literal text. Strings
# only: numbers and dates pass through untouched.
module SpreadsheetSafe
  TRIGGER = /\A[=+\-@\t\r]/

  def self.cell(value)
    value.is_a?(String) && value.match?(TRIGGER) ? "'#{value}" : value
  end

  def self.row(values) = values.map { |value| cell(value) }
end
