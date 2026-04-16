namespace :foaf do
  desc "Check FOAF protocol status and connectivity"
  task status: :environment do
    unless Foaf::Config.shadow_mode?
      puts "FOAF shadow mode is OFF"
      exit
    end

    client = Foaf::Client.new
    version = begin
      uri = URI("#{Foaf::Config.api_url}/api/v1/version")
      Net::HTTP.get(uri)
    rescue => e
      nil
    end

    puts "Shadow mode:  ON"
    puts "FOAF URL:     #{Foaf::Config.api_url}"
    puts "Reachable:    #{version.present? ? 'YES' : 'NO'}"
    puts "Version:      #{version || 'N/A'}"
    puts "Users linked: #{User.where.not(foaf_address: nil).count}/#{User.count}"
  end

  desc "Compare all trustline state between app and FOAF protocol"
  task reconcile: :environment do
    unless Foaf::Config.shadow_mode?
      puts "FOAF shadow mode is OFF"
      exit
    end

    client = Foaf::Client.new
    networks = client.networks
    unless networks&.any?
      puts "No FOAF network found"
      exit
    end
    network_address = networks.first["address"]

    matches = 0
    discrepancies = 0
    missing = 0

    Trustline.where(is_active: true).each do |tl|
      user_a = User.find(tl.user_a_id)
      user_b = User.find(tl.user_b_id)
      label = "#{user_a.user_name} <-> #{user_b.user_name}"

      unless user_a.foaf_address.present?
        puts "  SKIP  #{label} — no FOAF address for #{user_a.user_name}"
        missing += 1
        next
      end

      foaf_trustlines = client.user_trustlines(
        network_address: network_address,
        user_address: user_a.foaf_address
      )

      unless foaf_trustlines
        puts "  ERR   #{label} — FOAF API call failed"
        missing += 1
        next
      end

      foaf_tl = foaf_trustlines.find { |ft| ft["counterParty"] == user_b.foaf_address }

      unless foaf_tl
        puts "  MISS  #{label} — not found in FOAF"
        missing += 1
        next
      end

      # Map FOAF back to app semantics
      foaf_a_to_b = foaf_tl["received"]
      foaf_b_to_a = foaf_tl["given"]
      foaf_balance = -foaf_tl["balance"]

      diffs = []
      diffs << "limit_a_to_b: app=#{tl.credit_limit_a_to_b.to_f} foaf=#{foaf_a_to_b}" if tl.credit_limit_a_to_b.to_f != foaf_a_to_b
      diffs << "limit_b_to_a: app=#{tl.credit_limit_b_to_a.to_f} foaf=#{foaf_b_to_a}" if tl.credit_limit_b_to_a.to_f != foaf_b_to_a
      diffs << "balance: app=#{tl.current_balance.to_f} foaf=#{foaf_balance}" if tl.current_balance.to_f != foaf_balance

      if diffs.empty?
        puts "  OK    #{label}"
        matches += 1
      else
        puts "  DIFF  #{label}"
        diffs.each { |d| puts "        #{d}" }
        discrepancies += 1
      end
    end

    puts "\n--- Summary ---"
    puts "Matches:       #{matches}"
    puts "Discrepancies: #{discrepancies}"
    puts "Missing/Skip:  #{missing}"
  end
end
