require "csv"

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
end
