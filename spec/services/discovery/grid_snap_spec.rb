require 'rails_helper'

# Pure unit spec for the privacy grid. No DB, no FactoryBot — skip_hooks bypasses
# DatabaseCleaner/seed so this stays fast and isolated from the shared dev DB.
# (Sibling skip_hooks service specs tag type: :model — match that convention.)
RSpec.describe Discovery::GridSnap, type: :model, skip_hooks: true do
  GRID = described_class::GRID_SIZE_DEG

  it 'returns a two-element array of floats' do
    result = described_class.snap(51.503, -0.123)

    expect(result).to be_an(Array)
    expect(result.size).to eq(2)
    expect(result).to all(be_a(Float))
  end

  it 'is deterministic — the same input yields identical output' do
    expect(described_class.snap(51.503, -0.123)).to eq(described_class.snap(51.503, -0.123))
  end

  it 'maps two points in the same latitude cell to the same centroid' do
    # Both latitudes sit inside the [40.50, 40.51) cell; identical longitude keeps
    # the longitude step (hence cell_lng) identical, so the centroids must match.
    a = described_class.snap(40.502, -100.0)
    b = described_class.snap(40.503, -100.0)

    expect(a).to eq(b)
  end

  it 'maps two points in adjacent latitude cells to different centroids' do
    # 40.502 is in [40.50, 40.51); 40.512 is in the neighbouring [40.51, 40.52).
    a = described_class.snap(40.502, -100.0)
    b = described_class.snap(40.512, -100.0)

    expect(a).not_to eq(b)
  end

  it 'keeps one E-W cell at least ~1 km wide at 55N, measured from snap output (AC 15d / AC 3)' do
    # The whole reason GridSnap exists: the latitude-aware longitude step keeps a
    # cell's E-W metric width ≈1.1 km at any inhabited latitude, so a stored
    # centroid never pins a user closer than that. We derive the width purely from
    # snap's returned centroids (never from the impl's own step), so this is a real
    # invariant guard, not a tautology.
    #
    # 0.0 and 0.019 fall in ADJACENT longitude cells at 55N under the real,
    # latitude-aware step (~0.0174° ≈ 1.11 km wide). This assertion goes RED if the
    # longitude step is ever reverted to a fixed GRID_SIZE_DEG — at 55N that gives
    # ~0.64 km cells (0.019 then still lands in the adjacent 0.01° cell, so the
    # measured width collapses below the 1 km floor). Regression-verified: temporarily
    # forcing lon_step = GRID_SIZE_DEG makes this example fail.
    _, cell_lng_a = described_class.snap(55.0, 0.0)
    _, cell_lng_b = described_class.snap(55.0, 0.019)

    ew_km = (cell_lng_b - cell_lng_a).abs * Math.cos(55.0 * Math::PI / 180.0) * 111.32

    expect(ew_km).to be >= 1.0
  end

  it 'snaps longitude onto the plain 0.01° grid at the equator (cos 0 = 1)' do
    # At the equator cos(lat) ≈ 1, so the latitude-aware longitude step collapses to
    # GRID_SIZE_DEG. We consume snap's ACTUAL output and assert it lands on the plain
    # 0.01° grid centroid ((k * 0.01) + 0.005) — not by re-deriving 0.01 / cos(0).
    _, cell_lng = described_class.snap(0.0, 0.123)

    expected = (0.123 / GRID).floor * GRID + GRID / 2.0 # plain 0.01° grid centroid = 0.125
    expect(cell_lng).to eq(expected.round(6))
  end

  it 'groups different longitudes in the same high-latitude cell to one centroid (W2)' do
    # At 55N the longitude step widens to ~0.0174°, so 0.002 and 0.015 fall in the
    # SAME longitude cell → identical centroid. The latitude-fixed tests above never
    # exercise this same-band grouping (they hold longitude constant at -100.0).
    a = described_class.snap(55.0, 0.002)
    b = described_class.snap(55.0, 0.015)

    expect(a).to eq(b)
  end

  it 'separates adjacent high-latitude longitude cells (W2)' do
    # 0.002 is in longitude cell 0; 0.020 crosses into the neighbouring cell 1 at 55N.
    a = described_class.snap(55.0, 0.002)
    b = described_class.snap(55.0, 0.020)

    expect(a).not_to eq(b)
  end
end
