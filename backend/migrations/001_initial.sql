-- Initial SchoolNet schema for Neon PostgreSQL.
-- Provision with a migration/owner role. Application runtime must use a separate,
-- non-owner database role and must set app.current_institution per authenticated request.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS institutions (
  id varchar(36) PRIMARY KEY,
  name varchar(180) NOT NULL,
  slug varchar(100) NOT NULL UNIQUE,
  has_guidance_counseling boolean NOT NULL DEFAULT false,
  is_boarding_school boolean NOT NULL DEFAULT false,
  logo_url varchar(500),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS users (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  full_name varchar(180) NOT NULL,
  email varchar(320) NOT NULL,
  role varchar(24) NOT NULL CHECK (role IN ('ADMIN','TEACHER','STUDENT','COUNSELOR','COMMUNITY')),
  password_hash varchar(255) NOT NULL,
  force_password_change boolean NOT NULL DEFAULT true,
  teacher_stars double precision CHECK (teacher_stars IS NULL OR (teacher_stars >= 0 AND teacher_stars <= 5)),
  avatar_url varchar(500),
  active boolean NOT NULL DEFAULT true,
  CONSTRAINT uq_user_school_email UNIQUE(institution_id,email)
);
CREATE TABLE IF NOT EXISTS classes_and_sections (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  grade_level integer NOT NULL CHECK (grade_level BETWEEN 9 AND 12),
  section_name varchar(20) NOT NULL,
  head_teacher_id varchar(36) REFERENCES users(id),
  academic_year varchar(16) NOT NULL,
  CONSTRAINT uq_school_section_year UNIQUE(institution_id,grade_level,section_name,academic_year)
);
CREATE TABLE IF NOT EXISTS enrollments (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  student_id varchar(36) NOT NULL REFERENCES users(id),
  section_id varchar(36) NOT NULL REFERENCES classes_and_sections(id),
  academic_year varchar(16) NOT NULL,
  CONSTRAINT uq_student_year_enrollment UNIQUE(student_id,academic_year)
);
CREATE TABLE IF NOT EXISTS subjects (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  name varchar(120) NOT NULL
);
CREATE TABLE IF NOT EXISTS teaching_assignments (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  teacher_id varchar(36) NOT NULL REFERENCES users(id),
  section_id varchar(36) NOT NULL REFERENCES classes_and_sections(id),
  subject_id varchar(36) NOT NULL REFERENCES subjects(id)
);
CREATE TABLE IF NOT EXISTS marklists (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  section_id varchar(36) NOT NULL REFERENCES classes_and_sections(id),
  subject_id varchar(36) NOT NULL REFERENCES subjects(id),
  teacher_id varchar(36) NOT NULL REFERENCES users(id),
  title varchar(180) NOT NULL,
  max_points double precision NOT NULL CHECK (max_points > 0),
  term varchar(60) NOT NULL,
  academic_year varchar(16) NOT NULL,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS student_scores (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  marklist_id varchar(36) NOT NULL REFERENCES marklists(id) ON DELETE CASCADE,
  student_id varchar(36) NOT NULL REFERENCES users(id),
  earned_points double precision NOT NULL CHECK (earned_points >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_score_student_marklist UNIQUE(marklist_id,student_id)
);
CREATE TABLE IF NOT EXISTS messages_and_posts (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  sender_id varchar(36) NOT NULL REFERENCES users(id),
  scope varchar(16) NOT NULL CHECK (scope IN ('GLOBAL','GRADE','SECTION','DM')),
  grade_level integer,
  section_id varchar(36) REFERENCES classes_and_sections(id),
  recipient_id varchar(36) REFERENCES users(id),
  category varchar(40) NOT NULL DEFAULT 'POST',
  title varchar(180),
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS recovery_requests (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  user_email varchar(320) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS archive_vault (
  id varchar(36) PRIMARY KEY,
  institution_id varchar(36) NOT NULL REFERENCES institutions(id),
  academic_year varchar(16) NOT NULL,
  snapshot_json text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_users_institution_id ON users(institution_id);
CREATE INDEX IF NOT EXISTS ix_users_email ON users(email);
CREATE INDEX IF NOT EXISTS ix_classes_and_sections_institution_id ON classes_and_sections(institution_id);
CREATE INDEX IF NOT EXISTS ix_enrollments_institution_id ON enrollments(institution_id);
CREATE INDEX IF NOT EXISTS ix_enrollments_student_id ON enrollments(student_id);
CREATE INDEX IF NOT EXISTS ix_enrollments_section_id ON enrollments(section_id);
CREATE INDEX IF NOT EXISTS ix_marklists_institution_id ON marklists(institution_id);
CREATE INDEX IF NOT EXISTS ix_marklists_section_id ON marklists(section_id);
CREATE INDEX IF NOT EXISTS ix_student_scores_institution_id ON student_scores(institution_id);
CREATE INDEX IF NOT EXISTS ix_student_scores_marklist_id ON student_scores(marklist_id);
CREATE INDEX IF NOT EXISTS ix_student_scores_student_id ON student_scores(student_id);
CREATE INDEX IF NOT EXISTS ix_messages_and_posts_institution_id ON messages_and_posts(institution_id);
CREATE INDEX IF NOT EXISTS ix_messages_and_posts_created_at ON messages_and_posts(created_at);
CREATE INDEX IF NOT EXISTS ix_recovery_requests_institution_id ON recovery_requests(institution_id);
CREATE INDEX IF NOT EXISTS ix_archive_vault_institution_id ON archive_vault(institution_id);
