import json
import time
import requests

from config import API_BASE_URL, API_TOKEN


class ApiClient:
    def __init__(self):
        self.base_url = API_BASE_URL.rstrip("/")
        self.headers = {
            "authorization": API_TOKEN,
            "Content-Type": "application/json",
        }

    def get_tv_statistics(
        self,
        channel_ids,
        date_from,
        date_to,
        max_retries=6,
        retry_delay=10,
    ):
        with open("payloads/query18.json", "r", encoding="utf-8") as f:
            payload = json.load(f)

        payload["parameters"]["channel"] = [str(channel_id) for channel_id in channel_ids]
        payload["parameters"]["period"]["start"] = date_from
        payload["parameters"]["period"]["end"] = date_to

        url = f"{self.base_url}/api/queries/18/results"

        for attempt in range(1, max_retries + 1):
            print(f"Запрос API. Попытка {attempt}/{max_retries}")

            response = requests.post(
                url,
                headers=self.headers,
                json=payload,
                timeout=120,
            )

            print("HTTP:", response.status_code)

            if response.status_code != 200:
                print("Ответ API:")
                print(response.text)
                response.raise_for_status()

            data = response.json()

            if "job" not in data:
                print("Отчёт получен")
                return data

            print("Отчёт ещё строится")

            if attempt < max_retries:
                time.sleep(retry_delay)

        raise TimeoutError("Не удалось дождаться готовности отчёта")
        