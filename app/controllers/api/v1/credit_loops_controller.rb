class Api::V1::CreditLoopsController < Api::V1::ApiController
  # Superuser-only forensic view of credit-loop cancellations. Proxies the
  # FOAF /credloops endpoints and resolves hop/path addresses to user names.

  before_action :require_superuser!

  # GET /v1/admin/credit_loops
  def index
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
    end

    client = Foaf::Client.new
    networks = client.networks
    return render json: { credloops: [] } unless networks&.any?
    network_address = networks.first["address"]

    limit = [params.fetch(:limit, 20).to_i, 1].max
    offset = [params.fetch(:offset, 0).to_i, 0].max

    result = client.credloops(network_address: network_address, limit: limit, offset: offset)
    return render json: { error: "Failed to fetch credit loops" }, status: 502 unless result

    loops = (result["credloops"] || []).map { |row| decorate_summary(row) }
    render json: { credloops: loops }
  end

  # GET /v1/admin/credit_loops/:id
  def show
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
    end

    result = Foaf::Client.new.credloop(operation_id: params[:id])
    return render json: { error: "Credit loop not found" }, status: 404 unless result

    render json: decorate_detail(result)
  end

  private

  def require_superuser!
    return if current_user&.is_superuser?
    render json: { error: "Superuser access required" }, status: 403
  end

  # --- Address → user name resolution ---

  def resolve_names(addresses)
    addrs = addresses.compact.uniq
    return {} if addrs.empty?
    User.where(foaf_address: addrs).pluck(:foaf_address, :user_name).to_h
  end

  def decorate_summary(row)
    path = row["path"] || []
    names = resolve_names(path)
    {
      operation_id: row["operation_id"],
      detected_at: row["detected_at"],
      cancellable_amount: row["cancellable_amount"],
      hop_count: row["hop_count"],
      path: path.map { |addr| { address: addr, name: names[addr] } },
    }
  end

  def decorate_detail(row)
    path = row["path"] || []
    hops = row["hops"] || []
    trigger = row["triggered_by"]
    addrs = path + hops.flat_map { |h| [h["debtor"], h["creditor"]] } + [trigger&.dig("from"), trigger&.dig("to")].compact
    names = resolve_names(addrs)

    {
      operation_id: row["operation_id"],
      detected_at: row["detected_at"],
      cancellable_amount: row["cancellable_amount"],
      hop_count: row["hop_count"],
      path: path.map { |addr| { address: addr, name: names[addr] } },
      hops: hops.map do |h|
        {
          debtor: { address: h["debtor"], name: names[h["debtor"]] },
          creditor: { address: h["creditor"], name: names[h["creditor"]] },
          trustline_id: h["trustline_id"],
          pre_debt: h["pre_debt"],
          post_debt: h["post_debt"],
        }
      end,
      triggered_by: trigger && {
        operation_id: trigger["operation_id"],
        created_at: trigger["created_at"],
        operation_type: trigger["operation_type"],
        from: { address: trigger["from"], name: names[trigger["from"]] },
        to: { address: trigger["to"], name: names[trigger["to"]] },
        value: trigger["value"],
      },
    }
  end
end
