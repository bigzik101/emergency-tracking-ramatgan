-- ============================================================
-- Emergency Tracking v4.0 — Supabase Schema
-- עיריית רמת גן | מערכת כוננות חירום
-- ============================================================

-- ── PROFILES (extends auth.users) ──────────────────────────
CREATE TABLE profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT NOT NULL,
  phone       TEXT UNIQUE NOT NULL,
  role        TEXT NOT NULL CHECK (role IN ('admin','commander','officer')),
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── OFFICERS ────────────────────────────────────────────────
CREATE TABLE officers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id    UUID REFERENCES profiles(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  phone         TEXT NOT NULL,
  is_on_duty    BOOLEAN DEFAULT false,
  duty_start    TIMESTAMPTZ,
  status        TEXT DEFAULT 'off_duty' CHECK (status IN ('off_duty','available','enroute','onsite','sos')),
  nav_mode      TEXT DEFAULT 'vehicle' CHECK (nav_mode IN ('vehicle','foot')),
  last_lat      DOUBLE PRECISION,
  last_lng      DOUBLE PRECISION,
  last_speed    DOUBLE PRECISION DEFAULT 0,
  last_seen     TIMESTAMPTZ,
  vehicle_parked_lat DOUBLE PRECISION,
  vehicle_parked_lng DOUBLE PRECISION,
  dispatch_count INTEGER DEFAULT 0,
  total_response_min DOUBLE PRECISION DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── INCIDENTS ───────────────────────────────────────────────
CREATE TABLE incidents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type          TEXT NOT NULL CHECK (type IN ('water','sewage')),
  title         TEXT NOT NULL,
  address       TEXT,
  lat           DOUBLE PRECISION NOT NULL,
  lng           DOUBLE PRECISION NOT NULL,
  description   TEXT,
  severity      INTEGER DEFAULT 2 CHECK (severity BETWEEN 1 AND 3),
  status        TEXT DEFAULT 'open' CHECK (status IN ('open','active','resolved')),
  is_flood      BOOLEAN DEFAULT false,
  opened_by     UUID REFERENCES profiles(id),
  closed_by     UUID REFERENCES profiles(id),
  opened_at     TIMESTAMPTZ DEFAULT NOW(),
  closed_at     TIMESTAMPTZ
);

-- ── DISPATCHES ──────────────────────────────────────────────
CREATE TABLE dispatches (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id         UUID REFERENCES incidents(id) ON DELETE CASCADE,
  officer_id          UUID REFERENCES officers(id),
  dispatched_by       UUID REFERENCES profiles(id),
  dispatched_at       TIMESTAMPTZ DEFAULT NOW(),
  arrived_at          TIMESTAMPTZ,
  treating_at         TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  nav_mode            TEXT DEFAULT 'vehicle',
  vehicle_parked_lat  DOUBLE PRECISION,
  vehicle_parked_lng  DOUBLE PRECISION,
  eta_minutes         DOUBLE PRECISION,
  distance_km         DOUBLE PRECISION,
  eta_method          TEXT DEFAULT 'aerial'
);

-- ── MAP ANNOTATIONS ─────────────────────────────────────────
CREATE TABLE map_annotations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN ('blocked_road','note','danger','water_source','sewage_point')),
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  label       TEXT NOT NULL,
  color       TEXT DEFAULT '#f97316',
  created_by  UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── LOCATION HISTORY ────────────────────────────────────────
