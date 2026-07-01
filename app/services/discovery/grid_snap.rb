module Discovery
  # Privacy grid: snaps a raw (lat, lng) to the centroid of a fixed-size grid
  # cell so a user's exact position is never stored or exposed — only the cell
  # they fall in. Shared by the write path (PATCH /location) and the read path
  # (GET /nearby) so both quantise with the identical knob.
  #
  # GRID_SIZE_DEG is the single privacy knob: the cell height in degrees of
  # latitude. Every caller imports it from here — never duplicate the constant.
  # The longitude step widens by 1/cos(lat) so cells stay roughly square in
  # metres as latitude increases, floored at 85 deg (COS_FLOOR) to keep the step
  # finite near the poles.
  class GridSnap
    GRID_SIZE_DEG = 0.01
    COS_FLOOR     = Math.cos(85.0 * Math::PI / 180.0)

    def self.snap(lat, lng)
      cell_lat = (lat.to_f / GRID_SIZE_DEG).floor * GRID_SIZE_DEG + GRID_SIZE_DEG / 2.0
      lon_step = GRID_SIZE_DEG / [Math.cos(cell_lat * Math::PI / 180.0), COS_FLOOR].max
      cell_lng = (lng.to_f / lon_step).floor * lon_step + lon_step / 2.0
      [cell_lat.round(8), cell_lng.round(8)]
    end
  end
end
