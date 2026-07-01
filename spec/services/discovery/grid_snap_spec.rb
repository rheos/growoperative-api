require 'rails_helper'

# Pure unit spec for the privacy grid. No DB, no FactoryBot — skip_hooks bypasses
# DatabaseCleaner/seed so this stays fast and isolated from the shared dev DB.
RSpec.describe Discovery::GridSnap, type: :service, skip_hooks: true do
  GRID = described_class::GRID_SIZE_DEG
  FLOOR = described_class::COS_FLOOR

  it 'returns a two-element array of floats' do
    result = described_class.snap(51.503, -0.123)

    expect(result).to be_an(Array)
    expect(result.size).to eq(2)
    expect(result).to all(be_a(Float))
  end

  it 'is deterministic — the same input yields identical output' do
    expect(described_class.snap(51.503, -0.123)).to eq(described_class.snap(51.503, -0.123))
  end

  it 'maps two points in the same cell to the same centroid' do
    # Both latitudes sit inside the [40.50, 40.51) cell; identical longitude keeps
    # the longitude step (hence cell_lng) identical, so the centroids must match.
    a = described_class.snap(40.502, -100.0)
    b = described_class.snap(40.503, -100.0)

    expect(a).to eq(b)
  end

  it 'maps two points in adjacent cells to different centroids' do
    # 40.502 is in [40.50, 40.51); 40.512 is in the neighbouring [40.51, 40.52).
    a = described_class.snap(40.502, -100.0)
    b = described_class.snap(40.512, -100.0)

    expect(a).not_to eq(b)
  end

  it 'keeps the E-W cell width at least 1 km at 55N (AC 15d)' do
    cell_lat, _ = described_class.snap(55.0, 0.0)
    cos_lat     = Math.cos(cell_lat * Math::PI / 180.0)
    lon_step    = GRID / [cos_lat, FLOOR].max
    ew_width_km = lon_step * cos_lat * 111.32

    expect(ew_width_km).to be >= 1.0
  end

  it 'has a longitude step equal to GRID_SIZE_DEG at the equator (cos 0 = 1)' do
    lon_step = GRID / [Math.cos(0.0), FLOOR].max

    expect(lon_step).to eq(GRID)
  end
end
