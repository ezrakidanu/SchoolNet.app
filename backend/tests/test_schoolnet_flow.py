from __future__ import annotations

import os
import sys
from pathlib import Path

# This test module uses an isolated local database and a test-only signing secret.
_test_db = Path('/tmp') / f'schoolnet_pytest_{os.getpid()}.db'
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ['DATABASE_URL'] = f'sqlite:///{_test_db}'
os.environ['JWT_SECRET'] = 'schoolnet-test-only-signing-secret'

from fastapi.testclient import TestClient

from app.main import Institution, Role, SessionLocal, User, app, hash_password


def test_schoolnet_role_and_privacy_flow() -> None:
    with TestClient(app) as client:
        db = SessionLocal()
        school = Institution(name='Test School', slug='test-school', has_guidance_counseling=True)
        db.add(school)
        db.flush()
        db.add(User(
            institution_id=school.id,
            full_name='Admin User',
            email='admin@test.school',
            role=Role.ADMIN.value,
            password_hash=hash_password('Admin-Test-Password-123'),
            force_password_change=False,
        ))
        db.commit()
        db.close()

        def login(email: str, password: str, role: str) -> dict:
            response = client.post('/auth/login', json={
                'institution_slug': 'test-school',
                'email': email,
                'password': password,
                'role': role,
            })
            assert response.status_code == 200, response.text
            return response.json()

        admin = login('admin@test.school', 'Admin-Test-Password-123', 'ADMIN')
        admin_headers = {'Authorization': f"Bearer {admin['access_token']}"}

        teacher_result = client.post('/admin/users', headers=admin_headers, json={
            'full_name': 'Teacher One', 'email': 'teacher@test.school', 'role': 'TEACHER'
        })
        assert teacher_result.status_code == 201, teacher_result.text
        teacher = teacher_result.json()
        section_result = client.post('/admin/sections', headers=admin_headers, json={
            'grade_level': 9,
            'section_name': 'A',
            'academic_year': '2026-2027',
            'head_teacher_id': teacher['user']['id'],
        })
        assert section_result.status_code == 201, section_result.text
        section_id = section_result.json()['id']

        student_result = client.post('/admin/users', headers=admin_headers, json={
            'full_name': 'Student One',
            'email': 'student@test.school',
            'role': 'STUDENT',
            'section_id': section_id,
        })
        other_student_result = client.post('/admin/users', headers=admin_headers, json={
            'full_name': 'Student Two',
            'email': 'student2@test.school',
            'role': 'STUDENT',
            'section_id': section_id,
        })
        assert student_result.status_code == other_student_result.status_code == 201
        student = student_result.json()

        subject_result = client.post('/admin/subjects', headers=admin_headers, json={'name': 'Math'})
        assert subject_result.status_code == 201, subject_result.text
        assignment_result = client.post('/admin/assignments', headers=admin_headers, json={
            'teacher_id': teacher['user']['id'],
            'section_id': section_id,
            'subject_id': subject_result.json()['id'],
        })
        assert assignment_result.status_code == 201, assignment_result.text

        teacher_login = login('teacher@test.school', teacher['temporary_pin'], 'TEACHER')
        assert teacher_login['user']['force_password_change'] is True
        teacher_headers = {'Authorization': f"Bearer {teacher_login['access_token']}"}
        changed = client.post('/auth/change-password', headers=teacher_headers, json={
            'new_password': 'Teacher-Test-Password-123'
        })
        assert changed.status_code == 200, changed.text
        teacher_login = login('teacher@test.school', 'Teacher-Test-Password-123', 'TEACHER')
        teacher_headers = {'Authorization': f"Bearer {teacher_login['access_token']}"}

        marklist_result = client.post('/marklists', headers=teacher_headers, json={
            'section_id': section_id,
            'subject_id': subject_result.json()['id'],
            'title': 'Semester Exam',
            'max_points': 100,
            'term': 'Semester I',
            'academic_year': '2026-2027',
        })
        assert marklist_result.status_code == 201, marklist_result.text
        score_result = client.put(
            f"/marklists/{marklist_result.json()['id']}/scores",
            headers=teacher_headers,
            json={'scores': {student['user']['id']: 92}, 'publish': True},
        )
        assert score_result.status_code == 200, score_result.text

        student_login = login('student@test.school', student['temporary_pin'], 'STUDENT')
        student_headers = {'Authorization': f"Bearer {student_login['access_token']}"}
        assert student_login['user']['force_password_change'] is True
        assert client.post('/auth/change-password', headers=student_headers, json={
            'new_password': 'Student-Test-Password-123'
        }).status_code == 200
        student_login = login('student@test.school', 'Student-Test-Password-123', 'STUDENT')
        student_headers = {'Authorization': f"Bearer {student_login['access_token']}"}
        performance = client.get('/performance/me', headers=student_headers)
        assert performance.status_code == 200
        assert performance.json()['calculated_stars'] == 9.2

        assert client.post('/posts', headers=admin_headers, json={
            'scope': 'GLOBAL', 'title': 'Welcome', 'content': 'School update'
        }).status_code == 201
        assert client.post('/posts', headers=teacher_headers, json={
            'scope': 'GRADE', 'grade_level': 9, 'title': 'Grade 9', 'content': 'Grade update'
        }).status_code == 201
        assert len(client.get('/posts', headers=student_headers).json()) == 2
        assert client.post('/messages/student/' + student['user']['id'],
                           headers=student_headers,
                           json={'content': 'forbidden', 'title': 'Unauthorized'}).status_code == 403
        assert client.get(
            f"/exports/students/{other_student_result.json()['user']['id']}.docx",
            headers=student_headers,
        ).status_code == 403
        own_report = client.get(
            f"/exports/students/{student['user']['id']}.docx", headers=student_headers
        )
        assert own_report.status_code == 200

        community_result = client.post('/auth/register-community', json={
            'institution_slug': 'test-school',
            'full_name': 'Community Person',
            'email': 'community@example.net',
            'password': 'Community-Test-Password-123',
        })
        assert community_result.status_code == 201, community_result.text
        community_headers = {
            'Authorization': f"Bearer {community_result.json()['access_token']}"
        }
        inquiry = client.post('/messages/community-inquiry', headers=community_headers, json={
            'content': 'Please contact me', 'category': 'INQUIRY'
        })
        assert inquiry.status_code == 201, inquiry.text
        inbox = client.get('/admin/inbox', headers=admin_headers)
        assert inbox.status_code == 200
        assert len(inbox.json()) == 1
