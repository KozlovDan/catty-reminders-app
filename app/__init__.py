"""
This module builds shared parts for other modules.
"""

# --------------------------------------------------------------------------------
# Imports
# --------------------------------------------------------------------------------

import json
import os

from fastapi.templating import Jinja2Templates


# --------------------------------------------------------------------------------
# Read Configuration
# --------------------------------------------------------------------------------

with open('config.json') as config_json:
  config = json.load(config_json)
  users = config['users']
  db_path = os.getenv('DB_PATH', config.get('db_path', 'reminder_db.json'))
  storage_backend = os.getenv('STORAGE_BACKEND', config.get('storage_backend', 'tinydb')).lower()
  db_config = {
    'host': os.getenv('DB_HOST', os.getenv('MYSQL_HOST', config.get('db_config', {}).get('host', 'localhost'))),
    'port': int(os.getenv('DB_PORT', os.getenv('MYSQL_PORT', config.get('db_config', {}).get('port', 3306)))),
    'user': os.getenv('DB_USER', os.getenv('MYSQL_USER', config.get('db_config', {}).get('user', 'catty'))),
    'password': os.getenv('DB_PASSWORD', os.getenv('MYSQL_PASSWORD', config.get('db_config', {}).get('password', 'catty'))),
    'database': os.getenv('DB_NAME', os.getenv('MYSQL_DATABASE', config.get('db_config', {}).get('database', 'catty_reminders'))),
  }

DEPLOY_REF = os.getenv("DEPLOY_REF", "NA")

# --------------------------------------------------------------------------------
# Establish the Secret Key
# --------------------------------------------------------------------------------

secret_key = config['secret_key']


# --------------------------------------------------------------------------------
# Templates
# --------------------------------------------------------------------------------

templates = Jinja2Templates(directory="templates")
