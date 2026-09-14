module Api::V1
  module Admin
    # Superuser registry for display currencies a subnet can pick.
    # Built-in ISO codes ship in SupportedCurrency::BUILTIN; this API
    # adds or overrides rows so a new community currency does not need
    # a code deploy.
    class CurrenciesController < ApiController
      before_action :require_superuser!

      # GET /v1/admin/currencies
      def index
        render json: {
          currencies: SupportedCurrency.registry.map { |row| SupportedCurrency.admin_payload(row) }
        }, status: 200
      end

      # POST /v1/admin/currencies
      # Body: { code: "PHP", name: "Philippine peso", locale: "en-PH" }
      # `name` and `locale` are optional (`name` defaults to the code, locale to "en").
      def create
        code = params[:code].to_s.strip.upcase
        if SupportedCurrency.registered?(code)
          return render json: { message: 'Currency already registered' }, status: 422
        end

        record = SupportedCurrency.new(create_params)
        if record.save
          render json: SupportedCurrency.admin_payload(record_as_row(record)), status: 201
        else
          render json: { errors: record.errors.full_messages }, status: 422
        end
      end

      # PATCH /v1/admin/currencies/:code
      # Body: { name, locale, active } — any subset. Creates a DB override
      # for a builtin code so it can be renamed or deactivated.
      def update
        code = params[:code].to_s.strip.upcase
        unless SupportedCurrency.registered?(code)
          return render json: { message: 'Currency not found' }, status: 404
        end

        if deactivating_default?(code)
          return render json: { message: 'Cannot deactivate the default currency' }, status: 422
        end

        record = SupportedCurrency.find_or_initialize_by(code: code)
        if record.new_record?
          builtin = SupportedCurrency::BUILTIN.find { |row| row[:code] == code } || {}
          record.name = builtin[:name] || code
          record.locale = builtin[:locale] || 'en'
          record.active = true
        end
        record.assign_attributes(update_params)

        if record.save
          render json: SupportedCurrency.admin_payload(record_as_row(record)), status: 200
        else
          render json: { errors: record.errors.full_messages }, status: 422
        end
      end

      private

      def require_superuser!
        return if current_user&.is_superuser?
        render json: { message: 'Superuser access required' }, status: 403
      end

      def create_params
        params.permit(:code, :name, :locale)
      end

      def update_params
        params.permit(:name, :locale, :active)
      end

      def deactivating_default?(code)
        return false unless params.key?(:active)

        active = params[:active]
        turning_off = active == false || %w[false 0 no].include?(active.to_s.downcase)
        turning_off && code == SiteConfig::DEFAULTS[:currency]
      end

      def record_as_row(record)
        {
          code: record.code,
          name: record.name,
          locale: record.locale,
          active: record.active
        }
      end
    end
  end
end
