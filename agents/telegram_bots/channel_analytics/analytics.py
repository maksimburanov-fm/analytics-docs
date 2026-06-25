from api_client import ApiClient
from date_utils import get_period
from channel_service import get_channel_ids_by_category


class AnalyticsService:
    def __init__(self):
        self.api = ApiClient()

    def sport_yesterday(self):
        return self.tv_report("yesterday")
    
    def tv_report(self, period_key: str = "yesterday", category: str = "sport"):
        date_from, date_to, period_name = get_period(period_key)

        channel_ids = get_channel_ids_by_category(category)
        
        result = self.api.get_tv_statistics(
            channel_ids= channel_ids,
            date_from=date_from,
            date_to=date_to,
        )
        rows = result["query_result"]["data"]["rows"]

        if not rows:
            return f"📺 ТВ-смотрение: {category}\n\nПериод: {period_name}\nДанных нет."

        total_sessions = sum(int(row.get("session_c", 0) or 0) for row in rows)
        total_users_sum = sum(int(row.get("user_c", 0) or 0) for row in rows)
        total_view_time_h = sum(float(row.get("view_time_h", 0) or 0) for row in rows)

        top_rows = sorted(
            rows,
            key=lambda row: int(row.get("user_c", 0) or 0),
            reverse=True,
        )[:5]

        top_text = "\n".join(
            f"{i + 1}. {row.get('channel_name')} — "
            f"{int(row.get('user_c', 0) or 0):,} пользователей, "
            f"{int(row.get('session_c', 0) or 0):,} сессий"
            for i, row in enumerate(top_rows)
        ).replace(",", " ")

        return (
            f"📺 ТВ-смотрение: спорт\n\n"
            f"Период: {period_name} ({date_from} — {date_to})\n\n"
            f"Сессий: {total_sessions:,}\n"
            f"Пользователей по каналам суммарно: {total_users_sum:,}\n"
            f"Время просмотра: {total_view_time_h:,.0f} ч\n\n"
            f"Топ каналов по пользователям:\n"
            f"{top_text}"
        ).replace(",", " ")

