# Enriched profiles (Plan 30). Two of these MIRROR the shared identity that
# lives in auth.foaf.io, so GrowOperative-owned surfaces (contact_list,
# discovery nearby, own-profile serializers) can serve them without a
# per-request round-trip to auth; the third is app-owned.
#
#   about       — mirror of the identity's short bio (canonical in auth).
#   area_label  — mirror of the identity's self-set place label (canonical in
#                 auth). NOT geolocation — never touches the discovery grid.
#   offering    — app-owned "what I grow/sell" blurb, GrowOperative-only (not
#                 portable to other FOAF apps). Length-capped at the model.
#
# Additive + nullable. utf8mb4, so unicode/emoji in about/offering are safe.
class AddProfileFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :about, :text
    add_column :users, :area_label, :string
    add_column :users, :offering, :text
  end
end
