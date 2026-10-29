"""Trusted bootstrap only; run once using a secure local environment or migration role."""
from __future__ import annotations

import os
import re
import uuid

from sqlalchemy import select

from .main import Base, DATABASE_URL, Institution, Role, SessionLocal, User, engine, hash_password


def required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Set {name} before running the trusted bootstrap.")
    return value


def main() -> None:
    school_name = required("SCHOOLNET_SCHOOL_NAME")
    slug = required("SCHOOLNET_SCHOOL_SLUG").lower()
    if not re.fullmatch(r"[a-z0-9-]{2,100}", slug):
        raise SystemExit("SCHOOLNET_SCHOOL_SLUG must use lowercase letters, digits, and hyphens.")
    admin_name = required("SCHOOLNET_ADMIN_NAME")
    admin_email = required("SCHOOLNET_ADMIN_EMAIL").lower()
    admin_password = required("SCHOOLNET_ADMIN_PASSWORD")
    if len(admin_password) < 12:
        raise SystemExit("Use an initial administrator password of at least 12 characters.")

    if DATABASE_URL.startswith("sqlite"):
        Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        school = db.scalar(select(Institution).where(Institution.slug == slug))
        if school is None:
            school = Institution(id=str(uuid.uuid4()), name=school_name, slug=slug)
            db.add(school)
            db.flush()
        existing = db.scalar(select(User).where(User.institution_id == school.id, User.email == admin_email))
        if existing:
            raise SystemExit("An account with that email already exists for this school; no changes made.")
        admin = User(id=str(uuid.uuid4()), institution_id=school.id, full_name=admin_name,
                     email=admin_email, role=Role.ADMIN.value, password_hash=hash_password(admin_password),
                     force_password_change=False, active=True)
        db.add(admin)
        db.commit()
        print(f"Provisioned administrator {admin_email} for school '{slug}' ({school.id}).")
    finally:
        db.close()


if __name__ == "__main__":
    main()
