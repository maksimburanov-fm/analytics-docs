import os
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
API_TOKEN = os.getenv("API_TOKEN", "")
API_BASE_URL = os.getenv("API_BASE_URL", "")

ALLOWED_USERS_RAW = os.getenv("ALLOWED_USERS", "")

ALLOWED_USERS = {
    int(user_id.strip())
    for user_id in ALLOWED_USERS_RAW.split(",")
    if user_id.strip().isdigit()
}

CHANNELS_SHEET_URL = os.getenv("CHANNELS_SHEET_URL", "")
