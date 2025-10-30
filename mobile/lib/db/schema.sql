PRAGMA foreign_keys = ON;

-- USERS
CREATE TABLE IF NOT EXISTS users (
  uid TEXT PRIMARY KEY,
  email TEXT,
  display_name TEXT,
  role TEXT,
  current_plan TEXT,
  plan_updated_at TEXT,
  created_at TEXT,
  updated_at TEXT,
  deleted INTEGER,
  deleted_at TEXT
);

-- USER META
CREATE TABLE IF NOT EXISTS user_meta (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  month_key TEXT,
  monthly_generated_count INTEGER,
  plan TEXT,
  plan_start_date TEXT,
  plan_end_date TEXT,
  reset_date TEXT,
  updated_at TEXT,
  deleted INTEGER,
  deleted_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(uid) ON DELETE CASCADE
);

-- PLANS
CREATE TABLE IF NOT EXISTS plans (
  plan_id TEXT PRIMARY KEY,
  name TEXT,
  monthly_quiz_limit INTEGER,
  price_usd REAL,
  description TEXT,
  created_at TEXT,
  updated_at TEXT
);

-- USER QUIZZES (local only)
CREATE TABLE IF NOT EXISTS user_quizzes (
  quiz_id TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  difficulty TEXT,
  owner_id TEXT NOT NULL,
  source TEXT,
  deleted INTEGER,
  deleted_at TEXT,
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (owner_id) REFERENCES users(uid) ON DELETE CASCADE
);

-- USER QUIZ TAGS
CREATE TABLE IF NOT EXISTS user_quiz_tags (
  id TEXT PRIMARY KEY,
  quiz_id TEXT NOT NULL,
  tag_name TEXT NOT NULL,
  FOREIGN KEY (quiz_id) REFERENCES user_quizzes(quiz_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_user_quiz_tag_name ON user_quiz_tags(tag_name);

-- USER QUESTIONS (local only)
-- Keep both "order" (preferred) and legacy "index" for compatibility.
CREATE TABLE IF NOT EXISTS user_questions (
  question_id TEXT PRIMARY KEY,
  quiz_id TEXT NOT NULL,
  "order" INTEGER,
  "index" INTEGER,
  text TEXT,
  options TEXT,
  correct_index INTEGER,
  image_url TEXT,
  deleted INTEGER,
  deleted_at TEXT,
  created_at TEXT,
  updated_at TEXT,
  FOREIGN KEY (quiz_id) REFERENCES user_quizzes(quiz_id) ON DELETE CASCADE
);

-- CACHE ADMIN QUIZZES (mirror of Firestore for offline)
CREATE TABLE IF NOT EXISTS cache_admin_quizzes (
  quiz_id TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  difficulty TEXT,
  tags TEXT,
  is_admin_quiz INTEGER,
  available_to_all INTEGER,
  is_approved INTEGER,
  deleted INTEGER,
  deleted_at TEXT,
  created_at TEXT,
  updated_at TEXT
);

-- CACHE ADMIN QUESTIONS
-- Keep both "order" (preferred) and legacy "index" for compatibility.
CREATE TABLE IF NOT EXISTS cache_admin_questions (
  question_id TEXT PRIMARY KEY,
  quiz_id TEXT,
  "order" INTEGER,
  "index" INTEGER,
  text TEXT,
  options TEXT,
  correct_index INTEGER,
  image_url TEXT,
  created_at TEXT,
  updated_at TEXT
);

-- ATTEMPTS (runtime shape)
CREATE TABLE IF NOT EXISTS attempts (
  attempt_id   TEXT PRIMARY KEY,
  quiz_id      TEXT NOT NULL,
  quiz_title   TEXT NOT NULL,
  difficulty   TEXT NOT NULL,
  started_at   TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  score        INTEGER NOT NULL,
  num_correct  INTEGER NOT NULL,
  num_total    INTEGER NOT NULL
);

-- ATTEMPT ANSWERS (runtime shape)
CREATE TABLE IF NOT EXISTS attempt_answers (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  attempt_id     TEXT NOT NULL,
  question_id    TEXT NOT NULL,
  q_index        INTEGER NOT NULL,
  selected_index INTEGER NOT NULL,
  correct_index  INTEGER NOT NULL,
  is_correct     INTEGER NOT NULL,
  elapsed_ms     INTEGER NULL,
  FOREIGN KEY (attempt_id) REFERENCES attempts(attempt_id) ON DELETE CASCADE
);

-- SYNC QUEUE (optional; future)
CREATE TABLE IF NOT EXISTS sync_queue (
  id TEXT PRIMARY KEY,
  entity_type TEXT,
  entity_id TEXT,
  operation TEXT,
  payload_json TEXT,
  retry_count INTEGER,
  last_error TEXT,
  created_at TEXT,
  updated_at TEXT
);
