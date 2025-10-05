#!/usr/bin/env python3
import sqlite3
import bcrypt
import sys
import os

if len(sys.argv) != 2:
    sys.exit(1)

if not os.path.exists('/var/lib/private/n8n/.n8n/database.sqlite'):
    sys.exit(1)

try:
    conn = sqlite3.connect('/var/lib/private/n8n/.n8n/database.sqlite')
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM user WHERE email = ?", ('moyeodiase@gmail.com',))
    if cursor.fetchone()[0] > 0:
        sys.exit(0)

    hashed = bcrypt.hashpw(sys.argv[1].encode('utf-8'), bcrypt.gensalt(rounds=10)).decode('utf-8')

    cursor.execute("""
        INSERT INTO user (id, email, firstName, lastName, password, personalizationAnswers, role, settings)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, ('1', 'moyeodiase@gmail.com', 'Moye', 'Odiase', hashed, None, 'global:owner', '{}'))

    cursor.execute("""
        INSERT OR REPLACE INTO settings (key, value, loadOnStartup)
        VALUES (?, ?, ?)
    """, ('userManagement.isInstanceOwnerSetUp', 'true', 1))

    conn.commit()
except:
    sys.exit(1)
finally:
    if 'conn' in locals():
        conn.close()