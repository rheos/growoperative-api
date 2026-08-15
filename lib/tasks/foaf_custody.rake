require "csv"
require "json"
require "uri"

namespace :foaf_custody do
  desc "Snapshot the foaf_id -> foaf_address map from railsbackend.users for pre/post migration diff (AC 6)"
  task snapshot: :environment do
    # Portable ActiveRecord + plain Ruby CSV — no adapter-specific SQL, so this
    # runs unchanged on the current MySQL and on the Neon Postgres target.
    rows = User.where.not(foaf_address: nil).pluck(:foaf_id, :foaf_address)

    path = Rails.root.join("tmp", "foaf_address_snapshot_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv")
    CSV.open(path, "w") do |csv|
      csv << %w[foaf_id foaf_address]
      rows.each { |foaf_id, foaf_address| csv << [foaf_id, foaf_address] }
    end

    puts "Snapshot written: #{rows.size} users -> #{path}"
  end

  desc "Idempotently migrate each user's private key to the shared FOAF custodian (FR 9/10/11). " \
       "Env: DRY_RUN, FOAF_AUTH_URL, FOAF_AUTH_SERVICE_TOKEN_GROWOP."
  task migrate_keys: :environment do
    # --- No-logging grep-assert (EC 7 / AC 9) -----------------------------
    # Guard the exact failure mode BEFORE touching any user: a source line that
    # contains BOTH a log verb AND the private-key variable name. Anchored
    # per-line (no /m) so a comment mentioning `priv_key` alone never trips it.
    # The two lines that DEFINE this guard necessarily name both a log verb and
    # the key var, so they carry the `grep-assert-self` sentinel and are skipped;
    # a real leak line elsewhere carries no sentinel and still raises.
    source = File.read(__FILE__)
    lines_with_key_in_log = source.each_line.reject { |line| line.include?("grep-assert-self") }.select do |line| # grep-assert-self
      line.match?(/Rails\.logger|puts|inspect/) && line.match?(/priv_key/) # grep-assert-self
    end
    if lines_with_key_in_log.any?
      raise "SECURITY: key variable in a log call — fix before running: #{lines_with_key_in_log.first}"
    end

    dry_run   = ENV["DRY_RUN"] == "true"
    auth_url  = ENV["FOAF_AUTH_URL"].to_s.sub(%r{/\z}, "")
    token     = ENV["FOAF_AUTH_SERVICE_TOKEN_GROWOP"].to_s

    unless dry_run
      raise "FOAF_AUTH_URL is required" if auth_url.empty?
      raise "FOAF_AUTH_SERVICE_TOKEN_GROWOP is required" if token.empty?
    end

    migrated = 0
    errored  = 0
    would    = 0

    # Include "error" users so a row parked by a transient custodian 5xx, network
    # blip, or probe-sign hiccup self-heals on re-run (Prompt 9 re-run contract).
    # This is safe because the state machine is idempotent and an "error" user
    # still holds its key (the error path never nulls it): retrying re-runs
    # parity -> migrate -> verify -> null cleanly, and if the custodian already
    # adopted the key on a prior partial run the migrate POST returns "noop" and
    # the null still completes. "migrated" users stay EXCLUDED — they're done.
    scope = User.where(custody_state: %w[pending error]).where.not(foaf_private_key: nil)

    scope.find_each do |user|
      # Read the secret into a local var. From here it is passed by reference
      # only — never interpolated into a string, log, or exception.
      priv_key = user.foaf_private_key

      if dry_run
        would += 1
        puts "would migrate foaf_id=#{user.foaf_id} address=#{user.foaf_address}"
        next
      end

      # Step (a) — derive-address parity (EC 3). No re-key: the existing
      # foaf_address stays canonical; we only assert the held key derives it.
      derived = Foaf::LedgerSigner.address(priv_key)
      if derived.nil? || derived.downcase != user.foaf_address.to_s.downcase
        user.update_columns(custody_state: "error")
        errored += 1
        Rails.logger.warn("[foaf_custody] derive-address mismatch foaf_id=#{user.foaf_id} — skipped")
        next
      end

      # Step (b) — hand the key to the custodian (idempotent: adopted|noop).
      adapter = FoafCustodyMigration.custody_http_adapter
      status = FoafCustodyMigration.post_migrate(auth_url, token, user.foaf_id, priv_key, user.foaf_address, http_adapter: adapter)
      unless %w[adopted noop].include?(status)
        user.update_columns(custody_state: "error")
        errored += 1
        Rails.logger.warn("[foaf_custody] migrate rejected foaf_id=#{user.foaf_id} status=#{status} — skipped")
        next
      end

      # Step (c) — probe-sign through the custodian and verify via the real
      # verify_by_address path (personal_recover -> public_key_to_address).
      unless FoafCustodyMigration.custodian_holds_key?(auth_url, token, user.foaf_id, user.foaf_address, http_adapter: adapter)
        user.update_columns(custody_state: "error")
        errored += 1
        Rails.logger.warn("[foaf_custody] probe-sign verify failed foaf_id=#{user.foaf_id} — skipped")
        next
      end

      # Step (d) — null BOTH the key and the seed at source, record state
      # (W2 / AC 7). The seed is destroyed, not moved: it is the re-derivable
      # secret and must not survive the migration.
      user.update_columns(foaf_private_key: nil, foaf_seed_phrase: nil, custody_state: "migrated")
      migrated += 1
      Rails.logger.info("[foaf_custody] migrated foaf_id=#{user.foaf_id}")
    end

    if dry_run
      puts "DRY_RUN complete — would migrate #{would} pending/error user(s). No HTTP calls made."
    else
      puts "migrate_keys complete — migrated=#{migrated} errors=#{errored}"
    end
  end

  desc "Diff current users.foaf_address against the latest snapshot CSV; exit 1 if any address changed (AC 6)"
  task diff_addresses: :environment do
    path = FoafCustodyMigration.latest_snapshot_path
    raise "No snapshot CSV found in tmp/ — run foaf_custody:snapshot first" if path.nil?

    puts "Diffing against snapshot: #{path}"
    changed = []

    CSV.foreach(path, headers: true) do |row|
      foaf_id  = row["foaf_id"]
      snapshot = row["foaf_address"]
      current  = User.where(foaf_id: foaf_id).pick(:foaf_address)
      if current.to_s != snapshot.to_s
        changed << { foaf_id: foaf_id, was: snapshot, now: current }
      end
    end

    if changed.any?
      changed.each do |c|
        puts "CHANGED foaf_id=#{c[:foaf_id]} was=#{c[:was]} now=#{c[:now]}"
      end
      abort "AC 6 FAILED — #{changed.size} address(es) changed since snapshot."
    else
      puts "AC 6 OK — no foaf_address changed since snapshot."
    end
  end

  desc "Verify every migrated user has both foaf_private_key and foaf_seed_phrase nulled; exit 1 otherwise (AC 7)"
  task check_nulled: :environment do
    leaking = User.where(custody_state: "migrated")
                  .where("foaf_private_key IS NOT NULL OR foaf_seed_phrase IS NOT NULL")

    count = leaking.count
    if count.positive?
      leaking.pluck(:foaf_id).each do |foaf_id|
        puts "LEAK foaf_id=#{foaf_id} — migrated but key or seed still present"
      end
      abort "AC 7 FAILED — #{count} migrated user(s) still hold a key or seed."
    else
      migrated_total = User.where(custody_state: "migrated").count
      puts "AC 7 OK — all #{migrated_total} migrated user(s) have key and seed nulled."
    end
  end