CREATE TABLE location_history (
  id          BIGSERIAL PRIMARY KEY,
  officer_id  UUID REFERENCES officers(id) ON DELETE CASCADE,
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  speed       DOUBLE PRECISION DEFAULT 0,
  accuracy    DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── DUTY SCHEDULE ───────────────────────────────────────────
CREATE TABLE duty_schedule (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  officer_id  UUID REFERENCES officers(id) ON DELETE CASCADE,
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
  start_hour  INTEGER CHECK (start_hour BETWEEN 0 AND 23),
  end_hour    INTEGER CHECK (end_hour BETWEEN 1 AND 24),
  created_by  UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── EVENT LOG ───────────────────────────────────────────────
CREATE TABLE event_log (
  id          BIGSERIAL PRIMARY KEY,
  incident_id UUID REFERENCES incidents(id),
  officer_id  UUID REFERENCES officers(id),
  actor_id    UUID REFERENCES profiles(id),
  event_type  TEXT NOT NULL,
  description TEXT NOT NULL,
  metadata    JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── MEDIA FILES ─────────────────────────────────────────────
CREATE TABLE media_files (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  officer_id  UUID REFERENCES officers(id),
  file_name   TEXT NOT NULL,
  file_type   TEXT NOT NULL CHECK (file_type IN ('image','video')),
  file_data   TEXT NOT NULL,
  lat         DOUBLE PRECISION,
  lng         DOUBLE PRECISION,
  uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE officers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents        ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispatches       ENABLE ROW LEVEL SECURITY;
ALTER TABLE map_annotations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE duty_schedule    ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_log        ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_files      ENABLE ROW LEVEL SECURITY;

-- Role helper
CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT LANGUAGE sql SECURITY DEFINER AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION get_my_officer_id()
RETURNS UUID LANGUAGE sql SECURITY DEFINER AS $$
  SELECT id FROM officers WHERE profile_id = auth.uid();
$$;

-- PROFILES
CREATE POLICY "own profile" ON profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "admin/cmd see all" ON profiles FOR SELECT USING (get_my_role() IN ('admin','commander'));
CREATE POLICY "admin manages" ON profiles FOR ALL USING (get_my_role() = 'admin');

-- OFFICERS
CREATE POLICY "all see officers" ON officers FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "officer updates self" ON officers FOR UPDATE USING (profile_id = auth.uid());
CREATE POLICY "admin manages officers" ON officers FOR ALL USING (get_my_role() = 'admin');

-- INCIDENTS
CREATE POLICY "all see incidents" ON incidents FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "cmd opens incident" ON incidents FOR INSERT WITH CHECK (get_my_role() IN ('admin','commander'));
CREATE POLICY "cmd updates incident" ON incidents FOR UPDATE USING (get_my_role() IN ('admin','commander'));
CREATE POLICY "admin deletes incident" ON incidents FOR DELETE USING (get_my_role() = 'admin');

-- DISPATCHES
CREATE POLICY "all see dispatches" ON dispatches FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "cmd creates dispatch" ON dispatches FOR INSERT WITH CHECK (get_my_role() IN ('admin','commander'));
CREATE POLICY "officer/cmd updates dispatch" ON dispatches FOR UPDATE USING (
  officer_id = get_my_officer_id() OR get_my_role() IN ('admin','commander')
);

-- MAP ANNOTATIONS
CREATE POLICY "all see annotations" ON map_annotations FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "cmd manages annotations" ON map_annotations FOR ALL USING (get_my_role() IN ('admin','commander'));

-- LOCATION HISTORY
CREATE POLICY "cmd sees all locs" ON location_history FOR SELECT USING (get_my_role() IN ('admin','commander'));
CREATE POLICY "officer sees own locs" ON location_history FOR SELECT USING (officer_id = get_my_officer_id());
CREATE POLICY "officer inserts loc" ON location_history FOR INSERT WITH CHECK (officer_id = get_my_officer_id());

-- DUTY SCHEDULE
CREATE POLICY "all see schedule" ON duty_schedule FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "cmd manages schedule" ON duty_schedule FOR ALL USING (get_my_role() IN ('admin','commander'));

-- EVENT LOG
CREATE POLICY "cmd sees log" ON event_log FOR SELECT USING (get_my_role() IN ('admin','commander'));
CREATE POLICY "all insert log" ON event_log FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- MEDIA
CREATE POLICY "all see media" ON media_files FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "officer uploads" ON media_files FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "admin deletes media" ON media_files FOR DELETE USING (get_my_role() = 'admin');

-- ============================================================
-- REALTIME
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE officers;
ALTER PUBLICATION supabase_realtime ADD TABLE incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE dispatches;
ALTER PUBLICATION supabase_realtime ADD TABLE map_annotations;
ALTER PUBLICATION supabase_realtime ADD TABLE event_log;
