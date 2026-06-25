import pandas as pd

from config import CHANNELS_SHEET_URL


def get_channel_ids_by_category(category: str) -> list[int]:
    if not CHANNELS_SHEET_URL:
        raise ValueError("Не задан CHANNELS_SHEET_URL в .env")

    df = pd.read_csv(CHANNELS_SHEET_URL)

    df["category"] = df["category"].astype(str).str.lower()

    filtered = df[
        df["category"] == category.lower()
    ]

    return filtered["channel_id"].astype(str).tolist()