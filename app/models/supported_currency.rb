class SupportedCurrency < ApplicationRecord
  # Starter catalog shipped in code. Extra (or overridden) rows live in this
  # table and are added via POST /v1/admin/currencies so a new community
  # currency does not need a deploy.
  BUILTIN = [
    { code: 'AUD', name: 'Australian dollar', locale: 'en-AU' },
    { code: 'BRL', name: 'Brazilian real', locale: 'pt-BR' },
    { code: 'CAD', name: 'Canadian dollar', locale: 'en-CA' },
    { code: 'CHF', name: 'Swiss franc', locale: 'de-CH' },
    { code: 'CRC', name: 'Costa Rican colon', locale: 'es-CR' },
    { code: 'CZK', name: 'Czech koruna', locale: 'cs-CZ' },
    { code: 'DKK', name: 'Danish krone', locale: 'da-DK' },
    { code: 'EUR', name: 'Euro', locale: 'de-DE' },
    { code: 'GBP', name: 'British pound', locale: 'en-GB' },
    { code: 'HUF', name: 'Hungarian forint', locale: 'hu-HU' },
    { code: 'IDR', name: 'Indonesian rupiah', locale: 'id-ID' },
    { code: 'INR', name: 'Indian rupee', locale: 'en-IN' },
    { code: 'JPY', name: 'Japanese yen', locale: 'ja-JP' },
    { code: 'KRW', name: 'South Korean won', locale: 'ko-KR' },
    { code: 'MXN', name: 'Mexican peso', locale: 'es-MX' },
    { code: 'NOK', name: 'Norwegian krone', locale: 'nb-NO' },
    { code: 'NZD', name: 'New Zealand dollar', locale: 'en-NZ' },
    { code: 'PLN', name: 'Polish zloty', locale: 'pl-PL' },
    { code: 'SEK', name: 'Swedish krona', locale: 'sv-SE' },
    { code: 'THB', name: 'Thai baht', locale: 'th-TH' },
    { code: 'USD', name: 'US dollar', locale: 'en-US' },
    { code: 'VND', name: 'Vietnamese dong', locale: 'vi-VN' },
    { code: 'ZAR', name: 'South African rand', locale: 'en-ZA' }
  ].freeze

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :code, format: { with: /\A[A-Z]{3}\z/, message: 'must be a 3-letter ISO 4217 code' }
  validates :name, presence: true
  validates :locale, presence: true

  before_validation :normalize_fields

  def self.registry
    merged = BUILTIN.each_with_object({}) do |row, acc|
      acc[row[:code]] = row.merge(active: true)
    end
    find_each do |row|
      merged[row.code] = {
        code: row.code,
        name: row.name,
        locale: row.locale,
        active: row.active
      }
    end
    merged.values.sort_by { |row| row[:code] }
  end

  def self.catalog
    registry.select { |row| row[:active] }
  end

  def self.codes
    catalog.map { |row| row[:code] }
  end

  def self.payloads
    catalog.map { |row| public_payload(row) }
  end

  def self.public_payload(row)
    {
      code: row[:code],
      name: row[:name],
      locale: row[:locale]
    }
  end

  def self.admin_payload(row)
    public_payload(row).merge(active: row[:active])
  end

  def self.registered?(code)
    normalized = code.to_s.strip.upcase
    registry.any? { |row| row[:code] == normalized }
  end

  private

  def normalize_fields
    self.code = code.to_s.strip.upcase
    self.locale = locale.to_s.strip.presence || 'en'
    self.name = name.to_s.strip
    self.name = code if name.blank?
  end
end