end

# --- Helpers -----------------------------------------------------------------
# Namespaced in a module (not top-level defs) so they don't become private
# methods on Object — no global-namespace collision, and specs stub the module
# method directly instead of allow_any_instance_of(Object). Called from the rake
# task bodies as FoafCustodyMigration.<helper>(...). All use Foaf::NetHttpAdapter
# for TLS HTTP; the adapter is injectable so specs can drive the state machine
# without a live custodian; production uses the default gem adapter.
module FoafCustodyMigration
  module_function

  # POST the adopted key to the custodian migrate endpoint. Returns the custodian
  # "status" string ("adopted" | "noop" | other). priv_key is a parameter value
  # only — it is JSON-encoded, never interpolated into a log or exception here.
  def post_migrate(auth_url, service_token, foaf_id, priv_key, expected_address, http_adapter: nil)
    http = http_adapter || Foaf::NetHttpAdapter.new
    uri  = URI.parse("#{auth_url}/v1/internal/custodian/migrate")
    body = JSON.generate(
      foaf_id: foaf_id,
      adopted_private_key: priv_key,
      expected_address: expected_address
    )

    response = http.request(
      method: :post,
      uri: uri,
      headers: custodian_headers(service_token),
      body: body
    )

    return "http_#{response.status}" unless response.status.to_i.between?(200, 299)

    JSON.parse(response.body.to_s).fetch("status", "unknown")
  rescue JSON::ParserError
    "invalid_json"
  rescue StandardError => e
    "unreachable_#{e.class}"
  end

  # Ask the custodian to sign a per-user probe, then verify the signature recovers
  # to the user's foaf_address (the real verify_by_address path). Returns a Hash:
  # { "signature" => ... } on success, or a status string on failure.
  def probe_sign(auth_url, service_token, foaf_id, expected_address, http_adapter: nil)
    http = http_adapter || Foaf::NetHttpAdapter.new
    uri  = URI.parse("#{auth_url}/v1/internal/custodian/sign")
    body = JSON.generate(foaf_id: foaf_id, exact_body: "<probe-#{foaf_id}>")

    response = http.request(
      method: :post,
      uri: uri,
      headers: custodian_headers(service_token),
      body: body
    )

    return "http_#{response.status}" unless response.status.to_i.between?(200, 299)

    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    "invalid_json"
  rescue StandardError => e
    "unreachable_#{e.class}"
  end

  # True when the custodian returns a signature that recovers to expected_address.
  def custodian_holds_key?(auth_url, service_token, foaf_id, expected_address, http_adapter: nil)
    result = probe_sign(auth_url, service_token, foaf_id, expected_address, http_adapter: http_adapter)
    return false unless result.is_a?(Hash)

    signature = result["signature"] || result[:signature]
    return false if signature.to_s.empty?

    exact_body = "<probe-#{foaf_id}>"
    recovered_public_key = Eth::Signature.personal_recover(exact_body, signature)
    recovered_address = Eth::Util.public_key_to_address(
      Eth::Util.hex_to_bin(recovered_public_key)
    ).to_s

    recovered_address.downcase == expected_address.to_s.downcase
  rescue StandardError
    false
  end

  def custodian_headers(service_token)
    {
      "Accept" => "application/json",
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{service_token}"
    }
  end

  # Single HTTP seam for the migrate_keys state machine. Production returns the
  # gem's real TLS adapter; specs stub this one method to inject a fake and drive
  # adopted/noop/reject/verify-fail without a live custodian.
  def custody_http_adapter
    Foaf::NetHttpAdapter.new
  end

  # Latest tmp/foaf_address_snapshot_*.csv by filename (timestamps sort lexically).
  def latest_snapshot_path
    Dir.glob(Rails.root.join("tmp", "foaf_address_snapshot_*.csv")).max
  end
end
